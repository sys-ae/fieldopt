# Vendored static deps

These files are vendored on purpose — no npm, no CDN at runtime.
Pin a known-good version + SHA. Verify before committing.

## htmx.min.js

Path: `web/vendor/htmx.min.js`

Download (verify the URL on https://htmx.org before running):

```bash
curl -fsSL https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js -o web/vendor/htmx.min.js
```

Verify SHA-256 against https://htmx.org/docs/#installing or the npm registry's reported integrity for that exact version:

```bash
shasum -a 256 web/vendor/htmx.min.js
```

Commit the file. Future upgrades = bump version + re-verify SHA. No build step ever touches `node_modules`.

## leaflet.js / leaflet.css

Vendored alongside htmx, plus `images/` for the marker sprites. Same pattern:
download + SHA verify + commit.

## idiomorph-ext.min.js

The htmx morph swap extension. Polled fragments use `hx-swap="morph:innerHTML"` so
scroll position, hover and selection survive a refresh.
