import { supabase } from '@/lib/supabase'
import type { TransaccionCombustibleCliente } from './portal-cliente'

// ====== Stock actual de estanques ==========================================

export type EstanqueStock = {
  id:                    string
  codigo:                string
  nombre:                string
  capacidad_lt:          number
  stock_teorico_lt:      number
  stock_minimo_alerta_lt: number | null
  faena_nombre:          string | null
  porcentaje:            number   // 0..100
  estado:                'critico' | 'bajo' | 'ok' | 'lleno'
}

export async function cargarStockEstanques(): Promise<EstanqueStock[]> {
  const { data, error } = await supabase
    .from('combustible_estanques')
    .select(`
      id, codigo, nombre, capacidad_lt, stock_teorico_lt, stock_minimo_alerta_lt,
      faena:faenas!faena_id ( nombre )
    `)
    .order('codigo')
  if (error) throw error
  type Raw = Omit<EstanqueStock, 'faena_nombre' | 'porcentaje' | 'estado'> & {
    faena: { nombre: string } | null
  }
  return ((data ?? []) as unknown as Raw[]).map((e) => {
    const cap = Number(e.capacidad_lt)
    const sto = Number(e.stock_teorico_lt)
    const min = e.stock_minimo_alerta_lt ?? 0
    const pct = cap > 0 ? Math.min(100, (sto / cap) * 100) : 0
    let estado: EstanqueStock['estado'] = 'ok'
    if (sto <= 0)                estado = 'critico'
    else if (min && sto <= min)  estado = 'bajo'
    else if (pct >= 90)          estado = 'lleno'
    return {
      ...e,
      faena_nombre: e.faena?.nombre ?? null,
      porcentaje:   pct,
      estado,
    }
  })
}

// Reutiliza la misma vista enriquecida — pero como admin/comercial NO se aplica
// la RLS del portal (esos roles tienen acceso completo a combustible_movimientos
// y por extension a v_combustible_movimientos_cliente).

export type FiltrosComercial = {
  fechaDesde?: string
  fechaHasta?: string
}

export async function cargarConsolidadoComercial(
  filtros: FiltrosComercial = {},
): Promise<TransaccionCombustibleCliente[]> {
  let q = supabase
    .from('v_combustible_movimientos_cliente')
    .select('*')
    .order('fecha', { ascending: false })
    .limit(5000)
  if (filtros.fechaDesde) q = q.gte('fecha', filtros.fechaDesde + 'T00:00:00')
  if (filtros.fechaHasta) q = q.lte('fecha', filtros.fechaHasta + 'T23:59:59')
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as TransaccionCombustibleCliente[]
}

// Carga solo ventas a vehiculos EXTERNOS (subcontratistas autorizados).
// Es lo que comercial necesita para cobrar. La vista ya viene enriquecida con
// precio_venta y total_venta_clp (MIG73).
export type FiltrosVentasExternas = {
  fechaDesde?: string
  fechaHasta?: string
  empresa?:    string
  patente?:    string
}

export async function cargarVentasExternasComercial(
  filtros: FiltrosVentasExternas = {},
): Promise<TransaccionCombustibleCliente[]> {
  let q = supabase
    .from('v_combustible_movimientos_cliente')
    .select('*')
    .not('vehiculo_externo_id', 'is', null)
    .order('fecha', { ascending: false })
    .limit(5000)
  if (filtros.fechaDesde) q = q.gte('fecha', filtros.fechaDesde + 'T00:00:00')
  if (filtros.fechaHasta) q = q.lte('fecha', filtros.fechaHasta + 'T23:59:59')
  const { data, error } = await q
  if (error) throw error
  let rows = (data ?? []) as TransaccionCombustibleCliente[]
  if (filtros.empresa) {
    const q2 = filtros.empresa.toLowerCase()
    rows = rows.filter((r) => (r.externo_empresa ?? '').toLowerCase().includes(q2))
  }
  if (filtros.patente) {
    const q2 = filtros.patente.toLowerCase()
    rows = rows.filter((r) => (r.externo_patente ?? '').toLowerCase().includes(q2))
  }
  return rows
}


export type ResumenPorEmpresa = {
  empresa:          string       // "LISSET LOPEZ G" | "MYG" | cliente del contrato
  origen:           'externa' | 'contrato' | 'sin_clasificar'
  transacciones:    number
  litros:           number
  costo:            number
  patentes_unicas:  number
  primera_fecha:    string | null
  ultima_fecha:     string | null
}

export function agruparPorEmpresa(rows: TransaccionCombustibleCliente[]): ResumenPorEmpresa[] {
  type Agg = {
    origen: 'externa' | 'contrato' | 'sin_clasificar'
    transacciones: number
    litros: number
    costo: number
    patentes: Set<string>
    fechas: string[]
  }
  const grupos = new Map<string, Agg>()
  for (const r of rows) {
    let empresa: string
    let origen: Agg['origen']
    if (r.externo_empresa) {
      empresa = r.externo_empresa; origen = 'externa'
    } else if (r.activo_cliente) {
      empresa = r.activo_cliente;  origen = 'contrato'
    } else {
      empresa = '(sin clasificar)'; origen = 'sin_clasificar'
    }
    if (!grupos.has(empresa)) {
      grupos.set(empresa, { origen, transacciones: 0, litros: 0, costo: 0, patentes: new Set(), fechas: [] })
    }
    const g = grupos.get(empresa)!
    g.transacciones++
    g.litros += Number(r.litros)
    g.costo  += Number(r.costo_total_clp ?? 0)
    const pat = r.activo_patente ?? r.externo_patente
    if (pat) g.patentes.add(pat)
    g.fechas.push(r.fecha)
  }
  return Array.from(grupos.entries())
    .map(([empresa, g]) => {
      g.fechas.sort()
      return {
        empresa,
        origen:          g.origen,
        transacciones:   g.transacciones,
        litros:          g.litros,
        costo:           g.costo,
        patentes_unicas: g.patentes.size,
        primera_fecha:   g.fechas[0]?.slice(0, 10) ?? null,
        ultima_fecha:    g.fechas[g.fechas.length - 1]?.slice(0, 10) ?? null,
      }
    })
    .sort((a, b) => b.litros - a.litros)
}


export type DiaApilado = {
  fecha: string
  [empresa: string]: string | number   // total por empresa
}

export function gruparApiladoPorDia(rows: TransaccionCombustibleCliente[], empresas: string[]): DiaApilado[] {
  const matriz = new Map<string, Map<string, number>>()  // fecha -> empresa -> litros
  for (const r of rows) {
    const fecha = r.fecha.slice(0, 10)
    const emp = r.externo_empresa ?? r.activo_cliente ?? '(sin clasificar)'
    if (!matriz.has(fecha)) matriz.set(fecha, new Map())
    const f = matriz.get(fecha)!
    f.set(emp, (f.get(emp) ?? 0) + Number(r.litros))
  }
  return Array.from(matriz.entries())
    .map(([fecha, mapEmp]) => {
      const obj: DiaApilado = { fecha }
      for (const e of empresas) {
        obj[e] = mapEmp.get(e) ?? 0
      }
      return obj
    })
    .sort((a, b) => (a.fecha as string).localeCompare(b.fecha as string))
}


export type PatenteRanking = {
  patente:      string
  empresa:      string
  litros:       number
  despachos:    number
  costo:        number
}

export function rankearPatentes(rows: TransaccionCombustibleCliente[]): PatenteRanking[] {
  const m = new Map<string, { empresa: string; litros: number; despachos: number; costo: number }>()
  for (const r of rows) {
    const pat = r.activo_patente ?? r.externo_patente
    if (!pat) continue
    const empresa = r.externo_empresa ?? r.activo_cliente ?? '—'
    if (!m.has(pat)) m.set(pat, { empresa, litros: 0, despachos: 0, costo: 0 })
    const g = m.get(pat)!
    g.litros    += Number(r.litros)
    g.despachos += 1
    g.costo     += Number(r.costo_total_clp ?? 0)
  }
  return Array.from(m.entries())
    .map(([patente, g]) => ({ patente, ...g }))
    .sort((a, b) => b.litros - a.litros)
}
