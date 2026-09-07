'use client'

// Plan de acción Gemba — la bandeja de GESTIÓN de los hallazgos de terreno.
//
// Manuel: «las NC que levantan en terreno, ¿dónde las pueden ver? La idea es
// hacer gestión». Los hallazgos ya vivían en gemba_hallazgos y por diseño
// siguen editables después de cerrar el recorrido (MIG288: el plan de acción
// SIGUE VIVO), pero solo se podían trabajar entrando recorrido por recorrido.
// Acá están todos juntos: filtrar, asignar responsable y plazo, avanzar el
// estado y cerrar — sin salir de la página.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, AlertTriangle, Pencil, CheckCircle2, RotateCcw, PlayCircle,
  Footprints, Camera,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useToast } from '@/hooks/use-toast'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useGembaHallazgos, useUpdateGembaHallazgo } from '@/hooks/use-gemba'
import type { GembaHallazgo } from '@/lib/services/gemba'

type Filtro = 'pendientes' | 'vencidos' | 'sin_plazo' | 'cerrados' | 'todos'

const hoyIso = () => new Date().toISOString().slice(0, 10)

const estaVencido = (h: GembaHallazgo) =>
  h.estado !== 'cerrada' && !!h.fecha_compromiso && h.fecha_compromiso < hoyIso()

function fechaCorta(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y.slice(2)}`
}

function EstadoBadge({ h }: { h: GembaHallazgo }) {
  if (h.estado === 'cerrada') {
    return <span className="shrink-0 rounded bg-green-100 px-1.5 py-0.5 text-[10px] font-semibold text-green-700">Cerrada</span>
  }
  if (estaVencido(h)) {
    return <span className="shrink-0 rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-semibold text-red-700">Vencida</span>
  }
  if (h.estado === 'en_proceso') {
    return <span className="shrink-0 rounded bg-blue-100 px-1.5 py-0.5 text-[10px] font-semibold text-blue-700">En proceso</span>
  }
  return <span className="shrink-0 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700">Abierta</span>
}

function HallazgoCard({ h }: { h: GembaHallazgo }) {
  const toast = useToast()
  const upd = useUpdateGembaHallazgo()
  const [editando, setEditando] = useState(false)
  const [accion, setAccion] = useState(h.accion_correctiva ?? '')
  const [resp, setResp] = useState(h.responsable_texto ?? h.responsable?.nombre_completo ?? '')
  const [plazo, setPlazo] = useState(h.fecha_compromiso ?? '')

  const vencido = estaVencido(h)
  const cerrada = h.estado === 'cerrada'

  const guardar = async () => {
    try {
      await upd.mutateAsync({
        id: h.id,
        accion_correctiva: accion.trim() || undefined,
        responsable_texto: resp.trim() || undefined,
        fecha_compromiso: plazo || undefined,
      })
      toast.success('Hallazgo actualizado')
      setEditando(false)
    } catch (e) {
      toast.error(`No se pudo guardar: ${(e as Error).message ?? ''}`)
    }
  }

  const cambiarEstado = async (estado: 'abierta' | 'en_proceso' | 'cerrada') => {
    try {
      await upd.mutateAsync({
        id: h.id, estado,
        fecha_cierre: estado === 'cerrada' ? hoyIso() : null,
      })
      toast.success(estado === 'cerrada' ? 'Acción cerrada'
        : estado === 'en_proceso' ? 'Marcada en proceso' : 'Acción reabierta')
    } catch (e) {
      toast.error(`No se pudo actualizar: ${(e as Error).message ?? ''}`)
    }
  }

  return (
    <div className={cn('rounded-lg border p-3',
      cerrada ? 'border-gray-200 bg-gray-50/60'
      : vencido ? 'border-red-200 bg-red-50/50' : 'border-gray-200 bg-white')}>
      <div className="flex items-start gap-2.5">
        {h.respuesta?.foto_url && (
          <a href={h.respuesta.foto_url} target="_blank" rel="noreferrer" className="shrink-0">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={h.respuesta.foto_url} alt="" className="h-14 w-14 rounded-lg border object-cover" />
          </a>
        )}
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <p className={cn('min-w-0 flex-1 text-sm font-medium',
              cerrada ? 'text-gray-500' : 'text-gray-800')}>{h.descripcion}</p>
            <EstadoBadge h={h} />
          </div>
          {h.respuesta?.item && (
            <p className="mt-0.5 truncate text-[11px] text-gray-500">
              <Camera className="mr-0.5 inline h-3 w-3 text-gray-400" />
              {h.respuesta.seccion} · {h.respuesta.item}
            </p>
          )}
          {h.accion_correctiva && !editando && (
            <p className="mt-1 text-xs text-gray-600">
              <span className="text-gray-400">Acción:</span> {h.accion_correctiva}
            </p>
          )}
          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11px] text-gray-500">
            <span>{h.responsable_texto || h.responsable?.nombre_completo || 'Sin responsable'}</span>
            {h.fecha_compromiso ? (
              <span className={vencido ? 'font-semibold text-red-700' : ''}>
                compromiso {fechaCorta(h.fecha_compromiso)}{vencido ? ' · VENCIDO' : ''}
              </span>
            ) : !cerrada && (
              <span className="font-medium text-amber-700">sin plazo</span>
            )}
            {cerrada && h.fecha_cierre && <span className="text-green-700">cerrada el {fechaCorta(h.fecha_cierre)}</span>}
            {h.recorrido?.fecha && (
              <Link href={`/dashboard/gemba/${h.recorrido_id}`}
                    className="inline-flex items-center gap-0.5 text-blue-600 hover:underline">
                <Footprints className="h-3 w-3" />
                recorrido {fechaCorta(h.recorrido.fecha)}
                {h.recorrido.sector ? ` · ${h.recorrido.sector}` : ''}
              </Link>
            )}
          </div>
        </div>
      </div>

      {editando && (
        <div className="mt-2.5 space-y-2 rounded-lg border border-blue-200 bg-blue-50/50 p-2.5">
          <div>
            <label className="text-[11px] font-medium text-gray-600">Acción correctiva</label>
            <textarea value={accion} onChange={(e) => setAccion(e.target.value)} rows={2}
                      placeholder="Qué se va a hacer para que no se repita…"
                      className="mt-0.5 w-full rounded-lg border border-gray-300 px-2.5 py-1.5 text-sm" />
          </div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div>
              <label className="text-[11px] font-medium text-gray-600">Responsable</label>
              <input value={resp} onChange={(e) => setResp(e.target.value)}
                     placeholder="Quién se hace cargo"
                     className="mt-0.5 w-full rounded-lg border border-gray-300 px-2.5 py-1.5 text-sm" />
            </div>
            <div>
              <label className="text-[11px] font-medium text-gray-600">Fecha compromiso</label>
              <input type="date" value={plazo} onChange={(e) => setPlazo(e.target.value)}
                     className="mt-0.5 w-full rounded-lg border border-gray-300 px-2.5 py-1.5 text-sm" />
            </div>
          </div>
          <div className="flex gap-2">
            <Button variant="primary" size="sm" onClick={guardar} loading={upd.isPending}>Guardar</Button>
            <Button variant="ghost" size="sm" onClick={() => setEditando(false)}>Cancelar</Button>
          </div>
        </div>
      )}

      {!editando && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {!cerrada && (
            <>
              <button onClick={() => setEditando(true)}
                      className="inline-flex items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[11px] font-medium text-gray-700 hover:bg-gray-50">
                <Pencil className="h-3 w-3" /> Gestionar
              </button>
              {h.estado === 'abierta' && (
                <button onClick={() => cambiarEstado('en_proceso')}
                        className="inline-flex items-center gap-1 rounded-lg border border-blue-300 bg-blue-50 px-2 py-1 text-[11px] font-medium text-blue-700 hover:bg-blue-100">
                  <PlayCircle className="h-3 w-3" /> En proceso
                </button>
              )}
              <button onClick={() => cambiarEstado('cerrada')}
                      className="inline-flex items-center gap-1 rounded-lg border border-green-300 bg-green-50 px-2 py-1 text-[11px] font-medium text-green-700 hover:bg-green-100">
                <CheckCircle2 className="h-3 w-3" /> Cerrar acción
              </button>
            </>
          )}
          {cerrada && (
            <button onClick={() => cambiarEstado('abierta')}
                    className="inline-flex items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[11px] font-medium text-gray-600 hover:bg-gray-50">
              <RotateCcw className="h-3 w-3" /> Reabrir
            </button>
          )}
        </div>
      )}
    </div>
  )
}

export default function GembaHallazgosPage() {
  useRequireAuth()
  const { data: hallazgos, isLoading } = useGembaHallazgos()
  const [filtro, setFiltro] = useState<Filtro>('pendientes')

  const todos = useMemo(() => hallazgos ?? [], [hallazgos])
  const n = {
    pendientes: todos.filter((h) => h.estado !== 'cerrada').length,
    vencidos: todos.filter(estaVencido).length,
    sin_plazo: todos.filter((h) => h.estado !== 'cerrada' && !h.fecha_compromiso).length,
    cerrados: todos.filter((h) => h.estado === 'cerrada').length,
    todos: todos.length,
  }
  const visibles = todos.filter((h) => {
    if (filtro === 'pendientes') return h.estado !== 'cerrada'
    if (filtro === 'vencidos') return estaVencido(h)
    if (filtro === 'sin_plazo') return h.estado !== 'cerrada' && !h.fecha_compromiso
    if (filtro === 'cerrados') return h.estado === 'cerrada'
    return true
  })

  const CHIPS: { key: Filtro; label: string; alerta?: boolean }[] = [
    { key: 'pendientes', label: `Pendientes (${n.pendientes})` },
    { key: 'vencidos', label: `Vencidas (${n.vencidos})`, alerta: n.vencidos > 0 },
    { key: 'sin_plazo', label: `Sin plazo (${n.sin_plazo})`, alerta: n.sin_plazo > 0 },
    { key: 'cerrados', label: `Cerradas (${n.cerrados})` },
    { key: 'todos', label: `Todas (${n.todos})` },
  ]

  return (
    <div className="space-y-4 pb-6">
      <div>
        <Link href="/dashboard/gemba"
              className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
          <ArrowLeft className="h-4 w-4" /> Volver a recorridos
        </Link>
        <h1 className="mt-2 flex items-center gap-2 text-xl font-bold text-gray-900 sm:text-2xl">
          <AlertTriangle className="h-6 w-6 text-amber-500" />
          Plan de acción — hallazgos de terreno
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Todo lo levantado en los recorridos, en un solo lugar: asigna responsable y plazo,
          avanza el estado y cierra la acción cuando esté resuelta.
        </p>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {CHIPS.map((c) => (
          <button key={c.key} onClick={() => setFiltro(c.key)}
                  className={cn('rounded-full border px-3 py-1.5 text-xs font-medium',
                    filtro === c.key
                      ? 'border-gray-900 bg-gray-900 text-white'
                      : c.alerta
                        ? 'border-red-300 bg-red-50 text-red-700 hover:bg-red-100'
                        : 'border-gray-300 bg-white text-gray-600 hover:bg-gray-50')}>
            {c.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="flex h-40 items-center justify-center"><Spinner className="h-8 w-8" /></div>
      ) : visibles.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-gray-400">
            {filtro === 'pendientes'
              ? 'Sin hallazgos pendientes — plan de acción al día.'
              : 'Nada que mostrar con este filtro.'}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {visibles.map((h) => <HallazgoCard key={h.id} h={h} />)}
        </div>
      )}
    </div>
  )
}
