'use client'

// ============================================================================
// Formulario de registro preventivo de terreno (MIG546)
// ----------------------------------------------------------------------------
// El mismo formulario en el teléfono del supervisor (/m/prevencion) y en el
// panel (/dashboard/prevencion/reportabilidad). Carga el registro con sus
// fotos comprimidas al bucket privado y lo deja contado para el consolidado.
// ============================================================================

import { useMemo, useRef, useState } from 'react'
import { Camera, Loader2, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { useToast } from '@/hooks/use-toast'
import {
  useActividadTipos,
  useCreateRegistro,
  useFaenasPrevencion,
  useFaenaTipos,
} from '@/hooks/use-prevencion-reportabilidad'
import { subirEvidencia, type EvidenciaArchivo } from '@/lib/services/prevencion-reportabilidad'

function hoyISO(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function RegistroTerrenoForm({
  faenaIdInicial,
  onGuardado,
  onCancelar,
}: {
  faenaIdInicial?: string | null
  onGuardado?: () => void
  onCancelar?: () => void
}) {
  const toast = useToast()
  const { data: tipos } = useActividadTipos()
  const { data: faenas } = useFaenasPrevencion()
  const { data: faenaTipos } = useFaenaTipos()
  const crear = useCreateRegistro()

  const [faenaId, setFaenaId] = useState(faenaIdInicial ?? '')
  const [tipoCodigo, setTipoCodigo] = useState('')
  const [fecha, setFecha] = useState(hoyISO())
  const [titulo, setTitulo] = useState('')
  const [descripcion, setDescripcion] = useState('')
  const [area, setArea] = useState('')
  const [duracion, setDuracion] = useState('')
  const [asistentes, setAsistentes] = useState('')
  const [quedaAbierto, setQuedaAbierto] = useState(false)
  const [archivos, setArchivos] = useState<File[]>([])
  const [subiendo, setSubiendo] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  const tipoSel = useMemo(
    () => (tipos ?? []).find((t: any) => t.codigo === tipoCodigo),
    [tipos, tipoCodigo],
  )
  const esCapacitacion = tipoCodigo === 'CAPACITACION' || tipoCodigo === 'CHARLA'
  // [MIG551] PGR y similares: el título se elige del catálogo del mandante.
  const titulosOpciones: string[] = (tipoSel as any)?.titulos_opciones ?? []

  // [MIG552] Cada faena ofrece SOLO las herramientas de su mandante (Romeral:
  // RIT/VAT/VCT/EPF; Centinela: PGR…). Faena sin mapeo = ve todos (fallback).
  const tiposVisibles = useMemo(() => {
    const permitidos = faenaId ? faenaTipos?.get(faenaId) : undefined
    if (!permitidos?.size) return tipos ?? []
    return (tipos ?? []).filter((t: any) => permitidos.has(t.codigo))
  }, [tipos, faenaTipos, faenaId])

  const elegirTipo = (codigo: string) => {
    setTipoCodigo(codigo)
    // Al cambiar de tipo, un título que era del catálogo anterior no vale.
    const opciones = (tipos ?? []).find((t: any) => t.codigo === codigo)?.titulos_opciones
    if (opciones?.length && !opciones.includes(titulo)) setTitulo('')
  }

  const elegirFaena = (id: string) => {
    setFaenaId(id)
    // Un tipo que la faena nueva no ofrece se limpia (y su título de catálogo).
    const permitidos = faenaTipos?.get(id)
    if (tipoCodigo && permitidos?.size && !permitidos.has(tipoCodigo)) {
      setTipoCodigo('')
      if (titulosOpciones.length) setTitulo('')
    }
  }

  const guardar = async () => {
    if (!faenaId) return toast.error('Elija la faena')
    if (!tipoCodigo) return toast.error('Elija el tipo de actividad')
    if (!titulo.trim()) return toast.error('Escriba un título: es lo que se lee en el consolidado')

    setSubiendo(true)
    try {
      const [anioS, mesS] = fecha.split('-')
      const evidencias: EvidenciaArchivo[] = []
      for (const f of archivos) {
        const { data, error } = await subirEvidencia(f, {
          faenaId,
          anio: Number(anioS),
          mes: Number(mesS),
          carpeta: tipoCodigo.toLowerCase(),
        })
        if (error || !data) throw error ?? new Error('No se pudo subir la evidencia')
        evidencias.push(data)
      }

      await crear.mutateAsync({
        faena_id: faenaId,
        tipo_codigo: tipoCodigo,
        fecha_actividad: fecha,
        titulo: titulo.trim(),
        descripcion: descripcion.trim() || null,
        area_sector: area.trim() || null,
        estado: tipoSel?.requiere_cierre && quedaAbierto ? 'abierto' : 'cerrado',
        duracion_minutos: esCapacitacion && duracion ? Number(duracion) : null,
        asistentes: esCapacitacion && asistentes ? Number(asistentes) : null,
        evidencias,
      })

      toast.success('Registro guardado')
      setTitulo(''); setDescripcion(''); setArea('')
      setDuracion(''); setAsistentes(''); setArchivos([]); setQuedaAbierto(false)
      onGuardado?.()
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar el registro')
    } finally {
      setSubiendo(false)
    }
  }

  return (
    <div className="space-y-3">
      <Select
        label="Faena"
        value={faenaId}
        onChange={(e) => elegirFaena(e.target.value)}
        placeholder="Elegir faena…"
        options={(faenas ?? []).map((f: any) => ({ value: f.id, label: f.nombre }))}
      />

      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">Tipo de actividad</label>
        {!faenaId && (
          <p className="mb-1 text-xs text-gray-400">Elija primero la faena: cada mandante tiene sus herramientas.</p>
        )}
        <div className="flex flex-wrap gap-2">
          {tiposVisibles.map((t: any) => (
            <button
              key={t.codigo}
              type="button"
              onClick={() => elegirTipo(t.codigo)}
              className={
                'rounded-full border px-3 py-1.5 text-sm font-medium transition-colors ' +
                (tipoCodigo === t.codigo
                  ? 'border-gray-900 bg-gray-900 text-white'
                  : 'border-gray-300 bg-white text-gray-700 hover:border-gray-400')
              }
            >
              {t.nombre}
            </button>
          ))}
        </div>
        {tipoSel?.descripcion && (
          <p className="mt-1 text-xs text-gray-500">{tipoSel.descripcion}</p>
        )}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Fecha" type="date" value={fecha} max={hoyISO()}
               onChange={(e) => setFecha(e.target.value)} />
        <Input label="Área / sector" value={area} placeholder="Ej: taller, rajo…"
               onChange={(e) => setArea(e.target.value)} />
      </div>

      {titulosOpciones.length > 0 ? (
        <Select
          label="Título (catálogo del mandante)"
          value={titulo}
          onChange={(e) => setTitulo(e.target.value)}
          placeholder="Elegir herramienta…"
          options={titulosOpciones.map((t) => ({ value: t, label: t }))}
        />
      ) : (
        <Input label="Título" value={titulo} maxLength={200}
               placeholder="Ej: VCT izaje con camión pluma"
               onChange={(e) => setTitulo(e.target.value)} />
      )}

      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">
          Descripción / observaciones
        </label>
        <textarea
          className="min-h-[80px] w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          value={descripcion}
          onChange={(e) => setDescripcion(e.target.value)}
        />
      </div>

      {esCapacitacion && (
        <div className="grid grid-cols-2 gap-3">
          <Input label="Duración (min)" type="number" min={1} value={duracion}
                 onChange={(e) => setDuracion(e.target.value)} />
          <Input label="Asistentes" type="number" min={0} value={asistentes}
                 onChange={(e) => setAsistentes(e.target.value)} />
        </div>
      )}

      {tipoSel?.requiere_cierre && (
        <label className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          <input type="checkbox" checked={quedaAbierto}
                 onChange={(e) => setQuedaAbierto(e.target.checked)}
                 className="h-4 w-4" />
          Queda <b>abierto</b> (tiene hallazgos o medidas pendientes de cierre)
        </label>
      )}

      <div>
        <label className="mb-1.5 block text-sm font-medium text-gray-700">Evidencias</label>
        <input ref={fileRef} type="file" accept="image/*,.pdf" multiple hidden
               onChange={(e) => {
                 const nuevos = Array.from(e.target.files ?? [])
                 if (nuevos.length) setArchivos((prev) => [...prev, ...nuevos])
                 if (fileRef.current) fileRef.current.value = ''
               }} />
        <Button type="button" variant="outline" onClick={() => fileRef.current?.click()}>
          <Camera className="mr-2 h-4 w-4" /> Agregar foto o PDF
        </Button>
        {archivos.length > 0 && (
          <ul className="mt-2 space-y-1">
            {archivos.map((f, i) => (
              <li key={`${f.name}-${i}`}
                  className="flex items-center justify-between rounded border border-gray-200 bg-gray-50 px-2 py-1 text-xs text-gray-700">
                <span className="truncate">{f.name}</span>
                <button type="button" className="ml-2 text-gray-400 hover:text-red-500"
                        onClick={() => setArchivos((prev) => prev.filter((_, j) => j !== i))}>
                  <X className="h-3.5 w-3.5" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex gap-2 pt-1">
        <Button className="flex-1" onClick={guardar} disabled={subiendo}>
          {subiendo && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          Guardar registro
        </Button>
        {onCancelar && (
          <Button variant="outline" onClick={onCancelar} disabled={subiendo}>
            Cancelar
          </Button>
        )}
      </div>
    </div>
  )
}
