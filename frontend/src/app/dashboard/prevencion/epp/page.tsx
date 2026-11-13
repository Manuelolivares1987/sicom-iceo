'use client'

// ============================================================================
// Panel — Entregas de EPP (MIG687)
// ----------------------------------------------------------------------------
// Registro DS 44 art. 13: qué recibió cada trabajador, cuándo, por qué, si se
// le instruyó el uso y su firma. Comprobante PDF por entrega.
// ============================================================================

import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Ban, FileDown, HardHat, Loader2, Plus, Search } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { useFaenasPrevencion } from '@/hooks/use-prevencion-reportabilidad'
import { EppEntregaForm } from '@/components/prevencion/epp-entrega-form'
import { descargarComprobanteEpp } from '@/components/prevencion/pdf-comprobante-epp'
import { MOTIVO_EPP, anularEntregaEpp, getEntregasEpp, type EppEntrega } from '@/lib/services/prevencion-epp'

const ROLES_ADMIN = ['administrador', 'prevencionista', 'jefe_operaciones', 'subgerente_operaciones']

function primerDiaMes(offset = 0) {
  const d = new Date(); d.setMonth(d.getMonth() + offset, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

export default function EppPanelPage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const [desde, setDesde] = useState(primerDiaMes(-2))
  const [hasta, setHasta] = useState(new Date().toISOString().slice(0, 10))
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [nueva, setNueva] = useState(false)
  const [pdfId, setPdfId] = useState<string | null>(null)
  const [anulando, setAnulando] = useState<EppEntrega | null>(null)
  const [motivoAnula, setMotivoAnula] = useState('')
  const esAdmin = !!perfil?.rol && ROLES_ADMIN.includes(perfil.rol)

  const { data: faenas } = useFaenasPrevencion()
  const { data: entregas, isLoading } = useQuery({
    queryKey: ['epp-entregas', desde, hasta, faenaId],
    queryFn: () => getEntregasEpp({ desde, hasta, faenaId }),
  })

  const lista = useMemo(() => {
    const t = q.trim().toLowerCase()
    return (entregas ?? []).filter((e) => !t || e.trabajador_nombre.toLowerCase().includes(t)
      || (e.trabajador_rut ?? '').toLowerCase().includes(t)
      || e.items.some((i) => i.nombre.toLowerCase().includes(t)))
  }, [entregas, q])

  const kpis = useMemo(() => {
    const v = (entregas ?? []).filter((e) => !e.anulada)
    return {
      entregas: v.length,
      personas: new Set(v.map((e) => e.personal_id)).size,
      unidades: v.reduce((s, e) => s + e.items.reduce((a, i) => a + i.cantidad, 0), 0),
      sinInstruccion: v.filter((e) => !e.instruccion_uso).length,
    }
  }, [entregas])

  const anular = useMutation({
    mutationFn: () => anularEntregaEpp(anulando!.id, motivoAnula.trim()),
    onSuccess: () => {
      toast.success('Entrega anulada'); setAnulando(null); setMotivoAnula('')
      qc.invalidateQueries({ queryKey: ['epp-entregas'] })
    },
    onError: (e: any) => toast.error(e?.message ?? 'No se pudo anular'),
  })

  const pdf = async (e: EppEntrega) => {
    setPdfId(e.id)
    try { await descargarComprobanteEpp(e) } catch (err: any) { toast.error(err?.message ?? 'No se pudo generar el PDF') }
    finally { setPdfId(null) }
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold"><HardHat className="h-6 w-6 text-orange-500" /> Entregas de EPP</h1>
          <p className="text-sm text-muted-foreground">
            Registro con firma del trabajador e instrucción de uso (DS 44 art. 13). No descuenta stock de bodega.
          </p>
        </div>
        <Button onClick={() => setNueva(true)}><Plus className="mr-1.5 h-4 w-4" /> Nueva entrega</Button>
      </div>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {[
          { l: 'Entregas', v: kpis.entregas },
          { l: 'Trabajadores', v: kpis.personas },
          { l: 'Unidades entregadas', v: kpis.unidades },
          { l: 'Sin instrucción de uso', v: kpis.sinInstruccion, warn: kpis.sinInstruccion > 0 },
        ].map((k) => (
          <Card key={k.l}><CardContent className="p-3">
            <p className="text-[11px] uppercase text-muted-foreground">{k.l}</p>
            <p className={cn('text-2xl font-bold', k.warn && 'text-amber-700')}>{k.v}</p>
          </CardContent></Card>
        ))}
      </div>

      <div className="flex flex-wrap items-end gap-2">
        <Input label="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="h-9 w-40" />
        <Input label="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="h-9 w-40" />
        <div className="relative min-w-[220px] flex-1">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Trabajador, RUT o elemento…" className="h-9 pl-9" />
        </div>
      </div>
      <div className="flex flex-wrap gap-1.5">
        <Button size="sm" variant={faenaId === null ? 'primary' : 'outline'} onClick={() => setFaenaId(null)}>Todas</Button>
        {(faenas ?? []).map((f: any) => (
          <Button key={f.id} size="sm" variant={faenaId === f.id ? 'primary' : 'outline'} onClick={() => setFaenaId(f.id)}>{f.nombre}</Button>
        ))}
      </div>

      {isLoading ? <div className="flex justify-center py-12"><Spinner /></div> : (
        <Card><CardContent className="overflow-x-auto p-0">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-[11px] uppercase text-muted-foreground">
              <tr><th className="px-3 py-2">Fecha</th><th>Trabajador</th><th>Faena</th><th>Elementos</th><th>Motivo</th><th>Instrucción</th><th>Entregó</th><th></th></tr>
            </thead>
            <tbody>
              {lista.map((e) => (
                <tr key={e.id} className={cn('border-t align-top', e.anulada && 'opacity-50')}>
                  <td className="whitespace-nowrap px-3 py-2">{e.fecha}</td>
                  <td className="whitespace-nowrap">
                    {e.trabajador_nombre}
                    {e.anulada && <span className="ml-1 rounded bg-red-100 px-1 text-[10px] font-bold text-red-700" title={e.anulada_motivo ?? ''}>ANULADA</span>}
                  </td>
                  <td className="whitespace-nowrap text-[12px]">{e.faena_nombre}</td>
                  <td className="max-w-[320px] py-2 text-[12px]">
                    {e.items.map((i) => `${i.cantidad > 1 ? i.cantidad + '× ' : ''}${i.nombre}${i.talla ? ` (${i.talla})` : ''}`).join(' · ')}
                  </td>
                  <td className="whitespace-nowrap text-[12px]">{MOTIVO_EPP[e.motivo] ?? e.motivo}</td>
                  <td className="text-[12px]">{e.instruccion_uso ? 'Sí' : <span className="font-semibold text-amber-700">No</span>}</td>
                  <td className="whitespace-nowrap text-[12px]">{e.entregado_por_nombre ?? '—'}</td>
                  <td className="whitespace-nowrap pr-3 text-right">
                    <Button size="sm" variant="ghost" title="Comprobante PDF" onClick={() => pdf(e)} disabled={pdfId === e.id}>
                      {pdfId === e.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileDown className="h-4 w-4" />}
                    </Button>
                    {esAdmin && !e.anulada && (
                      <Button size="sm" variant="ghost" title="Anular" onClick={() => setAnulando(e)}><Ban className="h-4 w-4 text-red-500" /></Button>
                    )}
                  </td>
                </tr>
              ))}
              {!lista.length && <tr><td colSpan={8} className="py-10 text-center text-muted-foreground">Sin entregas en el período.</td></tr>}
            </tbody>
          </table>
        </CardContent></Card>
      )}

      <Modal open={nueva} onClose={() => setNueva(false)} title="Nueva entrega de EPP" className="max-w-[560px]">
        <EppEntregaForm onGuardado={() => setNueva(false)} onCancelar={() => setNueva(false)} />
      </Modal>

      <Modal open={!!anulando} onClose={() => setAnulando(null)} title="Anular entrega">
        <div className="space-y-3">
          <p className="text-sm">
            La entrega de <b>{anulando?.trabajador_nombre}</b> del {anulando?.fecha} queda marcada como anulada (no se borra).
          </p>
          <Input label="Motivo" value={motivoAnula} onChange={(e) => setMotivoAnula(e.target.value)} placeholder="Ej: cargada al trabajador equivocado" />
          <div className="flex gap-2">
            <Button variant="danger" className="flex-1" disabled={!motivoAnula.trim() || anular.isPending} onClick={() => anular.mutate()}>
              {anular.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Anular
            </Button>
            <Button variant="outline" onClick={() => setAnulando(null)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
