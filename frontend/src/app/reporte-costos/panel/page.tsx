'use client'

import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { PanelCostosOperacion } from '@/components/costos/panel-costos'
import { usarTokenReporteCostos } from '@/lib/services/costos-operacion'

// ============================================================================
// /reporte-costos/panel — el MISMO panel de Gerencia → Costos (gráficos, Pareto
// en cadena hasta la línea de Softland), abierto desde el correo sin iniciar
// sesión: el token del link (?t=) viaja en `x-reporte-token` (MIG620). Con
// sesión funciona igual que en el dashboard.
// ============================================================================

export default function PanelCostosPublicoPage() {
  // undefined = verificando; el panel no se monta hasta saber con qué consulta.
  const [acceso, setAcceso] = useState<'token' | 'sesion' | 'ninguno' | undefined>(undefined)

  useEffect(() => {
    const t = new URLSearchParams(window.location.search).get('t')
    if (t) {
      usarTokenReporteCostos(t)
      setAcceso('token')
      return () => usarTokenReporteCostos(null)
    }
    supabase.auth.getSession().then(({ data: { session } }) => setAcceso(session ? 'sesion' : 'ninguno'))
  }, [])

  if (acceso === undefined) {
    return <div className="min-h-screen bg-gray-50 py-20 text-center text-gray-400">Verificando acceso…</div>
  }
  if (acceso === 'ninguno') {
    return (
      <div className="min-h-screen bg-gray-50 py-20">
        <div className="mx-auto max-w-md rounded-lg border border-gray-200 bg-white p-8 text-center shadow-sm">
          <h1 className="text-lg font-bold text-[#1e5929]">Costos de operación — Pillado</h1>
          <p className="mt-3 text-sm text-gray-600">Este panel es de uso interno y requiere iniciar sesión.</p>
          <a href={`/login?next=${encodeURIComponent('/dashboard/gerencia/costos')}`}
             className="mt-5 inline-block rounded-lg bg-[#1e5929] px-5 py-2 text-sm font-semibold text-white">
            Iniciar sesión
          </a>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="mx-auto max-w-7xl">
        <PanelCostosOperacion
          titulo="Costos de Operación — Pillado"
          descripcion="Compras aprobadas (OC) o consumo de bodega de Softland, por equipo, faena y familia. Sin combustible de reventa. Clic en cualquier barra o fila para ver su Pareto." />
      </div>
    </div>
  )
}
