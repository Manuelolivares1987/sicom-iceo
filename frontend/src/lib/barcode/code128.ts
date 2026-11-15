// ============================================================================
// Code128 (juego B) → barras para SVG. Sin dependencias.
// ----------------------------------------------------------------------------
// [MIG692] Etiquetas de bodega: el lector físico («pistola») lee Code128 y lo
// teclea seguido de Enter. Se codifica el código del producto tal cual.
// Juego B cubre ASCII 32-126 (letras, números, guiones), que es lo que usan
// los códigos del maestro (ISEEPPCAM001-LB, FRK-0001…).
// ============================================================================

/** Anchos barra/espacio de cada símbolo (0-105) y el de parada. Cada símbolo suma 11 módulos. */
export const PATRONES = [
  '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213',
  '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
  '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
  '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
  '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
  '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
  '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
  '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
  '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
  '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
  '114131', '311141', '411131', '211412', '211214', '211232',
]
export const PARADA = '2331112'
const INICIO_B = 104

export function esCodificable(texto: string): boolean {
  return texto.length > 0 && texto.length <= 40 && texto.split("").every((c) => c.charCodeAt(0) >= 32 && c.charCodeAt(0) <= 126)
}

/** Secuencia de símbolos (con inicio y dígito verificador, sin parada). */
export function simbolos(texto: string): number[] {
  if (!esCodificable(texto)) throw new Error(`No se puede codificar «${texto}» en Code128-B`)
  const valores = texto.split("").map((c) => c.charCodeAt(0) - 32)
  const suma = valores.reduce((s, v, i) => s + v * (i + 1), INICIO_B)
  return [INICIO_B, ...valores, suma % 103]
}

/** Anchos alternados barra/espacio/barra… de todo el código, en módulos. */
export function anchos(texto: string): number[] {
  const out: number[] = []
  for (const s of simbolos(texto)) for (const d of PATRONES[s].split("")) out.push(Number(d))
  for (const d of PARADA.split("")) out.push(Number(d))
  return out
}

/** Rectángulos de las barras (x y ancho en módulos) y ancho total con zona de silencio de 10 módulos. */
export function barras(texto: string): { x: number; w: number }[] & { total?: number } {
  const res: { x: number; w: number }[] = []
  let x = 10
  anchos(texto).forEach((w, i) => {
    if (i % 2 === 0) res.push({ x, w })
    x += w
  })
  return Object.assign(res, { total: x + 10 })
}
