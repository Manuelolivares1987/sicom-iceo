import { useQuery } from '@tanstack/react-query'
import { getEventosAuditoria } from '@/lib/services/auditoria'

export function useAuditoria(filters?: Record<string, string>) {
  return useQuery({
    queryKey: ['auditoria', filters],
    queryFn: async () => {
      const { data, error } = await getEventosAuditoria(filters)
      if (error) throw error
      return data
    },
  })
}
