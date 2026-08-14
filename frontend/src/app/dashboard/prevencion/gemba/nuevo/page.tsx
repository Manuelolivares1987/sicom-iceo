'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, Footprints } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useGembaPlantillas,
  useFaenasActivas,
  useCreateGembaRecorrido,
} from '@/hooks/use-gemba'
import { useToast } from '@/hooks/use-toast'
import { useAuth } from '@/contexts/auth-context'
import {
  plantillaDeRol, seccionesDelDia, contarItems, nombreDia, CADENCIA_LABEL,
} from '@/lib/services/gemba'

const CARGO_LABEL: Record<string, string> = {
  prevencionista: 'Prevencionista de Riesgos',
  jefe_taller: 'Jefe de Taller',
  jefe_operaciones: 'Jefe de Operaciones',
}

export default function NuevoGembaPage() {
  useRequireAuth()
  const router = useRouter()
  const toast = useToast()

  const { perfil } = useAuth()
  const { data: plantillas, isLoading } = useGembaPlantillas()
  const { data: faenas } = useFaenasActivas()
  const crear = useCreateGembaRecorrido()

  const hoy = new Date().toISOString().split('T')[0]
  const ahora = new Date().toTimeString().slice(0, 5)

  const [plantillaId, setPlantillaId] = useState('')
  const [fecha, setFecha] = useState(hoy)
  const [horaInicio, setHoraInicio] = useState(ahora)
  const [lugarTipo, setLugarTipo] = useState<'taller' | 'faena'>('taller')
  const [faenaId, setFaenaId] = useState('')
  const [sector, setSector] = useState('')
  const [acompanantes, setAcompanantes] = useState('')
  const [foco, setFoco] = useState('')

  const plantilla = useMemo(
    () => plantillas?.find((p) => p.id === plantillaId),
    [plantillas, plantillaId]
  )

  // [MIG288] El checklist del cargo viene preseleccionado: son 3 y sin esto
  // cada uno tiene que acordarse de cuál es el suyo (y llenar el ajeno).
  // Los otros dos siguen disponibles en la lista — a veces se cubre al otro.
  const miPlantilla = useMemo(
    () => plantillaDeRol(plantillas, perfil?.rol), [plantillas, perfil?.rol])
  useEffect(() => {
    if (miPlantilla && !plantillaId) setPlantillaId(miPlantilla.id)
  }, [miPlantilla, plantillaId])

  // [MIG290] Lo que se va a cargar hoy: las secciones fijas más el bloque del
  // día. No el checklist completo — el recorrido diario no lo abarca.
  const seccionesHoy = useMemo(
    () => seccionesDelDia(plantilla, fecha), [plantilla, fecha])
  const totalItems = useMemo(() => contarItems(seccionesHoy), [seccionesHoy])
  const bloqueDelDia = useMemo(
    () => seccionesHoy.find((s) => s.dia != null) ?? null, [seccionesHoy])
  const rota = (plantilla?.secciones ?? []).some((s) => s.dia != null)

  const puedeIniciar =
    !!plantillaId && !!fecha && (lugarTipo === 'taller' || !!faenaId)

  const iniciar = async () => {
    try {
      const recorrido = await crear.mutateAsync({
        plantilla_id: plantillaId,
        fecha,
        hora_inicio: horaInicio,
        lugar_tipo: lugarTipo,
        faena_id: lugarTipo === 'faena' ? faenaId : undefined,
        sector: sector || undefined,
        acompanantes: acompanantes || undefined,
        foco: foco || undefined,
      })
      if (recorrido) {
        toast.success('Recorrido iniciado — checklist pre-cargado')
        router.push(`/dashboard/prevencion/gemba/${recorrido.id}`)
      }
    } catch (e: any) {
      toast.error(`No se pudo iniciar el recorrido: ${e?.message ?? 'error desconocido'}`)
    }
  }

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <Link
          href="/dashboard/prevencion/gemba"
          className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
        >
          <ArrowLeft className="h-4 w-4" /> Volver a recorridos
        </Link>
        <h1 className="mt-2 text-2xl font-bold text-gray-900 flex items-center gap-2">
          <Footprints className="h-7 w-7 text-amber-500" />
          Nuevo Recorrido Gemba
        </h1>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos del recorrido</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Select
            label="Checklist (según cargo)"
            placeholder="Seleccione un checklist…"
            value={plantillaId}
            onChange={(e) => setPlantillaId(e.target.value)}
            options={(plantillas ?? []).map((p) => ({
              value: p.id,
              label: `${p.nombre} — ${CARGO_LABEL[p.cargo] ?? p.cargo}`
                + (p.id === miPlantilla?.id ? '  ★ el de tu cargo' : ''),
            }))}
          />

          {plantilla && (
            <div className="rounded bg-blue-50 p-3 text-xs text-blue-800">
              <p>{plantilla.descripcion}</p>
              {plantilla.cadencia && (
                <p className="mt-1 font-semibold">
                  Recorrido {CADENCIA_LABEL[plantilla.cadencia].toLowerCase()}.
                </p>
              )}
              {/* Qué toca hoy: el jefe tiene que saber, antes de partir, que no
                  va a llenar 28 ítems sino 12 — y cuáles. */}
              {rota ? (
                bloqueDelDia ? (
                  <p className="mt-1">
                    Hoy es <b>{nombreDia(fecha)}</b>: van las secciones fijas más
                    el bloque <b>{bloqueDelDia.titulo.replace(/^[^·]+·\s*/, '')}</b> —
                    {' '}<b>{totalItems} ítems</b>. El resto del checklist entra los otros días.
                  </p>
                ) : (
                  <p className="mt-1">
                    {nombreDia(fecha)}: sin bloque rotativo, va solo el núcleo fijo —
                    {' '}<b>{totalItems} ítems</b>.
                  </p>
                )
              ) : (
                <p className="mt-1">{seccionesHoy.length} secciones, <b>{totalItems} ítems</b>.</p>
              )}
            </div>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              label="Fecha"
              type="date"
              value={fecha}
              onChange={(e) => setFecha(e.target.value)}
            />
            <Input
              label="Hora de inicio"
              type="time"
              value={horaInicio}
              onChange={(e) => setHoraInicio(e.target.value)}
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Select
              label="Lugar del recorrido"
              value={lugarTipo}
              onChange={(e) => setLugarTipo(e.target.value as 'taller' | 'faena')}
              options={[
                { value: 'taller', label: 'Taller' },
                { value: 'faena', label: 'Faena' },
              ]}
            />
            {lugarTipo === 'faena' ? (
              <Select
                label="Faena"
                placeholder="Seleccione la faena…"
                value={faenaId}
                onChange={(e) => setFaenaId(e.target.value)}
                options={(faenas ?? []).map((f) => ({
                  value: f.id,
                  label: `${f.nombre} (${f.codigo})`,
                }))}
              />
            ) : (
              <Input
                label="Sector / zona del taller"
                placeholder="Ej: Zona soldadura, bahía 2…"
                value={sector}
                onChange={(e) => setSector(e.target.value)}
              />
            )}
          </div>

          {lugarTipo === 'faena' && (
            <Input
              label="Sector / zona de la faena (opcional)"
              placeholder="Ej: Frente de trabajo norte…"
              value={sector}
              onChange={(e) => setSector(e.target.value)}
            />
          )}

          <Input
            label="Acompañantes (opcional)"
            placeholder="Ej: Jefe de Taller, Prevencionista…"
            value={acompanantes}
            onChange={(e) => setAcompanantes(e.target.value)}
          />

          <Input
            label="Foco del recorrido (opcional)"
            placeholder="Ej: Cierre de acciones pendientes, EPP, 5S…"
            value={foco}
            onChange={(e) => setFoco(e.target.value)}
          />

          <div className="flex justify-end gap-2 pt-2">
            <Link href="/dashboard/prevencion/gemba">
              <Button variant="ghost">Cancelar</Button>
            </Link>
            <Button onClick={iniciar} disabled={!puedeIniciar} loading={crear.isPending}>
              Iniciar recorrido
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
