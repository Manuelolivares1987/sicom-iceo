'use client'

// ============================================================================
// El link que bodega le pasa a la oficina (MIG376/377)
// ----------------------------------------------------------------------------
// Un link de estos es una credencial: quien lo tiene puede emitir vales contra
// los centros de costo que el link trae escritos. Por eso la tarjeta muestra lo
// que hace falta para decidir si sigue vivo —a qué carga, qué deja pedir,
// cuántas veces se usó y quién lo usó— y deja revocarlo de una.
// El token completo no se pinta hasta que se pide verlo.
// ============================================================================

import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Link2, Copy, Check, EyeOff, Eye, Ban, Wallet, Tag, Users } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'

type Portal = {
  id: string
  token: string
  nombre: string
  ceco_ids: string[] | null
  categorias: string[] | null
  activo: boolean
  expira_at: string | null
  usos: number
  last_used_at: string | null
  max_items_por_vale: number
  max_vales_por_ingreso: number
}

type Acceso = { id: string; portal_id: string; nombre: string; rut: string | null; entrada_at: string; vales: number }

const CATEGORIA_CORTA: Record<string, string> = {
  articulos_de_oficina: 'oficina',
  implementos_de_aseo_y_fungibles: 'aseo',
  implementos_de_seguridad: 'EPP',
  ferreteria: 'ferretería',
  repuesto: 'repuestos',
}

function baseUrl() {
  if (typeof window !== 'undefined') return window.location.origin
  return 'https://pilladoiceo.netlify.app'
}

export function PortalesValeCard() {
  const toast = useToast()
  const qc = useQueryClient()
  const [revelado, setRevelado] = useState<Record<string, boolean>>({})
  const [copiado, setCopiado] = useState<string | null>(null)

  const { data: portales, isLoading } = useQuery({
    queryKey: ['portales-vale'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('portales_vale_oficina')
        .select('id, token, nombre, ceco_ids, categorias, activo, expira_at, usos, last_used_at, max_items_por_vale, max_vales_por_ingreso')
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Portal[]
    },
  })

  // Quién entró por el link. Es la contracara del token: sin esto no se sabe a
  // quién se le está entregando material.
  const { data: accesos = [] } = useQuery({
    queryKey: ['portal-vale-accesos'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('portal_vale_accesos')
        .select('id, portal_id, nombre, rut, entrada_at, vales')
        .order('entrada_at', { ascending: false })
        .limit(8)
      if (error) throw error
      return (data ?? []) as Acceso[]
    },
    enabled: !!portales?.length,
  })

  const toggle = useMutation({
    mutationFn: async ({ id, activo }: { id: string; activo: boolean }) => {
      const { error } = await supabase
        .from('portales_vale_oficina')
        .update({ activo, updated_at: new Date().toISOString() })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['portales-vale'] })
      toast.success(v.activo ? 'Link reactivado' : 'Link revocado — deja de servir al instante')
    },
    onError: (e) => toast.error(errorMessage(e, 'No se pudo cambiar el link')),
  })

  const copiar = async (p: Portal) => {
    const url = `${baseUrl()}/vale-oficina/${p.token}/`
    try {
      await navigator.clipboard.writeText(url)
      setCopiado(p.id)
      setTimeout(() => setCopiado(null), 2000)
      toast.success('Link copiado')
    } catch {
      toast.error('No se pudo copiar. Muestre el link y cópielo a mano.')
    }
  }

  // Si nadie tiene permiso para administrar, RLS devuelve vacío: no se pinta
  // una tarjeta muerta.
  if (!isLoading && (!portales || portales.length === 0)) return null

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base text-gray-700">
          <Link2 className="h-5 w-5 text-orange-600" />
          Link para que oficina pida sin cuenta
        </CardTitle>
        <p className="text-xs text-gray-500">
          Se reenvía por WhatsApp. Quien lo abre dice su nombre y puede emitir un vale o pedir una
          compra. El alcance está fijado en el link: no puede cargar a otro centro de costo ni pedir
          repuestos de equipos.
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading ? (
          <div className="flex justify-center py-6"><Spinner className="h-5 w-5" /></div>
        ) : (
          portales!.map((p) => {
            const url = `${baseUrl()}/vale-oficina/${p.token}/`
            const vencido = p.expira_at != null && new Date(p.expira_at) < new Date()
            const vivo = p.activo && !vencido
            const suyos = accesos.filter((a) => a.portal_id === p.id).slice(0, 4)
            return (
              <div key={p.id}
                   className={`rounded-lg border p-3 ${vivo ? 'border-gray-200' : 'border-gray-200 bg-gray-50 opacity-70'}`}>
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-gray-900">{p.nombre}</p>
                    <p className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-500">
                      <span className="inline-flex items-center gap-1">
                        <Wallet className="h-3.5 w-3.5" />
                        {p.ceco_ids?.length ?? 0} centro{(p.ceco_ids?.length ?? 0) === 1 ? '' : 's'} de costo
                      </span>
                      <span className="inline-flex items-center gap-1">
                        <Tag className="h-3.5 w-3.5" />
                        {(p.categorias ?? []).map((c) => CATEGORIA_CORTA[c] ?? c).join(', ') || '—'}
                      </span>
                      <span>{p.usos} ingreso{p.usos === 1 ? '' : 's'}</span>
                      {p.last_used_at && (
                        <span>último {new Date(p.last_used_at).toLocaleDateString('es-CL')}</span>
                      )}
                    </p>
                  </div>
                  <div className="flex items-center gap-1.5">
                    {!vivo && (
                      <span className="rounded-full bg-gray-200 px-2 py-0.5 text-[10px] font-semibold text-gray-600">
                        {vencido ? 'Vencido' : 'Revocado'}
                      </span>
                    )}
                    <button onClick={() => setRevelado((r) => ({ ...r, [p.id]: !r[p.id] }))}
                            title={revelado[p.id] ? 'Ocultar el link' : 'Mostrar el link'}
                            className="rounded border border-gray-300 p-1.5 text-gray-500">
                      {revelado[p.id] ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                    </button>
                    <button onClick={() => copiar(p)} title="Copiar el link"
                            className="rounded border border-gray-300 p-1.5 text-gray-500">
                      {copiado === p.id ? <Check className="h-3.5 w-3.5 text-green-600" /> : <Copy className="h-3.5 w-3.5" />}
                    </button>
                    <button onClick={() => toggle.mutate({ id: p.id, activo: !p.activo })}
                            title={p.activo ? 'Revocar' : 'Reactivar'}
                            className={`rounded border p-1.5 ${p.activo
                              ? 'border-red-200 text-red-600' : 'border-green-200 text-green-700'}`}>
                      <Ban className="h-3.5 w-3.5" />
                    </button>
                  </div>
                </div>

                {revelado[p.id] && (
                  <p className="mt-2 break-all rounded bg-gray-100 p-2 font-mono text-[10px] text-gray-600">
                    {url}
                  </p>
                )}

                {suyos.length > 0 && (
                  <div className="mt-2 border-t border-gray-100 pt-2">
                    <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-wide text-gray-400">
                      <Users className="h-3 w-3" /> Quién lo ha usado
                    </p>
                    <div className="mt-1 space-y-0.5">
                      {suyos.map((a) => (
                        <p key={a.id} className="text-[11px] text-gray-600">
                          <span className="font-medium text-gray-800">{a.nombre}</span>
                          {a.rut ? ` · ${a.rut}` : ''}
                          {' · '}{new Date(a.entrada_at).toLocaleString('es-CL', {
                            day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}
                          {a.vales > 0 && ` · ${a.vales} vale${a.vales === 1 ? '' : 's'}`}
                        </p>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )
          })
        )}
      </CardContent>
    </Card>
  )
}
