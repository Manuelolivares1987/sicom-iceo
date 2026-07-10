'use client'

// Costos iniciales FIFO (MIG222): las capas semilla se crearon a $1 para
// destrabar los despachos; aquí administración corrige el costo real de
// cada capa (solo capas sin consumos — el costeo histórico no se toca).

import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { DollarSign, Pencil, Search, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'

type CapaAdmin = {
  id: string
  producto_codigo: string | null
  producto_nombre: string
  categoria: string | null
  bodega_nombre: string
  fecha_recepcion: string
  folio_recepcion: string | null
  cantidad_inicial: number
  cantidad_disponible: number
  unidad: string | null
  costo_unitario: number
  costo_total_disponible: number
  estado: string
  es_semilla: boolean
  editable: boolean
}

async function getCapas(): Promise<CapaAdmin[]> {
  const { data, error } = await supabase.from('v_capas_fifo_admin')
    .select('*').order('producto_nombre').limit(2000)
  if (error) throw error
  return (data ?? []) as CapaAdmin[]
}

async function actualizarCosto(capaId: string, costo: number) {
  const { data, error } = await supabase.rpc('rpc_actualizar_costo_capa', {
    p_capa_id: capaId, p_costo_unitario: costo,
  })
  if (error) throw error
  return data as { success: boolean }
}

const CLP = (n: number) => `$${Math.round(n).toLocaleString('es-CL')}`

export default function CostosFifoPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const { data: capas, isLoading } = useQuery({ queryKey: ['capas-fifo-admin'], queryFn: getCapas })

  const [filtro, setFiltro] = useState<'semilla' | 'todas'>('semilla')
  const [q, setQ] = useState('')
  const [editando, setEditando] = useState<CapaAdmin | null>(null)
  const [nuevoCosto, setNuevoCosto] = useState('')

  const lista = useMemo(() => {
    let l = capas ?? []
    if (filtro === 'semilla') l = l.filter((c) => c.es_semilla && c.costo_unitario <= 1)
    if (q.trim()) {
      const s = q.trim().toLowerCase()
      l = l.filter((c) => c.producto_nombre.toLowerCase().includes(s)
        || (c.producto_codigo ?? '').toLowerCase().includes(s)
        || c.bodega_nombre.toLowerCase().includes(s))
    }
    return l
  }, [capas, filtro, q])

  const pendientes = (capas ?? []).filter((c) => c.es_semilla && c.costo_unitario <= 1).length

  const guardar = useMutation({
    mutationFn: (p: { id: string; costo: number }) => actualizarCosto(p.id, p.costo),
    onSuccess: () => {
      toast.success('Costo actualizado')
      qc.invalidateQueries({ queryKey: ['capas-fifo-admin'] })
      setEditando(null)
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="space-y-4 pb-16">
      <div className="flex items-center gap-2">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-600 text-white">
          <DollarSign className="h-5 w-5" />
        </div>
        <div>
          <h1 className="text-lg font-bold text-gray-900">Costos iniciales FIFO</h1>
          <p className="text-xs text-gray-500">
            Las capas semilla partieron en $1 para destrabar los despachos — corrige aquí el costo real de cada repuesto.
          </p>
        </div>
      </div>

      {pendientes > 0 && (
        <div className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          <b>{pendientes}</b> capa{pendientes !== 1 ? 's' : ''} semilla siguen valorizadas en $1 — los consumos de esos
          repuestos costearán $1 hasta que corrijas el costo.
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {([['semilla', `Semilla en $1 (${pendientes})`], ['todas', 'Todas las capas']] as const).map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)}
                  className={`rounded-full border px-3 py-1 text-xs ${filtro === k ? 'border-emerald-600 bg-emerald-600 text-white' : 'hover:bg-gray-50'}`}>
            {l}
          </button>
        ))}
        <div className="relative ml-auto w-72">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar producto, código o bodega…" className="pl-8" />
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : lista.length === 0 ? (
        <Card><CardContent className="p-8 text-center text-sm text-gray-400">
          {filtro === 'semilla' ? '🎉 No quedan capas semilla en $1.' : 'Sin capas.'}
        </CardContent></Card>
      ) : (
        <Card>
          <CardContent className="overflow-x-auto p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Producto</TableHead>
                  <TableHead>Bodega</TableHead>
                  <TableHead className="text-right">Disponible</TableHead>
                  <TableHead className="text-right">Costo unit.</TableHead>
                  <TableHead className="text-right">Valor</TableHead>
                  <TableHead>Origen</TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {lista.map((c) => (
                  <TableRow key={c.id} className={c.es_semilla && c.costo_unitario <= 1 ? 'bg-amber-50/40' : ''}>
                    <TableCell>
                      <span className="font-mono text-[10px] text-gray-400">{c.producto_codigo}</span>{' '}
                      <span className="text-sm">{c.producto_nombre}</span>
                    </TableCell>
                    <TableCell className="text-xs text-gray-500">{c.bodega_nombre}</TableCell>
                    <TableCell className="text-right text-sm">{c.cantidad_disponible} {c.unidad ?? ''}</TableCell>
                    <TableCell className={`text-right text-sm font-semibold ${c.costo_unitario <= 1 ? 'text-amber-700' : ''}`}>
                      {CLP(c.costo_unitario)}
                    </TableCell>
                    <TableCell className="text-right text-sm">{CLP(c.costo_total_disponible)}</TableCell>
                    <TableCell>
                      <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${
                        c.es_semilla ? 'bg-amber-100 text-amber-800' : 'bg-gray-100 text-gray-600'}`}>
                        {c.es_semilla ? 'semilla' : (c.folio_recepcion ?? 'recepción')}
                      </span>
                    </TableCell>
                    <TableCell className="text-right">
                      {c.editable ? (
                        <Button variant="outline" size="sm"
                                onClick={() => { setEditando(c); setNuevoCosto(c.costo_unitario > 1 ? String(c.costo_unitario) : '') }}>
                          <Pencil className="h-3.5 w-3.5 mr-1" /> Costo
                        </Button>
                      ) : (
                        <span className="text-[10px] text-gray-400" title="La capa ya tiene consumos: el costeo histórico no se toca">
                          con consumos
                        </span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Modal editar costo */}
      {editando && (
        <Modal open onClose={() => setEditando(null)} title="Corregir costo de la capa">
          <div className="space-y-3">
            <div className="rounded-lg border bg-gray-50 p-2.5 text-sm">
              <b>{editando.producto_nombre}</b>
              <div className="text-xs text-gray-500">
                {editando.bodega_nombre} · {editando.cantidad_disponible} {editando.unidad ?? 'un'} disponibles
                · costo actual {CLP(editando.costo_unitario)}
              </div>
            </div>
            <div>
              <label className="text-xs font-medium">Costo unitario real (CLP, neto)</label>
              <Input type="number" min="0" autoFocus value={nuevoCosto}
                     onChange={(e) => setNuevoCosto(e.target.value)}
                     placeholder="ej: 12500" />
              {Number(nuevoCosto) > 0 && (
                <p className="mt-1 text-xs text-gray-500">
                  Valor de la capa: {CLP(Number(nuevoCosto) * editando.cantidad_disponible)}
                </p>
              )}
            </div>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setEditando(null)}>Cancelar</Button>
            <Button disabled={!(Number(nuevoCosto) >= 0) || nuevoCosto === '' || guardar.isPending}
                    onClick={() => guardar.mutate({ id: editando.id, costo: Number(nuevoCosto) })}>
              {guardar.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <DollarSign className="h-4 w-4 mr-1" />}
              Guardar costo
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
