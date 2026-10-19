'use client'

import { useState } from 'react'
import { Mail } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  copiarReporteCostos, getReporteCostos, getTokenReporteCostos, linkReporteCostos, mesCerradoIso, mesLargo,
} from '@/lib/reporte-costos'

/** Últimos 12 meses, del más reciente (mes en curso) hacia atrás. */
function ultimosMeses(): string[] {
  const hoy = new Date()
  return Array.from({ length: 12 }, (_, i) => {
    const d = new Date(hoy.getFullYear(), hoy.getMonth() - i, 1)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
  })
}

/**
 * Informe mensual para gerencia (MIG617): top 10 por equipo, familia y centro
 * de costo. Copia el correo con formato (como fiabilidad) o abre el informe
 * interactivo, que se ve sin sesión con el token del link.
 */
export function InformeMensualCostos() {
  const [mes, setMes] = useState(mesCerradoIso())
  const [msg, setMsg] = useState<string | null>(null)
  const [ocupado, setOcupado] = useState(false)

  const copiar = async () => {
    setOcupado(true); setMsg(null)
    try {
      const [data, token] = await Promise.all([getReporteCostos(mes), getTokenReporteCostos()])
      setMsg(await copiarReporteCostos(data, token))
    } catch (e) {
      setMsg(`No se pudo armar el informe: ${(e as Error).message}`)
    } finally {
      setOcupado(false)
    }
  }

  const abrir = async () => {
    const token = await getTokenReporteCostos()
    window.open(linkReporteCostos(window.location.origin, mes, token), '_blank')
  }

  return (
    <div className="mx-4 mt-4 flex flex-wrap items-center gap-2 rounded-xl border border-pillado-green-200 bg-pillado-green-50 px-4 py-3 md:mx-6">
      <Mail className="h-5 w-5 text-pillado-green-700" />
      <div className="mr-auto">
        <div className="text-sm font-semibold text-gray-900">Informe mensual por correo</div>
        <div className="text-xs text-gray-600">Top 10 del mes por equipo, familia y centro de costo, con link interactivo.</div>
      </div>
      <select value={mes} onChange={(e) => setMes(e.target.value)}
              className="h-9 rounded-lg border border-gray-300 bg-white px-2 text-sm capitalize">
        {ultimosMeses().map((m) => <option key={m} value={m}>{mesLargo(m)}</option>)}
      </select>
      <Button size="sm" variant="outline" onClick={abrir}>Ver informe</Button>
      <Button size="sm" onClick={copiar} disabled={ocupado}>{ocupado ? 'Armando…' : '📋 Copiar para correo'}</Button>
      {msg && <div className="w-full text-sm text-pillado-green-800">{msg}</div>}
    </div>
  )
}
