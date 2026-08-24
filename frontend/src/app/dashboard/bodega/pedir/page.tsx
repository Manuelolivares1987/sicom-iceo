'use client'

// ============================================================================
// Pedirle algo a bodega (MIG374)
// ----------------------------------------------------------------------------
// La entrada de oficina. Todo lo que hoy llega a bodega viene del taller —de un
// hallazgo, de una OT o del pedido manual contra una patente—. El tóner, las
// resmas y lo de aseo se piden de palabra, y bodega no tiene cómo saber quién
// pidió qué ni desde cuándo espera.
//
// NO ES UN VALE, Y ESO ES A PROPÓSITO
// El vale mueve stock del kardex contra una OT y lleva la firma del jefe de
// taller. Una resma de papel no tiene OT, y forzarle una ensuciaría el costo
// por equipo — que es justamente lo que el vale existe para cuidar. Esto es una
// SOLICITUD: bodega la tiene, la compra o la rechaza, y contesta.
//
// SIN GATE DE MÓDULO
// La página no pide el módulo de bodega: quien pide un tóner es de
// administración, de prevención o de comercial, y ninguno tiene ese permiso.
// Lo que sí necesita es sesión — un pedido sin nombre no se puede atender.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  PackageSearch, Send, Loader2, CheckCircle2, Clock, XCircle, Truck, Search, X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import {
  solicitarMaterialBodega, getMisSolicitudesBodega, type BodegaSolicitud,
} from '@/lib/services/bodega-solicitudes'
import { getEquiposParaVale, type EquipoParaVale } from '@/lib/services/bodega-tickets'
import { cn } from '@/lib/utils'

const AREAS = ['Oficina', 'Prevención', 'Taller', 'Terreno', 'Aseo y casino'] as const

const ESTADO = {
  pendiente: { t: 'Esperando', c: 'bg-amber-100 text-amber-800', i: Clock },
  atendida:  { t: 'Entregada', c: 'bg-green-100 text-green-700', i: CheckCircle2 },
  rechazada: { t: 'Rechazada', c: 'bg-gray-200 text-gray-600', i: XCircle },
} as const

export default function PedirABodegaPage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const toast = useToast()

  const [descripcion, setDescripcion] = useState('')
  const [cantidad, setCantidad] = useState('1')
  const [unidad, setUnidad] = useState('')
  const [area, setArea] = useState<string>('Oficina')
  const [observacion, setObservacion] = useState('')
  const [equipo, setEquipo] = useState<EquipoParaVale | null>(null)
  const [buscarEq, setBuscarEq] = useState('')
  const [busy, setBusy] = useState(false)

  const { data: mias = [], refetch } = useQuery({
    queryKey: ['mis-solicitudes-bodega'],
    queryFn: getMisSolicitudesBodega,
    staleTime: 15_000,
  })

  // El equipo sólo se busca si de verdad lo van a usar: la mayoría de los
  // pedidos de oficina no son para una patente.
  const { data: equipos = [] } = useQuery({
    queryKey: ['equipos-para-vale'],
    queryFn: getEquiposParaVale,
    staleTime: 300_000,
    enabled: buscarEq.trim().length > 0,
  })
  const sugerencias = useMemo(() => {
    const q = buscarEq.trim().toLowerCase()
    if (!q) return []
    return equipos.filter((e) =>
      (e.patente ?? '').toLowerCase().includes(q)
      || e.codigo.toLowerCase().includes(q)
      || (e.nombre ?? '').toLowerCase().includes(q)).slice(0, 8)
  }, [equipos, buscarEq])

  const cant = Number(String(cantidad).replace(',', '.'))
  const listo = descripcion.trim().length >= 3 && Number.isFinite(cant) && cant > 0

  const pedir = async () => {
    if (!listo) return
    setBusy(true)
    try {
      await solicitarMaterialBodega({
        descripcion: descripcion.trim(),
        cantidad: cant,
        unidad: unidad.trim() || null,
        observacion: observacion.trim() || null,
        activoId: equipo?.id ?? null,
        area,
      })
      toast.success('Pedido enviado a bodega. Queda con su nombre y con la fecha.')
      setDescripcion(''); setCantidad('1'); setUnidad(''); setObservacion('')
      setEquipo(null); setBuscarEq('')
      refetch()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo enviar el pedido')
    } finally { setBusy(false) }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6 p-6">
      <div className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-orange-600 text-white">
          <PackageSearch className="h-5 w-5" />
        </div>
        <div>
          <h1 className="text-xl font-bold text-gray-900">Pedirle algo a bodega</h1>
          <p className="text-xs text-gray-500">
            Para lo que no viene de un hallazgo ni de una orden de trabajo: útiles, tóner,
            insumos de aseo, lo que haga falta.
          </p>
        </div>
      </div>

      <Card>
        <CardContent className="space-y-4 p-5">
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">¿Qué necesita?</span>
            <Input value={descripcion} onChange={(e) => setDescripcion(e.target.value)}
                   placeholder="Tóner Brother TN-1060 negro" className="mt-1" />
          </label>

          <div className="grid grid-cols-3 gap-3">
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Cantidad</span>
              <Input value={cantidad} onChange={(e) => setCantidad(e.target.value.replace(/[^\d.,]/g, ''))}
                     inputMode="decimal" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Unidad</span>
              <Input value={unidad} onChange={(e) => setUnidad(e.target.value)}
                     placeholder="unidad, caja, litro" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">¿Para quién?</span>
              <select value={area} onChange={(e) => setArea(e.target.value)}
                      className="mt-1 h-10 w-full rounded-md border border-gray-300 px-2 text-sm">
                {AREAS.map((a) => <option key={a} value={a}>{a}</option>)}
              </select>
            </label>
          </div>

          {/* El equipo, sólo si el pedido es para una patente */}
          <div>
            <span className="text-sm font-semibold text-gray-800">
              ¿Es para un equipo? <span className="font-normal text-gray-500">— opcional</span>
            </span>
            {equipo ? (
              <div className="mt-1 flex items-center gap-3 rounded-lg border-2 border-orange-500 bg-orange-50 px-3 py-2">
                <Truck className="h-4 w-4 shrink-0 text-orange-600" />
                <span className="font-bold text-gray-800">{equipo.patente ?? equipo.codigo}</span>
                <span className="min-w-0 flex-1 truncate text-xs text-gray-500">{equipo.nombre}</span>
                <button type="button" onClick={() => setEquipo(null)} aria-label="Quitar"
                        className="shrink-0 text-orange-700"><X className="h-4 w-4" /></button>
              </div>
            ) : (
              <>
                <div className="relative mt-1">
                  <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                  <input value={buscarEq} onChange={(e) => setBuscarEq(e.target.value)}
                         placeholder="Buscar patente… (déjelo vacío si no es para un equipo)"
                         className="w-full rounded-md border border-gray-300 py-2 pl-8 pr-2 text-sm" />
                </div>
                {sugerencias.length > 0 && (
                  <div className="mt-1 max-h-40 space-y-0.5 overflow-y-auto rounded-lg border border-gray-200 p-1">
                    {sugerencias.map((e) => (
                      <button key={e.id} type="button"
                              onClick={() => { setEquipo(e); setBuscarEq('') }}
                              className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-gray-50">
                        <span className="font-bold text-gray-800">{e.patente ?? e.codigo}</span>
                        <span className="min-w-0 flex-1 truncate text-xs text-gray-500">{e.nombre}</span>
                      </button>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>

          <label className="block">
            <span className="text-sm font-semibold text-gray-800">
              Algo más que bodega deba saber <span className="font-normal text-gray-500">— opcional</span>
            </span>
            <Input value={observacion} onChange={(e) => setObservacion(e.target.value)}
                   placeholder="Para cuándo se necesita, dónde dejarlo, marca equivalente que sirve"
                   className="mt-1" />
          </label>

          <Button onClick={pedir} disabled={!listo || busy} className="w-full">
            {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Send className="mr-1.5 h-4 w-4" />}
            Enviar el pedido
          </Button>
          <p className="text-center text-[11px] text-gray-500">
            Queda con su nombre y la fecha. Bodega lo ve en «Pedidos a bodega» y contesta ahí mismo.
          </p>
        </CardContent>
      </Card>

      {/* Lo que uno mismo pidió: para no tener que llamar a preguntar */}
      <div>
        <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-gray-500">Mis pedidos</h2>
        {mias.length === 0 ? (
          <p className="rounded-lg border border-dashed border-gray-300 p-6 text-center text-sm text-gray-400">
            Todavía no ha pedido nada.
          </p>
        ) : (
          <div className="space-y-2">
            {mias.map((s: BodegaSolicitud) => {
              const e = ESTADO[s.estado] ?? ESTADO.pendiente
              const Icono = e.i
              return (
                <div key={s.id} className="flex items-center gap-3 rounded-lg border border-gray-200 bg-white p-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-gray-900">{s.descripcion}</p>
                    <p className="text-xs text-gray-500">
                      {s.cantidad}{s.unidad ? ` ${s.unidad}` : ''}
                      {s.area ? ` · ${s.area}` : ''}
                      {' · '}{new Date(s.created_at).toLocaleDateString('es-CL')}
                    </p>
                    {s.nota_bodega && (
                      <p className="mt-0.5 text-xs italic text-gray-600">Bodega: {s.nota_bodega}</p>
                    )}
                  </div>
                  <span className={cn('inline-flex shrink-0 items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold', e.c)}>
                    <Icono className="h-3.5 w-3.5" /> {e.t}
                  </span>
                </div>
              )
            })}
          </div>
        )}
      </div>

      {perfil?.nombre_completo && (
        <p className="text-center text-[11px] text-gray-400">
          Pidiendo como {perfil.nombre_completo}{perfil.cargo ? ` · ${perfil.cargo}` : ''}
        </p>
      )}
    </div>
  )
}
