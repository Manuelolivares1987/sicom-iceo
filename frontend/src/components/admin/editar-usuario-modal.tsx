'use client'

import { useState, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Spinner } from '@/components/ui/spinner'
import { updateUsuario } from '@/lib/services/admin'
import { getFaenas } from '@/lib/services/faenas'
import type { RolUsuario } from '@/types/database'

interface Usuario {
  id: string
  nombre_completo: string
  email: string
  rol: RolUsuario
  faena_id: string | null
  cargo: string | null
  activo: boolean
}

interface EditarUsuarioModalProps {
  open: boolean
  onClose: () => void
  usuario: Usuario | null
  onSaved: () => void
}

const rolOptions: Array<{ value: RolUsuario; label: string }> = [
  { value: 'administrador', label: 'Administrador' },
  { value: 'gerencia', label: 'Gerencia' },
  { value: 'subgerente_operaciones', label: 'Subgerente de Operaciones' },
  { value: 'supervisor', label: 'Supervisor' },
  { value: 'planificador', label: 'Planificador' },
  { value: 'tecnico_mantenimiento', label: 'Tecnico de Mantenimiento' },
  { value: 'bodeguero', label: 'Bodeguero' },
  { value: 'operador_abastecimiento', label: 'Operador de Abastecimiento' },
  { value: 'auditor', label: 'Auditor' },
  { value: 'rrhh_incentivos', label: 'RRHH Incentivos' },
]

export function EditarUsuarioModal({ open, onClose, usuario, onSaved }: EditarUsuarioModalProps) {
  const [rol, setRol] = useState<RolUsuario>('supervisor')
  const [faenaId, setFaenaId] = useState<string>('')
  const [cargo, setCargo] = useState('')
  const [activo, setActivo] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const { data: faenas } = useQuery({
    queryKey: ['faenas'],
    queryFn: async () => {
      const { data, error } = await getFaenas()
      if (error) throw error
      return data
    },
  })

  // Sync form state when usuario changes
  useEffect(() => {
    if (usuario) {
      setRol(usuario.rol)
      setFaenaId(usuario.faena_id ?? '')
      setCargo(usuario.cargo ?? '')
      setActivo(usuario.activo)
      setError(null)
    }
  }, [usuario])

  async function handleSave() {
    if (!usuario) return

    setSaving(true)
    setError(null)

    try {
      const { error: updateError } = await updateUsuario(usuario.id, {
        rol,
        faena_id: faenaId || null,
        cargo: cargo.trim() || null,
        activo,
      })

      if (updateError) {
        setError(updateError.message ?? 'Error al actualizar usuario.')
        return
      }

      onSaved()
      onClose()
    } catch {
      setError('Error inesperado al guardar.')
    } finally {
      setSaving(false)
    }
  }

  if (!usuario) return null

  return (
    <Modal open={open} onClose={onClose} title="Editar Usuario" description="Modifique el rol, faena y datos del usuario.">
      <div className="space-y-5">
        {/* Read-only fields */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">Nombre completo</label>
          <p className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm text-gray-700">
            {usuario.nombre_completo}
          </p>
        </div>

        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">Email</label>
          <p className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm text-gray-700">
            {usuario.email}
          </p>
        </div>

        {/* Editable fields */}
        <Select
          label="Rol"
          value={rol}
          onChange={(e) => setRol(e.target.value as RolUsuario)}
          options={rolOptions}
        />

        <Select
          label="Faena"
          value={faenaId}
          onChange={(e) => setFaenaId(e.target.value)}
          placeholder="Sin faena asignada"
        >
          <option value="">Sin faena asignada</option>
          {faenas?.map((f) => (
            <option key={f.id} value={f.id}>
              {f.nombre}
            </option>
          ))}
        </Select>

        <Input
          label="Cargo"
          value={cargo}
          onChange={(e) => setCargo(e.target.value)}
          placeholder="Ej: Jefe de Mantenimiento"
        />

        <div className="flex items-center gap-3">
          <label className="relative inline-flex cursor-pointer items-center">
            <input
              type="checkbox"
              checked={activo}
              onChange={(e) => setActivo(e.target.checked)}
              className="peer sr-only"
            />
            <div className="h-6 w-11 rounded-full bg-gray-200 after:absolute after:left-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:border after:border-gray-300 after:bg-white after:transition-all after:content-[''] peer-checked:bg-pillado-green-500 peer-checked:after:translate-x-full peer-checked:after:border-white peer-focus:ring-2 peer-focus:ring-pillado-green-500/20" />
          </label>
          <span className="text-sm font-medium text-gray-700">
            {activo ? 'Usuario activo' : 'Usuario inactivo'}
          </span>
        </div>

        {error && (
          <div className="rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </div>
        )}
      </div>

      <ModalFooter className="mt-6 -mx-6 -mb-6">
        <Button variant="ghost" onClick={onClose} disabled={saving}>
          Cancelar
        </Button>
        <Button onClick={handleSave} disabled={saving}>
          {saving ? <><Spinner size="sm" className="mr-2" /> Guardando...</> : 'Guardar Cambios'}
        </Button>
      </ModalFooter>
    </Modal>
  )
}
