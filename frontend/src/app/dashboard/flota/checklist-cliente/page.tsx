'use client'

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ClipboardList, AlertTriangle, CheckCircle2, Clock, XCircle, Link2, Wrench, Camera,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import {
  getCumplimientoCliente, getChecklistClienteDetalle, generarOtDesdeChecklistCliente,
} from '@/lib/services/checklist-cliente'
import { cn } from '@/lib/utils'

const ESTADO_BADGE: Record<string, { v: any; t: string }> = {
  al_dia: { v: 'operativo', t: 'Al día' },
  atrasado: { v: 'alta', t: 'Atrasado' },
  sin_check: { v: 'fuera_servicio', t: 'Sin check' },
}

export default function ChecklistClientePanelPage() {
  useRequireAuth()
  const { canEdit } = usePermissions()
  const qc = useQueryClient()
  const { data: filas = [], isLoading } = useQuery({
    queryKey: ['checklist-cliente-cumplimiento'],
    queryFn: async () => { const { data, error } = await getCumplimientoCliente(); if (error) throw error; return data ?? [] },
    staleTime: 30_000,
  })
  const [sel, setSel] = useState<any | null>(null)
  const [soloNovedad, setSoloNovedad] = useState(false)

  const kpi = useMemo(() => {
    const total = filas.length
    const alDia = filas.filter((f: any) => f.estado_cumplimiento === 'al_dia').length
    const atras = filas.filter((f: any) => f.estado_cumplimiento === 'atrasado').length
    const sin = filas.filter((f: any) => f.estado_cumplimiento === 'sin_check').length
    const nov = filas.filter((f: any) => f.tiene_novedad).length
    return { total, alDia, atras, sin, nov, pct: total ? Math.round(100 * alDia / total) : 0 }
  }, [filas])

  const lista = soloNovedad ? filas.filter((f: any) => f.tiene_novedad) : filas

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ClipboardList className="h-6 w-6 text-blue-600" /> Checklist semanal del cliente
        </h1>
        <p className="text-sm text-muted-foreground">
          Cumplimiento del checklist de estado que ejecuta el cliente (vía QR) en cada equipo fuera de
          nuestras instalaciones: arrendado, leasing o bajo contrato.
        </p>
      </div>

      <div className="grid gap-3 grid-cols-2 md:grid-cols-5">
        <Kpi label="Equipos en terreno" value={kpi.total} icon={ClipboardList} />
        <Kpi label="Cumplimiento" value={`${kpi.pct}%`} icon={CheckCircle2} />
        <Kpi label="Atrasados" value={kpi.atras} icon={Clock} warn={kpi.atras > 0} />
        <Kpi label="Sin check" value={kpi.sin} icon={XCircle} warn={kpi.sin > 0} />
        <Kpi label="Con novedad" value={kpi.nov} icon={AlertTriangle} warn={kpi.nov > 0} />
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_400px]">
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center justify-between">
              <span>Equipos ({lista.length})</span>
              <label className="text-xs font-normal flex items-center gap-1">
                <input type="checkbox" checked={soloNovedad} onChange={(e) => setSoloNovedad(e.target.checked)} /> solo con novedad
              </label>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1">
            {isLoading && <Spinner className="h-5 w-5" />}
            {lista.map((f: any) => {
              const b = ESTADO_BADGE[f.estado_cumplimiento] ?? ESTADO_BADGE.sin_check
              return (
                <button key={f.activo_id} onClick={() => setSel(f)}
                  className={cn('w-full text-left rounded border p-2 text-sm flex items-center justify-between gap-2',
                    sel?.activo_id === f.activo_id ? 'border-blue-500 bg-blue-50' : 'hover:bg-muted')}>
                  <div className="min-w-0">
                    <div className="font-medium truncate">{f.patente ?? f.codigo} <span className="text-xs text-muted-foreground">· {f.cliente ?? '—'}</span></div>
                    <div className="text-xs text-muted-foreground">
                      {f.ultima_fecha ? `Último: ${f.ultima_fecha}` : 'Nunca'}{f.dias_desde_ultimo != null ? ` (${f.dias_desde_ultimo}d)` : ''}
                    </div>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    {f.tiene_novedad && <Badge variant="alta" className="text-[10px]">novedad</Badge>}
                    <Badge variant={b.v} className="text-[10px]">{b.t}</Badge>
                  </div>
                </button>
              )
            })}
          </CardContent>
        </Card>

        {sel
          ? <DetalleEquipo key={sel.activo_id} fila={sel} canEdit={canEdit('flota')}
              onOt={() => qc.invalidateQueries({ queryKey: ['checklist-cliente-cumplimiento'] })} />
          : <Card><CardContent className="py-16 text-center text-muted-foreground">
              <ClipboardList className="h-10 w-10 mx-auto mb-2 opacity-40" /> Selecciona un equipo.
            </CardContent></Card>}
      </div>
    </div>
  )
}

function DetalleEquipo({ fila, canEdit, onOt }: { fila: any; canEdit: boolean; onOt: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['checklist-cliente-detalle', fila.ultimo_id],
    queryFn: async () => { const { data, error } = await getChecklistClienteDetalle(fila.ultimo_id); if (error) throw error; return data },
    enabled: !!fila.ultimo_id,
  })
  const [generando, setGenerando] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const link = typeof window !== 'undefined' ? `${window.location.origin}/equipo/${fila.activo_id}/checklist-cliente` : ''

  const generarOt = async () => {
    if (!fila.ultimo_id) return
    setGenerando(true); setMsg(null)
    try {
      const { data, error } = await generarOtDesdeChecklistCliente(fila.ultimo_id)
      if (error) throw error
      setMsg(`OT creada (${(data as any)?.ot_id ? 'ok' : ''}). Revisa Órdenes de Trabajo.`)
      onOt()
    } catch (e) { setMsg(e instanceof Error ? e.message : 'Error') } finally { setGenerando(false) }
  }

  const h = data?.header
  return (
    <Card>
      <CardHeader><CardTitle className="text-base">{fila.patente ?? fila.codigo}</CardTitle></CardHeader>
      <CardContent className="space-y-4">
        {/* Link QR para el cliente */}
        <div className="rounded-lg border bg-muted/40 p-3 space-y-1">
          <div className="text-xs font-medium flex items-center gap-1"><Link2 className="h-3.5 w-3.5" /> Link para el cliente</div>
          <div className="flex gap-2">
            <input readOnly value={link} className="flex-1 rounded border px-2 py-1 text-xs bg-white" />
            <Button size="sm" variant="outline" onClick={() => navigator.clipboard?.writeText(link)}>Copiar</Button>
          </div>
          <a href={`https://api.qrserver.com/v1/create-qr-code/?size=140x140&data=${encodeURIComponent(link)}`}
            target="_blank" rel="noreferrer" className="text-xs text-blue-600 underline">Ver QR</a>
        </div>

        {!fila.ultimo_id && <p className="text-sm text-muted-foreground">Este equipo aún no tiene checklists del cliente.</p>}
        {isLoading && <Spinner className="h-5 w-5" />}

        {h && (
          <>
            <div className="text-sm space-y-0.5">
              <div><b>Fecha:</b> {h.fecha} · semana {h.semana_iso}/{h.anio}</div>
              <div><b>Operador:</b> {h.operador_nombre} ({h.operador_rut}) · {h.operador_empresa ?? '—'}</div>
              <div><b>Horómetro:</b> {h.horometro ?? '—'} · <b>Km:</b> {h.kilometraje ?? '—'}</div>
              {h.observaciones && <div><b>Obs:</b> {h.observaciones}</div>}
              <div className="flex gap-3 pt-1">
                <span className="text-green-600">{h.items_ok} OK</span>
                <span className="text-red-600">{h.items_no_ok} novedad</span>
              </div>
            </div>

            <div className="space-y-1">
              {(data?.items ?? []).map((i: any) => (
                <div key={i.id} className={cn('text-sm rounded border p-2', i.resultado === 'no_ok' && 'border-red-200 bg-red-50')}>
                  <div className="flex items-center justify-between">
                    <span>{i.descripcion}</span>
                    <Badge variant={i.resultado === 'ok' ? 'operativo' : i.resultado === 'no_ok' ? 'alta' : 'default'} className="text-[10px]">
                      {i.resultado === 'ok' ? 'OK' : i.resultado === 'no_ok' ? 'NOVEDAD' : 'N/A'}
                    </Badge>
                  </div>
                  {i.observacion && <div className="text-xs text-muted-foreground mt-0.5">{i.observacion}</div>}
                  {i.foto_url && <a href={i.foto_url} target="_blank" rel="noreferrer" className="text-xs text-blue-600 flex items-center gap-1 mt-1"><Camera className="h-3 w-3" /> ver foto</a>}
                </div>
              ))}
            </div>

            {h.tiene_novedad && (
              <div className="border-t pt-3">
                {h.ot_generada_id ? (
                  <Badge variant="en_ejecucion">OT ya generada para estas novedades</Badge>
                ) : canEdit ? (
                  <Button size="sm" disabled={generando} onClick={generarOt}>
                    <Wrench className="h-4 w-4 mr-1" /> Generar OT correctiva
                  </Button>
                ) : null}
                {msg && <p className="text-xs text-emerald-700 mt-2">{msg}</p>}
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}

function Kpi({ label, value, icon: Icon, warn }: { label: string; value: React.ReactNode; icon: any; warn?: boolean }) {
  return (
    <Card><CardContent className="p-3">
      <div className="flex items-center gap-2 text-xs text-muted-foreground"><Icon className="h-4 w-4" /> {label}</div>
      <div className={cn('text-xl font-bold mt-1', warn && 'text-red-600')}>{value}</div>
    </CardContent></Card>
  )
}
