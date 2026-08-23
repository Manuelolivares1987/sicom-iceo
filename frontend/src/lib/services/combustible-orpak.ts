// ============================================================================
// Orpak dentro de SICOM (MIG328–MIG333)
// ----------------------------------------------------------------------------
// El cierre tiene tres lados y hasta MIG328 el sistema sólo veía dos:
//
//     VARILLA        cuánto combustible hay realmente en el estanque
//     CUENTALITROS   cuánto dice el mecanismo que salió
//     SIST. AUT.     cuánto registró Orpak que se vendió, y a quién
//
// Dos de las tres siempre se parecen. La que se desvía dice qué falló, y esa
// es toda la gracia: un descuadre sin diagnóstico obliga a revisar el día
// entero; con el tercer lado, dice dónde mirar.
//
// La clasificación de cada transacción y el mapeo estación→estanque viven en
// la base como reglas editables, no acá. Una estación nueva se resuelve
// agregando una fila, no publicando una versión.
// ============================================================================

import { supabase } from '@/lib/supabase'

// ── Carga del archivo ───────────────────────────────────────────────────────

export type FilaOrpak = {
  hoja: string | null
  serie: string | null
  fecha: string
  hora: string | null
  flota: string | null
  vehiculo: string
  producto: string | null
  litros: number
  estacion: string | null
  departamento: string | null
  tarjeta: string | null
  autorizado_por: string | null
  bomba: string | null
  dia_cierre: string | null
}

export type ResultadoCarga = {
  carga_id: string
  nuevas: number
  repetidas: number
  rechazadas: number
  rechazos: { hoja?: string; fila?: string; motivo: string }[]
  desde: string | null
  hasta: string | null
}

export async function cargarOrpak(faenaId: string, archivo: string, filas: FilaOrpak[]) {
  const { data, error } = await supabase.rpc('rpc_comb_orpak_cargar', {
    p_faena_id: faenaId, p_archivo: archivo, p_filas: filas,
  })
  if (error) throw error
  return data as ResultadoCarga
}

export type Carga = {
  id: string
  archivo: string
  periodo_desde: string | null
  periodo_hasta: string | null
  filas_leidas: number
  filas_nuevas: number
  filas_repetidas: number
  filas_rechazadas: number
  cargado_nombre: string | null
  cargado_at: string
}

export async function getCargas(faenaId: string, limite = 20) {
  const { data, error } = await supabase
    .from('combustible_orpak_carga').select('*')
    .eq('faena_id', faenaId).order('cargado_at', { ascending: false }).limit(limite)
  if (error) throw error
  return (data ?? []) as Carga[]
}

// ── El triángulo ────────────────────────────────────────────────────────────

/**
 * Cada diagnóstico dice dónde buscar, no sólo que algo está mal.
 * El orden importa: de arriba hacia abajo, de más grave a menos.
 */
export const DIAGNOSTICO_UI: Record<string, { label: string; cls: string; explica: string }> = {
  'salida sin registrar': {
    label: 'Salió sin imputar',
    cls: 'bg-red-100 text-red-800',
    explica: 'La varilla y el cuentalitros coinciden en que salió combustible, y el sistema no tiene ninguna transacción. No se sabe a quién cargarlo.',
  },
  'dia mal medido': {
    label: 'Día mal medido',
    cls: 'bg-red-100 text-red-800',
    explica: 'Las tres medidas se contradicen entre sí. No hay conclusión posible: hay que rehacer la medición.',
  },
  'falla en el estanque': {
    label: 'Revisar el estanque',
    cls: 'bg-amber-100 text-amber-800',
    explica: 'El cuentalitros coincide con Orpak, así que el registro está bien. La que se aparta es la varilla: agua, aforo, temperatura o una salida sin medir.',
  },
  'falla en el registro': {
    label: 'Revisar el registro',
    cls: 'bg-amber-100 text-amber-800',
    explica: 'La varilla coincide con el cuentalitros, así que el combustible se movió como dice. Lo que no cuadra es lo que Orpak registró: una tarjeta que no leyó, un CECO por defecto o un movimiento mal clasificado.',
  },
  'las tres coinciden': {
    label: 'Cuadra',
    cls: 'bg-emerald-100 text-emerald-800',
    explica: 'Varilla, cuentalitros y Orpak dicen lo mismo.',
  },
  incompleto: {
    label: 'Sin contador',
    cls: 'bg-orange-100 text-orange-800',
    explica: 'Falta leer algún cuentalitros. Sin eso no hay control cruzado: no se puede saber.',
  },
  'sin movimiento': {
    label: 'Sin movimiento',
    cls: 'bg-gray-100 text-gray-500',
    explica: 'El punto no operó ese día.',
  },
}

export type Triangulo = {
  faena_id: string
  fecha: string
  grupo: string
  puntos: string
  por_varilla: number
  por_contador: number
  por_sistema: number
  fuente: 'orpak' | 'terreno' | 'sin_registro'
  contador_menos_varilla: number
  contador_menos_sistema: number
  sistema_menos_varilla: number
  variacion_estacion: number
  diagnostico: string
}

export async function getTriangulo(faenaId: string, desde: string, hasta: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_triangulo').select('*')
    .eq('faena_id', faenaId).gte('fecha', desde).lte('fecha', hasta)
    .order('fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as Triangulo[]
}

// ── Variación acumulada ─────────────────────────────────────────────────────
//
// La variación de UN día no sirve para decidir nada. Una varilla tiene ±0,3 %
// de incertidumbre por su propia física — el menisco, la inclinación del
// estanque, la temperatura del día. En un estanque de 50.000 litros eso son
// 150 litros de ruido legítimo todos los días.
//
// Lo que sí decide es el acumulado del mes: si el ruido es ruido, se compensa
// y la suma tiende a cero. Si hay una pérdida real, la suma se va para un lado
// y no vuelve.

export type VariacionMes = {
  faena_id: string
  mes: string
  grupo: string
  hasta: string
  variacion_acumulada: number
  despachado_acumulado: number
  variacion_pct: number | null
  estado_mes: 'normal' | 'vigilar' | 'investigar' | 'sin_datos'
}

export const ESTADO_MES_UI: Record<string, { label: string; cls: string }> = {
  normal:     { label: 'Normal',     cls: 'bg-emerald-100 text-emerald-800' },
  vigilar:    { label: 'Vigilar',    cls: 'bg-amber-100 text-amber-800' },
  investigar: { label: 'Investigar', cls: 'bg-red-100 text-red-800' },
  sin_datos:  { label: 'Sin datos',  cls: 'bg-gray-100 text-gray-500' },
}

export async function getVariacionMes(faenaId: string, mes: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_variacion_mes').select('*')
    .eq('faena_id', faenaId).eq('mes', mes).order('grupo')
  if (error) throw error
  return (data ?? []) as VariacionMes[]
}

export type VariacionDia = {
  fecha: string
  grupo: string
  variacion_dia: number
  variacion_acumulada: number
  despachado_acumulado: number
  variacion_pct: number | null
  diagnostico: string
}

export async function getVariacionSerie(faenaId: string, mes: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_variacion_acumulada').select('*')
    .eq('faena_id', faenaId).eq('mes', mes).order('fecha')
  if (error) throw error
  return (data ?? []) as VariacionDia[]
}

// ── Reabrir un cierre firmado ───────────────────────────────────────────────
//
// Alguien va a firmar con un error la primera semana. Sin salida, ese callejón
// cuesta la confianza del turno entero: al segundo día nadie firma "por si
// acaso" y el cierre deja de existir.
// El motivo es obligatorio porque un cierre firmado ya se informó al mandante,
// y cada reapertura queda en bitácora.

export async function reabrirCierre(cierreId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_reabrir_cierre', {
    p_cierre_id: cierreId, p_motivo: motivo,
  })
  if (error) throw error
  return data as { cierre_id: string; reaperturas: number }
}

export async function getBitacoraCierre(cierreId: string) {
  const { data, error } = await supabase
    .from('combustible_faena_cierre_bitacora').select('*')
    .eq('cierre_id', cierreId).order('ocurrido_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as {
    id: string; accion: string; motivo: string | null
    usuario: string | null; ocurrido_at: string
  }[]
}

// ── Reemplazar un cuentalitros ──────────────────────────────────────────────
//
// Un contador se cambia y el numeral vuelve a cero. Es un evento normal de
// faena, no una excepción: sin esto, el día del cambio el cierre se bloquea
// porque "el contador no puede bajar".

export async function reemplazarMedidor(p: {
  medidorId: string
  numeralRetiro: number
  numeralInicial?: number
  serieNueva?: string | null
  motivo?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_reemplazar_medidor', {
    p_medidor_id: p.medidorId,
    p_numeral_retiro: p.numeralRetiro,
    p_numeral_inicial: p.numeralInicial ?? 0,
    p_serie_nueva: p.serieNueva ?? null,
    p_motivo: p.motivo ?? null,
  })
  if (error) throw error
  return data as { medidor_nuevo: string; numeral_al_retiro: number }
}

// ── CECO que Orpak usa y el maestro no tiene ────────────────────────────────

export type CecoDesconocido = {
  faena_id: string
  ceco_codigo: string
  departamento: string
  transacciones: number
  litros: number
  desde: string
  hasta: string
}

export async function getCecosDesconocidos(faenaId: string) {
  const { data, error } = await supabase
    .from('v_comb_orpak_ceco_desconocido').select('*')
    .eq('faena_id', faenaId).order('litros', { ascending: false }).limit(100)
  if (error) throw error
  return (data ?? []) as CecoDesconocido[]
}

// ── Los cierres del mes, para poder reabrir el que corresponda ──────────────

export type CierreMes = {
  id: string
  fecha: string
  turno: string | null
  estado: string
  medido_por: string | null
  firmado_at: string | null
  reaperturas: number
  motivo_reapertura: string | null
}

export async function getCierresMes(faenaId: string, desde: string, hasta: string) {
  const { data, error } = await supabase
    .from('combustible_faena_cierre')
    .select('id, fecha, turno, estado, medido_por, firmado_at, reaperturas, motivo_reapertura')
    .eq('faena_id', faenaId).gte('fecha', desde).lte('fecha', hasta)
    .order('fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as CierreMes[]
}
