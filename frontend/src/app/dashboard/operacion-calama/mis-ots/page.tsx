'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, ClipboardCheck, Calendar, MapPin, ChevronRight } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useMisOTsAsignadas } from '@/hooks/use-calama-plan-semanal'
import { useCalamaOTs } from '@/hooks/use-calama'
import { usePermissions } from '@/hooks/use-permissions'
import { Info } from 'lucide-react'
import { excelCodigoFromFolio, zonaCodeFromFolio } from '@/lib/services/calama'
import { EstadoBadge } from '@/components/calama/gantt-table'

type FiltroTiempo = 'hoy' | 'semana' | 'pendientes' | 'en_ejecucion' | 'finalizadas' | 'todas'

const FILTROS: Array<{ value: FiltroTiempo; label: string }> = [
  { value: 'hoy',          label: 'Hoy' },
  { value: 'semana',       label: 'Esta semana' },
  { value: 'pendientes',   label: 'Pendientes' },
  { value: 'en_ejecucion', label: 'En ejecucion' },
  { value: 'finalizadas',  label: 'Finalizadas' },
  { value: 'todas',        label: 'Todas' },
]

export default function MisOTsPage() {
  useRequireAuth()
  const [filtro, setFiltro] = useState<FiltroTiempo>('semana')

  const { rol } = usePermissions()
  const esAdminOPlanificador = ['administrador', 'gerencia', 'subgerente_operaciones', 'supervisor', 'planificador', 'jefe_operaciones'].includes(rol ?? '')
  const { data: planOts, isLoading } = useMisOTsAsignadas()
  // Cargar todas las OTs del usuario para tener metadata (titulo, fecha, etc).
  // El servicio filtra por responsable_id en plan_semanal_ots, pero la OT madre
  // puede no tener responsable directo. Buscamos por ids desde planOts.
  const { data: ots } = useCalamaOTs()

  const otsByid = useMemo(() => new Map((ots ?? []).map((o) => [o.id, o])), [ots])
  const hoy = new Date().toISOString().slice(0, 10)
  const inicioSemana = useMemo(() => {
    const d = new Date()
    const dow = d.getDay()
    const diff = (dow === 0 ? -6 : 1) - dow
    d.setDate(d.getDate() + diff)
    return d.toISOString().slice(0, 10)
  }, [])
  const finSemana = useMemo(() => {
    const d = new Date(inicioSemana)
    d.setDate(d.getDate() + 6)
    return d.toISOString().slice(0, 10)
  }, [inicioSemana])

  const lista = useMemo(() => {
    const result: Array<{
      planOt: typeof planOts extends (infer T)[] | null | undefined ? T : never
      ot: ReturnType<typeof otsByid.get>
    }> = []
    for (const p of planOts ?? []) {
      const ot = otsByid.get(p.ot_id)
      if (!ot) continue
      result.push({ planOt: p, ot })
    }
    return result.filter(({ ot, planOt }) => {
      if (!ot) return false
      const fecha = ot.fecha_programada ?? ''
      if (filtro === 'hoy') return fecha === hoy
      if (filtro === 'semana') return fecha >= inicioSemana && fecha <= finSemana
      if (filtro === 'pendientes') return ['planificada', 'liberada', 'asignada'].includes(planOt.estado_plan) && !['finalizada', 'cancelada'].includes(ot.estado)
      if (filtro === 'en_ejecucion') return ot.estado === 'en_ejecucion' || planOt.estado_plan === 'en_ejecucion'
      if (filtro === 'finalizadas') return ot.estado === 'finalizada'
      return true
    })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [planOts, otsByid, filtro, hoy, inicioSemana, finSemana])

  return (
    <div className="space-y-4">
      <Link
        href="/dashboard/operacion-calama"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Panel Calama
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-4 sm:p-6 text-white shadow-lg">
        <h1 className="text-xl sm:text-2xl font-bold flex items-center gap-2">
          <ClipboardCheck className="h-5 w-5 sm:h-6 sm:w-6" />
          Mis OTs Calama
        </h1>
        <p className="text-xs sm:text-sm text-white/90 mt-1">
          OTs asignadas a ti dentro del plan semanal.
        </p>
      </div>

      <div className="flex gap-2 overflow-x-auto pb-2">
        {FILTROS.map((f) => (
          <button
            key={f.value}
            onClick={() => setFiltro(f.value)}
            className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-medium border ${
              filtro === f.value
                ? 'bg-amber-600 text-white border-amber-600'
                : 'bg-white text-gray-700 border-gray-200 hover:bg-gray-50'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner className="h-4 w-4" /> Cargando…
        </div>
      )}

      {esAdminOPlanificador && (
        <Card className="border-blue-200 bg-blue-50">
          <CardContent className="p-3 text-sm text-blue-900 flex items-start gap-2">
            <Info className="h-4 w-4 mt-0.5 shrink-0" />
            <div>
              Esta vista muestra solo OTs asignadas <strong>a vos</strong>. Como{' '}
              <span className="font-mono">{rol}</span>, podes ver el listado completo en{' '}
              <Link href="/dashboard/operacion-calama/ots" className="text-blue-700 underline font-medium">
                Ordenes Calama
              </Link>{' '}
              o gestionar el plan en{' '}
              <Link href="/dashboard/operacion-calama/plan-semanal" className="text-blue-700 underline font-medium">
                Plan Semanal
              </Link>.
            </div>
          </CardContent>
        </Card>
      )}

      {lista.length === 0 ? (
        <Card>
          <CardContent className="p-6 text-center text-sm text-gray-500 space-y-2">
            <ClipboardCheck className="mx-auto h-10 w-10 text-gray-300" />
            <p>
              No tenes OTs asignadas con el filtro <strong>{FILTROS.find((f) => f.value === filtro)?.label}</strong>.
            </p>
            {esAdminOPlanificador && (
              <p className="text-xs">
                Para ver el listado completo de OTs Calama:{' '}
                <Link href="/dashboard/operacion-calama/ots" className="text-blue-700 underline">
                  /dashboard/operacion-calama/ots
                </Link>
              </p>
            )}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {lista.map(({ ot, planOt }) => {
            if (!ot) return null
            const codigo = excelCodigoFromFolio(ot.folio)
            const zona = zonaCodeFromFolio(ot.folio)
            return (
              <Link
                key={ot.id}
                href={`/dashboard/operacion-calama/mis-ots/${ot.id}`}
                className="block rounded-lg border border-gray-200 bg-white p-3 sm:p-4 shadow-sm hover:border-amber-300 active:bg-gray-50"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 text-xs text-gray-500 mb-1">
                      <span className="font-mono">{codigo}</span>
                      <EstadoBadge estado={ot.estado} />
                    </div>
                    <h3 className="font-medium text-gray-900 line-clamp-2">{ot.titulo}</h3>
                    <div className="mt-2 flex flex-wrap gap-3 text-xs text-gray-500">
                      <span className="inline-flex items-center gap-1">
                        <MapPin className="h-3 w-3" />
                        Zona {zona ?? '—'}
                      </span>
                      <span className="inline-flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        {ot.fecha_programada}
                      </span>
                      <span className="font-mono">avance {ot.avance_pct.toFixed(0)}%</span>
                      <span className="rounded bg-gray-100 px-1.5">{planOt.estado_plan}</span>
                    </div>
                  </div>
                  <ChevronRight className="h-5 w-5 text-gray-400 shrink-0 mt-1" />
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
