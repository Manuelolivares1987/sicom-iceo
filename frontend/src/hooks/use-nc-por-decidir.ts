import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

/**
 * Cuántas cosas esperan una decisión del jefe de taller: repuestos que el
 * operador pidió y hallazgos sin planificar.
 *
 * Va en el menú, junto a "No Conformidades". La campanita no sirve para quien
 * trabaja en terreno —no la abre—, así que el número tiene que estar donde
 * entra a trabajar.
 */
export function useNcPorDecidir() {
  return useQuery({
    queryKey: ['nc-por-decidir-conteo'],
    queryFn: async () => {
      const [repuestos, hallazgos] = await Promise.all([
        supabase.from('v_ot_recursos_seguimiento')
          .select('id', { count: 'exact', head: true }).eq('estado', 'solicitado'),
        supabase.from('no_conformidades')
          .select('id', { count: 'exact', head: true })
          .eq('estado_planificacion', 'registrada').is('plan_ot_id', null),
      ])
      return (repuestos.count ?? 0) + (hallazgos.count ?? 0)
    },
    refetchInterval: 60_000,
    staleTime: 30_000,
  })
}
