'use client'

// ============================================================================
// Lanzador de la app de terreno: /m/ (start_url del ícono, 20-11-2026)
// ----------------------------------------------------------------------------
// Antes el ícono abría /dashboard/ (panel de oficina: no queda guardado para
// usar sin señal, 1-2 redirecciones) y la gente de faena quedaba en la ruedita
// o en «Sin conexión». Esto decide con lo que el TELÉFONO ya sabe, sin esperar
// a la red: la última app de terreno usada, o la de su faena, o el panel.
// ============================================================================

import { useEffect, useState } from 'react'
import { leerIdentidadEquipo, leerSesionPersistida } from '@/lib/supabase'
import { ULTIMA_APP_KEY } from '@/components/layout/terreno-global'

const OFICINA = ['administrador', 'subgerente_operaciones', 'gerente', 'gerente_general', 'jefe_operaciones', 'planificador', 'rrhh']

function destino(): string {
  try {
    const u = leerSesionPersistida()?.user ?? leerIdentidadEquipo()
    if (!u) return '/login/?next=%2Fm%2F'
    const p = JSON.parse(localStorage.getItem('sicom-perfil-cache') ?? 'null') as
      { id?: string; rol?: string; faena?: { app_movil?: string | null } | null } | null
    const mio = p?.id === u.id ? p : null
    // La oficina abre el panel aunque alguna vez haya mirado una app de terreno.
    const oficina = !!mio?.rol && OFICINA.includes(mio.rol) && !mio.faena?.app_movil
    const ultima = localStorage.getItem(ULTIMA_APP_KEY)
    if (!oficina && ultima && /^\/m\/[a-z0-9-]+\/$/.test(ultima)) return ultima
    const app = mio?.faena?.app_movil
    if (app && app.startsWith('/m/')) return app.endsWith('/') ? app : `${app}/`
  } catch { /* sigue al panel */ }
  return '/dashboard/'
}

export default function LanzadorTerreno() {
  const [ir, setIr] = useState<string | null>(null)
  useEffect(() => {
    const d = destino()
    setIr(d)
    window.location.replace(d)
  }, [])
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-gray-50 px-6 text-center">
      <p className="text-sm text-gray-500">Abriendo SICOM…</p>
      {ir && <a href={ir} className="rounded-lg bg-gray-900 px-4 py-3 text-sm font-semibold text-white">Abrir</a>}
    </div>
  )
}
