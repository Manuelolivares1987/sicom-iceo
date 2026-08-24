'use client'

// ============================================================================
// El momento cero de la faena (MIG378)
// ----------------------------------------------------------------------------
// Antes de que el sistema pueda decir nada sobre litros, alguien tiene que
// declarar con qué se parte. Hasta hoy los siete estanques mostraban números
// sembrados por una migración: nadie los varilló nunca.
//
// SE HACE UNA VEZ Y NO SE PISA
// De acá en adelante todo se compara contra esto, así que la pantalla lo trata
// como lo que es: un acto único. Los estanques ya declarados salen bloqueados
// con su fecha y quién los midió, y no se vuelven a preguntar.
//
// CERO ES UNA RESPUESTA
// El LCSX-78 está vacío. Un estanque vacío hay que declararlo igual —si no,
// queda sin ancla y su primer movimiento no tendrá contra qué contrastarse—.
// Por eso el campo parte vacío pero cero se acepta, y lo que no se acepta es
// dejarlo en blanco.
//
// LA FOTO NO ES ADORNO
// Es el respaldo de una cifra que va a ordenar el control de todo un contrato.
// Si no se puede sacar, hay que escribir por qué. Ninguna de las dos es opcional.
// ============================================================================

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Ruler, Camera, Loader2, ChevronLeft, Check, Lock, AlertTriangle, X,
} from 'lucide-react'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import {
  getFaenaPorCodigo, getEstanquesFaena, declararMomentoCero, subirFotoMedidor,
  FAENA_ROMERAL, type EstanqueFaena,
} from '@/lib/services/combustible-faena'
import { cn } from '@/lib/utils'

type Lectura = {
  litros: string
  cm: string
  foto: { file: File; url: string } | null
  sinFoto: string
}

export default function MomentoCeroPage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const router = useRouter()
  const toast = useToast()

  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [estanques, setEstanques] = useState<EstanqueFaena[]>([])
  const [cargando, setCargando] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [fecha, setFecha] = useState(() => new Date().toISOString().slice(0, 10))
  const [medidoPor, setMedidoPor] = useState('')
  const [lecturas, setLecturas] = useState<Record<string, Lectura>>({})
  const [firma, setFirma] = useState('')
  const [obs, setObs] = useState('')
  const [guardando, setGuardando] = useState(false)

  useEffect(() => {
    if (perfil?.nombre_completo && !medidoPor) setMedidoPor(perfil.nombre_completo)
  }, [perfil, medidoPor])

  useEffect(() => {
    let cancel = false
    ;(async () => {
      try {
        const f = await getFaenaPorCodigo(FAENA_ROMERAL)
        if (!f) throw new Error('No se encontró la faena Romeral')
        const es = await getEstanquesFaena(f.id)
        if (cancel) return
        setFaenaId(f.id)
        setEstanques(es)
      } catch (e) {
        if (!cancel) setError(e instanceof Error ? e.message : 'No se pudo cargar')
      } finally { if (!cancel) setCargando(false) }
    })()
    return () => { cancel = true }
  }, [])

  const pendientes = useMemo(() => estanques.filter((e) => !e.tiene_momento_cero), [estanques])
  const yaHechos = useMemo(() => estanques.filter((e) => e.tiene_momento_cero), [estanques])

  const VACIA: Lectura = { litros: '', cm: '', foto: null, sinFoto: '' }
  const setL = (id: string, patch: Partial<Lectura>) =>
    setLecturas((l) => ({ ...l, [id]: { ...VACIA, ...l[id], ...patch } }))

  // Cada estanque pendiente necesita su lectura y su respaldo. Se valida acá y
  // no al apretar el botón: quien mide tiene que ver qué le falta mientras mide.
  const faltaEn = (e: EstanqueFaena): string | null => {
    const l = lecturas[e.id]
    if (!l || l.litros.trim() === '') return 'falta la lectura'
    const n = Number(l.litros.replace(',', '.'))
    if (!Number.isFinite(n) || n < 0) return 'la lectura no es un número'
    if (e.capacidad_lt != null && n > Number(e.capacidad_lt)) {
      return `no le caben ${n.toLocaleString('es-CL')} L`
    }
    if (!l.foto && l.sinFoto.trim().length < 5) return 'falta la foto de la varilla'
    return null
  }

  const problemas = pendientes.map((e) => ({ e, falta: faltaEn(e) })).filter((x) => x.falta)
  const listo = pendientes.length > 0 && problemas.length === 0
    && medidoPor.trim().length >= 3 && !!firma && !guardando

  const guardar = async () => {
    if (!listo || !faenaId) return
    setGuardando(true)
    try {
      // Las fotos suben antes: si una falla, no se declara un momento cero a
      // medias que después no se puede repetir.
      const puntos = []
      for (const e of pendientes) {
        const l = lecturas[e.id]
        let fotoUrl: string | null = null
        if (l.foto) fotoUrl = await subirFotoMedidor(l.foto.file)
        puntos.push({
          estanque_id: e.id,
          litros: Number(l.litros.replace(',', '.')),
          lectura_cm: l.cm.trim() ? Number(l.cm.replace(',', '.')) : null,
          foto_url: fotoUrl,
          sin_foto_motivo: fotoUrl ? null : l.sinFoto.trim(),
        })
      }
      const firmaUrl = await subirFotoMedidor(await (await fetch(firma)).blob())

      const r = await declararMomentoCero({
        faenaId, fecha, medidoPor: medidoPor.trim(), puntos,
        firmaUrl, observacion: obs.trim() || null,
        clientUuid: crypto.randomUUID(),
      })
      toast.success(
        r.faltan.length > 0
          ? `${r.declarados} estanque(s) declarados. Quedan sin declarar: ${r.faltan.join(', ')}.`
          : `Momento cero cerrado: los ${r.declarados} estanques quedaron anclados.`,
      )
      router.push('/m/romeral')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo guardar')
      setGuardando(false)
    }
  }

  if (cargando) {
    return <div className="flex min-h-[60vh] items-center justify-center">
      <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
    </div>
  }
  if (error) {
    return <div className="p-4 text-center text-sm text-red-600">{error}</div>
  }

  return (
    <div className="space-y-3 p-3 pb-24">
      <div className="flex items-center gap-2">
        <Link href="/m/romeral" className="rounded-lg border border-gray-300 p-2">
          <ChevronLeft className="h-4 w-4 text-gray-600" />
        </Link>
        <div className="min-w-0 flex-1">
          <h1 className="text-base font-bold text-gray-900">Momento cero</h1>
          <p className="text-[11px] text-gray-500">Con qué parte la faena. Se declara una vez.</p>
        </div>
      </div>

      {pendientes.length === 0 ? (
        <div className="rounded-xl border-2 border-green-300 bg-green-50 p-4 text-center">
          <Check className="mx-auto h-8 w-8 text-green-600" />
          <p className="mt-2 text-sm font-bold text-green-900">Ya está declarado</p>
          <p className="mt-1 text-xs text-green-800">
            Los {yaHechos.length} estanques tienen su punto de partida. De acá en adelante el
            control lo lleva el cierre con varilla.
          </p>
          <Link href="/m/romeral"
                className="mt-3 inline-block rounded-lg bg-green-700 px-4 py-2 text-xs font-bold text-white">
            Volver
          </Link>
        </div>
      ) : (
        <>
          <p className="rounded-lg bg-blue-50 p-2.5 text-[11px] leading-snug text-blue-900">
            Varille cada estanque y anote los litros. Un estanque vacío se declara con 0 — también
            necesita su punto de partida. Esto no se puede repetir después.
          </p>

          <div className="grid grid-cols-2 gap-2">
            <label className="block">
              <span className="text-[11px] font-bold text-gray-700">Fecha</span>
              <input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)}
                     className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
            </label>
            <label className="block">
              <span className="text-[11px] font-bold text-gray-700">¿Quién midió?</span>
              <input value={medidoPor} onChange={(e) => setMedidoPor(e.target.value)}
                     placeholder="Nombre y apellido"
                     className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
            </label>
          </div>

          {pendientes.map((e) => (
            <FilaEstanque key={e.id} e={e} l={lecturas[e.id]} falta={faltaEn(e)}
                          onChange={(patch) => setL(e.id, patch)} />
          ))}

          {yaHechos.length > 0 && (
            <div className="rounded-lg border border-gray-200 bg-gray-50 p-2.5">
              <p className="flex items-center gap-1.5 text-[11px] font-bold text-gray-600">
                <Lock className="h-3.5 w-3.5" /> Ya declarados
              </p>
              <div className="mt-1 space-y-0.5">
                {yaHechos.map((e) => (
                  <p key={e.id} className="text-[11px] text-gray-500">
                    <span className="font-semibold text-gray-700">{e.codigo}</span>
                    {' · '}{Number(e.momento_cero_litros ?? 0).toLocaleString('es-CL')} L
                    {e.momento_cero_medido_por ? ` · ${e.momento_cero_medido_por}` : ''}
                  </p>
                ))}
              </div>
            </div>
          )}

          <label className="block">
            <span className="text-[11px] font-bold text-gray-700">
              Observación <span className="font-normal text-gray-400">— opcional</span>
            </span>
            <input value={obs} onChange={(e) => setObs(e.target.value)}
                   placeholder="Quién acompañó la medición, condiciones"
                   className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
          </label>

          <SignaturePad label="Firma de quien certifica (obligatoria)" onCapture={setFirma} />

          {problemas.length > 0 && (
            <div className="rounded-lg border border-amber-300 bg-amber-50 p-2.5">
              <p className="flex items-center gap-1.5 text-[11px] font-bold text-amber-900">
                <AlertTriangle className="h-3.5 w-3.5" /> Falta completar
              </p>
              {problemas.map(({ e, falta }) => (
                <p key={e.id} className="text-[11px] text-amber-800">{e.codigo}: {falta}</p>
              ))}
            </div>
          )}

          <button onClick={guardar} disabled={!listo}
                  className="flex w-full items-center justify-center gap-2 rounded-xl bg-gray-900 px-4 py-3 text-sm font-bold text-white disabled:opacity-40">
            {guardando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Ruler className="h-4 w-4" />}
            Declarar el momento cero de {pendientes.length} estanque{pendientes.length === 1 ? '' : 's'}
          </button>
          {!listo && !guardando && (
            <p className="text-center text-[11px] text-gray-500">
              {problemas.length > 0 ? 'Complete las lecturas de arriba.'
                : medidoPor.trim().length < 3 ? 'Falta el nombre de quien midió.'
                : !firma ? 'Falta la firma.' : ''}
            </p>
          )}
        </>
      )}
    </div>
  )
}

function FilaEstanque({ e, l, falta, onChange }: {
  e: EstanqueFaena
  l: Lectura | undefined
  falta: string | null
  onChange: (p: Partial<Lectura>) => void
}) {
  const lec = l ?? { litros: '', cm: '', foto: null, sinFoto: '' }
  const esCamion = e.tipo === 'movil'

  return (
    <div className={cn('rounded-xl border-2 bg-white p-2.5',
      falta ? 'border-gray-200' : 'border-green-400')}>
      <div className="flex items-center gap-2">
        <span className="text-sm font-bold text-gray-900">{e.patente ?? e.codigo}</span>
        <span className="min-w-0 flex-1 truncate text-[11px] text-gray-500">{e.nombre}</span>
        <span className="shrink-0 rounded bg-gray-100 px-1.5 py-0.5 text-[10px] font-semibold text-gray-600">
          {esCamion ? 'camión' : 'estación'} · {Number(e.capacidad_lt ?? 0).toLocaleString('es-CL')} L
        </span>
      </div>

      <div className="mt-2 grid grid-cols-2 gap-2">
        <label className="block">
          <span className="text-[10px] font-bold text-gray-600">Litros (0 si está vacío)</span>
          <input value={lec.litros} inputMode="decimal"
                 onChange={(ev) => onChange({ litros: ev.target.value.replace(/[^\d.,]/g, '') })}
                 placeholder="0"
                 className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-right text-base font-bold tabular-nums" />
        </label>
        <label className="block">
          <span className="text-[10px] font-bold text-gray-600">
            Varilla cm <span className="font-normal text-gray-400">— opcional</span>
          </span>
          <input value={lec.cm} inputMode="decimal"
                 onChange={(ev) => onChange({ cm: ev.target.value.replace(/[^\d.,]/g, '') })}
                 className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-right text-sm tabular-nums" />
        </label>
      </div>

      <div className="mt-2">
        {lec.foto ? (
          <div className="flex items-center gap-2 rounded-lg border border-green-300 bg-green-50 p-1.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={lec.foto.url} alt="varilla" className="h-12 w-12 rounded object-cover" />
            <span className="flex-1 text-[11px] font-semibold text-green-800">Foto tomada</span>
            <button type="button" onClick={() => onChange({ foto: null })}
                    aria-label="Quitar foto" className="text-green-700">
              <X className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <>
            <label className="flex items-center justify-center gap-2 rounded-lg border-2 border-dashed border-gray-300 py-2.5 text-xs font-semibold text-gray-600">
              <Camera className="h-4 w-4" /> Foto de la varilla
              <input type="file" accept="image/*" capture="environment" className="hidden"
                     onChange={(ev) => {
                       const f = ev.target.files?.[0]
                       if (f) onChange({ foto: { file: f, url: URL.createObjectURL(f) }, sinFoto: '' })
                     }} />
            </label>
            <input value={lec.sinFoto} onChange={(ev) => onChange({ sinFoto: ev.target.value })}
                   placeholder="…o escriba por qué no hay foto"
                   className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-1.5 text-xs" />
          </>
        )}
      </div>
    </div>
  )
}
