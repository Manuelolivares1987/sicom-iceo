'use client'

// ============================================================================
// Guardar equipos en el historial. [MIG406]
// ----------------------------------------------------------------------------
// Manuel: «la idea es que se pueda seleccionar la patente y colocar como
// historia, así empiezo limpio».
//
// Se elige la patente y se va TODO lo suyo de una vez: no conformidades,
// órdenes de trabajo, vales de bodega, repuestos pedidos y checklists. Ir
// entidad por entidad obliga a pasar por cinco menús para dejar un camión
// limpio, y a la quinta alguien se olvida.
//
// Nada se borra, y el lote se deshace entero.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Archive, AlertTriangle, Undo2, Loader2, Search } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getEquiposParaArchivar, archivarEquipos, getLotesArchivo, deshacerLote,
} from '@/lib/services/archivo'

function hoyISO() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export default function HistorialEquiposPage() {
  const { loading: authLoading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()

  const [sel, setSel] = useState<Set<string>>(new Set())
  const [busca, setBusca] = useState('')
  const [abierto, setAbierto] = useState(false)
  const [motivo, setMotivo] = useState('Prueba de agosto 2026')
  const [hasta, setHasta] = useState(hoyISO())
  const [busy, setBusy] = useState(false)

  const { data: equipos = [], isLoading, refetch } = useQuery({
    queryKey: ['equipos-para-archivar'], queryFn: getEquiposParaArchivar,
  })
  const { data: lotes = [], refetch: refetchLotes } = useQuery({
    queryKey: ['archivo-lotes', 'equipo'], queryFn: () => getLotesArchivo(),
  })
  const lotesEquipo = useMemo(() => lotes.filter((l) => l.entidad === 'equipo'), [lotes])

  const visibles = useMemo(() => {
    const q = busca.trim().toLowerCase()
    const conAlgo = equipos.filter((e) => e.n_total > 0)
    if (!q) return conAlgo
    return conAlgo.filter((e) =>
      (e.patente ?? '').toLowerCase().includes(q) ||
      (e.activo_codigo ?? '').toLowerCase().includes(q) ||
      (e.activo_nombre ?? '').toLowerCase().includes(q))
  }, [equipos, busca])

  const elegidos = useMemo(() => equipos.filter((e) => sel.has(e.activo_id)), [equipos, sel])
  const totalElegido = elegidos.reduce((a, e) => a + e.n_total, 0)
  const valesPendientes = elegidos.reduce((a, e) => a + e.vales_con_pendiente, 0)

  if (authLoading) return <div className="flex justify-center py-20"><Spinner /></div>

  const toggle = (id: string) => setSel((p) => {
    const n = new Set(p); n.has(id) ? n.delete(id) : n.add(id); return n
  })

  const refrescar = () => {
    void refetch(); void refetchLotes()
    qc.invalidateQueries({ queryKey: ['nc-recepcion'] })
    qc.invalidateQueries({ queryKey: ['mec-ots'] })
  }

  const guardar = async () => {
    setBusy(true)
    try {
      const r = await archivarEquipos(Array.from(sel), motivo, hasta || null)
      if (!r.success) { toast.error(r.mensaje ?? 'No se guardó nada'); return }
      toast.success(
        `${r.total} registros de ${r.patentes} al historial · ` +
        `${r.no_conformidades} NC, ${r.ordenes_trabajo} OT, ${r.vales} vales, ` +
        `${r.repuestos} repuestos, ${r.checklists} checklists`)
      setAbierto(false); setSel(new Set()); refrescar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  const deshacer = async (loteId: string) => {
    setBusy(true)
    try {
      const r = await deshacerLote(loteId)
      toast.success(`${r.devueltos} registros de vuelta.`)
      refrescar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <div className="space-y-4 p-4 md:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <Archive className="h-6 w-6 text-gray-700" /> Guardar equipos en el historial
        </h1>
        <p className="mt-1 max-w-3xl text-sm text-gray-600">
          Elige las patentes y todo lo suyo pasa a historia de una vez: no conformidades, órdenes
          de trabajo, vales de bodega, repuestos pedidos y checklists. <b>No se borra nada</b> —
          sale de las pantallas operativas y se puede devolver completo.
        </p>
      </div>

      {lotesEquipo.some((l) => l.vigente) && (
        <div className="space-y-1.5">
          {lotesEquipo.filter((l) => l.vigente).slice(0, 3).map((l) => (
            <div key={l.id} className="flex flex-wrap items-center gap-2 rounded-lg border border-gray-200 bg-gray-50 px-3 py-1.5 text-[12px] text-gray-600">
              <Archive className="h-3.5 w-3.5 text-gray-400" />
              <span><b>{l.n_registros}</b> registros · «{l.motivo}» · {new Date(l.archivado_at).toLocaleString('es-CL')} por {l.archivado_por_nombre}</span>
              <button type="button" disabled={busy} onClick={() => deshacer(l.id)}
                      className="flex items-center gap-1 font-semibold text-blue-600 underline disabled:opacity-50">
                <Undo2 className="h-3 w-3" /> Deshacer
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="relative max-w-sm">
        <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
        <Input value={busca} onChange={(e) => setBusca(e.target.value)} className="pl-8"
               placeholder="Buscar patente, código o nombre…" />
      </div>

      {isLoading ? <div className="flex justify-center py-10"><Spinner /></div> : (
        <Card>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-left text-[11px] uppercase tracking-wide text-gray-500">
                  <tr>
                    <th className="w-10 p-2">
                      <input type="checkbox"
                             checked={visibles.length > 0 && visibles.every((e) => sel.has(e.activo_id))}
                             onChange={(ev) => setSel(ev.target.checked
                               ? new Set(visibles.map((e) => e.activo_id))
                               : new Set())}
                             title="Elegir todas las de la lista"
                             className="h-3.5 w-3.5 cursor-pointer" />
                    </th>
                    <th className="p-2">Equipo</th>
                    <th className="p-2 text-right">NC</th>
                    <th className="p-2 text-right">OT</th>
                    <th className="p-2 text-right">Vales</th>
                    <th className="p-2 text-right">Repuestos</th>
                    <th className="p-2 text-right">Checklists</th>
                    <th className="p-2 text-right">Total</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {visibles.map((e) => (
                    <tr key={e.activo_id}
                        className={`cursor-pointer hover:bg-gray-50 ${sel.has(e.activo_id) ? 'bg-blue-50' : ''}`}
                        onClick={() => toggle(e.activo_id)}>
                      <td className="p-2">
                        <input type="checkbox" checked={sel.has(e.activo_id)}
                               onChange={() => toggle(e.activo_id)}
                               onClick={(ev) => ev.stopPropagation()}
                               className="h-3.5 w-3.5 cursor-pointer" />
                      </td>
                      <td className="p-2">
                        <div className="font-semibold text-gray-800">{e.patente ?? e.activo_codigo}</div>
                        <div className="text-[11px] text-gray-500">{e.activo_nombre}</div>
                        {e.vales_con_pendiente > 0 && (
                          <div className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-800"
                               title="Tiene vales sin despachar: repuestos pedidos que nunca llegaron">
                            <AlertTriangle className="h-3 w-3" />
                            {e.vales_con_pendiente} vale{e.vales_con_pendiente !== 1 ? 's' : ''} sin despachar
                          </div>
                        )}
                      </td>
                      <td className="p-2 text-right tabular-nums text-gray-600">{e.n_nc || '—'}</td>
                      <td className="p-2 text-right tabular-nums text-gray-600">{e.n_ot || '—'}</td>
                      <td className="p-2 text-right tabular-nums text-gray-600">{e.n_vales || '—'}</td>
                      <td className="p-2 text-right tabular-nums text-gray-600">{e.n_recursos || '—'}</td>
                      <td className="p-2 text-right tabular-nums text-gray-600">{e.n_checklists || '—'}</td>
                      <td className="p-2 text-right font-bold tabular-nums">{e.n_total}</td>
                    </tr>
                  ))}
                  {visibles.length === 0 && (
                    <tr><td colSpan={8} className="py-8 text-center text-sm text-gray-400">
                      {equipos.length === 0 ? 'Cargando…' : 'No queda ningún equipo con registros sin archivar.'}
                    </td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}

      {sel.size > 0 && (
        <div className="sticky bottom-3 z-20 flex flex-wrap items-center gap-3 rounded-xl border border-gray-800 bg-gray-900 px-4 py-2.5 text-white shadow-lg">
          <span className="text-sm font-semibold">
            {sel.size} patente{sel.size !== 1 ? 's' : ''} · {totalElegido} registros
          </span>
          {valesPendientes > 0 && (
            <span className="rounded-full bg-amber-400 px-2 py-0.5 text-[11px] font-bold text-amber-950">
              {valesPendientes} vale{valesPendientes !== 1 ? 's' : ''} sin despachar
            </span>
          )}
          <Button onClick={() => setAbierto(true)} className="h-8 bg-white text-gray-900 hover:bg-gray-100">
            <Archive className="mr-1 h-3.5 w-3.5" /> Guardar en el historial
          </Button>
          <button type="button" onClick={() => setSel(new Set())}
                  className="ml-auto text-xs text-gray-300 hover:text-white">Quitar la selección</button>
        </div>
      )}

      {abierto && (
        <Modal open onClose={() => setAbierto(false)} title="Guardar equipos en el historial">
          <div className="space-y-3">
            <p className="text-sm text-gray-600">
              Se van a guardar <b>{totalElegido} registros</b> de <b>{sel.size} patente{sel.size !== 1 ? 's' : ''}</b>:
            </p>
            <div className="max-h-40 overflow-y-auto rounded-lg border border-gray-200 bg-gray-50 p-2 text-[12px]">
              {elegidos.map((e) => (
                <div key={e.activo_id} className="flex justify-between py-0.5">
                  <span className="font-medium">{e.patente ?? e.activo_codigo}</span>
                  <span className="text-gray-500">
                    {e.n_nc} NC · {e.n_ot} OT · {e.n_vales} vales · {e.n_recursos} rep. · {e.n_checklists} chk
                  </span>
                </div>
              ))}
            </div>

            {valesPendientes > 0 && (
              <div className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-[12px] text-amber-900">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span>
                  Hay <b>{valesPendientes} vale{valesPendientes !== 1 ? 's' : ''} sin despachar</b> entre lo
                  seleccionado. Son repuestos que se pidieron y nunca llegaron: al archivarlos salen de la
                  bandeja de bodega. Si todavía se esperan, conviene despacharlos o anularlos antes.
                </span>
              </div>
            )}

            <label className="block text-xs font-medium text-gray-700">
              ¿Por qué se guardan?
              <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                     placeholder="Prueba de agosto 2026" className="mt-1" />
            </label>
            <label className="block text-xs font-medium text-gray-700">
              Guardar sólo lo creado hasta
              <Input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="mt-1" />
              <span className="mt-0.5 block text-[11px] font-normal text-gray-400">
                Lo posterior a esta fecha se queda en las pantallas. Sirve para cerrar agosto sin
                arrastrar lo que ya empezó después.
              </span>
            </label>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setAbierto(false)}>Cancelar</Button>
            <Button disabled={busy || motivo.trim().length < 4} onClick={guardar}>
              {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Archive className="mr-1 h-4 w-4" />}
              Guardar {totalElegido} registros
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
