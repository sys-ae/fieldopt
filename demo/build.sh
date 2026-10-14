#!/bin/sh
# demo/build.sh — build the in-browser demo (demo.fieldopt.dev) into demo/dist.
# The console runs on PGlite (Postgres compiled to WebAssembly) with the same SQL as a
# server install, minus pg_cron: the page ticks the clock itself.
#   local preview: sh demo/build.sh && python3 -m http.server 8090 --directory demo/dist
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/demo/dist"
CACHE="$ROOT/demo/.cache"

# PGlite is fetched at build time, never committed, and checked against the registry's
# published integrity for this exact version.
PGLITE_VERSION=0.5.9
PGLITE_SHA512=GoQTRMZ/o4J3sMW4mLDtDFGNOm1xy5oH+iHDALWll3uERY6OF4BSnL1t7FZH2Mlw+RPceDBlFJgSaecO73c4EA==
tgz="$CACHE/pglite-$PGLITE_VERSION.tgz"
mkdir -p "$CACHE"
[ -f "$tgz" ] || curl -fsSL -o "$tgz" "https://registry.npmjs.org/@electric-sql/pglite/-/pglite-$PGLITE_VERSION.tgz"
if [ "$(openssl dgst -sha512 -binary "$tgz" | openssl base64 -A)" != "$PGLITE_SHA512" ]; then
	rm -f "$tgz"
	echo "PGlite $PGLITE_VERSION failed its integrity check — not building"
	exit 1
fi
pkg="$CACHE/pglite-$PGLITE_VERSION"
[ -d "$pkg" ] || { mkdir -p "$pkg" && tar -xzf "$tgz" -C "$pkg"; }
pg="$pkg/package/dist"

rm -rf "$OUT" && mkdir -p "$OUT/vendor/pglite"
cp -R "$ROOT/web/." "$OUT/"
cp "$ROOT/demo/index.html" "$ROOT/demo/sw.js" "$ROOT/demo/og.jpg" "$OUT/"
cp "$pg"/index.js "$pg"/chunk-*.js "$pg"/pglite.wasm "$pg"/pglite.data "$pg"/initdb.wasm "$OUT/vendor/pglite/"

# Same order as deploy/initdb.sh: tables, bootstrap, functions in file order, seeds.
{
	sed '/^\\restrict/d; /^\\unrestrict/d' "$ROOT/db/schema/schema.sql"
	echo "reset search_path; reset check_function_bodies;"
	cat "$ROOT/db/postgrest/00_bootstrap.sql"
	for f in "$ROOT"/db/functions/*.sql; do
		[ "$(basename "$f")" = 25_cron.sql ] || cat "$f"
	done
	cat "$ROOT/db/seeds/01_seed.sql"
} > "$OUT/fieldopt.sql"

echo "built $OUT"
