'use client'

// ============================================================================
// Emitir un certificado de hermeticidad
// ----------------------------------------------------------------------------
// El certificado tiene más de treinta campos. Treinta campos en un formulario
// son una garantía de que nadie lo llene, así que el modal se abre con los
// datos de la última emisión de ESE camión y arriba deja sólo lo que cambia de
// verdad: la fecha de la prueba y las dos fotos.
//
// El resto queda plegado. Está ahí, se puede corregir, pero no hay que mirarlo
// para emitir una renovación.
//
// La fecha de vencimiento NO se pide: se calcula. Toda la auditoría documental
// de esta semana empezó porque alguien escribió un año donde iban seis meses.
// ============================================================================

import { useEffect, useState } from 'react'
import { Loader2, Camera, ChevronDown, ChevronRight, FileCheck2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useToast } from '@/contexts/toast-context'
import {
  getDatosPrevios, emitirCertificado, subirFotoCertificado, getCertificadoEmitido,
  getMiFirma, guardarMiFirmaDesdeArchivo, type MiFirma,
  getFirmantesAutorizados, type FirmanteAutorizado,
  GRUPOS_HERMETICIDAD, OBLIGATORIOS_HERMETICIDAD, type DatosPrevios,
} from '@/lib/services/certificados'
import { descargarCertificadoHermeticidad } from './pdf-hermeticidad'

const LOGO = '/images/logo_empresa_2.png'
const hoyISO = () => new Date().toISOString().slice(0, 10)

/** fecha de prueba + N meses, sin pasarse de fin de mes. */
function sumarMeses(iso: string, meses: number): string {
  if (!iso) return ''
  const [a, m, d] = iso.split('-').map(Number)
  const ultimo = new Date(Date.UTC(a, m - 1 + meses + 1, 0)).getUTCDate()
  return new Date(Date.UTC(a, m - 1 + meses, Math.min(d, ultimo))).toISOString().slice(0, 10)
}

export function ModalEmitirHermeticidad({ activoId, patente, onClose, onListo }: {
  activoId: string; patente: string; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [previos, setPrevios] = useState<DatosPrevios | null>(null)
  const [v, setV] = useState<Record<string, string>>({})
  const [fechaPrueba, setFechaPrueba] = useState(hoyISO())
  const [informe, setInforme] = useState('Aceptado sin filtraciones')
  const [fotos, setFotos] = useState<{ inicio: File | null; termino: File | null }>({ inicio: null, termino: null })
  const [abierto, setAbierto] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    getDatosPrevios(activoId)
      .then((p) => {
        setPrevios(p)
        const base: Record<string, string> = {}
        for (const [k, val] of Object.entries(p.datos ?? {})) base[k] = (val as string) ?? ''
        setV(base)
        // La primera vez de un equipo no hay nada que confirmar: se abre el
        // grupo del estanque, que es el que hay que llenar sí o sí.
        if (!p.hay_anterior) setAbierto('El estanque')
      })
      .catch((e) => toast.error((e as Error).message))
  }, [activoId, toast])

  // [MIG467] La firma de quien está emitiendo. Vive en su perfil, así que se
  // sube una vez y sirve para todos los certificados que emita.
  const [firma, setFirma] = useState<MiFirma | null>(null)
  const [subiendoFirma, setSubiendoFirma] = useState(false)
  useEffect(() => { getMiFirma().then(setFirma).catch(() => {}) }, [])

  // [MIG469] Quien emite no es necesariamente quien firma: el jefe de
  // operaciones hace el certificado y lo firma Manuel. La lista es de personas
  // DESIGNADAS, no de cuentas con permiso para emitir.
  const [firmantes, setFirmantes] = useState<FirmanteAutorizado[]>([])
  const [firmanteId, setFirmanteId] = useState<string>('')
  useEffect(() => {
    getFirmantesAutorizados('hermeticidad')
      .then((fs) => { setFirmantes(fs); if (fs.length === 1) setFirmanteId(fs[0].id) })
      .catch(() => {})
  }, [])
  const firmante = firmantes.find((f) => f.id === firmanteId) ?? null
  const soyElFirmante = !!firmante && !!firma && firmante.nombre === firma.nombre

  // Lo que va impreso viene del perfil del designado. Se muestra, no se edita:
  // el servidor lo resuelve igual, y un campo editable que se ignora es una
  // mentira en pantalla.
  useEffect(() => {
    if (!firmante) return
    setV((p) => ({
      ...p,
      firmante_nombre: firmante.nombre ?? '',
      firmante_cargo:  firmante.cargo ?? '',
      firmante_titulo: firmante.titulo ?? p.firmante_titulo ?? '',
    }))
  }, [firmante])

  async function cargarFirma(file: File) {
    setSubiendoFirma(true)
    try {
      await guardarMiFirmaDesdeArchivo(file)
      setFirma(await getMiFirma())
      toast.success('Firma guardada. Va a salir en los certificados que emitas.')
    } catch (e) {
      toast.error((e as Error).message)
    } finally { setSubiendoFirma(false) }
  }

  const meses = previos?.meses_vigencia ?? 6
  const vence = sumarMeses(fechaPrueba, meses)
  const faltan = OBLIGATORIOS_HERMETICIDAD.filter((k) => !(v[k] ?? '').trim())

  const emitir = async () => {
    setBusy(true)
    try {
      const [fi, ft] = await Promise.all([
        fotos.inicio ? subirFotoCertificado(activoId, 'inicio', fotos.inicio) : Promise.resolve(null),
        fotos.termino ? subirFotoCertificado(activoId, 'termino', fotos.termino) : Promise.resolve(null),
      ])
      const r = await emitirCertificado({
        ...v, activo_id: activoId, tipo: 'hermeticidad',
        fecha_prueba: fechaPrueba, informe,
        foto_inicio_url: fi, foto_termino_url: ft,
        // [MIG469] Sólo se dice A QUIÉN se le pide firmar. El nombre, el cargo
        // y la firma los resuelve el servidor desde su perfil, y los congela con
        // el certificado. Lo que mandemos acá en esos campos se ignora.
        firmante_id: firmanteId || null,
      })
      toast.success(`Certificado Nº ${r.folio} emitido — vence el ${r.fecha_vencimiento}`)
      // Se baja al toque: quien lo emitió lo necesita ahora, no después.
      try {
        const completo = await getCertificadoEmitido(r.id)
        await descargarCertificadoHermeticidad(completo, LOGO)
      } catch {
        toast.error('El certificado quedó emitido, pero el PDF no se pudo generar. Se puede descargar desde el equipo.')
      }
      onListo()
    } catch (e) {
      toast.error((e as Error).message)
    } finally { setBusy(false) }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4" onClick={onClose}>
      <div className="my-6 w-full max-w-3xl rounded-xl bg-white p-5 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="flex items-center gap-2 text-base font-bold">
          <FileCheck2 className="h-5 w-5 text-teal-700" /> Emitir certificado de hermeticidad
        </h3>
        <p className="mt-0.5 text-xs text-gray-500">{patente}</p>

        {!previos ? (
          <div className="py-10 text-center"><Loader2 className="mx-auto h-5 w-5 animate-spin text-gray-400" /></div>
        ) : (
          <>
            <p className={`mt-3 rounded p-2 text-[11px] ${previos.hay_anterior
              ? 'bg-teal-50 text-teal-800' : 'bg-amber-50 text-amber-800'}`}>
              {previos.hay_anterior
                ? <>Los datos del estanque vienen del certificado anterior de este camión ({previos.folio_anterior}).
                    Revisa lo de abajo sólo si algo cambió.</>
                : <>Es el primer certificado que emite el sistema para este camión: hay que llenar los datos
                    del estanque una vez. Los siguientes se abren con estos mismos.</>}
            </p>

            {/* ── Lo que cambia en cada prueba ─────────────────────────────── */}
            <div className="mt-4 rounded-lg border border-gray-300 p-3">
              <p className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500">
                La prueba
              </p>
              <div className="grid gap-3 sm:grid-cols-3">
                <div>
                  <label className="text-xs font-medium text-gray-600">Fecha de la prueba</label>
                  <input type="date" value={fechaPrueba} max={hoyISO()}
                         onChange={(e) => setFechaPrueba(e.target.value)}
                         className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
                </div>
                <div className="sm:col-span-2">
                  <label className="text-xs font-medium text-gray-600">Resultado</label>
                  <input value={informe} onChange={(e) => setInforme(e.target.value)}
                         className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
                </div>
              </div>
              <p className="mt-2 rounded bg-gray-50 px-2 py-1.5 text-[11px] text-gray-600">
                Vence el <b>{vence || '—'}</b> — {meses} meses desde la prueba. No se escribe a mano:
                lo calcula el sistema.
              </p>
            </div>

            {/* ── Control fotográfico ──────────────────────────────────────── */}
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              {(['inicio', 'termino'] as const).map((m) => (
                <div key={m} className="rounded-lg border p-3">
                  <label className="flex items-center gap-1.5 text-xs font-semibold text-gray-700">
                    <Camera className="h-3.5 w-3.5" /> Foto de {m === 'inicio' ? 'inicio' : 'término'}
                  </label>
                  <input type="file" accept="image/*" capture="environment"
                         onChange={(e) => setFotos((p) => ({ ...p, [m]: e.target.files?.[0] ?? null }))}
                         className="mt-1.5 w-full text-[11px]" />
                  {fotos[m] && <p className="mt-1 text-[11px] text-green-700">{fotos[m]!.name}</p>}
                </div>
              ))}
            </div>

            {/* ── Todo lo demás, plegado ───────────────────────────────────── */}
            <div className="mt-3 space-y-1.5">
              {GRUPOS_HERMETICIDAD.map((g) => {
                const abierta = abierto === g.titulo
                const faltanAqui = g.campos.filter(
                  (c) => OBLIGATORIOS_HERMETICIDAD.includes(c.k) && !(v[c.k] ?? '').trim()).length
                return (
                  <div key={g.titulo} className="rounded-lg border">
                    <button type="button" onClick={() => setAbierto(abierta ? null : g.titulo)}
                      className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm font-medium hover:bg-gray-50">
                      {abierta ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                      {g.titulo}
                      {faltanAqui > 0 && (
                        <span className="rounded-full bg-red-100 px-1.5 text-[10px] font-bold text-red-700">
                          falta {faltanAqui}
                        </span>
                      )}
                    </button>
                    {abierta && (
                      <div className="border-t p-3">
                        {g.nota && <p className="mb-2 text-[11px] text-gray-500">{g.nota}</p>}
                        {g.titulo === 'Quién firma' && (
                          <div className="mb-3 rounded-lg border border-gray-200 bg-gray-50 p-2.5">
                            <p className="text-[11px] font-semibold text-gray-700">
                              Quién firma este certificado
                            </p>
                            {firmantes.length === 0 ? (
                              <p className="mt-0.5 text-[11px] text-amber-800">
                                No hay nadie designado para firmar certificados de hermeticidad:
                                va a salir con la línea en blanco para firmar a mano.
                              </p>
                            ) : (
                              <>
                                <select value={firmanteId} onChange={(e) => setFirmanteId(e.target.value)}
                                        className="mt-1 w-full rounded border border-gray-300 bg-white px-2 py-1.5 text-sm">
                                  <option value="">— Se firma a mano —</option>
                                  {firmantes.map((f) => (
                                    <option key={f.id} value={f.id}>
                                      {f.nombre}{f.cargo ? ' · ' + f.cargo : ''}
                                      {f.tiene_firma ? '' : ' (sin firma cargada)'}
                                    </option>
                                  ))}
                                </select>
                                <p className="mt-1 text-[10px] text-gray-500">
                                  Puedes emitirlo tú y que lo firme otra persona. El nombre, el cargo
                                  y la firma salen de su perfil — no se escriben acá.
                                </p>
                              </>
                            )}

                            {firmante && !firmante.tiene_firma && (
                              <p className="mt-1.5 text-[11px] text-amber-800">
                                {firmante.nombre} todavía no tiene firma cargada: el certificado va a
                                salir con la línea en blanco.
                              </p>
                            )}

                            {firmante?.firma_url ? (
                              <>
                                {/* eslint-disable-next-line @next/next/no-img-element */}
                                <img src={firmante.firma_url} alt="Firma"
                                     className="mt-1.5 h-14 bg-white object-contain px-2" />
                                <p className="mt-0.5 text-[10px] text-gray-500">
                                  Va a salir sobre la línea del certificado.
                                </p>
                              </>
                            ) : null}

                            {(soyElFirmante || !firmanteId) && (
                              <>
                                <label className="mt-1.5 inline-flex cursor-pointer items-center gap-1.5 text-[11px] font-medium text-blue-700">
                                  <input type="file" accept="image/*" className="hidden"
                                         disabled={subiendoFirma}
                                         onChange={(e) => {
                                           const f = e.target.files?.[0]
                                           if (f) cargarFirma(f)
                                           e.target.value = ''
                                         }} />
                                  {subiendoFirma ? 'Guardando…'
                                    : firma?.firma_url ? 'Cambiar mi firma' : 'Subir mi firma'}
                                </label>
                                <p className="mt-1 text-[10px] text-gray-500">
                                  PNG con fondo transparente o una foto de la firma sobre hoja blanca.
                                  Queda guardada en tu perfil, no en este certificado.
                                </p>
                              </>
                            )}
                          </div>
                        )}
                        <div className="grid gap-2.5 sm:grid-cols-2">
                          {g.campos.map((c) => (
                            <div key={c.k} className={c.ancho === 'full' ? 'sm:col-span-2' : ''}>
                              <label className="text-[11px] font-medium text-gray-600">
                                {c.label}
                                {OBLIGATORIOS_HERMETICIDAD.includes(c.k) && <span className="text-red-600"> *</span>}
                              </label>
                              <input value={v[c.k] ?? ''} placeholder={c.ph}
                                     readOnly={!!firmante && c.k.startsWith('firmante_')}
                                     onChange={(e) => setV((p) => ({ ...p, [c.k]: e.target.value }))}
                                     className={`mt-0.5 w-full rounded border px-2 py-1 text-sm ${firmante && c.k.startsWith("firmante_") ? "bg-gray-100 text-gray-600" : ""}`} />
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>

            {faltan.length > 0 && (
              <p className="mt-3 rounded border border-red-200 bg-red-50 p-2 text-[11px] text-red-700">
                Falta llenar: {faltan.join(', ')}. Sin eso el certificado no dice nada.
              </p>
            )}

            <div className="mt-4 flex items-center justify-end gap-2">
              <Button variant="outline" onClick={onClose}>Cancelar</Button>
              <Button disabled={busy || faltan.length > 0 || !fechaPrueba} onClick={emitir}>
                {busy && <Loader2 className="mr-1 h-4 w-4 animate-spin" />}
                Emitir y descargar
              </Button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
