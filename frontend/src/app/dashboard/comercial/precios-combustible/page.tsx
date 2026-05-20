'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, RefreshCw, Plus, DollarSign, Building2, FileText, History, Save,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { formatCLP, errorMessage } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  listarPreciosVentaCombustible, setPrecioVentaCombustible,
  cargarEmpresasExternasDistintas,
  type PrecioVentaCombustible,
} from '@/lib/services/portal-cliente'
import { supabase } from '@/lib/supabase'

type ContratoRow = { id: string; codigo: string | null; cliente: string | null }

export default function PreciosCombustiblePage() {
  const toast = useToast()
  const [rows, setRows]               = useState<PrecioVentaCombustible[]>([])
  const [empresas, setEmpresas]       = useState<string[]>([])
  const [contratos, setContratos]     = useState<ContratoRow[]>([])
  const [loading, setLoading]         = useState(true)
  const [modalOpen, setModalOpen]     = useState(false)

  const cargar = async () => {
    setLoading(true)
    try {
      const [precios, empExt, contr] = await Promise.all([
        listarPreciosVentaCombustible(),
        cargarEmpresasExternasDistintas(),
        supabase.from('contratos').select('id, codigo, cliente').order('cliente'),
      ])
      setRows(precios)
      setEmpresas(empExt)
      setContratos((contr.data ?? []) as ContratoRow[])
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudieron cargar los precios.'))
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { cargar() }, [])

  const vigentes = useMemo(() => rows.filter((r) => r.vigente_hasta == null), [rows])
  const historico = useMemo(() => rows.filter((r) => r.vigente_hasta != null), [rows])

  const nombreContrato = (id: string) => {
    const c = contratos.find((x) => x.id === id)
    return c ? `${c.codigo ?? '—'} · ${c.cliente ?? '—'}` : id
  }

  return (
    <div className="p-4 sm:p-6 max-w-5xl mx-auto space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <Link href="/dashboard/comercial">
          <Button variant="outline" size="sm">
            <ArrowLeft className="h-4 w-4 mr-1" /> Volver
          </Button>
        </Link>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <DollarSign className="h-5 w-5 text-pillado-green-700" />
          Precios de venta de combustible
        </h1>
        <div className="flex-1" />
        <Button variant="outline" size="sm" onClick={cargar} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-1 ${loading ? 'animate-spin' : ''}`} />
          Actualizar
        </Button>
        <Button size="sm" onClick={() => setModalOpen(true)}
                className="bg-pillado-green-600 hover:bg-pillado-green-700">
          <Plus className="h-4 w-4 mr-1" /> Nuevo precio
        </Button>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900">
        Cada precio queda con histórico de vigencias. Al setear un precio nuevo,
        el anterior se cierra automáticamente. Los despachos ya hechos mantienen
        el precio que estaba vigente en ese momento (auditable).
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : (
        <>
          <Card>
            <CardHeader className="border-b">
              <CardTitle className="text-base flex items-center gap-2">
                <Building2 className="h-4 w-4" /> Precios vigentes ({vigentes.length})
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {vigentes.length === 0 ? (
                <div className="p-6 text-center text-sm text-gray-500">
                  Sin precios vigentes. Crea uno con "Nuevo precio".
                </div>
              ) : (
                <table className="w-full text-xs">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left">Cliente</th>
                      <th className="px-3 py-2 text-right">Precio CLP/lt</th>
                      <th className="px-3 py-2 text-left">Vigente desde</th>
                      <th className="px-3 py-2 text-left">Observación</th>
                    </tr>
                  </thead>
                  <tbody>
                    {vigentes.map((p) => (
                      <tr key={p.id} className="border-t">
                        <td className="px-3 py-2">
                          {p.empresa_externa ? (
                            <span>
                              <Badge className="bg-purple-100 text-purple-700">externo</Badge>
                              {' '}{p.empresa_externa}
                            </span>
                          ) : p.contrato_id ? (
                            <span>
                              <Badge className="bg-blue-100 text-blue-700">contrato</Badge>
                              {' '}{nombreContrato(p.contrato_id)}
                            </span>
                          ) : '—'}
                        </td>
                        <td className="px-3 py-2 text-right font-mono font-semibold text-pillado-green-700">
                          {formatCLP(p.precio_clp_lt)}
                        </td>
                        <td className="px-3 py-2 text-gray-600">
                          {new Date(p.vigente_desde).toLocaleString('es-CL')}
                        </td>
                        <td className="px-3 py-2 text-gray-500 text-[11px]">
                          {p.observacion ?? '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </CardContent>
          </Card>

          {historico.length > 0 && (
            <Card>
              <CardHeader className="border-b">
                <CardTitle className="text-base flex items-center gap-2">
                  <History className="h-4 w-4" /> Histórico cerrado ({historico.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="p-0">
                <table className="w-full text-xs">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left">Cliente</th>
                      <th className="px-3 py-2 text-right">Precio CLP/lt</th>
                      <th className="px-3 py-2 text-left">Desde</th>
                      <th className="px-3 py-2 text-left">Hasta</th>
                    </tr>
                  </thead>
                  <tbody>
                    {historico.map((p) => (
                      <tr key={p.id} className="border-t text-gray-500">
                        <td className="px-3 py-2">
                          {p.empresa_externa ?? (p.contrato_id ? nombreContrato(p.contrato_id) : '—')}
                        </td>
                        <td className="px-3 py-2 text-right font-mono">{formatCLP(p.precio_clp_lt)}</td>
                        <td className="px-3 py-2">{new Date(p.vigente_desde).toLocaleString('es-CL')}</td>
                        <td className="px-3 py-2">
                          {p.vigente_hasta ? new Date(p.vigente_hasta).toLocaleString('es-CL') : '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </CardContent>
            </Card>
          )}
        </>
      )}

      {modalOpen && (
        <NuevoPrecioModal
          empresas={empresas} contratos={contratos}
          onClose={() => setModalOpen(false)}
          onSaved={() => { setModalOpen(false); cargar() }}
        />
      )}
    </div>
  )
}

function NuevoPrecioModal({
  empresas, contratos, onClose, onSaved,
}: {
  empresas: string[]
  contratos: ContratoRow[]
  onClose: () => void
  onSaved: () => void
}) {
  const toast = useToast()
  const [target, setTarget]     = useState<'empresa' | 'contrato'>('empresa')
  const [empresa, setEmpresa]   = useState('')
  const [contratoId, setCId]    = useState('')
  const [precio, setPrecio]     = useState<number | ''>('')
  const [vigDesde, setVigDesde] = useState('')
  const [obs, setObs]           = useState('')
  const [saving, setSaving]     = useState(false)

  const canSave =
    (target === 'empresa' ? empresa.trim().length > 0 : contratoId.length > 0)
    && typeof precio === 'number' && precio > 0
    && !saving

  const onSubmit = async () => {
    if (!canSave) return
    setSaving(true)
    try {
      await setPrecioVentaCombustible({
        empresa:    target === 'empresa'  ? empresa : undefined,
        contratoId: target === 'contrato' ? contratoId : undefined,
        precioClpLt: precio as number,
        vigenteDesde: vigDesde ? new Date(vigDesde).toISOString() : undefined,
        observacion:  obs.trim() || undefined,
      })
      toast.success('Precio guardado. El anterior fue cerrado.')
      onSaved()
    } catch (e) {
      toast.error(errorMessage(e, 'Error al guardar precio.'))
      setSaving(false)
    }
  }

  return (
    <Modal open={true} onClose={onClose} title="Nuevo precio de venta">
      <div className="space-y-3 text-sm">
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">¿Para quién?</label>
          <div className="flex gap-2">
            <button type="button" onClick={() => setTarget('empresa')}
                    className={`flex-1 rounded-md border px-3 py-2 text-xs ${
                      target === 'empresa'
                        ? 'border-purple-500 bg-purple-50 text-purple-900'
                        : 'border-gray-300 bg-white text-gray-700'}`}>
              Empresa externa
            </button>
            <button type="button" onClick={() => setTarget('contrato')}
                    className={`flex-1 rounded-md border px-3 py-2 text-xs ${
                      target === 'contrato'
                        ? 'border-blue-500 bg-blue-50 text-blue-900'
                        : 'border-gray-300 bg-white text-gray-700'}`}>
              Contrato (flota propia)
            </button>
          </div>
        </div>

        {target === 'empresa' ? (
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Empresa autorizada *</label>
            <select value={empresa} onChange={(e) => setEmpresa(e.target.value)}
                    className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
              <option value="">— Selecciona empresa —</option>
              {empresas.map((e) => <option key={e} value={e}>{e}</option>)}
            </select>
          </div>
        ) : (
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Contrato *</label>
            <select value={contratoId} onChange={(e) => setCId(e.target.value)}
                    className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
              <option value="">— Selecciona contrato —</option>
              {contratos.map((c) => (
                <option key={c.id} value={c.id}>{c.codigo ?? '—'} · {c.cliente ?? '—'}</option>
              ))}
            </select>
          </div>
        )}

        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Precio CLP/lt *</label>
            <Input type="number" step="0.01" min="0.01"
                   value={precio}
                   onChange={(e) => setPrecio(e.target.value === '' ? '' : Number(e.target.value))}
                   placeholder="ej: 1180" />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Vigente desde</label>
            <Input type="datetime-local" value={vigDesde} onChange={(e) => setVigDesde(e.target.value)} />
            <p className="text-[10px] text-gray-500 mt-1">Vacío = ahora</p>
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Observación (opcional)</label>
          <Input value={obs} onChange={(e) => setObs(e.target.value)}
                 placeholder="ej: ajuste alza diesel mayo 2026" />
        </div>

        <div className="flex justify-between pt-2 border-t">
          <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSave}
                  className="bg-pillado-green-600 hover:bg-pillado-green-700">
            {saving ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {saving ? 'Guardando…' : 'Guardar precio'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
