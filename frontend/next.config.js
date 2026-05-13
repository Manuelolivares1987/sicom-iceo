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
}

module.exports = withPWA(nextConfig)
