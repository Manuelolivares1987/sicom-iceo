'use client'

// Bajar todos los papeles del equipo en un ZIP desde la ficha pública del QR,
// igual que el portal de flota (descargarZip arma el archivo en el navegador).

import { useState } from 'react'
import { FileArchive } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { descargarZip } from '@/lib/services/portal-flota'

export function DescargarDocumentosZip({
  patente, docs, className,
}: {
  patente: string
  docs: { etiqueta: string; url: string | null }[]
  className?: string
}) {
  const [progreso, setProgreso] = useState<{ hechos: number; total: number } | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const conArchivo = docs.filter((d): d is { etiqueta: string; url: string } => !!d.url)
  if (conArchivo.length === 0) return null

  const bajar = async () => {
    setAviso(null)
    setProgreso({ hechos: 0, total: conArchivo.length })
    try {
      const { fallidos } = await descargarZip(patente, conArchivo, (hechos, total) => setProgreso({ hechos, total }))
      if (fallidos.length) setAviso(`No se pudieron incluir: ${fallidos.join(', ')}. Descárguelos uno a uno.`)
    } catch {
      setAviso('No se pudo armar el ZIP. Descargue los documentos uno a uno.')
    } finally {
      setProgreso(null)
    }
  }

  return (
    <div className={className}>
      <button onClick={bajar} disabled={!!progreso}
              className={cn('flex w-full items-center justify-center gap-1.5 rounded-lg border border-pillado-green-600 px-3 py-2',
                            'text-xs font-semibold text-pillado-green-700 hover:bg-pillado-green-50 disabled:opacity-60')}>
        {progreso
          ? <><Spinner className="h-3.5 w-3.5" /> Preparando {progreso.hechos}/{progreso.total}…</>
          : <><FileArchive className="h-3.5 w-3.5" /> Descargar toda la documentación (ZIP, {conArchivo.length})</>}
      </button>
      {aviso && <p className="mt-1 text-[11px] text-orange-700">{aviso}</p>}
    </div>
  )
}
