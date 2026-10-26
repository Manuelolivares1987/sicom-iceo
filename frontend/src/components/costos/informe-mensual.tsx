'use client'

import { useState } from 'react'
import { Mail } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  copiarReporteCostos, getReporteCostos, getTokenReporteCostos, linkReporteCostos, mesEnCursoIso, mesLargo,
} from '@/lib/reporte-costos'

const MINUTA_KEY = 'costos-minuta-borrador'

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
 *
 * El selector de mes también filtra todo el panel de abajo (`onMes`). Vacío =
 * el panel usa los botones de período y el correo, el mes en curso.
 */
export function InformeMensualCostos({ mesFiltro = null, onMes }: {
  mesFiltro?: string | null; onMes?: (mes: string | null) => void
} = {}) {
  const mes = mesFiltro ?? mesEnCursoIso()
  const [msg, setMsg] = useState<string | null>(null)
  const [ocupado, setOcupado] = useState(false)
  // Minuta de la reunión: se escribe aquí y sale dentro del correo, debajo del
  // informe. Se guarda como borrador en este navegador.
  const [minuta, setMinuta] = useState(() => {
    try { return localStorage.getItem(MINUTA_KEY) ?? '' } catch { return '' }
  })
  const cambiarMinuta = (v: string) => {
    setMinuta(v)
    try { localStorage.setItem(MINUTA_KEY, v) } catch { /* sin almacenamiento: solo en memoria */ }
  }

  const copiar = async () => {
    setOcupado(true); setMsg(null)
    try {
      const [data, token] = await Promise.all([getReporteCostos(mes), getTokenReporteCostos()])
      setMsg(await copiarReporteCostos(data, token, minuta))
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
      <label className="flex items-center gap-1.5 text-sm text-gray-700">
        Mes
        <select value={mesFiltro ?? ''} onChange={(e) => onMes?.(e.target.value || null)}
                title="Filtra todo el panel de abajo a ese mes"
                className="h-9 rounded-lg border border-gray-300 bg-white px-2 text-sm capitalize">
          <option value="">Todos (usar el período de abajo)</option>
          {ultimosMeses().map((m) => <option key={m} value={m}>{mesLargo(m)}</option>)}
        </select>
      </label>
      <Button size="sm" variant="outline" onClick={abrir}>Ver informe</Button>
      <Button size="sm" onClick={copiar} disabled={ocupado}>{ocupado ? 'Armando…' : '📋 Copiar para correo'}</Button>
      <div className="w-full">
        <label className="mb-1 block text-xs font-semibold text-gray-700">
          Minuta de la reunión <span className="font-normal text-gray-500">(sale en el correo debajo del informe; «-» al inicio de línea = viñeta)</span>
        </label>
        <textarea value={minuta} onChange={(e) => cambiarMinuta(e.target.value)} rows={4}
                  placeholder={'- Acuerdo 1\n- Acuerdo 2'}
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm" />
      </div>
      {msg && <div className="w-full text-sm text-pillado-green-800">{msg}</div>}
    </div>
  )
}
