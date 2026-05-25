'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, Plus, Search, RefreshCw, Truck, Pencil, Ban, RotateCcw, Save } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  getTodosVehiculosExternos,
  crearVehiculoExterno,
  actualizarVehiculoExterno,
  setVehiculoExternoActivo,
  type VehiculoExternoAutorizado,
} from '@/lib/services/combustible'

type FormState = { patente: string; empresa: string; notas: string }
const EMPTY_FORM: FormState = { patente: '', empresa: '', notas: '' }

export default function VehiculosExternosPage() {
  const toast = useToast()
  const [rows, setRows] = useState<VehiculoExternoAutorizado[]>([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState('')

  const [modalOpen, setModalOpen] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [saving, setSaving] = useState(false)

  const cargar = async () => {
    setLoading(true)
    try {
      setRows(await getTodosVehiculosExternos())
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudieron cargar los vehículos externos.'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { cargar() }, [])

  const filtradas = useMemo(() => {
    const q = filtro.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((v) =>
      v.patente.toLowerCase().includes(q) || v.empresa.toLowerCase().includes(q))
  }, [rows, filtro])

  const abrirCrear = () => { setEditId(null); setForm(EMPTY_FORM); setModalOpen(true) }
  const abrirEditar = (v: VehiculoExternoAutorizado) => {
    setEditId(v.id)
    setForm({ patente: v.patente, empresa: v.empresa, notas: v.notas ?? '' })
    setModalOpen(true)
  }

  const guardar = async () => {
    if (!form.patente.trim()) { toast.warning('La patente es obligatoria.'); return }
    if (!form.empresa.trim()) { toast.warning('La empresa es obligatoria.'); return }
    setSaving(true)
    try {
      if (editId) {
        await actualizarVehiculoExterno(editId, form)
        toast.success('Vehículo externo actualizado.')
      } else {
        await crearVehiculoExterno(form)
        toast.success('Patente autorizada agregada.')
      }
      setModalOpen(false)
      await cargar()
    } catch (e) {
      const msg = errorMessage(e, 'No se pudo guardar.')
      toast.error(/duplicate|uq_vehiculo_externo_patente|already exists/i.test(msg)
        ? 'Ya existe un vehículo con esa patente.'
        : msg)
    } finally {
      setSaving(false)
    }
  }

  const toggleActivo = async (v: VehiculoExternoAutorizado) => {
    try {
      await setVehiculoExternoActivo(v.id, !v.activo)
      toast.success(v.activo ? `Patente ${v.patente} revocada.` : `Patente ${v.patente} reactivada.`)
      await cargar()
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo cambiar el estado.'))
    }
  }

  return (
    <div className="space-y-4 p-6">
      <header className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <Link href="/dashboard/combustible" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-800">
            <ArrowLeft className="h-4 w-4" /> Volver a Combustible
          </Link>
          <h1 className="text-2xl font-bold flex items-center gap-2 mt-1">
            <Truck className="h-6 w-6 text-amber-700" />
            Vehículos externos autorizados
          </h1>
          <p className="text-sm text-gray-600 mt-1">
            Patentes habilitadas para recibir despacho de combustible (no son flota Pillado).
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={cargar} disabled={loading}>
            <RefreshCw className={`h-4 w-4 mr-1 ${loading ? 'animate-spin' : ''}`} /> Actualizar
          </Button>
          <Button size="sm" onClick={abrirCrear}>
            <Plus className="h-4 w-4 mr-1" /> Agregar patente
          </Button>
        </div>
      </header>

      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
        <Input className="pl-9" placeholder="Buscar patente o empresa..."
               value={filtro} onChange={(e) => setFiltro(e.target.value)} />
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><Spinner className="h-6 w-6" /></div>
      ) : filtradas.length === 0 ? (
        <Card><CardContent className="py-10 text-center text-sm text-gray-500">
          {rows.length === 0 ? 'Aún no hay vehículos externos. Agrega el primero.' : 'Sin resultados para la búsqueda.'}
        </CardContent></Card>
      ) : (
        <div className="space-y-2">
          {filtradas.map((v) => (
            <Card key={v.id} className={v.activo ? '' : 'opacity-60'}>
              <CardContent className="flex items-center justify-between gap-3 py-3 flex-wrap">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-gray-900">{v.patente}</span>
                    {v.activo
                      ? <Badge className="bg-green-100 text-green-700">Activo</Badge>
                      : <Badge className="bg-gray-200 text-gray-600">Revocado</Badge>}
                  </div>
                  <div className="text-sm text-gray-600">{v.empresa}</div>
                  {v.notas && <div className="text-xs text-gray-400 mt-0.5">{v.notas}</div>}
                </div>
                <div className="flex gap-2 shrink-0">
                  <Button variant="outline" size="sm" onClick={() => abrirEditar(v)}>
                    <Pencil className="h-4 w-4 mr-1" /> Editar
                  </Button>
                  <Button variant="outline" size="sm" onClick={() => toggleActivo(v)}>
                    {v.activo
                      ? <><Ban className="h-4 w-4 mr-1" /> Revocar</>
                      : <><RotateCcw className="h-4 w-4 mr-1" /> Reactivar</>}
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Modal open={modalOpen} onClose={() => setModalOpen(false)}
             title={editId ? 'Editar vehículo externo' : 'Agregar vehículo externo'}>
        <div className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Patente *</label>
            <Input value={form.patente} placeholder="ej: GHIJ-56"
                   onChange={(e) => setForm((f) => ({ ...f, patente: e.target.value }))} />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Empresa *</label>
            <Input value={form.empresa} placeholder="ej: Transportes Pérez"
                   onChange={(e) => setForm((f) => ({ ...f, empresa: e.target.value }))} />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Notas (opcional)</label>
            <Input value={form.notas} placeholder="ej: autorizado faena Centinela"
                   onChange={(e) => setForm((f) => ({ ...f, notas: e.target.value }))} />
          </div>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalOpen(false)} disabled={saving}>Cancelar</Button>
          <Button onClick={guardar} disabled={saving}>
            {saving ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {editId ? 'Guardar cambios' : 'Agregar'}
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}
