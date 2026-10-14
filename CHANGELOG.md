# Change Log

The latest version is in the [README](README.md#change-log).

## 0.0.8
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

## 0.0.7
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

## 0.0.6
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

## 0.0.5
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

## 0.0.4
Async backend migration + bug fixes
- SQLAlchemy async engine with asyncpg
- Fixed delete_technician, workload signature, reassign atomicity
- Fixed get_jobs_summary filter bug
- lazy="selectin" on all relationships
- Routing now uses current tech location over home base

## 0.0.3
Project restructuring + frontend
- Fully backend-driven
- PostgreSQL over SQLite
- Map view via OpenStreetMap/Leaflet
- Vite + React + Tailwind frontend

## 0.0.2
Started frontend
- FastAPI + React integration
- Technician + job CRUD via API
- Basic frontend displaying techs/jobs

## 0.0.1
Initial commit
- Basic backend logic
- Proof of concept
