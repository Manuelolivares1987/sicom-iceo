/** @type {import('next').NextConfig} */
const withPWA = require('@ducanh2912/next-pwa').default({
  dest: 'public',
  disable: process.env.NODE_ENV === 'development',
  register: true,
  reloadOnOnline: true,
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
  workboxOptions: {
    disableDevLogs: true,
    runtimeCaching: [
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
