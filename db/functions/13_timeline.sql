-- Pure-SVG per-tech assignment timeline, 08:00-18:00 (the sim day), drawn at the width the
-- pane asks for: row_h=22, name_w=140, px_per_min = chart width / 600.
-- Coordinates are floats -> api.py_float() reproduces Python's str(float) '.0' repr.
-- Blocks: committed work sits at its ETA; a tech's queued jobs are laid end-to-end after
--   it (see the `packed` CTE). Offsets are from 08:00; width>=15; techs ordered by name.
-- NOTE: this deliberately DIVERGES from the retired FastAPI template, which placed every
--   ETA-less block on the job's scheduled time and stacked them.
-- p_selected: optional comma-separated tech ids to keep (mirrors ?selected=).
-- p_width: pane width in px; narrow panes still get a readable minimum.
drop function if exists api.timeline(text);
create or replace function api.timeline(p_selected text default '', p_width integer default 800)
returns "text/html" language sql stable as $$
	with cfg as (
		select w, (w - 148) / 600.0 as ppm
		from (select greatest(coalesce(p_width, 800), 360)::float8 as w) x
	),
	clk as (
		select api.sim_now() as t
	),
	d as (
		select
			date_trunc('day', t) as day_start,
			greatest(0,
				(extract(hour from (t at time zone 'UTC'))::int - 8) * 60
				+ extract(minute from (t at time zone 'UTC'))::int) as now_off
		from clk
	),
	techs as (
		select id, name, (row_number() over (order by name) - 1)::int as idx
		from technicians
		where is_active
		  and (p_selected = '' or id = any (
				string_to_array(p_selected, ',')::int[]))
	),
	nrows as (
		select count(*)::int as n, count(*)::int * 22 + 28 as svg_h from techs
	),
	-- A tech only carries an ETA for the job they are currently heading to; the rest of
	-- their day has none. Placing those on the job's scheduled time stacks them all on the
	-- same x. Lay them end-to-end after the tech's committed work instead, no earlier than
	-- the customer window opens. Committed blocks keep their real ETA position.
	laid as (
		select
			a.job_id,
			a.technician_id,
			a.estimated_arrival is not null as committed,
			coalesce(a.estimated_arrival, j.scheduled_date) as eta,
			greatest(0, extract(epoch from (a.estimated_arrival - d.day_start)) / 60.0 - 480) as eta_off,
			greatest(0, case
				when j.time_slot_start ~ '^[0-9]{1,2}:[0-9]{2}'
					then split_part(j.time_slot_start, ':', 1)::int * 60
						+ split_part(j.time_slot_start, ':', 2)::int
				else 480 end - 480)::float8 as slot_off,
			greatest(15, coalesce(a.actual_duration_minutes, j.estimated_duration, 60)::float8) as width_min
		from assignments a
		join jobs j on j.id = a.job_id
		cross join d
		where j.scheduled_date >= d.day_start
		  and j.scheduled_date <  d.day_start + interval '1 day'
		  and coalesce(a.estimated_arrival, j.scheduled_date) is not null
	),
	packed as (
		select
			l.job_id, l.technician_id, l.eta, l.width_min,
			case when l.committed then l.eta_off
			else greatest(
				coalesce(max(case when l.committed then l.eta_off + l.width_min end)
					over (partition by l.technician_id), 0),
				l.slot_off)
				+ coalesce(sum(l.width_min) filter (where not l.committed)
					over (partition by l.technician_id
						order by l.slot_off, l.job_id
						rows between unbounded preceding and 1 preceding), 0)
			end as offset_min
		from laid l
	),
	-- per-block html, keyed to its tech row's y-position (needs techs.idx)
	blk as (
		select
			tk.idx,
			bo.offset_min,
			'<g class="tl-block tl-block--' || lower(j.status::text) || '">'
			|| '<title>#' || api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text))
				|| ' ' || api.html_escape(j.customer_name)
				|| ' — ETA ' || to_char(bo.eta at time zone 'UTC', 'HH24:MI')
				|| ' (' || trunc(bo.width_min)::bigint || 'm)</title>'
			|| '<rect x="' || api.py_float(140 + bo.offset_min * c.ppm) || '"'
				|| ' y="' || (24 + tk.idx * 22 + 3) || '"'
				|| ' width="' || api.py_float(bo.width_min * c.ppm) || '"'
				|| ' height="15" rx="2"/>'
			|| case when bo.width_min * c.ppm > 36 then
				'<text x="' || api.py_float(140 + bo.offset_min * c.ppm + 4) || '"'
				|| ' y="' || (24 + tk.idx * 22 + 14) || '" class="tl-block-label">#'
				|| api.html_escape(coalesce(nullif(j.job_number, ''), j.id::text)) || '</text>'
			else '' end
			|| '</g>' as block_html
		from packed bo
		join jobs j on j.id = bo.job_id
		join techs tk on tk.id = bo.technician_id
		cross join cfg c
	)
	select
		'<div class="timeline-wrap">'
		|| '<svg class="timeline" width="' || api.py_float(c.w) || '" height="' || nrows.svg_h || '"'
			|| ' viewBox="0 0 ' || api.py_float(c.w) || ' ' || nrows.svg_h || '">'
		|| '<!-- Hour grid -->'
		|| (select string_agg(
				'<line x1="' || api.py_float(140 + g.i * 60 * c.ppm) || '" y1="20"'
					|| ' x2="' || api.py_float(140 + g.i * 60 * c.ppm) || '" y2="' || nrows.svg_h || '" class="tl-grid"/>'
				|| case when g.i < 10 and (60 * c.ppm >= 40 or g.i % 2 = 0) then '<text x="' || api.py_float(140 + g.i * 60 * c.ppm + 2) || '" y="14" class="tl-hour">'
					|| to_char(8 + g.i, 'FM00') || ':00</text>' else '' end,
				'' order by g.i)
			from generate_series(0, 10) as g(i))
		|| '<!-- Rows -->'
		|| coalesce((select string_agg(
				'<text x="6" y="' || (24 + tk.idx * 22 + 14) || '" class="tl-name">'
					|| api.html_escape(tk.name) || '</text>'
				|| '<line x1="140" y1="' || (24 + tk.idx * 22 + 21) || '"'
					|| ' x2="' || api.py_float(c.w) || '" y2="' || (24 + tk.idx * 22 + 21) || '" class="tl-rowline"/>'
				|| coalesce((select string_agg(b.block_html, '' order by b.offset_min)
							 from blk b where b.idx = tk.idx), ''),
				'' order by tk.idx)
			from techs tk), '')
		|| '<!-- Now marker -->'
		|| case when d.now_off < 600 then
			'<line x1="' || api.py_float(140 + d.now_off * c.ppm) || '" y1="18"'
			|| ' x2="' || api.py_float(140 + d.now_off * c.ppm) || '" y2="' || nrows.svg_h || '" class="tl-now"/>'
		else '' end
		|| '</svg></div>'
	from nrows, d, cfg c;
$$;

grant execute on function api.timeline(text, integer) to web_anon;
