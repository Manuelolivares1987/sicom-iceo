'use client'

import { useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  Wrench, History, ShieldCheck, FileText, Clock, ClipboardList, ChevronDown, ChevronRight,
  Camera, CheckCircle2, XCircle, MinusCircle, Truck, ExternalLink,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { getBitacoraEquipo, getActivoBasico, getOtDetalleBitacora, type BitacoraEvento } from '@/lib/services/bitacora'
import { cn } from '@/lib/utils'

const TIPO_META: Record<string, { icon: any; label: string; color: string }> = {
  ot:                { icon: Wrench,        label: 'OT',              color: 'text-blue-600' },
  os_legacy:         { icon: History,       label: 'OS histórica',    color: 'text-gray-500' },
  auditoria:         { icon: ShieldCheck,   label: 'Auditoría',       color: 'text-emerald-600' },
  recepcion:         { icon: FileText,      label: 'Recepción',       color: 'text-purple-600' },
  diferido:          { icon: Clock,         label: 'Pendiente',       color: 'text-amber-600' },
  checklist_cliente: { icon: ClipboardList, label: 'Checklist cliente', color: 'text-indigo-600' },
}

const TIPOS = ['ot', 'os_legacy', 'auditoria', 'recepcion', 'diferido', 'checklist_cliente'] as const

export default function BitacoraEquipoPage() {
  useRequireAuth()
  const { activoId } = useParams<{ activoId: string }>()
  const { data: activo } = useQuery({
    queryKey: ['activo-basico', activoId],
    queryFn: async () => { const { data, error } = await getActivoBasico(activoId); if (error) throw error; return data },
  })
  const { data: eventos = [], isLoading } = useQuery({
    queryKey: ['bitacora', activoId],
    queryFn: async () => { const { data, error } = await getBitacoraEquipo(activoId); if (error) throw error; return data },
  })
  const [filtros, setFiltros] = useState<Set<string>>(new Set())

  const lista = useMemo(
    () => filtros.size ? eventos.filter((e) => filtros.has(e.tipo_registro)) : eventos,
    [eventos, filtros],
  )
  const conteo = useMemo(() => {
    const c: Record<string, number> = {}
    for (const e of eventos) c[e.tipo_registro] = (c[e.tipo_registro] ?? 0) + 1
    return c
  }, [eventos])

  const toggleFiltro = (t: string) =>
    setFiltros((s) => { const n = new Set(s); n.has(t) ? n.delete(t) : n.add(t); return n })

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Truck className="h-7 w-7 text-blue-600" />
        <div>
          <h1 className="text-2xl font-bold">Bitácora · {activo?.patente ?? activo?.codigo ?? ''}</h1>
          <p className="text-sm text-muted-foreground">
            {activo?.nombre} · Horómetro {activo?.horas_uso_actual ?? '—'} · {eventos.length} eventos
          </p>
        </div>
      </div>

      {/* Filtros por tipo */}
      <div className="flex flex-wrap gap-2">
        {TIPOS.filter((t) => conteo[t]).map((t) => {
          const m = TIPO_META[t]; const active = filtros.has(t)
          return (
            <button key={t} onClick={() => toggleFiltro(t)}
              className={cn('flex items-center gap-1 rounded-full border px-3 py-1 text-xs',
                active ? 'bg-blue-600 text-white border-blue-600' : 'hover:bg-muted')}>
              <m.icon className="h-3.5 w-3.5" /> {m.label} ({conteo[t]})
            </button>
          )
        })}
      </div>

      {isLoading && <Spinner className="h-6 w-6" />}

      <div className="relative border-l-2 border-muted ml-3 space-y-3">
        {lista.map((e) => <EventoFila key={`${e.tipo_registro}-${e.ref_id}`} e={e} />)}
        {!isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground py-8 pl-6">Sin eventos para este equipo.</p>
        )}
      </div>
    </div>
  )
}

function EventoFila({ e }: { e: BitacoraEvento }) {
  const m = TIPO_META[e.tipo_registro] ?? TIPO_META.ot
  const [open, setOpen] = useState(false)
  const expandible = e.tipo_registro === 'ot'
  const fecha = e.fecha ? new Date(e.fecha).toLocaleDateString('es-CL', { year: 'numeric', month: 'short', day: 'numeric' }) : '—'

  return (
    <div className="relative pl-6">
      <div className={cn('absolute -left-[9px] top-3 h-4 w-4 rounded-full bg-white border-2 flex items-center justify-center', m.color)}>
        <m.icon className={cn('h-2.5 w-2.5', m.color)} />
      </div>
      <Card>
        <CardContent className="p-3">
          <div className={cn('flex items-start justify-between gap-3', expandible && 'cursor-pointer')}
            onClick={() => expandible && setOpen((o) => !o)}>
            <div className="min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <Badge variant="default" className="text-[10px]">{m.label}</Badge>
                <span className="font-medium text-sm">{e.titulo}</span>
                {e.subtitulo && <span className="text-xs text-muted-foreground">· {e.subtitulo}</span>}
              </div>
              {e.detalle && <p className="text-xs text-muted-foreground mt-1 line-clamp-2">{e.detalle}</p>}
              <div className="text-xs text-muted-foreground mt-1 flex gap-3">
                <span>{fecha}</span>
                {e.responsable && <span>· {e.responsable}</span>}
                {e.costo != null && Number(e.costo) > 0 && <span>· ${Number(e.costo).toLocaleString('es-CL')}</span>}
              </div>
            </div>
            <div className="shrink-0 flex items-center gap-2">
              {e.tipo_registro === 'ot' && (
                <Link href={`/dashboard/ordenes-trabajo/${e.ref_id}`} onClick={(ev) => ev.stopPropagation()}
                  className="text-blue-600"><ExternalLink className="h-4 w-4" /></Link>
              )}
              {expandible && (open ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />)}
            </div>
          </div>
          {open && expandible && <OtDetalle otId={e.ref_id} />}
        </CardContent>
      </Card>
    </div>
  )
}

function OtDetalle({ otId }: { otId: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['bitacora-ot-detalle', otId],
    queryFn: () => getOtDetalleBitacora(otId),
  })
  if (isLoading) return <div className="mt-3 pt-3 border-t"><Spinner className="h-4 w-4" /></div>
  if (!data) return null

  const resIcon = (r: string) => r === 'ok' ? <CheckCircle2 className="h-3.5 w-3.5 text-green-600" />
    : r === 'no_ok' ? <XCircle className="h-3.5 w-3.5 text-red-600" />
    : <MinusCircle className="h-3.5 w-3.5 text-gray-400" />

  return (
    <div className="mt-3 pt-3 border-t space-y-3 text-sm">
      {data.checklist.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-muted-foreground mb-1">Tareas</div>
          <div className="space-y-0.5">
            {data.checklist.map((c: any, i: number) => (
              <div key={i} className="flex items-center gap-2 text-xs">
                {resIcon(c.resultado)} <span>{c.descripcion}</span>
                {c.observacion && <span className="text-muted-foreground">— {c.observacion}</span>}
                {c.foto_url && <a href={c.foto_url} target="_blank" rel="noreferrer" className="text-blue-600"><Camera className="h-3 w-3 inline" /></a>}
              </div>
            ))}
          </div>
        </div>
      )}
      {data.materiales.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-muted-foreground mb-1">Repuestos</div>
          {data.materiales.map((mt: any, i: number) => (
            <div key={i} className="text-xs">• {mt.producto?.nombre ?? mt.producto?.codigo ?? 'item'} × {mt.cantidad_entregada ?? 0} <span className="text-muted-foreground">({mt.estado})</span></div>
          ))}
        </div>
      )}
      {data.evidencias.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-muted-foreground mb-1">Evidencias ({data.evidencias.length})</div>
          <div className="flex flex-wrap gap-2">
            {data.evidencias.map((ev: any, i: number) => (
              ev.archivo_url ? <a key={i} href={ev.archivo_url} target="_blank" rel="noreferrer"
                className="text-xs text-blue-600 flex items-center gap-1 border rounded px-2 py-1">
                <Camera className="h-3 w-3" /> {ev.tipo}</a> : null
            ))}
          </div>
        </div>
      )}
      {data.ejecuciones.length > 0 && data.ejecuciones.map((j: any, i: number) => (
        <div key={i} className="text-xs text-muted-foreground">
          Ejecución: {j.tiempo_efectivo_segundos ? Math.round(j.tiempo_efectivo_segundos / 60) + ' min efectivos' : '—'}
          {j.avance_final != null && ` · avance ${j.avance_final}%`}
          {j.observacion_cierre && ` · ${j.observacion_cierre}`}
        </div>
      ))}
      {data.checklist.length === 0 && data.materiales.length === 0 && data.evidencias.length === 0 && (
        <p className="text-xs text-muted-foreground">Sin detalle registrado. <Link href={`/dashboard/ordenes-trabajo/${otId}`} className="text-blue-600">Abrir OT</Link></p>
      )}
    </div>
  )
}
