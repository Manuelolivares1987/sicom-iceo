// ============================================================================
// Escrituras que de verdad se guardaron (22-11-2026)
// ----------------------------------------------------------------------------
// Bajo RLS, un UPDATE/DELETE que la regla no deja pasar NO da error: termina
// bien y no toca ninguna fila. Sin pedir las filas de vuelta (.select('id')),
// la pantalla decía «guardado» y no se había guardado nada. Así se perdieron
// fotos de Taller (12-11) y se «cerraban» desviaciones que seguían abiertas.
// ============================================================================

export function exigirFilas(filas: unknown[] | null | undefined, que = 'este cambio'): void {
  if (!filas || filas.length === 0) {
    throw new Error(`No se guardó ${que}: no tienes permiso para hacerlo o el registro ya no existe.`)
  }
}
