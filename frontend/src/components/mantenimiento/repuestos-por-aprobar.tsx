'use client'

// Las solicitudes de repuestos del operador, ARRIBA de la bandeja de NC, con
// los botones para validar ahí mismo.
//
// Historia: [03-09] esto pasó a ser solo un aviso y la aprobación se movió a
// la ficha de cada NC. [21-09] Manuel lo devolvió: «cuando le pidan aprobar,
// le salga en la parte de arriba y ahí pueda validar, para que sea más
// intuitivo». Para no perder lo que se ganó en la ficha, cada pedido trae su
// contexto: equipo, OT, el hallazgo que lo motivó, las fotos y el stock en
// bodega. La ficha de la NC sigue aprobando igual (mismo RPC).
//
// Los pedidos que no cuelgan de ningún equipo (insumos del taller, con CECO)
// se siguen validando en el Plan Taller: acá solo se avisan.

import { useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, Check, Clock, Package, X } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { useToast } from '@/contexts/toast-context'
import { usePermissions } from '@/hooks/use-permissions'
import {
  getSeguimientoRecursos, validarRecurso, type OTRecursoSeguimiento,
} from '@/lib/services/ot-recursos'
import { cn } from '@/lib/utils'

function PedidoPorAprobar({ r, onListo, puede }: { r: OTRecursoSeguimiento; onListo: () => void; puede: boolean }) {
  const toast = useToast()
  const [cant, setCant] = useState(String(r.cantidad))
  const [rechazando, setRechazando] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [busy, setBusy] = useState(false)

  const espera = r.dias_desde_solicitud ?? 0
  const stock = r.producto_id ? Number(r.stock_total ?? 0) : null
  const nCant = Number(cant)

  const validar = async (accion: 'aprobar' | 'rechazar') => {
    if (accion === 'aprobar' && !(nCant > 0)) { toast.error('La cantidad debe ser mayor a 0'); return }
    if (accion === 'rechazar' && motivo.trim().length < 3) { toast.error('Escribe el motivo del rechazo'); return }
    setBusy(true)
    try {
      const res = await validarRecurso({
        recursoId: r.id, accion,
        cantidadAprobada: accion === 'aprobar' ? nCant : null,
        nota: accion === 'rechazar' ? motivo.trim() : null,
      })
      toast.success(accion === 'rechazar'
        ? 'Pedido rechazado: le llega el motivo a quien lo pidió'
        : res.ticket_folio
          ? `Aprobado · va en el vale ${res.ticket_folio}`
          : stock !== null && stock <= 0
            ? 'Aprobado · no hay stock: pasa a bodega para comprarlo'
            : 'Aprobado')
      onListo()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo validar')
    } finally { setBusy(false) }
  }

  return (
    <div className="rounded-lg border border-amber-200 bg-white p-2.5">
      <div className="flex flex-wrap items-start gap-x-3 gap-y-1">
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-gray-900">
            {r.producto_nombre ?? r.descripcion ?? 'Sin descripción'}
            {r.producto_codigo && <span className="ml-1 font-mono text-[10px] font-normal text-gray-400">{r.producto_codigo}</span>}
          </p>
          <p className="text-[11px] text-gray-600">
            <b className="font-mono text-gray-800">{r.activo_patente ?? r.activo_codigo ?? '—'}</b>
            {r.activo_nombre && <> · {r.activo_nombre}</>}
            {r.ot_folio && <> · <span className="font-mono">{r.ot_folio}</span></>}
            {' · '}lo pidió {r.solicitado_nombre ?? (r.agregado_por_jefe ? 'jefatura' : 'el operador')}
          </p>
          {r.comentario && <p className="mt-0.5 text-[11px] italic text-gray-500">«{r.comentario}»</p>}
        </div>
        <div className="flex shrink-0 items-center gap-2 text-[11px]">
          {stock === null ? (
            <span className="rounded bg-orange-100 px-1.5 py-0.5 font-medium text-orange-700">sin catálogo</span>
          ) : (
            <span className={cn('rounded px-1.5 py-0.5 font-medium',
                                stock > 0 ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-700')}>
              {stock > 0 ? `${stock} en bodega` : 'sin stock'}
            </span>
          )}
          {espera > 0 && (
            <span className={cn('inline-flex items-center gap-0.5 text-gray-500', espera >= 3 && 'font-semibold text-red-600')}>
              <Clock className="h-3 w-3" /> {espera} d
            </span>
          )}
        </div>
      </div>

      {(r.fotos?.length ?? 0) > 0 && (
        <div className="mt-1.5 flex flex-wrap gap-1">
          {(r.fotos ?? []).map((url, i) => (
            <a key={i} href={url} target="_blank" rel="noreferrer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={url} alt="foto del pedido" className="h-14 w-14 rounded border object-cover hover:opacity-80" />
            </a>
          ))}
        </div>
      )}

      {!puede ? null : rechazando ? (
        <div className="mt-2 space-y-1.5">
          <input value={motivo} onChange={(e) => setMotivo(e.target.value)} autoFocus
                 placeholder="Motivo del rechazo (lo verá quien lo pidió)"
                 className="w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          <div className="flex flex-wrap gap-1.5">
            <button type="button" disabled={busy} onClick={() => validar('rechazar')}
                    className="rounded bg-red-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">
              Confirmar rechazo
            </button>
            <button type="button" disabled={busy} onClick={() => { setRechazando(false); setMotivo('') }}
                    className="rounded border border-gray-300 bg-white px-3 py-1.5 text-xs text-gray-600">
              Volver
            </button>
          </div>
        </div>
      ) : (
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <label className="text-[11px] text-gray-500">Cantidad</label>
          <input type="number" min="0" step="any" value={cant} onChange={(e) => setCant(e.target.value)}
                 className="w-20 rounded border border-gray-300 px-1.5 py-1 text-sm" />
          <span className="text-[11px] text-gray-500">{r.unidad ?? 'un'}</span>
          <button type="button" disabled={busy} onClick={() => validar('aprobar')}
                  className="ml-auto inline-flex items-center gap-1 rounded bg-green-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-green-700 disabled:opacity-50">
            <Check className="h-3.5 w-3.5" /> Aprobar
          </button>
          <button type="button" disabled={busy} onClick={() => setRechazando(true)}
                  className="inline-flex items-center gap-1 rounded border border-red-300 bg-white px-3 py-1.5 text-xs font-semibold text-red-600 hover:bg-red-50 disabled:opacity-50">
            <X className="h-3.5 w-3.5" /> Rechazar
          </button>
        </div>
      )}
    </div>
  )
}

export function RepuestosPorAprobar({ onCambio }: { onCambio?: () => void }) {
  const qc = useQueryClient()
  // Misma regla que la ficha de la NC (puedeGestionar); el RPC valida igual.
  const { canEdit, canCreate } = usePermissions()
  const puede = canEdit('mantenimiento') || canCreate('mantenimiento')
  const { data: todos = [] } = useQuery({
    queryKey: ['recursos-por-aprobar'],
    queryFn: getSeguimientoRecursos,
    staleTime: 20_000,
  })
  const pendientes = todos.filter((r) => r.estado === 'solicitado')
  // Lo más antiguo primero: es lo que lleva más tiempo esperando al jefe.
  const deEquipo = pendientes.filter((r) => !r.es_insumo_taller)
    .sort((a, b) => (b.dias_desde_solicitud ?? 0) - (a.dias_desde_solicitud ?? 0))
  const delTaller = pendientes.filter((r) => r.es_insumo_taller)

  if (pendientes.length === 0) return null

  const listo = () => {
    qc.invalidateQueries({ queryKey: ['recursos-por-aprobar'] })
    qc.invalidateQueries({ queryKey: ['seguimiento-repuestos'] })
    qc.invalidateQueries({ queryKey: ['vale-equipos-listos'] })
    qc.invalidateQueries({ queryKey: ['nc-insumos'] })
    onCambio?.()
  }

  return (
    <Card className="border-amber-300 bg-amber-50/70">
      <CardContent className="p-3 sm:p-4">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 shrink-0 text-amber-600" />
          <h2 className="text-base font-bold text-amber-900">
            Por aprobar: {pendientes.length} pedido{pendientes.length > 1 ? 's' : ''} de repuestos
          </h2>
        </div>

        {deEquipo.length > 0 && (
          <>
            <p className="mt-1 text-xs text-amber-800">
              Revisa la foto y el stock, ajusta la cantidad si hace falta y aprueba. Con stock sale
              al vale de bodega del equipo; sin stock pasa a bodega para comprarlo.
            </p>
            <div className="mt-2 grid gap-2 lg:grid-cols-2">
              {deEquipo.map((r) => <PedidoPorAprobar key={r.id} r={r} onListo={listo} puede={puede} />)}
            </div>
          </>
        )}

        {delTaller.length > 0 && (
          <p className="mt-2 flex flex-wrap items-center gap-1 text-xs text-amber-800">
            <Package className="h-3.5 w-3.5" />
            {delTaller.length} insumo{delTaller.length > 1 ? 's' : ''} del taller (sin equipo) se validan en el
            <Link href="/dashboard/mantenimiento/plan-semanal-taller" className="font-semibold underline">Plan Taller</Link>.
          </p>
        )}
      </CardContent>
    </Card>
  )
}
