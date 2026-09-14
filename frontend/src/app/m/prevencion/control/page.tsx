'use client'

// ============================================================================
// Portal de prevención — control del mes (MIG547)
// ----------------------------------------------------------------------------
// La otra mitad del portal que pidió Manuel: el supervisor entra a COMPLETAR
// (/m/prevencion) y el prevencionista entra ACÁ a chequear el avance y
// generar los documentos del mes — E-200, informes y presentaciones — desde
// el teléfono o el escritorio, sin navegar el panel completo.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, FileCheck, FileWarning, Loader2, Monitor, ShieldCheck,
  Sparkles, UserX,
} from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import {
  useConsolidadoMes, useFaenasPrevencion, useMonitoreoMes, useSupervisoresFaena,
} from '@/hooks/use-prevencion-reportabilidad'
import type { ReportabilidadEstado } from '@/lib/services/prevencion-reportabilidad'
import { descargarBlob, generarEntregable } from '@/lib/entregables/prevencion-generar'

const ROLES_CONTROL = ['administrador', 'prevencionista', 'jefe_operaciones', 'subgerente_operaciones']

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

function mesActualISO(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

export default function PrevencionControlPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const toast = useToast()

  const { data: faenas } = useFaenasPrevencion()
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [periodo, setPeriodo] = useState(mesActualISO())
  const anio = Number(periodo.slice(0, 4))
  const mes = Number(periodo.slice(5, 7))
  const faenaEfectiva = faenaId ?? (faenas?.[0]?.id ?? null)
  const faenaNombre = useMemo(
    () => (faenas ?? []).find((x: any) => x.id === faenaEfectiva)?.nombre ?? '',
    [faenas, faenaEfectiva],
  )

  const { data: consolidado, isLoading } = useConsolidadoMes(faenaEfectiva, anio, mes)
  const { data: monitoreo } = useMonitoreoMes(faenaEfectiva, anio, mes)
  const { data: esperados } = useSupervisoresFaena(faenaEfectiva)

  const [generando, setGenerando] = useState<string | null>(null)
  const [progreso, setProgreso] = useState('')

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  if (!perfil?.rol || !ROLES_CONTROL.includes(perfil.rol)) {
    return (
      <div className="min-h-screen bg-gray-50 px-4 py-10">
        <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
          El control del mes es de prevención y jefaturas. Para cargar sus
          registros use <Link href="/m/prevencion" className="font-bold text-pillado-green-600 underline">el registro de terreno</Link>.
        </p>
      </div>
    )
  }

  const filas = monitoreo ?? []
  const cargaron = new Set(filas.map((m) => m.creado_por))
  const sinCargar = (esperados ?? []).filter((s) => !cargaron.has(s.usuario_id))
  const totalRegistros = filas.reduce((a, m) => a + m.total, 0)
  const entregas: ReportabilidadEstado[] = consolidado?.reportabilidad ?? []
  const entregasHechas = entregas.filter((e) => e.enviado).length
  const indicadoresOk = !!consolidado?.indicadores

  const generar = async (it: ReportabilidadEstado) => {
    if (!it.plantilla || !faenaEfectiva) return
    setGenerando(it.item_id)
    setProgreso('Preparando…')
    try {
      const { blob, filename } = await generarEntregable({
        plantilla: it.plantilla, itemNombre: it.nombre,
        faenaId: faenaEfectiva, faenaNombre, anio, mes,
        onProgreso: setProgreso,
      })
      descargarBlob(blob, filename)
      toast.success(`${filename} generado`)
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo generar')
    } finally {
      setGenerando(null)
      setProgreso('')
    }
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <header className="border-b border-gray-200 bg-white px-4 pb-4 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-2">
          <Link href="/m/prevencion" className="text-gray-400"><ArrowLeft className="h-5 w-5" /></Link>
          <div>
            <p className="flex items-center gap-2 text-lg font-bold leading-tight text-gray-900">
              <ShieldCheck className="h-5 w-5 text-pillado-green-500" />
              Control del mes
            </p>
            <p className="text-xs text-gray-500">Avance, faltantes y documentos por faena</p>
          </div>
        </div>
        <div className="mt-3 flex gap-2">
          <div className="flex-1">
            <Select value={faenaEfectiva ?? ''} onChange={(e) => setFaenaId(e.target.value)}
                    options={(faenas ?? []).map((x: any) => ({ value: x.id, label: x.nombre }))} />
          </div>
          <Input type="month" className="w-40" value={periodo}
                 onChange={(e) => e.target.value && setPeriodo(e.target.value)} />
        </div>
      </header>

      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner className="h-8 w-8" /></div>
      ) : (
        <main className="space-y-4 px-4 py-4">
          {/* KPIs del mes */}
          <div className="grid grid-cols-2 gap-2">
            <MiniKpi label="Registros" valor={String(totalRegistros)} />
            <MiniKpi label="Supervisores"
                     valor={`${cargaron.size}${esperados?.length ? ` / ${esperados.length}` : ''}`}
                     alerta={!!esperados?.length && cargaron.size < esperados.length} />
            <MiniKpi label="Indicadores" valor={indicadoresOk ? 'Cargados' : 'Faltan'} alerta={!indicadoresOk} />
            <MiniKpi label="Entregas" valor={`${entregasHechas} / ${entregas.length}`}
                     alerta={entregas.length > 0 && entregasHechas < entregas.length} />
          </div>

          {/* Quién cargó / quién falta */}
          <section className="rounded-xl border border-gray-200 bg-white p-3">
            <p className="mb-2 text-sm font-bold text-gray-700">
              Carga por supervisor — {MESES[mes - 1]}
            </p>
            {filas.length === 0 && (
              <p className="py-2 text-sm text-gray-500">Nadie ha cargado este mes.</p>
            )}
            <ul className="space-y-1.5">
              {filas.map((m) => (
                <li key={m.creado_por} className="flex items-center justify-between gap-2 text-sm">
                  <span className="min-w-0 flex-1 truncate font-medium">{m.supervisor}</span>
                  <span className="flex flex-wrap justify-end gap-1">
                    {Object.entries(m.por_tipo ?? {}).map(([t, n]) => (
                      <span key={t} className="rounded bg-gray-100 px-1.5 py-0.5 text-[11px]">
                        {t}: <b>{n as number}</b>
                      </span>
                    ))}
                    {m.abiertos > 0 && (
                      <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[11px] font-bold text-amber-700">
                        {m.abiertos} abiertos
                      </span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
            {sinCargar.length > 0 && (
              <div className="mt-2 rounded-lg border border-red-200 bg-red-50 p-2">
                <p className="flex items-center gap-1 text-xs font-bold text-red-700">
                  <UserX className="h-3.5 w-3.5" /> Sin cargas: {sinCargar.map((s) => s.nombre).join(', ')}
                </p>
              </div>
            )}
          </section>

          {/* Entregas + generación */}
          <section className="rounded-xl border border-gray-200 bg-white p-3">
            <p className="mb-2 text-sm font-bold text-gray-700">
              Documentos del mes
            </p>
            <ul className="space-y-2">
              {entregas.map((it) => (
                <li key={it.item_id}
                    className={cn(
                      'rounded-lg border p-2.5',
                      it.enviado ? 'border-green-200 bg-green-50' : 'border-gray-200',
                    )}>
                  <div className="flex items-center gap-2">
                    {it.enviado
                      ? <FileCheck className="h-4 w-4 shrink-0 text-green-600" />
                      : <FileWarning className="h-4 w-4 shrink-0 text-amber-500" />}
                    <p className="min-w-0 flex-1 truncate text-sm font-medium">{it.nombre}</p>
                    {it.enviado && <span className="text-[11px] font-bold text-green-700">enviada</span>}
                  </div>
                  {it.plantilla && (
                    <Button size="sm" variant="outline" className="mt-1.5 w-full"
                            disabled={generando !== null}
                            onClick={() => generar(it)}>
                      {generando === it.item_id
                        ? <Loader2 className="mr-1 h-4 w-4 animate-spin" />
                        : <Sparkles className="mr-1 h-4 w-4" />}
                      {generando === it.item_id ? (progreso || 'Generando…') : 'Generar documento'}
                    </Button>
                  )}
                </li>
              ))}
              {entregas.length === 0 && (
                <p className="py-2 text-sm text-gray-500">Esta faena no tiene reportabilidad configurada.</p>
              )}
            </ul>
            <p className="mt-2 text-xs text-gray-500">
              Marcar la entrega (con el respaldo) se hace en el panel completo.
            </p>
          </section>

          <Link href="/dashboard/prevencion/reportabilidad"
                className="flex items-center justify-center gap-2 rounded-xl border-2 border-gray-200 bg-white p-3 text-sm font-bold text-gray-700">
            <Monitor className="h-4 w-4" /> Abrir el panel completo
          </Link>
        </main>
      )}
    </div>
  )
}

function MiniKpi({ label, valor, alerta }: { label: string; valor: string; alerta?: boolean }) {
  return (
    <div className={cn(
      'rounded-xl border p-3',
      alerta ? 'border-red-200 bg-red-50' : 'border-gray-200 bg-white',
    )}>
      <p className="text-[11px] uppercase text-gray-500">{label}</p>
      <p className={cn('text-lg font-bold', alerta ? 'text-red-700' : 'text-gray-900')}>{valor}</p>
    </div>
  )
}
