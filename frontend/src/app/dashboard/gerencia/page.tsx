'use client'

import { useMemo, useState } from 'react'
import {
  AlertTriangle, Building2, ChevronLeft, ChevronRight, MessageSquare, Printer,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  usePanelGerencia, useGuardarComentario, useEstadoCompromiso,
} from '@/hooks/use-panel-gerencia'
import type { Excepcion } from '@/lib/services/panel-gerencia'
import { ComentarioEditor, fmtFecha, iso, lunesDe } from '@/components/gerencia/comunes'
import { BandaCalidad, FranjaKpi } from '@/components/gerencia/portada'
import { PanelExcepciones } from '@/components/gerencia/excepciones'
import { PanelCompromisos } from '@/components/gerencia/compromisos'
import {
  CuadranteCalama, CuadranteCoquimbo,
} from '@/components/gerencia/detalle-cuadrantes'

// ============================================================================
// Panel de Gerencia (MIG295-297 · reordenado en MIG305)
// ----------------------------------------------------------------------------
// Se lee de arriba hacia abajo, y cada nivel responde una pregunta distinta:
//
//   1. Calidad del dato → ¿puedo creerle a lo que viene abajo?
//   2. Franja de KPI    → ¿cómo vamos, y vamos mejor o peor que el mes pasado?
//   3. Requiere decisión→ ¿qué tengo que resolver hoy?
//   4. Compromisos      → ¿qué se prometió y quién responde?
//   5. Cuadrantes       → ¿de dónde sale ese número? (colapsado)
//
// La versión anterior partía directo en el punto 5, con todo abierto y todo
// del mismo tamaño. Ese es el cambio.
// ============================================================================

export default function PanelGerenciaPage() {
  useRequireAuth()
  const [semana, setSemana] = useState(() => iso(lunesDe(new Date())))

  const { data, isLoading, error } = usePanelGerencia(semana)
  const guardar = useGuardarComentario(semana)
  const estadoCompromiso = useEstadoCompromiso(semana)

  const mueveSemana = (dias: number) => {
    const d = new Date(semana + 'T12:00:00')
    d.setDate(d.getDate() + dias)
    setSemana(iso(lunesDe(d)))
  }

  const rango = useMemo(() => {
    if (!data) return ''
    const i = new Date(data.semana.inicio + 'T12:00:00')
    const f = new Date(data.semana.fin + 'T12:00:00')
    return `${i.toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })} — ${
      f.toLocaleDateString('es-CL', { day: '2-digit', month: 'short', year: 'numeric' })}`
  }, [data])

  /**
   * El plan escrito desde una excepción se guarda contra su entidad real
   * (equipo o faena), no contra la excepción: así aparece también dentro del
   * cuadrante y en la lista de compromisos, sin duplicarse.
   */
  const guardarPlanDeExcepcion = (e: Excepcion, v: {
    texto: string; planAccion: string; responsable: string; fechaCompromiso: string
  }) => {
    const base = {
      semana,
      texto: v.texto,
      planAccion: v.planAccion,
      responsable: v.responsable,
      fechaCompromiso: v.fechaCompromiso || null,
    }
    if (e.activo_id) {
      guardar.mutate({ ...base, ambito: 'equipo', activoId: e.activo_id })
    } else if (e.enex_faena_id) {
      guardar.mutate({ ...base, ambito: 'faena_enex', enexFaenaId: e.enex_faena_id })
    }
  }

  if (error?.name === 'PanelNoAutorizadoError') {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-10 text-center">
            <AlertTriangle className="h-8 w-8 text-amber-500" />
            <p className="font-medium">No tienes permiso para ver el Panel de Gerencia.</p>
            <p className="text-sm text-muted-foreground">
              Pídele a un administrador el permiso <code>gerencia · view</code> en
              Admin → Perfiles y roles.
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-start justify-between gap-3 print:hidden">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <Building2 className="h-6 w-6 text-blue-700" />
            Panel de Gerencia
          </h1>
          <p className="text-sm text-muted-foreground">
            Semana {rango}
            {data && <> · KPI del mes al {fmtFecha(data.semana.mes_fin)}</>}
          </p>
        </div>
        <div className="flex items-center gap-1">
          <Button variant="outline" size="sm" onClick={() => mueveSemana(-7)}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Input
            type="date"
            value={semana}
            onChange={(e) => e.target.value && setSemana(iso(lunesDe(new Date(e.target.value + 'T12:00:00'))))}
            className="h-9 w-[150px]"
          />
          <Button variant="outline" size="sm" onClick={() => mueveSemana(7)}>
            <ChevronRight className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={() => setSemana(iso(lunesDe(new Date())))}>
            Hoy
          </Button>
          <Button variant="ghost" size="sm" onClick={() => window.print()} title="Imprimir / PDF">
            <Printer className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {isLoading && (
        <div className="flex justify-center py-16"><Spinner /></div>
      )}

      {error && error.name !== 'PanelNoAutorizadoError' && (
        <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
          No se pudo cargar el panel: {error.message}
        </div>
      )}

      {data && (
        <>
          {/* 1 · ¿Puedo creerle al panel? */}
          <BandaCalidad c={data.calidad_dato} />

          {/* 2 · ¿Cómo vamos? */}
          <FranjaKpi r={data.resumen} />

          {/* 3 · ¿Qué decido hoy? */}
          <PanelExcepciones
            excepciones={data.excepciones}
            guardando={guardar.isPending}
            onGuardarPlan={guardarPlanDeExcepcion}
          />

          {/* 4 · ¿Quién responde por qué? */}
          <div className="grid gap-4 lg:grid-cols-3">
            <div className="lg:col-span-2">
              <PanelCompromisos
                compromisos={data.compromisos}
                guardando={estadoCompromiso.isPending}
                onEstado={(id, estado) => estadoCompromiso.mutate({ id, estado })}
              />
            </div>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-base">
                  <MessageSquare className="h-4 w-4" />
                  Lectura de la semana
                </CardTitle>
                <p className="text-xs text-muted-foreground">
                  Lo que hay que decir de esta semana completa. Es lo que encabeza
                  el correo al Gerente General.
                </p>
              </CardHeader>
              <CardContent>
                <ComentarioEditor
                  titulo={`Semana ${rango}`}
                  comentario={data.comentario_semana}
                  compacto
                  guardando={guardar.isPending}
                  onGuardar={(v) => guardar.mutate({
                    semana, ambito: 'semana', texto: v.texto,
                  })}
                />
              </CardContent>
            </Card>
          </div>

          {/* 5 · ¿De dónde sale ese número? */}
          <div className="grid gap-4 xl:grid-cols-2">
            <CuadranteCoquimbo
              data={data}
              semana={semana}
              guardando={guardar.isPending}
              onGuardarEquipo={(activoId, v) => guardar.mutate({
                semana, ambito: 'equipo', activoId,
                texto: v.texto, planAccion: v.planAccion,
                responsable: v.responsable, fechaCompromiso: v.fechaCompromiso || null,
              })}
              onGuardarCuadrante={(v) => guardar.mutate({
                semana, ambito: 'cuadrante', cuadrante: 'coquimbo', texto: v.texto,
              })}
            />

            <CuadranteCalama
              data={data}
              guardando={guardar.isPending}
              onGuardarEquipo={(activoId, v) => guardar.mutate({
                semana, ambito: 'equipo', activoId,
                texto: v.texto, planAccion: v.planAccion,
                responsable: v.responsable, fechaCompromiso: v.fechaCompromiso || null,
              })}
              onGuardarFaena={(faenaId, v) => guardar.mutate({
                semana, ambito: 'faena_enex', enexFaenaId: faenaId,
                texto: v.texto, planAccion: v.planAccion,
                responsable: v.responsable, fechaCompromiso: v.fechaCompromiso || null,
              })}
              onGuardarCuadrante={(v) => guardar.mutate({
                semana, ambito: 'cuadrante', cuadrante: 'calama', texto: v.texto,
              })}
            />
          </div>

          <p className="text-center text-[11px] text-muted-foreground">
            Generado {new Date(data.semana.generado_at).toLocaleString('es-CL')} ·
            KPI del mes calculados del {fmtFecha(data.semana.mes_inicio)} al{' '}
            {fmtFecha(data.semana.mes_fin)} · comparación contra{' '}
            {fmtFecha(data.resumen.periodo_anterior.desde)} —{' '}
            {fmtFecha(data.resumen.periodo_anterior.hasta)} ({data.resumen.dias_comparados} días)
          </p>
        </>
      )}
    </div>
  )
}
