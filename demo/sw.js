// Stands in for nginx + PostgREST: /console and /rpc/* go to the page that holds the database.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (e) => {
	const u = new URL(e.request.url);
	if (u.origin !== location.origin) return;
	if (u.pathname === "/console" || u.pathname.startsWith("/rpc/")) e.respondWith(forward(e.request, u));
});

async function host() {
	const all = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
	return all.find((c) => ["/", "/index.html"].includes(new URL(c.url).pathname));
}

async function forward(req, u) {
	const c = await host();
	if (!c) return new Response("The demo database is not running. Open the demo home page first.", { status: 503 });
	const ch = new MessageChannel();
	const reply = new Promise((r) => { ch.port1.onmessage = (e) => r(e.data); });
	c.postMessage({
		path: u.pathname,
		query: u.search,
		method: req.method,
		type: req.headers.get("content-type") || "",
		body: req.method === "GET" ? "" : await req.text(),
	}, [ch.port2]);
	const res = await reply;
	return new Response(res.body, { status: res.status, headers: res.headers });
}
