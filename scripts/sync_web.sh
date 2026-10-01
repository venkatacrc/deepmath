#!/usr/bin/env bash
# Syncs the deck and KaTeX into web/, refreshes the PWA icons, and stamps the
# service-worker cache name so installed phones pick up the new version.
# Open web/ over HTTPS (or localhost) on a Pixel to Install / Add to Home screen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/web"
RES="$ROOT/app/Sources/DeepMath/Resources"

python3 "$ROOT/tools/build_deck.py" --skip-tex-check >/dev/null
cp "$RES/deck.json" "$WEB/deck.json"

mkdir -p "$WEB/katex/fonts"
cp "$RES/web/katex/katex.min.js" "$RES/web/katex/katex.min.css" "$WEB/katex/"
cp "$RES/web/katex/fonts/"*.woff2 "$WEB/katex/fonts/"

if [ ! -f "$WEB/icons/maskable-512.png" ]; then
    swift "$ROOT/scripts/make_icon.swift" --web "$WEB/icons"
fi

python3 - "$WEB" <<'PY'
import hashlib, pathlib, sys

web = pathlib.Path(sys.argv[1])
fonts = sorted((web / "katex" / "fonts").glob("*.woff2"))
font_entries = "".join(f"\n    'katex/fonts/{f.name}'," for f in fonts)

# Stamp the cache name from the app payload so phones drop the old cache.
parts = []
for name in ("index.html", "app.css", "app.js", "deck.json", "manifest.webmanifest",
             "icons/icon-192.png", "icons/icon-512.png", "icons/maskable-512.png",
             "katex/katex.min.css", "katex/katex.min.js"):
    parts.append((web / name).read_bytes())
for f in fonts:
    parts.append(f.read_bytes())
version = hashlib.sha1(b"".join(parts)).hexdigest()[:10]

(web / "sw.js").write_text(f"""\
// Network first so a new deck or app version shows up as soon as the phone is online;
// the cache keeps everything working offline on Pixel / Android.
const CACHE = 'deepmath-{version}';
const FILES = [
    './',
    'index.html',
    'app.css',
    'app.js',
    'deck.json',
    'manifest.webmanifest',
    'icons/icon-192.png',
    'icons/icon-512.png',
    'icons/maskable-512.png',
    'katex/katex.min.css',
    'katex/katex.min.js',{font_entries}
];

self.addEventListener('install', (event) => {{
    event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES)).then(() => self.skipWaiting()));
}});

self.addEventListener('activate', (event) => {{
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
            .then(() => self.clients.claim()));
}});

self.addEventListener('fetch', (event) => {{
    const {{ request }} = event;
    if (request.method !== 'GET' || new URL(request.url).origin !== location.origin) return;
    event.respondWith(
        fetch(request)
            .then((response) => {{
                if (response.ok) {{
                    const copy = response.clone();
                    caches.open(CACHE).then((cache) => cache.put(request, copy));
                }}
                return response;
            }})
            .catch(() => caches.match(request, {{ ignoreSearch: true }})
                .then((hit) => hit || caches.match('./'))));
}});
""")
print(f"Synced {web} (cache deepmath-{version}, {len(fonts)} KaTeX fonts)")
PY

echo "Serve with:  cd $WEB && python3 -m http.server 8080"
echo "On a Pixel, open http://<your-mac-ip>:8080 → Chrome menu ⋮ → Install app / Add to Home screen."
