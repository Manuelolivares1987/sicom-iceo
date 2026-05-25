import { useQuery } from '@tanstack/react-query'
import {
  getHistorialOSLegacyByActivo, getHistorialOSLegacySinActivo,
} from '@/lib/services/historial-os-legacy'

export function useHistorialOSLegacyByActivo(activoId: string | null) {
  return useQuery({
    queryKey: ['historial-os-legacy', activoId ?? 'none'],
    enabled: !!activoId,
    queryFn: () => getHistorialOSLegacyByActivo(activoId!),
    staleTime: 5 * 60_000,
  })
}

export function useHistorialOSLegacySinActivo() {
  return useQuery({
    queryKey: ['historial-os-legacy', 'sin-activo'],
    queryFn: () => getHistorialOSLegacySinActivo(),
    staleTime: 5 * 60_000,
  })
}
