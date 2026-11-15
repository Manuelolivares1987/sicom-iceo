'use client'

// ============================================================================
// Justificar diferencias de combustible por enlace (MIG691)
// ----------------------------------------------------------------------------
// Llega en el correo semanal de cada operación (Calama → Jefe de Operaciones;
// Coquimbo → Bodega). Sin cuenta: el token del reporte abre SOLO las cargas de
// esa operación. Cada diferencia exige un texto (qué pasó, quién cargó) y el
// nombre de quien responde. La jefatura después la acepta o la rechaza; si la
// rechaza, vuelve a aparecer aquí con el motivo.
// Fuera de /dashboard a propósito: sin sesión ni menú, una sola pantalla.
// ============================================================================

import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { AlertTriangle, CheckCircle2, Clock, Fuel, Loader2, MapPin, XCircle } from 'lucide-react'
import { ALERTA_TXT, type Alerta } from '@/lib/services/combustible-tarjeta'
import { getReporteToken, justificarConToken, type DiferenciaComb, type ReporteToken } from '@/lib/services/combustible-control'
import { cn, errorMessage } from '@/lib/utils'

const n0 = (n: number | null | undefined) => (n == null ? '—' : Math.round(Number(n)).toLocaleString('es-CL'))
const n1 = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 }))
const fecha = (s: string) => new Date(`${s}T12:00:00`).toLocaleDateString('es-CL', { day: '2-digit', month: 'long' })
const fechaHora = (s: string) => {
  const d = new Date(s)
  return d.toLocaleDateString('es-CL', { weekday: 'long', day: '2-digit', month: 'short' }) + ', ' +
    d.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })
}
const CLAVE_NOMBRE = 'sicom-justificar-nombre'

export default function JustificarCombustiblePage() {
  const token = useParams()?.token as string
  const [rep, setRep] = useState<ReporteToken | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [nombre, setNombre] = useState('')

  const cargar = useCallback(async () => {
    try { setRep(await getReporteToken(token)) } catch (e) { setError(errorMessage(e)) }
  }, [token])

  useEffect(() => { cargar() }, [cargar])
  useEffect(() => {
    try { const n = localStorage.getItem(CLAVE_NOMBRE); if (n) setNombre(n) } catch { /* sin almacenamiento */ }
  }, [])
  useEffect(() => {
    if (rep?.valido && rep.responsable && !nombre) setNombre(rep.responsable)
  }, [rep, nombre])

  if (error) return <Marco><Aviso icono={XCircle} color="text-red-600" texto={error} /></Marco>
  if (!rep) return <Marco><div className="flex justify-center py-16"><Loader2 className="h-7 w-7 animate-spin text-emerald-700" /></div></Marco>
  if (!rep.valido) return <Marco><Aviso icono={XCircle} color="text-red-600" texto={rep.motivo} /></Marco>

  const pendientes = rep.diferencias.filter((d) => d.estado === 'pendiente')
  const porValidar = rep.diferencias.filter((d) => d.estado === 'por_validar')
  const cerradas = rep.diferencias.filter((d) => d.estado === 'cerrada' || d.estado === 'escalada')
  const litros = rep.vehiculos.reduce((s, v) => s + Number(v.litros ?? 0), 0)
  const pago = rep.vehiculos.reduce((s, v) => s + Number(v.pago ?? 0), 0)

  return (
    <Marco>
      <header className="space-y-1">
        <p className="text-xs font-semibold uppercase tracking-wider text-emerald-800">Control de combustible · {rep.operacion}</p>
        <h1 className="text-xl font-bold text-gray-900">Semana del {fecha(rep.semana_desde)} al {fecha(rep.semana_hasta)}</h1>
        <p className="text-sm text-gray-600">
          Cada carga de la tarjeta Aramco se compara con el GPS del vehículo. Las diferencias deben justificarse: qué pasó y quién cargó.
          Horario normal de carga: lunes a viernes de 07:00 a 19:00.
        </p>
      </header>

      <section className="grid grid-cols-3 gap-2">
        <Kpi titulo="Por justificar" valor={String(pendientes.length)} tono={pendientes.length > 0 ? 'rojo' : 'verde'} />
        <Kpi titulo="Litros semana" valor={n0(litros)} />
        <Kpi titulo="Gasto semana" valor={'$' + n0(pago)} />
      </section>

      <label className="block space-y-1">
        <span className="text-sm font-medium text-gray-700">Su nombre (queda registrado en cada justificación)</span>
        <input value={nombre} onChange={(e) => setNombre(e.target.value)}
               className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-emerald-600 focus:outline-none focus:ring-1 focus:ring-emerald-600"
               placeholder="Nombre y apellido" />
      </label>

      {pendientes.length === 0 && (
        <Aviso icono={CheckCircle2} color="text-emerald-700" texto="No hay diferencias por justificar. Gracias." />
      )}
      {pendientes.length > 0 && (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">Por justificar ({pendientes.length})</h2>
          {pendientes.map((d) => (
            <TarjetaDiferencia key={d.carga_id} d={d} token={token} nombre={nombre}
                               onListo={() => { try { localStorage.setItem(CLAVE_NOMBRE, nombre) } catch { /* nada */ } cargar() }} />
          ))}
        </section>
      )}

      {porValidar.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">Justificadas, esperando validación ({porValidar.length})</h2>
          {porValidar.map((d) => <Resumen key={d.carga_id} d={d} icono={Clock} color="text-amber-600" />)}
        </section>
      )}

      <section className="space-y-2">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">Consumo de la semana</h2>
        <div className="overflow-hidden rounded-xl border bg-white">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs text-gray-500">
              <tr><th className="px-3 py-2">Vehículo</th><th className="px-3 py-2 text-right">Litros</th><th className="px-3 py-2 text-right">$</th><th className="px-3 py-2 text-right">km GPS</th></tr>
            </thead>
            <tbody className="divide-y">
              {rep.vehiculos.map((v) => (
                <tr key={v.patente}>
                  <td className="px-3 py-2 font-medium">{v.patente}<span className="ml-1 text-xs text-gray-400">{v.cargas}×</span></td>
                  <td className="px-3 py-2 text-right">{n1(v.litros)}</td>
                  <td className="px-3 py-2 text-right">{n0(v.pago)}</td>
                  <td className="px-3 py-2 text-right">{n0(v.km)}</td>
                </tr>
              ))}
              {rep.vehiculos.length === 0 && <tr><td colSpan={4} className="px-3 py-4 text-center text-gray-500">Sin cargas esta semana.</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      {cerradas.length > 0 && (
        <details className="rounded-xl border bg-white px-4 py-3 text-sm">
          <summary className="cursor-pointer font-medium text-gray-600">Cerradas ({cerradas.length})</summary>
          <div className="mt-2 space-y-2">{cerradas.map((d) => <Resumen key={d.carga_id} d={d} icono={CheckCircle2} color="text-emerald-600" />)}</div>
        </details>
      )}
    </Marco>
  )
}

function TarjetaDiferencia({ d, token, nombre, onListo }: { d: DiferenciaComb; token: string; nombre: string; onListo: () => void }) {
  const [texto, setTexto] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  async function enviar() {
    setErr(null)
    if (nombre.trim().length < 3) { setErr('Escriba su nombre arriba.'); return }
    if (texto.trim().length < 15) { setErr('Explique un poco más (mínimo 15 caracteres): qué pasó y quién cargó.'); return }
    setGuardando(true)
    try { await justificarConToken(token, d.carga_id, texto, nombre); onListo() }
    catch (e) { setErr(errorMessage(e)) }
    finally { setGuardando(false) }
  }

  return (
    <article className="space-y-3 rounded-xl border border-red-200 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="font-semibold text-gray-900">{d.patente}</p>
          <p className="text-sm capitalize text-gray-600">{fechaHora(d.fecha_hora)}</p>
        </div>
        <div className="text-right text-sm">
          <p className="font-semibold">{n1(d.litros)} L</p>
          <p className="text-gray-500">${n0(d.total_pago)}</p>
        </div>
      </div>
      <p className="flex items-center gap-1 text-xs text-gray-500"><MapPin className="h-3.5 w-3.5" />{d.estacion}{d.chofer ? ` · Chofer en la tarjeta: ${d.chofer}` : ''}</p>
      <ul className="space-y-1">
        {d.alertas.map((a) => (
          <li key={a} className="flex items-center gap-1.5 text-sm font-medium text-red-700">
            <AlertTriangle className="h-4 w-4 shrink-0" />{ALERTA_TXT[a as Alerta] ?? a}
          </li>
        ))}
      </ul>
      {d.rechazada && d.nota_validacion && (
        <p className="rounded-lg bg-red-50 p-2 text-sm text-red-800"><b>La justificación anterior fue rechazada:</b> {d.nota_validacion}</p>
      )}
      <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3}
                className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-emerald-600 focus:outline-none focus:ring-1 focus:ring-emerald-600"
                placeholder="Ej.: Turno de noche en faena Spence, cargó el operador Juan Pérez antes de salir a ruta." />
      {err && <p className="text-sm text-red-700">{err}</p>}
      <button onClick={enviar} disabled={guardando}
              className="w-full rounded-lg bg-emerald-800 py-2.5 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-50">
        {guardando ? 'Guardando…' : 'Enviar justificación'}
      </button>
    </article>
  )
}

function Resumen({ d, icono: I, color }: { d: DiferenciaComb; icono: typeof Clock; color: string }) {
  return (
    <div className="flex gap-2 rounded-lg border bg-white p-3 text-sm">
      <I className={cn('mt-0.5 h-4 w-4 shrink-0', color)} />
      <div>
        <p className="font-medium">{d.patente} · <span className="capitalize">{fechaHora(d.fecha_hora)}</span> · {n1(d.litros)} L</p>
        {d.comentario && <p className="text-gray-600">«{d.comentario}»{d.autor ? ` — ${d.autor}` : ''}</p>}
      </div>
    </div>
  )
}

function Kpi({ titulo, valor, tono }: { titulo: string; valor: string; tono?: 'rojo' | 'verde' }) {
  return (
    <div className="rounded-xl border bg-white p-3">
      <p className="text-[11px] font-medium uppercase tracking-wide text-gray-500">{titulo}</p>
      <p className={cn('mt-1 text-xl font-bold tabular-nums', tono === 'rojo' ? 'text-red-700' : tono === 'verde' ? 'text-emerald-700' : 'text-gray-900')}>{valor}</p>
    </div>
  )
}

function Aviso({ icono: I, color, texto }: { icono: typeof Clock; color: string; texto: string }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border bg-white p-4 text-sm text-gray-700">
      <I className={cn('h-6 w-6 shrink-0', color)} />{texto}
    </div>
  )
}

function Marco({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-gray-50">
      <div className="bg-emerald-900 px-4 py-3 text-white">
        <div className="mx-auto flex max-w-2xl items-center gap-2 text-sm font-semibold"><Fuel className="h-4 w-4" /> SICOM · Pillado</div>
      </div>
      <main className="mx-auto max-w-2xl space-y-5 px-4 py-6">{children}</main>
    </div>
  )
}
