'use client'

// ============================================================================
// El que sube lo que quedó esperando, esté donde esté el mecánico
// ----------------------------------------------------------------------------
// Al probarlo sin señal apareció esto: la cola sólo se vaciaba en la pantalla
// de la jornada. El mecánico que termina la última pauta del día en el patio,
// guarda el teléfono y se va, no la sube hasta que vuelve a abrir esa pantalla
// — y puede ser al día siguiente, o nunca. Lo mismo el conductor con la última
// carga del turno.
//
// Vive en el layout de /m/franke, así que corre en cualquier pantalla de la
// faena. Tres momentos, que son los tres en que hay red y nadie está mirando:
//
//   · al volver la señal
//   · al volver a la app desde segundo plano (el teléfono en el bolsillo con la
//     pantalla apagada no dispara «online»)
//   · cada dos minutos, por si los dos anteriores no ocurrieron
//
// No pinta nada cuando no hay nada que subir. Un aviso permanente de «todo en
// orden» es ruido, y el mecánico deja de mirar la zona donde después aparece el
// que sí importa.
// ============================================================================

import { useCallback, useEffect, useRef, useState } from 'react'
import { CloudOff, CloudUpload } from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { getFaenaId } from '@/lib/services/faena-pauta'
import {
  sincronizar as sincronizarPautas, pendientesCount as pautasPendientes, refrescarSiViejo,
} from '@/lib/offline/faena-pauta-offline'
import {
  sincronizar as sincronizarDespachos, pendientesCount as despachosPendientes,
} from '@/lib/offline/combustible-faena-offline'
import {
  sincronizar as sincronizarBodega, pendientesCount as bodegaPendientes,
} from '@/lib/offline/bodega-faena-offline'
import {
  sincronizar as sincronizarBitacora, pendientesCount as bitacoraPendientes,
} from '@/lib/offline/faena-bitacora-offline'
import {
  sincronizar as sincronizarEntrega, pendientesCount as entregaPendientes,
} from '@/lib/offline/faena-entrega-offline'
// [F3] Bandeja única (carga del camión y lo que venga) + movimientos de despacho
// + todo lo de la faena bajado al teléfono.
import { sincronizarBandeja, contarBandeja, EVENTO_BANDEJA } from '@/lib/offline/bandeja'
import '@/lib/offline/franke-carga'
import { sincronizarMovimientos, movimientosPendientesCount } from '@/lib/offline/combustible-faena-offline'
import { precargarFaena } from '@/lib/offline/franke-precarga'
import Link from 'next/link'

export function SincronizadorFranke() {
  const online = useNetworkStatus()
  const toast = useToast()
  const [pendientes, setPendientes] = useState(0)
  const [subiendo, setSubiendo] = useState(false)
  // Sin esto, dos disparos casi simultáneos —volver la señal y volver a la
  // app— intentan subir la misma pauta dos veces.
  const enCurso = useRef(false)

  const contar = useCallback(async () => {
    try {
      setPendientes((await pautasPendientes()) + (await despachosPendientes()) + (await bodegaPendientes()) + (await bitacoraPendientes())
        + (await entregaPendientes()) + (await contarBandeja()) + (await movimientosPendientesCount()))
    } catch { /* IndexedDB no disponible: no es motivo para romper la pantalla */ }
  }, [])

  const subir = useCallback(async (avisar: boolean) => {
    if (enCurso.current || !navigator.onLine) return
    enCurso.current = true
    setSubiendo(true)
    try {
      // [MIG694] La bodega de faena también sube su cola desde acá.
      // [MIG696] Y la bitácora del turno.
      const [a, b, c, d, e, f, g] = await Promise.all([sincronizarPautas(), sincronizarDespachos(), sincronizarBodega(), sincronizarBitacora(),
        sincronizarEntrega(), sincronizarBandeja(), sincronizarMovimientos()])
      const ok = a.ok + b.ok + c.ok + d.ok + e.ok + f + g.ok
      if (c.rechazadas > 0) toast.error(`${c.rechazadas} registro(s) de bodega no se aceptaron: revíselos en Bodega.`)
      if (ok > 0 && avisar) {
        toast.success(`Volvió la señal: se subieron ${ok} registro(s) que estaban esperando.`)
      }
      await contar()
    } catch { /* se reintenta en el próximo disparo */ }
    finally { enCurso.current = false; setSubiendo(false) }
  }, [toast, contar])

  useEffect(() => { void contar() }, [contar])

  useEffect(() => {
    if (online) void subir(true)
  }, [online, subir])

  // [MIG721] Las pautas del teléfono al día: con señal y si lo bajado tiene
  // más de 6 h, se vuelve a bajar en silencio (no reemplaza lo que el
  // mecánico tiene a medio llenar: eso vive en su borrador).
  useEffect(() => {
    if (!online) return
    // [F3] Antes solo las pautas; ahora todo lo de la faena (cada 30 min).
    void precargarFaena().catch(() => undefined)
  }, [online])

  // La cuenta se actualiza apenas algo entra o sale de la bandeja.
  useEffect(() => {
    const al = () => { void contar() }
    window.addEventListener(EVENTO_BANDEJA, al)
    return () => window.removeEventListener(EVENTO_BANDEJA, al)
  }, [contar])

  useEffect(() => {
    // El teléfono en el bolsillo con la pantalla apagada no dispara «online»:
    // la señal vuelve y el aparato no se entera hasta que alguien lo mira.
    const alVolver = () => {
      if (document.visibilityState !== 'visible') return
      void subir(true)
      void precargarFaena().catch(() => undefined)
    }
    document.addEventListener('visibilitychange', alVolver)
    const cada2min = setInterval(() => void subir(false), 120_000)
    // La cuenta se refresca aparte y más seguido: lo que encola es OTRA
    // pantalla, y sin esto el aviso no aparecía hasta el siguiente intento de
    // subida. El mecánico guardaba sin señal y no veía nada.
    const cada10s = setInterval(() => void contar(), 10_000)
    return () => {
      document.removeEventListener('visibilitychange', alVolver)
      clearInterval(cada2min)
      clearInterval(cada10s)
    }
  }, [subir, contar])

  if (pendientes === 0) return null

  // Un toque: a «Pendientes», donde se ve qué espera y por qué.
  return (
    <Link
      href="/m/franke/pendientes"
      onClick={() => { if (online) void subir(true) }}
      className="fixed bottom-20 left-3 z-40 flex items-center gap-2 rounded-full border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-bold text-amber-900 shadow-lg disabled:opacity-70"
    >
      {online
        ? <CloudUpload className={subiendo ? 'h-4 w-4 animate-pulse' : 'h-4 w-4'} />
        : <CloudOff className="h-4 w-4" />}
      {subiendo
        ? 'Subiendo…'
        : online
          ? `Subir ${pendientes}`
          : `${pendientes} sin subir`}
    </Link>
  )
}
