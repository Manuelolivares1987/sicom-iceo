'use client'

// ============================================================================
// /dashboard/mantencion/alertas — Listado global de alertas mantención.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  listarAlertasMantencionAbiertas,
  marcarAlertaEnRevision,
  cerrarAlertaMantencion,
  type AlertaListadoItem,
  type TipoAlertaListado,
} from '@/lib/services/mantencion-alertas'

const ROLES_MANTENCION = new Set([
  'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
  'supervisor', 'planificador', 'tecnico_mantenimiento', 'auditor',
  'jefe_mantenimiento',
])

type Filtro = 'todas' | 'rojo' | 'naranja' | 'amarillo' | 'tempranas' | 'calidad'

function severidadCls(s: AlertaListadoItem['severidad_visual']): string {
  if (s === 'rojo')     return 'border-red-300 bg-red-50 text-red-900'
  if (s === 'naranja')  return 'border-orange-300 bg-orange-50 text-orange-900'
  if (s === 'amarillo') return 'border-yellow-300 bg-yellow-50 text-yellow-900'
  return 'border-gray-300 bg-gray-50 text-gray-900'
}
function severidadDot(s: AlertaListadoItem['severidad_visual']): string {
  if (s === 'rojo')     return 'bg-red-600'
  if (s === 'naranja')  return 'bg-orange-500'
  if (s === 'amarillo') return 'bg-yellow-500'
  return 'bg-gray-400'
}
function tipoBadgeCls(t: TipoAlertaListado): string {
  return t === 'temprana'
    ? 'bg-blue-100 text-blue-800 border-blue-300'
    : 'bg-purple-100 text-purple-800 border-purple-300'
}

export default function AlertasMantencionPage() {
  const router = useRouter()
  const { perfil, loading: authLoading } = useRequireAuth()
  const queryClient = useQueryClient()
  const [filtro, setFiltro] = useState<Filtro>('todas')

  const rolValido = perfil?.rol && ROLES_MANTENCION.has(perfil.rol)

  const alertas = useQuery({
    queryKey: ['mantencion-alertas-listado'],
    queryFn: async () => {
      const r = await listarAlertasMantencionAbiertas()
      if (r.error) throw r.error
      return r.data ?? []
    },
    enabled: !!rolValido,
    refetchInterval: 60_000,
  })

  const enRevision = useMutation({
    mutationFn: async (a: AlertaListadoItem) => {
      const r = await marcarAlertaEnRevision(a.id, a.tipo)
      if (r.error) throw r.error
      return r.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mantencion-alertas-listado'] })
      queryClient.invalidateQueries({ queryKey: ['mantencion-alertas-resumen'] })
    },
  })

  const cerrar = useMutation({
    mutationFn: async (vars: { a: AlertaListadoItem; motivo: string; descartar: boolean }) => {
      const r = await cerrarAlertaMantencion(vars.a.id, vars.a.tipo, vars.motivo, vars.descartar)
      if (r.error) throw r.error
      return r.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mantencion-alertas-listado'] })
      queryClient.invalidateQueries({ queryKey: ['mantencion-alertas-resumen'] })
    },
  })

  const items = alertas.data ?? []
  const filtradas = useMemo(() => {
    if (filtro === 'todas')     return items
    if (filtro === 'tempranas') return items.filter((a) => a.tipo === 'temprana')
    if (filtro === 'calidad')   return items.filter((a) => a.tipo === 'calidad')
    return items.filter((a) => a.severidad_visual === filtro)
  }, [items, filtro])

  if (authLoading || alertas.isLoading) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  if (!rolValido) {
    return (
      <div className="rounded-lg border-2 border-red-300 bg-red-50 p-4">
        <p className="font-semibold text-red-800">Acceso denegado</p>
        <p className="text-sm text-red-700 mt-1">
          Tu rol ({perfil?.rol ?? 'sin rol'}) no tiene permisos para ver alertas de mantención.
        </p>
      </div>
    )
  }

  const counts = {
    todas: items.length,
    rojo: items.filter((a) => a.severidad_visual === 'rojo').length,
    naranja: items.filter((a) => a.severidad_visual === 'naranja').length,
    amarillo: items.filter((a) => a.severidad_visual === 'amarillo').length,
    tempranas: items.filter((a) => a.tipo === 'temprana').length,
    calidad: items.filter((a) => a.tipo === 'calidad').length,
  }

  const handleCerrar = (a: AlertaListadoItem, descartar: boolean) => {
    const motivo = window.prompt(
      descartar
        ? 'Motivo para DESCARTAR (mín. 5 caracteres):'
        : 'Motivo / acción tomada (mín. 5 caracteres):'
    )
    if (!motivo || motivo.trim().length < 5) return
    cerrar.mutate({ a, motivo, descartar })
  }

  return (
    <div className="space-y-5 max-w-6xl mx-auto">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Alertas de mantención</h1>
        <p className="text-sm text-gray-500 mt-0.5">
          Vista global de todas las alertas abiertas generadas por checklists QR.
        </p>
      </div>

      {/* Filtros */}
      <div className="flex flex-wrap gap-2">
        {([
          ['todas', 'Todas'],
          ['rojo', 'Críticas'],
          ['naranja', 'Riesgo'],
          ['amarillo', 'Atención'],
          ['tempranas', 'Técnicas'],
          ['calidad', 'Calidad'],
        ] as Array<[Filtro, string]>).map(([key, label]) => (
          <button
            key={key}
            type="button"
            onClick={() => setFiltro(key)}
            className={`rounded-full border px-3 py-1.5 text-xs font-semibold transition ${
              filtro === key
                ? 'bg-pillado-green-600 text-white border-pillado-green-600'
                : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
            }`}
          >
            {label} ({counts[key]})
          </button>
        ))}
        <button
          type="button"
          onClick={() => alertas.refetch()}
          disabled={alertas.isFetching}
          className="ml-auto rounded-md border border-gray-300 bg-white px-3 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50 disabled:opacity-50"
        >
          {alertas.isFetching ? 'Actualizando...' : 'Actualizar'}
        </button>
      </div>

      {/* Listado */}
      {filtradas.length === 0 ? (
        <div className="rounded-2xl border-2 border-pillado-green-300 bg-pillado-green-50 p-8 text-center">
          <p className="text-lg font-bold text-pillado-green-800">
            No hay alertas abiertas
          </p>
          <p className="text-sm text-pillado-green-700 mt-1">
            {filtro === 'todas'
              ? 'Toda la flota está en estado operativo según los últimos checklists.'
              : 'Sin coincidencias para este filtro.'}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {filtradas.map((a) => (
            <div
              key={`${a.tipo}-${a.id}`}
              className={`rounded-xl border-2 p-4 ${severidadCls(a.severidad_visual)}`}
            >
              <div className="flex items-start gap-3">
                <span className={`mt-1.5 h-3 w-3 shrink-0 rounded-full ${severidadDot(a.severidad_visual)}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase ${tipoBadgeCls(a.tipo)}`}>
                      {a.tipo === 'temprana' ? 'Falla técnica' : 'Calidad checklist'}
                    </span>
                    <span className="font-mono text-sm font-bold text-gray-900">
                      {a.activo_codigo}
                    </span>
                    {a.activo_nombre && (
                      <span className="text-xs text-gray-600 truncate">{a.activo_nombre}</span>
                    )}
                    <span className="text-[11px] uppercase opacity-60">{a.estado}</span>
                  </div>
                  <p className="mt-1 font-mono text-[11px] opacity-70">{a.codigo_alerta}</p>
                  <p className="mt-0.5 text-sm font-semibold">{a.descripcion}</p>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[11px] opacity-80">
                    <span>{new Date(a.created_at).toLocaleString('es-CL')}</span>
                    {a.operador && <span>Operador: {a.operador}</span>}
                    {a.score_calidad !== null && (
                      <span>Score: <strong>{a.score_calidad}/100</strong></span>
                    )}
                    {a.repeticiones_7d !== null && a.repeticiones_7d > 0 && (
                      <span>Repeticiones 7d: <strong>{a.repeticiones_7d}</strong></span>
                    )}
                  </div>
                  {a.severidad_visual === 'rojo' && (
                    <p className="mt-2 text-xs font-semibold text-red-800">
                      Falla roja: revisar equipo antes de operar.
                    </p>
                  )}
                  {a.tipo === 'calidad' && a.score_calidad !== null && a.score_calidad < 50 && (
                    <p className="mt-2 text-xs font-semibold">
                      Checklist sospechoso requiere revisión.
                    </p>
                  )}
                </div>
              </div>

              {/* Acciones */}
              <div className="mt-3 flex flex-wrap gap-2 pl-6">
                <button
                  type="button"
                  onClick={() => router.push(`/dashboard/mantencion/equipos/${a.activo_id}`)}
                  className="rounded-md bg-white px-3 py-1.5 text-xs font-semibold text-gray-800 border border-gray-300 hover:bg-gray-50"
                >
                  Ver equipo
                </button>
                {a.estado === 'abierta' && (
                  <button
                    type="button"
                    onClick={() => enRevision.mutate(a)}
                    disabled={enRevision.isPending}
                    className="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
                  >
                    Marcar en revisión
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => handleCerrar(a, false)}
                  disabled={cerrar.isPending}
                  className="rounded-md bg-pillado-green-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
                >
                  Cerrar / resolver
                </button>
                <button
                  type="button"
                  onClick={() => handleCerrar(a, true)}
                  disabled={cerrar.isPending}
                  className="rounded-md bg-gray-700 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
                >
                  Descartar
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="border-t border-gray-200 pt-4 text-xs text-gray-500">
        <Link href="/dashboard/mantencion" className="hover:underline">
          ← Volver al dashboard de mantención
        </Link>
      </div>
    </div>
  )
}
