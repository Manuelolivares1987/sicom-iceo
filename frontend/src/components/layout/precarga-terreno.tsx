'use client'

// ============================================================================
// Precarga de la app de terreno (19-11-2026)
// ----------------------------------------------------------------------------
// El service worker guarda una pantalla recién cuando se abre con señal. El
// mecánico que entra por primera vez a «Bodega» o «Entrega de turno» estando
// ya en el rajo, sin señal, caía en /offline aunque hubiera iniciado sesión
// esa misma mañana en el campamento.
//
// Con sesión y conexión real, en un momento ocioso, se piden en segundo plano
// las pantallas de SU app de terreno: el service worker las guarda 30 días
// (regla «terreno» de next.config.js). Una vez por día y por versión; no corre
// con «ahorro de datos» ni sin conexión. Solo pantallas fijas: las de un id
// (OT, OS, pauta) dependen de qué se abra y siguen su regla normal.
// ============================================================================

import { useEffect } from 'react'
import { useAuth } from '@/contexts/auth-context'
import { estaEnLinea, EVENTO_CONECTIVIDAD } from '@/lib/conectividad'

const PANTALLAS: Record<string, string[]> = {
  '/m/franke': ['', 'pauta', 'bitacora', 'bodega', 'despacho', 'carga', 'entrega', 'turno', 'guia'],
  '/m/franke-venta': [''],
  '/m/taller': ['', 'insumos', 'copiloto'],
  '/m/romeral': ['', 'inicial', 'recepcion', 'trasvasije', 'cierre'],
  '/m/calama': [''],
  '/m/enex': ['', 'servicio'],
  '/m/prevencion': ['', 'control', 'epp', 'inspeccion'],
}

const ROLES_TALLER = ['operador_taller', 'tecnico_mantenimiento', 'jefe_mantenimiento']
const ROLES_PREVENCION = ['supervisor', 'prevencionista', 'jefe_operaciones']
const CLAVE = 'sicom-precarga-terreno'
const VERSION = process.env.NEXT_PUBLIC_BUILD_ID || 'dev'

function raizApp(ruta: string | null | undefined): string | null {
  if (!ruta) return null
  const m = ruta.match(/^\/m\/[a-z-]+/)
  return m && PANTALLAS[m[0]] ? m[0] : null
}

export function PrecargaTerreno() {
  const { perfil, rolCalama, loading } = useAuth()

  useEffect(() => {
    if (loading || !perfil || typeof window === 'undefined') return
    if (!('serviceWorker' in navigator) || !navigator.serviceWorker.controller) return

    const apps = new Set<string>()
    const add = (r: string | null) => { if (r) apps.add(r) }
    add(raizApp(perfil.faena?.app_movil))
    add(raizApp((perfil as { app_terreno?: string | null }).app_terreno))
    if (ROLES_TALLER.includes(perfil.rol) && !perfil.faena?.app_movil) add('/m/taller')
    if (rolCalama) add('/m/calama')
    if (ROLES_PREVENCION.includes(perfil.rol)) add('/m/prevencion')
    if (apps.size === 0) return

    const firma = `${VERSION}|${perfil.id}|${new Date().toISOString().slice(0, 10)}|${Array.from(apps).sort().join(',')}`
    let hecha = false
    try { hecha = localStorage.getItem(CLAVE) === firma } catch { /* sin storage */ }
    if (hecha) return

    let cancelado = false
    const correr = async () => {
      if (cancelado || !estaEnLinea()) return
      const conn = (navigator as { connection?: { saveData?: boolean } }).connection
      if (conn?.saveData) return
      const urls = Array.from(apps).flatMap((app) => PANTALLAS[app].map((p) => (p ? `${app}/${p}/` : `${app}/`)))
      let ok = 0
      // [19-11-2026] El precache ya no trae todos los JS (para que las
      // actualizaciones bajen livianas): de cada pantalla se piden también sus
      // scripts y estilos, y el service worker los guarda 30 días.
      const recursos = new Set<string>()
      for (const u of urls) {
        if (cancelado || !estaEnLinea()) return
        try {
          const r = await fetch(u, { credentials: 'same-origin', cache: 'no-store' })
          if (r.ok) {
            ok += 1
            const html = await r.text()
            for (const m of Array.from(html.matchAll(/(?:src|href)="(\/_next\/static\/[^"]+\.(?:js|css))"/g))) recursos.add(m[1])
          }
        } catch { /* se reintenta otro día / con señal */ }
      }
      let recursosOk = 0
      for (const u of Array.from(recursos)) {
        if (cancelado || !estaEnLinea()) return
        try {
          const r = await fetch(u, { credentials: 'same-origin' })
          if (r.ok) recursosOk += 1
        } catch { /* idem */ }
      }
      if (ok === urls.length && recursosOk === recursos.size) {
        try { localStorage.setItem(CLAVE, firma) } catch { /* sin storage */ }
      }
    }

    // Que no compita con lo que la persona está abriendo ahora.
    const programar = () => {
      const ric = (window as { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number }).requestIdleCallback
      if (ric) ric(() => { void correr() }, { timeout: 15_000 })
      else setTimeout(() => { void correr() }, 8_000)
    }
    const t = setTimeout(programar, 5_000)
    // Si se logueó sin señal, se precarga apenas vuelva.
    const alVolver = (e: Event) => { if ((e as CustomEvent<{ enLinea: boolean }>).detail?.enLinea) programar() }
    window.addEventListener(EVENTO_CONECTIVIDAD, alVolver)
    return () => {
      cancelado = true
      clearTimeout(t)
      window.removeEventListener(EVENTO_CONECTIVIDAD, alVolver)
    }
  }, [loading, perfil, rolCalama])

  return null
}

export default PrecargaTerreno
