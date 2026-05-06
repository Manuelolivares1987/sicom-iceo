'use client'

import { useEffect, useMemo, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import {
  ArrowLeft, Play, Pause, RotateCcw, CheckCircle2, AlertTriangle,
  MapPin, MessageSquare, User, Coffee, Wrench, Camera, FileSignature,
  ShieldCheck, ShieldAlert, ClipboardCheck,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useCalamaOT } from '@/hooks/use-calama'
import {
  useEjecucionActivaPorOT, useMisOTsAsignadas,
} from '@/hooks/use-calama-plan-semanal'
import {
  useIniciarJornada, useRegistrarEventoJornada, useFinalizarJornada,
  useAceptarJornada, useRechazarJornada, useRegistrarLlegadaFaena,
  useFirmasJornada, useEvidenciasJornada, useRechazosJornada,
} from '@/hooks/use-calama-jornada'
import { usePermissions } from '@/hooks/use-permissions'
import { excelCodigoFromFolio, zonaCodeFromFolio } from '@/lib/services/calama'
import { tryGeolocate, genClientUuid, type GeoFix } from '@/lib/services/calama-jornada'
import { PhotoCapture, type PhotoCaptureResult } from '@/components/calama/photo-capture'
import { FirmaCapture, type FirmaCaptureResult } from '@/components/calama/firma-capture'
import { GeoStatus } from '@/components/calama/geo-status'

const MOTIVOS_PAUSA: Array<{ value: string; label: string }> = [
  { value: 'colacion',                label: 'Colacion' },
  { value: 'espera_autorizacion',     label: 'Espera autorizacion' },
  { value: 'falta_material',          label: 'Falta material' },
  { value: 'falta_herramienta',       label: 'Falta herramienta' },
  { value: 'traslado',                label: 'Traslado' },
  { value: 'clima',                   label: 'Clima' },
  { value: 'condicion_insegura',      label: 'Condicion insegura' },
  { value: 'otro',                    label: 'Otro' },
]

const TIPOS_INTERFERENCIA: Array<{ value: string; label: string }> = [
  { value: 'area_no_liberada',           label: 'Area no liberada' },
  { value: 'espera_autorizacion',        label: 'Espera autorizacion' },
  { value: 'interferencia_operacional',  label: 'Interferencia operacional' },
  { value: 'falta_permiso_ingreso',      label: 'Falta permiso ingreso' },
  { value: 'area_ocupada_mandante',      label: 'Area ocupada por mandante' },
  { value: 'cambio_prioridad_mandante',  label: 'Cambio de prioridad mandante' },
  { value: 'otro_mandante',              label: 'Otro' },
]

type Paso = 'llegada' | 'preparar' | 'ejecutar' | 'cerrar' | 'aceptacion' | 'cerrada' | 'rechazada'

export default function MobileOTDetallePage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const otId = params?.id as string | undefined
  const toast = useToast()
  const { rol } = usePermissions()
  const esMandante = ['administrador','gerencia','subgerente_operaciones','supervisor','jefe_operaciones','planificador'].includes(rol ?? '')

  const { data: ot, isLoading } = useCalamaOT(otId)
  const { data: ejecucion } = useEjecucionActivaPorOT(otId)
  // Mostrar todas las jornadas: si soy admin/planificador veo todo; si soy operador solo las mias.
  const { data: misOts } = useMisOTsAsignadas({ todas: esMandante })

  // Plan-OT activo de esta OT: la primera jornada NO cerrada/aceptada (orden secuencia).
  const planOt = useMemo(() => {
    const todas = (misOts ?? []).filter((p) => p.ot_id === otId)
    if (todas.length === 0) return null
    const activa = todas.find((p) => !['cerrada','aceptada','finalizada','no_ejecutada','reprogramada'].includes(p.estado_plan))
    return activa ?? todas[0]
  }, [misOts, otId])

  const planOtId = planOt?.id ?? null
  const planSemanalId = planOt?.plan_semanal_id ?? undefined
  const { data: firmas } = useFirmasJornada(planOtId)
  const { data: evidencias } = useEvidenciasJornada(planOtId)
  const { data: rechazos } = useRechazosJornada(planOtId)

  const iniciar  = useIniciarJornada()
  const evento   = useRegistrarEventoJornada()
  const finalizar = useFinalizarJornada()
  const aceptar  = useAceptarJornada()
  const rechazar = useRechazarJornada()
  const llegada  = useRegistrarLlegadaFaena()

  // Estado UI
  const [tickElapsed, setTickElapsed] = useState(0)
  const [avanceValor, setAvanceValor] = useState<number>(0)
  const [showMotivos, setShowMotivos] = useState(false)
  const [obsCierre, setObsCierre] = useState('')
  const [pasoForzado, setPasoForzado] = useState<Paso | null>(null)
  const [geoFix, setGeoFix] = useState<GeoFix>({ lat: null, lng: null, accuracy: null, status: 'unavailable' })

  // Interferencia mandante
  const [showInterferencia, setShowInterferencia] = useState(false)
  const [interfTipo, setInterfTipo] = useState<string>('area_no_liberada')
  const [interfObs, setInterfObs] = useState<string>('')
  const [interfQuienInforma, setInterfQuienInforma] = useState<string>('')
  const [interfFoto, setInterfFoto] = useState<PhotoCaptureResult | null>(null)

  // Capturas
  const [fotoLlegada, setFotoLlegada] = useState<PhotoCaptureResult | null>(null)
  const [obsLlegada, setObsLlegada] = useState<string>('')
  const [fotoAntes, setFotoAntes] = useState<PhotoCaptureResult | null>(null)
  const [fotoDespues, setFotoDespues] = useState<PhotoCaptureResult | null>(null)
  const [firmaOperador, setFirmaOperador] = useState<FirmaCaptureResult | null>(null)
  const [firmaMandante, setFirmaMandante] = useState<FirmaCaptureResult | null>(null)
  const [motivoRechazo, setMotivoRechazo] = useState('')
  const [requiereRehacer, setRequiereRehacer] = useState(true)
  const [fotosRechazo, setFotosRechazo] = useState<PhotoCaptureResult[]>([])
  const [firmanteNombre, setFirmanteNombre] = useState('')
  const [firmanteRut, setFirmanteRut] = useState('')

  useEffect(() => {
    if (!ejecucion || ejecucion.estado !== 'en_ejecucion') return
    const t = setInterval(() => setTickElapsed((n) => n + 1), 1000)
    return () => clearInterval(t)
  }, [ejecucion])
  useEffect(() => { setTickElapsed(0) }, [ejecucion?.last_event_at])
  useEffect(() => {
    if (ot) setAvanceValor(Math.round(Number(ot.avance_pct ?? 0)))
  }, [ot])

  // Determinar paso actual del wizard
  const planOtLlegadaAt = (planOt as { llegada_faena_at?: string | null } | null)?.llegada_faena_at ?? null
  const paso: Paso = useMemo(() => {
    if (pasoForzado) return pasoForzado
    if (!planOt) return 'llegada'
    const ep = planOt.estado_plan
    if (ep === 'cerrada' || ep === 'aceptada') return 'cerrada'
    if (ep === 'rechazada') return 'rechazada'
    if (ep === 'finalizada_operador' || ep === 'pendiente_aprobacion') return 'aceptacion'
    if (ep === 'en_ejecucion' || ep === 'pausada') return 'ejecutar'
    // Antes de preparar: si no hay llegada registrada, exigirla.
    if (!planOtLlegadaAt) return 'llegada'
    return 'preparar'
  }, [planOt, pasoForzado, planOtLlegadaAt])

  if (isLoading) {
    return <div className="flex items-center justify-center h-screen text-gray-500"><Spinner className="h-6 w-6" /></div>
  }
  if (!ot) {
    return (
      <div className="p-4 text-center">
        <p className="text-sm text-red-700">OT no encontrada o sin permisos.</p>
        <button onClick={() => router.push('/m/calama')} className="mt-3 rounded bg-amber-600 px-4 py-2 text-white text-sm">Volver</button>
      </div>
    )
  }
  // Si misOts ya cargo y NO hay jornada activa para este ot_id (puede haber sido
  // sacada del programa, anulada o cancelada por admin), bloquear ejecucion.
  if (misOts !== undefined && planOt === null && !esMandante) {
    return (
      <div className="p-4 text-center space-y-3">
        <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
        <p className="text-sm text-gray-900">
          Esta jornada fue <strong>sacada del programa</strong> y ya no esta disponible para ejecucion.
        </p>
        <p className="text-xs text-gray-500">
          Habla con tu supervisor si crees que esto es un error.
        </p>
        <button onClick={() => router.push('/m/calama')} className="rounded bg-amber-600 px-4 py-2 text-white text-sm">
          Volver a mis jornadas
        </button>
      </div>
    )
  }

  const codigo = excelCodigoFromFolio(ot.folio)
  const lugar = zonaCodeFromFolio(ot.folio)
  const avanceReal = Number(ot.avance_pct ?? 0)

  const tEfectivo = (ejecucion?.tiempo_efectivo_segundos ?? 0)
    + (ejecucion?.estado === 'en_ejecucion' ? tickElapsed : 0)
  const tPausado = (ejecucion?.tiempo_pausado_segundos ?? 0)
    + (ejecucion?.estado === 'pausada' ? tickElapsed : 0)

  // ── Handlers PRO terreno ──────────────────────────────────────────────────

  const refreshGeo = async (): Promise<GeoFix> => {
    const f = await tryGeolocate()
    setGeoFix(f)
    return f
  }

  const handleRegistrarLlegada = async () => {
    if (!planOtId) { toast.error('No hay jornada asignada a esta OT'); return }
    if (!fotoLlegada) { toast.error('Foto de llegada obligatoria'); return }
    try {
      const geo = await refreshGeo()
      await llegada.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        foto_llegada_url: fotoLlegada.url,
        foto_llegada_storage_path: fotoLlegada.storage_path,
        gps_lat: geo.lat ?? fotoLlegada.lat,
        gps_lng: geo.lng ?? fotoLlegada.lng,
        gps_accuracy: geo.accuracy,
        geolocation_status: geo.status,
        observacion: obsLlegada || undefined,
        client_uuid: genClientUuid(),
      })
      toast.success('Llegada registrada')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al registrar llegada')
    }
  }

  const handleIniciar = async () => {
    if (!planOtId) { toast.error('No hay jornada asignada a esta OT'); return }
    if (!fotoAntes) { toast.error('Foto ANTES obligatoria'); return }
    try {
      const geo = await refreshGeo()
      await iniciar.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        foto_antes_url: fotoAntes.url,
        foto_antes_storage_path: fotoAntes.storage_path,
        gps_lat: geo.lat ?? fotoAntes.lat,
        gps_lng: geo.lng ?? fotoAntes.lng,
        gps_accuracy: geo.accuracy,
        geolocation_status: geo.status,
        client_uuid_evidencia: genClientUuid(),
        client_uuid_ejecucion: genClientUuid(),
      })
      toast.success('Jornada iniciada')
      setPasoForzado(null)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al iniciar')
    }
  }

  const handlePausar = async (motivo: string) => {
    if (!planOtId) return
    setShowMotivos(false)
    try {
      const geo = await refreshGeo()
      await evento.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        tipo: 'pause', motivo,
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid: genClientUuid(),
      })
      toast.info(`Pausada: ${motivo}`)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al pausar') }
  }

  const handleReanudar = async () => {
    if (!planOtId) return
    try {
      const geo = await refreshGeo()
      await evento.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        tipo: 'resume',
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid: genClientUuid(),
      })
      toast.success('Reanudada')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al reanudar') }
  }

  const handleGuardarAvance = async () => {
    if (!planOtId) return
    try {
      const geo = await refreshGeo()
      await evento.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        tipo: 'avance', avance: avanceValor,
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid: genClientUuid(),
      })
      toast.success(`Avance: ${avanceValor}%`)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al guardar') }
  }

  const handleRegistrarInterferencia = async () => {
    if (!planOtId) return
    if (!interfObs.trim()) { toast.error('Observacion obligatoria'); return }
    try {
      const geo = await refreshGeo()
      const motivo = `interferencia_mandante:${interfTipo}`
      const comentario = [
        `Tipo: ${interfTipo}`,
        interfQuienInforma ? `Informa: ${interfQuienInforma}` : null,
        interfObs,
      ].filter(Boolean).join(' | ')
      await evento.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        tipo: 'interferencia', motivo, comentario,
        foto_url: interfFoto?.url, foto_storage_path: interfFoto?.storage_path,
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid: genClientUuid(),
      })
      toast.warning('Interferencia mandante registrada')
      setShowInterferencia(false)
      setInterfObs(''); setInterfQuienInforma(''); setInterfFoto(null)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al registrar interferencia')
    }
  }

  const handleCerrarJornada = async () => {
    if (!planOtId) return
    if (!fotoDespues) { toast.error('Foto DESPUES obligatoria'); return }
    if (!firmaOperador) { toast.error('Firma operador obligatoria'); return }
    if (avanceValor < 100 && !obsCierre.trim()) {
      toast.error('Comentario obligatorio para cierre parcial (<100%)')
      return
    }
    try {
      const geo = await refreshGeo()
      await finalizar.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        avance_final: avanceValor,
        foto_despues_url: fotoDespues.url,
        foto_despues_storage_path: fotoDespues.storage_path,
        firma_operador_url: firmaOperador.url,
        firma_operador_storage_path: firmaOperador.storage_path,
        observacion: obsCierre || undefined,
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid_foto: genClientUuid(),
        client_uuid_firma: genClientUuid(),
      })
      toast.success('Jornada cerrada — pendiente aprobacion mandante')
      setPasoForzado(null)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al cerrar')
    }
  }

  const handleAceptar = async () => {
    if (!planOtId) return
    if (!firmaMandante) { toast.error('Firma mandante obligatoria'); return }
    if (!firmanteNombre.trim()) { toast.error('Nombre del firmante obligatorio'); return }
    try {
      const geo = await refreshGeo()
      await aceptar.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        firma_mandante_url: firmaMandante.url,
        firma_mandante_storage_path: firmaMandante.storage_path,
        firmante_nombre: firmanteNombre,
        firmante_rut: firmanteRut || undefined,
        observacion: obsCierre || undefined,
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid: genClientUuid(),
      })
      toast.success('Jornada aceptada')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al aceptar')
    }
  }

  const handleRechazar = async () => {
    if (!planOtId) return
    if (!motivoRechazo.trim()) { toast.error('Motivo obligatorio'); return }
    if (!firmaMandante) { toast.error('Firma mandante obligatoria'); return }
    if (!firmanteNombre.trim()) { toast.error('Nombre del firmante obligatorio'); return }
    try {
      const geo = await refreshGeo()
      await rechazar.mutateAsync({
        plan_semanal_ot_id: planOtId,
        ot_id: ot.id,
        plan_semanal_id: planSemanalId,
        motivo: motivoRechazo,
        requiere_rehacer: requiereRehacer,
        fotos: fotosRechazo.map((f) => ({
          url: f.url, storage_path: f.storage_path, client_uuid: genClientUuid(),
        })),
        firma_mandante_url: firmaMandante.url,
        firma_mandante_storage_path: firmaMandante.storage_path,
        firmante_nombre: firmanteNombre,
        observacion: obsCierre || undefined,
        gps_lat: geo.lat, gps_lng: geo.lng, gps_accuracy: geo.accuracy, geolocation_status: geo.status,
        client_uuid_rechazo: genClientUuid(),
        client_uuid_firma: genClientUuid(),
      })
      toast.warning('Jornada rechazada — requiere correccion')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al rechazar')
    }
  }

  const handleVolverAEjecutar = () => {
    // Permite al operador volver al paso 'cerrar' tras un rechazo, sin perder el ciclo.
    setPasoForzado('cerrar')
    setFotoDespues(null); setFirmaOperador(null); setObsCierre('')
  }

  // ── Render helpers ────────────────────────────────────────────────────────

  const fotoAntesYaSubida = (evidencias ?? []).find((e) => e.momento === 'antes')
  const fotoDespuesYaSubida = (evidencias ?? []).find((e) => e.momento === 'despues')
  const firmaOperadorYaSubida = (firmas ?? []).find((f) => f.firmante_tipo === 'operador' && f.contexto === 'cierre_operador')
  const firmaMandanteYaSubida = (firmas ?? []).find((f) => f.firmante_tipo === 'mandante')
  const ultimoRechazo = (rechazos ?? [])[0]

  return (
    <div className="space-y-3">
      {/* Header sticky */}
      <header className="sticky top-0 z-30 bg-amber-700 text-white shadow-md">
        <div className="px-3 py-2.5 flex items-center gap-2">
          <button onClick={() => router.push('/m/calama')} aria-label="Volver"
            className="rounded-full p-1.5 bg-white/10 hover:bg-white/20 active:bg-white/30">
            <ArrowLeft className="h-4 w-4" />
          </button>
          <div className="flex-1 min-w-0">
            <div className="text-[10px] uppercase opacity-90 font-mono">{codigo}</div>
            <h1 className="text-sm font-bold truncate">{ot.titulo}</h1>
          </div>
          <div className="text-right">
            <div className="font-mono text-base font-bold">{avanceReal.toFixed(0)}%</div>
            <EstadoChip estado={planOt?.estado_plan ?? ot.estado} />
          </div>
        </div>
        {/* Stepper compacto + GPS badge */}
        <div className="px-3 pb-2 space-y-1">
          <Stepper paso={paso} />
          <div className="flex justify-end">
            <GeoStatus compact onChange={setGeoFix} />
          </div>
        </div>
      </header>

      {geoFix.status === 'denied' && (
        <div className="mx-3 rounded-lg border border-red-300 bg-red-50 p-2 text-xs text-red-800 flex items-start gap-2">
          <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
          <div>
            GPS denegado. Los eventos quedaran sin ubicacion (auditoria reducida).
            Activa el permiso de ubicacion en tu navegador para registrar lat/lng en cada evento.
          </div>
        </div>
      )}

      <div className="px-3 space-y-3 pb-6">
        {/* Bloque comun: lugar */}
        <Card>
          <div className="flex items-start gap-2">
            <MapPin className="h-4 w-4 text-amber-700 mt-0.5 shrink-0" />
            <div className="text-sm flex-1">
              <div className="font-mono text-xs text-gray-500">{lugar ?? '—'}</div>
              <div className="text-gray-900 font-medium">{ot.faena?.nombre ?? '—'}</div>
              <div className="text-xs text-gray-500 mt-1 flex items-center gap-2 flex-wrap">
                <span><strong>Programada:</strong> {ot.fecha_programada}</span>
                {planOt?.responsable_id && (
                  <span className="inline-flex items-center gap-1"><User className="h-3 w-3" /> Asignada</span>
                )}
              </div>
            </div>
          </div>
        </Card>

        {/* Nota planificador */}
        {planOt?.observaciones && (
          <Card extraClass="border-amber-300 bg-amber-50">
            <div className="flex items-start gap-2">
              <MessageSquare className="h-4 w-4 text-amber-700 mt-0.5 shrink-0" />
              <div className="text-sm">
                <div className="text-[10px] uppercase font-bold text-amber-800">Nota del planificador</div>
                <p className="text-amber-900 mt-0.5">{planOt.observaciones}</p>
              </div>
            </div>
          </Card>
        )}

        {/* Si hay rechazo previo, mostrarlo */}
        {ultimoRechazo && paso !== 'cerrada' && (
          <Card extraClass="border-red-300 bg-red-50">
            <div className="flex items-start gap-2">
              <ShieldAlert className="h-4 w-4 text-red-700 mt-0.5 shrink-0" />
              <div className="text-sm flex-1">
                <div className="text-[10px] uppercase font-bold text-red-800">Ultimo rechazo</div>
                <p className="text-red-900 mt-0.5">{ultimoRechazo.motivo}</p>
                {ultimoRechazo.requiere_rehacer && (
                  <p className="text-xs text-red-700 mt-1">Requiere rehacer trabajo.</p>
                )}
              </div>
            </div>
          </Card>
        )}

        {/* ===== PASO 0: LLEGADA A FAENA ===== */}
        {paso === 'llegada' && (
          <Card>
            <SectionTitle icon={<MapPin className="h-4 w-4 text-amber-700" />} title="0. Llegada a faena" />
            <p className="text-xs text-gray-600 mb-3">
              Antes de iniciar la jornada, registra tu llegada con foto y GPS. Esta foto demuestra
              tu presencia en faena (no es la foto del estado del trabajo).
            </p>
            {planOtId ? (
              <>
                <PhotoCapture
                  label="Foto LLEGADA (presencia en faena)"
                  momento="llegada"
                  otId={ot.id}
                  planOtId={planOtId}
                  onCapture={setFotoLlegada}
                  required
                />
                <textarea
                  value={obsLlegada} onChange={(e) => setObsLlegada(e.target.value)}
                  rows={2} placeholder="Observación de llegada (opcional)"
                  className="mt-3 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                />
                <div className="mt-4">
                  <BotonGrande onClick={handleRegistrarLlegada} loading={llegada.isPending}
                    variant="amber" disabled={!fotoLlegada}>
                    <MapPin className="h-5 w-5" /> Registrar llegada
                  </BotonGrande>
                </div>
              </>
            ) : (
              <p className="text-xs text-amber-700">Esta OT no tiene jornada asignada en el plan semanal.</p>
            )}
          </Card>
        )}

        {/* ===== PASO 1: PREPARAR ===== */}
        {paso === 'preparar' && (
          <Card>
            <SectionTitle icon={<ClipboardCheck className="h-4 w-4" />} title="1. Preparar jornada" />
            <p className="text-xs text-gray-600 mb-3">
              Toma una foto del area de trabajo ANTES de iniciar (estado inicial).
              Debe tomarse en terreno con GPS habilitado.
            </p>
            {planOtId ? (
              <>
                <PhotoCapture
                  label="Foto ANTES (estado inicial)"
                  momento="antes"
                  otId={ot.id}
                  planOtId={planOtId}
                  onCapture={setFotoAntes}
                  required
                />
                <div className="mt-4">
                  <BotonGrande onClick={handleIniciar} loading={iniciar.isPending} variant="green" disabled={!fotoAntes}>
                    <Play className="h-5 w-5" /> Iniciar jornada
                  </BotonGrande>
                </div>
              </>
            ) : (
              <p className="text-xs text-amber-700">Esta OT no tiene jornada asignada en el plan semanal.</p>
            )}
          </Card>
        )}

        {/* ===== PASO 2: EJECUTAR ===== */}
        {paso === 'ejecutar' && (
          <>
            <Card extraClass="border-amber-300">
              <SectionTitle icon={<Wrench className="h-4 w-4" />} title="2. Ejecutar jornada" right={
                ejecucion && (
                  <span className={`text-[10px] rounded-full px-2 py-0.5 font-bold ${
                    ejecucion.estado === 'en_ejecucion' ? 'bg-green-100 text-green-700'
                    : ejecucion.estado === 'pausada' ? 'bg-yellow-100 text-yellow-800'
                    : 'bg-gray-100 text-gray-700'
                  }`}>{ejecucion.estado.replace('_', ' ')}</span>
                )
              } />

              {ejecucion && (
                <div className="grid grid-cols-3 gap-2 mb-3 text-xs">
                  <Tiempo label="Efectivo" segundos={tEfectivo} highlight={ejecucion.estado === 'en_ejecucion'} />
                  <Tiempo label="Pausado" segundos={tPausado} highlight={ejecucion.estado === 'pausada'} />
                  <Tiempo label="Colacion" segundos={ejecucion.tiempo_colacion_segundos ?? 0} />
                </div>
              )}

              {fotoAntesYaSubida && (
                // eslint-disable-next-line @next/next/no-img-element
                <div className="mb-3"><img src={fotoAntesYaSubida.archivo_url} alt="antes" className="h-20 rounded border" /></div>
              )}

              {ejecucion?.estado === 'en_ejecucion' && (
                <div className="space-y-2">
                  <BotonGrande onClick={() => setShowMotivos((v) => !v)} variant="amber">
                    <Pause className="h-5 w-5" /> Pausar
                  </BotonGrande>
                  {showMotivos && (
                    <div className="grid grid-cols-2 gap-1.5 rounded-lg border bg-gray-50 p-2">
                      <button onClick={() => handlePausar('colacion')} disabled={evento.isPending}
                        className="col-span-2 rounded bg-yellow-100 border border-yellow-300 py-2 text-sm font-medium text-yellow-900 inline-flex items-center justify-center gap-1.5">
                        <Coffee className="h-4 w-4" /> Colacion
                      </button>
                      {MOTIVOS_PAUSA.filter((m) => m.value !== 'colacion').map((m) => (
                        <button key={m.value} onClick={() => handlePausar(m.value)} disabled={evento.isPending}
                          className="rounded border border-gray-200 bg-white py-2 px-2 text-xs">{m.label}</button>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {ejecucion?.estado === 'pausada' && (
                <BotonGrande onClick={handleReanudar} loading={evento.isPending} variant="green">
                  <RotateCcw className="h-5 w-5" /> Reanudar
                </BotonGrande>
              )}
            </Card>

            <Card>
              <SectionTitle title="Avance" />
              <div className="mb-2">
                <div className="flex items-center justify-between mb-1">
                  <label className="text-xs text-gray-600">Avance actual</label>
                  <span className="font-mono text-xl font-bold text-amber-700">{avanceValor}%</span>
                </div>
                <input
                  type="range" min={0} max={100} step={5} value={avanceValor}
                  onChange={(e) => setAvanceValor(Number(e.target.value))}
                  className="w-full h-2 accent-amber-600"
                />
                <div className="flex gap-2 mt-2">
                  {[25, 50, 75, 100].map((v) => (
                    <button key={v} onClick={() => setAvanceValor(v)}
                      className={`flex-1 rounded border py-1.5 text-xs font-medium ${
                        avanceValor === v ? 'bg-amber-600 text-white border-amber-600' : 'bg-white border-gray-200 text-gray-700'
                      }`}>{v}%</button>
                  ))}
                </div>
              </div>
              <BotonGrande onClick={handleGuardarAvance} loading={evento.isPending} variant="amber">
                Guardar avance ({avanceValor}%)
              </BotonGrande>
            </Card>

            <Card extraClass="border-orange-200">
              <SectionTitle icon={<ShieldAlert className="h-4 w-4 text-orange-700" />} title="Interferencia mandante" />
              <p className="text-xs text-gray-600 mb-2">
                Registra cualquier interferencia del mandante (área no liberada, espera autorizacion, cambio
                de prioridad, etc). Pausa la jornada y queda como evento auditable.
              </p>
              {!showInterferencia ? (
                <BotonGrande onClick={() => setShowInterferencia(true)} variant="amber">
                  <ShieldAlert className="h-5 w-5" /> Registrar interferencia
                </BotonGrande>
              ) : (
                <div className="space-y-2">
                  <select value={interfTipo} onChange={(e) => setInterfTipo(e.target.value)}
                    className="w-full rounded border border-gray-300 px-3 py-2 text-sm">
                    {TIPOS_INTERFERENCIA.map((t) => (
                      <option key={t.value} value={t.value}>{t.label}</option>
                    ))}
                  </select>
                  <input value={interfQuienInforma} onChange={(e) => setInterfQuienInforma(e.target.value)}
                    placeholder="Nombre quien informa/interfiere (opcional)"
                    className="w-full rounded border border-gray-300 px-3 py-2 text-sm" />
                  <textarea rows={2} value={interfObs} onChange={(e) => setInterfObs(e.target.value)}
                    placeholder="Observacion (obligatoria)"
                    className="w-full rounded border border-orange-300 px-3 py-2 text-sm" />
                  {planOtId && (
                    <PhotoCapture
                      label="Foto evidencia (opcional)"
                      momento="interferencia"
                      otId={ot.id}
                      planOtId={planOtId}
                      onCapture={setInterfFoto}
                    />
                  )}
                  <div className="flex gap-2">
                    <button onClick={() => { setShowInterferencia(false); setInterfObs(''); setInterfQuienInforma(''); setInterfFoto(null) }}
                      className="flex-1 rounded border border-gray-300 px-3 py-2 text-xs">Cancelar</button>
                    <button onClick={handleRegistrarInterferencia}
                      disabled={!interfObs.trim() || evento.isPending}
                      className="flex-1 rounded bg-orange-600 text-white px-3 py-2 text-xs font-bold disabled:opacity-50">
                      {evento.isPending ? 'Guardando...' : 'Registrar'}
                    </button>
                  </div>
                </div>
              )}
            </Card>

            <Card>
              <BotonGrande onClick={() => setPasoForzado('cerrar')} variant="green">
                <CheckCircle2 className="h-5 w-5" /> Cerrar jornada
              </BotonGrande>
            </Card>
          </>
        )}

        {/* ===== PASO 3: CERRAR ===== */}
        {paso === 'cerrar' && (
          <Card>
            <SectionTitle icon={<FileSignature className="h-4 w-4" />} title="3. Cerrar jornada" />
            <p className="text-xs text-gray-600 mb-3">
              Foto del estado FINAL + firma del operador. Avance final {'< 100%'} crea saldo reprogramable.
            </p>

            {planOtId && (
              <>
                <div className="mb-3">
                  <label className="text-xs text-gray-600">Avance final</label>
                  <div className="flex items-center gap-2 mt-1">
                    <input
                      type="range" min={0} max={100} step={5} value={avanceValor}
                      onChange={(e) => setAvanceValor(Number(e.target.value))}
                      className="flex-1 h-2 accent-green-600"
                    />
                    <span className="font-mono text-lg font-bold text-green-700 w-12 text-right">{avanceValor}%</span>
                  </div>
                </div>

                <div className="mb-3">
                  <PhotoCapture
                    label="Foto DESPUES (estado final)"
                    momento="despues"
                    otId={ot.id}
                    planOtId={planOtId}
                    onCapture={setFotoDespues}
                    required
                  />
                </div>

                <div className="mb-3">
                  <FirmaCapture
                    label="Firma operador"
                    contexto="cierre_operador"
                    otId={ot.id}
                    planOtId={planOtId}
                    onCapture={setFirmaOperador}
                    required
                  />
                </div>

                <textarea
                  value={obsCierre} onChange={(e) => setObsCierre(e.target.value)}
                  rows={2} placeholder="Observacion de cierre (opcional)"
                  className="w-full rounded border border-gray-300 px-3 py-2 text-sm mb-3"
                />

                <BotonGrande onClick={handleCerrarJornada} loading={finalizar.isPending} variant="green"
                  disabled={!fotoDespues || !firmaOperador}>
                  <ShieldCheck className="h-5 w-5" /> Cerrar jornada ({avanceValor}%)
                </BotonGrande>

                <button onClick={() => setPasoForzado('ejecutar')} className="mt-2 w-full text-xs text-gray-500 underline">
                  Volver a ejecucion
                </button>
              </>
            )}
          </Card>
        )}

        {/* ===== PASO 4: ACEPTACION ===== */}
        {paso === 'aceptacion' && (
          <>
            {/* Resumen para mostrar */}
            <Card>
              <SectionTitle icon={<ShieldCheck className="h-4 w-4 text-green-700" />} title="Operador finalizo — pendiente aprobacion" />
              <div className="grid grid-cols-2 gap-2 text-xs">
                {fotoAntesYaSubida && <Thumb url={fotoAntesYaSubida.archivo_url} label="Antes" />}
                {fotoDespuesYaSubida && <Thumb url={fotoDespuesYaSubida.archivo_url} label="Despues" />}
              </div>
              {firmaOperadorYaSubida && (
                // eslint-disable-next-line @next/next/no-img-element
                <div className="mt-3">
                  <div className="text-[10px] uppercase text-gray-500">Firma operador</div>
                  <img src={firmaOperadorYaSubida.firma_url} alt="firma operador" className="h-16 bg-white border rounded mt-1" />
                </div>
              )}
            </Card>

            {esMandante ? (
              <Card>
                <SectionTitle icon={<FileSignature className="h-4 w-4" />} title="4. Aceptar / Rechazar" />
                <p className="text-xs text-gray-600 mb-3">Como mandante, valida la jornada y firma.</p>

                <div className="grid grid-cols-2 gap-2 mb-3">
                  <input
                    value={firmanteNombre} onChange={(e) => setFirmanteNombre(e.target.value)}
                    placeholder="Nombre firmante *"
                    className="rounded border border-gray-300 px-2 py-1.5 text-sm"
                    required
                  />
                  <input
                    value={firmanteRut} onChange={(e) => setFirmanteRut(e.target.value)}
                    placeholder="RUT (opcional)"
                    className="rounded border border-gray-300 px-2 py-1.5 text-sm"
                  />
                </div>

                {planOtId && (
                  <div className="mb-3">
                    <FirmaCapture
                      label="Firma mandante"
                      contexto="aceptacion"
                      otId={ot.id}
                      planOtId={planOtId}
                      onCapture={setFirmaMandante}
                      required
                    />
                  </div>
                )}

                <textarea
                  value={obsCierre} onChange={(e) => setObsCierre(e.target.value)}
                  rows={2} placeholder="Observacion (opcional)"
                  className="w-full rounded border border-gray-300 px-3 py-2 text-sm mb-3"
                />

                <BotonGrande onClick={handleAceptar} loading={aceptar.isPending} variant="green" disabled={!firmaMandante}>
                  <ShieldCheck className="h-5 w-5" /> Aceptar jornada
                </BotonGrande>

                <details className="mt-4">
                  <summary className="text-sm font-medium text-red-700 cursor-pointer">o rechazar jornada</summary>
                  <div className="mt-3 space-y-3">
                    <textarea
                      value={motivoRechazo} onChange={(e) => setMotivoRechazo(e.target.value)}
                      rows={2} placeholder="Motivo del rechazo (obligatorio)"
                      className="w-full rounded border border-red-300 px-3 py-2 text-sm"
                    />
                    <label className="flex items-center gap-2 text-xs">
                      <input type="checkbox" checked={requiereRehacer} onChange={(e) => setRequiereRehacer(e.target.checked)} />
                      Requiere rehacer trabajo (cambia OT a "requiere correccion")
                    </label>
                    {planOtId && fotosRechazo.length < 3 && (
                      <PhotoCapture
                        label={`Foto evidencia rechazo (${fotosRechazo.length + 1}/3)`}
                        momento="rechazo"
                        otId={ot.id}
                        planOtId={planOtId}
                        onCapture={(r) => setFotosRechazo((prev) => [...prev, r])}
                      />
                    )}
                    {fotosRechazo.length > 0 && (
                      <div className="grid grid-cols-3 gap-1">
                        {fotosRechazo.map((f, i) => (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img key={i} src={f.url} alt={`rechazo ${i+1}`} className="h-16 w-full object-cover rounded border" />
                        ))}
                      </div>
                    )}
                    <BotonGrande onClick={handleRechazar} loading={rechazar.isPending} variant="amber"
                      disabled={!motivoRechazo.trim() || !firmaMandante}>
                      <ShieldAlert className="h-5 w-5" /> Rechazar jornada
                    </BotonGrande>
                  </div>
                </details>
              </Card>
            ) : (
              <Card extraClass="border-amber-200 bg-amber-50">
                <p className="text-sm text-amber-900">
                  Esperando aprobacion del mandante. No se requieren mas acciones del operador.
                </p>
              </Card>
            )}
          </>
        )}

        {/* ===== ESTADO RECHAZADA ===== */}
        {paso === 'rechazada' && (
          <Card extraClass="border-red-300 bg-red-50">
            <SectionTitle icon={<ShieldAlert className="h-4 w-4 text-red-700" />} title="Jornada rechazada" />
            {ultimoRechazo && (
              <div className="text-sm text-red-900 space-y-2">
                <p><strong>Motivo:</strong> {ultimoRechazo.motivo}</p>
                {ultimoRechazo.requiere_rehacer && <p>Requiere rehacer trabajo.</p>}
                {ultimoRechazo.fotos_url?.length > 0 && (
                  <div className="grid grid-cols-3 gap-1">
                    {ultimoRechazo.fotos_url.map((u, i) => (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={i} src={u} alt={`rechazo ${i+1}`} className="h-16 w-full object-cover rounded border" />
                    ))}
                  </div>
                )}
              </div>
            )}
            <div className="mt-3">
              <BotonGrande onClick={handleVolverAEjecutar} variant="amber">
                <RotateCcw className="h-5 w-5" /> Corregir y volver a cerrar
              </BotonGrande>
            </div>
          </Card>
        )}

        {/* ===== ESTADO CERRADA / ACEPTADA ===== */}
        {paso === 'cerrada' && (
          <Card extraClass="border-green-300 bg-green-50">
            <SectionTitle icon={<ShieldCheck className="h-4 w-4 text-green-700" />} title="Jornada cerrada y aceptada" />
            <div className="text-xs text-green-900 space-y-1">
              <div>Avance final: <strong>{avanceReal.toFixed(0)}%</strong></div>
              {firmaMandanteYaSubida && (
                <div className="mt-2">
                  <div className="text-[10px] uppercase text-gray-500">Firma mandante</div>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={firmaMandanteYaSubida.firma_url} alt="firma mandante" className="h-16 bg-white border rounded mt-1" />
                </div>
              )}
            </div>
          </Card>
        )}
      </div>
    </div>
  )
}

// ── UI helpers ──────────────────────────────────────────────────────────────

function Card({ children, extraClass = '' }: { children: React.ReactNode; extraClass?: string }) {
  return <div className={`rounded-xl border bg-white p-3 shadow-sm ${extraClass}`}>{children}</div>
}

function SectionTitle({ icon, title, right }: { icon?: React.ReactNode; title: string; right?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 mb-2">
      {icon}
      <h2 className="font-bold text-sm">{title}</h2>
      {right && <span className="ml-auto">{right}</span>}
    </div>
  )
}

function BotonGrande({ children, onClick, loading, disabled, variant = 'amber' }: {
  children: React.ReactNode; onClick?: () => void; loading?: boolean; disabled?: boolean
  variant?: 'amber' | 'green' | 'gray'
}) {
  const colors: Record<string, string> = {
    amber: 'bg-amber-600 hover:bg-amber-700 active:bg-amber-800',
    green: 'bg-green-600 hover:bg-green-700 active:bg-green-800',
    gray:  'bg-gray-600 hover:bg-gray-700 active:bg-gray-800',
  }
  return (
    <button onClick={onClick} disabled={loading || disabled}
      className={`w-full rounded-xl ${colors[variant]} text-white font-bold py-3 px-4 text-base inline-flex items-center justify-center gap-2 shadow-md disabled:opacity-50 disabled:cursor-not-allowed`}>
      {loading ? <Spinner className="h-4 w-4" /> : children}
    </button>
  )
}

function EstadoChip({ estado }: { estado: string }) {
  const map: Record<string, { bg: string; txt: string }> = {
    planificada:           { bg: 'bg-white/20',         txt: 'Planificada' },
    asignada:              { bg: 'bg-blue-200/30',      txt: 'Asignada' },
    liberada:              { bg: 'bg-blue-200/30',      txt: 'Liberada' },
    descargada_offline:    { bg: 'bg-blue-200/30',      txt: 'Descargada' },
    en_ejecucion:          { bg: 'bg-yellow-200/30',    txt: 'En ejecucion' },
    pausada:               { bg: 'bg-yellow-200/40',    txt: 'Pausada' },
    finalizada_operador:   { bg: 'bg-blue-200/40',      txt: 'Por aprobar' },
    pendiente_aprobacion:  { bg: 'bg-blue-200/40',      txt: 'Por aprobar' },
    aceptada:              { bg: 'bg-green-200/40',     txt: 'Aceptada' },
    cerrada:               { bg: 'bg-green-200/40',     txt: 'Cerrada' },
    rechazada:             { bg: 'bg-red-200/40',       txt: 'Rechazada' },
    requiere_correccion:   { bg: 'bg-red-200/40',       txt: 'Corregir' },
    finalizada:            { bg: 'bg-green-200/40',     txt: 'Finalizada' },
    no_ejecutada:          { bg: 'bg-red-200/40',       txt: 'No ejec.' },
    cancelada:             { bg: 'bg-gray-200/40',      txt: 'Cancelada' },
    reprogramada:          { bg: 'bg-purple-200/40',    txt: 'Reprogr.' },
  }
  const c = map[estado] ?? { bg: 'bg-white/20', txt: estado }
  return <span className={`inline-block text-[9px] uppercase font-bold rounded px-1.5 py-0.5 mt-0.5 ${c.bg}`}>{c.txt}</span>
}

function Stepper({ paso }: { paso: Paso }) {
  const steps: Array<{ key: Paso; label: string; icon: React.ReactNode }> = [
    { key: 'llegada',   label: 'Llegada',   icon: <MapPin className="h-3 w-3" /> },
    { key: 'preparar',  label: 'Preparar',  icon: <Camera className="h-3 w-3" /> },
    { key: 'ejecutar',  label: 'Ejecutar',  icon: <Wrench className="h-3 w-3" /> },
    { key: 'cerrar',    label: 'Cerrar',    icon: <FileSignature className="h-3 w-3" /> },
    { key: 'aceptacion',label: 'Aceptacion',icon: <ShieldCheck className="h-3 w-3" /> },
  ]
  const order: Paso[] = ['llegada','preparar','ejecutar','cerrar','aceptacion','cerrada']
  const idx = paso === 'rechazada' ? 3 : Math.min(order.indexOf(paso), 5)
  return (
    <div className="flex gap-1">
      {steps.map((s, i) => (
        <div key={s.key} className={`flex-1 rounded px-1 py-0.5 text-[9px] font-bold inline-flex items-center justify-center gap-0.5 ${
          i < idx ? 'bg-white/30 text-white' :
          i === idx ? 'bg-white text-amber-800' :
          'bg-white/10 text-white/50'
        }`}>
          {s.icon}<span className="hidden xs:inline">{s.label}</span>
        </div>
      ))}
    </div>
  )
}

function Thumb({ url, label }: { url: string; label: string }) {
  return (
    <div>
      <div className="text-[10px] uppercase text-gray-500 mb-0.5">{label}</div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={url} alt={label} className="w-full h-20 object-cover rounded border" />
    </div>
  )
}

function Tiempo({ label, segundos, highlight }: { label: string; segundos: number; highlight?: boolean }) {
  const h = Math.floor(segundos / 3600)
  const m = Math.floor((segundos % 3600) / 60)
  const s = segundos % 60
  const txt = `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  return (
    <div className={`rounded-lg p-2 text-center ${highlight ? 'bg-amber-100 border border-amber-300' : 'bg-gray-50 border border-gray-200'}`}>
      <div className="text-[9px] uppercase text-gray-500">{label}</div>
      <div className={`font-mono text-xs font-bold ${highlight ? 'text-amber-800' : 'text-gray-700'}`}>{txt}</div>
    </div>
  )
}
