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
  // Chrome "no se puede acceder a este sitio". La pagina /offline detecta la
  // ruta solicitada y ofrece volver a /m/calama si los datos estan en
  // IndexedDB.
  fallbacks: {
    document: '/offline/',
  },
  workboxOptions: {
    disableDevLogs: true,
  },
})

const nextConfig = {
  trailingSlash: true,
  images: {
    unoptimized: true,
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
