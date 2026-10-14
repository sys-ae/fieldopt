> **v0.0.9 — full-Postgres architecture (Path C).** FieldOpt now runs with no application server: PL/pgSQL functions render the HTMX fragments and JSON, PostgREST exposes them as RPC, and nginx serves the shell. The FastAPI/Python stack it replaced remains in git history (v0.0.8). Every ported surface was verified against that stack before it was retired — 11/11 HTML fragments and the JSON endpoints byte-identical after whitespace normalization, and auto-route decisions identical across all 50 jobs (same technician, distance to 9dp, travel time).

## Overview
FieldOpt - v0.0.9<br>
An open-source field service management system. FieldOpt is an enterprise-grade dispatch console designed for dispatchers and field service companies to efficiently assign, route, and manage service jobs across a workforce of field technicians.

<table align="center">
	<tr>
		<td colspan="2" align="center">
			<img src="./assets/dashboard.png" alt="Dispatch Console" width="600"/><br/>
			Dispatch Console
		</td>
	</tr>
	<tr>
		<td align="center">
			<img src="./assets/jobsearch.png" alt="Job Search" width="300"/><br/>
			Job Search
		</td>
		<td align="center">
			<img src="./assets/map.png" alt="Map in Second Window" width="300"/><br/>
			Map in Second Window
		</td>
	</tr>
	<tr>
	<td align="center">
			<img src="./assets/filter.png" alt="Route Filter Display" width="300"/><br/>
			Route Filter Display
		</td>
		<td align="center">
			<img src="./assets/personal.png" alt="Personal Display" width="300"/><br/>
			Personal Display
		</td>
	</tr>
</table><br>

**Auto-Router** — Automatically assigns jobs to the best qualified technicians

**Skill-Based Matching** — Ensures technicians only get jobs they're qualified for (manual override capable)

**Capacity Management** — Prevents overbooking by tracking tech workload

**Route Criteria & Management Areas** — Techs are assigned geographic zones; jobs carry route criteria for zone-aware dispatch

**Enterprise Dispatch Console** — Server-rendered HTMX split-pane layout with right-click context menus, drag-and-drop assignment, multi-select batch operations, tech timeline, day picker, floating filter/search/personnel windows, and a detachable map popup for multi-monitor setups

## Launch FieldOpt

Try it first with nothing installed: **<https://demo.fieldopt.dev>** runs the whole console in
your browser — the same SQL as a server install, on Postgres compiled to WebAssembly.

### Requirements

- Docker + Docker Compose

### Run

```bash
make up        # start postgres (pg_cron) + postgrest + nginx
```

That is the whole install. A fresh database volume creates its own schema, installs the
application and loads the demo day on first boot (`deploy/initdb.sh`), so there is no
migration or seed step to run. Browse <http://localhost:8081>.

```bash
make demo      # enable the sim UI, then press Start Demo in the console
make no-demo   # disable it again
make pg-apply  # re-install the SQL after editing db/functions (dev loop)
make pg-seed   # reload the demo day
make pg-sync   # push web/ assets into nginx without an image rebuild
make down      # stop containers (DB volume kept)
make clean     # stop + wipe DB volume (next boot re-installs from scratch)
make logs      # tail nginx + postgrest + postgres
```

#### Access

| Service | URL |
|---------|-----|
| Dispatch Console | http://localhost:8081/ |
| RPC (PostgREST) | http://localhost:8081/rpc/ |

#### Architecture

| Piece | Role |
|-------|------|
| `db/functions/` | PL/pgSQL — every fragment, every write path, the routing and sim engine |
| `db/seeds/` | Demo data as SQL, dates relative to the run date |
| `db/postgrest/` | The `api` schema, the `web_anon` role and its grants |
| `web/` | Static assets only: `app.css`, `map.html`, vendored htmx/Leaflet |
| `deploy/` | Standalone `nginx.conf` + `postgrest.conf`, the three images, and `initdb.sh` |
| `demo/` | The in-browser demo: the same SQL on PGlite (WebAssembly Postgres), published to demo.fieldopt.dev |
| `db/schema/` | Table + enum DDL. The only thing that defines the schema now |

The page itself is `api.shell()` — Postgres renders the shell and the fragments inside it
in one response. nginx proxies `/` there and otherwise only serves static files; there is no
templating, no SSI, and no client-side URL mapping. Fragments and forms address `/rpc/*`
directly.

The demo clock runs on pg_cron inside the database (`db/functions/25_cron.sql`), scheduled
once a second, alongside a 04:00 UTC reseed that keeps a long-running demo box fresh.
`api.sim_tick()` is still an ordinary function, so if your Postgres lacks pg_cron — managed
instances often do — skip that file and call it from any external scheduler instead.

## Routing
### Routing Modes

- **Auto-Route** (`auto_route`) — assigns every pending job to the closest qualified tech
- **Sim dispatch** (`ml_assign`) — scores each qualified tech by travel time plus predicted job duration, preferring techs who can arrive inside the customer window

### How It Works

The routing engine evaluates multiple factors to find the best technician for each job:
1. **Skill** — Technician must have all required skills
2. **Route** — Job's route criteria must match one of the tech's assigned management areas
3. **Time** — Technician must have time available in their shift
4. **Distance** — Assigns closest qualified tech (haversine calculation)
5. **Priority** — Jobs are routed in priority order

### Job Evaluation

When assigning a job to a technician, the system evaluates three criteria and warns if any fail:
- **Skill** ✓/✕ — Does the tech have the required skills?
- **Route** ✓/✕ — Is the job in the tech's assigned management area?
- **Time** ✓/✕ — Does the tech have enough shift time remaining?
If any check fails, the dispatcher receives a warning with details but can override the assignment.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `R` | Refresh data |
| `/` | Open job search |
| `F` | Open display filter |
| `P` | Open personnel window |
| `D` / `S` / `C` / `H` | Done / Start / Cancel / Hold the selected jobs |
| `U` | Unassign the selected jobs |
| `Ctrl/Cmd+A` | Select all in focused grid |
| `Esc` | Clear selection, close modal / context menu |

## API

Everything is a PostgREST RPC over the `api` schema. HTML fragments return a `text/html`
domain type (send `Accept: text/html`); the rest return JSON.

```bash
curl -H 'Accept: text/html' http://localhost:8081/rpc/tech_list
curl -H 'Accept: application/json' http://localhost:8081/rpc/map_markers
curl -d 'p_job_id=1&p_tech_id=3' http://localhost:8081/rpc/assign
```

#### Read (HTML fragments)
- `tech_list()` — technician grid
- `job_table(p_status, p_job_type, p_tech_id, p_route)` — job grid, filtered
- `dash_bar()` — status counts
- `timeline(p_selected)` — per-tech SVG timeline
- `personnel_window()`, `filter_window()`, `settings_window()` — floating windows
- `search_window(p_q, p_date_from, p_date_to, p_job_id, p_tech_id, p_customer, p_status, p_job_type, p_route)`
- `tech_detail(p_tech_id)`, `job_detail(p_job_id)` — detail windows
- `sim_bar()` — simulation controls

#### Read (JSON)
- `map_markers()` — jobs, techs and route polylines for Leaflet
- `qualified_techs(p_job_id)` — techs split by skill match, for the Assign-To menu

#### Write
- `assign(p_job_id, p_tech_id, p_override)` — CanDo checks, override modal, assignment
- `unassign(p_job_id)`
- `job_action(p_job_id, p_action)` — `start` / `complete` / `hold` / `cancel`, FSM-validated
- `tech_set_status(p_tech_id, p_status)`
- `auto_route(p_target_date)` — assign all pending jobs to the closest qualified tech

#### Simulation
- `sim_start(p_speed)` — reseed, pre-route, start the virtual day
- `sim_pause()`, `sim_resume()`, `sim_stop()`, `sim_speed(p_speed)`
- `sim_tick(p_wall_seconds)` — advance the clock and run the engine; called by pg_cron every second
- `seed_demo()` — reset to a fresh demo day

#### Internals (not called by the UI)
`can_do`, `haversine`, `travel_time`, `sample_duration`, `what_if_duration`, `ml_assign`,
`dispatch_tick`, `day_beats`, `on_shift`, `slot_minutes`, `sim_now`, `is_demo`,
`html_escape`, `py_float`, `toast`.

## Change Log

### 0.0.9 (Latest)

**Postgres as a platform.** The FastAPI/Python backend is gone; the application now lives in
the database. PL/pgSQL functions build the HTMX fragments and JSON, PostgREST serves them as
RPC over a `text/html` domain handler, and nginx serves a static shell. Runtime stack is
Postgres + PostgREST + nginx.

- **Rendering in SQL** — all 12 fragment templates and the map JSON ported to PL/pgSQL,
  each verified byte-identical (after whitespace normalization) to the FastAPI output.
- **Write paths in SQL** — assign with the CanDo override modal, unassign, job status FSM,
  technician status, and auto-route. Routing decisions match the Python router exactly.
- **Sim engine in SQL** — the dispatch loop, MLStrategy scoring, scripted beats and the
  virtual clock, driven by `api.sim_tick`. A full simulated day runs entirely in-database.
- **Duration model** — the numpy log-normal sampler was reimplemented in SQL (hash to two
  uniforms, Box-Muller). Values differ from numpy's by necessity; the sampler is verified by
  determinism and by its mean tracking each technician's hidden `speed_factor`.
- **Seeds as SQL** — demo data ships as `db/seeds/01_seed.sql` with dates relative to the
  run date, so no Python is needed to build a demo database.
- **No WebSocket** — the event socket was dropped; the console polls fragments on a 3s cycle.
- **pg_cron clock** — the virtual clock ticks inside the database every second; no ticker
  process. `api.sim_tick()` stays a plain function for Postgres hosts without pg_cron.
- **Postgres renders the page** — `api.shell()` returns the console with its first fragments
  inline; nginx proxies `/` to it and serves only static files. Console moved to port 8081.
- **Standalone configs** — `deploy/nginx.conf` and `deploy/postgrest.conf` are the same files
  the Docker bundle uses, ready for a raw (no-Docker) install.

### 0.0.8
ML routing + investor-ready demo day
- **Single-container Docker** — multi-stage build (node → python). FastAPI serves the SPA via `StaticFiles`; no separate nginx. One command brings up Postgres + app: `make up` (or `make demo` to enable the simulation). Browse `http://localhost:8080`.
- **MLStrategy** — default dispatch. Scores `(job, tech)` by `travel_time + what_if_duration(job, tech)` using hidden `speed_factor` / `skill_bonuses` modifiers. Two-pass routing: prefers techs who can arrive within the customer window, falls back to best-available so jobs never sit unrouted. `HeuristicStrategy` kept for A/B.
- **Sim control bar** — DEMO badge, status pill, HH:MM:SS virtual clock that rolls second-by-second via local interpolation re-anchored on each WebSocket `clock_tick`. Start / Pause / Resume / Stop, 10×–500× speed. Hidden when `IS_DEMO` is unset.
- **Demo playback lock** — once the day is running, the dispatcher can still inspect (click techs / jobs, open Map, Refresh, Timeline) but assignment-mutating UI is disabled (Auto-Route, Filter, Personnel, Job Search, drag-drop assign, context-menu assign). "DEMO PLAYING" badge bottom-right.
- **Realistic schedule** — 1-hour job slots redistributed across 8:00-16:00 (lunch hour skipped). Universal staggered breaks (~10:30 mid-morning 15 min, 12:00 lunch 30 min) and `OFF_DUTY` flip at shift end. Tech goes `EN_ROUTE` on assign → `ON_JOB` on arrival → `AVAILABLE` on completion → `OFF_DUTY` past shift end.
- **Tech timeline by ETA** — blocks position by `assignment.estimated_arrival` and width by `actual_duration_minutes` (sampled), not the customer time-slot window. Sequential jobs render side-by-side; manual stacks fall into vertical lanes.
- **Past-timeframe + overrun indicators** — jobs whose `time_slot_end` has passed without completion get a red left-border (`row--overdue`); in-progress jobs past `estimated_duration` go yellow / red (`overrun_warning` WebSocket events).
- **Auto-reseed daily** — when `IS_DEMO=true`, the app spawns a background task that wipes + reseeds Postgres at 04:00 UTC every day. AWS demo box stays fresh with zero manual touch. `/simulation/start` also resets on every click.
- **Day-complete auto-pause** — when no active today's jobs remain, sim emits `day_complete`, halts the loop, and pauses the clock at the final virtual time so the dispatcher sees end-of-day instead of a snap to real time.
- **Simulation engine** — asyncio dispatch loop, 1-min virtual tick. Clock singleton (simulated / real, pause / resume, live speed change without drift). Log-normal duration sampler seeded per `(job, tech)` for deterministic replay.
- **WebSocket broadcaster** — FastAPI WS at `/api/v1/simulation/ws` streams `job_assigned`, `job_started`, `job_completed`, `overrun_warning`, `clock_tick`, `scripted_beat`, `day_complete`. Frontend reconnects with exponential backoff.
- **Scripted beats** — Apollo Theater VIP emergency at 10:47, afternoon job surge at 12:00.
- **Simulation engine** — asyncio dispatch loop drives a time-accelerated demo day (200× default). Clock singleton supports simulated/real modes, pause/resume, live speed changes without drift.
- **Duration sampler** — log-normal sampling seeded per (job, tech) pair. Tech `speed_factor` and `skill_bonuses` modifiers create realistic variance. Same pair always returns the same duration (deterministic replay).
- **WebSocket broadcaster** — FastAPI WebSocket at `/ws` broadcasts `DispatchEvent` payloads: `job_started`, `job_completed`, `overrun_warning`, `clock_tick`, `scripted_beat`. Dead connections auto-pruned.
- **Sim control endpoints** — `IS_DEMO`-gated REST controls: `/simulation/start|pause|resume|stop|speed|status`. All return 404 in production.
- **Day script** — three scripted beats: Dizzy Gillespie on break at 10:00, VIP Apollo Theater emergency injected at 10:47, afternoon job surge released at 12:00.
- **Calendar date picker** — click the date label in the header to open a calendar popup (portal-rendered, escapes overflow clipping). Prev/next month navigation, Today shortcut.
- **Mobile & touch responsive** — `@media (max-width: 768px)`: icons-only header buttons, scrollable dashboard bar, full-screen floating windows, bigger touch targets (40px buttons, 44px titlebars). Touch drag-and-drop: long-press 200ms on a job row → drag ghost → drop on tech row. Haptic feedback on drag start.
- **Ctrl/Cmd+A select all** — selects all rows in the currently focused grid (tech or job pane).
- **Version globalization** — single source of truth in `package.json`, injected at build time via Vite `define`. Version shown in header. Backend reads from `config.py APP_VERSION`.
- **Performance** — drag ghost is direct DOM writes (no React re-render per frame). Selection sync uses AG Grid `getRowNode` O(1) not `forEachNode` O(n). Filter computation in `useMemo`. Tech ID lookup at drop via `useImperativeHandle.getTechIdAtPoint`.
- **Seed data** — 25 jazz musician techs with `speed_factor` and `skill_bonuses` modifiers. 50 jobs across 13 NYC management areas. Miles Davis fast, Sun Ra catastrophic on service changes, Mary Halvorson slow new hire.

### Previous Versions
<details>
<summary>Previous Changes</summary>

***0.0.7***<br>
Windows, search, route criteria, map popup
- Display Filter Window — Multi-select filter by time slot, job type, route criteria, and technician with Select All / None / Reset. Stacks with dashboard bar filters.
- Personnel Window — Searchable list of all technicians regardless of schedule. Right-click for context actions, double-click for detail, locate-in-grid button.
- Job Search Window — Multi-criteria search (date range, job ID, tech #, customer name, status, type, route criteria). Full AG Grid results with all columns matching the main display. Right-click and double-click support. Drag from search results onto a tech in the R&D.
- Job Detail Panel — Double-click any job (main grid or search results) for full detail view: customer, address, route criteria, schedule, assignment, skills, description, notes, timestamps.
- Map as real OS popup — Map opens via `window.open()` as a standalone window for multi-monitor setups. Syncs live data via BroadcastChannel. Falls back to in-page floating window if popup is blocked.
- Route Criteria / Management Areas — `route_criteria` field on jobs, `assigned_routes` on technicians. 13 NYC management areas in seed data. Route criteria column in job grid, routes column in tech grid.
- Job evaluation — Expanded from skill-only to skill + route + time checks with haversine distance calculation. Override warning modal on assign with ✓/✕ indicators for each check.
- Auto-route confirmation — Auto-route now prompts for confirmation before executing.
- Toolbar — Filter, Personnel, Job Search buttons in header bar.
- Keyboard shortcuts — F (filter), P (personnel), J (job search), A (auto-route).
- Backend — `GET /jobs/search/query` endpoint, expanded Job Evaluation endpoint, route_criteria on all job schemas.
- Header and dashboard bar scroll gracefully on narrow windows.

***0.0.6***<br>
Dispatch interactivity + batch operations
- Day picker with date-filtered API calls (navigate days, all views scoped to selected date)
- Multi-select: Cmd/Ctrl+click to toggle, Shift+click for range (respects AG Grid sort order)
- Independent grid selections (select techs for timeline while selecting jobs for assignment)
- Batch assign/unassign via single API call and single DB transaction
- Batch tech status changes (select multiple techs, right-click → set all to available/break/off duty)
- Drag-and-drop job assignment (drag from job grid, drop on tech row)
- Multi-job drag (select multiple jobs, drag one → all selected assign to target tech)
- Tech timeline pane (toggle-able, shows hour blocks with job assignments, stacks overlapping jobs)
- Resizable timeline divider
- Jobs A:C column now shows real assigned/completed counts
- Job grid "Tech" column shows assigned technician name
- API responses now include assignment data (assigned_tech_id/name on jobs, job counts on techs)
- Skill-filtered context menus with multi-select awareness
- Context menu shows batch operations when multiple items selected

***0.0.5***<br>
Complete frontend redesign — enterprise dispatch console
- AG Grid-powered split-pane layout (technicians top, jobs bottom)
- Draggable divider between panes
- Right-click context menus with skill-filtered tech assignment
- Clickable dashboard indicator bar (filters grids by status)
- Floating, draggable, resizable map window (Leaflet)
- Toast notifications on all dispatch actions
- Keyboard shortcuts (R = refresh, M = map, T = timeline, Esc = close)
- Dropped Tailwind — handwritten enterprise CSS with dark theme
- Expanded API client (all endpoints wired)
- Jazz-themed seed data

***0.0.4***<br>
Async backend migration + bug fixes
- SQLAlchemy async engine with asyncpg
- Fixed delete_technician, workload signature, reassign atomicity
- Fixed get_jobs_summary filter bug
- lazy="selectin" on all relationships
- Routing now uses current tech location over home base

***0.0.3***<br>
Project restructuring + frontend
- Fully backend-driven
- PostgreSQL over SQLite
- Map view via OpenStreetMap/Leaflet
- Vite + React + Tailwind frontend

***0.0.2***<br>
Started frontend
- FastAPI + React integration
- Technician + job CRUD via API
- Basic frontend displaying techs/jobs

***0.0.1***<br>
Initial commit
- Basic backend logic
- Proof of concept
</details>

## Roadmap

- [x] Drag-and-drop job assignment
- [x] Day picker with date-filtered views
- [x] Multi-select and batch operations
- [x] Tech timeline pane
- [x] Display filter window (time slot, job type, route criteria, tech)
- [x] Tech/staff search window (personnel)
- [x] Job search window (multi-criteria)
- [x] Map as real popup window (second monitor support)
- [x] Route criteria / management areas
- [x] Job evaluation (skill/route/time + distance)
- [x] Override warning on assignment mismatch
- [x] Automated dispatch (simulation engine with time-accelerated demo day)
- [x] Live updates (3s fragment polling; the v0.0.8 WebSocket was retired)
- [x] Mobile responsive UI
- [ ] Touch drag-and-drop (not yet ported to the HTMX console)
- [x] Frontend sim control bar (start/pause/resume/stop, speed selector, virtual clock)
- [x] Overrun row highlighting (yellow/red at estimated/1.5× duration)
- [x] ML routing strategy (embedded model — travel + predicted completion time)
- [ ] God View debug overlay (reveal tech modifiers: speed_factor, skill_bonuses)
- [ ] Job visual column (per-job evaluation mode on tech grid)
- [ ] Dark/light theme toggle
- [ ] Account system with role-based access
- [ ] Column state persistence per user
- [ ] Mobile technician PWA
- [x] Docker compose full stack
- [x] Hosted live demo

## Contributing

If you share the belief that simplicity empowers creativity, feel free to contribute.
- Submit a Pull Request
- Bug reports and feature requests

Please ensure your code follows the existing style.

