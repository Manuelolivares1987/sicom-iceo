'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Search, RefreshCw, Wrench, AlertTriangle, Save, Calendar, Truck, Building2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  cargarTransaccionesCliente, corregirPatenteDespacho,
  type TransaccionCombustibleCliente,
} from '@/lib/services/portal-cliente'
import {
  getVehiculosExternosAutorizados, type VehiculoExternoAutorizado,
} from '@/lib/services/combustible'
import { supabase } from '@/lib/supabase'

type ActivoMin = { id: string; codigo: string | null; patente: string | null; nombre: string | null }

function todayISO()       { return new Date().toISOString().slice(0, 10) }
function hace30diasISO()  {
  const d = new Date(); d.setDate(d.getDate() - 30); return d.toISOString().slice(0, 10)
}

export default function CorregirDespachoPage() {
  const toast = useToast()
  const [rows, setRows]             = useState<TransaccionCombustibleCliente[]>([])
  const [loading, setLoading]       = useState(true)
  const [fechaDesde, setFechaDesde] = useState(hace30diasISO())
  const [fechaHasta, setFechaHasta] = useState(todayISO())
  const [filtroPatente, setFiltroP] = useState('')
  const [seleccion, setSeleccion]   = useState<TransaccionCombustibleCliente | null>(null)

  const [activos, setActivos]   = useState<ActivoMin[]>([])
  const [externos, setExternos] = useState<VehiculoExternoAutorizado[]>([])

  const cargar = async () => {
    setLoading(true)
    try {
      const data = await cargarTransaccionesCliente({ fechaDesde, fechaHasta })
      setRows(data)
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudieron cargar los despachos.'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    (async () => {
      const [act, ext] = await Promise.all([
        supabase.from('activos').select('id, codigo, patente, nombre').order('patente'),
        getVehiculosExternosAutorizados(),
      ])
      setActivos((act.data ?? []) as ActivoMin[])
      setExternos(ext)
    })()
  }, [])

  useEffect(() => {
    const t = setTimeout(cargar, 300)
    return () => clearTimeout(t)
    /* eslint-disable-next-line react-hooks/exhaustive-deps */
  }, [fechaDesde, fechaHasta])

  const filtradas = useMemo(() => {
    if (!filtroPatente.trim()) return rows
    const q = filtroPatente.toLowerCase()
    return rows.filter((r) =>
      (r.activo_patente ?? '').toLowerCase().includes(q) ||
      (r.externo_patente ?? '').toLowerCase().includes(q)
    )
  }, [rows, filtroPatente])

  return (
    <div className="p-4 sm:p-6 max-w-6xl mx-auto space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <Link href="/dashboard/combustible">
          <Button variant="outline" size="sm">
            <ArrowLeft className="h-4 w-4 mr-1" /> Volver
          </Button>
        </Link>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Wrench className="h-5 w-5 text-amber-700" />
          Corregir patente de despacho
        </h1>
        <div className="flex-1" />
        <Button variant="outline" size="sm" onClick={cargar} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-1 ${loading ? 'animate-spin' : ''}`} />
          Actualizar
        </Button>
      </div>

      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900 flex items-start gap-2">
        <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          Solo cambia la <strong>patente / vehículo</strong> del despacho. Litros, fecha, fotos, CPP y
          costo quedan intactos. Se anexa una marca de auditoría en la observación con quién hizo el
          cambio y la patente original. Solo administrador o subgerente.
        </div>
      </div>

      <Card>
        <CardContent className="p-3">
          <div className="grid gap-2 md:grid-cols-3">
            <div>
              <label className="text-[10px] font-medium text-gray-500">Desde</label>
              <Input type="date" value={fechaDesde} onChange={(e) => setFechaDesde(e.target.value)} />
            </div>
            <div>
              <label className="text-[10px] font-medium text-gray-500">Hasta</label>
              <Input type="date" value={fechaHasta} onChange={(e) => setFechaHasta(e.target.value)} />
            </div>
            <div className="relative">
              <label className="text-[10px] font-medium text-gray-500">Buscar patente</label>
              <Search className="absolute left-2 top-7 h-3 w-3 text-gray-400" />
              <Input value={filtroPatente} onChange={(e) => setFiltroP(e.target.value)}
                     placeholder="ej: XXXX-NN" className="pl-7" />
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="border-b">
          <CardTitle className="text-base">Despachos del período · {filtradas.length} resultados</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : filtradas.length === 0 ? (
            <div className="p-8 text-center text-sm text-gray-500">
              Sin despachos en el período/filtro seleccionado.
            </div>
          ) : (
            <div className="max-h-[60vh] overflow-auto">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-gray-50">
                  <tr>
                    <th className="px-2 py-2 text-left">Fecha</th>
                    <th className="px-2 py-2 text-left">Patente actual</th>
                    <th className="px-2 py-2 text-left">Empresa / Cliente</th>
                    <th className="px-2 py-2 text-right">Litros</th>
                    <th className="px-2 py-2 text-left">Estanque</th>
                    <th className="px-2 py-2 text-center"></th>
                  </tr>
                </thead>
                <tbody>
                  {filtradas.map((r) => (
                    <tr key={r.id} className="border-t hover:bg-gray-50">
                      <td className="px-2 py-1.5 text-gray-500 whitespace-nowrap">
                        {new Date(r.fecha).toLocaleString('es-CL')}
                      </td>
                      <td className="px-2 py-1.5 font-medium">
                        {r.activo_patente ? (
                          <span><Badge className="bg-blue-100 text-blue-700">flota</Badge> {r.activo_patente}</span>
                        ) : r.externo_patente ? (
                          <span><Badge className="bg-purple-100 text-purple-700">externo</Badge> {r.externo_patente}</span>
                        ) : '—'}
                      </td>
                      <td className="px-2 py-1.5 text-gray-600">
                        {r.activo_cliente ?? r.externo_empresa ?? '—'}
                      </td>
                      <td className="px-2 py-1.5 text-right font-mono">{Number(r.litros).toFixed(1)} L</td>
                      <td className="px-2 py-1.5 text-gray-500">{r.estanque_codigo ?? '—'}</td>
                      <td className="px-2 py-1.5 text-right">
                        <Button size="sm" variant="outline"
                                onClick={() => setSeleccion(r)}
                                className="border-amber-300 text-amber-700 hover:bg-amber-50">
                          <Wrench className="h-3 w-3 mr-1" /> Corregir
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {seleccion && (
        <CorregirModal
          trx={seleccion}
          activos={activos}
          externos={externos}
          onClose={() => setSeleccion(null)}
          onSaved={() => { setSeleccion(null); cargar() }}
        />
      )}
    </div>
  )
}

function CorregirModal({
  trx, activos, externos, onClose, onSaved,
}: {
  trx: TransaccionCombustibleCliente
  activos: ActivoMin[]
  externos: VehiculoExternoAutorizado[]
  onClose: () => void
  onSaved: () => void
}) {
  const toast = useToast()
  const eraExterno = trx.externo_patente != null
  const [tipo, setTipo]       = useState<'flota' | 'externo'>(eraExterno ? 'externo' : 'flota')
  const [equipoId, setEqId]   = useState('')
  const [externoId, setExtId] = useState('')
  const [motivo, setMotivo]   = useState('')
  const [saving, setSaving]   = useState(false)

  const canSave =
    motivo.trim().length >= 10
    && (tipo === 'flota' ? !!equipoId : !!externoId)
    && !saving

  const onSubmit = async () => {
    if (!canSave) return
    setSaving(true)
    try {
      const res = await corregirPatenteDespacho({
        id: trx.id,
        nuevoEquipoId:           tipo === 'flota'   ? equipoId : null,
        nuevoVehiculoExternoId:  tipo === 'externo' ? externoId : null,
        motivo: motivo.trim(),
      })
      toast.success(`Patente corregida: ${res.patente_anterior} → ${res.patente_nueva}`)
      onSaved()
    } catch (e) {
      toast.error(errorMessage(e, 'Error al corregir patente.'))
      setSaving(false)
    }
  }

  return (
    <Modal open={true} onClose={onClose} title="Corregir patente del despacho">
      <div className="space-y-3 text-sm">
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs space-y-1">
          <div className="flex items-center gap-1 text-gray-500">
            <Calendar className="h-3 w-3" />
            {new Date(trx.fecha).toLocaleString('es-CL')}
          </div>
          <div className="flex items-center gap-1">
            <Truck className="h-3 w-3 text-gray-500" />
            <span className="font-semibold">Patente actual: </span>
            {trx.activo_patente ?? trx.externo_patente ?? '—'}
          </div>
          <div className="flex items-center gap-1">
            <Building2 className="h-3 w-3 text-gray-500" />
            {trx.activo_cliente ?? trx.externo_empresa ?? '—'}
            {' · '}
            <span className="font-mono">{Number(trx.litros).toFixed(1)} L</span>
            {' · '}
            <span className="text-gray-500">{trx.estanque_codigo ?? ''}</span>
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Nuevo tipo de vehículo</label>
          <div className="flex gap-2">
            <button type="button" onClick={() => setTipo('flota')}
                    className={`flex-1 rounded-md border px-3 py-2 text-xs ${
                      tipo === 'flota' ? 'border-blue-500 bg-blue-50 text-blue-900'
                      : 'border-gray-300 bg-white text-gray-700'}`}>
              Flota propia
            </button>
            <button type="button" onClick={() => setTipo('externo')}
                    className={`flex-1 rounded-md border px-3 py-2 text-xs ${
                      tipo === 'externo' ? 'border-purple-500 bg-purple-50 text-purple-900'
                      : 'border-gray-300 bg-white text-gray-700'}`}>
              Externo autorizado
            </button>
          </div>
        </div>

        {tipo === 'flota' ? (
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Equipo de la flota *</label>
            <select value={equipoId} onChange={(e) => setEqId(e.target.value)}
                    className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
              <option value="">— Selecciona equipo —</option>
              {activos.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.patente ?? '(sin patente)'} · {a.codigo ?? '—'} {a.nombre ? `· ${a.nombre}` : ''}
                </option>
              ))}
            </select>
          </div>
        ) : (
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Vehículo externo autorizado *</label>
            <select value={externoId} onChange={(e) => setExtId(e.target.value)}
                    className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
              <option value="">— Selecciona patente —</option>
              {externos.map((v) => (
                <option key={v.id} value={v.id}>{v.patente} · {v.empresa}</option>
              ))}
            </select>
          </div>
        )}

        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">
            Motivo de la corrección * (mínimo 10 caracteres)
          </label>
          <textarea
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm min-h-[70px]"
            placeholder="ej: Bodeguero anoto patente equivocada. Confirmado con receptor que era HSFD-76, no HSFD-77."
          />
          <div className="text-[10px] text-gray-500 mt-1">{motivo.length} / mín 10</div>
        </div>

        <div className="flex justify-between pt-2 border-t">
          <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSave}
                  className="bg-amber-600 hover:bg-amber-700">
            {saving ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {saving ? 'Corrigiendo…' : 'Aplicar corrección'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
