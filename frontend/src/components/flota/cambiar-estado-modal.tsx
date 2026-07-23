'use client'

import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { AlertTriangle, Wrench, ClipboardList, Info, ShieldCheck, Calendar } from 'lucide-react'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { cn, todayISO, errorMessage } from '@/lib/utils'
import { usePermissions } from '@/hooks/use-permissions'
import {
  useActualizarEstadoManual,
  useEstadoDiarioActivoHoy,
} from '@/hooks/use-flota'
import {
  useVerificacionActivoVigente,
  useIniciarVerificacion,
} from '@/hooks/use-verificacion'
import { useIniciarInformeRecepcion } from '@/hooks/use-informe-recepcion'
import {
  ESTADO_DIARIO_LABELS,
  ESTADO_DIARIO_COLORS,
} from '@/lib/services/flota'
import { supabase } from '@/lib/supabase'
import { cambiarContratoActivo } from '@/lib/services/contrato-activo'
import { cargarContratosActivos, crearContratoRapido, type ContratoOption } from '@/lib/services/geocercas'
import { Building2, Plus, MapPin } from 'lucide-react'

type EstadoCodigo = 'A' | 'C' | 'D' | 'H' | 'R' | 'M' | 'T' | 'F' | 'V' | 'U' | 'L'

// Ubicación real del equipo según el GPS (fn_activo_geocerca_actual)
type GpsGeo = {
  nombre: string | null
  motivo: string | null
  cercana_nombre?: string | null
  cercana_km?: number | null
  lat?: number | null
  lng?: number | null
  ts_gps?: string | null
}
type TipoOT = 'preventivo' | 'correctivo' | 'inspeccion' | 'lubricacion'
type PrioridadOT = 'emergencia' | 'alta' | 'normal' | 'baja'

interface CambiarEstadoModalProps {
  open: boolean
  onClose: () => void
  activo: {
    id: string
    patente?: string | null
    codigo?: string | null
    nombre?: string | null
    estado_comercial?: string | null
    operacion?: string | null
    cliente_actual?: string | null
    contrato_id?: string | null
    ubicacion_actual?: string | null
  } | null
  /** Estado pre-seleccionado al abrir (ej. la sugerencia GPS). */
  estadoInicial?: EstadoCodigo
  /** Fecha pre-seleccionada del cambio (ej. la fecha que se planifica). */
  fechaInicial?: string
}

const ESTADO_OPTIONS: Array<{
  value: EstadoCodigo
  label: string
  helpText: string
  group: 'productivo' | 'no_productivo' | 'mantencion'
}> = [
  { value: 'A', label: 'A — Arrendado',         group: 'productivo',     helpText: 'Equipo en faena del cliente generando ingreso' },
  { value: 'C', label: 'C — Contrato',          group: 'productivo',     helpText: 'Bajo contrato de largo plazo (arriendo continuo)' },
  { value: 'U', label: 'U — Uso Interno',       group: 'productivo',     helpText: 'En operación propia o contrato empresa' },
  { value: 'L', label: 'L — Leasing',           group: 'productivo',     helpText: 'Bajo contrato de leasing operativo' },
  { value: 'D', label: 'D — Disponible',        group: 'no_productivo',  helpText: 'Operativo y listo, sin arriendo asignado (pérdida comercial)' },
  { value: 'H', label: 'H — En Habilitación',   group: 'no_productivo',  helpText: 'En proceso de habilitación o reacondicionamiento' },
  { value: 'R', label: 'R — En Recepción',      group: 'no_productivo',  helpText: 'Recién ingresado al inventario' },
  { value: 'V', label: 'V — En Venta',          group: 'no_productivo',  helpText: 'Marcado para baja o venta' },
  { value: 'M', label: 'M — Mantención (>1 día)', group: 'mantencion',   helpText: 'Mantención programada o que dura más de un día' },
  { value: 'T', label: 'T — Taller (correctivo)', group: 'mantencion',   helpText: 'Reparación correctiva, falla operativa' },
  { value: 'F', label: 'F — Fuera de Servicio', group: 'mantencion',     helpText: 'Equipo no operativo: documentación vencida, falla mayor o restricción normativa' },
]

export function CambiarEstadoModal({ open, onClose, activo, estadoInicial, fechaInicial }: CambiarEstadoModalProps) {
  const today = todayISO()
  const { isAdmin } = usePermissions()
  const qc = useQueryClient()

  const router = useRouter()

  // Fecha del cambio: por defecto hoy. Se permite programar a futuro.
  // Solo administradores pueden corregir días pasados.
  const [fechaCambio, setFechaCambio] = useState<string>(fechaInicial ?? today)
  const esFuturo = fechaCambio > today
  const esPasado = fechaCambio < today
  const fechaInvalida = esPasado && !isAdmin()

  // ── Cargar estado actual del día ──
  const { data: estadoHoy, isLoading: loadingEstadoHoy } = useEstadoDiarioActivoHoy(activo?.id)
  const mutation = useActualizarEstadoManual()
  const iniciarVerif = useIniciarVerificacion()
  const iniciarRecepcion = useIniciarInformeRecepcion()

  // ── Verificacion ready-to-rent vigente? ──
  const { data: verifVigente, isLoading: loadingVerif } = useVerificacionActivoVigente(activo?.id)

  // ── Responsables (técnicos de mantenimiento de usuarios_perfil) ──
  // Nota: el FK ordenes_trabajo.responsable_id apunta a usuarios_perfil,
  // NO a conductores. Si pasamos un id de conductor → FK violada.
  const [tecnicos, setTecnicos] = useState<Array<{ id: string; nombre_completo: string; cargo: string | null }>>([])
  useEffect(() => {
    if (!open) return
    supabase
      .from('usuarios_perfil')
      .select('id, nombre_completo, cargo, rol')
      .eq('activo', true)
      .eq('rol', 'tecnico_mantenimiento')
      .order('nombre_completo')
      .then(({ data }) => {
        if (data) setTecnicos(data as typeof tecnicos)
      })
  }, [open])

  // ── Form state ──
  const [nuevoEstado, setNuevoEstado] = useState<EstadoCodigo>('A')
  const [motivo, setMotivo] = useState('')
  const [crearOT, setCrearOT] = useState(false)
  const [otTipo, setOtTipo] = useState<TipoOT>('correctivo')
  const [otPrioridad, setOtPrioridad] = useState<PrioridadOT>('normal')
  const [otResponsableId, setOtResponsableId] = useState<string>('')
  const [otDescripcion, setOtDescripcion] = useState('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  // Ubicación real del equipo por GPS (geocerca actual o coordenada)
  const [gpsGeo, setGpsGeo] = useState<GpsGeo | null>(null)
  const [gpsLugarLoading, setGpsLugarLoading] = useState(false)
  const [gpsError, setGpsError] = useState<string | null>(null)

  // ── Contratos: opcional cambiar contrato en el mismo flujo ──
  const [contratos, setContratos] = useState<ContratoOption[]>([])
  const [nuevoContratoId, setNuevoContratoId] = useState<string>('')
  const [razonContrato, setRazonContrato] = useState('')
  // ¿Mantiene el contrato actual o cambia a otro? (pregunta explícita)
  const [cambiarContrato, setCambiarContrato] = useState(false)
  // Crear contrato nuevo al vuelo
  const [creandoContrato, setCreandoContrato] = useState(false)
  const [nuevoContratoCodigo, setNuevoContratoCodigo] = useState('')
  const [nuevoContratoCliente, setNuevoContratoCliente] = useState('')
  const [guardandoContrato, setGuardandoContrato] = useState(false)
  // Lugar físico en texto libre (ej. Salvador, Chuquicamata)
  const [ubicacion, setUbicacion] = useState('')
  // Operación / zona (Calama / Coquimbo). Selector manual.
  const [operacion, setOperacion] = useState('')
  // Historial de cambios (contrato / operación / lugar) — siempre visible
  type HistCambio = { id: number; campo_label: string; valor_anterior: string | null; valor_nuevo: string | null; cambio_at: string }
  const [historial, setHistorial] = useState<HistCambio[]>([])
  const cargarHistorial = () => {
    if (!activo?.id) { setHistorial([]); return }
    supabase
      .from('v_historico_equipo_atributo')
      .select('id, campo_label, valor_anterior, valor_nuevo, cambio_at')
      .eq('activo_id', activo.id)
      .order('cambio_at', { ascending: false })
      .limit(50)
      .then(({ data }) => setHistorial((data ?? []) as HistCambio[]))
  }
  useEffect(() => { if (open) cargarHistorial() /* eslint-disable-line */ }, [open, activo?.id])
  useEffect(() => {
    if (!open) return
    cargarContratosActivos().then(setContratos).catch(() => { /* skip */ })
  }, [open])
  // Pre-rellenar con el contrato actual y el lugar físico al abrir/cambiar de activo
  useEffect(() => {
    if (open && activo) {
      setNuevoContratoId(activo.contrato_id ?? '')
      setRazonContrato('')
      setCambiarContrato(false)
      setCreandoContrato(false)
      setNuevoContratoCodigo('')
      setNuevoContratoCliente('')
      setUbicacion(activo.ubicacion_actual ?? '')
      setOperacion(activo.operacion ?? '')
    }
  }, [open, activo?.id, activo?.contrato_id, activo?.ubicacion_actual, activo?.operacion])

  const handleCrearContrato = async () => {
    if (!nuevoContratoCodigo.trim()) {
      setErrorMsg('Indica el código del contrato nuevo.')
      return
    }
    setGuardandoContrato(true)
    setErrorMsg(null)
    try {
      const nuevo = await crearContratoRapido({
        codigo: nuevoContratoCodigo.trim(),
        cliente: nuevoContratoCliente.trim() || undefined,
      })
      // Agregar a la lista (si no estaba) y seleccionarlo
      setContratos((prev) =>
        prev.some((c) => c.id === nuevo.id) ? prev : [...prev, nuevo].sort((a, b) => a.codigo.localeCompare(b.codigo)),
      )
      setNuevoContratoId(nuevo.id)
      setCreandoContrato(false)
      setNuevoContratoCodigo('')
      setNuevoContratoCliente('')
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'No se pudo crear el contrato')
    } finally {
      setGuardandoContrato(false)
    }
  }

  // Etiqueta del contrato actual (último contrato del activo)
  const contratoActual = useMemo(() => {
    const c = contratos.find((x) => x.id === activo?.contrato_id)
    return c ? `${c.codigo} · ${c.cliente}` : (activo?.cliente_actual || 'Sin contrato asignado')
  }, [contratos, activo?.contrato_id, activo?.cliente_actual])

  // ── Reset del formulario: SOLO al abrir o cambiar de activo.
  //    Si dependiera de estadoHoy, el refetch post-mutación borraría el errorMsg.
  useEffect(() => {
    if (open && activo) {
      setFechaCambio(fechaInicial ?? today)
      setMotivo('')
      setCrearOT(false)
      setOtTipo('correctivo')
      setOtPrioridad('normal')
      setOtResponsableId('')
      setOtDescripcion('')
      setErrorMsg(null)
    }
  }, [open, activo?.id, today])

  // ── Sincroniza el estado seleccionado con el estado del día cargado.
  useEffect(() => {
    if (open) {
      // Prioridad: estado sugerido (estadoInicial) > estado del día > 'A'
      setNuevoEstado(estadoInicial ?? (estadoHoy?.estado_codigo as EstadoCodigo) ?? 'A')
    }
  }, [open, activo?.id, estadoHoy?.estado_codigo, estadoInicial])

  // ── Pre-marcar Crear OT cuando se selecciona M, T o F ──
  useEffect(() => {
    if (nuevoEstado === 'T') {
      setOtTipo('correctivo')
      setOtPrioridad('normal')
      setCrearOT(true)
    } else if (nuevoEstado === 'M') {
      setOtTipo('preventivo')
      setOtPrioridad('normal')
      setCrearOT(true)
    } else if (nuevoEstado === 'F') {
      setOtTipo('correctivo')
      setOtPrioridad('alta')
      setCrearOT(true)
    } else {
      setCrearOT(false)
    }
  }, [nuevoEstado])

  const requiereOT = nuevoEstado === 'M' || nuevoEstado === 'T' || nuevoEstado === 'F'
  // La verificación ready-to-rent solo se ADVIERTE (no bloquea) al TRANSICIONAR
  // a disponible, y solo si el equipo NO estaba ya disponible. La gestión de la
  // verificación la hace el planificador (decisión Manuel 2026-07-22); aquí solo
  // se muestra el aviso, nunca impide guardar. Espeja el trigger
  // fn_validar_cambio_disponible de la BD (que ahora también solo advierte).
  const yaDisponible = activo?.estado_comercial === 'disponible'
  const requiereVerificacion = nuevoEstado === 'D' && !yaDisponible

  const handleSubmit = async () => {
    setErrorMsg(null)
    if (!activo) return
    if (fechaInvalida) {
      setErrorMsg('Solo administradores pueden registrar cambios en fechas pasadas')
      return
    }
    if (!motivo.trim()) {
      setErrorMsg('Debe ingresar un motivo del cambio')
      return
    }
    if (requiereOT && crearOT && !otDescripcion.trim()) {
      setErrorMsg('Debe ingresar una descripción para la OT')
      return
    }
    // ¿El estado realmente cambia? Si solo se cambia el contrato (mismo estado),
    // NO reaplicamos el estado → no se dispara el gate de checklist/verificación.
    const estadoExistente = (estadoHoy?.estado_codigo as string) || null
    const debeActualizarEstado =
      nuevoEstado !== estadoExistente || (crearOT && requiereOT) || estadoExistente === null

    // La verificación ready-to-rent ya NO bloquea: si falta, la BD registra una
    // advertencia y el planificador la gestiona. No se corta el guardado aquí.

    try {
      const lugarTrim = ubicacion.trim()
      let result: Awaited<ReturnType<typeof mutation.mutateAsync>> | null = null
      if (debeActualizarEstado) {
        result = await mutation.mutateAsync({
          activo_id: activo.id,
          fecha: fechaCambio,
          nuevo_estado: nuevoEstado,
          motivo: motivo.trim(),
          crear_ot: crearOT && requiereOT,
          ot_tipo: requiereOT && crearOT ? otTipo : undefined,
          ot_prioridad: requiereOT && crearOT ? otPrioridad : undefined,
          ot_responsable_id: otResponsableId || undefined,
          ot_descripcion: otDescripcion.trim() || undefined,
          ubicacion: lugarTrim || undefined,
        })
      }
      // El lugar físico (cuando NO cambia el estado) y la operación se guardan
      // más abajo vía RPC. NO con .update directo: la RLS de `activos` es
      // admin-only y un update directo se perdería en silencio (0 filas).

      // Contrato: independiente del estado. Se aplica si el usuario eligió cambiarlo.
      const contratoOriginal = activo.contrato_id ?? null
      const contratoNuevo    = cambiarContrato ? (nuevoContratoId || null) : contratoOriginal
      if (contratoNuevo !== contratoOriginal) {
        try {
          await cambiarContratoActivo({
            activoId: activo.id,
            nuevoContratoId: contratoNuevo,
            razon: razonContrato.trim() || `Cambio de contrato (estado ${nuevoEstado}). Motivo: ${motivo.trim()}`,
          })
        } catch (err) {
          const msg = errorMessage(err, 'Error al cambiar contrato')
          setErrorMsg(`No se pudo cambiar el contrato: ${msg}`)
          return
        }
      }

      // Si se aplicó estado y se pidió crear OT pero falló, avisar sin cerrar
      if (debeActualizarEstado && result?.success) {
        const pedidoOT = crearOT && requiereOT
        const r = result as unknown as {
          success: boolean
          ot_creada?: boolean
          ot_folio?: string | null
          ot_error?: string | null
        }
        if (pedidoOT && !r.ot_creada) {
          setErrorMsg(
            `Estado aplicado, pero la OT no se pudo crear: ${r.ot_error || 'error desconocido'}`
          )
          return
        }
      }
      // Lugar físico y operación → RPC SECURITY DEFINER (sortea la RLS admin-only
      // de `activos`). El lugar solo se aplica aquí si el estado NO cambió (si
      // cambió, ya lo guardó el RPC de estado). La operación gana sobre el
      // autocompletado desde el contrato.
      const opTrim = operacion.trim()
      const aplicarUbic = !debeActualizarEstado && lugarTrim !== (activo.ubicacion_actual ?? '')
      const aplicarOp = opTrim !== (activo.operacion ?? '')
      if (aplicarUbic || aplicarOp) {
        const { error: eAttr } = await supabase.rpc('rpc_actualizar_atributos_activo', {
          p_activo_id: activo.id,
          p_aplicar_ubicacion: aplicarUbic,
          p_ubicacion: aplicarUbic ? (lugarTrim || null) : null,
          p_aplicar_operacion: aplicarOp,
          p_operacion: aplicarOp ? (opTrim || null) : null,
        })
        if (eAttr) { setErrorMsg(`No se pudo guardar lugar/operación: ${eAttr.message}`); return }
      }

      // Propagar a toda la app: invalidar cachés que dependen de contrato /
      // cliente / lugar / estado del equipo (la mutación de estado ya invalida
      // las suyas; esto cubre el cambio de contrato y de lugar).
      ;['activo', 'ficha-activo', 'activos', 'flota-vehicular', 'sugerencias-estado',
        'historial-arriendos', 'ultimo-arriendo', 'historico-contratos',
        'matriz-estados-flota', 'reporte-flota', 'comercial-dashboard'].forEach((k) =>
        qc.invalidateQueries({ queryKey: [k] }),
      )
      onClose()
    } catch (err) {
      const message = errorMessage(err, 'Error al actualizar estado')
      setErrorMsg(message)
    }
  }

  // Carga la ubicación real del equipo por GPS al abrir el modal.
  useEffect(() => {
    if (!open || !activo?.id) return
    let cancelled = false
    const load = async () => {
      setGpsGeo(null)
      setGpsError(null)
      setGpsLugarLoading(true)
      try {
        const { data, error } = await supabase.rpc('fn_activo_geocerca_actual', {
          p_activo_id: activo.id,
        })
        if (cancelled) return
        if (error) setGpsError(errorMessage(error, 'No se pudo leer la ubicación GPS'))
        else setGpsGeo(data as GpsGeo)
      } finally {
        if (!cancelled) setGpsLugarLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [open, activo?.id])

  // Copia el nombre de la ubicación GPS al campo editable de lugar físico.
  const usarUbicacionGPS = () => {
    if (gpsGeo?.nombre) setUbicacion(gpsGeo.nombre)
  }

  const estadoActualBadge = useMemo(() => {
    const code = (estadoHoy?.estado_codigo as string) || null
    if (!code) return null
    return (
      <span
        className={cn(
          'inline-block rounded px-2 py-0.5 text-xs font-semibold',
          ESTADO_DIARIO_COLORS[code] || 'bg-gray-200 text-gray-700',
        )}
      >
        {code} — {ESTADO_DIARIO_LABELS[code]}
      </span>
    )
  }, [estadoHoy?.estado_codigo])

  if (!activo) return null

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Cambiar Estado del Equipo"
      description={`${activo.patente || activo.codigo} — ${activo.nombre || ''}`}
      className="sm:max-w-2xl"
    >
      <div className="space-y-5">
        {/* ── Contexto del activo ── */}
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-gray-500">Estado del día (hoy):</span>
            {loadingEstadoHoy ? (
              <Spinner className="h-3 w-3" />
            ) : (
              estadoActualBadge || <span className="text-gray-400">Sin registro</span>
            )}
          </div>
          {estadoHoy?.override_manual && (
            <div className="text-amber-700 flex items-center gap-1">
              <Info className="h-3 w-3" />
              Estado ya tiene un override manual de hoy
            </div>
          )}
          {activo.cliente_actual && (
            <div className="text-gray-600">
              <span className="text-gray-500">Cliente actual:</span> {activo.cliente_actual}
            </div>
          )}
          {activo.operacion && (
            <div className="text-gray-600">
              <span className="text-gray-500">Operación:</span> {activo.operacion}
            </div>
          )}
        </div>

        {/* ── Fecha del cambio (permite programar a futuro) ── */}
        <div>
          <label className="mb-1.5 flex items-center gap-1.5 text-sm font-medium text-gray-700">
            <Calendar className="h-4 w-4 text-gray-500" />
            Fecha del cambio
          </label>
          <Input
            type="date"
            value={fechaCambio}
            onChange={(e) => setFechaCambio(e.target.value)}
            min={isAdmin() ? undefined : today}
            error={fechaInvalida ? 'Solo administradores pueden corregir días pasados' : undefined}
            helperText={
              esFuturo
                ? `Cambio programado para el ${new Date(fechaCambio + 'T12:00:00').toLocaleDateString('es-CL', { day: 'numeric', month: 'long', year: 'numeric' })}. Tomará efecto ese día.`
                : esPasado
                ? 'Está corrigiendo un día pasado. Esto sobrescribe el historial.'
                : 'Hoy. El cambio aplica de inmediato.'
            }
          />
        </div>

        {/* ── Nuevo estado ── */}
        <Select
          label="Nuevo estado"
          value={nuevoEstado}
          onChange={(e) => setNuevoEstado(e.target.value as EstadoCodigo)}
          helperText={ESTADO_OPTIONS.find((o) => o.value === nuevoEstado)?.helpText}
        >
          <optgroup label="Productivo (genera ingreso)">
            {ESTADO_OPTIONS.filter((o) => o.group === 'productivo').map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </optgroup>
          <optgroup label="No productivo">
            {ESTADO_OPTIONS.filter((o) => o.group === 'no_productivo').map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </optgroup>
          <optgroup label="Mantención / Servicio">
            {ESTADO_OPTIONS.filter((o) => o.group === 'mantencion').map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </optgroup>
        </Select>

        {/* ── Motivo ── */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">
            Motivo del cambio <span className="text-red-500">*</span>
          </label>
          <textarea
            className="min-h-[80px] w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            placeholder="Ej: Falla en bomba hidráulica detectada en faena CMP Romeral"
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            maxLength={500}
          />
          <div className="mt-1 text-xs text-gray-400 text-right">{motivo.length}/500</div>
        </div>

        {/* ── Contrato: pregunta explícita mantener vs cambiar ── */}
        <div className="rounded-lg border border-blue-200 bg-blue-50/40 p-3 space-y-2.5">
          <label className="flex items-center gap-1.5 text-sm font-medium text-gray-700">
            <Building2 className="h-4 w-4 text-blue-600" />
            Contrato del equipo
          </label>

          {/* Último contrato — siempre visible, clave al pasar a mantención */}
          <div className="rounded-md border border-blue-100 bg-white px-3 py-2 text-xs">
            <span className="text-gray-500">Último contrato:</span>{' '}
            <span className="font-semibold text-gray-800">{contratoActual}</span>
            {requiereOT && (
              <div className="mt-1 text-[11px] text-amber-700">
                Pasa a mantención — se conserva este contrato como referencia para cuando vuelva a operar.
              </div>
            )}
          </div>

          {/* Ubicación REAL por GPS — dónde está físicamente el equipo ahora */}
          <div className="rounded-lg border border-blue-200 bg-blue-50/60 p-3 text-xs space-y-1">
            <div className="flex items-center gap-1.5 font-medium text-blue-800">
              <MapPin className="h-4 w-4" />
              Ubicación real por GPS
            </div>
            {gpsLugarLoading ? (
              <div className="flex items-center gap-2 text-gray-500"><Spinner className="h-3 w-3" /> Leyendo GPS…</div>
            ) : gpsError ? (
              <p className="text-amber-700">{gpsError}</p>
            ) : gpsGeo?.nombre ? (
              <div className="space-y-0.5">
                <div className="text-sm font-semibold text-gray-800">{gpsGeo.nombre}</div>
                <div className="text-[11px] text-gray-500">
                  {gpsGeo.ts_gps && `Según GPS ${new Date(gpsGeo.ts_gps).toLocaleString('es-CL')}`}
                </div>
              </div>
            ) : gpsGeo?.motivo === 'sin_gps' ? (
              <p className="text-gray-500">Este equipo no tiene señal GPS.</p>
            ) : gpsGeo ? (
              <div className="space-y-0.5">
                <div className="text-gray-700">
                  Fuera de toda geocerca.{' '}
                  {gpsGeo.cercana_nombre && (
                    <>Lo más cercano: <span className="font-medium">{gpsGeo.cercana_nombre}</span> (a {gpsGeo.cercana_km} km).</>
                  )}
                </div>
                {gpsGeo.lat != null && gpsGeo.lng != null && (
                  <a
                    href={`https://www.google.com/maps?q=${gpsGeo.lat},${gpsGeo.lng}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 text-blue-700 hover:underline"
                  >
                    <MapPin className="h-3 w-3" /> Ver en mapa ({Number(gpsGeo.lat).toFixed(4)}, {Number(gpsGeo.lng).toFixed(4)})
                  </a>
                )}
                <div className="text-[11px] text-gray-500">
                  {gpsGeo.ts_gps && `Según GPS ${new Date(gpsGeo.ts_gps).toLocaleString('es-CL')}`}
                  {' · '}No hay geocerca en este punto para nombrarlo.
                </div>
              </div>
            ) : null}
          </div>

          {/* Lugar físico (texto libre) — dónde se registra el equipo */}
          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <label className="flex items-center gap-1.5 text-xs font-medium text-gray-600">
                <MapPin className="h-3.5 w-3.5 text-blue-600" />
                Lugar físico del equipo
              </label>
              {gpsGeo?.nombre && gpsGeo.nombre !== ubicacion && (
                <button
                  type="button"
                  onClick={usarUbicacionGPS}
                  className="flex items-center gap-1 rounded-md border border-blue-200 bg-blue-50 px-2 py-0.5 text-[11px] font-medium text-blue-700 hover:bg-blue-100"
                >
                  <MapPin className="h-3 w-3" />
                  Usar «{gpsGeo.nombre}»
                </button>
              )}
            </div>
            <input
              type="text"
              value={ubicacion}
              onChange={(e) => setUbicacion(e.target.value)}
              placeholder="Ej. Salvador, Chuquicamata, Spence…"
              className="w-full rounded-md border border-gray-300 px-3 py-1.5 text-sm focus:border-blue-500 focus:outline-none"
              maxLength={200}
            />
            <p className="text-[11px] text-gray-400">
              Texto que queda en el historial del equipo. Arriba ves la ubicación real por GPS; usa el botón para copiarla.
            </p>
          </div>

          {/* Operación / zona — se completa sola desde el contrato; si no hay, elígela aquí */}
          <div className="space-y-1">
            <label className="flex items-center gap-1.5 text-xs font-medium text-gray-600">
              <MapPin className="h-3.5 w-3.5 text-emerald-600" />
              Operación / zona
            </label>
            <Select value={operacion} onChange={(e) => setOperacion(e.target.value)}>
              <option value="">— Sin asignar —</option>
              <option value="Calama">Calama</option>
              <option value="Coquimbo">Coquimbo</option>
              {operacion && !['', 'Calama', 'Coquimbo'].includes(operacion) && (
                <option value={operacion}>{operacion}</option>
              )}
            </Select>
            <p className="text-[11px] text-gray-400">
              Se completa automáticamente desde el contrato. Si el contrato no tiene zona aún, elígela aquí.
            </p>
          </div>

          {/* Historial de cambios (contrato / operación / lugar) — siempre visible */}
          <div className="rounded-md border border-gray-200 bg-white p-2.5">
            <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-gray-500">
              Historial de cambios
            </div>
            {historial.length === 0 ? (
              <p className="text-[11px] text-gray-400">Sin cambios registrados todavía.</p>
            ) : (
              <ul className="max-h-36 space-y-1 overflow-auto text-[11px]">
                {historial.map((h) => (
                  <li key={h.id} className="flex flex-wrap items-baseline gap-x-1.5 border-b border-gray-100 pb-1 last:border-0">
                    <span className="text-gray-400">{h.cambio_at?.slice(0, 16).replace('T', ' ')}</span>
                    <span className="font-medium text-gray-700">{h.campo_label}:</span>
                    <span className="text-gray-500">{h.valor_anterior ?? '—'}</span>
                    <span className="text-gray-400">→</span>
                    <span className="font-semibold text-gray-800">{h.valor_nuevo ?? '—'}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* ¿Mantiene o cambia? */}
          <div className="space-y-1.5">
            <p className="text-xs font-medium text-gray-600">¿Qué pasa con el contrato?</p>
            <label className="flex items-start gap-2 text-sm text-gray-700 cursor-pointer">
              <input
                type="radio"
                name="opcion-contrato"
                checked={!cambiarContrato}
                onChange={() => { setCambiarContrato(false); setNuevoContratoId(activo?.contrato_id ?? '') }}
                className="mt-0.5"
              />
              <span>Se mantiene en el <strong>mismo contrato</strong></span>
            </label>
            <label className="flex items-start gap-2 text-sm text-gray-700 cursor-pointer">
              <input
                type="radio"
                name="opcion-contrato"
                checked={cambiarContrato}
                onChange={() => setCambiarContrato(true)}
                className="mt-0.5"
              />
              <span>Cambia a <strong>otro contrato</strong></span>
            </label>
          </div>

          {cambiarContrato && (
            <div className="space-y-2 pl-6">
              {!creandoContrato ? (
                <>
                  <Select
                    label="Nuevo contrato"
                    value={nuevoContratoId}
                    onChange={(e) => setNuevoContratoId(e.target.value)}
                    helperText={
                      !nuevoContratoId
                        ? 'Se QUITARÁ el contrato actual (queda sin contrato).'
                        : nuevoContratoId !== (activo?.contrato_id ?? '')
                        ? 'Se CAMBIARÁ al contrato seleccionado.'
                        : 'Es el mismo contrato actual.'
                    }
                  >
                    <option value="">— Sin contrato —</option>
                    {contratos.map((c) => (
                      <option key={c.id} value={c.id}>{c.codigo} · {c.cliente}</option>
                    ))}
                  </Select>
                  <button
                    type="button"
                    onClick={() => setCreandoContrato(true)}
                    className="inline-flex items-center gap-1 text-xs font-medium text-blue-600 hover:underline"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    ¿El contrato no está en la lista? Crear uno nuevo
                  </button>
                </>
              ) : (
                <div className="rounded-md border border-blue-200 bg-white p-3 space-y-2">
                  <div className="text-xs font-semibold text-gray-700">Nuevo contrato</div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                    <Input
                      placeholder="Código * (ej. CTR-FAENA-2026)"
                      value={nuevoContratoCodigo}
                      onChange={(e) => setNuevoContratoCodigo(e.target.value)}
                    />
                    <Input
                      placeholder="Cliente / faena"
                      value={nuevoContratoCliente}
                      onChange={(e) => setNuevoContratoCliente(e.target.value)}
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <Button
                      type="button"
                      size="sm"
                      onClick={handleCrearContrato}
                      loading={guardandoContrato}
                      disabled={!nuevoContratoCodigo.trim()}
                    >
                      <Plus className="h-4 w-4" /> Crear y seleccionar
                    </Button>
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      onClick={() => { setCreandoContrato(false); setNuevoContratoCodigo(''); setNuevoContratoCliente('') }}
                      disabled={guardandoContrato}
                    >
                      Cancelar
                    </Button>
                  </div>
                  <p className="text-[11px] text-gray-400">
                    Se crea un contrato mínimo (activo). Luego puedes completar fechas, valor y SLA en Contratos.
                  </p>
                </div>
              )}

              <Input
                placeholder="Razón del cambio de contrato (opcional)"
                value={razonContrato}
                onChange={(e) => setRazonContrato(e.target.value)}
              />
            </div>
          )}
        </div>

        {/* ── Sección Crear OT ── */}
        {requiereOT && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 space-y-3">
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="crear-ot"
                checked={crearOT}
                onChange={(e) => setCrearOT(e.target.checked)}
                className="h-4 w-4 rounded border-amber-300 text-amber-600 focus:ring-amber-500"
              />
              <label htmlFor="crear-ot" className="text-sm font-medium text-amber-900 flex items-center gap-1">
                <Wrench className="h-4 w-4" />
                Crear orden de trabajo automáticamente
              </label>
            </div>

            {crearOT && (
              <div className="space-y-3 pl-6">
                <div className="grid grid-cols-2 gap-3">
                  <Select
                    label="Tipo OT"
                    value={otTipo}
                    onChange={(e) => setOtTipo(e.target.value as TipoOT)}
                  >
                    <option value="correctivo">Correctivo</option>
                    <option value="preventivo">Preventivo</option>
                    <option value="inspeccion">Inspección</option>
                    <option value="lubricacion">Lubricación</option>
                  </Select>
                  <Select
                    label="Prioridad"
                    value={otPrioridad}
                    onChange={(e) => setOtPrioridad(e.target.value as PrioridadOT)}
                  >
                    <option value="emergencia">Emergencia</option>
                    <option value="alta">Alta</option>
                    <option value="normal">Normal</option>
                    <option value="baja">Baja</option>
                  </Select>
                </div>

                <Select
                  label="Técnico responsable (opcional)"
                  value={otResponsableId}
                  onChange={(e) => setOtResponsableId(e.target.value)}
                >
                  <option value="">Sin asignar</option>
                  {tecnicos.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.nombre_completo}{t.cargo ? ` — ${t.cargo}` : ''}
                    </option>
                  ))}
                </Select>

                <div>
                  <label className="mb-1.5 block text-sm font-medium text-gray-700">
                    Descripción del trabajo <span className="text-red-500">*</span>
                  </label>
                  <textarea
                    className="min-h-[60px] w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                    placeholder="Detalle del trabajo a realizar"
                    value={otDescripcion}
                    onChange={(e) => setOtDescripcion(e.target.value)}
                    maxLength={1000}
                  />
                </div>
              </div>
            )}
          </div>
        )}

        {/* ── Ready-to-rent: advertencia (no bloquea) si pasa a D sin verificación ── */}
        {requiereVerificacion && !loadingVerif && (
          <>
            {verifVigente ? (
              <div className="flex gap-2 rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800">
                <ShieldCheck className="h-5 w-5 shrink-0" />
                <div>
                  <strong>Verificación vigente</strong> hasta{' '}
                  {new Date(verifVigente.vigente_hasta!).toLocaleString('es-CL')}.
                  El equipo puede marcarse disponible.
                </div>
              </div>
            ) : (
              <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900 space-y-2">
                <div className="flex gap-2">
                  <AlertTriangle className="h-5 w-5 shrink-0" />
                  <div>
                    <strong>Sin verificación ready-to-rent vigente.</strong> Puedes marcarlo
                    disponible igual — el planificador debe gestionar la verificación
                    (checklist de 55 ítems + road test + doble firma) antes de arrendarlo.
                    Este aviso queda registrado.
                  </div>
                </div>
                <Button
                  variant="primary"
                  size="sm"
                  loading={iniciarVerif.isPending}
                  onClick={async () => {
                    if (!activo) return
                    try {
                      const res = await iniciarVerif.mutateAsync({
                        activoId: activo.id,
                        motivo: motivo.trim() || undefined,
                      })
                      onClose()
                      if (res?.ot_id) {
                        router.push(`/dashboard/flota/verificar/${res.ot_id}`)
                      }
                    } catch (err: unknown) {
                      setErrorMsg(
                        err instanceof Error ? err.message : 'Error al iniciar verificación',
                      )
                    }
                  }}
                >
                  <ShieldCheck className="h-4 w-4" />
                  Iniciar verificación
                </Button>
              </div>
            )}
          </>
        )}

        {/* ── Recepción: cuando pasa a R, opción de iniciar informe ── */}
        {nuevoEstado === 'R' && (
          <div className="rounded-lg border border-orange-300 bg-orange-50 p-3 text-sm text-orange-900 space-y-2">
            <div className="flex gap-2">
              <ClipboardList className="h-5 w-5 shrink-0" />
              <div>
                <strong>Recepción de equipo.</strong> Si viene devuelto del cliente en mal estado,
                genera un informe de recepción con checklist de condición + costos estimados.
                El encargado de cobros luego lo emite con PDF para cobrarle al cliente.
              </div>
            </div>
            <Button
              variant="primary"
              size="sm"
              loading={iniciarRecepcion.isPending}
              onClick={async () => {
                if (!activo) return
                try {
                  const res = await iniciarRecepcion.mutateAsync({
                    activoId: activo.id,
                    motivo: motivo.trim() || undefined,
                  })
                  onClose()
                  if (res?.informe_id) {
                    router.push(`/dashboard/flota/inspeccion-recepcion/${res.informe_id}`)
                  }
                } catch (err: unknown) {
                  setErrorMsg(err instanceof Error ? err.message : 'Error al iniciar informe')
                }
              }}
            >
              <ClipboardList className="h-4 w-4" />
              Iniciar informe de recepción
            </Button>
          </div>
        )}

        {/* ── Aviso si pasa a F estando arrendado ── */}
        {nuevoEstado === 'F' && activo.cliente_actual && (
          <div className="flex gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div>
              <strong>Atención:</strong> al pasar este equipo a Fuera de Servicio
              estando con cliente, se generará automáticamente una <em>no
              conformidad</em> que afectará el indicador de Calidad de Servicio.
            </div>
          </div>
        )}

        {/* ── Resumen del impacto ── */}
        <div className="flex gap-2 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-800">
          <ClipboardList className="h-4 w-4 shrink-0" />
          <div>
            Este cambio se registra como <strong>override manual</strong> del día
            seleccionado. El sistema NO recalculará el estado automáticamente
            sobre ese día. Para volver al cálculo automático, edite y vuelva a
            marcar el estado correcto.
          </div>
        </div>

        {errorMsg && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            {errorMsg}
          </div>
        )}
      </div>

      <ModalFooter className="-mx-6 -mb-6 mt-6">
        <Button variant="ghost" onClick={onClose} disabled={mutation.isPending}>
          Cancelar
        </Button>
        <Button
          variant="primary"
          onClick={handleSubmit}
          loading={mutation.isPending}
          disabled={fechaInvalida}
        >
          {esFuturo ? 'Programar cambio' : 'Guardar cambio'}
        </Button>
      </ModalFooter>
    </Modal>
  )
}
