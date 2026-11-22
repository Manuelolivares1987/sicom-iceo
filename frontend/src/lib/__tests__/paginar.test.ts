import { describe, it, expect } from 'vitest'
import { traerTodo } from '../services/paginar'

const servidor = (total: number) => {
  const pedidos: Array<[number, number]> = []
  const pagina = (desde: number, hasta: number) => {
    pedidos.push([desde, hasta])
    const n = Math.max(0, Math.min(hasta, total - 1) - desde + 1)
    return Promise.resolve({ data: Array.from({ length: n }, (_, i) => desde + i), error: null })
  }
  return { pagina, pedidos }
}

describe('traerTodo: no se corta en 1.000 filas', () => {
  it('2.500 filas → 3 páginas, todas las filas en orden', async () => {
    const s = servidor(2500)
    const filas = await traerTodo<number>(s.pagina)
    expect(filas).toHaveLength(2500)
    expect(filas[2499]).toBe(2499)
    expect(s.pedidos).toEqual([[0, 999], [1000, 1999], [2000, 2999]])
  })

  it('justo 1.000 filas → pide una página más (vacía) y termina', async () => {
    const s = servidor(1000)
    expect(await traerTodo<number>(s.pagina)).toHaveLength(1000)
    expect(s.pedidos).toHaveLength(2)
  })

  it('un error de la base se propaga (no devuelve datos a medias)', async () => {
    await expect(traerTodo(() => Promise.resolve({ data: null, error: { message: 'timeout' } }))).rejects.toEqual({ message: 'timeout' })
  })
})
