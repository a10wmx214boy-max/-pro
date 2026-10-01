// Do not cache API responses, authenticated HTML, signed media or messages.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
// Network-only: avoids stale user data and deployment assets.
