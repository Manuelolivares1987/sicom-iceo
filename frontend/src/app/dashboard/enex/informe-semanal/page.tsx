'use client'

// Informe semanal de cumplimiento a ENEX (MIG679): SICOM arma el borrador, una
// persona revisa y edita las observaciones, y recién ahí se envía.

import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, ChevronLeft, ChevronRight, Loader2, Send } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { supabase } from '@/lib/supabase'
import { sumarDias, trimestreContrato } from '@/lib/enex-avance'
import {
  armarInformeSemanal, fechaCorta, hoyIso, lunesSemanaAnterior, mesesNecesarios, numeroSemana, type InformeSemanal, type PautaLugarFaena,
} from '@/lib/enex-informe-semanal'
import { htmlInformeSemanal } from '@/lib/email/enex-informe-semanal'
import {
  getActividadesTrimestre, getEnviosInformeSemanal, getFaenas, getFaenasConLugares, getHallazgosDeEjecuciones, getLugarItems,
  getPanelVentana, getReprogramacionesDesde, sincronizarTrimestre,
} from '@/lib/services/enex'

const separar = (s: string) => s.split(/[,;\n]/).map((x) => x.trim()).filter(Boolean)
const EMAIL = /^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/

export default function InformeSemanalPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const [hoy, setHoy] = useState('')
  const [lunes, setLunes] = useState('')
  const [comentario, setComentario] = useState('')
  const [textos, setTextos] = useState<Record<string, string>>({})
  const [excluidas, setExcluidas] = useState<Set<string>>(new Set())
  const [para, setPara] = useState('')
  const [copia, setCopia] = useState('')
  const [confirmar, setConfirmar] = useState(false)
  const [enviando, setEnviando] = useState(false)

  useEffect(() => { const h = hoyIso(); setHoy(h); setLunes(lunesSemanaAnterior(h)) }, [])
  // Cada semana parte con su borrador limpio.
  useEffect(() => { setComentario(''); setTextos({}); setExcluidas(new Set()); setConfirmar(false) }, [lunes])

  const { data: base, isLoading, error } = useQuery({
    queryKey: ['enex-informe-semanal', lunes],
    enabled: !!lunes,
    staleTime: 30_000,
    queryFn: async () => {
      const [faenas, rows] = await Promise.all([getFaenas(), getPanelVentana(mesesNecesarios(lunes))])
      const hasta = sumarDias(lunes, 6)
      const eids = rows.filter((r) => r.fecha_ejecucion && r.fecha_ejecucion.slice(0, 10) >= lunes && r.fecha_ejecucion.slice(0, 10) <= hasta)
        .map((r) => r.ejecucion_id).filter(Boolean) as string[]
      const [reprogs, hallazgos] = await Promise.all([getReprogramacionesDesde(lunes), getHallazgosDeEjecuciones(eids)])
      // Lomas Lubricantes se mide por actividad de la pauta por lugar, como en su pantalla.
      const conLugares = await getFaenasConLugares()
      const pautaLugar: Record<string, PautaLugarFaena> = {}
      await Promise.all(faenas.filter((f) => conLugares.includes(f.id)).map(async (f) => {
        const trimestre = trimestreContrato(lunes, f.trimestre_ancla ?? 2).desde
        try { await sincronizarTrimestre(f.id, trimestre) } catch { /* se informa lo guardado */ }
        const items = await getLugarItems(f.id)
        pautaLugar[f.id] = { items, acts: await getActividadesTrimestre(items.map((i) => i.lugar_item_id), trimestre) }
      }))
      return { faenas, rows, reprogs, hallazgos, pautaLugar }
    },
  })

  const { data: envios = [] } = useQuery({
    queryKey: ['enex-informe-semanal-envios', lunes], enabled: !!lunes, queryFn: () => getEnviosInformeSemanal(lunes),
  })

  // Destinatarios: los del último envío, para no volver a escribirlos.
  const ultimoPara = envios[0]?.destinatarios?.join(', ')
  const ultimaCopia = envios[0]?.copia?.join(', ')
  useEffect(() => { if (ultimoPara && !para) setPara(ultimoPara) }, [ultimoPara]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (ultimaCopia && !copia) setCopia(ultimaCopia) }, [ultimaCopia]) // eslint-disable-line react-hooks/exhaustive-deps

  const armado = useMemo(() => (base && hoy ? armarInformeSemanal({ lunes, hoy, ...base }) : null), [base, lunes, hoy])

  // Lo que se revisa es lo que sale: comentario y observaciones ya editadas.
  const informe: InformeSemanal | null = useMemo(() => {
    if (!armado) return null
    return {
      ...armado,
      comentario,
      faenas: armado.faenas.map((f) => ({
        ...f,
        observaciones: f.observaciones
          .filter((o) => !excluidas.has(o.id))
          .map((o) => ({ ...o, texto: textos[o.id] ?? o.texto })),
      })),
    }
  }, [armado, comentario, textos, excluidas])

  const vista = useMemo(() => (informe ? htmlInformeSemanal(informe) : ''), [informe])
  const listaPara = separar(para), listaCopia = separar(copia)
  const correosOk = listaPara.length > 0 && [...listaPara, ...listaCopia].every((x) => EMAIL.test(x))
  const totalObs = armado?.faenas.reduce((n, f) => n + f.observaciones.length, 0) ?? 0
  const yaEnviado = envios.find((e) => e.estado === 'enviado')

  async function enviar() {
    if (!informe) return
    setEnviando(true)
    try {
      const { data } = await supabase.auth.getSession()
      const r = await fetch('/api/notificaciones/enex-informe-semanal/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.session?.access_token ?? ''}` },
        body: JSON.stringify({ informe, para: listaPara, copia: listaCopia }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j.error ?? 'No se pudo enviar')
      toast.success(`Informe enviado a ${listaPara.length} destinatario(s)`)
      setConfirmar(false)
      qc.invalidateQueries({ queryKey: ['enex-informe-semanal-envios', lunes] })
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setEnviando(false)
    }
  }

  if (!lunes) return <div className="flex justify-center p-12"><Spinner /></div>
  const domingo = sumarDias(lunes, 6)

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-gray-900">Informe semanal a ENEX</h1>
          <p className="text-sm text-gray-500">Revisa el borrador, ajusta las observaciones y envíalo. Nada sale sin tu confirmación.</p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" aria-label="Semana anterior" onClick={() => setLunes(sumarDias(lunes, -7))}><ChevronLeft className="h-4 w-4" /></Button>
          <span className="min-w-[190px] text-center text-sm font-semibold">Semana {numeroSemana(lunes)} · {fechaCorta(lunes)} al {fechaCorta(domingo)}</span>
          <Button variant="outline" size="sm" aria-label="Semana siguiente" onClick={() => setLunes(sumarDias(lunes, 7))}><ChevronRight className="h-4 w-4" /></Button>
        </div>
      </div>

      {error && <Card><CardContent className="p-4 text-sm text-red-700">No se pudo cargar: {(error as Error).message}</CardContent></Card>}
      {isLoading && <div className="flex justify-center p-12"><Spinner /></div>}
      {armado && armado.faenas.length === 0 && <Card><CardContent className="p-6 text-center text-sm text-gray-500">No hay actividad registrada para esta semana.</CardContent></Card>}

      {armado && armado.faenas.length > 0 && informe && (
        <div className="grid gap-4 lg:grid-cols-2">
          <div className="space-y-4">
            <Card><CardContent className="space-y-3 p-4">
              <label className="block text-sm font-semibold">Comentario general (opcional)
                <textarea value={comentario} onChange={(e) => setComentario(e.target.value)} rows={3}
                  className="mt-1 w-full rounded border p-2 text-sm font-normal" placeholder="Lo más importante de la semana" />
              </label>
            </CardContent></Card>

            <Card><CardContent className="space-y-3 p-4">
              <h2 className="text-sm font-semibold">Observaciones de los operadores ({totalObs})</h2>
              {totalObs === 0 && <p className="text-sm text-gray-500">Sin observaciones registradas esta semana.</p>}
              {armado.faenas.flatMap((f) => f.observaciones.map((o) => (
                <div key={o.id} className={`rounded border p-2 ${excluidas.has(o.id) ? 'opacity-50' : ''}`}>
                  <div className="flex items-start justify-between gap-2 text-xs text-gray-600">
                    <span><b>{f.nombre} · {o.instalacion}</b> · {o.servicio} · {fechaCorta(o.fecha)}{o.autor ? ` · ${o.autor}` : ''}
                      {o.tipo === 'hallazgo' && <span className="ml-1 font-semibold text-red-700">Hallazgo: {o.item}</span>}</span>
                    <label className="flex shrink-0 items-center gap-1">
                      <input type="checkbox" checked={!excluidas.has(o.id)} onChange={(e) => setExcluidas((s) => {
                        const n = new Set(s); if (e.target.checked) n.delete(o.id); else n.add(o.id); return n
                      })} /> Incluir
                    </label>
                  </div>
                  <textarea aria-label={`Observación de ${o.instalacion}`} value={textos[o.id] ?? o.texto} disabled={excluidas.has(o.id)} rows={3}
                    onChange={(e) => setTextos((t) => ({ ...t, [o.id]: e.target.value }))} className="mt-1 w-full rounded border p-2 text-sm" />
                </div>
              )))}
            </CardContent></Card>

            <Card><CardContent className="space-y-3 p-4">
              <label className="block text-sm font-semibold">Para
                <input value={para} onChange={(e) => { setPara(e.target.value); setConfirmar(false) }} className="mt-1 w-full rounded border p-2 text-sm font-normal" placeholder="correo@enex.cl, otro@esmax.cl" />
              </label>
              <label className="block text-sm font-semibold">Copia
                <input value={copia} onChange={(e) => { setCopia(e.target.value); setConfirmar(false) }} className="mt-1 w-full rounded border p-2 text-sm font-normal" />
              </label>
              {para && !correosOk && <p className="text-xs text-red-700">Revisa los correos: hay uno mal escrito.</p>}
              {yaEnviado && <p className="flex items-center gap-1 text-xs text-amber-700"><AlertTriangle className="h-3.5 w-3.5" /> Esta semana ya se envió el {new Date(yaEnviado.enviado_at ?? yaEnviado.created_at).toLocaleString('es-CL')} a {yaEnviado.destinatarios.join(', ')}.</p>}
              {!confirmar
                ? <Button disabled={!correosOk} onClick={() => setConfirmar(true)}><Send className="mr-2 h-4 w-4" /> Enviar informe</Button>
                : <div className="space-y-2 rounded border border-amber-300 bg-amber-50 p-3 text-sm">
                    <p>Se enviará a: <b>{[...listaPara, ...listaCopia].join(', ')}</b></p>
                    <div className="flex gap-2">
                      <Button disabled={enviando} onClick={enviar}>{enviando && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Confirmar envío</Button>
                      <Button variant="outline" disabled={enviando} onClick={() => setConfirmar(false)}>Cancelar</Button>
                    </div>
                  </div>}
            </CardContent></Card>
          </div>

          <Card className="overflow-hidden"><CardContent className="p-0">
            <iframe title="Vista previa del correo" srcDoc={vista} sandbox="" className="h-[80vh] w-full border-0" />
          </CardContent></Card>
        </div>
      )}
    </div>
  )
}
