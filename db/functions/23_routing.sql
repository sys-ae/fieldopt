-- Routing port: distance/duration helpers + auto_route (logic/routing/auto_router.py).
-- Two haversine variants exist in Python: distance.py uses 2*asin(sqrt(a)) and drives
-- selection + stored distance; can_technician_do_job uses 2*atan2 rounded to 1dp for a
-- display field only. This is the asin one — the selection-relevant one.
create or replace function api.haversine(
	lat1 double precision, lon1 double precision,
	lat2 double precision, lon2 double precision
) returns double precision language sql immutable as $$
	select 3959.0 * 2 * asin(sqrt(
		sin(radians(lat2 - lat1) / 2) ^ 2
		+ cos(radians(lat1)) * cos(radians(lat2)) * sin(radians(lon2 - lon1) / 2) ^ 2));
$$;

create or replace function api.travel_time(dist double precision, speed_mph double precision default 30.0)
returns integer language sql immutable as $$
	select trunc(dist / speed_mph * 60)::int;
$$;

-- Replaces simulation/sampler.py. Python seeds numpy PCG64 with hash((job_id, tech_id)),
-- which SQL cannot reproduce, so this is a deterministic lognormal of its own: hash the
-- pair to two uniforms, Box-Muller to z, then the same mean/sigma model. Same pair always
-- gives the same duration, as in Python.
create or replace function api.sample_duration(p_job_id integer, p_tech_id integer)
returns integer language plpgsql stable as $fn$
declare
	sigma constant double precision := 0.25;
	mult  double precision;
	mean  double precision;
	u1    double precision;
	u2    double precision;
	z     double precision;
	j     jobs%rowtype;
	t     technicians%rowtype;
begin
	select * into j from jobs where id = p_job_id;
	if not found then return null; end if;
	select * into t from technicians where id = p_tech_id;
	if not found then return null; end if;

	-- skill_bonuses is keyed by the job_type VALUE (lowercase); the column is UPPERCASE
	mult := coalesce(t.speed_factor, 1.0)
		* coalesce((t.skill_bonuses ->> lower(j.job_type::text))::double precision, 1.0);
	mean := greatest(coalesce(j.estimated_duration, 60) * mult, 1.0);

	-- two independent uniforms in (0,1) from the pair, shifted off 0 so ln() is safe
	u1 := (abs(mod(hashtextextended(p_job_id || ':' || p_tech_id, 0), 1000000)) + 1) / 1000001.0;
	u2 := (abs(mod(hashtextextended(p_job_id || ':' || p_tech_id, 1), 1000000)) + 1) / 1000001.0;
	z := sqrt(-2 * ln(u1)) * cos(2 * pi() * u2);

	return greatest(1, round(exp(ln(mean) - (sigma ^ 2) / 2 + sigma * z))::int);
end;
$fn$;

-- Counterfactual duration for a hypothetical tech — same sampler, as in Python.
create or replace function api.what_if_duration(p_job_id integer, p_tech_id integer)
returns integer language sql stable as $$
	select api.sample_duration(p_job_id, p_tech_id);
$$;

-- CanDo gate used by routing: skill + route + shift capacity (logic/jobs.py:301).
-- Route rule here is the REAL one (job route must be in the tech's assigned_routes),
-- not the advisory-permissive rule api.assign uses for the override modal.
-- has_time re-reads the tech's live workload, which mirrors Python: create_assignment
-- commits, SQLAlchemy expires the object, and tech.assignments reloads on next access —
-- so capacity shrinks as the loop assigns.
create or replace function api.can_do(p_job_id integer, p_tech_id integer)
returns boolean language plpgsql stable as $fn$
declare
	j             jobs%rowtype;
	t             technicians%rowtype;
	has_skill     boolean;
	has_route     boolean;
	has_time      boolean := true;
	assigned_mins integer;
	shift_start   integer;
	shift_end     integer;
begin
	select * into j from jobs where id = p_job_id;
	if not found then return false; end if;
	select * into t from technicians where id = p_tech_id;
	if not found then return false; end if;

	has_skill := not exists (
		select 1 from jsonb_array_elements_text(coalesce(j.required_skills, '[]'::jsonb)) s
		where s not in (select jsonb_array_elements_text(coalesce(t.skills, '[]'::jsonb)))
	);

	has_route := case
		when nullif(j.route_criteria, '') is null then true
		when coalesce(t.assigned_routes, '[]'::jsonb) = '[]'::jsonb then false
		else j.route_criteria in (select jsonb_array_elements_text(t.assigned_routes))
	end;

	if nullif(t.shift_end, '') is not null and j.estimated_duration is not null then
		shift_end := split_part(t.shift_end, ':', 1)::int * 60 + split_part(t.shift_end, ':', 2)::int;
		shift_start := case when nullif(t.shift_start, '') is null then 8 * 60
			else split_part(t.shift_start, ':', 1)::int * 60 + split_part(t.shift_start, ':', 2)::int end;
		select coalesce(sum(coalesce(jj.estimated_duration, 0)), 0) into assigned_mins
		from assignments a join jobs jj on jj.id = a.job_id
		where a.technician_id = t.id and jj.status not in ('COMPLETED', 'CANCELLED');
		has_time := (shift_end - shift_start) - assigned_mins >= j.estimated_duration;
	end if;

	return has_skill and has_route and has_time;
end;
$fn$;

-- Port of POST /api/v1/routing/auto-route (auto_router.auto_route_jobs).
-- Closest eligible tech wins — distance only, no duration prediction (that is
-- MLStrategy, which belongs to the dispatch loop, not this endpoint).
-- Techs are NOT removed from the pool after winning a job and stay AVAILABLE:
-- pre-routing hands a tech a whole day, and the loop stamps departures one at a time.
create or replace function api.auto_route(p_target_date date default null)
returns json language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	job_rec     record;
	best_tech   integer;
	best_dist   double precision;
	dist        double precision;
	travel      integer;
	tech_rec    record;
	assigned    integer := 0;
	unassigned  json[] := array[]::json[];
	pending_ct  integer;
	avail_ct    integer;
begin
	select count(*) into pending_ct from jobs
	where status = 'PENDING'
		and (p_target_date is null or scheduled_date::date = p_target_date);

	if pending_ct = 0 then
		return json_build_object(
			'success', true, 'message', 'No pending jobs to route',
			'jobs_assigned', 0, 'jobs_unassigned', 0,
			'unassigned_details', '[]'::json);
	end if;

	select count(*) into avail_ct from technicians where is_active and status = 'AVAILABLE';
	if avail_ct = 0 then
		return json_build_object(
			'success', false, 'message', 'No available technicians',
			'jobs_assigned', 0, 'jobs_unassigned', pending_ct,
			'unassigned_details', (
				select coalesce(json_agg(json_build_object(
					'job_id', id, 'reason', 'No available technicians') order by priority, created_at), '[]'::json)
				from jobs where status = 'PENDING'
					and (p_target_date is null or scheduled_date::date = p_target_date)));
	end if;

	for job_rec in
		select * from jobs
		where status = 'PENDING'
			and (p_target_date is null or scheduled_date::date = p_target_date)
		order by priority, created_at
	loop
		best_tech := null;
		best_dist := null;

		for tech_rec in
			select * from technicians where is_active and status = 'AVAILABLE' order by id
		loop
			if not api.can_do(job_rec.id, tech_rec.id) then
				continue;
			end if;
			dist := api.haversine(
				coalesce(tech_rec.current_latitude, tech_rec.home_latitude),
				coalesce(tech_rec.current_longitude, tech_rec.home_longitude),
				job_rec.latitude, job_rec.longitude);
			if best_dist is null or dist < best_dist then
				best_dist := dist;
				best_tech := tech_rec.id;
			end if;
		end loop;

		if best_tech is null then
			unassigned := unassigned || json_build_object(
				'job_id', job_rec.id, 'reason', 'No technicians with required skills');
			continue;
		end if;

		travel := api.travel_time(best_dist);
		insert into assignments (job_id, technician_id, sequence, estimated_distance,
			estimated_travel_time, actual_duration_minutes, estimated_arrival,
			assigned_at, created_at, updated_at)
		values (job_rec.id, best_tech, null, best_dist, travel,
			api.sample_duration(job_rec.id, best_tech), null, now(), now(), now());

		update jobs set status = 'ASSIGNED', updated_at = now() where id = job_rec.id;
		assigned := assigned + 1;
	end loop;

	return json_build_object(
		'success', true, 'message', 'Auto-routing complete',
		'jobs_assigned', assigned,
		'jobs_unassigned', coalesce(array_length(unassigned, 1), 0),
		'unassigned_details', array_to_json(unassigned));
end;
$fn$;

grant execute on function api.haversine(double precision, double precision, double precision, double precision) to web_anon;
grant execute on function api.travel_time(double precision, double precision) to web_anon;
grant execute on function api.sample_duration(integer, integer) to web_anon;
grant execute on function api.what_if_duration(integer, integer) to web_anon;
grant execute on function api.can_do(integer, integer) to web_anon;
grant execute on function api.auto_route(date) to web_anon;
