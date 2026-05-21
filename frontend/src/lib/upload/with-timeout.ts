// Envuelve una Promise con timeout. Si no resuelve dentro del plazo, rechaza
// con un Error cuyo mensaje contiene 'timeout' para que looksLikeNetworkError
// en calama-smart-handlers lo trate como red caida y dispare el fallback
// offline (guardar en IndexedDB y reintentar despues).
//
// Caveat: no aborta la operacion subyacente (Supabase storage no expone signal
// directo en upload). La operacion puede completar luego en background — vale
// la pena el tradeoff: "error claro reintentable" gana a "spinner infinito".

export class TimeoutError extends Error {
  constructor(ms: number, label?: string) {
    super(`${label ? label + ' ' : ''}connection timeout (${ms}ms)`)
    this.name = 'TimeoutError'
  }
}

export function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  label?: string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new TimeoutError(ms, label)), ms)
  })
  return Promise.race([
    promise.finally(() => { if (timer) clearTimeout(timer) }),
    timeout,
  ])
}
