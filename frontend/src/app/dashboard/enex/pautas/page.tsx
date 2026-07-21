'use client'

// Editor de pautas ENEX (MIG207): crear/editar checklists de mantención y
// calibración por tipo de instalación. Los borradores redactados por el
// sistema se corrigen aquí sin depender de migraciones.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import {
  ClipboardList, ArrowLeft, Plus, Pencil, Trash2, Camera, Ruler, ChevronDown, ChevronRight, Download, AlertTriangle,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getPautas, getPautaItems, guardarPauta, guardarPautaItem, eliminarPautaItem,
  TIPO_CAMPO_LABEL, TIPO_INSTALACION_LABEL,
  type EnexPauta, type EnexPautaItem, type TipoCampo, type Periodicidad,
} from '@/lib/services/enex'
import { descargarPautasEnexPdf } from '@/components/enex/pdf-pauta-enex'

const PERIODICIDADES: Periodicidad[] = ['trimestral', 'mensual', 'semestral', 'anual', 'requerimiento']
const TIPOS_CAMPO: TipoCampo[] = ['ok_nook', 'medicion', 'si_no', 'texto']

export default function EnexPautasPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [sel, setSel] = useState<string | null>(null)
  const [nuevaPauta, setNuevaPauta] = useState(false)
  const [descargando, setDescargando] = useState(false)

  const { data: pautas = [], isLoading } = useQuery({ queryKey: ['enex-pautas'], queryFn: getPautas, staleTime: 30_000 })
  const pautaSel = pautas.find((p) => p.id === sel) ?? pautas[0]

  async function descargarTodas() {
    setDescargando(true)
    try { await descargarPautasEnexPdf() } catch (e) { toast.error((e as Error).message) } finally { setDescargando(false) }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/dashboard/enex" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-4 w-4" /> Control ENEX
          </Link>
          <h1 className="mt-1 text-xl font-bold flex items-center gap-2">
            <ClipboardList className="h-5 w-5 text-blue-700" /> Pautas de mantención y calibración
          </h1>
          <p className="text-sm text-gray-500">Checklists por tipo de instalación. Los borradores están para revisar y corregir.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" disabled={descargando || pautas.length === 0} onClick={descargarTodas}>
            {descargando ? <Spinner className="h-4 w-4 mr-1" /> : <Download className="h-4 w-4 mr-1" />} Descargar todas (PDF)
          </Button>
          <Button onClick={() => setNuevaPauta(true)}><Plus className="h-4 w-4 mr-1" /> Nueva pauta</Button>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-[280px_1fr]">
        {/* Lista de pautas */}
        <Card>
          <CardContent className="p-2">
            {isLoading ? <div className="p-4"><Spinner /></div> : pautas.map((p) => (
              <button key={p.id} onClick={() => setSel(p.id)}
                      className={`w-full rounded-lg px-3 py-2 text-left ${pautaSel?.id === p.id ? 'bg-blue-50 border border-blue-300' : 'hover:bg-gray-50'}`}>
                <div className="flex items-center gap-1.5">
                  <span className="text-sm font-medium text-gray-800">{p.nombre}</span>
                  {p.es_borrador && <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[9px] font-semibold text-amber-700">borrador</span>}
                </div>
                <div className="text-[11px] text-gray-500">
                  {p.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'} · {p.aplica_tipos.map((t) => TIPO_INSTALACION_LABEL[t] ?? t).join(', ')}
                </div>
              </button>
            ))}
          </CardContent>
        </Card>

        {/* Detalle de la pauta */}
        {pautaSel ? <PautaDetalle pauta={pautaSel} /> : (
          <Card><CardContent className="p-8 text-center text-sm text-gray-400">Elige una pauta o crea una nueva.</CardContent></Card>
        )}
      </div>

      {nuevaPauta && (
        <PautaModal onClose={() => setNuevaPauta(false)}
          onDone={(id) => { setNuevaPauta(false); setSel(id); qc.invalidateQueries({ queryKey: ['enex-pautas'] }) }} />
      )}
    </div>
  )
}

function PautaDetalle({ pauta }: { pauta: EnexPauta }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: items = [] } = useQuery({ queryKey: ['enex-pauta-items', pauta.id], queryFn: () => getPautaItems(pauta.id), staleTime: 15_000 })
  const [editItem, setEditItem] = useState<EnexPautaItem | null>(null)
  const [nuevoItem, setNuevoItem] = useState(false)
  const [editHeader, setEditHeader] = useState(false)
  const [colapsados, setColapsados] = useState<Set<string>>(new Set())
  const [descargando, setDescargando] = useState(false)

  async function descargarPdf() {
    setDescargando(true)
    try { await descargarPautasEnexPdf(pauta.id) } catch (e) { toast.error((e as Error).message) } finally { setDescargando(false) }
  }

  const grupos = useMemo(() => {
    const g: { bloque: string; items: EnexPautaItem[] }[] = []
    for (const it of items) {
      let x = g.find((y) => y.bloque === it.bloque)
      if (!x) { x = { bloque: it.bloque, items: [] }; g.push(x) }
      x.items.push(it)
    }
    return g
  }, [items])

  const inv = () => qc.invalidateQueries({ queryKey: ['enex-pauta-items', pauta.id] })
  const elim = useMutation({
    mutationFn: eliminarPautaItem,
    onSuccess: () => { toast.success('Ítem eliminado'); inv() },
    onError: (e) => toast.error((e as Error).message),
  })

  const bloquesExistentes = Array.from(new Set(items.map((i) => i.bloque)))

  return (
    <Card>
      <CardContent className="p-0">
        <div className="flex items-center justify-between border-b p-3">
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-sm font-bold">{pauta.nombre}</h2>
              {pauta.es_borrador && <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700">BORRADOR — revisar</span>}
            </div>
            <p className="text-[11px] text-gray-500">{items.length} ítems · {grupos.length} bloques · código {pauta.codigo}</p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={descargando} onClick={descargarPdf}>
              {descargando ? <Spinner className="h-3.5 w-3.5 mr-1" /> : <Download className="h-3.5 w-3.5 mr-1" />} PDF
            </Button>
            <Button variant="outline" size="sm" onClick={() => setEditHeader(true)}><Pencil className="h-3.5 w-3.5 mr-1" /> Datos</Button>
            <Button size="sm" onClick={() => setNuevoItem(true)}><Plus className="h-4 w-4 mr-1" /> Ítem</Button>
          </div>
        </div>

        <div className="divide-y">
          {grupos.map((g) => {
            const cerrado = colapsados.has(g.bloque)
            return (
              <div key={g.bloque}>
                <button onClick={() => setColapsados((p) => { const n = new Set(p); n.has(g.bloque) ? n.delete(g.bloque) : n.add(g.bloque); return n })}
                        className="flex w-full items-center gap-1.5 bg-gray-50 px-3 py-1.5 text-left text-xs font-semibold text-gray-700">
                  {cerrado ? <ChevronRight className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                  {g.bloque} <span className="font-normal text-gray-400">({g.items.length})</span>
                </button>
                {!cerrado && g.items.map((it) => (
                  <div key={it.id} className="flex items-start gap-2 px-3 py-1.5 hover:bg-gray-50/60">
                    <span className="w-9 shrink-0 font-mono text-[10px] text-gray-400">{it.codigo}</span>
                    <div className="flex-1">
                      <div className="text-sm text-gray-800">{it.descripcion}</div>
                      <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-[10px]">
                        <span className="rounded bg-gray-100 px-1.5 py-0.5 text-gray-600">{it.periodicidad}</span>
                        <span className="rounded bg-blue-50 px-1.5 py-0.5 text-blue-700">{TIPO_CAMPO_LABEL[it.tipo_campo]}</span>
                        {it.tipo_campo === 'medicion' && (it.tolerancia_min != null || it.tolerancia_max != null) && (
                          <span className="flex items-center gap-0.5 rounded bg-purple-50 px-1.5 py-0.5 text-purple-700">
                            <Ruler className="h-3 w-3" /> {it.tolerancia_min ?? '−∞'} a {it.tolerancia_max ?? '+∞'} {it.unidad ?? ''}
                          </span>
                        )}
                        {it.requiere_foto && <span className="flex items-center gap-0.5 rounded bg-green-50 px-1.5 py-0.5 text-green-700"><Camera className="h-3 w-3" /> foto</span>}
                        {it.critico && <span className="flex items-center gap-0.5 rounded bg-amber-100 px-1.5 py-0.5 font-semibold text-amber-800"><AlertTriangle className="h-3 w-3" /> crítico · antes/después</span>}
                      </div>
                    </div>
                    <button onClick={() => setEditItem(it)} className="p-1 text-gray-400 hover:text-blue-600"><Pencil className="h-3.5 w-3.5" /></button>
                    <button onClick={() => { if (confirm('¿Eliminar ítem?')) elim.mutate(it.id) }} className="p-1 text-gray-400 hover:text-red-600"><Trash2 className="h-3.5 w-3.5" /></button>
                  </div>
                ))}
              </div>
            )
          })}
          {items.length === 0 && <p className="p-6 text-center text-sm text-gray-400">Pauta sin ítems. Agrega con «Ítem».</p>}
        </div>
      </CardContent>

      {(editItem || nuevoItem) && (
        <ItemModal pautaId={pauta.id} item={editItem} bloques={bloquesExistentes}
          defaultBloque={grupos[grupos.length - 1]?.bloque ?? 'General'}
          defaultOrden={(grupos[grupos.length - 1]?.items.length ?? 0) + 1}
          defaultBloqueOrden={grupos.length || 1}
          onClose={() => { setEditItem(null); setNuevoItem(false) }}
          onDone={() => { setEditItem(null); setNuevoItem(false); inv() }} />
      )}
      {editHeader && (
        <PautaModal pauta={pauta} onClose={() => setEditHeader(false)}
          onDone={() => { setEditHeader(false); qc.invalidateQueries({ queryKey: ['enex-pautas'] }) }} />
      )}
    </Card>
  )
}

function ItemModal({ pautaId, item, bloques, defaultBloque, defaultOrden, defaultBloqueOrden, onClose, onDone }: {
  pautaId: string; item: EnexPautaItem | null; bloques: string[]
  defaultBloque: string; defaultOrden: number; defaultBloqueOrden: number
  onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [bloque, setBloque] = useState(item?.bloque ?? defaultBloque)
  const [codigo, setCodigo] = useState(item?.codigo ?? '')
  const [descripcion, setDescripcion] = useState(item?.descripcion ?? '')
  const [periodicidad, setPeriodicidad] = useState<Periodicidad>(item?.periodicidad ?? 'trimestral')
  const [tipoCampo, setTipoCampo] = useState<TipoCampo>(item?.tipo_campo ?? 'ok_nook')
  const [unidad, setUnidad] = useState(item?.unidad ?? '')
  const [tmin, setTmin] = useState(item?.tolerancia_min?.toString() ?? '')
  const [tmax, setTmax] = useState(item?.tolerancia_max?.toString() ?? '')
  const [foto, setFoto] = useState(item?.requiere_foto ?? false)
  const [critico, setCritico] = useState(item?.critico ?? false)
  const [busy, setBusy] = useState(false)

  async function guardar() {
    if (!descripcion.trim()) return
    setBusy(true)
    try {
      await guardarPautaItem({
        id: item?.id ?? null, pautaId, bloque: bloque.trim() || 'General',
        bloqueOrden: item?.bloque_orden ?? defaultBloqueOrden, orden: item?.orden ?? defaultOrden,
        codigo: codigo.trim() || null, descripcion: descripcion.trim(), periodicidad, tipoCampo,
        unidad: tipoCampo === 'medicion' ? (unidad.trim() || null) : null,
        toleranciaMin: tipoCampo === 'medicion' && tmin !== '' ? Number(tmin) : null,
        toleranciaMax: tipoCampo === 'medicion' && tmax !== '' ? Number(tmax) : null,
        requiereFoto: foto, critico,
      })
      toast.success(item ? 'Ítem actualizado' : 'Ítem agregado'); onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={item ? 'Editar ítem' : 'Nuevo ítem'}>
      <div className="space-y-3">
        <div className="grid grid-cols-[1fr_80px] gap-2">
          <div>
            <label className="text-xs font-medium">Bloque</label>
            <Input list="bloques-list" value={bloque} onChange={(e) => setBloque(e.target.value)} placeholder="ej 1. Surtidores" />
            <datalist id="bloques-list">{bloques.map((b) => <option key={b} value={b} />)}</datalist>
          </div>
          <div><label className="text-xs font-medium">Código</label><Input value={codigo} onChange={(e) => setCodigo(e.target.value)} placeholder="1.1" /></div>
        </div>
        <div><label className="text-xs font-medium">Descripción de la tarea</label><Input value={descripcion} onChange={(e) => setDescripcion(e.target.value)} /></div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium">Periodicidad</label>
            <select value={periodicidad} onChange={(e) => setPeriodicidad(e.target.value as Periodicidad)} className="w-full rounded border px-2 py-1.5 text-sm capitalize">
              {PERIODICIDADES.map((p) => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Tipo de campo</label>
            <select value={tipoCampo} onChange={(e) => setTipoCampo(e.target.value as TipoCampo)} className="w-full rounded border px-2 py-1.5 text-sm">
              {TIPOS_CAMPO.map((t) => <option key={t} value={t}>{TIPO_CAMPO_LABEL[t]}</option>)}
            </select>
          </div>
        </div>
        {tipoCampo === 'medicion' && (
          <div className="grid grid-cols-3 gap-2 rounded-lg bg-purple-50/50 p-2">
            <div><label className="text-[11px] font-medium">Unidad</label><Input value={unidad} onChange={(e) => setUnidad(e.target.value)} placeholder="cc, V, A…" /></div>
            <div><label className="text-[11px] font-medium">Tol. mín</label><Input type="number" value={tmin} onChange={(e) => setTmin(e.target.value)} placeholder="-50" /></div>
            <div><label className="text-[11px] font-medium">Tol. máx</label><Input type="number" value={tmax} onChange={(e) => setTmax(e.target.value)} placeholder="+50" /></div>
          </div>
        )}
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={foto} onChange={(e) => setFoto(e.target.checked)} /> Requiere foto
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={critico} onChange={(e) => setCritico(e.target.checked)} />
          Actividad crítica (foto del antes y del después en terreno)
        </label>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy || !descripcion.trim()} onClick={guardar}>{busy ? <Spinner className="h-4 w-4 mr-1" /> : null} Guardar</Button>
      </ModalFooter>
    </Modal>
  )
}

function PautaModal({ pauta, onClose, onDone }: { pauta?: EnexPauta; onClose: () => void; onDone: (id: string) => void }) {
  const toast = useToast()
  const [codigo, setCodigo] = useState(pauta?.codigo ?? '')
  const [nombre, setNombre] = useState(pauta?.nombre ?? '')
  const [tipoServicio, setTipoServicio] = useState<'mantencion' | 'calibracion'>(pauta?.tipo_servicio ?? 'mantencion')
  const [tipos, setTipos] = useState<string[]>(pauta?.aplica_tipos ?? [])
  const [borrador, setBorrador] = useState(pauta?.es_borrador ?? true)
  const [busy, setBusy] = useState(false)

  function toggleTipo(t: string) { setTipos((p) => p.includes(t) ? p.filter((x) => x !== t) : [...p, t]) }
  async function guardar() {
    if (!codigo.trim() || !nombre.trim()) return
    setBusy(true)
    try {
      const r = await guardarPauta({ id: pauta?.id ?? null, codigo: codigo.trim(), nombre: nombre.trim(), tipoServicio, aplicaTipos: tipos, esBorrador: borrador })
      toast.success('Pauta guardada'); onDone(r.pauta_id)
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={pauta ? 'Datos de la pauta' : 'Nueva pauta'}>
      <div className="space-y-3">
        <div className="grid grid-cols-[110px_1fr] gap-2">
          <div><label className="text-xs font-medium">Código</label><Input value={codigo} onChange={(e) => setCodigo(e.target.value)} placeholder="PAUTA-XXX" /></div>
          <div><label className="text-xs font-medium">Nombre</label><Input value={nombre} onChange={(e) => setNombre(e.target.value)} /></div>
        </div>
        <div>
          <label className="text-xs font-medium">Servicio</label>
          <select value={tipoServicio} onChange={(e) => setTipoServicio(e.target.value as 'mantencion' | 'calibracion')} className="w-full rounded border px-2 py-1.5 text-sm">
            <option value="mantencion">Mantención</option>
            <option value="calibracion">Calibración y certificación</option>
          </select>
        </div>
        <div>
          <label className="text-xs font-medium">Aplica a tipos de instalación</label>
          <div className="mt-1 flex flex-wrap gap-1.5">
            {Object.entries(TIPO_INSTALACION_LABEL).map(([k, v]) => (
              <button key={k} type="button" onClick={() => toggleTipo(k)}
                      className={`rounded-full border px-2.5 py-1 text-xs ${tipos.includes(k) ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>{v}</button>
            ))}
          </div>
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={borrador} onChange={(e) => setBorrador(e.target.checked)} /> Es borrador (pendiente de validar)
        </label>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy || !codigo.trim() || !nombre.trim()} onClick={guardar}>{busy ? <Spinner className="h-4 w-4 mr-1" /> : null} Guardar</Button>
      </ModalFooter>
    </Modal>
  )
}
