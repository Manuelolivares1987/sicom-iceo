'use client'

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PackageSearch, Image as ImageIcon, Check, X, Loader2 } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { getSolicitudesBodega, atenderSolicitudBodega, type BodegaSolicitud } from '@/lib/services/bodega-solicitudes'
import { cn } from '@/lib/utils'

const FILTROS = [['pendiente', 'Pendientes'], ['atendida', 'Atendidas'], ['rechazada', 'Rechazadas'], ['', 'Todas']] as const

export default function SolicitudesBodegaPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('pendiente')
  const { data: sols = [], isLoading } = useQuery({ queryKey: ['bodega-solicitudes', filtro], queryFn: () => getSolicitudesBodega(filtro || undefined), staleTime: 15_000 })
  const [busy, setBusy] = useState<string | null>(null)

  const pendientes = useMemo(() => sols.filter((s) => s.estado === 'pendiente').length, [sols])

  const accion = async (s: BodegaSolicitud, estado: 'atendida' | 'rechazada') => {
    setBusy(s.id)
    try {
      await atenderSolicitudBodega({ id: s.id, estado })
      toast.success(estado === 'atendida' ? 'Solicitud atendida' : 'Solicitud rechazada')
      qc.invalidateQueries({ queryKey: ['bodega-solicitudes'] })
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(null) }
  }

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2"><PackageSearch className="h-6 w-6 text-indigo-600" /> Solicitudes de material {filtro === 'pendiente' && pendientes > 0 && <Badge variant="critica">{pendientes}</Badge>}</h1>
        <p className="text-sm text-muted-foreground">Materiales que no estaban en bodega, solicitados desde las No Conformidades (con foto y observación del equipo).</p>
      </div>

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
