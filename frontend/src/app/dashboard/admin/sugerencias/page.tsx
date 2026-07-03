'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, Lightbulb, ExternalLink, RefreshCw, Copy, ChevronDown, ChevronUp } from 'lucide-react'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'
import {
  getSugerencias, updateSugerenciaEstado, ESTADO_SUGERENCIA_LABEL,
  type Sugerencia, type EstadoSugerencia,
} from '@/lib/services/sugerencias'

const ESTADOS: EstadoSugerencia[] = ['nueva', 'en_proceso', 'aplicada', 'descartada']

const ESTADO_CLS: Record<EstadoSugerencia, string> = {
  nueva: 'bg-amber-100 text-amber-800',
  en_proceso: 'bg-blue-100 text-blue-800',
  aplicada: 'bg-green-100 text-green-700',
  descartada: 'bg-gray-100 text-gray-500',
}

function fmt(iso: string) {
  return new Date(iso).toLocaleString('es-CL', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export default function SugerenciasPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const [filtro, setFiltro] = useState<EstadoSugerencia | ''>('')
  const [abierta, setAbierta] = useState<string | null>(null)

  const { data: sugerencias = [], isLoading, refetch, isFetching } =
    useQuery({ queryKey: ['sugerencias'], queryFn: () => getSugerencias(), staleTime: 30_000 })

  const cambiarEstado = useMutation({
    mutationFn: ({ id, estado }: { id: string; estado: EstadoSugerencia }) => updateSugerenciaEstado(id, estado),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['sugerencias'] }),
    onError: (e) => toast.error(errorMessage(e, 'No se pudo actualizar')),
  })

  const conteos = useMemo(() => {
    const c: Record<string, number> = { total: sugerencias.length, nueva: 0, en_proceso: 0, aplicada: 0, descartada: 0 }
    for (const s of sugerencias) c[s.estado] = (c[s.estado] ?? 0) + 1
    return c
  }, [sugerencias])

  const filtradas = filtro ? sugerencias.filter((s) => s.estado === filtro) : sugerencias

  const copiarPrompt = async (s: Sugerencia) => {
    try { await navigator.clipboard.writeText(s.prompt_generado ?? s.texto); toast.success('Prompt copiado') }
    catch { toast.error('No se pudo copiar') }
  }

  return (
    <div className="space-y-4 p-6">
      <header>
        <Link href="/dashboard/admin" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-800">
          <ArrowLeft className="h-4 w-4" /> Volver a Administración
        </Link>
        <div className="mt-1 flex flex-wrap items-center justify-between gap-2">
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <Lightbulb className="h-6 w-6 text-amber-500" /> Sugerencias de mejora
          </h1>
          <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw className={`h-4 w-4 mr-1 ${isFetching ? 'animate-spin' : ''}`} /> Actualizar
          </Button>
        </div>
        <p className="mt-1 text-sm text-gray-600">
          Mejoras que el equipo envía desde la 💡 (ampolleta). Revísalas y marca su estado.
        </p>
      </header>

      {/* KPIs / filtros */}
      <div className="flex flex-wrap gap-2">
        <button onClick={() => setFiltro('')}
          className={`rounded-lg border px-3 py-1.5 text-sm ${filtro === '' ? 'border-amber-500 bg-amber-50 text-amber-800' : 'border-gray-200 bg-white text-gray-600 hover:bg-gray-50'}`}>
          Todas <span className="font-bold">{conteos.total}</span>
        </button>
        {ESTADOS.map((e) => (
          <button key={e} onClick={() => setFiltro(e)}
            className={`rounded-lg border px-3 py-1.5 text-sm ${filtro === e ? 'border-amber-500 bg-amber-50 text-amber-800' : 'border-gray-200 bg-white text-gray-600 hover:bg-gray-50'}`}>
            {ESTADO_SUGERENCIA_LABEL[e]} <span className="font-bold">{conteos[e] ?? 0}</span>
          </button>
        ))}
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base text-gray-700">{filtradas.length} sugerencia(s)</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner className="h-6 w-6" /></div>
          ) : filtradas.length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">
              {sugerencias.length === 0
                ? 'Aún no hay sugerencias. Cuando el equipo use la 💡, aparecerán aquí.'
                : 'Sin sugerencias en este estado.'}
            </p>
          ) : (
            <ul className="divide-y">
              {filtradas.map((s) => {
                const open = abierta === s.id
                return (
                  <li key={s.id} className="p-3 sm:p-4">
                    <div className="flex flex-wrap items-start gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-gray-500">
                          <span className="font-medium text-gray-700">{s.usuario_nombre ?? 'Usuario'}</span>
                          {s.usuario_rol && <span className="text-gray-400">· {s.usuario_rol}</span>}
                          <span className="text-gray-400">· {fmt(s.created_at)}</span>
                          {s.contexto_url && (
                            <Link href={s.contexto_url} className="inline-flex items-center gap-0.5 text-blue-600 hover:underline">
                              <ExternalLink className="h-3 w-3" /> {s.contexto_titulo || s.contexto_url}
                            </Link>
                          )}
                        </div>
                        <p className="mt-1 text-sm text-gray-800 whitespace-pre-wrap">{s.texto}</p>

                        <div className="mt-2 flex flex-wrap items-center gap-2">
                          {s.prompt_generado && (
                            <button onClick={() => setAbierta(open ? null : s.id)}
                              className="inline-flex items-center gap-1 text-[11px] text-gray-500 hover:text-gray-700">
                              {open ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                              Prompt para Claude Code
                            </button>
                          )}
                          <button onClick={() => copiarPrompt(s)}
                            className="inline-flex items-center gap-1 text-[11px] text-gray-500 hover:text-gray-700">
                            <Copy className="h-3.5 w-3.5" /> Copiar prompt
                          </button>
                        </div>
                        {open && s.prompt_generado && (
                          <pre className="mt-2 max-h-60 overflow-auto whitespace-pre-wrap rounded-lg bg-slate-900 p-3 text-[11px] text-slate-100">{s.prompt_generado}</pre>
                        )}
                      </div>

                      <div className="flex shrink-0 flex-col items-end gap-1.5">
                        <span className={`rounded px-2 py-0.5 text-[11px] font-semibold ${ESTADO_CLS[s.estado]}`}>
                          {ESTADO_SUGERENCIA_LABEL[s.estado]}
                        </span>
                        <select
                          value={s.estado}
                          disabled={cambiarEstado.isPending}
                          onChange={(e) => cambiarEstado.mutate({ id: s.id, estado: e.target.value as EstadoSugerencia })}
                          className="h-8 rounded border border-gray-300 px-1.5 text-xs"
                        >
                          {ESTADOS.map((e) => <option key={e} value={e}>{ESTADO_SUGERENCIA_LABEL[e]}</option>)}
                        </select>
                      </div>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
