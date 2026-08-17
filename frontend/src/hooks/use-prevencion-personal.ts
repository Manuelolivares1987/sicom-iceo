import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getControlDocumental,
  actualizarExamen,
  renovarExamen,
  getHistorialExamen,
  getUrlFirmadaExamen,
  enviarReporteDocumental,
  marcarNoAplica, marcarAplica, agregarExamen, eliminarExamen,
  actualizarPersona, getTiposExamen,
  type ActualizarExamenInput,
  type RenovarExamenInput,
  type EnviarReporteInput,
  type ActualizarPersonaInput,
} from '@/lib/services/prevencion-personal'

export function useControlDocumental(faena?: string | null) {
  return useQuery({
    queryKey: ['prevencion-control-documental', faena ?? 'todas'],
    queryFn: () => getControlDocumental(faena),
    // Corto: es una pantalla donde se corrige un vencimiento y se espera verlo.
    staleTime: 60_000,
  })
}

export function useActualizarExamen(faena?: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: ActualizarExamenInput) => actualizarExamen(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['prevencion-control-documental', faena ?? 'todas'] })
    },
  })
}

/** Renueva el examen subiendo el respaldo. Invalida el tablero al terminar. */
export function useRenovarExamen(faena?: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: RenovarExamenInput) => renovarExamen(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['prevencion-control-documental', faena ?? 'todas'] })
    },
  })
}

/** Versiones anteriores del examen. Solo se pide al abrir el historial. */
export function useHistorialExamen(examenId: string | null) {
  return useQuery({
    queryKey: ['prevencion-examen-historial', examenId],
    queryFn: () => getHistorialExamen(examenId!),
    enabled: !!examenId,
    staleTime: 5 * 60_000,
  })
}

/**
 * Abre el respaldo en una pestaña nueva. La URL se pide en el momento porque
 * es firmada y temporal: no se puede guardar ni cachear.
 */
export async function abrirRespaldo(path: string) {
  const url = await getUrlFirmadaExamen(path)
  if (url) window.open(url, '_blank', 'noopener,noreferrer')
  return url
}

/** Envío del reporte documental por correo, a pedido. */
export function useEnviarReporte() {
  return useMutation({
    mutationFn: (input: EnviarReporteInput) => enviarReporteDocumental(input),
  })
}

/** Catálogo de exámenes y licencias, para agregar los que falten. */
export function useTiposExamen() {
  return useQuery({
    queryKey: ['prevencion-tipos-examen'],
    queryFn: getTiposExamen,
    staleTime: 30 * 60_000,   // el catálogo casi no cambia
  })
}

/**
 * Gestión de los ítems de una persona. Todas invalidan el tablero al terminar,
 * porque cualquiera de ellas cambia el semáforo.
 */
export function useGestionExamen(faena?: string | null) {
  const qc = useQueryClient()
  const refrescar = () =>
    qc.invalidateQueries({ queryKey: ['prevencion-control-documental', faena ?? 'todas'] })

  return {
    noAplica: useMutation({
      mutationFn: (v: { examenId: string, motivo: string }) => marcarNoAplica(v.examenId, v.motivo),
      onSuccess: refrescar,
    }),
    volverAExigir: useMutation({
      mutationFn: (examenId: string) => marcarAplica(examenId),
      onSuccess: refrescar,
    }),
    agregar: useMutation({
      mutationFn: (v: { personalId: string, tipoCodigo: string }) =>
        agregarExamen(v.personalId, v.tipoCodigo),
      onSuccess: refrescar,
    }),
    eliminar: useMutation({
      mutationFn: (examenId: string) => eliminarExamen(examenId),
      onSuccess: refrescar,
    }),
  }
}

export function useActualizarPersona(faena?: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: ActualizarPersonaInput) => actualizarPersona(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['prevencion-control-documental', faena ?? 'todas'] })
    },
  })
}
