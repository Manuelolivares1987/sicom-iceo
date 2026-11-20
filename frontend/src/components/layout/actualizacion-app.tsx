'use client'

// ============================================================================
// Actualizaciones «como WhatsApp» (20-11-2026)
// ----------------------------------------------------------------------------
// El service worker ya no toma el control apenas llega una versión nueva
// (skipWaiting: false). La versión nueva se baja ENTERA en segundo plano y
// queda «esperando». Se aplica:
//   · al abrir la app (primeros segundos, antes de que nadie escriba nada), o
//   · cuando la persona toca «Actualizar» en el aviso.
// Si la descarga se corta, la versión instalada sigue funcionando completa: nunca
// queda una mezcla de HTML nuevo con JS viejo (la causa de la ruedita eterna).
//
// Además: busca versiones nuevas cada 30 min con señal, y borra las cachés de
// terreno de versiones anteriores.
// ============================================================================

import { useEffect, useRef, useState } from 'react'
import { estaEnLinea } from '@/lib/conectividad'

const BUILD = process.env.NEXT_PUBLIC_BUILD_ID || ''
const ARRANQUE_MS = 4000

function aplicar(reg: ServiceWorkerRegistration) {
  const w = reg.waiting
  if (!w) return
  let recargado = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (recargado) return
    recargado = true
    window.location.reload()
  })
  w.postMessage({ type: 'SKIP_WAITING' })
}

async function limpiarCachesViejas() {
  try {
    const keys = await caches.keys()
    await Promise.all(keys
      // También las de antes de este cambio (enex-terreno-*): HTML de versiones
      // viejas que se servía con chunks que ya no existen.
      .filter((k) => (/^terreno-(paginas|rsc)-/.test(k) && !k.endsWith(`-${BUILD}`)) || /^enex-terreno-(paginas|rsc)$/.test(k))
      .map((k) => caches.delete(k)))
  } catch { /* sin Cache Storage */ }
}

export function ActualizacionApp() {
  const [lista, setLista] = useState<ServiceWorkerRegistration | null>(null)
  const inicio = useRef(Date.now())

  useEffect(() => {
    if (typeof window === 'undefined' || !('serviceWorker' in navigator)) return
    let cancelado = false
    let intervalo: number | undefined

    const revisar = (reg: ServiceWorkerRegistration) => {
      if (!reg.waiting || !navigator.serviceWorker.controller) return
      // Recién abierta: se aplica sin preguntar (es el «próximo arranque»).
      if (Date.now() - inicio.current < ARRANQUE_MS) aplicar(reg)
      else setLista(reg)
    }

    navigator.serviceWorker.getRegistration().then((reg) => {
      if (!reg || cancelado) return
      revisar(reg)
      reg.addEventListener('updatefound', () => {
        const nuevo = reg.installing
        nuevo?.addEventListener('statechange', () => { if (nuevo.state === 'installed') revisar(reg) })
      })
      const buscar = () => { if (document.visibilityState === 'visible' && estaEnLinea()) void reg.update().catch(() => undefined) }
      intervalo = window.setInterval(buscar, 30 * 60_000)
      document.addEventListener('visibilitychange', buscar)
      if (!reg.waiting && !reg.installing) void limpiarCachesViejas()
    }).catch(() => undefined)

    return () => { cancelado = true; if (intervalo) window.clearInterval(intervalo) }
  }, [])

  if (!lista) return null
  return (
    <div className="fixed inset-x-0 bottom-0 z-50 mx-auto flex max-w-[480px] items-center justify-between gap-3 bg-gray-900 px-4 py-3 text-sm text-white shadow-lg">
      <span>Hay una versión nueva lista. Se aplica sola la próxima vez que abra la app.</span>
      <button type="button" onClick={() => aplicar(lista)} className="shrink-0 rounded bg-green-600 px-3 py-1.5 font-semibold">Actualizar</button>
    </div>
  )
}
