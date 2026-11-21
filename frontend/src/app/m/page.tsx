'use client'

// ============================================================================
// Lanzador de la app de terreno: /m/ (start_url del ícono, 20-11-2026)
// ----------------------------------------------------------------------------
// Antes el ícono abría /dashboard/ (panel de oficina: no queda guardado para
// usar sin señal, 1-2 redirecciones) y la gente de faena quedaba en la ruedita
// o en «Sin conexión». Esto decide con lo que el TELÉFONO ya sabe, sin esperar
// a la red: la última app de terreno usada, o la de su faena, o el panel.
// ============================================================================

import { useEffect, useRef, useState } from 'react'
import { useAuth } from '@/contexts/auth-context'
import { leerIdentidadEquipo, leerSesionPersistida } from '@/lib/supabase'
import { ULTIMA_APP_KEY } from '@/components/layout/terreno-global'

const OFICINA = ['administrador', 'subgerente_operaciones', 'gerente', 'gerente_general', 'jefe_operaciones', 'planificador', 'rrhh']

/**
 * `seguro` = el teléfono sabe a dónde ir. Si hay sesión pero el perfil no está
 * guardado (Chrome borró datos, primera vez), NO se manda al panel de oficina
 * a ciegas: se espera el perfil unos segundos (hallado por las pruebas E2E).
 */
function destino(): { ruta: string; seguro: boolean } {
  try {
    const u = leerSesionPersistida()?.user ?? leerIdentidadEquipo()
    if (!u) return { ruta: '/login/?next=%2Fm%2F', seguro: true }
    const p = JSON.parse(localStorage.getItem('sicom-perfil-cache') ?? 'null') as
      { id?: string; rol?: string; faena?: { app_movil?: string | null } | null } | null
    const mio = p?.id === u.id ? p : null
    // La oficina abre el panel aunque alguna vez haya mirado una app de terreno.
    const oficina = !!mio?.rol && OFICINA.includes(mio.rol) && !mio.faena?.app_movil
    const ultima = localStorage.getItem(ULTIMA_APP_KEY)
    if (!oficina && ultima && /^\/m\/[a-z0-9-]+\/$/.test(ultima)) return { ruta: ultima, seguro: true }
    const app = mio?.faena?.app_movil
    if (app && app.startsWith('/m/')) return { ruta: app.endsWith('/') ? app : `${app}/`, seguro: true }
    return { ruta: '/dashboard/', seguro: !!mio }
  } catch { /* sigue al panel */ }
  return { ruta: '/dashboard/', seguro: true }
}

export default function LanzadorTerreno() {
  const [ir, setIr] = useState<string | null>(null)
  const { perfilEstado } = useAuth()
  const listo = useRef(false)
  const [plazo, setPlazo] = useState(false)
  useEffect(() => { const t = setTimeout(() => setPlazo(true), 6000); return () => clearTimeout(t) }, [])
  useEffect(() => {
    if (listo.current) return
    const d = destino()
    // Sin perfil guardado: esperar a que llegue (o 6 s) antes de decidir.
    if (!d.seguro && perfilEstado === 'cargando' && !plazo) return
    listo.current = true
    const final = d.seguro ? d : destino()
    setIr(final.ruta)
    window.location.replace(final.ruta)
  }, [perfilEstado, plazo])
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-gray-50 px-6 text-center">
      <p className="text-sm text-gray-500">Abriendo SICOM…</p>
      {ir && <a href={ir} className="rounded-lg bg-gray-900 px-4 py-3 text-sm font-semibold text-white">Abrir</a>}
    </div>
  )
}
