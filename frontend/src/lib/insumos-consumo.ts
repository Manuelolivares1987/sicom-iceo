// Consumos por insumo (MIG681). Cálculo puro de la pestaña, para poder probarlo.

export type InsumoConsumo = {
  clave: string
  cod_prod: string | null
  descripcion: string
  familia: string
  unidad: string
  acumulado: number
  monto: number
  movimientos: number
  meses_con_consumo: number
  precio_ref: number | null
  camiones: number
  con_pauta: boolean
  /** Hay litros por confirmar en la placa del camión. */
  provisorio: boolean
  pauta_12m: number | null
  pauta_2027: number | null
  pauta_2028: number | null
  pauta_2029: number | null
  proveedor: string | null
  n_proveedores: number
}

export type PeriodoInsumo = { id: string; label: string; desde: string; hasta: string; meses: number }

export type FilaInsumo = InsumoConsumo & {
  promedio: number
  proyeccion: number
  /** pauta = sale de las mantenciones · promedio = sin pauta, sigue al consumo histórico */
  base: 'pauta' | 'promedio'
  precio: number | null
  monto_proyectado: number | null
}

const iso = (a: number, m: number, d: number) => `${a}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`
const finDeMes = (a: number, m: number) => iso(a, m, new Date(a, m, 0).getDate())

/** Períodos cerrados: el mes en curso va incompleto y bajaría el promedio. */
export function periodosInsumo(hoy: string): PeriodoInsumo[] {
  const a = Number(hoy.slice(0, 4)), m = Number(hoy.slice(5, 7))
  const ultimo = m === 1 ? { a: a - 1, m: 12 } : { a, m: m - 1 }
  const hasta = finDeMes(ultimo.a, ultimo.m)
  const ultimos = (n: number): PeriodoInsumo => {
    const t = ultimo.a * 12 + ultimo.m - 1 - (n - 1)
    return { id: `u${n}`, label: `Últimos ${n} meses`, desde: iso(Math.floor(t / 12), (t % 12) + 1, 1), hasta, meses: n }
  }
  const periodos = [ultimos(12), ultimos(24), ultimos(36)]
  if (ultimo.a === a) periodos.push({ id: `a${a}`, label: `${a} (ene a ${hasta.slice(5, 7)})`, desde: iso(a, 1, 1), hasta, meses: ultimo.m })
  periodos.push({ id: `a${a - 1}`, label: String(a - 1), desde: iso(a - 1, 1, 1), hasta: iso(a - 1, 12, 31), meses: 12 })
  return periodos
}

export function armarFilaInsumo(i: InsumoConsumo, meses: number): FilaInsumo {
  const acumulado = Number(i.acumulado) || 0
  const promedio = meses > 0 ? acumulado / meses : 0
  const base = i.con_pauta ? 'pauta' : 'promedio'
  const proyeccion = base === 'pauta' ? Number(i.pauta_12m) || 0 : promedio * 12
  const precio = acumulado > 0 ? Number(i.monto) / acumulado : i.precio_ref != null ? Number(i.precio_ref) : null
  return { ...i, acumulado, promedio, proyeccion, base, precio, monto_proyectado: precio != null ? proyeccion * precio : null }
}

/** Para mostrarle a un proveedor: solo volúmenes, nunca precios ni quién nos vende. */
export const filaParaProveedor = (f: FilaInsumo) => ({
  codigo: f.cod_prod ?? '',
  insumo: f.descripcion,
  familia: f.familia,
  unidad: f.unidad,
  acumulado: f.acumulado,
  promedio: f.promedio,
  proyeccion: f.proyeccion,
  base: f.base === 'pauta' ? 'Pauta de mantención' : 'Promedio histórico',
  condicion: f.provisorio ? 'Referencial, sujeto a confirmación' : 'Estimado',
})
