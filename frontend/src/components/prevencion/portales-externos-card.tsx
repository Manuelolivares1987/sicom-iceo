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
import { Link2, Copy, Check, EyeOff, Eye, Ban, Users, Truck, UserCheck, Settings, Loader2 } from 'lucide-react'
import { Modal } from '@/components/ui/modal'
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
  requiere_identificacion: boolean
  emails_autorizados: string[] | null
  activo: boolean
  expira_at: string | null
  usos: number
  last_used_at: string | null
  // [MIG688] Portal del mandante: faenas SICOM, contratos ENEX y pestañas.
  faena_ids: string[] | null
  enex_faena_codigos: string[] | null
  ver_prevencion: boolean
  ver_operaciones: boolean
}

type Acceso = {
  id: string
  portal_id: string
  nombre: string
  email: string
  entrada_at: string
  ultima_vista: string
  vistas: number
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
  const [editando, setEditando] = useState<Portal | null>(null)

  const { data: portales, isLoading } = useQuery({
    queryKey: ['portales-prevencion'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('portales_prevencion')
        .select('id, token, nombre, cliente, faena_codigo, activo_ids, ver_archivos_personal, requiere_identificacion, emails_autorizados, activo, expira_at, usos, last_used_at, faena_ids, enex_faena_codigos, ver_prevencion, ver_operaciones')
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as Portal[]
    },
  })

  // Quién entró. Es la mitad del valor del portal: poder responder "Karen lo
  // vio el martes" sin depender de la memoria de nadie.
  const { data: accesos } = useQuery({
    queryKey: ['portal-prevencion-accesos'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('portal_prevencion_accesos')
        .select('id, portal_id, nombre, email, entrada_at, ultima_vista, vistas')
        .order('entrada_at', { ascending: false })
        .limit(50)
      if (error) throw error
      return (data ?? []) as Acceso[]
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
                    {p.requiere_identificacion
                      ? `Ingreso identificado · ${p.emails_autorizados?.length ?? 0} correo(s) propios`
                      : 'Sin identificación'}
                  </span>
                  <span>
                    {[p.ver_prevencion && 'Prevención', p.ver_operaciones && 'Operaciones'].filter(Boolean).join(' + ') || 'Sin pestañas'}
                    {(p.enex_faena_codigos?.length ?? 0) > 0 && ` · informes ENEX ${p.enex_faena_codigos!.join(', ')}`}
                  </span>
                  <span>
                    {p.usos} consulta{p.usos === 1 ? '' : 's'}
                    {p.last_used_at ? ` · última ${new Date(p.last_used_at).toLocaleDateString('es-CL')}` : ''}
                  </span>
                </div>

                {(() => {
                  const ingresos = (accesos ?? []).filter((x) => x.portal_id === p.id).slice(0, 4)
                  if (ingresos.length === 0) {
                    return (
                      <p className="mt-2 text-[11px] italic text-gray-400">
                        Nadie ha ingresado todavía.
                      </p>
                    )
                  }
                  return (
                    <div className="mt-2 space-y-0.5 rounded bg-gray-50 px-2 py-1.5">
                      <p className="text-[10px] font-bold uppercase tracking-wide text-gray-400">
                        Últimos ingresos
                      </p>
                      {ingresos.map((x) => (
                        <p key={x.id} className="flex items-center gap-1.5 text-[11px] text-gray-600">
                          <UserCheck className="h-3 w-3 shrink-0 text-gray-400" />
                          <span className="font-medium">{x.nombre}</span>
                          <span className="text-gray-400">{x.email}</span>
                          <span className="ml-auto shrink-0 text-gray-400">
                            {new Date(x.entrada_at).toLocaleString('es-CL', {
                              day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
                            })}
                          </span>
                        </p>
                      ))}
                    </div>
                  )
                })()}

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
                    onClick={() => setEditando(p)}
                    className="inline-flex items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[11px] font-semibold text-gray-600 hover:bg-gray-50"
                  >
                    <Settings className="h-3.5 w-3.5" /> Configurar
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
      {editando && <EditarPortal p={editando} onCerrar={() => setEditando(null)} />}
    </Card>
  )
}

// [MIG688] Configurar un portal: quién entra y qué ve. El alcance queda en la
// fila del portal (la base nunca acepta filtros desde la página pública).
function EditarPortal({ p, onCerrar }: { p: Portal; onCerrar: () => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [correos, setCorreos] = useState((p.emails_autorizados ?? []).join('\n'))
  const [faenaIds, setFaenaIds] = useState<string[]>(p.faena_ids ?? [])
  const [enex, setEnex] = useState<string[]>(p.enex_faena_codigos ?? [])
  const [verPrev, setVerPrev] = useState(p.ver_prevencion)
  const [verOps, setVerOps] = useState(p.ver_operaciones)
  const [verArchivos, setVerArchivos] = useState(p.ver_archivos_personal)

  const { data: faenas } = useQuery({
    queryKey: ['portal-cfg-faenas'],
    queryFn: async () => {
      const [{ data: tf }, { data: f }] = await Promise.all([
        supabase.from('prevencion_faena_tipos').select('faena_id'),
        supabase.from('faenas').select('id, nombre').order('nombre'),
      ])
      const con = new Set((tf ?? []).map((x: any) => x.faena_id))
      return (f ?? []).filter((x: any) => con.has(x.id) || (p.faena_ids ?? []).includes(x.id)) as { id: string, nombre: string }[]
    },
  })
  const { data: faenasEnex } = useQuery({
    queryKey: ['portal-cfg-enex'],
    queryFn: async () => {
      const { data } = await supabase.from('enex_faenas').select('codigo, nombre').eq('activo', true).order('orden')
      return (data ?? []) as { codigo: string, nombre: string }[]
    },
  })

  const guardar = useMutation({
    mutationFn: async () => {
      const lista = Array.from(new Set(correos.split(/[\s,;]+/).map((c) => c.trim().toLowerCase()).filter(Boolean)))
      const malo = lista.find((c) => !/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(c))
      if (malo) throw new Error(`Correo no válido: ${malo}`)
      const { error } = await supabase.from('portales_prevencion').update({
        emails_autorizados: lista, faena_ids: faenaIds, enex_faena_codigos: enex,
        ver_prevencion: verPrev, ver_operaciones: verOps, ver_archivos_personal: verArchivos,
        updated_at: new Date().toISOString(),
      }).eq('id', p.id)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['portales-prevencion'] })
      toast.success('Portal actualizado')
      onCerrar()
    },
    onError: (e) => toast.error(errorMessage(e, 'No se pudo guardar')),
  })

  const toggle = (arr: string[], set: (v: string[]) => void, v: string) =>
    set(arr.includes(v) ? arr.filter((x) => x !== v) : [...arr, v])

  return (
    <Modal open onClose={onCerrar} title={`Configurar · ${p.nombre}`} className="max-w-[560px]">
      <div className="space-y-4 text-sm">
        <div>
          <p className="mb-1 font-medium text-gray-700">Correos del mandante autorizados (uno por línea)</p>
          <textarea value={correos} onChange={(e) => setCorreos(e.target.value)} rows={4}
            placeholder="nombre.apellido@minera.cl"
            className="w-full rounded-lg border border-gray-300 px-3 py-2 font-mono text-xs" />
          <p className="text-[11px] text-gray-500">
            Además entran los destinatarios internos de Prevención. Cada ingreso queda registrado y dura{' '}
            {12} horas.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <label className="flex items-center gap-2"><input type="checkbox" checked={verPrev} onChange={(e) => setVerPrev(e.target.checked)} /> Pestaña Prevención</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={verOps} onChange={(e) => setVerOps(e.target.checked)} /> Pestaña Operaciones</label>
          <label className="col-span-2 flex items-center gap-2">
            <input type="checkbox" checked={verArchivos} onChange={(e) => setVerArchivos(e.target.checked)} />
            Permitir descargar respaldos de exámenes del personal (datos de salud)
          </label>
        </div>

        <div>
          <p className="mb-1 font-medium text-gray-700">Faenas: inspecciones, actividades e indicadores</p>
          <div className="flex flex-wrap gap-1.5">
            {(faenas ?? []).map((f) => (
              <button key={f.id} type="button" onClick={() => toggle(faenaIds, setFaenaIds, f.id)}
                className={`rounded-full border px-2.5 py-1 text-xs ${faenaIds.includes(f.id) ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-300 text-gray-700'}`}>
                {f.nombre}
              </button>
            ))}
          </div>
        </div>

        <div>
          <p className="mb-1 font-medium text-gray-700">Contratos ENEX: informes de calibración y mantención</p>
          <div className="flex flex-wrap gap-1.5">
            {(faenasEnex ?? []).map((f) => (
              <button key={f.codigo} type="button" onClick={() => toggle(enex, setEnex, f.codigo)}
                className={`rounded-full border px-2.5 py-1 text-xs ${enex.includes(f.codigo) ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-300 text-gray-700'}`}>
                {f.nombre}
              </button>
            ))}
          </div>
        </div>

        <div className="flex justify-end gap-2">
          <button onClick={onCerrar} className="rounded-lg border border-gray-300 px-3 py-1.5 text-xs font-semibold text-gray-600">Cancelar</button>
          <button onClick={() => guardar.mutate()} disabled={guardar.isPending}
            className="inline-flex items-center gap-1 rounded-lg bg-gray-900 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">
            {guardar.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />} Guardar
          </button>
        </div>
      </div>
    </Modal>
  )
}
