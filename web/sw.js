// Network first so a new deck or app version shows up as soon as the phone is online;
// the cache keeps everything working offline on Pixel / Android.
const CACHE = 'deepmath-227d35fbbb';
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
    'katex/katex.min.js',
    'katex/fonts/KaTeX_AMS-Regular.woff2',
    'katex/fonts/KaTeX_Caligraphic-Bold.woff2',
    'katex/fonts/KaTeX_Caligraphic-Regular.woff2',
    'katex/fonts/KaTeX_Fraktur-Bold.woff2',
    'katex/fonts/KaTeX_Fraktur-Regular.woff2',
    'katex/fonts/KaTeX_Main-Bold.woff2',
    'katex/fonts/KaTeX_Main-BoldItalic.woff2',
    'katex/fonts/KaTeX_Main-Italic.woff2',
    'katex/fonts/KaTeX_Main-Regular.woff2',
    'katex/fonts/KaTeX_Math-BoldItalic.woff2',
    'katex/fonts/KaTeX_Math-Italic.woff2',
    'katex/fonts/KaTeX_SansSerif-Bold.woff2',
    'katex/fonts/KaTeX_SansSerif-Italic.woff2',
    'katex/fonts/KaTeX_SansSerif-Regular.woff2',
    'katex/fonts/KaTeX_Script-Regular.woff2',
    'katex/fonts/KaTeX_Size1-Regular.woff2',
    'katex/fonts/KaTeX_Size2-Regular.woff2',
    'katex/fonts/KaTeX_Size3-Regular.woff2',
    'katex/fonts/KaTeX_Size4-Regular.woff2',
    'katex/fonts/KaTeX_Typewriter-Regular.woff2',
];

self.addEventListener('install', (event) => {
    event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
            .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
    const { request } = event;
    if (request.method !== 'GET' || new URL(request.url).origin !== location.origin) return;
    event.respondWith(
        fetch(request)
            .then((response) => {
                if (response.ok) {
                    const copy = response.clone();
                    caches.open(CACHE).then((cache) => cache.put(request, copy));
                }
                return response;
            })
            .catch(() => caches.match(request, { ignoreSearch: true })
                .then((hit) => hit || caches.match('./'))));
});
