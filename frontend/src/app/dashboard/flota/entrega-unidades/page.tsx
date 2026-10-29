'use client'

// [MIG665] Entrega de unidades en terreno: elegir camiones → 7 fotos + llaves de
// cada uno → quien recibe firma una vez → un acta por camión (imprimible).
// El borrador (fotos ya subidas, datos) se guarda en el teléfono: si se cierra
// la página o se cae la señal, no se pierde lo hecho.

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Camera, CheckCircle2, FileText, KeyRound, Loader2, Search, Truck } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import {
  FOTOS_ENTREGA, getActas, getCamionesEntregables, registrarEntrega, subirFirmaEntrega, subirFotoEntrega,
  type ActaEntrega, type CamionEntrega,
} from '@/lib/services/entregas-unidad'

type Datos = { km: string; horometro: string; llaves: number; copias: number; observaciones: string; fotos: Record<string, string> }
type Borrador = { sel: string[]; datos: Record<string, Datos>; empresa: string; nombre: string; rut: string; cargo: string; lugar: string }

const CLAVE = 'entrega-unidades-borrador'
const VACIO: Borrador = { sel: [], datos: {}, empresa: 'SQM', nombre: '', rut: '', cargo: '', lugar: 'Calama' }
const nuevo = (c: CamionEntrega): Datos => ({
  km: c.kilometraje_actual ? String(Math.round(c.kilometraje_actual)) : '',
  horometro: c.horas_uso_actual ? String(Math.round(c.horas_uso_actual)) : '',
  llaves: 1, copias: 1, observaciones: '', fotos: {},
})

function leerBorrador(): Borrador {
  try { const s = localStorage.getItem(CLAVE); return s ? { ...VACIO, ...JSON.parse(s) } : VACIO } catch { return VACIO }
}

export default function EntregaUnidadesPage() {
  const { loading: authLoading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const router = useRouter()
  const camiones = useQuery({ queryKey: ['entrega-unidades', 'camiones'], queryFn: getCamionesEntregables, enabled: !authLoading })
  const actas = useQuery({ queryKey: ['entrega-unidades', 'actas'], queryFn: getActas, enabled: !authLoading })

  const [b, setB] = useState<Borrador>(VACIO)
  const [cargado, setCargado] = useState(false)
  useEffect(() => { setB(leerBorrador()); setCargado(true) }, [])
  useEffect(() => { if (cargado) try { localStorage.setItem(CLAVE, JSON.stringify(b)) } catch { /* sin almacenamiento */ } }, [b, cargado])

  const [buscar, setBuscar] = useState('')
  const [soloCalama, setSoloCalama] = useState(true)
  const [subiendo, setSubiendo] = useState<Record<string, boolean>>({})
  const [firma, setFirma] = useState<string | null>(null)
  const [guardando, setGuardando] = useState(false)

  const porId = useMemo(() => new Map((camiones.data ?? []).map((c) => [c.id, c])), [camiones.data])
  const lista = useMemo(() => {
    const q = buscar.trim().toUpperCase().replace(/-/g, '')
    return (camiones.data ?? []).filter((c) =>
      (!soloCalama || c.operacion === 'Calama' || b.sel.includes(c.id))
      && (!q || c.patente.replace(/-/g, '').includes(q) || (c.codigo ?? '').toUpperCase().includes(q)))
  }, [camiones.data, buscar, soloCalama, b.sel])

  const elegidos = b.sel.map((id) => porId.get(id)).filter((c): c is CamionEntrega => !!c)

  function alternar(c: CamionEntrega) {
    setB((x) => x.sel.includes(c.id)
      ? { ...x, sel: x.sel.filter((i) => i !== c.id) }
      : { ...x, sel: [...x.sel, c.id], datos: { ...x.datos, [c.id]: x.datos[c.id] ?? nuevo(c) } })
  }
  function cambiar(id: string, campo: Partial<Datos>) {
    setB((x) => ({ ...x, datos: { ...x.datos, [id]: { ...x.datos[id], ...campo } } }))
  }
  async function foto(id: string, tipo: string, file: File | undefined) {
    if (!file) return
    const k = `${id}|${tipo}`
    setSubiendo((s) => ({ ...s, [k]: true }))
    try {
      const url = await subirFotoEntrega(id, tipo, file)
      setB((x) => ({ ...x, datos: { ...x.datos, [id]: { ...x.datos[id], fotos: { ...x.datos[id].fotos, [tipo]: url } } } }))
    } catch (e) {
      toast.error(`${errorMessage(e)} Revise la señal y saque la foto de nuevo.`)
    } finally {
      setSubiendo((s) => ({ ...s, [k]: false }))
    }
  }

  const faltan = elegidos.flatMap((c) => {
    const d = b.datos[c.id]
    const f = FOTOS_ENTREGA.filter((t) => !d?.fotos[t.tipo]).length
    return [f ? `${c.patente}: ${f} foto${f > 1 ? 's' : ''}` : '', !d || d.llaves < 1 ? `${c.patente}: llaves` : ''].filter(Boolean)
  })
  const listoRecibe = b.empresa.trim().length >= 2 && b.nombre.trim().length >= 3 && b.rut.trim().length >= 7 && !!firma
  const enProceso = Object.values(subiendo).some(Boolean)

  async function firmarEntrega() {
    setGuardando(true)
    try {
      const firmaUrl = await subirFirmaEntrega(firma!)
      const r = await registrarEntrega(elegidos.map((c) => {
        const d = b.datos[c.id]
        return { activo_id: c.id, km: d.km, horometro: d.horometro, llaves: d.llaves, copias: d.copias,
          observaciones: d.observaciones, fotos: Object.entries(d.fotos).map(([tipo, url]) => ({ tipo, url })) }
      }), { empresa: b.empresa, nombre: b.nombre, rut: b.rut, cargo: b.cargo, firma_url: firmaUrl }, b.lugar)
      toast.success(`Entrega firmada: ${r.actas.map((a) => `${a.patente} (${a.folio})`).join(', ')}`)
      setB(VACIO); setFirma(null)
      try { localStorage.removeItem(CLAVE) } catch { /* sin almacenamiento */ }
      qc.invalidateQueries({ queryKey: ['entrega-unidades'] })
      router.push(`/dashboard/flota/entrega-unidades/acta/?lote=${r.lote_id}`)
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setGuardando(false)
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-4 p-3 sm:p-4">
      <header>
        <h1 className="text-xl font-bold text-gray-900">Entrega de unidades</h1>
        <p className="text-sm text-gray-600">
          Elija los camiones que entrega hoy, saque las 7 fotos de cada uno y anote las llaves. Al final, quien recibe firma una
          vez y queda un acta por camión.
        </p>
      </header>

      {/* 1. Camiones */}
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2 text-base"><Truck className="h-4 w-4" /> 1. ¿Qué camiones entrega?</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative min-w-[180px] flex-1">
              <Search className="absolute left-2 top-2.5 h-4 w-4 text-gray-400" />
              <input value={buscar} onChange={(e) => setBuscar(e.target.value)} placeholder="Buscar patente"
                     className="w-full rounded border py-2 pl-8 pr-2 text-sm" />
            </div>
            <label className="flex items-center gap-1.5 text-sm text-gray-700">
              <input type="checkbox" checked={soloCalama} onChange={(e) => setSoloCalama(e.target.checked)} /> Solo Calama
            </label>
          </div>
          {camiones.isLoading ? <p className="text-sm text-gray-500">Cargando…</p> : (
            <div className="grid max-h-72 grid-cols-2 gap-1.5 overflow-y-auto sm:grid-cols-3">
              {lista.map((c) => {
                const on = b.sel.includes(c.id)
                return (
                  <button key={c.id} type="button" onClick={() => alternar(c)}
                          className={cn('rounded border px-2 py-2 text-left text-sm',
                            on ? 'border-blue-600 bg-blue-50 ring-1 ring-blue-600' : 'border-gray-200 hover:bg-gray-50')}>
                    <span className="flex items-center gap-1 font-semibold">{on && <CheckCircle2 className="h-4 w-4 text-blue-600" />}{c.patente}</span>
                    <span className="block truncate text-xs text-gray-500">{c.codigo ?? ''} {c.tipo_equipamiento?.replace(/_/g, ' ') ?? ''}</span>
                  </button>
                )
              })}
            </div>
          )}
          <p className="text-sm text-gray-700">{elegidos.length ? `Seleccionados: ${elegidos.map((c) => c.patente).join(', ')}` : 'Ningún camión seleccionado.'}</p>
        </CardContent>
      </Card>

      {/* 2. Cada camión */}
      {elegidos.map((c) => {
        const d = b.datos[c.id]
        if (!d) return null
        const nFotos = FOTOS_ENTREGA.filter((t) => d.fotos[t.tipo]).length
        return (
          <Card key={c.id}>
            <CardHeader>
              <CardTitle className="flex items-center justify-between text-base">
                <span>2. {c.patente} <span className="text-sm font-normal text-gray-500">{c.codigo}</span></span>
                <span className={cn('text-sm font-medium', nFotos === FOTOS_ENTREGA.length ? 'text-green-700' : 'text-amber-700')}>
                  {nFotos}/{FOTOS_ENTREGA.length} fotos
                </span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {FOTOS_ENTREGA.map((t) => {
                  const url = d.fotos[t.tipo]
                  const sub = subiendo[`${c.id}|${t.tipo}`]
                  return (
                    <label key={t.tipo} className={cn('relative flex h-28 cursor-pointer flex-col items-center justify-center overflow-hidden rounded border text-center text-xs',
                      url ? 'border-green-600' : 'border-dashed border-gray-300 bg-gray-50')}>
                      {url
                        ? <img src={url} alt={t.txt} className="absolute inset-0 h-full w-full object-cover" />
                        : sub ? <Loader2 className="h-5 w-5 animate-spin text-gray-500" /> : <Camera className="h-5 w-5 text-gray-500" />}
                      <span className={cn('relative z-10 mt-1 rounded px-1', url ? 'bg-black/60 text-white' : 'text-gray-700')}>{t.txt}</span>
                      <input type="file" accept="image/*" capture="environment" className="hidden" disabled={sub}
                             onChange={(e) => { foto(c.id, t.tipo, e.target.files?.[0]); e.target.value = '' }} />
                    </label>
                  )
                })}
              </div>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                <Campo t="Km"><input inputMode="numeric" value={d.km} onChange={(e) => cambiar(c.id, { km: e.target.value })} className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
                <Campo t="Horómetro"><input inputMode="numeric" value={d.horometro} onChange={(e) => cambiar(c.id, { horometro: e.target.value })} className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
                <Campo t="Llaves que recibe"><Numero v={d.llaves} min={1} on={(v) => cambiar(c.id, { llaves: v })} /></Campo>
                <Campo t="Copias en Pillado"><Numero v={d.copias} min={0} on={(v) => cambiar(c.id, { copias: v })} /></Campo>
              </div>
              <Campo t="Observaciones (opcional)">
                <textarea value={d.observaciones} onChange={(e) => cambiar(c.id, { observaciones: e.target.value })} rows={2}
                          placeholder="Daños, faltantes, nivel de combustible…" className="w-full rounded border px-2 py-1.5 text-sm" />
              </Campo>
            </CardContent>
          </Card>
        )
      })}

      {/* 3. Recibe y firma */}
      {elegidos.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2 text-base"><KeyRound className="h-4 w-4" /> 3. Quien recibe firma</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <Campo t="Empresa que recibe"><input value={b.empresa} onChange={(e) => setB({ ...b, empresa: e.target.value })} className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
              <Campo t="Lugar"><input value={b.lugar} onChange={(e) => setB({ ...b, lugar: e.target.value })} className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
              <Campo t="Nombre de quien recibe"><input value={b.nombre} onChange={(e) => setB({ ...b, nombre: e.target.value })} className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
              <Campo t="RUT"><input value={b.rut} onChange={(e) => setB({ ...b, rut: e.target.value })} placeholder="12.345.678-9" className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
              <Campo t="Cargo (opcional)"><input value={b.cargo} onChange={(e) => setB({ ...b, cargo: e.target.value })} className="w-full rounded border px-2 py-1.5 text-sm" /></Campo>
            </div>
            <div className="rounded border bg-gray-50 p-2 text-sm text-gray-700">
              Recibe {elegidos.length} camión{elegidos.length > 1 ? 'es' : ''}:{' '}
              {elegidos.map((c) => `${c.patente} (${b.datos[c.id]?.llaves ?? 0} llave${(b.datos[c.id]?.llaves ?? 0) > 1 ? 's' : ''})`).join(', ')}.
              Las copias de las llaves quedan en Pillado.
            </div>
            <SignaturePad onCapture={setFirma} label="Firma de quien recibe (toque «Guardar firma» al terminar)" />
            {faltan.length > 0 && <p className="text-sm text-amber-700">Falta: {faltan.join(' · ')}</p>}
            <button type="button" disabled={guardando || enProceso || faltan.length > 0 || !listoRecibe} onClick={firmarEntrega}
                    className="w-full rounded bg-green-600 px-4 py-3 text-base font-semibold text-white hover:bg-green-700 disabled:opacity-40">
              {guardando ? 'Guardando…' : `Firmar entrega de ${elegidos.length} camión${elegidos.length > 1 ? 'es' : ''}`}
            </button>
          </CardContent>
        </Card>
      )}

      {/* Actas */}
      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2 text-base"><FileText className="h-4 w-4" /> Actas firmadas</CardTitle></CardHeader>
        <CardContent>
          <Actas filas={actas.data ?? []} />
        </CardContent>
      </Card>
    </div>
  )
}

function Actas({ filas }: { filas: ActaEntrega[] }) {
  if (!filas.length) return <p className="text-sm text-gray-500">Todavía no hay actas.</p>
  const lotes = new Map<string, ActaEntrega[]>()
  for (const a of filas) lotes.set(a.lote_id, [...(lotes.get(a.lote_id) ?? []), a])
  return (
    <ul className="divide-y text-sm">
      {Array.from(lotes.entries()).map(([lote, as]) => (
        <li key={lote} className="flex flex-wrap items-baseline justify-between gap-2 py-2">
          <span>
            <b>{new Date(as[0].fecha).toLocaleDateString('es-CL')}</b> · {as[0].empresa_recibe} · recibe {as[0].recibe_nombre}
            <span className="block text-xs text-gray-600">
              {as.map((a) => <span key={a.id} className={cn('mr-2', a.estado === 'anulada' && 'line-through text-gray-400')}>{a.patente} {a.folio}</span>)}
            </span>
          </span>
          <Link href={`/dashboard/flota/entrega-unidades/acta/?lote=${lote}`} className="text-blue-600 hover:underline">Ver / imprimir</Link>
        </li>
      ))}
    </ul>
  )
}

function Campo({ t, children }: { t: string; children: React.ReactNode }) {
  return <label className="block text-xs font-medium text-gray-600">{t}<div className="mt-0.5">{children}</div></label>
}

function Numero({ v, min, on }: { v: number; min: number; on: (v: number) => void }) {
  return (
    <div className="flex items-center gap-1">
      <button type="button" onClick={() => on(Math.max(min, v - 1))} className="h-8 w-8 rounded border text-lg">−</button>
      <span className="w-8 text-center text-sm font-semibold tabular-nums">{v}</span>
      <button type="button" onClick={() => on(v + 1)} className="h-8 w-8 rounded border text-lg">+</button>
    </div>
  )
}
