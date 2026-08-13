'use client'

// Los informes de recobro que ya se armaron pero siguen en borrador.
//
// El botón "Recobro" del equipo vuelca las NC a un informe y devuelve un link…
// que se pierde apenas se cierra el modal. Dos informes quedaron así desde
// julio: 20 hallazgos volcados, cero valorizados, nadie los vio más. Aquí
// quedan a la vista todo el tiempo, con lo que les falta para poder cobrarse.

import { useQuery } from '@tanstack/react-query'
import Link from 'next/link'
import { Receipt, ExternalLink, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { supabase } from '@/lib/supabase'

type InformeEnCurso = {
  id: string
  folio: string | null
  patente: string | null
  n_hallazgos: number | null
  n_costos: number | null
  total_cobrable_cliente: number | null
  created_at: string
}

async function getInformesEnCurso(): Promise<InformeEnCurso[]> {
  const { data, error } = await supabase
    .from('v_informes_recepcion_lista')
    .select('id, folio, patente, n_hallazgos, n_costos, total_cobrable_cliente, created_at')
    .eq('estado', 'borrador')
    .order('created_at', { ascending: true })
  if (error) throw error
  return (data ?? []) as InformeEnCurso[]
}

const dias = (iso: string) =>
  Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)

export function InformesRecobroEnCurso() {
  const { data: informes = [] } = useQuery({
    queryKey: ['informes-recobro-borrador'],
    queryFn: getInformesEnCurso,
    staleTime: 30_000,
  })

  if (informes.length === 0) return null

  return (
    <Card className="border-violet-300 bg-violet-50/60">
      <CardContent className="p-3 sm:p-4">
        <div className="mb-1 flex items-center gap-2">
          <Receipt className="h-5 w-5 shrink-0 text-violet-600" />
          <h2 className="text-base font-bold text-violet-900">
            {informes.length} informe{informes.length > 1 ? 's' : ''} de recobro sin terminar
          </h2>
        </div>
        <p className="mb-3 text-xs text-violet-800">
          Las NC ya están adentro. Falta ponerles precio para que se puedan cobrar —
          eso se hace en el informe, y después cobranza lo emite y firma.
        </p>

        <div className="grid gap-2 lg:grid-cols-2">
          {informes.map((i) => {
            const sinValorizar = !i.total_cobrable_cliente || Number(i.total_cobrable_cliente) === 0
            const espera = dias(i.created_at)
            return (
              <Link key={i.id} href={`/dashboard/flota/recepcion/${i.id}/emitir`} target="_blank"
                    className="block rounded-lg border border-violet-200 bg-white p-3 hover:bg-violet-50">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-sm font-bold text-gray-900">
                      {i.patente ?? '—'}
                      <span className="ml-1.5 text-[11px] font-normal text-muted-foreground">{i.folio ?? 'sin folio'}</span>
                    </p>
                    <p className="mt-0.5 text-xs text-gray-700">
                      {i.n_hallazgos ?? 0} hallazgo{(i.n_hallazgos ?? 0) === 1 ? '' : 's'}
                      {' · '}{i.n_costos ?? 0} ítem{(i.n_costos ?? 0) === 1 ? '' : 's'} por valorizar
                    </p>
                  </div>
                  <ExternalLink className="h-4 w-4 shrink-0 text-violet-500" />
                </div>

                {sinValorizar ? (
                  <p className="mt-1.5 inline-flex items-center gap-1 rounded bg-amber-100 px-1.5 py-0.5 text-[11px] font-semibold text-amber-800">
                    <AlertTriangle className="h-3 w-3" />
                    Sin valorizar{espera > 0 && ` · ${espera} día${espera === 1 ? '' : 's'} en borrador`}
                  </p>
                ) : (
                  <p className="mt-1.5 text-[11px] font-semibold text-emerald-700">
                    Valorizado en ${Number(i.total_cobrable_cliente).toLocaleString('es-CL')} — listo para que cobranza lo emita
                  </p>
                )}
              </Link>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}
