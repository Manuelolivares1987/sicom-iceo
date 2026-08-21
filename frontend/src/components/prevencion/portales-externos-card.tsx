'use client'

// ============================================================================
// Los links que Prevención le entrega a un mandante (MIG308)
// ----------------------------------------------------------------------------
// Un link de estos es una credencial: quien lo tiene ve la documentación de esa
// faena. Por eso esta tarjeta muestra tres cosas y no más — a quién se le dio,
// qué alcanza a ver, y cuántas veces se usó — y deja revocarlo de una.
// El token completo no se pinta en pantalla hasta que se pide verlo.
// ============================================================================

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Link2, Copy, Check, EyeOff, Eye, Ban, Users, Truck } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'

type Portal = {
  id: string
  token: string
  nombre: string
  cliente: string | null
  faena_codigo: string | null
  activo_ids: string[] | null
  ver_archivos_personal: boolean
  activo: boolean
  expira_at: string | null
  usos: number
  last_used_at: string | null
}

function baseUrl() {
  if (typeof window !== 'undefined') return window.location.origin
  return 'https://pilladoiceo.netlify.app'
}

export function PortalesExternosCard() {
  const toast = useToast()
  const qc = useQueryClient()
  const [revelado, setRevelado] = useState<Record<string, boolean>>({})
  const [copiado, setCopiado] = useState<string | null>(null)

  const { data: portales, isLoading } = useQuery({
    queryKey: ['portales-prevencion'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('portales_prevencion')
        .select('id, token, nombre, cliente, faena_codigo, activo_ids, ver_archivos_personal, activo, expira_at, usos, last_used_at')
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Portal[]
    },
  })

  const revocar = useMutation({
    mutationFn: async ({ id, activo }: { id: string; activo: boolean }) => {
      const { error } = await supabase
        .from('portales_prevencion')
        .update({ activo, updated_at: new Date().toISOString() })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['portales-prevencion'] })
      toast.success(v.activo ? 'Link reactivado' : 'Link revocado')
    },
    onError: (e) => toast.error(errorMessage(e, 'No se pudo cambiar el link')),
  })

  const copiar = async (p: Portal) => {
    const url = `${baseUrl()}/prevencion/${p.token}/`
    try {
      await navigator.clipboard.writeText(url)
      setCopiado(p.id)
      setTimeout(() => setCopiado(null), 2000)
      toast.success('Link copiado')
    } catch {
      toast.error('No se pudo copiar. Muestre el link y cópielo a mano.')
    }
  }

  // Si nadie tiene permiso para administrar, la consulta viene vacía por RLS:
  // no se pinta una tarjeta muerta.
  if (!isLoading && (!portales || portales.length === 0)) return null

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base text-gray-700">
          <Link2 className="h-5 w-5 text-emerald-600" />
          Portales de documentación para mandantes
        </CardTitle>
        <p className="text-xs text-gray-500">
          Link de solo lectura, sin cuenta. El alcance está fijado en el link: quien lo abre no puede
          pedir otra faena ni otro equipo.
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading ? (
          <div className="flex justify-center py-6"><Spinner className="h-5 w-5" /></div>
        ) : (
          portales!.map((p) => {
            const url = `${baseUrl()}/prevencion/${p.token}/`
            const vencido = p.expira_at != null && new Date(p.expira_at) < new Date()
            return (
              <div
                key={p.id}
                className={`rounded-lg border p-3 ${p.activo && !vencido ? 'border-gray-200' : 'border-gray-200 bg-gray-50 opacity-70'}`}
              >
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-gray-900">{p.nombre}</p>
                    <p className="text-xs text-gray-500">{p.cliente ?? '—'}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    {!p.activo || vencido ? (
                      <span className="rounded-full bg-gray-200 px-2 py-0.5 text-[10px] font-bold text-gray-600">
                        {vencido ? 'VENCIDO' : 'REVOCADO'}
                      </span>
                    ) : (
                      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-bold text-emerald-700">
                        ACTIVO
                      </span>
                    )}
                  </div>
                </div>

                <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-gray-500">
                  {p.faena_codigo && (
                    <span className="inline-flex items-center gap-1">
                      <Users className="h-3.5 w-3.5" /> Personal de {p.faena_codigo}
                    </span>
                  )}
                  <span className="inline-flex items-center gap-1">
                    <Truck className="h-3.5 w-3.5" /> {p.activo_ids?.length ?? 0} equipo
                    {(p.activo_ids?.length ?? 0) === 1 ? '' : 's'}
                  </span>
                  <span>
                    {p.ver_archivos_personal ? 'Entrega respaldos de personal' : 'Sin respaldos de personal'}
                  </span>
                  <span>
                    {p.usos} consulta{p.usos === 1 ? '' : 's'}
                    {p.last_used_at ? ` · última ${new Date(p.last_used_at).toLocaleDateString('es-CL')}` : ''}
                  </span>
                </div>

                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <code className="min-w-0 flex-1 truncate rounded bg-gray-100 px-2 py-1 font-mono text-[10px] text-gray-600">
                    {revelado[p.id] ? url : `${baseUrl()}/prevencion/••••••••••••/`}
                  </code>
                  <button
                    onClick={() => setRevelado((r) => ({ ...r, [p.id]: !r[p.id] }))}
                    className="inline-flex items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[11px] font-semibold text-gray-600 hover:bg-gray-50"
                  >
                    {revelado[p.id] ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                    {revelado[p.id] ? 'Ocultar' : 'Mostrar'}
                  </button>
                  <button
                    onClick={() => copiar(p)}
                    className="inline-flex items-center gap-1 rounded-lg border border-emerald-300 bg-emerald-50 px-2 py-1 text-[11px] font-semibold text-emerald-700 hover:bg-emerald-100"
                  >
                    {copiado === p.id ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
                    Copiar link
                  </button>
                  <button
                    onClick={() => revocar.mutate({ id: p.id, activo: !p.activo })}
                    disabled={revocar.isPending}
                    className="inline-flex items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[11px] font-semibold text-gray-600 hover:bg-gray-50 disabled:opacity-50"
                  >
                    <Ban className="h-3.5 w-3.5" />
                    {p.activo ? 'Revocar' : 'Reactivar'}
                  </button>
                </div>
              </div>
            )
          })
        )}
      </CardContent>
    </Card>
  )
}
