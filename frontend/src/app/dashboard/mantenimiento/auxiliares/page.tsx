'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, Layers, Plus, Wrench, AlertTriangle, Check } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getEquiposPadre, getAuxiliares, getPautasTodas, crearAuxiliar, asignarPauta,
  type EquipoSimple, type Auxiliar, type PautaOpcion, type TipoAuxiliar,
} from '@/lib/services/taller-planificacion'

const TIPO_AUX: { value: TipoAuxiliar; label: string }[] = [
  { value: 'estanque', label: 'Aljibe / Estanque' },
  { value: 'bomba', label: 'Bomba' },
  { value: 'manguera', label: 'Manguera' },
  { value: 'equipo_menor', label: 'Pluma / Grúa / Otro' },
]

export default function AuxiliaresPage() {
  useRequireAuth()
  const [padres, setPadres] = useState<EquipoSimple[]>([])
  const [pautas, setPautas] = useState<PautaOpcion[]>([])
  const [padreId, setPadreId] = useState('')
  const [auxiliares, setAuxiliares] = useState<Auxiliar[]>([])
  const [loading, setLoading] = useState(true)
  const [cargandoAux, setCargandoAux] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // form nuevo auxiliar
  const [nombre, setNombre] = useState('')
  const [tipo, setTipo] = useState<TipoAuxiliar>('estanque')
  const [creando, setCreando] = useState(false)

  useEffect(() => {
    Promise.all([getEquiposPadre(), getPautasTodas()])
      .then(([p, pa]) => { setPadres(p); setPautas(pa) })
      .catch((e) => setError((e as Error).message))
      .finally(() => setLoading(false))
  }, [])

  const cargarAux = async (id: string) => {
    if (!id) { setAuxiliares([]); return }
    setCargandoAux(true)
    try { setAuxiliares(await getAuxiliares(id)) }
    catch (e) { setError((e as Error).message) }
    finally { setCargandoAux(false) }
  }
  useEffect(() => { cargarAux(padreId) }, [padreId])

  const padreSel = useMemo(() => padres.find((p) => p.id === padreId) ?? null, [padres, padreId])

  const agregar = async () => {
    if (!padreId || !nombre.trim()) return
    setCreando(true); setError(null)
    try {
      await crearAuxiliar(padreId, nombre.trim(), tipo)
      setNombre('')
      await cargarAux(padreId)
    } catch (e) { setError((e as Error).message) }
    finally { setCreando(false) }
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex items-center gap-3">
        <Link href="/dashboard/mantenimiento">
          <Button variant="ghost" size="sm" className="gap-1"><ArrowLeft className="h-4 w-4" /> Mantenimiento</Button>
        </Link>
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold"><Layers className="h-6 w-6 text-indigo-600" /> Equipos auxiliares</h1>
          <p className="text-sm text-muted-foreground">Vincula los auxiliares de cada equipo (aljibe, bomba, pluma…) y asígnales su pauta.</p>
        </div>
      </div>

      {error && (
        <Card className="border-red-200 bg-red-50"><CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
          <AlertTriangle className="h-4 w-4" /> {error}
        </CardContent></Card>
      )}

      {loading ? <div className="flex h-48 items-center justify-center"><Spinner /></div> : (
        <>
          <Card><CardContent className="p-4">
            <label className="text-xs">
              <span className="mb-1 block font-semibold uppercase text-gray-500">Equipo principal</span>
              <select className="h-10 w-full max-w-md rounded border border-gray-300 px-2 text-sm" value={padreId} onChange={(e) => setPadreId(e.target.value)}>
                <option value="">— Selecciona un equipo —</option>
                {padres.map((p) => (<option key={p.id} value={p.id}>{p.patente ?? p.codigo} · {p.nombre}</option>))}
              </select>
            </label>
          </CardContent></Card>

          {padreSel && (
            <Card><CardContent className="space-y-4 p-4">
              <div className="text-sm font-semibold text-gray-700">Auxiliares de {padreSel.patente ?? padreSel.codigo}</div>

              {cargandoAux ? <Spinner className="h-5 w-5" /> : auxiliares.length === 0 ? (
                <p className="text-sm text-gray-400">Este equipo no tiene auxiliares vinculados aún.</p>
              ) : (
                <div className="space-y-2">
                  {auxiliares.map((a) => <AuxRow key={a.id} aux={a} pautas={pautas} onChange={() => cargarAux(padreId)} />)}
                </div>
              )}

              {/* Agregar auxiliar */}
              <div className="rounded-lg border border-dashed border-gray-300 p-3">
                <div className="mb-2 flex items-center gap-1 text-sm font-semibold text-gray-700"><Plus className="h-4 w-4" /> Agregar auxiliar</div>
                <div className="flex flex-wrap items-end gap-2">
                  <label className="text-xs">
                    <span className="mb-0.5 block text-gray-500">Nombre</span>
                    <input className="h-9 w-56 rounded border border-gray-300 px-2 text-sm" placeholder="Ej: Bomba aljibe CL" value={nombre} onChange={(e) => setNombre(e.target.value)} />
                  </label>
                  <label className="text-xs">
                    <span className="mb-0.5 block text-gray-500">Tipo</span>
                    <select className="h-9 rounded border border-gray-300 px-2 text-sm" value={tipo} onChange={(e) => setTipo(e.target.value as TipoAuxiliar)}>
                      {TIPO_AUX.map((t) => (<option key={t.value} value={t.value}>{t.label}</option>))}
                    </select>
                  </label>
                  <Button size="sm" className="gap-1 bg-indigo-600 hover:bg-indigo-700" disabled={creando || !nombre.trim()} onClick={agregar}>
                    <Plus className="h-4 w-4" /> {creando ? 'Agregando…' : 'Agregar'}
                  </Button>
                </div>
              </div>
            </CardContent></Card>
          )}
        </>
      )}
    </div>
  )
}

function AuxRow({ aux, pautas, onChange }: { aux: Auxiliar; pautas: PautaOpcion[]; onChange: () => void }) {
  const [pautaId, setPautaId] = useState('')
  const [asignando, setAsignando] = useState(false)
  const [ok, setOk] = useState(false)

  const asignar = async () => {
    if (!pautaId) return
    setAsignando(true)
    try { await asignarPauta(aux.id, pautaId); setOk(true); setPautaId(''); onChange() }
    finally { setAsignando(false) }
  }

  return (
    <div className="rounded-lg border border-gray-200 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <span className="font-semibold">{aux.nombre}</span>
          <span className="ml-2 rounded bg-gray-100 px-1.5 py-0.5 text-[10px] uppercase text-gray-600">{aux.tipo}</span>
          <span className="ml-2 font-mono text-xs text-gray-400">{aux.codigo}</span>
        </div>
      </div>

      {/* Pautas asignadas */}
      <div className="mt-2 flex flex-wrap gap-1">
        {aux.planes.length === 0 ? (
          <span className="text-xs text-gray-400">Sin pauta asignada.</span>
        ) : aux.planes.map((p) => (
          <span key={p.id} className="flex items-center gap-1 rounded bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700">
            <Wrench className="h-3 w-3" /> {p.pauta_nombre}{p.duracion_estimada_hrs != null ? ` (${p.duracion_estimada_hrs} h)` : ''}
          </span>
        ))}
      </div>

      {/* Asignar pauta */}
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <select className="h-8 max-w-xs rounded border border-gray-300 px-1 text-xs" value={pautaId} onChange={(e) => { setPautaId(e.target.value); setOk(false) }}>
          <option value="">— Asignar pauta —</option>
          {pautas.map((p) => (<option key={p.id} value={p.id}>{p.nombre}{p.duracion_estimada_hrs != null ? ` (${p.duracion_estimada_hrs} h)` : ''}</option>))}
        </select>
        <Button size="sm" variant="outline" disabled={asignando || !pautaId} onClick={asignar}>
          {asignando ? '…' : 'Asignar'}
        </Button>
        {ok && <span className="flex items-center gap-1 text-xs text-green-600"><Check className="h-3.5 w-3.5" /> asignada</span>}
      </div>
    </div>
  )
}
