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
