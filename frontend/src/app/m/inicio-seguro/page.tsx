'use client'

// Bandeja del Inicio Seguro (MIG735): Hersaly revisa cuadrilla, ART, controles
// críticos y fotos de bloqueo, y da el visto bueno (o pide corregir).
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, CheckCircle2, Hand, Loader2, ShieldCheck, XCircle } from 'lucide-react'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { BotonSalir } from '@/components/layout/boton-salir'
import { useToast } from '@/contexts/toast-context'
import { nombreEnergia } from '@/lib/inicio-seguro/psgcc'
import { decidirInicio, getBandejaInicio, soyAprobador, type InicioSeguro } from '@/lib/services/inicio-seguro'

const hora = (iso: string | null) => iso
  ? new Date(iso).toLocaleString('es-CL', { timeZone: 'America/Santiago', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
  : ''

const ETIQUETA: Record<string, { t: string; c: string }> = {
  pendiente: { t: 'Esperando', c: 'bg-blue-100 text-blue-800' },
  aprobado: { t: 'Aprobado', c: 'bg-emerald-100 text-emerald-800' },
  rechazado: { t: 'Corregir', c: 'bg-red-100 text-red-800' },
  detenido: { t: 'Detenido', c: 'bg-red-600 text-white' },
  cerrado: { t: 'Cerrado', c: 'bg-gray-200 text-gray-700' },
}

function Tarjeta({ s, puedeDecidir }: { s: InicioSeguro; puedeDecidir: boolean }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [abierta, setAbierta] = useState(s.estado === 'pendiente')
  const [comentario, setComentario] = useState('')
  const [enviando, setEnviando] = useState(false)
  const avisos = s.cuadrilla.filter((c) => !c.habilitado)
  const minutos = Math.floor((Date.now() - new Date(s.solicitado_at).getTime()) / 60000)

  async function decidir(aprobar: boolean) {
    setEnviando(true)
    try {
      await decidirInicio(s.id, aprobar, comentario)
      toast.success(aprobar ? 'Visto bueno dado: ya pueden iniciar' : 'Devuelto para corregir')
      qc.invalidateQueries({ queryKey: ['inicio-seguro-bandeja'] })
    } catch (e) { toast.error((e as Error).message) } finally { setEnviando(false) }
  }

  const et = ETIQUETA[s.estado]
  return (
    <article className={`rounded-xl border bg-white p-3 ${s.estado === 'pendiente' ? 'border-blue-400' : 'border-gray-200'}`} data-testid="tarjeta-inicio">
      <button type="button" onClick={() => setAbierta((v) => !v)} className="w-full text-left" aria-expanded={abierta}>
        <div className="flex items-start gap-2">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-gray-900">{s.instalacion}</p>
            <p className="text-xs text-gray-600">{s.faena} · {s.solicitado_por_nombre} · {hora(s.solicitado_at)}</p>
          </div>
          <span className={`shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold ${et.c}`}>
            {et.t}{s.estado === 'pendiente' ? ` · ${minutos} min` : ''}
          </span>
        </div>
        <p className="mt-1 text-sm text-gray-800">{s.tarea}</p>
      </button>

      {abierta && (
        <div className="mt-3 space-y-3 text-sm">
          {s.estado === 'detenido' && (
            <p className="flex items-start gap-1.5 rounded-lg bg-red-50 p-2 text-red-800"><Hand className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />{s.detenido_motivo}</p>
          )}
          <div>
            <p className="text-xs font-bold uppercase text-gray-600">Cuadrilla</p>
            <ul className="mt-1 space-y-0.5">
              {s.cuadrilla.map((c) => (
                <li key={c.personal_id}>
                  {c.nombre}{!c.leyo_art && <span className="text-red-700"> · no confirmó la ART</span>}
                  {!c.habilitado && <span className="block text-xs text-amber-700">Aviso: falta {c.pendientes.join(', ') || 'requisito'}</span>}
                </li>
              ))}
            </ul>
            {avisos.length > 0 && <p className="mt-1 text-xs text-amber-700">{avisos.length} con cursos o requisitos pendientes (solo aviso).</p>}
          </div>

          <div>
            <p className="text-xs font-bold uppercase text-gray-600">Bloqueos</p>
            {s.bloqueos.length === 0
              ? <p className="mt-1 rounded-lg bg-amber-50 p-2 text-amber-900">Sin bloqueo: {s.sin_bloqueo_motivo}</p>
              : s.bloqueos.map((b, i) => (
                <div key={i} className="mt-1">
                  <p className="text-xs font-semibold text-gray-700">{nombreEnergia(b.energia)} · {b.punto}</p>
                  <div className="mt-1 grid grid-cols-2 gap-2">
                    {[[b.foto_bloqueo, 'Candado y tarjeta'], [b.foto_energia_cero, 'Energía cero']].map(([u, t]) => (
                      <a key={t} href={u} target="_blank" rel="noreferrer" className="relative block">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={u} alt={`${t} — ${b.punto}`} loading="lazy" width={320} height={112} className="h-28 w-full rounded-lg object-cover" />
                        <span className="absolute left-1 top-1 rounded bg-black/60 px-1 text-[10px] text-white">{t}</span>
                      </a>
                    ))}
                  </div>
                </div>
              ))}
          </div>

          <details>
            <summary className="min-h-11 cursor-pointer py-2 text-xs font-bold uppercase text-gray-600">
              Controles críticos ({s.psgcc.length}) {s.psgcc.some((p) => p.respuesta === 'no') && '· HAY UN NO'}
            </summary>
            <ul className="space-y-1">
              {s.psgcc.map((p) => (
                <li key={p.control} className="text-xs">
                  <b className={p.respuesta === 'si' ? 'text-emerald-700' : p.respuesta === 'no' ? 'text-red-700' : 'text-gray-600'}>
                    {p.respuesta === 'si' ? 'Sí' : p.respuesta === 'no' ? 'No' : 'N/A'}
                  </b> · {p.pregunta}
                </li>
              ))}
            </ul>
          </details>

          <details>
            <summary className="min-h-11 cursor-pointer py-2 text-xs font-bold uppercase text-gray-600">
              ART {s.art?.asistida ? '(armada con el copiloto)' : ''}
            </summary>
            <p className="whitespace-pre-wrap text-xs text-gray-800">{s.art?.texto}</p>
          </details>

          {s.estado === 'pendiente' && puedeDecidir && (
            <div className="space-y-2 border-t border-gray-100 pt-3">
              <textarea value={comentario} onChange={(e) => setComentario(e.target.value)} rows={2}
                        aria-label="Comentario" placeholder="Comentario (obligatorio para pedir corrección)…"
                        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
              <div className="grid grid-cols-2 gap-2">
                <button type="button" onClick={() => decidir(false)} disabled={enviando}
                        className="flex min-h-12 items-center justify-center gap-1 rounded-lg border-2 border-red-500 text-sm font-bold text-red-700 disabled:opacity-40">
                  <XCircle className="h-4 w-4" aria-hidden="true" /> Corregir
                </button>
                <button type="button" onClick={() => decidir(true)} disabled={enviando}
                        className="flex min-h-12 items-center justify-center gap-1 rounded-lg bg-emerald-700 text-sm font-bold text-white disabled:opacity-40">
                  {enviando ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <CheckCircle2 className="h-4 w-4" aria-hidden="true" />} Visto bueno
                </button>
              </div>
            </div>
          )}
          {s.decidido_at && <p className="text-xs text-gray-600">Decidido {hora(s.decidido_at)}{s.comentario ? ` · «${s.comentario}»` : ''}</p>}
        </div>
      )}
    </article>
  )
}

export default function BandejaInicioSeguro() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { data: aprobador = false } = useQuery({ queryKey: ['inicio-seguro-aprobador'], queryFn: soyAprobador, enabled: !verificando })
  const { data = [], isLoading, error } = useQuery({
    queryKey: ['inicio-seguro-bandeja'], queryFn: getBandejaInicio, enabled: !verificando, refetchInterval: 20_000,
  })
  if (sinSesionOffline) return <SinSesionOffline />
  if (verificando) return <div className="flex justify-center py-10"><Spinner /></div>
  const pendientes = data.filter((s) => s.estado === 'pendiente')
  return (
    <div className="mx-auto max-w-[560px]">
      <header className="sticky top-0 z-30 flex items-center gap-2 bg-emerald-700 px-2 py-2 text-white">
        <button type="button" onClick={() => history.back()} aria-label="Volver"
                className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full hover:bg-white/10">
          <ArrowLeft className="h-5 w-5" aria-hidden="true" />
        </button>
        <div className="min-w-0 flex-1">
          <h1 className="flex items-center gap-1.5 text-base font-bold"><ShieldCheck className="h-5 w-5 shrink-0" aria-hidden="true" />Inicio seguro</h1>
          <p className="text-[11px] opacity-90">{pendientes.length ? `${pendientes.length} esperando visto bueno` : 'Sin solicitudes pendientes'}</p>
        </div>
        <BotonSalir className="hover:bg-white/10" aria-hidden="true" />
      </header>
      <main className="space-y-3 p-3">
        {!aprobador && <p className="rounded-lg bg-gray-100 p-2 text-xs text-gray-600">Vista de consulta: el visto bueno lo da el aprobador designado.</p>}
        {isLoading && <div className="flex justify-center py-6"><Spinner /></div>}
        {error && <p className="rounded-lg bg-red-50 p-2 text-sm text-red-700">{(error as Error).message}</p>}
        {!isLoading && data.length === 0 && <p className="py-6 text-center text-sm text-gray-600">No hay solicitudes de los últimos 7 días.</p>}
        {data.map((s) => <Tarjeta key={s.id} s={s} puedeDecidir={aprobador} />)}
      </main>
    </div>
  )
}
