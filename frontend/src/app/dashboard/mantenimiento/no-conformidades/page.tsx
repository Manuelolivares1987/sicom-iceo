'use client'

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ClipboardList, Wrench, PlusCircle, Trash2, CheckCircle2, Loader2, Package,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getNcRecepcion, asignarRecursosNc, planificarNc, registrarNcAdhoc, generarNcDesdeRecepcion,
  getRecepcionesParaNc, getActivosParaNc, type NcRecepcion, type NcMaterial,
} from '@/lib/services/no-conformidades'
import { getProductos } from '@/lib/services/inventario'
import { MECANICOS } from '@/lib/taller-grupos'
import { cn } from '@/lib/utils'

const ESTADO_BADGE: Record<string, { v: any; t: string }> = {
  registrada: { v: 'default', t: 'Registrada' },
  con_recursos: { v: 'asignada', t: 'Con recursos' },
  planificada: { v: 'en_ejecucion', t: 'Planificada' },
  en_ejecucion: { v: 'en_ejecucion', t: 'En ejecución' },
  resuelta: { v: 'operativo', t: 'Resuelta' },
  descartada: { v: 'default', t: 'Descartada' },
}
const FILTROS = [['', 'Todas'], ['registrada', 'Sin recursos'], ['con_recursos', 'Con recursos'], ['planificada', 'Planificadas']] as const

export default function NoConformidadesPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('')
  const { data: ncs = [], isLoading } = useQuery({ queryKey: ['nc-recepcion', filtro], queryFn: () => getNcRecepcion(filtro || undefined), staleTime: 20_000 })
  const [recursosNc, setRecursosNc] = useState<NcRecepcion | null>(null)
  const [genOpen, setGenOpen] = useState(false)
  const [adhocOpen, setAdhocOpen] = useState(false)
  const [busyId, setBusyId] = useState<string | null>(null)

  const invalidar = () => qc.invalidateQueries({ queryKey: ['nc-recepcion'] })

  const kpi = useMemo(() => ({
    total: ncs.length,
    sin: ncs.filter((n) => n.estado_planificacion === 'registrada').length,
    con: ncs.filter((n) => n.estado_planificacion === 'con_recursos').length,
    plan: ncs.filter((n) => n.estado_planificacion === 'planificada').length,
  }), [ncs])

  const planificar = async (nc: NcRecepcion) => {
    setBusyId(nc.id)
    try {
      await planificarNc(nc.id)
      toast.success('NC planificada: se creó la OT correctiva')
      invalidar(); qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al planificar') } finally { setBusyId(null) }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2"><AlertTriangle className="h-6 w-6 text-orange-600" /> No Conformidades (Recepción)</h1>
          <p className="text-sm text-muted-foreground">Nacen del checklist de recepción (y ad-hoc). Asigna recursos y planifícalas como trabajo correctivo.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setGenOpen(true)}><ClipboardList className="h-4 w-4 mr-1" /> Generar del checklist</Button>
          <Button variant="outline" onClick={() => setAdhocOpen(true)}><PlusCircle className="h-4 w-4 mr-1" /> Registrar NC ad-hoc</Button>
        </div>
      </div>

      <div className="grid gap-3 grid-cols-2 md:grid-cols-4">
        <Kpi label="Total" value={kpi.total} />
        <Kpi label="Sin recursos" value={kpi.sin} warn={kpi.sin > 0} />
        <Kpi label="Con recursos" value={kpi.con} />
        <Kpi label="Planificadas" value={kpi.plan} />
      </div>

      <div className="flex gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)} className={cn('rounded-full border px-3 py-1 text-xs', filtro === k ? 'bg-orange-600 text-white border-orange-600' : 'hover:bg-muted')}>{l}</button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {isLoading && <div className="p-4"><Spinner className="h-5 w-5" /></div>}
          <table className="w-full text-sm">
            <thead><tr className="text-xs text-muted-foreground border-b">
              <th className="text-left p-2">Equipo</th><th className="text-left p-2">No Conformidad</th>
              <th className="p-2">Sev.</th><th className="p-2">Origen</th><th className="text-left p-2">Recursos</th>
              <th className="p-2">Estado</th><th className="p-2"></th>
            </tr></thead>
            <tbody>
              {ncs.map((nc) => (
                <tr key={nc.id} className="border-b hover:bg-muted/40">
                  <td className="p-2 font-medium whitespace-nowrap">{nc.patente ?? nc.codigo}</td>
                  <td className="p-2">{nc.descripcion}</td>
                  <td className="p-2 text-center"><Badge variant={nc.severidad as any} className="text-[10px]">{nc.severidad}</Badge></td>
                  <td className="p-2 text-center text-[11px] text-muted-foreground">{nc.origen === 'recepcion_adhoc' ? 'ad-hoc' : 'checklist'}</td>
                  <td className="p-2 text-xs text-muted-foreground">
                    {nc.grupo_trabajo || nc.horas_estimadas || nc.n_materiales > 0
                      ? `${nc.grupo_trabajo ?? '—'}${nc.horas_estimadas ? ` · ${nc.horas_estimadas}h` : ''}${nc.tiempo_estimado_dias ? ` · ${nc.tiempo_estimado_dias}d` : ''}${nc.n_materiales ? ` · ${nc.n_materiales} mat.` : ''}`
                      : <span className="text-amber-600">sin asignar</span>}
                  </td>
                  <td className="p-2 text-center"><Badge variant={(ESTADO_BADGE[nc.estado_planificacion]?.v) ?? 'default'} className="text-[10px]">{ESTADO_BADGE[nc.estado_planificacion]?.t ?? nc.estado_planificacion}</Badge></td>
                  <td className="p-2 whitespace-nowrap text-right">
                    <Button size="sm" variant="outline" onClick={() => setRecursosNc(nc)}><Package className="h-3.5 w-3.5 mr-1" /> Recursos</Button>
                    {!nc.plan_ot_id && (
                      <Button size="sm" className="ml-1" disabled={busyId === nc.id} onClick={() => planificar(nc)}>
                        {busyId === nc.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Wrench className="h-3.5 w-3.5 mr-1" />} Planificar
                      </Button>
                    )}
                    {nc.plan_ot_id && <Badge variant="en_ejecucion" className="ml-1 text-[10px]">OT creada</Badge>}
                  </td>
                </tr>
              ))}
              {!isLoading && ncs.length === 0 && <tr><td colSpan={7} className="p-6 text-center text-muted-foreground">Sin No Conformidades. Genera desde un checklist de recepción o registra una ad-hoc.</td></tr>}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {recursosNc && <AsignarRecursosModal nc={recursosNc} onClose={() => setRecursosNc(null)} onDone={() => { setRecursosNc(null); invalidar() }} />}
      {genOpen && <GenerarDesdeRecepcionModal onClose={() => setGenOpen(false)} onDone={() => { setGenOpen(false); invalidar() }} />}
      {adhocOpen && <RegistrarNcModal onClose={() => setAdhocOpen(false)} onDone={() => { setAdhocOpen(false); invalidar() }} />}
    </div>
  )
}

function Kpi({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  return <Card><CardContent className="p-3"><div className="text-xs text-muted-foreground">{label}</div><div className={cn('text-2xl font-bold', warn && 'text-amber-600')}>{value}</div></CardContent></Card>
}

function AsignarRecursosModal({ nc, onClose, onDone }: { nc: NcRecepcion; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: prodRes } = useQuery({ queryKey: ['productos-nc'], queryFn: () => getProductos(), staleTime: 300_000 })
  const productos = (prodRes?.data ?? []) as Array<{ id: string; codigo: string; nombre: string }>

  const [mecanicos, setMecanicos] = useState<string[]>(() =>
    (nc.grupo_trabajo ?? '').split(',').map((s) => s.trim()).filter((s) => (MECANICOS as readonly string[]).includes(s)))
  const [horas, setHoras] = useState(nc.horas_estimadas?.toString() ?? '')
  const [dias, setDias] = useState(nc.tiempo_estimado_dias?.toString() ?? '')
  const [mats, setMats] = useState<NcMaterial[]>([{ producto_id: '', descripcion: '', cantidad: 1 }])
  const [saving, setSaving] = useState(false)

  const toggleMec = (m: string) => setMecanicos((prev) => prev.includes(m) ? prev.filter((x) => x !== m) : [...prev, m])

  const submit = async () => {
    setSaving(true)
    try {
      const materiales = mats
        .filter((m) => m.producto_id || (m.descripcion ?? '').trim())
        .map((m) => ({ producto_id: m.producto_id || null, descripcion: m.descripcion, cantidad: Number(m.cantidad) || 1 }))
      await asignarRecursosNc({
        ncId: nc.id,
        grupo: mecanicos.length ? mecanicos.join(', ') : null,
        horas: horas ? Number(horas) : null,
        tiempoDias: dias ? Number(dias) : null,
        materiales,
      })
      toast.success('Recursos asignados')
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Recursos · ${nc.patente ?? nc.codigo}`}>
      <div className="space-y-3">
        <p className="text-xs text-gray-500">{nc.descripcion}</p>
        <div>
          <label className="text-xs font-medium">Grupo de trabajo (mano de obra)</label>
          <div className="mt-1 flex flex-wrap gap-1">
            {MECANICOS.map((m) => {
              const on = mecanicos.includes(m)
              return (
                <button key={m} type="button" onClick={() => toggleMec(m)}
                  className={`rounded border px-2 py-1 text-[11px] ${on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>{m}</button>
              )
            })}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium">Horas estimadas (MO)
            <input type="number" value={horas} onChange={(e) => setHoras(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">Tiempo (días)
            <input type="number" value={dias} onChange={(e) => setDias(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
        </div>
        <div>
          <div className="text-xs font-medium mb-1 flex items-center gap-1"><Package className="h-3.5 w-3.5" /> Materiales (catálogo de bodega)</div>
          <div className="space-y-1">
            {mats.map((m, i) => (
              <div key={i} className="flex gap-1">
                <select value={m.producto_id ?? ''}
                  onChange={(e) => {
                    const p = productos.find((x) => x.id === e.target.value)
                    setMats((s) => s.map((x, j) => j === i ? { ...x, producto_id: e.target.value, descripcion: p ? `${p.codigo} · ${p.nombre}` : '' } : x))
                  }}
                  className="flex-1 rounded border px-2 py-1 text-sm">
                  <option value="">— Repuesto / material —</option>
                  {productos.map((p) => <option key={p.id} value={p.id}>{p.codigo} · {p.nombre}</option>)}
                </select>
                <input type="number" value={m.cantidad} onChange={(e) => setMats((s) => s.map((x, j) => j === i ? { ...x, cantidad: Number(e.target.value) } : x))} className="w-16 rounded border px-2 py-1 text-sm" />
                <button onClick={() => setMats((s) => s.filter((_, j) => j !== i))} className="text-red-500 px-1"><Trash2 className="h-4 w-4" /></button>
              </div>
            ))}
          </div>
          <button onClick={() => setMats((s) => [...s, { producto_id: '', descripcion: '', cantidad: 1 }])} className="text-xs text-blue-600 mt-1">+ Agregar material</button>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving}>{saving ? 'Guardando…' : 'Guardar recursos'}</Button>
      </ModalFooter>
    </Modal>
  )
}

function GenerarDesdeRecepcionModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: receps = [] } = useQuery({ queryKey: ['recepciones-para-nc'], queryFn: getRecepcionesParaNc })
  const [busy, setBusy] = useState<string | null>(null)
  const generar = async (informeId: string, patente: string) => {
    setBusy(informeId)
    try {
      const r: any = await generarNcDesdeRecepcion(informeId)
      toast.success(`${r?.creadas ?? 0} No Conformidad(es) generada(s) de ${patente}`)
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(null) }
  }
  return (
    <Modal open onClose={onClose} title="Generar NC desde checklist de recepción">
      <div className="space-y-1 max-h-80 overflow-auto">
        <p className="text-xs text-gray-500 mb-2">Toma los ítems «no OK» del checklist de la recepción y crea una NC por cada uno.</p>
        {receps.length === 0 && <p className="text-sm text-muted-foreground py-4 text-center">Sin recepciones.</p>}
        {receps.map((r: any) => (
          <div key={r.id} className="flex items-center justify-between border rounded p-2 text-sm">
            <div><b>{r.patente ?? r.activo_codigo}</b> <span className="text-xs text-muted-foreground">· {r.folio} · {r.estado}</span></div>
            <Button size="sm" variant="outline" disabled={busy === r.id} onClick={() => generar(r.id, r.patente ?? r.activo_codigo)}>
              {busy === r.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4 mr-1" />} Generar
            </Button>
          </div>
        ))}
      </div>
      <ModalFooter><Button variant="outline" onClick={onClose}>Cerrar</Button></ModalFooter>
    </Modal>
  )
}

function RegistrarNcModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const { data: activos = [] } = useQuery({ queryKey: ['activos-para-nc'], queryFn: getActivosParaNc })
  const [activoId, setActivoId] = useState('')
  const [desc, setDesc] = useState('')
  const [sev, setSev] = useState('media')
  const [saving, setSaving] = useState(false)
  const submit = async () => {
    if (!activoId || !desc.trim()) { toast.error('Equipo y descripción obligatorios'); return }
    setSaving(true)
    try {
      await registrarNcAdhoc({ activoId, descripcion: desc, severidad: sev })
      toast.success('No Conformidad registrada')
      onDone()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setSaving(false) }
  }
  return (
    <Modal open onClose={onClose} title="Registrar No Conformidad (ad-hoc)">
      <div className="space-y-3">
        <p className="text-xs text-gray-500">Para las NC que el grupo encuentra y NO estaban en el checklist (mejora continua).</p>
        <label className="text-xs font-medium block">Equipo
          <select value={activoId} onChange={(e) => setActivoId(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm">
            <option value="">—</option>
            {(activos as any[]).map((a) => <option key={a.id} value={a.id}>{a.patente ?? a.codigo}</option>)}
          </select>
        </label>
        <label className="text-xs font-medium block">Descripción
          <textarea value={desc} onChange={(e) => setDesc(e.target.value)} rows={2} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
        </label>
        <label className="text-xs font-medium block">Severidad
          <select value={sev} onChange={(e) => setSev(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm">
            <option value="baja">Baja</option><option value="media">Media</option><option value="alta">Alta</option><option value="critica">Crítica</option>
          </select>
        </label>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving}>{saving ? 'Guardando…' : 'Registrar'}</Button>
      </ModalFooter>
    </Modal>
  )
}
