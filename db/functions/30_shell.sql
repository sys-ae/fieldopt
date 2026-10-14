-- The dispatch console itself. Postgres renders the whole page: the shell plus the
-- fragments that used to be filled in by the browser (or, briefly, by nginx SSI).
-- nginx proxies / straight here and otherwise only serves static assets.
--
-- This file IS the page source — there is no web/index.html to edit. Keep the markup
-- readable: it is dollar-quoted, so single quotes inside it need no escaping.
create or replace function api.version()
returns text language sql immutable as $$
	select '0.0.9';
$$;

create or replace function api.shell()
returns "text/html" language sql stable as $fn$
	select $html$<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>FieldOpt — Dispatch</title>
	<link rel="icon" type="image/svg+xml" href="/favicon.svg">
	<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
	<link rel="apple-touch-icon" href="/apple-touch-icon.png">
	<link rel="stylesheet" href="/vendor/leaflet.css">
	<link rel="stylesheet" href="/app.css">
	<script src="/vendor/htmx.min.js"></script>
	<script src="/vendor/idiomorph-ext.min.js"></script>
	<script src="/vendor/leaflet.js" defer></script>
	<script>try { document.documentElement.dataset.theme = localStorage.getItem("fieldopt.theme") || "dark"; } catch {}</script>
</head>
<body hx-ext="morph">

<div class="app-shell">

	<!-- Row 1: Header -->
	<header class="header-bar">
		<div class="header-brand">
			<div class="header-brand-icon"></div>
			FieldOpt
			<span class="header-version mono">$html$ || api.version() || $html$</span>
		</div>
		<span class="header-real-clock mono" id="real-clock">--:--:--</span>

		<!-- Day picker -->
		<div class="day-picker">
			<button class="btn icon-btn" id="day-prev" title="Previous day" onclick="shiftDay(-1)">◂</button>
			<button class="btn btn--primary day-btn" id="day-label" onclick="toggleCalendar(event)">Demo Day</button>
			<button class="btn icon-btn" id="day-next" title="Next day" onclick="shiftDay(1)">▸</button>
		</div>

		<!-- Sim bar (demo only): rides the header row, wraps under it when space runs out -->
		<div class="sim-bar-row" id="sim-bar-wrap"
		     hx-get="/rpc/sim_bar" hx-trigger="every 3s, refreshAll from:body" hx-swap="innerHTML">$html$
			|| api.sim_bar()
			|| $html$</div>

		<div class="header-actions">
			<button class="btn icon-btn" id="btn-filter" title="Filter" onclick="openWindow('filter', 'Filter')">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1.5 2.5h13l-5 5.5v4l-3 1.5V8z"/></svg>
			</button>
			<button class="btn icon-btn" id="btn-personnel" title="Personnel" onclick="openWindow('personnel', 'Personnel')">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="5" r="2.5"/><path d="M3 14c0-2.8 2.2-5 5-5s5 2.2 5 5"/></svg>
			</button>
			<button class="btn icon-btn" id="btn-search" title="Job Search" onclick="openWindow('search', 'Job Search')">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="6.5" cy="6.5" r="4"/><path d="M10 10l4 4"/></svg>
			</button>
			<button class="btn icon-btn" id="btn-settings" title="Settings" onclick="openWindow('settings', 'Settings')">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 4h14M1 8h14M1 12h14"/><rect x="3" y="2.5" width="4" height="3" rx="0.5" fill="currentColor" stroke="none"/><rect x="8" y="6.5" width="5" height="3" rx="0.5" fill="currentColor" stroke="none"/><rect x="2" y="10.5" width="3" height="3" rx="0.5" fill="currentColor" stroke="none"/></svg>
			</button>
			<button class="btn icon-btn" id="btn-timeline" title="Toggle Timeline" onclick="toggleTimeline()">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 3.5h5M5 8h7.5M3 12.5h4"/><path d="M10 1v14" stroke-width="1" stroke-dasharray="1.5 1.5"/></svg>
			</button>
			<button class="btn icon-btn" id="btn-map" title="Toggle Map" onclick="toggleMapWindow()">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 3.5l4.5-2 5 2.5 4.5-2v11l-4.5 2-5-2.5-4.5 2z"/><path d="M5.5 1.5v11M10.5 4v11"/></svg>
			</button>
			<button class="btn icon-btn" title="Refresh" onclick="refreshAll()">
				<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M2.5 8a5.5 5.5 0 019.3-4M13.5 8a5.5 5.5 0 01-9.3 4"/><path d="M11.5 1v3h3M4.5 15v-3h-3"/></svg>
			</button>
			<button class="btn btn--warning icon-btn" title="Auto-Route" onclick="confirmAutoRoute()">
				<svg viewBox="0 0 16 16" fill="currentColor"><path d="M9.5 1L3 9h4.5L6.5 15 13 7H8.5z"/></svg>
			</button>
		</div>
	</header>

	<!-- Row 3: Dashboard counts -->
	<div class="dashboard-bar" id="dash-bar"
	     hx-get="/rpc/dash_bar" hx-trigger="every 3s, refreshAll from:body" hx-swap="morph:innerHTML">$html$
		|| api.dash_bar()
		|| $html$</div>

	<!-- Phone only: one pane at a time -->
	<nav class="pane-tabs">
		<button class="pane-tab active" data-pane="techs" onclick="showPane('techs')">Techs</button>
		<button class="pane-tab" data-pane="jobs" onclick="showPane('jobs')">Jobs</button>
		<button class="pane-tab" data-pane="timeline" onclick="showPane('timeline')">Timeline</button>
	</nav>

	<!-- Body: VERTICAL stack with resizable splitters -->
	<div class="stack" id="stack" data-pane="techs">

		<section class="pane pane-techs" id="pane-techs">
			<div class="pane-header">
				<span class="pane-title">Technicians</span>
				<span class="pane-count" id="tech-count">0</span>
				<span class="pane-sel-count" id="tech-sel-count"></span>
			</div>
			<div class="pane-body scroll-pres" id="tech-list"
			     hx-get="/rpc/tech_list" hx-trigger="every 3s, refreshAll from:body" hx-swap="morph:innerHTML">$html$
		|| api.tech_list()
		|| $html$</div>
		</section>

		<div class="row-splitter" data-resize="techs"></div>

		<section class="pane pane-jobs" id="pane-jobs">
			<div class="pane-header">
				<span class="pane-title">Jobs</span>
				<span class="pane-count" id="job-count">0</span>
				<span class="pane-sel-count" id="job-sel-count"></span>
			</div>
			<input type="hidden" name="p_status" value=""
			       hx-get="/rpc/job_table" hx-target="#job-table" hx-trigger="change" hx-swap="morph:innerHTML">
			<div class="pane-body scroll-pres" id="job-table"
			     hx-get="/rpc/job_table" hx-trigger="every 3s, refreshAll from:body" hx-swap="morph:innerHTML"
			     hx-include="[name='p_status']">$html$
		|| api.job_table()
		|| $html$</div>
		</section>

		<div class="row-splitter" data-resize="jobs"></div>

		<section class="pane pane-timeline" id="timeline-pane" hidden>
			<div class="pane-header">
				<span class="pane-title">Timeline</span>
				<span class="pane-count" id="timeline-sel-info"></span>
				<div class="pane-actions">
					<button class="btn" onclick="toggleTimeline()">Close</button>
				</div>
			</div>
			<div class="pane-body scroll-pres" id="timeline"
			     hx-get="/rpc/timeline" hx-trigger="every 3s, refreshAll from:body" hx-swap="morph:innerHTML"
			     hx-include="#tech-selection" hx-vals='js:{p_width: timelineWidth()}'>
				<div class="timeline-wrap"><em class="muted">Loading…</em></div>
			</div>
		</section>

	</div>
</div>

<input type="hidden" id="tech-selection" name="p_selected" value="">

<!-- Floating windows host + overlays -->
<div id="win-host"></div>
<div id="toast-host"></div>
<div id="modal-host"></div>
<div id="ctx-menu" class="ctx-menu" hidden></div>
<div id="drag-ghost" class="drag-ghost" hidden></div>

<script>
	// ── State ───────────────────────────────────────────────────────────────
	const selTechs = new Set();
	const selJobs = new Set();
	let lastTechClick = null;
	let lastJobClick = null;
	let mapWin = null;

	function refreshAll() { document.body.dispatchEvent(new Event("refreshAll")); }
	// ── PostgREST ──────────────────────────────────────────────────────────
	// Fragments and forms address /rpc/* directly; this is only for the handful of
	// calls that are not htmx-driven (drag-assign, context menus, map).
	const WINDOW_RPC = (key) =>
		key.startsWith("tech/") ? ["tech_detail", { p_tech_id: key.slice(5) }] :
		key.startsWith("job/")  ? ["job_detail",  { p_job_id:  key.slice(4) }] :
		[key + "_window", {}];
	async function rpc(name, params, method, accept) {
		if (Array.isArray(name)) { params = name[1]; name = name[0]; }
		params = params || {};
		accept = accept || "text/html";
		let url = "/rpc/" + name;
		const opts = { method: method || "GET", headers: { "Accept": accept } };
		if (opts.method === "GET") {
			const qs = new URLSearchParams(params).toString();
			if (qs) url += "?" + qs;
		} else {
			opts.headers["Content-Type"] = "application/json";
			opts.body = JSON.stringify(params);
		}
		return fetch(url, opts);
	}
	window.rpc = rpc;

	// The fragment functions return a text/html domain type, which PostgREST only serves
	// when the request asks for it; htmx's default Accept negotiates to JSON.
	document.body.addEventListener("htmx:configRequest", (e) => {
		e.detail.headers["Accept"] = "text/html";
	});


	// ── Pane counts (were server-rendered; now follow the swapped fragments) ─
	function updatePaneCounts() {
		const t = document.querySelectorAll("#tech-list [data-tech-id]").length;
		const j = document.querySelectorAll("#job-table [data-job-id]").length;
		document.getElementById("tech-count").textContent = t;
		document.getElementById("job-count").textContent = j;
	}
	// First paint arrives inline, and identical polls skip the swap, so count once now.
	updatePaneCounts();

	// ── Floating window manager (with localStorage persistence) ────────────
	const openWins = new Map(); // key -> { el, btn }
	let zCounter = 700;
	const WIN_KEY = (k) => "fieldopt.win." + k.replace(/\//g, "_");
	function loadWinState(key) {
		try { return JSON.parse(localStorage.getItem(WIN_KEY(key)) || "null"); } catch { return null; }
	}
	function saveWinState(key, w) {
		try {
			localStorage.setItem(WIN_KEY(key), JSON.stringify({
				left: w.style.left, top: w.style.top,
				width: w.style.width, height: w.style.height,
			}));
		} catch {}
	}

	// A window may hang off an edge, but enough of its title bar always stays on screen to
	// grab it back — while dragging, after the browser resizes, and when a position saved on
	// a larger screen is restored.
	function keepOnScreen(w) {
		const grab = 120, head = 36;
		const maxW = window.innerWidth, maxH = window.innerHeight;
		if (w.offsetWidth > maxW) w.style.width = maxW + "px";
		if (w.offsetHeight > maxH) w.style.height = maxH + "px";
		const left = Math.min(Math.max(w.offsetLeft, grab - w.offsetWidth), maxW - grab);
		const top = Math.min(Math.max(w.offsetTop, 0), maxH - head);
		w.style.left = left + "px";
		w.style.top = top + "px";
	}
	window.addEventListener("resize", () => openWins.forEach(({ el }) => keepOnScreen(el)));

	window.openWindow = async function(key, title) {
		if (openWins.has(key)) { closeWindow(key); return; }
		const btn = document.getElementById("btn-" + key.replace(/\/.*/, ""));
		if (btn) btn.classList.add("btn--primary");
		const w = document.createElement("div");
		w.className = "float-win";
		w.dataset.key = key;
		const saved = loadWinState(key);
		w.style.width  = saved?.width  || "560px";
		w.style.height = saved?.height || "480px";
		w.style.left   = saved?.left   || (80 + openWins.size * 28) + "px";
		w.style.top    = saved?.top    || (90 + openWins.size * 28) + "px";
		w.style.zIndex = ++zCounter;
		w.innerHTML = `
			<div class="float-win-head">
				<span class="float-win-title">${title}</span>
				<button class="float-win-close" onclick="closeWindow('${key}')">×</button>
			</div>
			<div class="float-win-body" id="win-${key}-content"><em class="muted" style="padding:20px;display:block;">Loading…</em></div>`;
		document.getElementById("win-host").appendChild(w);
		keepOnScreen(w);
		openWins.set(key, { el: w, btn });

		// Drag the window by header
		const head = w.querySelector(".float-win-head");
		let dragWin = null;
		head.addEventListener("mousedown", (e) => {
			if (e.target.closest(".float-win-close")) return;
			w.style.zIndex = ++zCounter;
			dragWin = { ox: e.clientX - w.offsetLeft, oy: e.clientY - w.offsetTop };
			e.preventDefault();
		});
		document.addEventListener("mousemove", (e) => {
			if (!dragWin) return;
			w.style.left = (e.clientX - dragWin.ox) + "px";
			w.style.top = (e.clientY - dragWin.oy) + "px";
			keepOnScreen(w);
		});
		document.addEventListener("mouseup", () => {
			if (dragWin) { saveWinState(key, w); }
			dragWin = null;
		});
		// Persist size on resize (corner grip)
		new ResizeObserver(() => saveWinState(key, w)).observe(w);
		w.addEventListener("mousedown", () => { w.style.zIndex = ++zCounter; });

		// Load content
		if (key === "map") {
			document.getElementById("win-map-content").innerHTML = '<iframe class="map-frame" src="/map.html" title="Map"></iframe>';
			return;
		}
		try {
			const r = await rpc(WINDOW_RPC(key));
			document.getElementById("win-" + key + "-content").innerHTML = await r.text();
			// Saved choices (scripts in innerHTML never run, so restore them here)
			w.querySelectorAll("select[data-pref]").forEach(el => {
				const v = localStorage.getItem(el.dataset.pref);
				if (v !== null) el.value = v;
			});
			if (window.htmx) htmx.process(w);
			if (window.attachAllResizers) attachAllResizers(w);
		} catch { document.getElementById("win-" + key + "-content").innerHTML = '<div class="win-empty">Failed to load.</div>'; }
	};

	window.closeWindow = function(key) {
		const w = openWins.get(key);
		if (!w) return;
		if (w.btn) w.btn.classList.remove("btn--primary");
		w.el.remove();
		openWins.delete(key);
	};

	// Filter window helpers
	window.applyMainFilter = function(name, value) {
		const sel = document.querySelector(`[name='${name}']`);
		if (sel) { sel.value = value; sel.dispatchEvent(new Event("change", { bubbles: true })); }
	};
	window.clearAllFilters = function() {
		applyMainFilter("p_status", "");
	};
	// Multi-select filter checkbox handlers (client-side row hide on job-table)
	window.applyFilterMulti = function() {
		const get = name => Array.from(document.querySelectorAll(`[name='f-${name}']:checked`)).map(c => c.value);
		const statuses = new Set(get("status"));
		const types = new Set(get("job_type"));
		const routes = new Set(get("route"));
		const techs = new Set(get("tech_id"));
		document.querySelectorAll("#job-table .job-row").forEach(r => {
			const st = r.dataset.jobStatus || "";
			const type = r.querySelector("td:nth-child(2)")?.textContent.trim() || "";
			const route = (r.querySelector("td.mono.route") || r.querySelector("td:nth-child(7)"))?.textContent.trim() || "";
			const techCell = r.querySelector("td:nth-child(4)")?.textContent.trim() || "—";
			const okStatus = statuses.size === 0 || statuses.has(st);
			const okType = types.size === 0 || types.has(type);
			const okRoute = routes.size === 0 || routes.has(route) || route === "—";
			const okTech = techs.size === 0 ||
				(techs.has("unassigned") && techCell === "—") ||
				Array.from(techs).some(tid => tid !== "unassigned" && techCell !== "—");
			r.style.display = (okStatus && okType && okRoute && okTech) ? "" : "none";
		});
	};
	window.filterCheckAll = function(group, state) {
		document.querySelectorAll(`[name='f-${group}']`).forEach(c => c.checked = state);
		applyFilterMulti();
	};
	window.filterResetAll = function() {
		document.querySelectorAll("[name^='f-']").forEach(c => c.checked = true);
		applyFilterMulti();
	};
	window.filterClearAll = function() {
		document.querySelectorAll("#job-table .job-row").forEach(r => r.style.display = "");
	};

	// Dash bar indicator click → filters Jobs grid by status
	window.toggleDashFilter = function(cell) {
		const filter = cell.dataset.filter;
		if (!filter) return;
		const [k, v] = filter.split("=");
		const wasActive = cell.classList.contains("active");
		document.querySelectorAll(".dash-cell[data-filter]").forEach(c => c.classList.remove("active"));
		const statusSel = document.querySelector("[name='p_status']");
		if (wasActive) {
			statusSel.value = "";
		} else {
			cell.classList.add("active");
			statusSel.value = v;
		}
		statusSel.dispatchEvent(new Event("change", { bubbles: true }));
	};

	// Search form clear
	window.clearSearchForm = function(btn) {
		const form = btn.closest("form");
		form.querySelectorAll("input, select").forEach(el => { el.value = ""; });
		form.requestSubmit();
	};

	// Personnel window search
	window.filterPersonnel = function(q) {
		q = (q || "").toLowerCase().trim();
		const rows = document.querySelectorAll(".personnel-row");
		let visible = 0;
		rows.forEach(r => {
			const hay = r.dataset.search || "";
			const match = !q || hay.includes(q);
			r.style.display = match ? "" : "none";
			if (match) visible++;
		});
		const c = document.getElementById("personnel-count");
		if (c) c.textContent = `${visible} / ${rows.length}`;
	};

	// Locate tech in main grid (from Personnel double-click)
	window.locateTech = function(techId) {
		const row = document.querySelector(`#tech-list [data-tech-id='${techId}']`);
		if (!row) return;
		selTechs.clear(); selTechs.add(String(techId));
		applySelectionVisuals(); updateSelCounts(); syncTechSelection();
		row.scrollIntoView({ behavior: "smooth", block: "center" });
	};

	// Refresh interval setter (persists to localStorage)
	window.setRefreshInterval = function(ms) {
		localStorage.setItem("fieldopt.refresh", ms);
		document.querySelectorAll("[hx-trigger*='every']").forEach(el => {
			const cur = el.getAttribute("hx-trigger");
			const next = ms > 0
				? cur.replace(/every \d+m?s/, `every ${ms}ms`)
				: cur.replace(/every \d+m?s,?\s*/, "");
			el.setAttribute("hx-trigger", next.trim() || "refreshAll from:body");
			if (window.htmx) htmx.process(el);
		});
		showToast(`Refresh: ${ms > 0 ? (ms/1000) + 's' : 'off'}`, "success");
	};
	// Apply saved refresh interval on load
	const _savedRefresh = parseInt(localStorage.getItem("fieldopt.refresh") || "3000", 10);
	if (_savedRefresh !== 3000) setTimeout(() => setRefreshInterval(_savedRefresh), 500);

	window.setTheme = function(t) {
		localStorage.setItem("fieldopt.theme", t);
		document.documentElement.dataset.theme = t;
	};

	// Density persisted
	const _savedDensity = localStorage.getItem("fieldopt.density");
	if (_savedDensity) document.body.dataset.density = _savedDensity;

	// ── Related-job highlight on tech selection ────────────────────────────
	function highlightRelatedJobs() {
		const selTechSet = selTechs;
		document.querySelectorAll(".job-row").forEach(row => {
			const techCell = row.querySelector("td:nth-child(4)")?.textContent.trim();
			let related = false;
			if (selTechSet.size > 0 && techCell && techCell !== "—") {
				selTechSet.forEach(tid => {
					const tRow = document.querySelector(`[data-tech-id='${tid}']`);
					if (tRow && tRow.dataset.techName === techCell) related = true;
				});
			}
			row.classList.toggle("related", related);
		});
	}
	// Hook into existing visuals update
	const _origApply = applySelectionVisuals;
	window.applySelectionVisuals = function() {
		_origApply();
		highlightRelatedJobs();
	};

	// ── Scroll preservation across HTMX swaps ──────────────────────────────
	// Polled fragments are usually byte-identical to the last one. Swapping anyway costs a
	// full morph plus resizer/selection/count passes every 3s, which is what makes hover
	// and click feel sticky. Compare first; skip the swap when nothing changed.
	const lastPayload = new Map();
	document.body.addEventListener("htmx:beforeSwap", (e) => {
		const t = e.detail.target;
		if (!t || !t.id) return;
		if (lastPayload.get(t.id) === e.detail.serverResponse) { e.detail.shouldSwap = false; return; }
		lastPayload.set(t.id, e.detail.serverResponse);
	});

	document.body.addEventListener("htmx:beforeSwap", (e) => {
		const t = e.detail.target;
		if (t.classList.contains("scroll-pres")) t.dataset.scrollY = t.scrollTop;
	});
	document.body.addEventListener("htmx:afterSwap", (e) => {
		const t = e.detail.target;
		if (t.classList.contains("scroll-pres") && t.dataset.scrollY) {
			t.scrollTop = parseInt(t.dataset.scrollY, 10);
		}
		applySelectionVisuals();
		updatePaneCounts();
	});

	// ── Sim state + real clock ─────────────────────────────────────────────
	function syncDemoLock() {
		const running = !!document.querySelector("#sim-bar .sim-state--simulated");
		document.body.classList.toggle("demo-locked", running);
	}

	// The bar is polled every 3s and the virtual clock advances in large steps, so the
	// displayed time is interpolated between polls — the smoothing the SSE stream used
	// to provide. Each poll re-syncs to the server value.
	let simSync = null;
	function syncSimClock() {
		const el = document.getElementById("sim-clock");
		const running = !!document.querySelector("#sim-bar .sim-state--simulated");
		const m = el ? (el.textContent || "").match(/^(\d{2}):(\d{2}):(\d{2})$/) : null;
		if (!el || !running || !m) { simSync = null; return; }
		const sel = document.querySelector("#sim-bar select[name='p_speed']");
		simSync = {
			at: Date.now(),
			secs: (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]),
			speed: sel ? (parseFloat(sel.value) || 1) : 1,
		};
	}
	function paintSimClock() {
		if (!simSync) return;
		const el = document.getElementById("sim-clock");
		if (!el) { simSync = null; return; }
		const t = Math.floor(simSync.secs + (Date.now() - simSync.at) / 1000 * simSync.speed) % 86400;
		const p = (n) => String(n).padStart(2, "0");
		el.textContent = `${p(Math.floor(t / 3600))}:${p(Math.floor(t / 60) % 60)}:${p(t % 60)}`;
	}
	setInterval(paintSimClock, 200);

	document.body.addEventListener("htmx:afterSwap", (e) => { syncDemoLock(); syncSimClock(); });
	function updateRealClock() {
		const el = document.getElementById("real-clock");
		if (!el) return;
		const d = new Date();
		const h12 = d.getHours() % 12 || 12;
		const mm = String(d.getMinutes()).padStart(2, "0");
		const ampm = d.getHours() >= 12 ? "PM" : "AM";
		el.textContent = `${h12}:${mm} ${ampm}`;
	}
	updateRealClock(); setInterval(updateRealClock, 1000);

	// ── Resizable splitters ─────────────────────────────────────────────────
	let resizing = null;
	document.addEventListener("mousedown", (e) => {
		const sp = e.target.closest(".row-splitter");
		if (!sp) return;
		resizing = { which: sp.dataset.resize, startY: e.clientY, el: sp };
		sp.classList.add("dragging");
		e.preventDefault();
	});
	document.addEventListener("mousemove", (e) => {
		if (!resizing) return;
		const stack = document.getElementById("stack");
		const rect = stack.getBoundingClientRect();
		const relY = e.clientY - rect.top;
		const pct = Math.max(10, Math.min(85, (relY / rect.height) * 100));
		if (resizing.which === "techs") {
			// Leave Jobs at least 80px above an open timeline.
			const tl = document.getElementById("timeline-pane");
			const room = tl.hidden ? 85 : ((rect.height - tl.getBoundingClientRect().height - 80) / rect.height) * 100;
			document.getElementById("pane-techs").style.flex = `0 0 ${Math.min(pct, room)}%`;
		} else if (resizing.which === "jobs") {
			// The timeline starts at this Y; Jobs (flex:1) takes whatever is left between,
			// so the Techs splitter only ever trades height between Techs and Jobs.
			pinTimeline(rect.bottom - e.clientY - 3, true);
		}
	});
	document.addEventListener("mouseup", () => {
		if (resizing) { resizing.el.classList.remove("dragging"); resizing = null; }
	});

	// ── Toast ───────────────────────────────────────────────────────────────
	function showToast(msg, kind = "success") {
		const host = document.getElementById("toast-host");
		const el = document.createElement("div");
		el.className = "toast toast--" + kind;
		el.textContent = msg;
		host.appendChild(el);
		setTimeout(() => el.remove(), 3500);
	}

	// ── Selection (Ctrl/Cmd-click toggle, Shift-click range, Ctrl+A all) ───
	function getRowsInDom(scope) {
		return Array.from(document.querySelectorAll(`#${scope}-list [data-tech-id], #${scope}-table [data-job-id]`));
	}
	function setSelection(scope, ids) {
		const set = scope === "tech" ? selTechs : selJobs;
		set.clear();
		ids.forEach(i => set.add(String(i)));
		applySelectionVisuals();
		updateSelCounts();
		if (scope === "tech") syncTechSelection();
	}
	function toggleId(scope, id, e, listEl) {
		const set = scope === "tech" ? selTechs : selJobs;
		const lastVar = scope === "tech" ? "lastTechClick" : "lastJobClick";
		const all = Array.from(listEl.querySelectorAll(scope === "tech" ? "[data-tech-id]" : "[data-job-id]"))
		                .map(r => r.dataset[scope + "Id"]);
		const idStr = String(id);
		if (e.shiftKey && window[lastVar]) {
			const a = all.indexOf(window[lastVar]); const b = all.indexOf(idStr);
			if (a >= 0 && b >= 0) { const [s, x] = a < b ? [a, b] : [b, a]; all.slice(s, x + 1).forEach(i => set.add(i)); }
		} else if (e.metaKey || e.ctrlKey) {
			set.has(idStr) ? set.delete(idStr) : set.add(idStr);
		} else {
			set.clear(); set.add(idStr);
		}
		window[lastVar] = idStr;
		applySelectionVisuals();
		updateSelCounts();
		if (scope === "tech") syncTechSelection();
	}
	function applySelectionVisuals() {
		document.querySelectorAll("[data-tech-id]").forEach(r => r.classList.toggle("selected", selTechs.has(r.dataset.techId)));
		document.querySelectorAll("[data-job-id]").forEach(r => r.classList.toggle("selected", selJobs.has(r.dataset.jobId)));
	}
	function updateSelCounts() {
		document.getElementById("tech-sel-count").textContent = selTechs.size ? `(${selTechs.size} selected)` : "";
		document.getElementById("job-sel-count").textContent = selJobs.size ? `(${selJobs.size} selected)` : "";
		document.getElementById("timeline-sel-info").textContent = selTechs.size ? `${selTechs.size} tech selected` : "all techs";
	}
	function syncTechSelection() {
		document.getElementById("tech-selection").value = Array.from(selTechs).join(",");
		// Refresh timeline so it filters by selection
		const tl = document.getElementById("timeline-pane");
		if (tl && !tl.hidden) htmx.trigger("#timeline", "refreshAll");
	}

	const touchUI = matchMedia("(pointer: coarse)");
	document.addEventListener("click", (e) => {
		const techRow = e.target.closest("[data-tech-id]");
		const jobRow = e.target.closest("[data-job-id]");
		if (techRow) toggleId("tech", techRow.dataset.techId, e, document.getElementById("tech-list"));
		else if (jobRow) toggleId("job", jobRow.dataset.jobId, e, document.getElementById("job-table"));
		// Touch has no right-click or double-click, so a tap opens the row's menu. Deferred so
		// the close-on-outside-click handler below does not shut it in the same event.
		if (touchUI.matches && (techRow || jobRow)) {
			setTimeout(() => techRow ? showTechMenu(e, techRow) : showJobMenu(e, jobRow), 0);
		}
	});
	document.addEventListener("keydown", (e) => {
		// Don't intercept typing in inputs
		if (e.target.matches("input, textarea, select")) return;

		if ((e.metaKey || e.ctrlKey) && e.key === "a") {
			e.preventDefault();
			const focusedJobs = document.querySelector("#job-table:hover");
			const focusedTechs = document.querySelector("#tech-list:hover");
			if (focusedTechs || (!focusedJobs && document.activeElement.closest("#tech-list"))) {
				const ids = Array.from(document.querySelectorAll("[data-tech-id]")).map(r => r.dataset.techId);
				setSelection("tech", ids);
			} else {
				const ids = Array.from(document.querySelectorAll("[data-job-id]")).map(r => r.dataset.jobId);
				setSelection("job", ids);
			}
			return;
		}
		if (e.key === "Escape") {
			selTechs.clear(); selJobs.clear(); applySelectionVisuals(); updateSelCounts(); syncTechSelection();
			document.getElementById("modal-host").innerHTML = "";
			ctxMenu.hidden = true;
			return;
		}

		// Leave the browser's own Cmd/Ctrl/Alt shortcuts (reload, find…) alone.
		if (e.metaKey || e.ctrlKey || e.altKey) return;
		const k = e.key.toLowerCase();
		if (k === "r") { refreshAll(); return; }                               // Refresh
		if (k === "/") { e.preventDefault(); openWindow("search", "Job Search"); return; }
		if (k === "f") { openWindow("filter", "Filter"); return; }
		if (k === "p") { openWindow("personnel", "Personnel"); return; }

		// Job action shortcuts (only when jobs selected)
		if (selJobs.size === 0) return;
		const ids = Array.from(selJobs);
		if (k === "d") { ids.forEach(i => jobAction("complete", i)); }      // Done
		else if (k === "c") { ids.forEach(i => jobAction("cancel", i)); }   // Cancel
		else if (k === "h") { ids.forEach(i => jobAction("hold", i)); }     // Hold
		else if (k === "s") { ids.forEach(i => jobAction("start", i)); }    // Start
		else if (k === "u") { ids.forEach(i => unassignJob(i, false)); }    // Unassign
	});

	// ── Timeline toggle ─────────────────────────────────────────────────────
	// The timeline keeps a fixed height: the last one dragged to, remembered across
	// close/reopen and reloads (a third of the stack until then). Clamped so Jobs keeps at
	// least 80px; the saved height is re-applied when the window size changes.
	function pinTimeline(h, save) {
		const stack = document.getElementById("stack");
		const techsH = document.getElementById("pane-techs").getBoundingClientRect().height;
		h = Math.round(Math.max(100, Math.min(stack.clientHeight - techsH - 80, h)));
		document.getElementById("timeline-pane").style.flex = `0 0 ${h}px`;
		if (save) try { localStorage.setItem("fieldopt.timelineH", h); } catch {}
	}
	function savedTimelineH() {
		let h = NaN;
		try { h = parseInt(localStorage.getItem("fieldopt.timelineH"), 10); } catch {}
		return h > 0 ? h : document.getElementById("stack").clientHeight / 3;
	}
	window.toggleTimeline = function() {
		const p = document.getElementById("timeline-pane");
		const btn = document.getElementById("btn-timeline");
		p.hidden = !p.hidden;
		btn.classList.toggle("btn--primary", !p.hidden);
		if (!p.hidden) {
			pinTimeline(savedTimelineH(), false);
			htmx.trigger("#timeline", "refreshAll");
		}
	};

	// The server draws the timeline at the pane's width; redraw when that changes.
	window.timelineWidth = () => Math.max(0, document.getElementById("timeline").clientWidth - 24);
	let _tlResize;
	window.addEventListener("resize", () => {
		clearTimeout(_tlResize);
		_tlResize = setTimeout(() => {
			if (!document.getElementById("timeline-pane").hidden) pinTimeline(savedTimelineH(), false);
			htmx.trigger("#timeline", "refreshAll");
		}, 200);
	});

	// ── Phone pane tabs ─────────────────────────────────────────────────────
	window.showPane = function(name) {
		document.getElementById("stack").dataset.pane = name;
		document.querySelectorAll(".pane-tab").forEach(b => b.classList.toggle("active", b.dataset.pane === name));
		if (name !== "timeline") return;
		if (document.getElementById("timeline-pane").hidden) toggleTimeline();
		else htmx.trigger("#timeline", "refreshAll");
	};

	// ── Map window toggle ───────────────────────────────────────────────────
	// One map at a time. Small screens (where windows go full screen) get it in-app like
	// Personnel or Search; larger ones get a separate browser window, falling back to the
	// in-app one when pop-ups are blocked. Resizing never opens a second map.
	const smallScreen = matchMedia("(max-width: 768px), (max-height: 500px) and (orientation: landscape)");
	window.toggleMapWindow = function() {
		const btn = document.getElementById("btn-map");
		if (openWins.has("map")) { closeWindow("map"); return; }
		if (mapWin && !mapWin.closed) {
			mapWin.close();
			mapWin = null;
			btn.classList.remove("btn--primary");
			return;
		}
		if (!smallScreen.matches) mapWin = window.open("/map.html", "fieldopt-map", "width=960,height=720,menubar=no,toolbar=no");
		if (!mapWin) { openWindow("map", "Map"); return; }
		btn.classList.add("btn--primary");
		const poll = setInterval(() => {
			if (!mapWin || mapWin.closed) { btn.classList.remove("btn--primary"); clearInterval(poll); mapWin = null; }
		}, 500);
	};

	// ── Drag (mouse-event based — OG style, no HTML5 drag) ─────────────────
	const ghost = document.getElementById("drag-ghost");
	let dragState = null;       // {jobId, jobNumber, startX, startY} or null
	let dragActive = false;     // true once movement threshold crossed
	let lastHover = null;

	document.addEventListener("mousedown", (e) => {
		if (e.button !== 0) return;
		const row = e.target.closest(".job-row");
		if (!row) return;
		if (e.target.closest(".ctx-menu, .modal-backdrop")) return;
		dragState = {
			jobId: row.dataset.jobId,
			jobNumber: row.dataset.jobNumber,
			startX: e.clientX,
			startY: e.clientY,
		};
		e.preventDefault();  // suppress text selection start
	});
	document.addEventListener("selectstart", (e) => {
		if (dragState || dragActive) e.preventDefault();
	});

	document.addEventListener("mousemove", (e) => {
		if (!dragState) return;
		if (!dragActive) {
			const dx = e.clientX - dragState.startX;
			const dy = e.clientY - dragState.startY;
			if (Math.sqrt(dx*dx + dy*dy) < 5) return;
			dragActive = true;
			document.body.classList.add("dragging-active");
			// Promote selection to include this job if not already
			if (!selJobs.has(dragState.jobId)) {
				selJobs.clear();
				selJobs.add(dragState.jobId);
				applySelectionVisuals();
				updateSelCounts();
			}
			ghost.textContent = selJobs.size > 1
				? `${selJobs.size} jobs`
				: "Job #" + dragState.jobNumber;
			ghost.hidden = false;
		}
		ghost.style.left = (e.clientX + 12) + "px";
		ghost.style.top = (e.clientY + 12) + "px";

		const target = document.elementFromPoint(e.clientX, e.clientY);
		const tech = target ? target.closest("[data-tech-id]") : null;
		if (tech !== lastHover) {
			if (lastHover) lastHover.classList.remove("drop-target-hover");
			if (tech) tech.classList.add("drop-target-hover");
			lastHover = tech;
		}
	});

	document.addEventListener("mouseup", async (e) => {
		if (!dragState) return;
		const wasActive = dragActive;
		const state = dragState;
		dragState = null;
		dragActive = false;
		document.body.classList.remove("dragging-active");
		ghost.hidden = true;
		if (lastHover) { lastHover.classList.remove("drop-target-hover"); }

		if (!wasActive) return;  // pure click, not a drag

		const target = document.elementFromPoint(e.clientX, e.clientY);
		const techRow = target ? target.closest("[data-tech-id]") : null;
		lastHover = null;
		if (!techRow) return;

		if (document.body.classList.contains("demo-locked")) {
			showToast("Stop the demo to assign jobs", "warning"); return;
		}
		const techId = techRow.dataset.techId;
		const techName = techRow.dataset.techName || ("Tech " + techId);
		const jobIds = Array.from(selJobs);
		if (jobIds.length > 1) {
			showConfirm(`Assign ${jobIds.length} jobs to ${techName}?`, async () => {
				for (const jid of jobIds) await assignOne(jid, techId);
				refreshAll();
			});
		} else {
			await assignOne(state.jobId, techId);
			refreshAll();
		}
	});

	async function assignOne(jobId, techId) {
		try {
			const resp = await rpc("assign", { p_job_id: jobId, p_tech_id: techId }, "POST");
			const html = await resp.text();
			// Parse response and manually move OOB pieces into their hosts.
			// (htmx.process does not perform OOB swaps for non-htmx fetches.)
			const tmp = document.createElement("template");
			tmp.innerHTML = html.trim();
			const frag = tmp.content;
			const newModal = frag.querySelector("#modal-host");
			if (newModal) {
				document.getElementById("modal-host").replaceWith(newModal);
				if (window.htmx) htmx.process(newModal);
			}
			const newToasts = frag.querySelectorAll("#toast-host .toast, .toast");
			newToasts.forEach(t => document.getElementById("toast-host").appendChild(t));
		} catch (err) { showToast("Assign failed", "error"); }
	}

	// ── Confirm modal helper ────────────────────────────────────────────────
	function showConfirm(msg, onYes) {
		const host = document.getElementById("modal-host");
		host.innerHTML = `
			<div class="modal-backdrop" id="confirm-bd">
				<div class="modal">
					<h3>Confirm</h3>
					<p>${msg}</p>
					<div class="modal-actions">
						<button class="btn" id="confirm-no">Cancel</button>
						<button class="btn btn--warning" id="confirm-yes">Confirm</button>
					</div>
				</div>
			</div>`;
		document.getElementById("confirm-no").onclick = () => host.innerHTML = "";
		document.getElementById("confirm-bd").onclick = (e) => { if (e.target.id === "confirm-bd") host.innerHTML = ""; };
		document.getElementById("confirm-yes").onclick = () => { host.innerHTML = ""; onYes(); };
	}

	window.confirmAutoRoute = function() {
		if (document.body.classList.contains("demo-locked")) {
			showToast("Stop the demo to auto-route", "warning"); return;
		}
		showConfirm("Auto-route all pending jobs? ML will assign best tech per job.", async () => {
			try {
				const today = new Date().toISOString().slice(0, 10);
				const r = await rpc("auto_route", { p_target_date: today }, "POST", "application/json");
				const d = await r.json();
				showToast(`Routed ${d.jobs_assigned || 0} jobs${d.jobs_unassigned ? ` · ${d.jobs_unassigned} unassigned` : ""}`, "success");
				refreshAll();
			} catch { showToast("Auto-route failed", "error"); }
		});
	};

	// ── Context menus (OG style) ────────────────────────────────────────────
	const ctxMenu = document.getElementById("ctx-menu");
	function positionMenu(e) {
		ctxMenu.style.left = e.clientX + "px";
		ctxMenu.style.top = e.clientY + "px";
		ctxMenu.hidden = false;
		// Reflow + keep on-screen
		requestAnimationFrame(() => {
			const r = ctxMenu.getBoundingClientRect();
			if (r.right > window.innerWidth) ctxMenu.style.left = (window.innerWidth - r.width - 4) + "px";
			if (r.bottom > window.innerHeight) ctxMenu.style.top = (window.innerHeight - r.height - 4) + "px";
		});
	}

	window.showJobMenu = async function(e, row) {
		const jobId = row.dataset.jobId;
		const jobNumber = row.dataset.jobNumber;
		const customer = row.dataset.jobCustomer;
		const status = row.dataset.jobStatus;
		const multi = selJobs.size > 1 && selJobs.has(jobId);
		const terminal = status === "completed" || status === "cancelled";
		const header = multi
			? `<div class="ctx-menu-header">${selJobs.size} jobs selected</div>`
			: `<div class="ctx-menu-header">Job #${jobNumber} — ${customer}</div>`;
		ctxMenu.innerHTML = `
			${header}
			<div class="ctx-menu-sep"></div>
			<button class="ctx-menu-item" onclick="menuDetails('job', ${jobId})">Details</button>
			<div class="ctx-menu-sep"></div>
			<div class="ctx-menu-item ctx-menu-item--parent" onmouseenter="showAssignSubmenu(${jobId}, ${multi})" onmouseleave="hideAssignSubmenu()"
			     onclick="if (!event.target.closest('.ctx-submenu')) showAssignSubmenu(${jobId}, ${multi})">
				${multi ? `Assign ${selJobs.size} jobs to` : (status === "assigned" || status === "in_progress" ? "Reassign to" : "Assign to")}
				<span class="ctx-arrow">▸</span>
				<div class="ctx-submenu" id="assign-submenu" hidden></div>
			</div>
			<div class="ctx-menu-sep"></div>
			<div class="ctx-menu-label">Status</div>
			<button class="ctx-menu-item" ${terminal ? "disabled" : ""} onclick="jobAction('start', ${jobId})">
				<span class="ctx-dot ctx-dot--success"></span>Start
			</button>
			<button class="ctx-menu-item" ${terminal ? "disabled" : ""} onclick="jobAction('complete', ${jobId})">
				<span class="ctx-dot ctx-dot--info"></span>Complete
			</button>
			<button class="ctx-menu-item" onclick="jobAction('hold', ${jobId})">
				<span class="ctx-dot ctx-dot--purple"></span>Hold
			</button>
			<button class="ctx-menu-item ctx-menu-item--danger" onclick="jobAction('cancel', ${jobId})">
				<span class="ctx-dot ctx-dot--danger"></span>Cancel
			</button>
			<div class="ctx-menu-sep"></div>
			<button class="ctx-menu-item" onclick="unassignJob(${multi ? '0' : jobId}, ${multi})">
				${multi ? `Unassign ${selJobs.size} jobs` : "Unassign"}
			</button>
		`;
		positionMenu(e);
	};

	window.showAssignSubmenu = async function(jobId, multi) {
		const sub = document.getElementById("assign-submenu");
		if (!sub) return;
		sub.hidden = false;
		sub.innerHTML = '<div class="ctx-menu-label">Loading…</div>';
		try {
			const r = await rpc("qualified_techs", { p_job_id: jobId }, "GET", "application/json");
			const d = await r.json();
			const renderTech = (t, disabled) => `
				<button class="ctx-menu-item" ${disabled ? 'style="opacity:0.5"' : ''}
				        onclick="assignFromMenu(${jobId}, ${t.id}, ${multi})">
					<span class="ctx-dot ctx-dot--${t.status === 'available' ? 'success' : t.status === 'en_route' ? 'warning' : t.status === 'on_job' ? 'info' : 'muted'}"></span>
					${t.name}${t.missing.length ? ` <span style="color:var(--color-danger);font-size:10px;">(✗ ${t.missing.join(', ')})</span>` : ''}
				</button>`;
			let html = "";
			if (d.qualified.length) {
				html += '<div class="ctx-menu-label">Qualified</div>';
				html += d.qualified.map(t => renderTech(t, false)).join("");
			}
			if (d.unqualified.length) {
				if (d.qualified.length) html += '<div class="ctx-menu-sep"></div>';
				html += '<div class="ctx-menu-label">Missing skills</div>';
				html += d.unqualified.map(t => renderTech(t, true)).join("");
			}
			if (!d.qualified.length && !d.unqualified.length) {
				html = '<div class="ctx-menu-empty">No techs on shift.</div>';
			}
			sub.innerHTML = html;
		} catch {
			sub.innerHTML = '<div class="ctx-menu-empty">Failed to load.</div>';
		}
	};
	window.hideAssignSubmenu = function() {
		// Delay hide so user can move into submenu
		setTimeout(() => {
			const sub = document.getElementById("assign-submenu");
			if (sub && !sub.matches(":hover") && !sub.parentElement?.matches(":hover")) sub.hidden = true;
		}, 200);
	};
	window.assignFromMenu = async function(jobId, techId, multi) {
		ctxMenu.hidden = true;
		if (document.body.classList.contains("demo-locked")) {
			showToast("Stop the demo to assign", "warning"); return;
		}
		const ids = multi ? Array.from(selJobs) : [jobId];
		for (const id of ids) await assignOne(id, techId);
		refreshAll();
	};

	window.showTechMenu = function(e, row) {
		const techId = row.dataset.techId;
		const techName = row.dataset.techName;
		const multi = selTechs.size > 1 && selTechs.has(techId);
		const header = multi
			? `<div class="ctx-menu-header">${selTechs.size} techs selected</div>`
			: `<div class="ctx-menu-header">Tech ${techName}</div>`;
		ctxMenu.innerHTML = `
			${header}
			<div class="ctx-menu-sep"></div>
			<button class="ctx-menu-item" onclick="menuDetails('tech', ${techId})">Details</button>
			<div class="ctx-menu-sep"></div>
			<div class="ctx-menu-label">${multi ? "Set All Status" : "Set Status"}</div>
			<button class="ctx-menu-item" onclick="techAction('available', ${techId}, ${multi})">
				<span class="ctx-dot ctx-dot--success"></span>Available
			</button>
			<button class="ctx-menu-item" onclick="techAction('on_break', ${techId}, ${multi})">
				<span class="ctx-dot ctx-dot--warning"></span>On Break
			</button>
			<button class="ctx-menu-item" onclick="techAction('off_duty', ${techId}, ${multi})">
				<span class="ctx-dot ctx-dot--muted"></span>Off Duty
			</button>
		`;
		positionMenu(e);
	};

	document.addEventListener("click", (e) => {
		if (!ctxMenu.contains(e.target)) ctxMenu.hidden = true;
	});

	// The same detail windows a double-click opens; names come from the row so quotes in
	// them never reach an inline handler.
	window.menuDetails = function(kind, id) {
		ctxMenu.hidden = true;
		const row = document.querySelector(`[data-${kind}-id="${id}"]`);
		if (kind === "job") openWindow("job/" + id, "Job #" + (row ? row.dataset.jobNumber : id));
		else openWindow("tech/" + id, row ? row.dataset.techName : "Tech");
	};

	window.jobAction = async function(action, jobId) {
		ctxMenu.hidden = true;
		const ids = (selJobs.size > 1 && selJobs.has(String(jobId))) ? Array.from(selJobs) : [jobId];
		try {
			for (const id of ids) {
				await rpc("job_action", { p_job_id: id, p_action: action }, "POST");
			}
			refreshAll();
		} catch (err) { showToast("Action failed", "error"); }
	};

	window.unassignJob = async function(jobId, multi) {
		ctxMenu.hidden = true;
		const ids = multi ? Array.from(selJobs) : [jobId];
		for (const id of ids) {
			await rpc("unassign", { p_job_id: id }, "POST");
		}
		refreshAll();
	};

	window.techAction = async function(status, techId, multi) {
		ctxMenu.hidden = true;
		const ids = multi ? Array.from(selTechs) : [techId];
		for (const id of ids) {
			try {
				await rpc("tech_set_status", { p_tech_id: id, p_status: status }, "POST");
			} catch {}
		}
		refreshAll();
	};

	// ── Column resize (manual, vanilla — no AG Grid) ────────────────────────
	function _gridKey(table) {
		if (table.classList.contains("tech-grid")) return "tech";
		if (table.classList.contains("job-grid")) return "job";
		if (table.id === "personnel-table") return "personnel";
		return table.id || "grid";
	}
	function attachColumnResizers(table) {
		const key = "fieldopt.cols." + _gridKey(table);
		const ths = table.querySelectorAll("thead th");
		if (!ths.length) return;

		let cg = table.querySelector("colgroup");
		if (!cg || cg.children.length !== ths.length) {
			if (cg) cg.remove();
			cg = document.createElement("colgroup");
			ths.forEach(() => cg.appendChild(document.createElement("col")));
			table.insertBefore(cg, table.firstChild);
		}
		const cols = cg.querySelectorAll("col");

		let saved = {};
		try { saved = JSON.parse(localStorage.getItem(key) || "{}"); } catch {}
		cols.forEach((c, i) => { if (saved[i]) c.style.width = saved[i]; });

		ths.forEach((th, i) => {
			if (th.querySelector(".col-resizer")) return;
			const r = document.createElement("div");
			r.className = "col-resizer";
			r.addEventListener("mousedown", (e) => {
				e.preventDefault(); e.stopPropagation();
				const startX = e.clientX;
				const startW = th.getBoundingClientRect().width;
				document.body.style.cursor = "col-resize";
				const onMove = (ev) => {
					const w = Math.max(40, startW + ev.clientX - startX);
					cols[i].style.width = w + "px";
				};
				const onUp = () => {
					document.removeEventListener("mousemove", onMove);
					document.removeEventListener("mouseup", onUp);
					document.body.style.cursor = "";
					const widths = {};
					cols.forEach((c, idx) => { if (c.style.width) widths[idx] = c.style.width; });
					try { localStorage.setItem(key, JSON.stringify(widths)); } catch {}
				};
				document.addEventListener("mousemove", onMove);
				document.addEventListener("mouseup", onUp);
			});
			th.appendChild(r);
		});
	}
	// ── Column sort + reorder ───────────────────────────────────────────────
	// Both are view state, not data: the grids are re-rendered by the server every 3s, so
	// the chosen order and sort are stored per grid and re-applied after each swap.
	const _gridState = {};
	function gridState(table) {
		const k = _gridKey(table);
		if (!_gridState[k]) {
			let saved = null;
			try { saved = JSON.parse(localStorage.getItem("fieldopt.grid." + k) || "null"); } catch {}
			_gridState[k] = saved || { sort: null, order: null };
		}
		return _gridState[k];
	}
	function saveGridState(table) {
		try {
			localStorage.setItem("fieldopt.grid." + _gridKey(table), JSON.stringify(gridState(table)));
		} catch {}
	}

	function applyColumnOrder(table) {
		const st = gridState(table);
		const ths = Array.from(table.querySelectorAll("thead th"));
		if (!st.order || st.order.length !== ths.length) return;
		// Nothing to do when the DOM already matches the stored order.
		if (st.order.every((src, i) => ths[i].dataset.colId === String(src))) return;
		const rows = [table.querySelector("thead tr")].concat(
			Array.from(table.querySelectorAll("tbody tr")));
		rows.forEach((row) => {
			if (!row) return;
			const cells = Array.from(row.children);
			if (cells.length !== st.order.length) return;
			st.order.forEach((src) => row.appendChild(cells[src]));
		});
	}

	function applySort(table) {
		const st = gridState(table);
		if (!st.sort) return;
		const tbody = table.querySelector("tbody");
		if (!tbody) return;
		const rows = Array.from(tbody.rows).filter(r => r.cells.length > st.sort.i);
		if (rows.length < 2) return;
		const dir = st.sort.dir === "desc" ? -1 : 1;
		const val = (r) => (r.cells[st.sort.i].textContent || "").trim();
		const num = rows.every(r => val(r) === "" || val(r) === "—" || !isNaN(parseFloat(val(r))));
		rows.sort((a, b) => {
			const x = val(a), y = val(b);
			if (num) return dir * ((parseFloat(x) || 0) - (parseFloat(y) || 0));
			return dir * x.localeCompare(y, undefined, { numeric: true });
		});
		rows.forEach(r => tbody.appendChild(r));
	}

	function markSortHeaders(table) {
		const st = gridState(table);
		table.querySelectorAll("thead th").forEach((th, i) => {
			th.classList.toggle("sorted-asc", !!st.sort && st.sort.i === i && st.sort.dir === "asc");
			th.classList.toggle("sorted-desc", !!st.sort && st.sort.i === i && st.sort.dir === "desc");
		});
	}

	function attachHeaderBehaviour(table) {
		const ths = Array.from(table.querySelectorAll("thead th"));
		ths.forEach((th, i) => {
			if (th.dataset.colId === undefined) th.dataset.colId = String(i);
			if (th.dataset.hdrBound) return;
			th.dataset.hdrBound = "1";
			th.draggable = true;

			// Click sorts: asc -> desc -> off.
			th.addEventListener("click", (e) => {
				if (e.target.closest(".col-resizer") || th.dataset.dragging) return;
				const st = gridState(table);
				const idx = Array.from(table.querySelectorAll("thead th")).indexOf(th);
				st.sort = (!st.sort || st.sort.i !== idx) ? { i: idx, dir: "asc" }
					: st.sort.dir === "asc" ? { i: idx, dir: "desc" } : null;
				saveGridState(table);
				applySort(table);
				markSortHeaders(table);
			});

			// Drag reorders.
			th.addEventListener("dragstart", (e) => {
				th.dataset.dragging = "1";
				e.dataTransfer.effectAllowed = "move";
				e.dataTransfer.setData("text/plain",
					String(Array.from(table.querySelectorAll("thead th")).indexOf(th)));
			});
			th.addEventListener("dragend", () => { delete th.dataset.dragging; th.classList.remove("col-drop"); });
			th.addEventListener("dragover", (e) => { e.preventDefault(); th.classList.add("col-drop"); });
			th.addEventListener("dragleave", () => th.classList.remove("col-drop"));
			th.addEventListener("drop", (e) => {
				e.preventDefault();
				th.classList.remove("col-drop");
				const from = parseInt(e.dataTransfer.getData("text/plain"), 10);
				const to = Array.from(table.querySelectorAll("thead th")).indexOf(th);
				if (isNaN(from) || from === to) return;
				const cur = Array.from(table.querySelectorAll("thead th")).map(h => parseInt(h.dataset.colId, 10));
				cur.splice(to, 0, cur.splice(from, 1)[0]);
				const st = gridState(table);
				st.order = cur;
				// Column widths are positional, so they no longer describe these columns.
				try { localStorage.removeItem("fieldopt.cols." + _gridKey(table)); } catch {}
				const cg = table.querySelector("colgroup");
				if (cg) cg.remove();
				saveGridState(table);
				applyColumnOrder(table);
				attachColumnResizers(table);
				markSortHeaders(table);
			});
		});
	}

	function attachAllResizers(root) {
		(root || document).querySelectorAll("table.grid").forEach((table) => {
			applyColumnOrder(table);
			applySort(table);
			attachHeaderBehaviour(table);
			markSortHeaders(table);
			attachColumnResizers(table);
		});
	}
	document.body.addEventListener("htmx:afterSwap", (e) => attachAllResizers(e.detail.target));
	document.addEventListener("DOMContentLoaded", () => attachAllResizers());
	attachAllResizers();
</script>
</body>
</html>
$html$;
$fn$;

grant execute on function api.version() to web_anon;
grant execute on function api.shell() to web_anon;
