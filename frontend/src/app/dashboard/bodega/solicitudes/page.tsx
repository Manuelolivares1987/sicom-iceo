'use client'

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PackageSearch, Image as ImageIcon, Check, X, Loader2, Truck, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { getSolicitudesBodega, atenderSolicitudBodega, type BodegaSolicitud } from '@/lib/services/bodega-solicitudes'
import { useMaterialesPendientesDespacho, useDespacharMaterialOT } from '@/hooks/use-ot-materiales'
import { cn } from '@/lib/utils'

export default function SolicitudesBodegaPage() {
  useRequireAuth()
  const [tab, setTab] = useState<'ot' | 'nc'>('ot')
  const { data: pendientesOT = [] } = useMaterialesPendientesDespacho()
  const { data: solsNc = [] } = useQuery({ queryKey: ['bodega-solicitudes', 'pendiente'], queryFn: () => getSolicitudesBodega('pendiente'), staleTime: 15_000 })

  const nOt = (pendientesOT as any[]).length
  const nNc = (solsNc as BodegaSolicitud[]).filter((s) => s.estado === 'pendiente').length

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2"><PackageSearch className="h-6 w-6 text-indigo-600" /> Bodega — pedidos de material</h1>
        <p className="text-sm text-muted-foreground">Todo lo que necesita el taller en un solo lugar: lo pedido en las OT (con o sin stock) y las solicitudes de las No Conformidades.</p>
      </div>

      <div className="flex gap-2">
        <button onClick={() => setTab('ot')} className={cn('rounded-full border px-4 py-1.5 text-sm flex items-center gap-1.5', tab === 'ot' ? 'bg-indigo-600 text-white border-indigo-600' : 'hover:bg-muted')}>
          <Truck className="h-4 w-4" /> Materiales de OT {nOt > 0 && <Badge variant="asignada" className="text-[10px]">{nOt}</Badge>}
        </button>
        <button onClick={() => setTab('nc')} className={cn('rounded-full border px-4 py-1.5 text-sm flex items-center gap-1.5', tab === 'nc' ? 'bg-indigo-600 text-white border-indigo-600' : 'hover:bg-muted')}>
          <PackageSearch className="h-4 w-4" /> Solicitudes NC {nNc > 0 && <Badge variant="critica" className="text-[10px]">{nNc}</Badge>}
        </button>
      </div>

      {tab === 'ot' ? <MaterialesOTTab items={pendientesOT as any[]} /> : <SolicitudesNCTab />}
    </div>
  )
}

function MaterialesOTTab({ items }: { items: any[] }) {
  const toast = useToast()
  const despachar = useDespacharMaterialOT()
  const [busy, setBusy] = useState<string | null>(null)
  const [soloFalta, setSoloFalta] = useState(false)

  const lista = soloFalta ? items.filter((m) => m.estado === 'faltante') : items
  const faltan = items.filter((m) => m.estado === 'faltante').length

  const onDespachar = (m: any) => {
    setBusy(m.material_id)
    despachar.mutate({ materialId: m.material_id, otId: m.ot_id }, {
      onSuccess: () => toast.success('Material despachado'),
      onError: (e: any) => toast.error(e?.message ?? 'Error al despachar'),
      onSettled: () => setBusy(null),
    })
  }

  if (items.length === 0) return <Card><CardContent className="p-8 text-center text-muted-foreground">Sin materiales pedidos por OT pendientes.</CardContent></Card>

  return (
    <div className="space-y-3">
      <label className="flex items-center gap-2 text-xs text-muted-foreground">
        <input type="checkbox" checked={soloFalta} onChange={(e) => setSoloFalta(e.target.checked)} />
        Mostrar solo lo que <b className="text-red-600">falta</b> ({faltan})
      </label>
      <Card>
        <CardContent className="p-0 overflow-x-auto">
          <table className="w-full text-sm">
            <thead><tr className="text-xs text-muted-foreground border-b">
              <th className="text-left p-2">Material</th><th className="text-left p-2">OT / Equipo</th>
              <th className="p-2">Pide</th><th className="p-2">Stock</th><th className="p-2">Estado</th><th className="p-2"></th>
            </tr></thead>
            <tbody>
              {lista.map((m) => {
                const hay = m.estado === 'suficiente'
                return (
                  <tr key={m.material_id} className={cn('border-b', !hay && 'bg-red-50/40')}>
                    <td className="p-2"><span className="font-mono text-xs text-muted-foreground">{m.producto_codigo}</span> {m.producto_nombre}</td>
                    <td className="p-2 text-xs">{m.ot_folio} · <b>{m.activo_patente ?? m.activo_codigo ?? '—'}</b></td>
                    <td className="p-2 text-center">{m.cantidad_plan}</td>
                    <td className="p-2 text-center text-xs">{m.stock_actual ?? 0}</td>
                    <td className="p-2 text-center">
                      <Badge variant={hay ? 'operativo' : 'critica'} className="text-[10px]">{hay ? 'Hay stock' : 'Falta'}</Badge>
                    </td>
                    <td className="p-2 text-right">
                      {hay ? (
                        <Button size="sm" disabled={busy === m.material_id} onClick={() => onDespachar(m)}>
                          {busy === m.material_id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Truck className="h-3.5 w-3.5 mr-1" />} Despachar
                        </Button>
                      ) : (
                        <span className="text-[11px] text-amber-600 flex items-center justify-end gap-1"><AlertTriangle className="h-3.5 w-3.5" /> comprar / reponer</span>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}

function SolicitudesNCTab() {
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('pendiente')
  const { data: sols = [], isLoading } = useQuery({ queryKey: ['bodega-solicitudes', filtro], queryFn: () => getSolicitudesBodega(filtro || undefined), staleTime: 15_000 })
  const [busy, setBusy] = useState<string | null>(null)
  const FILTROS = [['pendiente', 'Pendientes'], ['atendida', 'Atendidas'], ['rechazada', 'Rechazadas'], ['', 'Todas']] as const

  const accion = async (s: BodegaSolicitud, estado: 'atendida' | 'rechazada') => {
    setBusy(s.id)
    try {
      await atenderSolicitudBodega({ id: s.id, estado })
      toast.success(estado === 'atendida' ? 'Solicitud atendida' : 'Solicitud rechazada')
      qc.invalidateQueries({ queryKey: ['bodega-solicitudes'] })
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(null) }
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-muted-foreground">Materiales que no estaban en bodega, solicitados desde las No Conformidades (con foto y observación del equipo).</p>
      <div className="flex gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)} className={cn('rounded-full border px-3 py-1 text-xs', filtro === k ? 'bg-indigo-600 text-white border-indigo-600' : 'hover:bg-muted')}>{l}</button>
        ))}
      </div>
      {isLoading && <div className="p-6"><Spinner className="h-5 w-5" /></div>}
      {!isLoading && sols.length === 0 && <Card><CardContent className="p-8 text-center text-muted-foreground">Sin solicitudes {filtro && `(${filtro})`}.</CardContent></Card>}
      <div className="grid gap-3 md:grid-cols-2">
        {sols.map((s) => (
          <Card key={s.id} className={cn(s.estado === 'pendiente' && 'border-amber-300')}>
            <CardContent className="p-3 flex gap-3">
              {s.foto_url ? (
                <a href={s.foto_url} target="_blank" rel="noreferrer" className="shrink-0">
                  <img src={s.foto_url} alt="foto NC" className="h-20 w-20 rounded object-cover border" />
                </a>
              ) : (
                <div className="h-20 w-20 rounded border bg-muted flex items-center justify-center text-muted-foreground shrink-0"><ImageIcon className="h-6 w-6" /></div>
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{s.descripcion}</span>
                  <span className="text-xs text-muted-foreground">x{s.cantidad}{s.unidad ? ` ${s.unidad}` : ''}</span>
                </div>
                <div className="text-xs text-muted-foreground mt-0.5">
                  {s.patente ?? s.activo_codigo ?? '—'} · {s.solicitado_por_nombre ?? '—'} · {new Date(s.created_at).toLocaleDateString('es-CL')}
                </div>
                {s.observacion && <p className="text-xs mt-1 text-gray-600 line-clamp-2">{s.observacion}</p>}
                <div className="mt-2 flex items-center gap-2">
                  <Badge variant={s.estado === 'pendiente' ? 'asignada' : s.estado === 'atendida' ? 'operativo' : 'default'} className="text-[10px]">{s.estado}</Badge>
                  {s.estado === 'pendiente' && (
                    <>
                      <Button size="sm" disabled={busy === s.id} onClick={() => accion(s, 'atendida')}>
                        {busy === s.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5 mr-1" />} Atender
                      </Button>
                      <Button size="sm" variant="outline" disabled={busy === s.id} onClick={() => accion(s, 'rechazada')}><X className="h-3.5 w-3.5 mr-1" /> Rechazar</Button>
                    </>
                  )}
                  {s.nota_bodega && <span className="text-[11px] text-muted-foreground">· {s.nota_bodega}</span>}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
