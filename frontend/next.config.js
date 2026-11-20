/** @type {import('next').NextConfig} */
const fs = require('fs')
const path = require('path')

// Versión del build (Netlify da COMMIT_REF). La usan la app (precarga, avisos)
// y el service worker (nombre de las cachés de terreno y revisión de las páginas).
const BUILD_ID = (process.env.COMMIT_REF || String(Date.now())).slice(0, 12)

// [20-11-2026] Páginas fijas de la app de terreno (/m/**, sin [id]): se guardan
// ENTERAS en el teléfono junto con todos sus JS, como una app instalada.
function rutasTerreno() {
  const raiz = path.join(__dirname, 'src', 'app')
  const out = ['/m/', '/login/']
  const recorrer = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (!e.isDirectory() || /[[(]/.test(e.name)) continue
      const d = path.join(dir, e.name)
      if (fs.existsSync(path.join(d, 'page.tsx'))) out.push('/' + path.relative(raiz, d).split(path.sep).join('/') + '/')
      recorrer(d)
    }
  }
  recorrer(path.join(raiz, 'm'))
  return Array.from(new Set(out))
}

const withPWA = require('@ducanh2912/next-pwa').default({
  dest: 'public',
  disable: process.env.NODE_ENV === 'development',
  register: true,
  // Recargar la página al volver la señal botaba al mantenedor en medio del
  // formulario y, con señal que va y viene (lo normal en faena), la recarga
  // quedaba colgada esperando a la red. Las apps de terreno envían solas lo
  // pendiente al volver la conexión; no hace falta recargar.
  reloadOnOnline: false,
  cacheOnFrontEndNav: true,
  aggressiveFrontEndNavCaching: true,
  // Fallback offline: cuando una navegacion (document) no esta en cache y no
  // hay red, el SW sirve /offline en lugar de mostrar el error nativo de
  // Chrome "no se puede acceder a este sitio". La pagina /offline ofrece
  // Reintentar, vuelve a la app de la ruta pedida (Romeral, Calama, taller…)
  // y muestra un diagnóstico de conexión (24-09-2026).
  fallbacks: {
    document: '/offline/',
  },
  // La regla por defecto del plugin ("cross-origin", NetworkFirst con 10 s de
  // espera y 1 h de vida) guardaba TODAS las respuestas de Supabase por URL,
  // sin distinguir usuario: /auth/v1/user, el perfil, los permisos y cada
  // consulta REST quedaban en la caché del navegador y, con red lenta o caída,
  // el SW entregaba la respuesta de otra sesión o una lista vacía vieja (el
  // selector de faenas de /m/prevencion salió sin opciones el 15-09-2026).
  // Las llamadas a la API van siempre a la red; sólo Storage (fotos, PDF)
  // sigue con la regla por defecto. Las apps de terreno guardan su trabajo
  // sin señal en IndexedDB, no en esta caché.
  extendDefaultRuntimeCaching: true,
  // [19-11-2026] plantillas/pdf.worker (1,2 MB) solo lo usa el panel de oficina.
  publicExcludes: ['!noprecache/**', '!plantillas/**', '!reparar/**'],
  workboxOptions: {
    disableDevLogs: true,
    // [20-11-2026] Actualización «como WhatsApp»: la versión nueva se baja ENTERA
    // en segundo plano y queda esperando; se aplica al próximo arranque de la app
    // (components/layout/actualizacion-app.tsx), nunca a mitad de un formulario.
    // Antes (skipWaiting) tomaba el control al instante y mezclaba versiones.
    skipWaiting: false,
    // Las páginas guardadas se encuentran aunque lleven parámetros (?p=…&a=…).
    // `_rsc` NO va acá: esa es la navegación interna y tiene su propia regla.
    ignoreURLParametersMatching: [/^utm_/, /^fbclid$/, /^turno$/, /^p$/, /^a$/, /^id$/, /^fecha$/, /^next$/, /^v$/, /^source$/],
    additionalManifestEntries: rutasTerreno().map((url) => ({ url, revision: BUILD_ID })),
    // [19-11-2026] Precache MÍNIMO. Para actualizarse, el teléfono debe bajar
    // TODO el precache (eran 443 archivos, 15 MB) y si UNO falla con mala
    // señal descarta la versión nueva y se queda con la vieja — así el
    // teléfono de Yohan siguió con el build que se colgaba aunque el arreglo
    // ya estaba en producción. Ahora se precarga solo el arranque (framework,
    // CSS, layout raíz, login, /offline y las apps de terreno /m/*); el resto
    // (panel de oficina) se guarda al usarse (regla next-static-js-assets) y
    // PrecargaTerreno baja los JS de la app de cada usuario.
    manifestTransforms: [
      async (entries, compilation) => {
        // [20-11-2026] TODOS los JS que usan las páginas de terreno (sacados del
        // app-build-manifest de este mismo build): sin esto el teléfono tenía
        // el HTML guardado pero no los chunks compartidos, y quedaba en la ruedita.
        let terreno = null
        try {
          const a = compilation && compilation.getAsset && compilation.getAsset('app-build-manifest.json')
          if (a) {
            const pages = JSON.parse(a.source.source().toString()).pages
            terreno = new Set()
            for (const [ruta, archivos] of Object.entries(pages)) {
              if (/^\/(m\/|login\/|offline\/|_not-found\/|page$|layout$)/.test(ruta)) for (const f of archivos) terreno.add('/_next/' + f)
            }
          }
        } catch (e) { console.warn('[pwa] sin app-build-manifest:', e && e.message) }
        console.log(`[pwa] precache terreno: ${terreno ? terreno.size + ' archivos' : 'NO DISPONIBLE (se usa el mínimo)'}`)
        const esencial = (url) =>
          (terreno && terreno.has(url)) ||
          !/\/_next\/static\//.test(url) ||                         // public (iconos, manifest, offline)
          /\/static\/css\//.test(url) ||
          /\/static\/media\//.test(url) ||
          /\/static\/[^/]+\/_(build|ssg)Manifest\.js$/.test(url) ||
          /\/static\/chunks\/(framework|main|main-app|webpack|polyfills)[-.]/.test(url) ||
          /\/static\/chunks\/app\/(m\/|offline\/|login\/|layout-|page-|error-|global-error-|_not-found\/)/.test(url)
        // Archivos con hash en el nombre: la revisión es el propio nombre (no el
        // build). Así una versión nueva baja solo lo que cambió; antes la revisión
        // era el build y cada deploy re-bajaba todo. (null no sirve: el plugin lo
        // reemplaza por el build.)
        const manifest = entries.filter((e) => esencial(e.url))
          .map((e) => (/\/_next\/static\//.test(e.url) && !/_(build|ssg)Manifest/.test(e.url) ? { ...e, revision: e.url } : e))
        return { manifest, warnings: [] }
      },
    ],
    runtimeCaching: [
      // [19-11-2026] Los JS de Next tienen hash en el nombre: nunca cambian.
      // CacheFirst 30 días y 400 entradas (antes 1 día / 64): lo que se abrió
      // una vez abre sin señal, y no se re-descarga en cada visita.
      {
        urlPattern: /\/_next\/static.+\.js$/i,
        handler: 'CacheFirst',
        options: {
          cacheName: 'next-static-js-assets',
          expiration: { maxEntries: 400, maxAgeSeconds: 30 * 24 * 60 * 60 },
        },
      },
      // [19-11-2026] TODAS las apps de terreno (/m/*): taller, Romeral y Calama
      // tenían la regla general (1 día) y al día siguiente sin señal caían en
      // /offline. La precarga (components/layout/precarga-terreno.tsx) llena
      // esta caché con las pantallas de la app de cada usuario.
      // Antes: apps de terreno ENEX, Prevención (inspección APR, MIG685) y Franke (pauta, despacho,
      // bodega con lector — MIG694): tienen que abrir sin señal días después de la
      // última conexión. La regla general de páginas guarda 32 por 1 día y
      // espera a la red sin límite, así que al día siguiente en faena (o con
      // antena sin datos) caía en /offline teniendo todo descargado.
      // Acá: 30 días, y si la red no contesta en 4 s se usa lo guardado. La
      // clave ignora los parámetros (?id=…): /m/enex/servicio/ es una sola
      // página para todos los servicios.
      {
        urlPattern: ({ request, url, sameOrigin }) =>
          sameOrigin && url.pathname.startsWith('/m/') && request.headers.get('RSC') !== '1',
        handler: 'NetworkFirst',
        options: {
          cacheName: `terreno-paginas-${BUILD_ID}`,
          networkTimeoutSeconds: 4,
          expiration: { maxEntries: 80, maxAgeSeconds: 30 * 24 * 60 * 60 },
          plugins: [{
            // Con punto y coma: el plugin copia la función al service worker
            // en una sola línea.
            cacheKeyWillBeUsed: async ({ request }) => { const u = new URL(request.url); return u.origin + u.pathname },
          }],
        },
      },
      // Lo mismo para la navegación interna de Next (payload RSC). Los
      // prefetch se dejan a la regla general.
      {
        urlPattern: ({ request, url, sameOrigin }) =>
          sameOrigin && url.pathname.startsWith('/m/') &&
          request.headers.get('RSC') === '1' && !request.headers.get('Next-Router-Prefetch'),
        handler: 'NetworkFirst',
        options: {
          cacheName: `terreno-rsc-${BUILD_ID}`,
          networkTimeoutSeconds: 4,
          expiration: { maxEntries: 80, maxAgeSeconds: 30 * 24 * 60 * 60 },
          plugins: [{
            // Con punto y coma: el plugin copia la función al service worker
            // en una sola línea.
            cacheKeyWillBeUsed: async ({ request }) => { const u = new URL(request.url); return u.origin + u.pathname },
          }],
        },
      },
      // [19-11-2026] Las reglas por defecto «pages» y «pages-rsc» esperan a la
      // red SIN límite: con señal a medias, cambiar de pantalla (o el guard que
      // manda a cada uno a su faena) quedaba colgado para siempre. Mismo
      // cacheName = reemplazan a las del plugin; a los 8 s se usa lo guardado.
      // Solo documentos y payload RSC: el resto de los archivos sigue con sus
      // reglas de siempre.
      {
        urlPattern: ({ request, url, sameOrigin }) =>
          sameOrigin && !url.pathname.startsWith('/api/') &&
          request.headers.get('RSC') === '1' && !request.headers.get('Next-Router-Prefetch'),
        handler: 'NetworkFirst',
        options: {
          cacheName: 'pages-rsc',
          networkTimeoutSeconds: 8,
          expiration: { maxEntries: 32, maxAgeSeconds: 24 * 60 * 60 },
        },
      },
      {
        urlPattern: ({ request, url, sameOrigin }) =>
          sameOrigin && !url.pathname.startsWith('/api/') && request.mode === 'navigate',
        handler: 'NetworkFirst',
        options: {
          cacheName: 'pages',
          networkTimeoutSeconds: 8,
          expiration: { maxEntries: 32, maxAgeSeconds: 24 * 60 * 60 },
        },
      },
      {
        urlPattern: /^https:\/\/[a-z0-9-]+\.supabase\.co\/(rest|auth|functions|realtime|graphql)\//i,
        handler: 'NetworkOnly',
        options: { cacheName: 'supabase-api-sin-cache' },
      },
    ],
  },
})

const nextConfig = {
  trailingSlash: true,
  // Versión del build (Netlify da COMMIT_REF): la precarga de terreno se rehace
  // con cada versión nueva.
  env: {
    NEXT_PUBLIC_BUILD_ID: BUILD_ID,
  },
  images: {
    unoptimized: true,
  },
  webpack: (config, { isServer, webpack }) => {
    // pptxgenjs (PPT de evidencias de prevención, MIG547): TODOS sus bundles
    // traen `import 'node:fs'` (guardado en runtime para Node, muerto en el
    // navegador), y webpack se cae en el esquema `node:` antes de poder
    // aplicar el campo browser del paquete. Se le quita el prefijo y el
    // fallback deja esos módulos en false — en el navegador pptxgenjs nunca
    // los toca.
    if (!isServer) {
      config.plugins.push(
        new webpack.NormalModuleReplacementPlugin(/^node:/, (resource) => {
          resource.request = resource.request.replace(/^node:/, '')
        }),
      )
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        https: false,
        http: false,
        os: false,
        path: false,
        'image-size': false,
      }
    }
    return config
  },
  async redirects() {
    return [
      // Los Recorridos Gemba salieron de Prevención: no son un módulo de
      // prevención, son una práctica de tres cargos (jefe de taller, jefe de
      // operaciones y prevención). Se conserva la ruta vieja porque hay
      // favoritos y links en la documentación de puesta en marcha.
      {
        source: '/dashboard/prevencion/gemba',
        destination: '/dashboard/gemba',
        permanent: true,
      },
      {
        source: '/dashboard/prevencion/gemba/:path*',
        destination: '/dashboard/gemba/:path*',
        permanent: true,
      },
    ]
  },
}

module.exports = withPWA(nextConfig)
