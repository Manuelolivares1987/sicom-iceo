'use client'

// ============================================================================
// Cargar el archivo de Orpak (MIG328)
// ----------------------------------------------------------------------------
// Es el paso que faltaba para que el cierre tenga tres lados. Sin esto el
// sistema sabe cuánto combustible se movió, pero no a quién imputarlo — y esa
// mitad se seguía resolviendo a mano en un Excel aparte.
//
// La pantalla está hecha para que un archivo no se cargue "a ver qué pasa":
// primero se lee y se muestra qué trae, y recién después se confirma. Cargar
// dos veces el mismo archivo no duplica nada, pero saberlo antes es distinto a
// descubrirlo después.
// ============================================================================

import { useState, useRef } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Upload, FileSpreadsheet, CheckCircle2, AlertTriangle, Clock, Loader2 } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import { FAENA_ROMERAL, getFaenaPorCodigo } from '@/lib/services/combustible-faena'
import {
  cargarOrpak, getCargas, getCecosDesconocidos, getCecosPorRevisar,
  type FilaOrpak, type ResultadoCarga,
} from '@/lib/services/combustible-orpak'
import { confirmarCeco } from '@/lib/services/combustible-cierre'

const miles = (n: number | null | undefined) =>
  n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 })

type Leido = {
  archivo: string
  filas: FilaOrpak[]
  hojas: { hoja: string; leidas: number; sinColumnas: boolean }[]
  ambiguos: number
}

export default function CargarOrpakPage() {
  const { loading: authLoading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const input = useRef<HTMLInputElement>(null)

  const [leyendo, setLeyendo] = useState(false)
  const [subiendo, setSubiendo] = useState(false)
  const [leido, setLeido] = useState<Leido | null>(null)
  const [resultado, setResultado] = useState<ResultadoCarga | null>(null)

  const { data: faena } = useQuery({
    queryKey: ['faena', FAENA_ROMERAL],
    queryFn: () => getFaenaPorCodigo(FAENA_ROMERAL),
  })
  const faenaId = faena?.id

  const { data: cargas } = useQuery({
    queryKey: ['orpak-cargas', faenaId],
    queryFn: () => getCargas(faenaId!),
    enabled: !!faenaId,
  })

  const { data: cecosRaros } = useQuery({
    queryKey: ['orpak-cecos-desconocidos', faenaId],
    queryFn: () => getCecosDesconocidos(faenaId!),
    enabled: !!faenaId,
  })

  const { data: porRevisar } = useQuery({
    queryKey: ['orpak-cecos-por-revisar', faenaId],
    queryFn: () => getCecosPorRevisar(faenaId!),
    enabled: !!faenaId,
  })

  const [confirmando, setConfirmando] = useState<string | null>(null)

  async function confirmar(cecoId: string, codigo: string) {
    setConfirmando(cecoId)
    try {
      await confirmarCeco(cecoId)
      qc.invalidateQueries({ queryKey: ['orpak-cecos-por-revisar'] })
      toast.success(`CECO ${codigo} confirmado.`)
    } catch (err) {
      toast.error(errorMessage(err))
    } finally {
      setConfirmando(null)
    }
  }

  async function alElegirArchivo(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setResultado(null)
    setLeyendo(true)
    try {
      // ExcelJS y el lector se cargan sólo cuando hacen falta: son pesados y
      // esta pantalla se abre una vez al día.
      const [{ default: ExcelJS }, { leerOrpak }] = await Promise.all([
        import('exceljs'),
        import('@/lib/services/orpak-parse.js') as any,
      ])
      const wb = new ExcelJS.Workbook()
      await wb.xlsx.load(await file.arrayBuffer())
      const { filas, hojas, ambiguos } = leerOrpak(wb)
      if (!filas.length) {
        toast.error('El archivo no trae ninguna transacción legible.')
        setLeido(null)
        return
      }
      setLeido({ archivo: file.name, filas, hojas, ambiguos })
    } catch (err) {
      toast.error(errorMessage(err))
      setLeido(null)
    } finally {
      setLeyendo(false)
      if (input.current) input.current.value = ''
    }
  }

  async function confirmarCarga() {
    if (!leido || !faenaId) return
    setSubiendo(true)
    try {
      const r = await cargarOrpak(faenaId, leido.archivo, leido.filas)
      setResultado(r)
      setLeido(null)
      qc.invalidateQueries({ queryKey: ['orpak-cargas'] })
      qc.invalidateQueries({ queryKey: ['orpak-cecos-desconocidos'] })
      qc.invalidateQueries({ queryKey: ['control-diario'] })
      toast.success(r.nuevas > 0
        ? `${r.nuevas} transacciones nuevas del ${r.desde} al ${r.hasta}.`
        : 'Este archivo ya estaba cargado completo. No se duplicó nada.')
    } catch (err) {
      toast.error(errorMessage(err))
    } finally {
      setSubiendo(false)
    }
  }

  if (authLoading) return null

  const totalLitros = leido?.filas.reduce((a, b) => a + b.litros, 0) ?? 0
  const dias = leido ? Array.from(new Set(leido.filas.map((f) => f.dia_cierre ?? f.fecha))).sort() : []

  return (
    <div className="mx-auto max-w-5xl space-y-5 p-4">
      <header>
        <h1 className="text-xl font-bold text-gray-900">Cargar Orpak</h1>
        <p className="mt-1 text-sm text-gray-600">
          Es la tercera medida del cierre: cuánto registró el sistema automático y a quién.
          Sin ella el volumen cuadra pero la imputación queda abierta.
        </p>
      </header>

      <Card>
        <CardContent className="p-5">
          <input
            ref={input} type="file" accept=".xlsx,.xls" className="hidden"
            onChange={alElegirArchivo}
          />
          <button
            onClick={() => input.current?.click()}
            disabled={leyendo || subiendo}
            className="flex w-full flex-col items-center gap-2 rounded-lg border-2 border-dashed
                       border-gray-300 py-10 text-gray-600 transition hover:border-blue-400
                       hover:bg-blue-50 disabled:opacity-50"
          >
            {leyendo
              ? <><Loader2 className="h-8 w-8 animate-spin text-blue-600" /><span>Leyendo el archivo…</span></>
              : <><Upload className="h-8 w-8" /><span className="font-medium">Elegir el archivo de Orpak</span>
                  <span className="text-xs text-gray-500">
                    El export tal como lo baja del sistema, con sus hojas por estación
                  </span></>}
          </button>
        </CardContent>
      </Card>

      {leido && (
        <Card className="border-blue-200">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-base">
              <FileSpreadsheet className="h-4 w-4 text-blue-600" />
              {leido.archivo}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-3 gap-3 text-center">
              <Dato valor={miles(leido.filas.length)} label="transacciones" />
              <Dato valor={miles(totalLitros)} label="litros" />
              <Dato
                valor={dias.length ? `${dias[0].slice(8)} al ${dias[dias.length - 1].slice(8)}` : '—'}
                label={dias.length ? `de ${dias[0].slice(0, 7)}` : 'sin fechas'}
              />
            </div>

            <table className="w-full text-sm">
              <tbody>
                {leido.hojas.map((h) => (
                  <tr key={h.hoja} className="border-b border-gray-100 last:border-0">
                    <td className="py-1.5 font-medium text-gray-700">{h.hoja}</td>
                    <td className="py-1.5 text-right tabular-nums text-gray-600">
                      {h.sinColumnas
                        ? <span className="text-amber-700">sin columnas reconocibles</span>
                        : h.leidas === 0
                          ? <span className="text-gray-400">sin movimientos</span>
                          : `${miles(h.leidas)} filas`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {leido.ambiguos > 0 && (
              <p className="rounded bg-amber-50 p-2 text-xs text-amber-800">
                <AlertTriangle className="mr-1 inline h-3.5 w-3.5" />
                {leido.ambiguos} {leido.ambiguos === 1 ? 'valor tiene' : 'valores tienen'} un
                separador que puede ser decimal o de miles (por ejemplo «1.234»). Se leyeron como
                miles. Conviene revisarlos en el archivo original.
              </p>
            )}

            <div className="flex gap-2">
              <button
                onClick={confirmarCarga} disabled={subiendo}
                className="flex-1 rounded-lg bg-blue-600 py-2.5 font-medium text-white
                           hover:bg-blue-700 disabled:opacity-50"
              >
                {subiendo ? 'Cargando…' : 'Cargar al sistema'}
              </button>
              <button
                onClick={() => setLeido(null)} disabled={subiendo}
                className="rounded-lg border border-gray-300 px-4 py-2.5 text-gray-700 hover:bg-gray-50"
              >
                Cancelar
              </button>
            </div>
            <p className="text-center text-xs text-gray-500">
              Si este archivo ya se cargó, las filas repetidas se reconocen y no se duplican.
            </p>
          </CardContent>
        </Card>
      )}

      {resultado && (
        <Card className="border-emerald-200 bg-emerald-50/40">
          <CardContent className="space-y-2 p-5 text-sm">
            <p className="flex items-center gap-2 font-medium text-emerald-900">
              <CheckCircle2 className="h-4 w-4" />
              {resultado.nuevas > 0
                ? `Entraron ${miles(resultado.nuevas)} transacciones nuevas.`
                : 'No había nada nuevo: el archivo ya estaba cargado.'}
            </p>
            <ul className="ml-6 space-y-0.5 text-gray-700">
              {resultado.repetidas > 0 && <li>{miles(resultado.repetidas)} ya estaban y no se duplicaron.</li>}
              {resultado.rechazadas > 0 && (
                <li className="text-amber-800">
                  {miles(resultado.rechazadas)} filas no se pudieron cargar
                  {resultado.rechazos?.[0] && <> — {resultado.rechazos[0].motivo}</>}.
                </li>
              )}
              {resultado.desde && <li>Período: {resultado.desde} al {resultado.hasta}.</li>}
            </ul>
          </CardContent>
        </Card>
      )}

      {!!porRevisar?.length && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">
              CECO creados desde Orpak, por revisar
              <span className="ml-2 text-xs font-normal text-gray-400">({porRevisar.length})</span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="mb-3 text-xs text-gray-600">
              Se dieron de alta solos con la razón social que trae el archivo, así que la imputación
              de esos días ya cerró. Falta que alguien mire el nombre: una razón social mal escrita
              en Orpak se arrastra hasta la facturación.
            </p>
            <div className="max-h-96 overflow-y-auto">
              <table className="w-full text-sm">
                <tbody>
                  {porRevisar.map((c) => (
                    <tr key={c.ceco_id} className="border-b border-gray-100 last:border-0">
                      <td className="py-1.5 font-mono text-xs text-gray-800">{c.codigo}</td>
                      <td className="py-1.5 text-gray-700">
                        {c.empresa ?? <span className="italic text-amber-700">sin razón social en el archivo</span>}
                      </td>
                      <td className="py-1.5 text-right tabular-nums text-gray-600">
                        {miles(c.litros)} L
                      </td>
                      <td className="py-1.5 pl-3 text-right text-xs text-gray-400">
                        {c.transacciones} mov.
                      </td>
                      <td className="py-1.5 pl-3 text-right">
                        <button
                          onClick={() => confirmar(c.ceco_id, c.codigo)}
                          disabled={confirmando === c.ceco_id}
                          className="rounded border border-gray-300 px-2 py-1 text-xs text-gray-700
                                     transition hover:border-emerald-400 hover:bg-emerald-50
                                     hover:text-emerald-800 disabled:opacity-40"
                        >
                          {confirmando === c.ceco_id ? '…' : 'Está bien'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}

      {!!cecosRaros?.length && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">CECO que no se pudieron dar de alta</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="mb-3 text-xs text-gray-600">
              Traen código legible y no se pudieron crear solos. Si aparece algo acá, hay un
              choque de códigos que hay que mirar a mano.
            </p>
            <div className="max-h-72 overflow-y-auto">
              <table className="w-full text-sm">
                <tbody>
                  {cecosRaros.map((c) => (
                    <tr key={c.ceco_codigo} className="border-b border-gray-100 last:border-0">
                      <td className="py-1.5 font-mono text-xs text-gray-800">{c.ceco_codigo}</td>
                      <td className="py-1.5 text-gray-600">{c.departamento}</td>
                      <td className="py-1.5 text-right tabular-nums text-gray-700">
                        {miles(c.litros)} L
                      </td>
                      <td className="py-1.5 pl-3 text-right text-xs text-gray-500">
                        {c.transacciones} mov.
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}

      {!!cargas?.length && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-base">
              <Clock className="h-4 w-4 text-gray-500" /> Cargas anteriores
            </CardTitle>
          </CardHeader>
          <CardContent>
            <table className="w-full text-sm">
              <tbody>
                {cargas.map((c) => (
                  <tr key={c.id} className="border-b border-gray-100 last:border-0">
                    <td className="py-1.5">
                      <div className="font-medium text-gray-800">{c.archivo}</div>
                      <div className="text-xs text-gray-500">
                        {c.cargado_nombre ?? 'alguien'} · {new Date(c.cargado_at).toLocaleString('es-CL')}
                      </div>
                    </td>
                    <td className="py-1.5 text-right text-xs text-gray-600">
                      {c.periodo_desde && <div>{c.periodo_desde} al {c.periodo_hasta}</div>}
                      <div className={cn(c.filas_nuevas > 0 ? 'text-emerald-700' : 'text-gray-400')}>
                        {miles(c.filas_nuevas)} nuevas
                        {c.filas_repetidas > 0 && ` · ${miles(c.filas_repetidas)} repetidas`}
                      </div>
                    </td>
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

function Dato({ valor, label }: { valor: string; label: string }) {
  return (
    <div className="rounded-lg bg-gray-50 p-3">
      <div className="text-lg font-bold tabular-nums text-gray-900">{valor}</div>
      <div className="text-xs text-gray-500">{label}</div>
    </div>
  )
}
