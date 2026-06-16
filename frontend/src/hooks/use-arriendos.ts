import { useQuery } from '@tanstack/react-query'
import { getHistorialArriendos, getUltimoArriendo } from '@/lib/services/arriendos'

export function useHistorialArriendos(activoId?: string) {
  return useQuery({
    queryKey: ['historial-arriendos', activoId],
    queryFn: () => getHistorialArriendos(activoId!),
    enabled: !!activoId,
  })
}

export function useUltimoArriendo(activoId?: string) {
  return useQuery({
    queryKey: ['ultimo-arriendo', activoId],
    queryFn: () => getUltimoArriendo(activoId!),
    enabled: !!activoId,
  })
}
