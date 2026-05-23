import { useQuery } from '@tanstack/react-query'
import {
  getFlotaDashboard, getFlotaKpiResumen, getFlotaAlertasResumen,
} from '@/lib/services/flota-dashboard'

const STALE = 30_000

export function useFlotaDashboard() {
  return useQuery({
    queryKey: ['flota-dashboard'],
    queryFn: () => getFlotaDashboard(),
    staleTime: STALE,
    refetchInterval: 60_000,
  })
}

export function useFlotaKpiResumen() {
  return useQuery({
    queryKey: ['flota-dashboard', 'kpi-resumen'],
    queryFn: () => getFlotaKpiResumen(),
    staleTime: STALE,
    refetchInterval: 60_000,
  })
}

export function useFlotaAlertasResumen() {
  return useQuery({
    queryKey: ['flota-dashboard', 'alertas'],
    queryFn: () => getFlotaAlertasResumen(),
    staleTime: STALE,
  })
}
