import { describe, it, expect } from 'vitest'
import { aplicarAvanceEnItems, type AuditoriaItem } from '@/hooks/use-control-calidad'

/**
 * El caché de ítems vive 5 min (staleTime global). Si el autoguardado no lo
 * refleja, al volver a la auditoría se lee la copia anterior y el comentario
 * técnico aparece en blanco pese a estar grabado en la BD.
 */

const item = (over: Partial<AuditoriaItem> = {}): AuditoriaItem => ({
  id: 'i1',
  categoria: 'tecnica',
  orden: 1,
  descripcion: 'Corta corriente',
  obligatorio: true,
  critico: false,
  resultado: 'pendiente',
  observacion: null,
  foto_url: null,
  referencia_cert_id: null,
  bloque: 'B01',
  bloque_orden: 1,
  requiere_foto: false,
  aplica_tipo: true,
  ...over,
})

describe('aplicarAvanceEnItems', () => {
  it('guarda la observación recién escrita en el ítem que corresponde', () => {
    const r = aplicarAvanceEnItems(
      [item(), item({ id: 'i2' })],
      [{ id: 'i1', observacion: 'La llave de accionamiento está dura' }],
    )
    expect(r[0].observacion).toBe('La llave de accionamiento está dura')
    expect(r[1].observacion).toBeNull()
  })

  it('un patch de solo foto no borra la observación ya guardada', () => {
    const r = aplicarAvanceEnItems(
      [item({ observacion: 'Necesita limpieza' })],
      [{ id: 'i1', foto_url: 'https://x/f.jpg' }],
    )
    expect(r[0].observacion).toBe('Necesita limpieza')
    expect(r[0].foto_url).toBe('https://x/f.jpg')
  })

  it('un patch de solo resultado no toca foto ni observación', () => {
    const r = aplicarAvanceEnItems(
      [item({ observacion: 'ojo acá', foto_url: 'https://x/a.jpg' })],
      [{ id: 'i1', resultado: 'no_ok' }],
    )
    expect(r[0]).toMatchObject({
      resultado: 'no_ok', observacion: 'ojo acá', foto_url: 'https://x/a.jpg',
    })
  })

  it('borrar el comentario a propósito sí queda vacío', () => {
    const r = aplicarAvanceEnItems(
      [item({ observacion: 'texto viejo' })],
      [{ id: 'i1', observacion: '' }],
    )
    expect(r[0].observacion).toBe('')
  })

  it('deja intactos los ítems que no vienen en el patch', () => {
    const items = [item(), item({ id: 'i2', observacion: 'otra' })]
    const r = aplicarAvanceEnItems(items, [{ id: 'i1', resultado: 'ok' }])
    expect(r[1]).toBe(items[1])
    expect(aplicarAvanceEnItems(items, [])).toBe(items)
  })
})
