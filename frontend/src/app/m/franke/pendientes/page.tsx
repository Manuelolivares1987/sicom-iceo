'use client'

// ============================================================================
// Pendientes — lo que está en el teléfono esperando subir (F3, 20-11-2026)
// ----------------------------------------------------------------------------
// El «reloj ⏱» de WhatsApp, en una pantalla: qué falta subir, por qué espera
// (sin señal, sin sesión, reintentando) y qué se rechazó y por qué. Más el
// estado de los datos de la faena bajados al teléfono.
// ============================================================================

import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, CloudOff, CloudUpload, CheckCircle2, AlertTriangle, Clock, RefreshCw, Download, LogIn } from 'lucide-react'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useAuth } from '@/contexts/auth-context'
import { EsperandoSesion } from '@/components/layout/esperando-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { estaEnLinea, EVENTO_CONECTIVIDAD } from '@/lib/conectividad'
import { haySesionServidor } from '@/lib/supabase'
import {
  listarBandeja, sincronizarBandeja, reintentarYa, descartar, EVENTO_BANDEJA, type OperacionBandeja,
} from '@/lib/offline/bandeja'
import '@/lib/offline/franke-carga'
import { precargarFaena, ultimaPrecarga, type EstadoPrecarga } from '@/lib/offline/franke-precarga'
import { pendientesCount as pautas, sincronizar as subirPautas } from '@/lib/offline/faena-pauta-offline'
import {
  pendientesCount as despachos, movimientosPendientesCount as movimientos, sincronizar as subirDespachos, sincronizarMovimientos,
} from '@/lib/offline/combustible-faena-offline'
import { pendientesCount as bodega, pendientesBodega, sincronizar as subirBodega } from '@/lib/offline/bodega-faena-offline'
import { pendientesCount as bitacora, colaBitacora, sincronizar as subirBitacora } from '@/lib/offline/faena-bitacora-offline'
import { pendientesCount as entrega, colaEntrega, sincronizar as subirEntrega } from '@/lib/offline/faena-entrega-offline'

type Modulo = { nombre: string; href: string; n: number; rechazadas: number }

const hora = (iso?: string | null) =>
  (iso ? new Date(iso).toLocaleString('es-CL', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—')

export default function PendientesPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { sesionPerdida } = useAuth()
  const [online, setOnline] = useState(true)
  const [modulos, setModulos] = useState<Modulo[]>([])
  const [ops, setOps] = useState<OperacionBandeja[]>([])
  const [precarga, setPrecarga] = useState<EstadoPrecarga | null>(null)
  const [subiendo, setSubiendo] = useState(false)
  const [bajando, setBajando] = useState(false)
  const [confirmar, setConfirmar] = useState<string | null>(null)

  const refrescar = useCallback(async () => {
    setOnline(estaEnLinea())
    setPrecarga(ultimaPrecarga())
    setOps(await listarBandeja())
    const seguro = async (f: () => Promise<number>) => { try { return await f() } catch { return 0 } }
    const rechBodega = (await pendientesBodega().catch(() => [])).filter((o) => o.sync_status === 'rechazada').length
    const rechBitacora = (await colaBitacora().catch(() => [])).filter((o) => o.sync_status === 'rechazada').length
    const rechEntrega = (await colaEntrega().catch(() => [])).filter((o) => o.sync_status === 'rechazada').length
    setModulos([
      { nombre: 'Revisión de equipos (pautas)', href: '/m/franke/pauta', n: await seguro(pautas), rechazadas: 0 },
      { nombre: 'Despacho de combustible', href: '/m/franke/despacho', n: (await seguro(despachos)) + (await seguro(movimientos)), rechazadas: 0 },
      { nombre: 'Bodega', href: '/m/franke/bodega', n: await seguro(bodega), rechazadas: rechBodega },
      { nombre: 'Bitácora del turno', href: '/m/franke/bitacora', n: await seguro(bitacora), rechazadas: rechBitacora },
      { nombre: 'Entrega de turno', href: '/m/franke/entrega', n: await seguro(entrega), rechazadas: rechEntrega },
    ])
  }, [])

  useEffect(() => {
    void refrescar()
    const al = () => { void refrescar() }
    window.addEventListener(EVENTO_BANDEJA, al)
    window.addEventListener(EVENTO_CONECTIVIDAD, al)
    const t = setInterval(al, 10_000)
    return () => {
      window.removeEventListener(EVENTO_BANDEJA, al)
      window.removeEventListener(EVENTO_CONECTIVIDAD, al)
      clearInterval(t)
    }
  }, [refrescar])

  const subirTodo = async () => {
    setSubiendo(true)
    try {
      await Promise.allSettled([subirPautas(), subirDespachos(), sincronizarMovimientos(), subirBodega(), subirBitacora(),
        subirEntrega(), sincronizarBandeja(true)])
    } finally { setSubiendo(false); void refrescar() }
  }

  const bajarTodo = async () => {
    setBajando(true)
    try { await precargarFaena(true) } finally { setBajando(false); void refrescar() }
  }

  if (verificando) return <EsperandoSesion />
  if (sinSesionOffline) return <SinSesionOffline />

  const sesionOk = haySesionServidor() && !sesionPerdida
  const total = modulos.reduce((a, m) => a + m.n, 0) + ops.length

  let estadoTxt = 'Con señal: se está subiendo sola.'
  if (!online) estadoTxt = 'Sin señal: se sube sola apenas vuelva.'
  else if (!sesionOk) estadoTxt = 'Hay señal, pero la sesión está por renovar: entre de nuevo para subir.'
  else if (total === 0) estadoTxt = 'Con señal y sesión al día.'

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-3">
          <Link href="/m/franke" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100"><ArrowLeft className="h-5 w-5" /></Link>
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold leading-tight text-gray-900">Pendientes</p>
            <p className="text-xs text-gray-500">Lo que está en el teléfono esperando subir</p>
          </div>
        </div>
      </header>

      <main className="space-y-4 px-4 py-4">
        <section className={`rounded-xl border p-4 ${total === 0 ? 'border-green-200 bg-green-50' : 'border-amber-200 bg-amber-50'}`}>
          <div className="flex items-center gap-3">
            {total === 0 ? <CheckCircle2 className="h-8 w-8 text-green-600" /> : <Clock className="h-8 w-8 text-amber-600" />}
            <div>
              <p className="text-lg font-bold text-gray-900">{total === 0 ? 'Todo subido ✓✓' : `${total} por subir ⏱`}</p>
              <p className="text-xs text-gray-600">{estadoTxt}</p>
            </div>
          </div>
          <div className="mt-3 flex gap-2">
            {!sesionOk && online && (
              <a href="/login/?next=%2Fm%2Ffranke%2Fpendientes%2F"
                 className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-amber-600 py-2.5 text-sm font-bold text-white">
                <LogIn className="h-4 w-4" /> Entrar
              </a>
            )}
            {total > 0 && (
              <button onClick={() => void subirTodo()} disabled={!online || !sesionOk || subiendo}
                      className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-gray-900 py-2.5 text-sm font-bold text-white disabled:opacity-40">
                {online ? <CloudUpload className={subiendo ? 'h-4 w-4 animate-pulse' : 'h-4 w-4'} /> : <CloudOff className="h-4 w-4" />}
                {subiendo ? 'Subiendo…' : 'Subir ahora'}
              </button>
            )}
          </div>
        </section>

        <section className="rounded-xl border border-gray-200 bg-white">
          {modulos.map((m) => (
            <Link key={m.nombre} href={m.href} className="flex items-center justify-between border-b border-gray-100 px-4 py-3 last:border-0">
              <span className="text-sm font-medium text-gray-800">{m.nombre}</span>
              <span className="flex items-center gap-2 text-sm">
                {m.rechazadas > 0 && (
                  <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-bold text-red-700">{m.rechazadas} no aceptado(s)</span>
                )}
                <span className={m.n > 0 ? 'font-bold text-amber-700' : 'text-gray-400'}>{m.n > 0 ? `⏱ ${m.n}` : '✓'}</span>
              </span>
            </Link>
          ))}
        </section>

        {ops.length > 0 && (
          <section className="space-y-2">
            <p className="text-xs font-bold uppercase tracking-wide text-gray-500">En la bandeja</p>
            {ops.map((o) => (
              <div key={o.id} className={`rounded-xl border p-3 ${o.estado === 'rechazada' ? 'border-red-300 bg-red-50' : 'border-gray-200 bg-white'}`}>
                <div className="flex items-start gap-2">
                  {o.estado === 'rechazada'
                    ? <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-red-600" />
                    : <Clock className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />}
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-semibold text-gray-900">{o.resumen}</p>
                    <p className="text-[11px] text-gray-500">
                      Guardado {hora(o.creado_at)}
                      {o.estado === 'rechazada'
                        ? ` · No se aceptó: ${o.error ?? ''}`
                        : o.intentos > 0 ? ` · ${o.intentos} intento(s); vuelve a probar ${hora(new Date(o.proximo_at).toISOString())}` : ''}
                    </p>
                  </div>
                </div>
                <div className="mt-2 flex justify-end gap-2">
                  <button onClick={() => void reintentarYa(o.id)} disabled={!online}
                          className="flex items-center gap-1 rounded-lg border px-2.5 py-1.5 text-xs font-semibold text-gray-700 disabled:opacity-40">
                    <RefreshCw className="h-3.5 w-3.5" /> Reintentar
                  </button>
                  {confirmar === o.id ? (
                    <button onClick={() => { void descartar(o.id); setConfirmar(null) }}
                            className="rounded-lg bg-red-600 px-2.5 py-1.5 text-xs font-bold text-white">Sí, borrar del teléfono</button>
                  ) : (
                    <button onClick={() => setConfirmar(o.id)}
                            className="rounded-lg border border-red-200 px-2.5 py-1.5 text-xs font-semibold text-red-700">Descartar</button>
                  )}
                </div>
              </div>
            ))}
          </section>
        )}

        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <p className="text-sm font-bold text-gray-900">Datos de la faena en este teléfono</p>
          <p className="mt-1 text-xs text-gray-500">
            {precarga ? `Última actualización: ${hora(precarga.at)}` : 'Todavía no se han bajado con señal.'}
          </p>
          {precarga && (
            <ul className="mt-2 space-y-0.5 text-xs">
              {precarga.ok.map((x) => <li key={x} className="text-green-700">✓ {x}</li>)}
              {precarga.fallaron.map((x) => <li key={x} className="text-red-700">✗ {x} (se reintenta)</li>)}
            </ul>
          )}
          <button onClick={() => void bajarTodo()} disabled={!online || bajando}
                  className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-lg border border-gray-300 py-2.5 text-sm font-semibold text-gray-800 disabled:opacity-40">
            <Download className={bajando ? 'h-4 w-4 animate-bounce' : 'h-4 w-4'} /> {bajando ? 'Bajando…' : 'Actualizar datos ahora'}
          </button>
        </section>
      </main>
    </div>
  )
}
