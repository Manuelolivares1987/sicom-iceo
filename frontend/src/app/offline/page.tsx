'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { WifiOff, ArrowLeft, Info, RefreshCw } from 'lucide-react'

// Pagina servida por el Service Worker cuando una navegacion (document) no
// esta en cache y la red FALLA (no por lentitud: la regla de paginas es
// NetworkFirst sin timeout). Reemplaza el error nativo de Chrome.
//
// La ruta original queda en la URL del navegador (el SW no la cambia).
//
// [24-09-2026] Catalina (Romeral) quedaba aquí «sin conexión» con señal, y la
// pantalla solo ofrecía volver a /m/calama. Ahora: Reintentar (y reintento
// solo al volver la red), vuelta a la app que corresponde según la ruta, y un
// diagnóstico visible (¿responde SICOM? ¿responde la base? ¿hora del teléfono?)
// para que una foto de esta pantalla diga qué está fallando.

type Chequeo = { estado: 'probando' | 'ok' | 'falla'; detalle: string }

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || ''
const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || ''

async function probar(url: string, init?: RequestInit): Promise<Chequeo & { fechaServidor?: string | null }> {
  const t0 = performance.now()
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), 15000)
  try {
    const r = await fetch(url, { ...init, cache: 'no-store', signal: ctrl.signal })
    const ms = Math.round(performance.now() - t0)
    return { estado: 'ok', detalle: `responde (${ms} ms)`, fechaServidor: r.headers.get('date') }
  } catch (e) {
    const ms = Math.round(performance.now() - t0)
    const motivo = (e as Error)?.name === 'AbortError' ? 'no respondió en 15 s' : `error de red tras ${ms} ms`
    return { estado: 'falla', detalle: motivo }
  } finally {
    clearTimeout(timer)
  }
}

function volverA(path: string | null): { href: string; texto: string } {
  if (path?.startsWith('/m/calama')) return { href: '/m/calama', texto: 'Volver a Mis OTs Calama' }
  if (path?.startsWith('/m/romeral')) return { href: '/m/romeral', texto: 'Volver a Romeral' }
  if (path?.startsWith('/m/franke')) return { href: '/m/franke', texto: 'Volver a Franke' }
  if (path?.startsWith('/m/taller')) return { href: '/m/taller', texto: 'Volver a Taller' }
  if (path?.startsWith('/m/enex')) return { href: '/m/enex', texto: 'Volver a ENEX' }
  if (path?.startsWith('/m/prevencion')) return { href: '/m/prevencion', texto: 'Volver a Prevención' }
  return { href: '/dashboard', texto: 'Ir al inicio de SICOM' }
}

export default function OfflinePage() {
  const [originalPath, setOriginalPath] = useState<string | null>(null)
  const [originalOtId, setOriginalOtId] = useState<string | null>(null)
  const [sicom, setSicom] = useState<Chequeo>({ estado: 'probando', detalle: 'probando…' })
  const [base, setBase] = useState<Chequeo>({ estado: 'probando', detalle: 'probando…' })
  const [desfaseMin, setDesfaseMin] = useState<number | null>(null)
  const [online, setOnline] = useState<boolean | null>(null)

  const diagnosticar = async () => {
    setSicom({ estado: 'probando', detalle: 'probando…' })
    setBase({ estado: 'probando', detalle: 'probando…' })
    setOnline(navigator.onLine)
    const [a, b] = await Promise.all([
      probar(`/manifest.json?diag=${Date.now()}`),
      SUPABASE_URL
        ? probar(`${SUPABASE_URL}/auth/v1/health`, { headers: { apikey: SUPABASE_ANON } })
        : Promise.resolve({ estado: 'falla' as const, detalle: 'sin configuración' }),
    ])
    setSicom(a)
    setBase(b)
    const fecha = a.fechaServidor ?? ('fechaServidor' in b ? b.fechaServidor : null)
    if (fecha) setDesfaseMin(Math.round((Date.now() - new Date(fecha).getTime()) / 60000))
  }

  useEffect(() => {
    if (typeof window === 'undefined') return
    const pathname = window.location.pathname
    setOriginalPath(pathname)
    const m = pathname.match(/^\/m\/calama\/ot\/([^/]+)/)
    if (m) setOriginalOtId(m[1])
    void diagnosticar()
    // Si vuelve la red, se reintenta la pantalla que se pidió.
    const alVolver = () => window.location.reload()
    window.addEventListener('online', alVolver)
    return () => window.removeEventListener('online', alVolver)
  }, [])

  const destino = volverA(originalPath)
  const color = (c: Chequeo) => c.estado === 'ok' ? 'text-green-700' : c.estado === 'falla' ? 'text-red-700' : 'text-gray-500'
  const ambosOk = sicom.estado === 'ok' && base.estado === 'ok'

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-amber-50 to-orange-100">
      <div className="max-w-sm w-full bg-white rounded-2xl shadow-lg p-6 space-y-4">
        <div className="flex flex-col items-center text-center space-y-2">
          <div className="rounded-full bg-amber-100 p-3">
            <WifiOff className="h-8 w-8 text-amber-700" />
          </div>
          <h1 className="text-lg font-bold text-gray-900">No se pudo cargar esta pantalla</h1>
          <p className="text-sm text-gray-600">
            El teléfono no logró conectarse con SICOM. Puede pasar con señal pero sin datos,
            o con una red que bloquea la página. Prueba de nuevo o cambia de red (WiFi / datos).
          </p>
        </div>

        <button
          type="button"
          onClick={() => window.location.reload()}
          className="flex w-full items-center justify-center gap-2 rounded-lg bg-amber-600 text-white px-4 py-2.5 text-sm font-semibold active:bg-amber-700"
        >
          <RefreshCw className="h-4 w-4" />
          Reintentar
        </button>

        <Link
          href={destino.href}
          className="flex items-center justify-center gap-2 rounded-lg border border-amber-300 text-amber-800 px-4 py-2.5 text-sm font-semibold"
        >
          <ArrowLeft className="h-4 w-4" />
          {destino.texto}
        </Link>

        <div className="rounded-lg bg-gray-50 border border-gray-200 px-3 py-2 text-xs space-y-1">
          <p className="text-[10px] uppercase tracking-wider text-gray-500">Diagnóstico (envía una foto de esto si sigue fallando)</p>
          <p>Teléfono dice que tiene red: <b>{online == null ? '…' : online ? 'sí' : 'no'}</b></p>
          <p>Servidor SICOM: <b className={color(sicom)}>{sicom.detalle}</b></p>
          <p>Base de datos: <b className={color(base)}>{base.detalle}</b></p>
          {desfaseMin != null && Math.abs(desfaseMin) >= 5 && (
            <p className="text-red-700"><b>La hora del teléfono está desfasada {Math.abs(desfaseMin)} min.</b> Activa «fecha y hora automática».</p>
          )}
          {ambosOk && <p className="text-green-700">Ahora sí hay conexión: aprieta Reintentar.</p>}
          {originalPath && <p className="font-mono break-all text-gray-500">Ruta: {originalPath}</p>}
          <button type="button" onClick={() => void diagnosticar()} className="text-amber-700 underline">Probar de nuevo</button>
        </div>

        {originalOtId && (
          <div className="rounded-lg bg-blue-50 border border-blue-200 p-3 flex items-start gap-2">
            <Info className="h-4 w-4 text-blue-700 shrink-0 mt-0.5" />
            <p className="text-xs text-blue-900">
              Para ejecutar OTs sin señal, abre cada una al menos una vez con
              conexión antes de salir a terreno. Así el celular la guarda en
              caché local.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
