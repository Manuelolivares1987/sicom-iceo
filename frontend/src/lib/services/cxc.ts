import { supabase } from '@/lib/supabase'

// ============================================================================
// Cuentas por cobrar (MIG730-731)
// ----------------------------------------------------------------------------
// La cartera sale de Softland (solo lectura) por database/scripts/softland-sync.ps1
// una vez al día. Cartera cobrable = facturas emitidas desde el 01-01-2026.
// La autorización vive en la base (fn_finanzas_puede_ver): un 42501 se
// traduce a "no autorizado", no a una cartera vacía.
// ============================================================================

export type EstadoDoc = 'pagada' | 'por_vencer' | 'vencida'

export type DocumentoCxc = {
  cod_aux: string
  rut: string | null
  cliente: string
  tipo: string
  folio: number
  emision: string
  vence: string | null
  monto: number
  notas_credito: number
  pagado: number
  saldo: number
  ultimo_pago: string | null
  n_pagos: number
  estado: EstadoDoc
  dias_vencida: number
  dias_pago: number | null
  dias_atraso: number | null
  patentes?: string[]
}

export type ClienteCxc = {
  cod_aux: string
  rut: string | null
  cliente: string
  deuda: number | null
  vencido: number | null
  abiertas: number
  facturas: number
  facturado: number
  dias_pago_prom: number | null
  dias_atraso_prom: number | null
  pagadas_con_dato: number
  max_dias_vencida: number | null
}

export type CarteraCxc = {
  sincronizado_at: string | null
  resumen: {
    facturado: number; pagado: number; por_vencer: number; vencido: number
    n_por_vencer: number; n_vencido: number; n_pagada: number
    tramos: { '1_30': number; '31_60': number; '61_90': number; mas_90: number }
    credito_a_favor: number
  }
  mensual: { mes: string; facturado: number; cobrado: number; pendiente: number }[]
  clientes: ClienteCxc[]
  documentos: DocumentoCxc[]
}

export type FichaCliente = {
  cliente: { cod_aux: string; rut: string | null; nombre: string | null; email: string | null; email_dte: string | null; telefono: string | null; dia_plazo: number | null } | null
  documentos: (DocumentoCxc & {
    equipos: { patente: string; activo_id: string | null; total: number }[]
    movimientos: { fecha: string; tipo: string; numero: number; monto: number; glosa: string | null }[]
  })[]
}

export class SinPermisoFinanzas extends Error {}

function traducir(error: { code?: string; message: string }): never {
  if (error.code === '42501') throw new SinPermisoFinanzas(error.message)
  throw new Error(error.message)
}

export async function getCarteraCxc(): Promise<CarteraCxc> {
  const { data, error } = await supabase.rpc('rpc_cxc_cartera')
  if (error) traducir(error)
  return data as CarteraCxc
}

export async function getFichaCliente(codAux: string): Promise<FichaCliente> {
  const { data, error } = await supabase.rpc('rpc_cxc_cliente', { p_cod_aux: codAux })
  if (error) traducir(error)
  return data as FichaCliente
}

// ----------------------------------------------------------------------------
// Clasificación del pagador por su atraso promedio contra el vencimiento
// (facturas 2026 ya pagadas). Sin historial suficiente no se clasifica.
// ----------------------------------------------------------------------------
export type Pagador = { etiqueta: string; tono: 'bueno' | 'atento' | 'serio' | 'critico' | 'sin' ; detalle: string }

export function clasificarPagador(c: Pick<ClienteCxc, 'dias_atraso_prom' | 'pagadas_con_dato'>): Pagador {
  const a = c.dias_atraso_prom
  if (a == null || c.pagadas_con_dato < 2) return { etiqueta: 'Sin historial', tono: 'sin', detalle: 'Menos de 2 facturas pagadas en 2026' }
  if (a <= 5) return { etiqueta: 'Puntual', tono: 'bueno', detalle: `Paga en plazo (atraso promedio ${a} días)` }
  if (a <= 15) return { etiqueta: 'Normal', tono: 'atento', detalle: `Atraso promedio ${a} días` }
  if (a <= 30) return { etiqueta: 'Lento', tono: 'serio', detalle: `Atraso promedio ${a} días` }
  return { etiqueta: 'Moroso', tono: 'critico', detalle: `Atraso promedio ${a} días` }
}
