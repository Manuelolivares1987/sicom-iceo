// Carga del camión en la EDS sin señal (F3, 20-11-2026).
// El registro va a la bandeja con su identificador (carga-<fecha>-<folio>, el
// mismo client_uuid que ya usaba el servidor: reintentar no duplica). La foto
// del ticket viaja aparte y no se vuelve a subir si ya llegó.

import { encolar, registrarTipo, sincronizarBandeja, listarBandeja } from '@/lib/offline/bandeja'
import { registrarRecepcion, subirFotoMedicion, type RecepcionInput } from '@/lib/services/combustible-cierre'

export const TIPO_CARGA = 'franke-carga'

registrarTipo(TIPO_CARGA, async (op, subirBlob) => {
  const p = op.payload as unknown as RecepcionInput
  const foto = await subirBlob('foto', (b) => subirFotoMedicion(b))
  await registrarRecepcion({ ...p, fotoGuia: foto ?? p.fotoGuia ?? null, sinSenal: true })
})

export async function encolarCarga(input: RecepcionInput, foto: Blob | null, resumen: string): Promise<void> {
  const id = input.clientUuid || `carga-${input.fecha}-${Date.now()}`
  await encolar({
    id, tipo: TIPO_CARGA, resumen,
    payload: { ...input, clientUuid: id } as unknown as Record<string, unknown>,
    blobs: foto ? { foto } : undefined,
  })
  void sincronizarBandeja(true)
}

export type CargaLocal = { id: string; guia: string | null; camion: string | null; proveedor: string | null; hora: string | null; litros_guia: number | null; estado: string; error?: string | null }

/** Cargas del día que siguen en el teléfono (para mostrarlas con ⏱). */
export async function cargasLocalesDelDia(fecha: string): Promise<CargaLocal[]> {
  return (await listarBandeja(TIPO_CARGA))
    .filter((o) => (o.payload as { fecha?: string }).fecha === fecha)
    .map((o) => {
      const p = o.payload as unknown as RecepcionInput
      return { id: o.id, guia: p.guia ?? null, camion: p.camion ?? null, proveedor: p.proveedor ?? null, hora: p.hora ?? null,
               litros_guia: p.litrosGuia ?? null, estado: o.estado, error: o.error }
    })
}
