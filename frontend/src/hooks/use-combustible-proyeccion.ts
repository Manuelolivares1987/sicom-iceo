import { useQuery } from '@tanstack/react-query'
import {
  getCombustibleProyeccion, getCombustibleDemandaDiariaEmpresa,
} from '@/lib/services/combustible-proyeccion'

const STALE = 60_000

export function useCombustibleProyeccion() {
  return useQuery({
    queryKey: ['combustible-proyeccion'],
    queryFn: () => getCombustibleProyeccion(),
    staleTime: STALE,
    refetchInterval: 5 * 60_000,
  })
}

export function useCombustibleDemandaDiariaEmpresa() {
  return useQuery({
    queryKey: ['combustible-proyeccion', 'demanda-diaria-empresa'],
    queryFn: () => getCombustibleDemandaDiariaEmpresa(),
    staleTime: STALE,
  })
}
