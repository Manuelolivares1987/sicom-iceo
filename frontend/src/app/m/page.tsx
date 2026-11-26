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
import { leerUltimaApp } from '@/lib/app-terreno'
import { ROL_CALAMA_KEY } from '@/contexts/auth-context'

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
      { id?: string; rol?: string; app_terreno?: string | null; faena?: { app_movil?: string | null } | null } | null
    const mio = p?.id === u.id ? p : null
    // La oficina abre el panel aunque alguna vez haya mirado una app de terreno.
    const oficina = !!mio?.rol && OFICINA.includes(mio.rol) && !mio.faena?.app_movil
    // La última app de ESTA persona (no la del teléfono): quien entra después
    // en el mismo equipo va a la suya.
    const ultima = leerUltimaApp(u.id, p?.id)
    if (!oficina && ultima) return { ruta: ultima, seguro: true }
    const app = mio?.faena?.app_movil
    if (app && app.startsWith('/m/')) return { ruta: app.endsWith('/') ? app : `${app}/`, seguro: true }
    // [20-11-2026] Las mismas reglas del panel (dashboard/layout), pero decididas
    // en el teléfono: antes taller/combustible/Calama pasaban por /dashboard/
    // (no guardado para usar sin señal) y la primera vez sin señal caían en
    // «Sin conexión».
    const conBarra = (r: string) => (r.endsWith('/') ? r : `${r}/`)
    if (mio?.app_terreno && mio.app_terreno.startsWith('/m/')) return { ruta: conBarra(mio.app_terreno), seguro: true }
    if (mio?.rol === 'operador_taller') return { ruta: '/m/taller/', seguro: true }
    if (mio?.rol === 'operador_combustible') return { ruta: '/m/romeral/', seguro: true }
    const rc = JSON.parse(localStorage.getItem(ROL_CALAMA_KEY) ?? 'null') as { id?: string; rol?: string } | null
    if (rc?.id === u.id && rc.rol === 'operador_calama' && !(mio?.rol && OFICINA.includes(mio.rol))) return { ruta: '/m/calama/', seguro: true }
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
