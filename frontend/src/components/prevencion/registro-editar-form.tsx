'use client'

// ============================================================================
// Corrección de un registro de terreno (MIG561)
// ----------------------------------------------------------------------------
// El supervisor se equivocó: puede corregir fecha, título, descripción, área
// y evidencias de SU registro (la RLS lo limita a registros abiertos o con
// menos de 24 h), o borrarlo de plano y cargarlo de nuevo. El tipo no se
// cambia: para eso se borra y se vuelve a cargar con el tipo correcto.
// ============================================================================

import { useMemo, useRef, useState } from 'react'
import { Camera, Loader2, Trash2, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { useToast } from '@/hooks/use-toast'
import {
  useActividadTipos, useDeleteRegistro, useUpdateRegistro,
} from '@/hooks/use-prevencion-reportabilidad'
import {
  subirEvidencia,
  type EvidenciaArchivo, type PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'

export function RegistroEditarForm({
  registro,
  onGuardado,
  onCancelar,
}: {
  registro: PrevencionRegistro
  onGuardado?: () => void
  onCancelar?: () => void
}) {
  const toast = useToast()
  const { data: tipos } = useActividadTipos()
  const actualizar = useUpdateRegistro()
  const eliminar = useDeleteRegistro()

  const [fecha, setFecha] = useState(registro.fecha_actividad)
  const [titulo, setTitulo] = useState(registro.titulo)
  const [descripcion, setDescripcion] = useState(registro.descripcion ?? '')
  const [area, setArea] = useState(registro.area_sector ?? '')
  const [evidencias, setEvidencias] = useState<EvidenciaArchivo[]>(registro.evidencias ?? [])
  const [nuevos, setNuevos] = useState<File[]>([])
  const [guardando, setGuardando] = useState(false)
  const [confirmandoBorrado, setConfirmandoBorrado] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  // Tipos con catálogo (PGR, Anexo 10.2): el título corregido también sale
  // del catálogo del mandante, no de texto libre.
  const titulosOpciones: string[] = useMemo(() => {
    const t = (tipos ?? []).find((x: any) => x.codigo === registro.tipo_codigo)
    return (t as any)?.titulos_opciones ?? []
  }, [tipos, registro.tipo_codigo])

  const guardar = async () => {
    if (!titulo.trim()) return toast.error('El título no puede quedar vacío')
    setGuardando(true)
    try {
      const [anioS, mesS] = fecha.split('-')
      const subidas: EvidenciaArchivo[] = []
      for (const f of nuevos) {
        const { data, error } = await subirEvidencia(f, {
          faenaId: registro.faena_id,
          anio: Number(anioS),
          mes: Number(mesS),
          carpeta: registro.tipo_codigo.toLowerCase(),
        })
        if (error || !data) throw error ?? new Error('No se pudo subir la evidencia')
        subidas.push(data)
      }
      await actualizar.mutateAsync({
        id: registro.id,
        patch: {
          fecha_actividad: fecha,
          titulo: titulo.trim(),
          descripcion: descripcion.trim() || null,
          area_sector: area.trim() || null,
          evidencias: [...evidencias, ...subidas],
        },
      })
      toast.success('Registro corregido')
      onGuardado?.()
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo corregir (¿pasaron más de 24 h y está cerrado?)')
    } finally {
      setGuardando(false)
    }
  }

  const borrar = async () => {
    setGuardando(true)
    try {
      await eliminar.mutateAsync(registro.id)
      toast.success('Registro eliminado — puede cargarlo de nuevo correcto')
      onGuardado?.()
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo eliminar (¿pasaron más de 24 h?)')
    } finally {
      setGuardando(false)
      setConfirmandoBorrado(false)
    }
  }

  return (
    <div className="space-y-3">
      <p className="rounded-lg bg-gray-100 px-3 py-2 text-xs text-gray-600">
        <b>{registro.tipo_codigo}</b> — el tipo no se cambia: si se equivocó de
        tipo, elimine el registro y cárguelo de nuevo.
      </p>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Fecha" type="date" value={fecha}
               onChange={(e) => setFecha(e.target.value)} />
        <Input label="Área / sector" value={area}
               onChange={(e) => setArea(e.target.value)} />
      </div>

      {titulosOpciones.length > 0 ? (
        <Select
          label="Título (catálogo del mandante)"
          value={titulo}
          onChange={(e) => setTitulo(e.target.value)}
          placeholder="Elegir…"
          options={titulosOpciones.map((t) => ({ value: t, label: t }))}
        />
      ) : (
        <Input label="Título" value={titulo} maxLength={200}
               onChange={(e) => setTitulo(e.target.value)} />
      )}

      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">
          Descripción / observaciones
        </label>
        <textarea
          className="min-h-[80px] w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
          value={descripcion}
          onChange={(e) => setDescripcion(e.target.value)}
        />
      </div>

      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">Evidencias</label>
        {evidencias.length > 0 && (
          <ul className="mb-2 space-y-1">
            {evidencias.map((ev, i) => (
              <li key={ev.path}
                  className="flex items-center justify-between rounded border border-gray-200 bg-gray-50 px-2 py-1 text-xs text-gray-700">
                <span className="truncate">{ev.nombre}</span>
                <button type="button" className="ml-2 text-gray-400 hover:text-red-500"
                        onClick={() => setEvidencias((prev) => prev.filter((_, j) => j !== i))}>
                  <X className="h-3.5 w-3.5" />
                </button>
              </li>
            ))}
          </ul>
        )}
        <input ref={fileRef} type="file" accept="image/*,.pdf" multiple hidden
               onChange={(e) => {
                 const files = Array.from(e.target.files ?? [])
                 if (files.length) setNuevos((prev) => [...prev, ...files])
                 if (fileRef.current) fileRef.current.value = ''
               }} />
        <Button type="button" variant="outline" size="sm" onClick={() => fileRef.current?.click()}>
          <Camera className="mr-2 h-4 w-4" /> Agregar foto o PDF
        </Button>
        {nuevos.length > 0 && (
          <ul className="mt-2 space-y-1">
            {nuevos.map((f, i) => (
              <li key={`${f.name}-${i}`}
                  className="flex items-center justify-between rounded border border-blue-200 bg-blue-50 px-2 py-1 text-xs text-gray-700">
                <span className="truncate">{f.name} (nueva)</span>
                <button type="button" className="ml-2 text-gray-400 hover:text-red-500"
                        onClick={() => setNuevos((prev) => prev.filter((_, j) => j !== i))}>
                  <X className="h-3.5 w-3.5" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex gap-2 pt-1">
        <Button className="flex-1" onClick={guardar} disabled={guardando}>
          {guardando && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          Guardar corrección
        </Button>
        {onCancelar && (
          <Button variant="outline" onClick={onCancelar} disabled={guardando}>Cancelar</Button>
        )}
      </div>

      {!confirmandoBorrado ? (
        <button type="button"
                className="flex w-full items-center justify-center gap-1.5 py-1 text-sm text-red-600"
                onClick={() => setConfirmandoBorrado(true)}>
          <Trash2 className="h-4 w-4" /> Eliminar este registro
        </button>
      ) : (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-center">
          <p className="mb-2 text-sm font-medium text-red-700">
            ¿Eliminar definitivamente? Las evidencias dejan de contar para el mes.
          </p>
          <div className="flex gap-2">
            <Button variant="danger" className="flex-1" onClick={borrar} disabled={guardando}>
              Sí, eliminar
            </Button>
            <Button variant="outline" className="flex-1"
                    onClick={() => setConfirmandoBorrado(false)} disabled={guardando}>
              No
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
