// ============================================================================
// Traer TODAS las filas (22-11-2026)
// ----------------------------------------------------------------------------
// Supabase corta cada consulta en 1.000 filas (max_rows) SIN avisar. Reportes,
// exportaciones y totales en pesos quedaban incompletos y se veían completos.
// Esto pide de a 1.000 (.range) hasta que viene una página corta.
// ============================================================================

type Pagina<T> = PromiseLike<{ data: T[] | null; error: unknown }>

export async function traerTodo<T>(
  pagina: (desde: number, hasta: number) => Pagina<T>,
  tamano = 1000,
  tope = 100_000,
): Promise<T[]> {
  const out: T[] = []
  for (let desde = 0; desde < tope; desde += tamano) {
    const { data, error } = await pagina(desde, desde + tamano - 1)
    if (error) throw error
    const filas = data ?? []
    out.push(...filas)
    if (filas.length < tamano) break
  }
  return out
}

/** Fecha local (YYYY-MM-DD) → instante ISO del inicio/fin de ese día en la hora
 *  del navegador (Chile). Antes se mandaba «T00:00:00» sin zona y la base lo
 *  leía en UTC: el rango quedaba corrido 3-4 horas. */
export function inicioDelDia(fecha: string): string {
  return new Date(`${fecha}T00:00:00`).toISOString()
}
export function finDelDia(fecha: string): string {
  return new Date(`${fecha}T23:59:59.999`).toISOString()
}

/** Igual que `await consulta`, pero con TODAS las páginas. `construir` arma la
 *  consulta de nuevo para cada página (con sus filtros y su orden). */
export async function paginado<T>(construir: () => any): Promise<{ data: T[] | null; error: { message: string; code?: string } | null }> {
  try {
    const data = await traerTodo<T>((desde, hasta) => construir().range(desde, hasta))
    return { data, error: null }
  } catch (e) {
    const x = e as { message?: string; code?: string }
    return { data: null, error: { message: x?.message ?? String(e), code: x?.code } }
  }
}
