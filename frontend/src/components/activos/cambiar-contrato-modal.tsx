'use client'

import { useEffect, useState } from 'react'
import { AlertTriangle, Save, X, Building2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal } from '@/components/ui/modal'
import { cambiarContratoActivo } from '@/lib/services/contrato-activo'
import { cargarContratosActivos, type ContratoOption } from '@/lib/services/geocercas'

interface Props {
  abierto:              boolean
  onClose:              () => void
  activoId:             string
  activoCodigo:         string
  contratoActualId:     string | null
  contratoActualCodigo: string | null
  clienteActual:        string | null
  estadoComercial:      string | null
  onCambioOk:           () => void
}

export function CambiarContratoModal({
  abierto, onClose, activoId, activoCodigo,
  contratoActualId, contratoActualCodigo, clienteActual,
  estadoComercial, onCambioOk,
}: Props) {
  const [contratos, setContratos] = useState<ContratoOption[]>([])
  const [nuevoContratoId, setNuevoContratoId] = useState<string>('')
  const [razon, setRazon] = useState('')
  const [loading, setLoading] = useState(false)
  const [saving, setSaving]   = useState(false)
  const [error, setError]     = useState<string | null>(null)

  useEffect(() => {
    if (!abierto) return
    setError(null)
    setNuevoContratoId(contratoActualId ?? '')
    setRazon('')
    setLoading(true)
    cargarContratosActivos()
      .then(setContratos)
      .catch((e) => setError((e as Error).message))
      .finally(() => setLoading(false))
  }, [abierto, contratoActualId])

  const estaArrendado = estadoComercial === 'arrendado'
  const cambioReal = (nuevoContratoId || null) !== contratoActualId

  const handleGuardar = async () => {
    if (!cambioReal) {
      setError('No hay cambio: el contrato sigue siendo el mismo.')
      return
    }
    if (estaArrendado && !confirm(
      `El activo ${activoCodigo} está ARRENDADO al cliente "${clienteActual}". ` +
      `Cambiar el contrato sin pasar por en_recepcion puede dejar inconsistencias.\n\n` +
      `¿Realmente quieres cambiar el contrato ahora?`
    )) {
      return
    }
    setSaving(true); setError(null)
    try {
      await cambiarContratoActivo({
        activoId,
        nuevoContratoId: nuevoContratoId || null,
        razon: razon.trim() || undefined,
      })
      onCambioOk()
      onClose()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  if (!abierto) return null

  return (
    <Modal open={abierto} onClose={onClose} title={`Cambiar contrato — ${activoCodigo}`}>
      <div className="space-y-4">
        {/* Estado actual */}
        <div className="rounded-lg border bg-gray-50 p-3 text-sm">
          <div className="flex items-center gap-2 text-gray-700">
            <Building2 className="h-4 w-4 text-gray-500" />
            <span>Contrato actual:</span>
            {contratoActualCodigo ? (
              <span className="font-medium">{contratoActualCodigo} · {clienteActual}</span>
            ) : (
              <span className="italic text-gray-500">Sin contrato</span>
            )}
          </div>
          {estaArrendado && (
            <div className="mt-2 flex items-start gap-2 text-amber-700">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span className="text-xs">
                Activo en estado <b>ARRENDADO</b>. Cambiar contrato sin pasar por en_recepcion
                puede afectar el flujo de cobro/checklist. Procede solo si sabes lo que haces.
              </span>
            </div>
          )}
        </div>

        {/* Selector nuevo contrato */}
        <div>
          <label className="text-xs font-medium text-gray-700">Nuevo contrato</label>
          <select
            value={nuevoContratoId}
            onChange={(e) => setNuevoContratoId(e.target.value)}
            className="mt-1 w-full h-10 rounded-md border border-gray-200 bg-white px-2 text-sm"
            disabled={loading}>
            <option value="">— Sin contrato (quitar) —</option>
            {contratos.map((c) => (
              <option key={c.id} value={c.id}>
                {c.codigo} · {c.cliente}
              </option>
            ))}
          </select>
          {loading && <div className="mt-1 text-xs text-gray-500">Cargando contratos...</div>}
        </div>

        {/* Razón */}
        <div>
          <label className="text-xs font-medium text-gray-700">Razón del cambio (opcional)</label>
          <textarea
            value={razon}
            onChange={(e) => setRazon(e.target.value)}
            placeholder="Ej: reasignación a faena Codelco Norte por solicitud cliente"
            className="mt-1 w-full rounded border border-gray-200 px-2 py-1.5 text-sm focus:border-blue-500 focus:outline-none"
            rows={3}
          />
          <p className="mt-1 text-[10px] text-gray-500">
            Queda registrado en el histórico para trazabilidad comercial.
          </p>
        </div>

        {error && (
          <div className="flex items-center gap-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </div>
        )}

        {/* Botones */}
        <div className="flex justify-end gap-2 border-t pt-3">
          <Button variant="outline" size="sm" onClick={onClose} disabled={saving}>
            <X className="mr-1 h-4 w-4" /> Cancelar
          </Button>
          <Button
            size="sm"
            onClick={handleGuardar}
            disabled={saving || !cambioReal}
            className="bg-green-600 hover:bg-green-700">
            <Save className="mr-1 h-4 w-4" />
            {saving ? 'Guardando...' : 'Cambiar contrato'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
