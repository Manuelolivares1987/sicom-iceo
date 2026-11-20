'use client'

// ============================================================================
// /instalar/ — Instalar la app «SICOM Terreno» en un teléfono Android
// ----------------------------------------------------------------------------
// Página pública (sin sesión): se manda por WhatsApp o se escanea el QR desde
// el PC. La app es independiente de la configuración de Chrome (no le afecta
// que el navegador bloquee datos o que alguien «borre el historial») y abre sin
// señal como cualquier app instalada.
// ============================================================================

import { useEffect, useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { APK_URL, PAGINA_INSTALAR, enAppTerreno, esAndroid } from '@/lib/app-terreno'

const VERDE = '#16a34a'

function Paso({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <li className="flex gap-3">
      <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-bold text-white" style={{ background: VERDE }}>{n}</span>
      <div className="pt-0.5 text-[15px] leading-snug text-gray-800">{children}</div>
    </li>
  )
}

export default function InstalarAppPage() {
  const [android, setAndroid] = useState<boolean | null>(null)
  const [enApp, setEnApp] = useState(false)
  useEffect(() => { setAndroid(esAndroid()); setEnApp(enAppTerreno()) }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="mx-auto max-w-md px-5 pb-12 pt-8">
        <div className="flex items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/icon-192.png" alt="" className="h-14 w-14 rounded-2xl shadow-sm" />
          <div>
            <h1 className="text-xl font-bold text-gray-900">SICOM Terreno</h1>
            <p className="text-sm text-gray-500">App de faena · Pillado Empresas</p>
          </div>
        </div>

        {enApp ? (
          <div className="mt-6 rounded-xl border border-green-200 bg-green-50 p-4 text-sm text-green-900">
            Ya está usando la app instalada. No hace falta hacer nada más.
            <a href="/m/" className="mt-3 block rounded-lg py-3 text-center font-semibold text-white" style={{ background: VERDE }}>Abrir SICOM</a>
          </div>
        ) : (
          <>
            <p className="mt-5 text-[15px] text-gray-700">
              Funciona <b>sin señal</b>, se abre al instante y no depende de la configuración de Chrome.
              Se instala una sola vez; las mejoras llegan solas.
            </p>

            {android !== false && (
              <a href={APK_URL}
                 className="mt-5 block rounded-xl py-4 text-center text-base font-bold text-white shadow-sm active:opacity-90"
                 style={{ background: VERDE }}>
                Descargar SICOM Terreno
              </a>
            )}

            {android === false && (
              <div className="mt-5 flex flex-col items-center rounded-xl border bg-white p-5 text-center">
                <p className="mb-3 text-sm text-gray-600">Escanee este código con la cámara del teléfono Android:</p>
                <QRCodeSVG value={PAGINA_INSTALAR} size={200} />
                <p className="mt-3 break-all text-xs text-gray-400">{PAGINA_INSTALAR}</p>
              </div>
            )}

            <h2 className="mt-8 text-sm font-semibold uppercase tracking-wide text-gray-500">Cómo se instala</h2>
            <ol className="mt-3 space-y-4">
              <Paso n={1}>Toque <b>Descargar SICOM Terreno</b> (con señal o wifi).</Paso>
              <Paso n={2}>Cuando termine, toque <b>Abrir</b> en el aviso de descarga (o búsquelo en <b>Descargas</b>).</Paso>
              <Paso n={3}>
                Si el teléfono pregunta por <b>instalar apps desconocidas</b>, toque <b>Configuración</b> y active
                <b> Permitir de esta fuente</b>. Vuelva atrás. <span className="text-gray-500">(Solo la primera vez.)</span>
              </Paso>
              <Paso n={4}>Toque <b>Instalar</b>. Si aparece un aviso de Play Protect, elija <b>Instalar de todas formas</b>.</Paso>
              <Paso n={5}>Abra <b>SICOM Terreno</b> desde el ícono y entre con su usuario. Listo: desde ahí funciona sin señal.</Paso>
            </ol>

            <div className="mt-8 rounded-xl border bg-white p-4 text-sm text-gray-600">
              <p className="font-semibold text-gray-800">¿Ya tenía el ícono de SICOM de Chrome?</p>
              <p className="mt-1">Puede dejarlo o borrarlo. Use desde ahora el ícono <b>SICOM Terreno</b>.</p>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
