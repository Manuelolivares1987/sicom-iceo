// Doble de prueba: SICOM falso (sesión/RLS), corpus REAL.
export * from '../src/lib/copiloto/server'
const ACTIVO = { codigo: process.env.T_PATENTE ?? 'KCBY-30', nombre: 'Equipo', patente: process.env.T_PATENTE ?? 'KCBY-30', tipo: 'camion', estado: 'operativo',
  horas_uso_actual: 12000, kilometraje_actual: 210000, anio_fabricacion: 2017,
  modelo: { nombre: process.env.T_MODELO ?? 'Actros 3336 K', marca: { nombre: process.env.T_MARCA ?? 'Mercedes-Benz' } } }
function chain(result: unknown): any {
  const p: any = Promise.resolve(result)
  const self: any = new Proxy(p, { get: (t, k) => (k in t ? (typeof t[k] === 'function' ? t[k].bind(t) : t[k]) : () => self) })
  return self
}
const sb = {
  from: (t: string) => ({
    select: () => chain(t === 'activos' ? { data: ACTIVO, error: null } : { data: [], error: null }),
    insert: () => chain({ data: { id: 'prueba-local' }, error: null }),
    update: () => chain({ data: null, error: null }),
  }),
  rpc: () => chain({ data: [], error: null }),
}
export async function autenticar() { return { sb, uid: 'uid-prueba' } as any }
