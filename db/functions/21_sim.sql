-- Sim UI + controls. Posts straight to /rpc/sim_* with p_-prefixed fields.
-- NOTE the clock is REDESIGNED (stepped, see 02_clock.sql), so sim_bar's simulated/running
-- states are NOT byte-comparable to FastAPI's live-interpolated clock — only the deterministic
-- states (is_demo=false -> empty; real/STOPPED -> --:--:-- ) byte-match. Controls write clock
-- state only; the reseed + auto_route + dispatch-loop that /sim/start also does are the sim
-- ENGINE (deferred — needs strategy.py->PL/pgSQL). is_demo gates whether the bar renders at all.

-- True once the demo day has played out. The engine pauses the clock when nothing is left
-- to do (24_engine.sql, auto-stop); resuming then would only nudge the clock a step before
-- the next tick pauses it again, so the bar offers Stop only.
create or replace function api.sim_day_done()
returns boolean language sql stable as $$
	select coalesce((
		select s.mode = 'simulated' and s.is_paused and not exists (
			select 1 from jobs j
			where j.status in ('PENDING', 'ASSIGNED', 'IN_PROGRESS')
				and j.scheduled_date >= date_trunc('day', s.virtual_now)
				and j.scheduled_date <  date_trunc('day', s.virtual_now) + interval '1 day')
		from api.sim_state s limit 1), false);
$$;

-- ── Render: sim bar ─────────────────────────────────────────────────────────
create or replace function api.sim_bar()
returns "text/html" language sql stable as $$
	select case when not api.is_demo() then '<div id="sim-bar"></div>'
	else (
		select
			'<div id="sim-bar" class="sim-row"><span class="demo-badge">DEMO</span>'
			|| '<span class="sim-state sim-state--' || case when d.done then 'done' when s.is_paused then 'paused' else s.mode end || '">'
				|| case when d.done then '✓ DAY COMPLETE'
					when s.is_paused then '■ PAUSED'
					when s.mode = 'real' then '■ STOPPED'
					else '● RUNNING' end
			|| '</span>'
			|| '<span class="sim-clock mono" id="sim-clock">'
				|| case when s.mode = 'real' then '--:--:--'
					else to_char(api.sim_now() at time zone 'UTC', 'HH24:MI:SS') end
			|| '</span>'
			|| case when s.mode = 'real' then
				'<form hx-post="/rpc/sim_start" hx-target="#sim-bar" hx-swap="outerHTML">'
				|| '<input type="hidden" name="p_speed" value="500">'
				|| '<button class="btn btn--success">▶ Start Demo</button></form>'
			else
				case when d.done then ''
				when s.is_paused then
					'<button class="btn btn--primary" hx-post="/rpc/sim_resume" hx-target="#sim-bar" hx-swap="outerHTML">▶ Resume</button>'
				else
					'<button class="btn" hx-post="/rpc/sim_pause" hx-target="#sim-bar" hx-swap="outerHTML">❚❚ Pause</button>'
				end
				|| '<button class="btn btn--danger" hx-post="/rpc/sim_stop" hx-target="#sim-bar" hx-swap="outerHTML">■ Stop</button>'
			end
			|| '<div class="sim-speed"><span class="sim-speed-label">Speed</span>'
			|| '<select name="p_speed" hx-post="/rpc/sim_speed" hx-target="#sim-bar" hx-swap="outerHTML" hx-trigger="change"'
				|| case when s.mode = 'real' or d.done then ' disabled' else '' end || '>'
			|| (select string_agg('<option value="' || v || '" '
					|| case when v = case when s.mode = 'real' then 500 else trunc(s.speed)::int end then 'selected' else '' end || '>' || v || '×</option>', '' order by ord)
				from unnest(array[10,100,250,500,1000,2000]) with ordinality o(v, ord))
			|| '</select></div>'
			|| '</div>'
		from api.sim_state s, lateral (select api.sim_day_done() as done) d limit 1
	) end;
$$;

-- ── Render: settings window ─────────────────────────────────────────────────
create or replace function api.settings_window()
returns "text/html" language sql stable as $$
	select
		'<div class="win-body" style="padding:14px;">'
		|| '<div class="settings-group"><label>Theme</label>'
		|| '<select id="set-theme" data-pref="fieldopt.theme" onchange="setTheme(this.value)">'
		|| '<option value="dark" selected>Dark</option><option value="light">Light</option></select></div>'
		|| '<div class="settings-group"><label>Refresh interval</label>'
		|| '<select id="set-refresh" data-pref="fieldopt.refresh" onchange="setRefreshInterval(parseInt(this.value))">'
		|| '<option value="1000">1 second</option><option value="3000" selected>3 seconds</option>'
		|| '<option value="5000">5 seconds</option><option value="10000">10 seconds</option>'
		|| '<option value="0">Off (manual)</option></select></div>'
		|| '<div class="settings-group"><label>Display density</label>'
		|| '<select id="set-density" data-pref="fieldopt.density" onchange="document.body.dataset.density = this.value; localStorage.setItem(''fieldopt.density'', this.value);">'
		|| '<option value="normal" selected>Normal</option><option value="compact">Compact</option>'
		|| '<option value="comfortable">Comfortable</option></select></div>'
		|| '<div class="settings-group"><label>Sim mode</label>'
		|| '<div class="mono muted">' || upper((select mode from api.sim_state limit 1))
			|| case when api.is_demo() then ' · DEMO build' else '' end || '</div></div>'
		|| '<div class="settings-group"><label>Quick actions</label>'
		|| '<button class="btn" onclick="document.body.dispatchEvent(new Event(''refreshAll''))">Refresh now</button>'
		|| '<button class="btn btn--danger" onclick="if(confirm(''Reset all selections?'')){selTechs.clear();selJobs.clear();applySelectionVisuals();updateSelCounts();syncTechSelection();}">Clear selections</button></div>'
		|| '<div class="settings-group"><label>Keyboard shortcuts</label>'
		|| '<div style="font-size:var(--font-size-xs); color: var(--text-secondary); line-height: 1.8;">'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">⌘/Ctrl+A</span> Select all (in hovered pane)</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">Esc</span> Clear selection / close modal</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">D</span> Complete selected jobs</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">S</span> Start selected jobs</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">C</span> Cancel selected jobs</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">H</span> Hold selected jobs</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">U</span> Unassign selected jobs</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">R</span> Refresh all panes</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">/</span> Open Job Search</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">F</span> Open Filter</div>'
		|| '<div><span class="mono" style="display:inline-block;width:80px;color:var(--color-accent);">P</span> Open Personnel</div>'
		|| '</div></div></div>';
$$;

-- ── Controls (write clock state, return the bar). SECURITY DEFINER for the writes. ──
-- DEFERRED vs FastAPI: /sim/start also reseeds + auto_routes + starts dispatch loop (the sim
-- ENGINE). Here start only sets clock state; engine port is separate (strategy.py->PL/pgSQL).
create or replace function api.sim_start(p_speed double precision default 500)
returns "text/html" language plpgsql volatile security definer set search_path = api, public as $$
begin
	update api.sim_state set mode = 'simulated', is_paused = false, speed = p_speed,
		virtual_now = date_trunc('day', now()) + interval '8 hours',
		sim_start = date_trunc('day', now()) + interval '8 hours',
		fired_beats = '{}';
	-- Reset + pre-route, as FastAPI's /sim/start did (reset_db + reseed + auto_route),
	-- so every Start Demo begins from the same clean day.
	perform api.seed_demo();
	perform api.auto_route(current_date);
	return api.sim_bar();
end $$;

create or replace function api.sim_pause()
returns "text/html" language plpgsql volatile security definer set search_path = api, public as $$
begin update api.sim_state set is_paused = true; return api.sim_bar(); end $$;

create or replace function api.sim_resume()
returns "text/html" language plpgsql volatile security definer set search_path = api, public as $$
begin
	if not api.sim_day_done() then update api.sim_state set is_paused = false; end if;
	return api.sim_bar();
end $$;

create or replace function api.sim_stop()
returns "text/html" language plpgsql volatile security definer set search_path = api, public as $$
begin
	update api.sim_state set mode = 'real', is_paused = false, speed = 1.0, virtual_now = null;
	return api.sim_bar();
end $$;

create or replace function api.sim_speed(p_speed double precision)
returns "text/html" language plpgsql volatile security definer set search_path = api, public as $$
begin
	if (select mode from api.sim_state limit 1) <> 'simulated' then
		raise exception 'Simulation not running' using errcode = 'P0001';
	end if;
	update api.sim_state set speed = p_speed;
	return api.sim_bar();
end $$;

grant execute on function api.sim_day_done() to web_anon;
grant execute on function api.sim_bar() to web_anon;
grant execute on function api.settings_window() to web_anon;
grant execute on function api.sim_start(double precision) to web_anon;
grant execute on function api.sim_pause() to web_anon;
grant execute on function api.sim_resume() to web_anon;
grant execute on function api.sim_stop() to web_anon;
grant execute on function api.sim_speed(double precision) to web_anon;
