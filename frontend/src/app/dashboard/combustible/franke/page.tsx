'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Fuel, Truck, AlertTriangle, ArrowLeftRight, Send, PlusCircle, Loader2, CheckCircle2, Gauge,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getCamionesFranke, getPuntosCargaFranke, getCuadreDiarioFranke, getComprasPuntoFranke,
  registrarCargaCamion,
} from '@/lib/services/combustible-franke'
import { uploadEvidenciaCombustible, uploadBlobEvidenciaCombustible } from '@/lib/services/combustible'
import { cn } from '@/lib/utils'

const nf = (n: any) => Number(n ?? 0).toLocaleString('es-CL')

export default function CombustibleFrankePage() {
  useRequireAuth()
  const [tab, setTab] = useState<'camiones' | 'cuadre' | 'compras'>('camiones')
  const [cargaOpen, setCargaOpen] = useState(false)

  const { data: camiones = [], isLoading: lc } = useQuery({ queryKey: ['franke-camiones'], queryFn: async () => (await getCamionesFranke()).data })
  const { data: cuadre = [] } = useQuery({ queryKey: ['franke-cuadre'], queryFn: async () => (await getCuadreDiarioFranke()).data })
  const { data: compras = [] } = useQuery({ queryKey: ['franke-compras'], queryFn: async () => (await getComprasPuntoFranke()).data })

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Fuel className="h-6 w-6 text-orange-600" /> Combustible · Franke
          </h1>
          <p className="text-sm text-muted-foreground">
            Camiones petroleros, cargas por punto, trasvasije entre camiones, despacho/venta y cuadre diario.
          </p>
        </div>
        <div className="flex gap-2">
          <Button onClick={() => setCargaOpen((o) => !o)}><PlusCircle className="h-4 w-4 mr-1" /> Registrar carga</Button>
          <Link href="/dashboard/combustible/traspaso"><Button variant="outline"><ArrowLeftRight className="h-4 w-4 mr-1" /> Trasvasije</Button></Link>
          <Link href="/dashboard/combustible/despacho"><Button variant="outline"><Send className="h-4 w-4 mr-1" /> Despacho/Venta</Button></Link>
        </div>
      </div>

      {cargaOpen && <CargaForm camiones={camiones} onClose={() => setCargaOpen(false)} />}

      <div className="flex gap-2 border-b">
        {([['camiones', 'Camiones'], ['cuadre', 'Cuadre diario'], ['compras', 'Compras por punto']] as const).map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
            className={cn('px-4 py-2 text-sm border-b-2 -mb-px', tab === k ? 'border-orange-600 text-orange-700 font-medium' : 'border-transparent text-muted-foreground')}>
            {l}
          </button>
        ))}
      </div>

      {tab === 'camiones' && (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {lc && <Spinner className="h-5 w-5" />}
          {camiones.map((c: any) => {
            const pct = c.capacidad_lt ? Math.round(100 * Number(c.stock_teorico_lt) / Number(c.capacidad_lt)) : 0
            return (
              <Card key={c.id}>
                <CardContent className="p-4 space-y-2">
                  <div className="flex items-center gap-2"><Truck className="h-5 w-5 text-blue-600" />
                    <span className="font-semibold">{c.patente}</span>
                    <Badge variant="default" className="text-[10px]">{c.codigo}</Badge></div>
                  <div className="text-sm text-muted-foreground">{c.nombre}</div>
                  <div className="text-2xl font-bold">{nf(c.stock_teorico_lt)} <span className="text-sm font-normal text-muted-foreground">/ {nf(c.capacidad_lt)} L</span></div>
                  <div className="h-2 rounded bg-gray-100 overflow-hidden">
                    <div className={cn('h-full', pct > 20 ? 'bg-orange-500' : 'bg-red-500')} style={{ width: `${Math.min(pct, 100)}%` }} />
                  </div>
                  <div className="text-xs text-muted-foreground">CPP ${nf(c.costo_promedio_lt)}/L</div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      {tab === 'cuadre' && (
        <Card><CardHeader><CardTitle className="text-base flex items-center gap-2"><Gauge className="h-4 w-4" /> Cuadre diario por camión</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr className="text-xs text-muted-foreground text-right">
                <th className="text-left py-1">Camión</th><th>Día</th><th>Cargado</th><th>Trasv. recibido</th>
                <th>Trasv. entregado</th><th>Despachado</th><th>Vendido</th><th>Mov. neto</th><th>Descuadre</th>
              </tr></thead>
              <tbody>
                {cuadre.map((r: any, i: number) => (
                  <tr key={i} className="border-t text-right">
                    <td className="text-left py-1.5">{r.patente}</td>
                    <td>{r.dia}</td>
                    <td>{nf(r.cargado)}</td><td>{nf(r.trasvasije_recibido)}</td><td>{nf(r.trasvasije_entregado)}</td>
                    <td>{nf(r.despachado)}</td><td>{nf(r.vendido)}</td>
                    <td className="font-medium">{nf(r.movimiento_neto)}</td>
                    <td className={cn(r.descuadre_lt != null && Math.abs(Number(r.descuadre_lt)) > 0 ? 'text-red-600 font-semibold' : 'text-muted-foreground')}>
                      {r.descuadre_lt != null ? nf(r.descuadre_lt) : '—'}
                    </td>
                  </tr>
                ))}
                {cuadre.length === 0 && <tr><td colSpan={9} className="py-6 text-center text-muted-foreground">Aún no hay movimientos de combustible en los camiones Franke.</td></tr>}
              </tbody>
            </table>
            <p className="text-xs text-muted-foreground mt-2">Descuadre = medición física (varillaje) − teórico. Vacío si no se hizo varillaje ese día.</p>
          </CardContent>
        </Card>
      )}

      {tab === 'compras' && (
        <Card><CardHeader><CardTitle className="text-base">Compras por punto de carga</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr className="text-xs text-muted-foreground"><th className="text-left py-1">Punto</th><th className="text-left">Tipo</th><th className="text-right">N° cargas</th><th className="text-right">Litros</th><th className="text-right">Costo total</th><th className="text-left pl-4">Última carga</th></tr></thead>
              <tbody>
                {compras.map((p: any) => (
                  <tr key={p.punto_id} className="border-t">
                    <td className="py-1.5">{p.nombre}</td>
                    <td><Badge variant="default" className="text-[10px]">{p.tipo}</Badge></td>
                    <td className="text-right">{nf(p.n_cargas)}</td>
                    <td className="text-right">{nf(p.litros_total)}</td>
                    <td className="text-right">${nf(p.costo_total)}</td>
                    <td className="pl-4 text-muted-foreground">{p.ultima_carga ? new Date(p.ultima_carga).toLocaleDateString('es-CL') : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function CargaForm({ camiones, onClose }: { camiones: any[]; onClose: () => void }) {
  const qc = useQueryClient()
  const { data: puntos = [] } = useQuery({ queryKey: ['franke-puntos'], queryFn: async () => (await getPuntosCargaFranke()).data })
  const [camion, setCamion] = useState('')
  const [punto, setPunto] = useState('')
  const [litros, setLitros] = useState('')
  const [costo, setCosto] = useState('')
  const [nombre, setNombre] = useState('')
  const [rut, setRut] = useState('')
  const [doc, setDoc] = useState('')
  const [fPat, setFPat] = useState<File | null>(null)
  const [fMedI, setFMedI] = useState<File | null>(null)
  const [fMedF, setFMedF] = useState<File | null>(null)
  const [firma, setFirma] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [ok, setOk] = useState<string | null>(null)

  const enviar = async () => {
    setErr(null)
    if (!camion || !litros) { setErr('Selecciona camión e ingresa litros.'); return }
    setSaving(true)
    try {
      const up = async (f: File | null, tipo: any) => f ? (await uploadEvidenciaCombustible(f, { tipo, estanqueId: camion })).url : null
      const [fpu, fmi, fmf] = await Promise.all([up(fPat, 'patente'), up(fMedI, 'medidor_inicial'), up(fMedF, 'medidor_final')])
      let firmaUrl: string | null = null
      if (firma) {
        const blob = await (await fetch(firma)).blob()
        firmaUrl = (await uploadBlobEvidenciaCombustible(blob, { tipo: 'firma', contextoId: camion, ext: 'png' })).url
      }
      const { data, error } = await registrarCargaCamion({
        estanque_movil_id: camion, punto_carga_id: punto || null, litros: Number(litros),
        costo_unitario_clp: costo ? Number(costo) : null, operador_nombre: nombre, operador_rut: rut,
        firma_operador_url: firmaUrl, foto_patente_url: fpu, foto_medidor_inicial_url: fmi, foto_medidor_final_url: fmf,
        documento_numero: doc,
      })
      if (error) throw error
      setOk(`Carga registrada (${(data as any)?.folio ?? ''}).`)
      qc.invalidateQueries({ queryKey: ['franke-camiones'] })
      qc.invalidateQueries({ queryKey: ['franke-cuadre'] })
      qc.invalidateQueries({ queryKey: ['franke-compras'] })
      setLitros(''); setCosto(''); setDoc(''); setFPat(null); setFMedI(null); setFMedF(null); setFirma(null)
    } catch (e) { setErr(e instanceof Error ? e.message : 'Error al registrar') } finally { setSaving(false) }
  }

  return (
    <Card className="border-orange-200">
      <CardHeader><CardTitle className="text-base flex items-center justify-between">
        <span>Registrar carga de camión</span>
        <Button size="sm" variant="ghost" onClick={onClose}>Cerrar</Button>
      </CardTitle></CardHeader>
      <CardContent className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <Sel label="Camión*" value={camion} onChange={setCamion} options={camiones.map((c) => [c.id, `${c.patente} (${c.codigo})`])} />
          <Sel label="Punto de carga" value={punto} onChange={setPunto} options={puntos.map((p: any) => [p.id, p.nombre])} />
          <In label="Litros*" value={litros} onChange={setLitros} type="number" />
          <In label="Costo unitario CLP/L" value={costo} onChange={setCosto} type="number" />
          <In label="Operador" value={nombre} onChange={setNombre} />
          <In label="RUT operador" value={rut} onChange={setRut} />
          <In label="N° documento/guía" value={doc} onChange={setDoc} />
        </div>
        <div className="grid gap-3 sm:grid-cols-3">
          <FileIn label="Foto patente camión" file={fPat} onChange={setFPat} />
          <FileIn label="Foto medidor inicial" file={fMedI} onChange={setFMedI} />
          <FileIn label="Foto medidor final" file={fMedF} onChange={setFMedF} />
        </div>
        <SignaturePad label="Firma del operador" onCapture={setFirma} />
        {err && <div className="flex items-center gap-2 text-sm text-red-600"><AlertTriangle className="h-4 w-4" />{err}</div>}
        {ok && <div className="flex items-center gap-2 text-sm text-emerald-700"><CheckCircle2 className="h-4 w-4" />{ok}</div>}
        <Button disabled={saving} onClick={enviar}>{saving ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <PlusCircle className="h-4 w-4 mr-1" />} Registrar carga</Button>
      </CardContent>
    </Card>
  )
}

function In({ label, value, onChange, type = 'text' }: { label: string; value: string; onChange: (v: string) => void; type?: string }) {
  return <label className="text-sm block">{label}<input type={type} value={value} onChange={(e) => onChange(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1" /></label>
}
function Sel({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: [string, string][] }) {
  return <label className="text-sm block">{label}
    <select value={value} onChange={(e) => onChange(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1">
      <option value="">—</option>{options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
    </select></label>
}
function FileIn({ label, file, onChange }: { label: string; file: File | null; onChange: (f: File | null) => void }) {
  return <label className="text-sm block border rounded px-2 py-1.5 cursor-pointer text-blue-600">
    {file ? '✓ ' + label : label}
    <input type="file" accept="image/*" capture="environment" className="hidden" onChange={(e) => onChange(e.target.files?.[0] ?? null)} />
  </label>
}
