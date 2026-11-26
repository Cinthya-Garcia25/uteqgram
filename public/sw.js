importScripts('/src/js/idb.js');
importScripts('/src/js/utility.js');

var CACHE_STATIC_NAME = 'static-v25';
var CACHE_DYNAMIC_NAME = 'dynamic-v25';
var STATIC_FILES = [
  '/',
  '/index.html',
  '/offline.html',
  '/manifest.json',
  '/src/js/app.js',
  '/src/js/feed.js',
  '/src/js/idb.js',
  '/src/js/utility.js',
  '/src/js/material.min.js',
  '/src/css/app.css',
  '/src/css/feed.css',
  '/src/images/main-image.jpg',
  '/src/images/main-image-sm.png',
  '/src/images/main-image.png',
  '/src/images/main-image.lg.png',
  '/src/images/main-image.xl.png',
  'https://fonts.googleapis.com/css?family=Roboto:400,700',
  'https://fonts.googleapis.com/icon?family=Material+Icons',
  'https://cdnjs.cloudflare.com/ajax/libs/material-design-lite/1.3.0/material.indigo-pink.min.css'
];

self.addEventListener('install', function (event) {
  console.log('[Service Worker] Installing Service Worker ...', event);
  event.waitUntil(
    caches.open(CACHE_STATIC_NAME)
      .then(function (cache) {
        console.log('[Service Worker] Precaching App Shell');
        return cache.addAll(STATIC_FILES);
      })
  );
});

self.addEventListener('activate', function (event) {
  console.log('[Service Worker] Activating Service Worker ....', event);
  event.waitUntil(
    caches.keys()
      .then(function (keyList) {
        return Promise.all(keyList.map(function (key) {
          if (key !== CACHE_STATIC_NAME && key !== CACHE_DYNAMIC_NAME) {
            console.log('[Service Worker] Removing old cache.', key);
            return caches.delete(key);
          }
        }));
      })
  );
  return self.clients.claim();
});

function isInArray(string, array) {
  var cachePath;
  if (string.indexOf(self.origin) === 0) {
    console.log('matched ', string);
    cachePath = string.substring(self.origin.length);
  } else {
    cachePath = string;
  }
  return array.indexOf(cachePath) > -1;
}

self.addEventListener('fetch', function (event) {
  if (event.request.method !== 'GET') {
    return;
  }

  var url = postsUrl + '.json';

  if (event.request.url.indexOf(url) > -1) {
    event.respondWith(fetch(event.request)
      .then(function (res) {
        var clonedRes = res.clone();
        clearAllData('posts')
          .then(function () {
            return clonedRes.json();
          })
          .then(function (data) {
            console.log('[Service Worker] Saving posts in IndexedDB', data);
            for (var key in data) {
              writeData('posts', data[key]);
            }
          });
        return res;
      })
      .catch(function (err) {
        console.log('[Service Worker] No internet, sending posts from IndexedDB');
        return readAllData('posts')
          .then(function (posts) {
            var data = {};
            for (var i = 0; i < posts.length; i++) {
              data[posts[i].id] = posts[i];
            }
            return new Response(JSON.stringify(data), {
              headers: { 'Content-Type': 'application/json' }
            });
          });
      })
    );
  } else if (isInArray(event.request.url, STATIC_FILES)) {
    event.respondWith(
      caches.match(event.request)
        .then(function (response) {
          return response || fetch(event.request);
        })
    );
  } else {
    event.respondWith(
      caches.match(event.request)
        .then(function (response) {
          if (response) {
            return response;
          } else {
            return fetch(event.request)
              .then(function (res) {
                if (event.request.method !== 'GET' || event.request.url.indexOf('http') !== 0) {
                  return res;
                }
                return caches.open(CACHE_DYNAMIC_NAME)
                  .then(function (cache) {
                    cache.put(event.request.url, res.clone());
                    return res;
                  });
              })
              .catch(function (err) {
                return caches.open(CACHE_STATIC_NAME)
                  .then(function (cache) {
                    return cache.match('/offline.html');
                  });
              });
          }
        })
    );
  }
});

self.addEventListener('sync', function (event) {
  if (event.tag === 'sync-new-posts') {
    event.waitUntil(syncPendingPosts());
  }
});
