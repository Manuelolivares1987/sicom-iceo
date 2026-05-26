import { useQuery } from '@tanstack/react-query'
import { getComercialEquipos } from '@/lib/services/comercial-equipos'

export function useComercialEquipos(ini: string, fin: string) {
  return useQuery({
    queryKey: ['comercial-equipos', ini, fin],
    queryFn: () => getComercialEquipos(ini, fin),
    enabled: !!ini && !!fin,
    staleTime: 60_000,
  })
}
