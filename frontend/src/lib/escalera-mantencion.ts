// ============================================================================
// Escalera de mantención por horas — reprogramar la próxima (MIG642)
// ----------------------------------------------------------------------------
// Se elige qué pauta toca y a qué horómetro (X). Las bases quedan así:
//   · la elegida (F):                      X − F
//   · las menores que dividen a F:          X − f  (se absorben en X)
//   · las mayores que son múltiplo de F:    X − F  (cuentan desde el peldaño
//                                                   anterior a X)
//   · las que no calzan (6.000, 8.000…):    sin cambio
// La misma regla está en rpc_escalera_reprogramar; si cambia una, cambia la otra.
// ============================================================================

export type PeldanoEscalera = {
  id: string
  nombre: string
  frecuencia_horas: number
  ultima_ejecucion_horas: number | null
}

export type BaseReprogramada = PeldanoEscalera & { base_nueva: number | null }

const divide = (a: number, b: number) => b % a === 0

export function reprogramarEscalera(pautas: PeldanoEscalera[], planId: string, x: number): BaseReprogramada[] {
  const elegida = pautas.find((p) => p.id === planId)
  if (!elegida) return pautas.map((p) => ({ ...p, base_nueva: null }))
  const F = elegida.frecuencia_horas
  return pautas.map((p) => {
    const f = p.frecuencia_horas
    let base: number | null = null
    if (p.id === planId) base = x - F
    else if (f < F && divide(f, F)) base = x - f
    else if (f > F && divide(F, f)) base = x - F
    return { ...p, base_nueva: base }
  })
}

/** Horómetro máximo para la próxima: ninguna base puede quedar sobre el actual. */
export function limiteProxima(pautas: BaseReprogramada[], x: number, horometro: number): number | null {
  const cambiadas = pautas.filter((p) => p.base_nueva != null)
  if (!cambiadas.length) return null
  const mayorBase = Math.max(...cambiadas.map((p) => p.base_nueva!))
  return horometro + (x - mayorBase)
}

/**
 * Las próximas n mantenciones con las bases dadas: en cada punto se hace la
 * pauta mayor que vence (absorbe a las menores).
 */
export function secuenciaEscalera(
  pautas: { nombre: string; frecuencia_horas: number; base: number | null }[],
  n = 6,
): { horas: number; nombre: string }[] {
  const conBase = pautas.filter((p) => p.base != null && p.frecuencia_horas > 0)
  if (!conBase.length) return []
  const vence = conBase.map((p) => ({ ...p, prox: p.base! + p.frecuencia_horas }))
  const out: { horas: number; nombre: string }[] = []
  while (out.length < n) {
    const t = Math.min(...vence.map((v) => v.prox))
    const tocan = vence.filter((v) => Math.abs(v.prox - t) < 1)
    const mayor = tocan.reduce((a, b) => (b.frecuencia_horas > a.frecuencia_horas ? b : a))
    out.push({ horas: t, nombre: mayor.nombre })
    // Absorción: todas las que vencen ahí (y las menores de la escalera) parten de t.
    for (const v of vence) {
      if (Math.abs(v.prox - t) < 1 || (v.frecuencia_horas < mayor.frecuencia_horas && divide(v.frecuencia_horas, mayor.frecuencia_horas))) {
        v.prox = t + v.frecuencia_horas
      }
    }
  }
  return out
}
