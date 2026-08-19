'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  AlertTriangle, CheckCircle2, ChevronDown, ChevronRight,
  ExternalLink, Fuel, FileWarning, Database, Truck, Wrench,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import type { Excepcion, SeveridadExcepcion } from '@/lib/services/panel-gerencia'
import { ComentarioEditor, fmtClpCorto } from './comunes'

// ============================================================================
// Requiere decisión — la agenda de la reunión (MIG305)
// ----------------------------------------------------------------------------
// Una sola lista con todo lo fuera de norma, cruzando equipos, contrato,
// combustible, taller y calidad del dato. El orden lo pone la base: severidad,
// después plata en juego, después si tiene o no plan escrito.
//
// La pregunta que responde no es "¿cómo vamos?" sino "¿qué tengo que decidir
// hoy?". Por eso lo primero que se ve de cada fila es si ya tiene dueño.
// ============================================================================

const ICONO = {
  equipo: Truck,
  contrato: FileWarning,
  combustible: Fuel,
  taller: Wrench,
  dato: Database,
} as const

const SEV_ORDEN: SeveridadExcepcion[] = ['critica', 'alta', 'media']
const SEV_LABEL: Record<SeveridadExcepcion, string> = {
  critica: 'Crítico', alta: 'Alto', media: 'Medio',
}
const SEV_BORDE: Record<SeveridadExcepcion, string> = {
  critica: 'border-l-4 border-l-red-600',
  alta:    'border-l-4 border-l-orange-500',
  media:   'border-l-4 border-l-yellow-400',
}
const CUADRANTE_LABEL: Record<string, string> = {
  coquimbo: 'Coquimbo', calama: 'Calama', global: 'Transversal',
}

function FilaExcepcion({ e, guardando, onGuardarPlan }: {
  e: Excepcion
  guardando: boolean
  onGuardarPlan: (e: Excepcion, v: {
    texto: string; planAccion: string; responsable: string; fechaCompromiso: string
  }) => void
}) {
  const [abierto, setAbierto] = useState(false)
  const Icono = ICONO[e.categoria] ?? AlertTriangle
  // Sólo las excepciones con entidad propia pueden llevar plan de acción: el
  // resto no tiene dónde guardarlo sin pisar el comentario del cuadrante.
  const planificable = Boolean(e.activo_id || e.enex_faena_id)

  return (
    <div className={`rounded-lg border bg-card ${SEV_BORDE[e.severidad]}`}>
      <div className="flex items-start gap-3 px-3 py-2">
        <Icono className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span className="font-semibold leading-tight">{e.titulo}</span>
            <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
              {CUADRANTE_LABEL[e.cuadrante] ?? e.cuadrante}
            </span>
            {e.tiene_plan ? (
              <span className="inline-flex items-center gap-1 rounded bg-emerald-100 px-1.5 py-0.5
                               text-[10px] font-semibold text-emerald-800">
                <CheckCircle2 className="h-3 w-3" /> con plan
              </span>
            ) : (
              <span className="inline-flex items-center gap-1 rounded bg-amber-100 px-1.5 py-0.5
                               text-[10px] font-semibold text-amber-800">
                <AlertTriangle className="h-3 w-3" /> sin plan
              </span>
            )}
          </div>
          <p className="mt-0.5 text-xs leading-snug text-muted-foreground">{e.detalle}</p>

          <div className="mt-1.5 flex flex-wrap items-center gap-3 text-[11px]">
            {planificable && (
              <button onClick={() => setAbierto((v) => !v)}
                className="inline-flex items-center gap-0.5 font-medium text-blue-700 underline">
                {abierto ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
                {e.tiene_plan ? 'Ver / editar plan de acción' : 'Escribir plan de acción'}
              </button>
            )}
            {e.href && (
              <Link href={e.href}
                className="inline-flex items-center gap-0.5 font-medium text-blue-700 underline">
                Ir al detalle <ExternalLink className="h-3 w-3" />
              </Link>
            )}
          </div>
        </div>

        <div className="shrink-0 text-right">
          <div className="text-lg font-bold leading-none">{e.metrica}</div>
          {e.impacto_clp != null && (
            <div className="text-[10px] text-muted-foreground">
              {fmtClpCorto(e.impacto_clp)}/mes
            </div>
          )}
          <Badge variant={e.severidad} className="mt-1">{SEV_LABEL[e.severidad]}</Badge>
        </div>
      </div>

      {abierto && planificable && (
        <div className="border-t bg-muted/30 px-3 py-2">
          <ComentarioEditor
            titulo="Plan de acción"
            comentario={null}
            conPlan
            compacto
            guardando={guardando}
            onGuardar={(v) => { onGuardarPlan(e, v); setAbierto(false) }}
          />
        </div>
      )}
    </div>
  )
}

export function PanelExcepciones({ excepciones, guardando, onGuardarPlan }: {
  excepciones: Excepcion[]
  guardando: boolean
  onGuardarPlan: (e: Excepcion, v: {
    texto: string; planAccion: string; responsable: string; fechaCompromiso: string
  }) => void
}) {
  const [cuadrante, setCuadrante] = useState<'todos' | 'coquimbo' | 'calama'>('todos')
  const [soloSinPlan, setSoloSinPlan] = useState(false)
  const [verTodo, setVerTodo] = useState(false)

  const filtradas = useMemo(() => excepciones.filter((e) =>
    (cuadrante === 'todos' || e.cuadrante === cuadrante || e.cuadrante === 'global')
    && (!soloSinPlan || !e.tiene_plan)
  ), [excepciones, cuadrante, soloSinPlan])

  const conteo = useMemo(() => {
    const c: Record<SeveridadExcepcion, number> = { critica: 0, alta: 0, media: 0 }
    for (const e of excepciones) c[e.severidad]++
    return c
  }, [excepciones])

  // Ocho filas es lo que cabe en pantalla sin scrollear en una reunión; el
  // resto queda a un clic para no esconder nada.
  const visibles = verTodo ? filtradas : filtradas.slice(0, 8)

  return (
    <Card className="border-l-4 border-l-red-600">
      <CardHeader className="pb-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <AlertTriangle className="h-4 w-4 text-red-600" />
            Requiere decisión
            <span className="text-sm font-normal text-muted-foreground">
              ({excepciones.length})
            </span>
          </CardTitle>

          <div className="flex flex-wrap items-center gap-1.5 text-[11px]">
            {SEV_ORDEN.map((s) => conteo[s] > 0 && (
              <Badge key={s} variant={s}>{conteo[s]} {SEV_LABEL[s].toLowerCase()}</Badge>
            ))}
            <span className="mx-1 h-4 w-px bg-border" />
            {(['todos', 'coquimbo', 'calama'] as const).map((c) => (
              <button key={c} onClick={() => setCuadrante(c)}
                className={`rounded px-2 py-0.5 font-medium
                  ${cuadrante === c ? 'bg-foreground text-background' : 'bg-muted text-muted-foreground'}`}>
                {c === 'todos' ? 'Todos' : CUADRANTE_LABEL[c]}
              </button>
            ))}
            <button onClick={() => setSoloSinPlan((v) => !v)}
              className={`rounded px-2 py-0.5 font-medium
                ${soloSinPlan ? 'bg-amber-500 text-white' : 'bg-muted text-muted-foreground'}`}>
              Sin plan
            </button>
          </div>
        </div>
        <p className="text-xs text-muted-foreground">
          Todo lo que está fuera de norma, ordenado por severidad y por la plata
          que hay detrás. Escribe el plan de acción aquí mismo y queda en la
          lista de compromisos.
        </p>
      </CardHeader>

      <CardContent className="space-y-2">
        {filtradas.length === 0 && (
          <div className="flex flex-col items-center gap-1 py-6 text-center">
            <CheckCircle2 className="h-6 w-6 text-emerald-600" />
            <p className="text-sm font-medium">Nada fuera de norma con este filtro.</p>
          </div>
        )}

        {visibles.map((e) => (
          <FilaExcepcion key={e.clave} e={e}
            guardando={guardando} onGuardarPlan={onGuardarPlan} />
        ))}

        {filtradas.length > visibles.length && (
          <button onClick={() => setVerTodo(true)}
            className="w-full rounded-lg border border-dashed py-2 text-xs font-medium
                       text-muted-foreground hover:bg-muted/50">
            Ver {filtradas.length - visibles.length} más
          </button>
        )}
        {verTodo && filtradas.length > 8 && (
          <button onClick={() => setVerTodo(false)}
            className="w-full rounded-lg border border-dashed py-2 text-xs font-medium
                       text-muted-foreground hover:bg-muted/50">
            Mostrar sólo las 8 primeras
          </button>
        )}
      </CardContent>
    </Card>
  )
}
