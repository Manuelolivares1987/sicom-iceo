import { useQuery } from '@tanstack/react-query'
import { getSystemStats } from '@/lib/services/admin'

export function useSystemStats() {
  return useQuery({
    queryKey: ['admin', 'system-stats'],
    queryFn: async () => {
      const { data, error } = await getSystemStats()
      if (error) throw error
      return data
    },
  })
}
