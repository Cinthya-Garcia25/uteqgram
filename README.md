# UTEQGram

Aplicación web progresiva para consultar publicaciones de la comunidad UTEQ y registrar momentos con título y ubicación. El formulario usa una imagen de ejemplo.

- [Aplicación publicada en Firebase Hosting](https://uteqgram-2ea69.web.app/)
- [Documento de evaluación](https://chatgpt.com/space/page_541c3e875730819189fe9b35c27fa931)

## Ejecutar en local

```sh
npm ci
npm start
```

Abre [http://localhost:8080/](http://localhost:8080/). El servidor sirve `public/` y el navegador puede registrar el service worker en localhost. El código local consulta la misma base de datos que la versión publicada.

## Pantallas y datos

- **Home (`/`).** Tarjetas generadas en el navegador con JavaScript.
- **Formulario de publicación.** Valida título y ubicación y guarda cada envío en IndexedDB antes de sincronizarlo.
- **Ayuda (`/help/`) y vista sin conexión (`/offline.html`).** El service worker muestra la vista sin conexión cuando una navegación falla y la ruta aún no está en caché.
- **Datos.** Firebase Realtime Database almacena publicaciones. IndexedDB conserva el feed consultado y la cola pendiente. Cache Storage conserva la interfaz y los recursos solicitados.

## Comprobar el modo offline

1. Abre Home en Chrome con conexión y espera a que carguen las tarjetas.
2. En DevTools → Application → Service Workers comprueba que el worker esté activo y recarga Home con conexión para poblar IndexedDB.
3. Cambia la red a **Offline** y recarga. Comprueba que reaparezcan las tarjetas consultadas.
4. En la misma sesión, visita una ruta que no se haya abierto antes y confirma que se muestre la pantalla offline.

## Despliegue

`firebase.json` usa `public/` como raíz del sitio. `.firebaserc` contiene el proyecto `uteqgram-2ea69`. Con Firebase CLI y acceso al proyecto, el comando de actualización es `firebase deploy --only hosting --project uteqgram-2ea69`. Los archivos SQL de `supabase/` y `tests/` pertenecen a una práctica aparte.
