'use client'

import { useState } from 'react'
import { Mail, Send, CheckCircle2, AlertTriangle } from 'lucide-react'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import { getCombustibleProyeccion } from '@/lib/services/combustible-proyeccion'
import type {
  ReporteEmailPayload,
  EquipoReporte,
  EstanqueReporte,
  MantenimientoItem,
} from '@/lib/email/reporte-flota-email'

type ReporteRpc = {
  fecha: string | null
  total: number
  disponibilidad: number | null
  utilizacion: number | null
  por_estado: Record<string, number> | null
  por_operacion: Record<string, number> | null
  equipos?: Array<EquipoReporte & { dias_sin_arriendo?: number | null }> | null
}

async function armarPayload(): Promise<ReporteEmailPayload> {
  const { data, error } = await supabase.rpc('fn_reporte_flota_publico')
  if (error) throw new Error(error.message)
  const r = data as ReporteRpc

  let combustible: EstanqueReporte[] = []
  try {
    const proy = await getCombustibleProyeccion()
    combustible = proy.map((e) => ({
      estanque_codigo: e.estanque_codigo,
      estanque_nombre: e.estanque_nombre,
      capacidad_lt: e.capacidad_lt,
      stock_actual: e.stock_actual,
      dias_cobertura: e.dias_cobertura,
      fecha_agotamiento_estimada: e.fecha_agotamiento_estimada,
      ventana_usada: e.ventana_usada,
      severidad: e.severidad,
    }))
  } catch {
    // si no hay permiso/datos de combustible, el reporte se envía sin esa sección
    combustible = []
  }

  const disponibles = (r.equipos ?? [])
    .filter((e) => e.estado === 'D')
    .map((e) => ({
      patente: e.patente,
      equipamiento: e.equipamiento,
      estado: e.estado,
      dias_arrendado: e.dias_arrendado,
      ultimo_cliente: e.ultimo_cliente,
    }))

  let mantenimiento: MantenimientoItem[] = []
  try {
    const { data: mant, error: mantErr } = await supabase.rpc('fn_flota_en_mantenimiento')
    if (!mantErr && Array.isArray(mant)) {
      mantenimiento = mant.map((m: any) => ({
        patente: m.patente,
        equipamiento: m.equipamiento,
        estado_codigo: m.estado_codigo,
        dias_mantencion: m.dias_mantencion,
        ultimo_contrato: m.ultimo_contrato,
        motivo: m.motivo,
      }))
    }
  } catch {
    mantenimiento = []
  }

  return {
    fecha: r.fecha,
    total: r.total,
    disponibilidad: r.disponibilidad,
    utilizacion: r.utilizacion,
    por_estado: r.por_estado,
    por_operacion: r.por_operacion,
    disponibles,
    combustible,
    mantenimiento,
    reporteUrl:
      typeof window !== 'undefined'
        ? `${window.location.origin}/reporte-flota`
        : 'https://pilladoiceo.netlify.app/reporte-flota',
  }
}

export function EnviarReporteModal() {
  const [open, setOpen] = useState(false)
  const [destinatarios, setDestinatarios] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [ok, setOk] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const enviar = async () => {
    setError(null)
    setOk(null)
    const to = destinatarios
      .split(/[,\n;]+/)
      .map((s) => s.trim())
      .filter(Boolean)
    if (to.length === 0) {
      setError('Indica al menos un correo destinatario.')
      return
    }
    setEnviando(true)
    try {
      const { data: sessionData } = await supabase.auth.getSession()
      const token = sessionData.session?.access_token
      if (!token) throw new Error('Tu sesión expiró, vuelve a iniciar sesión.')

      const payload = await armarPayload()
      const res = await fetch('/api/reporte-flota/enviar', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ to, payload }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error ?? 'No se pudo enviar el reporte.')
      setOk(`Reporte enviado a ${json.enviados} destinatario${json.enviados === 1 ? '' : 's'}.`)
      setDestinatarios('')
    } catch (e: any) {
      setError(e.message ?? 'Error inesperado al enviar.')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50"
      >
        <Mail className="h-4 w-4" />
        Enviar por correo
      </button>

      <Modal
        open={open}
        onClose={() => { if (!enviando) setOpen(false) }}
        title="Enviar reporte de flota por correo"
        description="Resumen con disponibilidad por equipo, stock de combustible y link al reporte interactivo."
      >
        <div className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">
              Destinatarios
            </label>
            <textarea
              value={destinatarios}
              onChange={(e) => setDestinatarios(e.target.value)}
              placeholder="correo1@empresa.cl, correo2@empresa.cl"
              rows={3}
              disabled={enviando}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 disabled:bg-gray-50"
            />
            <p className="mt-1 text-xs text-gray-400">
              Separa varios correos con coma, punto y coma o salto de línea.
            </p>
          </div>

          {error && (
            <div className="flex items-start gap-2 rounded-lg bg-red-50 p-3 text-sm text-red-700">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}
          {ok && (
            <div className="flex items-start gap-2 rounded-lg bg-green-50 p-3 text-sm text-green-700">
              <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{ok}</span>
            </div>
          )}

          <div className="flex justify-end gap-3 pt-1">
            <button
              onClick={() => setOpen(false)}
              disabled={enviando}
              className="rounded-lg px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100 disabled:opacity-50"
            >
              Cerrar
            </button>
            <button
              onClick={enviar}
              disabled={enviando}
              className="inline-flex items-center gap-2 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white hover:bg-[#0e3458] disabled:opacity-50"
            >
              {enviando ? <Spinner className="h-4 w-4" /> : <Send className="h-4 w-4" />}
              {enviando ? 'Enviando…' : 'Enviar reporte'}
            </button>
          </div>
        </div>
      </Modal>
    </>
  )
}
