'use client'

// Firma remota (MIG276/277) — página PÚBLICA, sin sesión.
// El informe lleva DOS firmas y cada una tiene su propio link: la del técnico
// que ejecutó (Pillado) y la de quien recibe conforme por ESM/ENEX. Quien abre
// el link revisa la pauta y las fotos del antes y después, y firma con el dedo.
// Solo la firma del mandante cierra el servicio para el contrato.

import { useCallback, useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { CheckCircle2, AlertTriangle, Camera, ClipboardList, MessageSquareWarning } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { getDatosFirma, registrarFirmaRemota, type EnexFirmaDatos } from '@/lib/services/enex'

const RESULTADO: Record<string, { txt: string; cls: string }> = {
  ok: { txt: 'Conforme', cls: 'bg-green-100 text-green-700' },
  no_ok: { txt: 'No conforme', cls: 'bg-red-100 text-red-700' },
  na: { txt: 'No aplica', cls: 'bg-gray-100 text-gray-500' },
  si: { txt: 'Sí', cls: 'bg-green-100 text-green-700' },
  no: { txt: 'No', cls: 'bg-red-100 text-red-700' },
}

function fechaCL(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

const MOTIVO: Record<string, string> = {
  no_existe: 'Este link de firma no existe. Pide uno nuevo al planificador.',
  revocado: 'Este link fue anulado. Pide uno nuevo al planificador.',
  vencido: 'Este link venció. Pide uno nuevo al planificador.',
}

export default function FirmaEnexPage() {
  const params = useParams()
  const token = params?.token as string
  const [datos, setDatos] = useState<EnexFirmaDatos | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [nombre, setNombre] = useState('')
  const [firma, setFirma] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [listo, setListo] = useState(false)

  const cargar = useCallback(async () => {
    try { setDatos(await getDatosFirma(token)) }
    catch (e) { setError((e as Error).message) }
  }, [token])

  useEffect(() => { if (token) void cargar() }, [token, cargar])

  async function firmar() {
    if (!nombre.trim()) { setError('Escribe tu nombre'); return }
    if (!firma) { setError('Falta la firma'); return }
    setEnviando(true); setError(null)
    try {
      await registrarFirmaRemota(token, nombre.trim(), firma)
      setListo(true)
    } catch (e) { setError((e as Error).message) } finally { setEnviando(false) }
  }

  if (!datos && !error) return <div className="py-20 text-center text-gray-400"><Spinner /></div>

  if (datos && !datos.ok) {
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <AlertTriangle className="mx-auto h-10 w-10 text-amber-500" />
        <p className="mt-3 text-sm text-gray-700">{MOTIVO[datos.motivo ?? ''] ?? 'El link no es válido.'}</p>
      </div>
    )
  }

  if (listo || datos?.ya_firmado) {
    const esTecnico = datos?.tipo === 'tecnico'
    // Tras firmar, decir si falta la otra parte: son dos firmas distintas y la
    // gente asume que con la suya el informe quedó completo.
    const faltaOtra = esTecnico ? !datos?.firma_mandante_lista : !datos?.firma_tecnico_lista
    return (
      <div className="mx-auto max-w-md px-4 py-16 text-center">
        <CheckCircle2 className="mx-auto h-12 w-12 text-green-600" />
        <h1 className="mt-3 text-lg font-bold text-gray-800">
          {esTecnico ? 'Firma del técnico registrada' : 'Servicio recibido conforme'}
        </h1>
        <p className="mt-1 text-sm text-gray-600">
          {datos?.instalacion} · {fechaCL(datos?.fecha)}
        </p>
        {(listo || datos?.firmante) && (
          <p className="mt-3 text-xs text-gray-500">
            Firmado por {listo ? nombre : datos?.firmante}
            {datos?.firmado_at && !listo ? ` el ${fechaCL(datos.firmado_at)}` : ''}.
          </p>
        )}
        <p className="mt-3 text-xs text-gray-500">
          {faltaOtra
            ? esTecnico
              ? 'Falta la recepción conforme de ESM / ENEX para cerrar el servicio.'
              : 'Falta la firma del técnico ejecutor en el informe.'
            : 'El informe quedó con las dos firmas. No hace falta nada más.'}
        </p>
      </div>
    )
  }

  const d = datos!
  const esTecnico = d.tipo === 'tecnico'
  const acts = d.actividades ?? []
  const conFotos = acts.filter((a) => (a.fotos_antes?.length ?? 0) + (a.fotos_despues?.length ?? 0) > 0)
  const noOk = acts.filter((a) => a.resultado === 'no_ok' || a.resultado === 'no')
  const ds = d.datos_servicio ?? {}
  const reqs = d.requerimientos ?? []
  const pedidos = reqs.filter((r) => r.tipo === 'requerimiento')

  return (
    <div className="mx-auto max-w-2xl px-3 py-5">
      <div className="rounded-xl border border-gray-200 bg-white p-4">
        <p className={`text-[11px] font-semibold uppercase tracking-wide ${
          esTecnico ? 'text-emerald-700' : 'text-blue-700'}`}>
          {esTecnico ? 'Firma del técnico ejecutor — Pillado' : 'Recepción conforme — ENEX / ESM'}
        </p>
        <h1 className="mt-0.5 text-lg font-bold leading-tight text-gray-900">{d.instalacion}</h1>
        <p className="text-sm text-gray-500">
          {d.faena} · {d.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'} · {fechaCL(d.fecha)}
        </p>
        <div className="mt-3 grid grid-cols-2 gap-2 text-xs text-gray-600">
          {ds['DS.HORA_INI'] && <div><span className="text-gray-400">Hora inicio:</span> <b>{ds['DS.HORA_INI']}</b></div>}
          {ds['DS.HORA_FIN'] && <div><span className="text-gray-400">Hora término:</span> <b>{ds['DS.HORA_FIN']}</b></div>}
          {d.tecnico && <div className="col-span-2"><span className="text-gray-400">Técnico:</span> <b>{d.tecnico}</b></div>}
          {ds['DS.RUT_TEC'] && <div className="col-span-2"><span className="text-gray-400">Ejecutores:</span> {ds['DS.RUT_TEC']}</div>}
          {ds['DS.MOTIVO'] && <div className="col-span-2"><span className="text-gray-400">Motivo:</span> {ds['DS.MOTIVO']}</div>}
        </div>
      </div>

      {/* Lo que se hizo */}
      <div className="mt-3 rounded-xl border border-gray-200 bg-white p-4">
        <h2 className="flex items-center gap-1.5 text-sm font-bold text-gray-800">
          <ClipboardList className="h-4 w-4 text-blue-700" /> Trabajo realizado ({acts.length})
        </h2>
        <ul className="mt-2 space-y-1.5">
          {acts.map((a, i) => {
            const r = a.resultado ? RESULTADO[a.resultado] : null
            const na = a.fotos_antes?.length ?? 0, nd = a.fotos_despues?.length ?? 0
            return (
              <li key={i} className="flex items-start gap-2 border-b border-gray-100 pb-1.5 text-xs">
                <span className="font-mono text-[10px] text-gray-400">{a.codigo}</span>
                <span className="flex-1 text-gray-700">
                  {a.descripcion}
                  {a.observacion && <span className="block text-[11px] italic text-gray-500">{a.observacion}</span>}
                  {na + nd > 0 && (
                    <span className="mt-0.5 flex items-center gap-1 text-[10px] text-gray-400">
                      <Camera className="h-3 w-3" /> {na} antes · {nd} después
                    </span>
                  )}
                </span>
                {r && <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${r.cls}`}>{r.txt}</span>}
              </li>
            )
          })}
        </ul>
        {noOk.length > 0 && (
          <p className="mt-2 rounded bg-red-50 p-2 text-[11px] text-red-800">
            <b>{noOk.length} hallazgo(s) no conforme(s):</b>{' '}
            {noOk.map((a) => a.descripcion).join(' · ')}
          </p>
        )}
        {d.observacion && (
          <p className="mt-2 text-[11px] text-gray-600"><span className="text-gray-400">Observación:</span> {d.observacion}</p>
        )}
      </div>

      {/* Evidencia */}
      {conFotos.length > 0 && (
        <div className="mt-3 rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="text-sm font-bold text-gray-800">Evidencia — antes y después</h2>
          {conFotos.map((a, i) => (
            <div key={i} className="mt-3">
              <p className="text-[11px] font-semibold text-gray-700">{a.codigo} · {a.descripcion}</p>
              <div className="mt-1 grid grid-cols-2 gap-2">
                {([['Antes', a.fotos_antes ?? []], ['Después', a.fotos_despues ?? []]] as const).map(([tag, fotos]) => (
                  <div key={tag}>
                    <p className={`rounded px-1.5 py-0.5 text-center text-[10px] font-bold ${
                      tag === 'Antes' ? 'bg-amber-100 text-amber-800' : 'bg-green-100 text-green-800'}`}>
                      {tag} ({fotos.length})
                    </p>
                    <div className="mt-1 flex flex-wrap gap-1">
                      {fotos.length === 0
                        ? <span className="py-2 text-[10px] italic text-gray-400">sin fotos</span>
                        : fotos.map((u, k) => (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img key={k} src={u} alt={`${tag} ${k + 1}`}
                               onClick={() => window.open(u, '_blank')}
                               className="h-16 w-16 cursor-zoom-in rounded border object-cover" />
                        ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
          {(d.evidencia_urls?.length ?? 0) > 0 && (
            <div className="mt-3">
              <p className="text-[11px] font-semibold text-gray-700">Registro complementario</p>
              <div className="mt-1 flex flex-wrap gap-1">
                {(d.evidencia_urls ?? []).map((u, k) => (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img key={k} src={u} alt={`evidencia ${k + 1}`} onClick={() => window.open(u, '_blank')}
                       className="h-16 w-16 cursor-zoom-in rounded border object-cover" />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* [MIG287] Lo que hay que resolver y no se hace en terreno. Va pegado a la
          firma a propósito: es parte de lo que el mandante está recibiendo. */}
      {reqs.length > 0 && (
        <div className="mt-3 rounded-xl border-2 border-amber-300 bg-amber-50/60 p-4">
          <h2 className="flex items-center gap-1.5 text-sm font-bold text-amber-900">
            <MessageSquareWarning className="h-4 w-4" /> Comentarios y requerimientos ({reqs.length})
          </h2>
          <p className="mt-0.5 text-[11px] text-amber-800">
            Detectado durante el servicio y fuera del alcance de esta visita.
          </p>
          <ul className="mt-2 space-y-2">
            {reqs.map((r, i) => (
              <li key={r.id ?? i} className="rounded-lg border border-amber-200 bg-white p-2.5">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold uppercase ${
                    r.tipo === 'requerimiento'
                      ? r.prioridad === 'alta' ? 'bg-red-100 text-red-800'
                        : r.prioridad === 'media' ? 'bg-amber-100 text-amber-800'
                        : 'bg-gray-100 text-gray-600'
                      : 'bg-gray-100 text-gray-600'}`}>
                    {r.tipo === 'requerimiento' ? `Requerimiento · ${r.prioridad}` : 'Comentario'}
                  </span>
                  {r.item_codigo && (
                    <span className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[10px] text-gray-500">
                      Ítem {r.item_codigo}
                    </span>
                  )}
                  {r.plazo && (
                    <span className="text-[10px] font-semibold text-red-700">
                      antes del {fechaCL(r.plazo)}
                    </span>
                  )}
                </div>
                {r.titulo && <p className="mt-1 text-sm font-semibold text-gray-800">{r.titulo}</p>}
                <p className="mt-0.5 whitespace-pre-wrap text-xs text-gray-700">{r.descripcion}</p>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Firma — el texto y el peso cambian según quién esté firmando */}
      <div className={`mt-3 rounded-xl border-2 bg-white p-4 ${
        esTecnico ? 'border-emerald-300' : 'border-blue-300'}`}>
        <h2 className="text-sm font-bold text-gray-800">
          {esTecnico ? 'Firma del técnico ejecutor' : 'Recepción conforme'}
        </h2>
        <p className="mt-0.5 text-[11px] text-gray-500">
          {esTecnico
            ? 'Al firmar, declaras que ejecutaste este trabajo tal como quedó registrado.'
            : 'Al firmar, das por recibido el servicio y queda cumplido para el contrato.'}
        </p>
        {!esTecnico && pedidos.length > 0 && (
          <p className="mt-1 rounded bg-amber-50 p-2 text-[11px] font-semibold text-amber-900">
            También das por informados los {pedidos.length} requerimiento(s) del informe.
          </p>
        )}
        {/* Estado de la otra firma: que nadie asuma que con la suya está listo */}
        <p className="mt-1 text-[11px] text-gray-500">
          {esTecnico
            ? (d.firma_mandante_lista
                ? `ESM / ENEX ya recibió conforme${d.mandante_nombre ? ` (${d.mandante_nombre})` : ''}.`
                : 'Después falta la recepción conforme de ESM / ENEX.')
            : (d.firma_tecnico_lista
                ? `El técnico ejecutor ya firmó${d.tecnico_nombre ? ` (${d.tecnico_nombre})` : ''}.`
                : 'El técnico ejecutor todavía no firma el informe.')}
        </p>
        <input value={nombre} onChange={(e) => setNombre(e.target.value)}
               placeholder={esTecnico ? 'Tu nombre y RUT' : 'Tu nombre y cargo'}
               className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
        <div className="mt-2">
          <SignaturePad label="Firma" onCapture={setFirma} />
        </div>
        {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
        <button onClick={firmar} disabled={enviando || !nombre.trim() || !firma}
                className={`mt-3 w-full rounded-lg py-3 text-sm font-semibold text-white disabled:opacity-50 ${
                  esTecnico ? 'bg-emerald-700' : 'bg-blue-700'}`}>
          {enviando ? 'Enviando…' : esTecnico ? 'Firmar como ejecutor' : 'Firmar y dar por recibido'}
        </button>
      </div>

      <p className="mt-4 text-center text-[10px] text-gray-400">
        SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM
      </p>
    </div>
  )
}
