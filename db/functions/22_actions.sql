-- Context-menu write paths the shell needs: qualified-tech submenu, job status FSM,
-- tech status. Ports htmx.py:408 (/qualified/{id}), logic/jobs.py:146 (update_job_status)
-- and technicians.py PATCH /{id}/status.
-- Status values arrive lowercase from the UI; enum columns are UPPERCASE.

-- Assign-To submenu source. JSON, not the text/html domain — verified by jq -S diff
-- like map_markers, not the byte harness.
create or replace function api.qualified_techs(p_job_id integer)
returns json language plpgsql stable as $fn$
declare
	j        jobs%rowtype;
	required jsonb;
begin
	select * into j from jobs where id = p_job_id;
	if not found then
		return json_build_object('qualified', '[]'::json, 'missing_skills', '[]'::json);
	end if;
	required := coalesce(j.required_skills, '[]'::jsonb);

	return (
		with cand as (
			select
				t.name,
				array(
					select s from jsonb_array_elements_text(required) s
					where s not in (select jsonb_array_elements_text(coalesce(t.skills, '[]'::jsonb)))
				) as missing,
				t.id, lower(t.status::text) as status
			from technicians t
			where t.is_active and t.status <> 'OFF_DUTY'
		)
		select json_build_object(
			'qualified', coalesce((
				select json_agg(json_build_object('id', id, 'name', name, 'status', status,
					'missing', array_to_json(missing)) order by name)
				from cand where missing = '{}'), '[]'::json),
			'unqualified', coalesce((
				select json_agg(json_build_object('id', id, 'name', name, 'status', status,
					'missing', array_to_json(missing)) order by name)
				from cand where missing <> '{}'), '[]'::json),
			'required', array_to_json(array(select s from jsonb_array_elements_text(required) s))
		)
	);
end;
$fn$;

-- Job status FSM. Transition table is logic/jobs.py:166-173 verbatim; side effects are
-- the started_at / completed_at stamps. Tech status is deliberately untouched (FastAPI
-- does not touch it here either).
create or replace function api.job_action(p_job_id integer, p_action text)
returns "text/html" language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	j        jobs%rowtype;
	target   text;
	allowed  text[];
begin
	target := case p_action
		when 'start' then 'IN_PROGRESS'
		when 'complete' then 'COMPLETED'
		when 'hold' then 'ON_HOLD'
		when 'cancel' then 'CANCELLED'
	end;
	if target is null then
		return api.toast('Unknown action', 'warning');
	end if;

	select * into j from jobs where id = p_job_id;
	if not found then
		return api.toast('Job not found', 'warning');
	end if;

	allowed := case j.status::text
		when 'PENDING' then array['ASSIGNED', 'CANCELLED', 'ON_HOLD']
		when 'ASSIGNED' then array['IN_PROGRESS', 'PENDING', 'CANCELLED', 'ON_HOLD']
		when 'IN_PROGRESS' then array['COMPLETED', 'ON_HOLD', 'CANCELLED']
		when 'ON_HOLD' then array['PENDING', 'ASSIGNED', 'CANCELLED']
		else array[]::text[]
	end;
	if not (target = any (allowed)) then
		return api.toast('Cannot ' || p_action || ' a ' || lower(j.status::text) || ' job', 'warning');
	end if;

	update jobs set
		status = target::jobstatus,
		updated_at = now(),
		started_at = case when target = 'IN_PROGRESS' and started_at is null then now() else started_at end,
		completed_at = case when target = 'COMPLETED' and completed_at is null then now() else completed_at end
	where id = p_job_id;

	perform set_config('response.headers', '[{"HX-Trigger": "refreshAll"}]', true);
	return api.toast('Job #' || coalesce(nullif(j.job_number, ''), j.id::text)
		|| ' → ' || replace(lower(target), '_', ' '), 'success');
end;
$fn$;

create or replace function api.tech_set_status(p_tech_id integer, p_status text)
returns "text/html" language plpgsql volatile
security definer set search_path = api, public as $fn$
declare
	t      technicians%rowtype;
	target text;
begin
	target := upper(p_status);
	if not exists (select 1 from unnest(enum_range(null::technicianstatus)) e where e::text = target) then
		return api.toast('Unknown status', 'warning');
	end if;

	select * into t from technicians where id = p_tech_id;
	if not found then
		return api.toast('Tech not found', 'warning');
	end if;

	update technicians set status = target::technicianstatus, updated_at = now() where id = p_tech_id;

	perform set_config('response.headers', '[{"HX-Trigger": "refreshAll"}]', true);
	return api.toast(t.name || ' → ' || replace(lower(target), '_', ' '), 'success');
end;
$fn$;

grant execute on function api.qualified_techs(integer) to web_anon;
grant execute on function api.job_action(integer, text) to web_anon;
grant execute on function api.tech_set_status(integer, text) to web_anon;
