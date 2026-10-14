-- Sim engine: ports simulation/loop.py `_tick`, simulation/strategy.py MLStrategy and
-- simulation/day_script.py beats. Driven by api.sim_tick, which this file REDEFINES —
-- 02_clock.sql's clock-only version is superseded here (files apply in sorted order).
-- Python drove this from an asyncio loop at TICK_VIRTUAL_MINUTES=1; Path C steps the
-- clock in large jumps instead, so one tick may span many virtual minutes.

-- Sim run state the engine needs beyond the clock: when the day started (for the
-- monotonic dispatch-minute reference) and which scripted beats already fired.
alter table api.sim_state add column if not exists sim_start   timestamptz;
alter table api.sim_state add column if not exists fired_beats integer[] not null default '{}';

-- "HH:MM" -> minutes since midnight; 0 when absent/unparseable (strategy.py:_slot_minutes).
create or replace function api.slot_minutes(p_time text)
returns integer language sql immutable as $$
	select case
		when p_time is null or p_time !~ '^[0-9]{1,2}:[0-9]{2}' then 0
		else split_part(p_time, ':', 1)::int * 60 + split_part(p_time, ':', 2)::int
	end;
$$;

-- Tech is dispatchable only inside their shift and outside the scheduled break/lunch.
-- Breaks stagger by id parity so coverage stays continuous (strategy.py:_on_shift).
create or replace function api.on_shift(p_tech_id integer, p_now_minutes integer)
returns boolean language plpgsql stable as $fn$
declare
	t           technicians%rowtype;
	start_min   integer;
	end_min     integer;
	even        boolean;
	break_start integer;
	lunch_start integer;
begin
	select * into t from technicians where id = p_tech_id;
	if not found then return false; end if;
	if nullif(t.shift_start, '') is null or nullif(t.shift_end, '') is null then
		return true;
	end if;

	start_min := api.slot_minutes(t.shift_start);
	end_min := api.slot_minutes(t.shift_end);
	if not (p_now_minutes >= start_min and p_now_minutes < end_min) then
		return false;
	end if;

	even := (coalesce(t.id, 0) % 2) = 0;
	break_start := case when even then 10 * 60 + 30 else 10 * 60 + 45 end;
	if p_now_minutes >= break_start and p_now_minutes < break_start + 15 then
		return false;
	end if;
	lunch_start := case when even then 12 * 60 else 12 * 60 + 30 end;
	if p_now_minutes >= lunch_start and p_now_minutes < lunch_start + 30 then
		return false;
	end if;

	return true;
end;
$fn$;

-- MLStrategy.tick — scores each (job, tech) pair by predicted completion:
-- travel + what_if_duration. Two-pass: prefer techs who can still ARRIVE inside the
-- customer window, else fall back to the best available so jobs don't sit PENDING.
-- A tech that wins a job leaves the pool for the rest of this tick.
-- Python's min() keeps the first of equal scores in list order; techs are ordered by id
-- here so ties resolve deterministically.
create or replace function api.ml_assign(p_now timestamptz, p_sim_start timestamptz)
returns integer language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	job_rec    record;
	tech_rec   record;
	now_min    integer;
	day_start  timestamptz;
	travel     integer;
	predicted  integer;
	score      integer;
	best_tech  integer;
	best_score integer;
	best_travel integer;
	best_dist  double precision;
	fits       boolean;
	slot_end   integer;
	dist       double precision;
	taken      integer[] := '{}';
	assigned   integer := 0;
begin
	now_min := 8 * 60 + (extract(epoch from (p_now - p_sim_start)) / 60)::int;
	day_start := date_trunc('day', p_sim_start);

	for job_rec in
		select * from jobs
		where status = 'PENDING'
			and scheduled_date >= day_start and scheduled_date < day_start + interval '1 day'
			and api.slot_minutes(time_slot_start) <= now_min
		order by priority, id
	loop
		best_tech := null; best_score := null; best_travel := null; best_dist := null;
		slot_end := api.slot_minutes(job_rec.time_slot_end);

		-- pass 1 = arrives in window, pass 2 = any qualified tech
		for fits in select unnest(array[true, false]) loop
			for tech_rec in
				select t.* from technicians t
				where t.is_active and t.status = 'AVAILABLE'
					and not (t.id = any (taken))
					and not exists (
						select 1 from assignments a join jobs jj on jj.id = a.job_id
						where a.technician_id = t.id and jj.status in ('ASSIGNED', 'IN_PROGRESS'))
					and api.on_shift(t.id, now_min)
				order by t.id
			loop
				if not api.can_do(job_rec.id, tech_rec.id) then
					continue;
				end if;
				dist := api.haversine(
					coalesce(tech_rec.current_latitude, tech_rec.home_latitude),
					coalesce(tech_rec.current_longitude, tech_rec.home_longitude),
					job_rec.latitude, job_rec.longitude);
				travel := api.travel_time(dist);
				predicted := api.what_if_duration(job_rec.id, tech_rec.id);
				score := travel + predicted;

				-- The tech must be able to finish before their shift ends; priority-1 work
				-- may run into overtime rather than wait for tomorrow.
				if job_rec.priority <> 1 and api.slot_minutes(tech_rec.shift_end) <> 0
						and now_min + travel + predicted > api.slot_minutes(tech_rec.shift_end) then
					continue;
				end if;

				-- pass 1 skips techs that cannot arrive before the window closes
				if fits and slot_end <> 0 and now_min + travel > slot_end then
					continue;
				end if;

				if best_score is null or score < best_score then
					best_score := score; best_tech := tech_rec.id;
					best_travel := travel; best_dist := dist;
				end if;
			end loop;
			exit when best_tech is not null;
		end loop;

		if best_tech is null then
			continue;
		end if;

		insert into assignments (job_id, technician_id, sequence, estimated_distance,
			estimated_travel_time, actual_duration_minutes, estimated_arrival,
			assigned_at, created_at, updated_at)
		values (job_rec.id, best_tech, null, best_dist, best_travel,
			api.sample_duration(job_rec.id, best_tech),
			p_now + make_interval(mins => best_travel), now(), now(), now());

		update jobs set status = 'ASSIGNED', updated_at = now() where id = job_rec.id;
		update technicians set status = 'EN_ROUTE', updated_at = now()
		where id = best_tech and status = 'AVAILABLE';
		taken := taken || best_tech;
		assigned := assigned + 1;
	end loop;

	return assigned;
end;
$fn$;

-- day_script.py beats. Offsets are virtual minutes after sim start; each fires once,
-- tracked in sim_state.fired_beats (Python used a module-global set, cleared on start).
create or replace function api.day_beats(p_now timestamptz, p_sim_start timestamptz)
returns integer language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	elapsed integer;
	fired   integer[] ;
	count_  integer := 0;
begin
	elapsed := (extract(epoch from (p_now - p_sim_start)) / 60)::int;
	select fired_beats into fired from api.sim_state limit 1;

	-- 10:47 — VIP emergency drops into the pending queue
	if elapsed >= 167 and not (167 = any (fired)) then
		insert into jobs (job_number, job_type, status, customer_name, service_address,
			service_city, service_zip, latitude, longitude, required_skills, route_criteria,
			priority, scheduled_date, estimated_duration, description, special_instructions,
			created_at, updated_at)
		values ('VIP-EMERGENCY-001', 'SERVICE_CHANGE', 'PENDING', 'Apollo Theater — EMERGENCY',
			'253 W 125th St', 'New York', '10027', 40.8100, -73.9500,
			'["service_change", "install"]'::jsonb, 'MN-HARLEM', 1, p_now, 120,
			'Main console failed mid-load-in — show in 3 hours',
			'VIP EMERGENCY — drop everything', now(), now());
		fired := fired || 167;
		count_ := count_ + 1;
	end if;

	-- 12:00 — afternoon surge releases the held drip jobs
	if elapsed >= 240 and not (240 = any (fired)) then
		update jobs set status = 'PENDING', updated_at = now()
		where status = 'ON_HOLD' and notes like '%DRIP:AFTERNOON%';
		fired := fired || 240;
		count_ := count_ + 1;
	end if;

	if count_ > 0 then
		update api.sim_state set fired_beats = fired;
	end if;
	return count_;
end;
$fn$;

-- loop.py `_tick` — the state machine, in its original order.
-- Overrun warnings (steps 4's yellow/red events) are NOT ported: they only ever emitted
-- websocket events, and Path C dropped the socket. They changed no state.
create or replace function api.dispatch_tick(p_now timestamptz, p_sim_start timestamptz)
returns json language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	tech_rec     record;
	a_rec        record;
	next_a       record;
	slot_dt      timestamptz;
	depart_dt    timestamptz;
	arrival_dt   timestamptz;
	now_min      integer;
	day_start    timestamptz;
	started      integer := 0;
	completed    integer := 0;
	off_duty     integer := 0;
	assigned     integer := 0;
	beats        integer := 0;
	active_today integer;
	past_shift   boolean;
	day_complete boolean := false;
begin
	now_min := 8 * 60 + (extract(epoch from (p_now - p_sim_start)) / 60)::int;
	day_start := date_trunc('day', p_sim_start);

	-- 1. Stamp estimated_arrival, one job per tech per tick. A tech is ready for the next
	-- job only when none of their ASSIGNED jobs already has an arrival pending, so the
	-- day's pre-routed queue plays out earliest-slot-first instead of all at once.
	for tech_rec in
		select distinct t.* from technicians t
		join assignments a on a.technician_id = t.id
		join jobs j on j.id = a.job_id
		where t.status in ('AVAILABLE', 'EN_ROUTE')
			and j.status = 'ASSIGNED' and a.estimated_arrival is null
		order by t.id
	loop
		if exists (
			select 1 from assignments a join jobs j on j.id = a.job_id
			where a.technician_id = tech_rec.id and j.status = 'ASSIGNED'
				and a.estimated_arrival is not null
		) then
			continue;
		end if;

		select a.id, a.estimated_travel_time, j.time_slot_start into next_a
		from assignments a join jobs j on j.id = a.job_id
		where a.technician_id = tech_rec.id and j.status = 'ASSIGNED'
			and a.estimated_arrival is null
		order by j.time_slot_start nulls first, j.id
		limit 1;
		if not found then
			continue;
		end if;

		-- Honour the customer window: idle at base until slot_start - travel.
		if nullif(next_a.time_slot_start, '') is not null then
			slot_dt := date_trunc('day', p_now)
				+ make_interval(mins => api.slot_minutes(next_a.time_slot_start));
			depart_dt := slot_dt - make_interval(mins => coalesce(next_a.estimated_travel_time, 0));
			if p_now < depart_dt then
				continue;
			end if;
			arrival_dt := greatest(p_now + make_interval(mins => coalesce(next_a.estimated_travel_time, 0)), slot_dt);
		else
			arrival_dt := p_now + make_interval(mins => coalesce(next_a.estimated_travel_time, 0));
		end if;

		update assignments set estimated_arrival = arrival_dt, updated_at = now()
		where id = next_a.id;
		update technicians set status = 'EN_ROUTE', updated_at = now()
		where id = tech_rec.id and status = 'AVAILABLE';
	end loop;

	-- 2. ASSIGNED -> IN_PROGRESS once the arrival time passes
	for a_rec in
		select a.id, a.job_id, a.technician_id from assignments a
		join jobs j on j.id = a.job_id
		where j.status = 'ASSIGNED' and a.estimated_arrival <= p_now
	loop
		update jobs set status = 'IN_PROGRESS', started_at = p_now, updated_at = now()
		where id = a_rec.job_id;
		update technicians set status = 'ON_JOB', updated_at = now() where id = a_rec.technician_id;
		started := started + 1;
	end loop;

	-- 3. IN_PROGRESS -> COMPLETED once the sampled duration has elapsed
	for a_rec in
		select a.id, a.job_id, a.technician_id,
			coalesce(a.actual_duration_minutes, j.estimated_duration) as actual,
			j.started_at
		from assignments a join jobs j on j.id = a.job_id
		where j.status = 'IN_PROGRESS' and j.started_at is not null
	loop
		if extract(epoch from (p_now - a_rec.started_at)) / 60 >= a_rec.actual then
			update jobs set status = 'COMPLETED', completed_at = p_now, updated_at = now()
			where id = a_rec.job_id;
			update assignments set actual_completion = p_now, updated_at = now() where id = a_rec.id;
			update technicians set status = 'AVAILABLE', updated_at = now() where id = a_rec.technician_id;
			completed := completed + 1;
		end if;
	end loop;

	-- 3.5 Shift end -> OFF_DUTY (only from AVAILABLE, as in Python)
	update technicians set status = 'OFF_DUTY', updated_at = now()
	where is_active and status = 'AVAILABLE'
		and nullif(shift_end, '') is not null
		and api.slot_minutes(shift_end) <> 0
		and now_min >= api.slot_minutes(shift_end);
	get diagnostics off_duty = row_count;

	-- 4. Scripted beats
	beats := api.day_beats(p_now, p_sim_start);

	-- 5. Strategy assigns whatever is now eligible
	assigned := api.ml_assign(p_now, p_sim_start);

	-- 6. Auto-stop. At 18:00 work that has not started is cancelled, but a tech already on
	-- a job finishes it, so the clock runs until nothing is in progress.
	past_shift := extract(hour from p_now) >= 18;
	if past_shift then
		update jobs set status = 'CANCELLED', updated_at = now()
		where status in ('PENDING', 'ASSIGNED')
			and scheduled_date >= day_start and scheduled_date < day_start + interval '1 day';
	end if;
	select count(*) into active_today from jobs
	where status in ('PENDING', 'ASSIGNED', 'IN_PROGRESS')
		and scheduled_date >= day_start and scheduled_date < day_start + interval '1 day';

	if active_today = 0 then
		day_complete := true;
		-- Pause rather than stop so the UI keeps showing the final virtual time.
		update api.sim_state set is_paused = true;
	end if;

	return json_build_object('started', started, 'completed', completed, 'off_duty', off_duty,
		'assigned', assigned, 'beats', beats, 'day_complete', day_complete);
end;
$fn$;

-- Supersedes 02_clock.sql's clock-only sim_tick: advance the virtual clock, then run the
-- engine. Still scheduler-agnostic — pg_cron/external cron/sidecar just call it.
--
-- Python's loop ticked once per VIRTUAL minute (TICK_VIRTUAL_MINUTES=1). Path C's clock
-- jumps in large steps, so a single call must walk the interval in small increments and
-- run the state machine at each one. Stepping the whole jump at once starves the parts of
-- the machine that are deliberately rate-limited — step 1 stamps one arrival per tech per
-- pass — which leaves most assignments without an ETA and piles their timeline blocks on
-- the job's scheduled time.
create or replace function api.sim_tick(p_wall_seconds double precision default 10)
returns void language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	step  constant interval := interval '1 minute';
	guard constant integer := 600;   -- ceiling on work per call
	st     api.sim_state%rowtype;
	target timestamptz;
	cur    timestamptz;
	i      integer := 0;
begin
	select * into st from api.sim_state limit 1;
	if st.mode <> 'simulated' or st.is_paused or st.virtual_now is null then
		return;
	end if;

	target := st.virtual_now + make_interval(secs => st.speed * p_wall_seconds);
	cur := st.virtual_now;

	while cur < target and i < guard loop
		cur := least(cur + step, target);
		update api.sim_state set virtual_now = cur;
		if st.sim_start is not null then
			perform api.dispatch_tick(cur, st.sim_start);
		end if;
		i := i + 1;
		-- dispatch_tick pauses the clock when the day completes
		exit when (select is_paused from api.sim_state limit 1);
	end loop;
end;
$fn$;

grant execute on function api.slot_minutes(text) to web_anon;
grant execute on function api.on_shift(integer, integer) to web_anon;
grant execute on function api.ml_assign(timestamptz, timestamptz) to web_anon;
grant execute on function api.day_beats(timestamptz, timestamptz) to web_anon;
grant execute on function api.dispatch_tick(timestamptz, timestamptz) to web_anon;
