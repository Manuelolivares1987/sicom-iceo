'use client'

// ============================================================================
// Card del QR del equipo: visualizar, copiar enlace, descargar PNG e imprimir
// etiqueta. Apunta a la ruta pública /equipo/[id]/checklist.
// ============================================================================

import { useEffect, useRef, useState } from 'react'
import { QRCodeCanvas } from 'qrcode.react'
import { Copy, Download, Printer, Check, AlertTriangle, Link2 } from 'lucide-react'

interface Props {
  activoId: string
  codigo: string
  nombre?: string | null
  /** Si la columna existe en la BD y la ficha la trae, se respeta. Si es undefined, no se muestra advertencia. */
  qrPublicoHabilitado?: boolean | null
}

function safeFilename(s: string): string {
  return s.replace(/[^A-Za-z0-9._-]/g, '-').replace(/^-+|-+$/g, '') || 'equipo'
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

export function EquipoQrCard({ activoId, codigo, nombre, qrPublicoHabilitado }: Props) {
  const wrapperRef = useRef<HTMLDivElement>(null)
  const [origin, setOrigin] = useState('')
  const [copiado, setCopiado] = useState(false)

  useEffect(() => {
    if (typeof window !== 'undefined') setOrigin(window.location.origin)
  }, [])

  const url = origin ? `${origin}/equipo/${activoId}/checklist` : ''
  const habilitadoConocido = typeof qrPublicoHabilitado === 'boolean'
  const deshabilitado = habilitadoConocido && qrPublicoHabilitado === false

  const handleCopiar = async () => {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(url)
      } else {
        // Fallback para móviles antiguos
        const ta = document.createElement('textarea')
        ta.value = url
        ta.style.position = 'fixed'
        ta.style.opacity = '0'
        document.body.appendChild(ta)
        ta.select()
        document.execCommand('copy')
        document.body.removeChild(ta)
      }
      setCopiado(true)
      setTimeout(() => setCopiado(false), 2000)
    } catch (e) {
      // ignore
    }
  }

  const getCanvas = (): HTMLCanvasElement | null => {
    return wrapperRef.current?.querySelector('canvas') ?? null
  }

  const handleDescargar = () => {
    const canvas = getCanvas()
    if (!canvas) return
    const dataUrl = canvas.toDataURL('image/png')
    const a = document.createElement('a')
    a.download = `qr-checklist-${safeFilename(codigo)}.png`
    a.href = dataUrl
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
  }

  const handleImprimir = () => {
    const canvas = getCanvas()
    if (!canvas) return
    const dataUrl = canvas.toDataURL('image/png')
    const win = window.open('', '_blank', 'width=420,height=600')
    if (!win) {
      alert('Habilite las ventanas emergentes para imprimir la etiqueta.')
      return
    }
    const codigoSafe = escapeHtml(codigo)
    const nombreSafe = nombre ? escapeHtml(nombre) : ''
    const urlSafe = escapeHtml(url)
    win.document.write(`<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Etiqueta QR — ${codigoSafe}</title>
<style>
  @page { size: 80mm 110mm; margin: 4mm; }
  @media print { body { margin: 0; } .no-print { display: none !important; } }
  body { font-family: -apple-system, 'Segoe UI', Roboto, system-ui, sans-serif; margin: 0; padding: 12px; }
  .label { width: 320px; max-width: 100%; margin: 0 auto; padding: 14px; border: 2px solid #000; border-radius: 8px; text-align: center; box-sizing: border-box; background: #fff; }
  .brand { font-size: 11px; font-weight: 800; letter-spacing: 0.18em; color: #16a34a; text-transform: uppercase; margin-bottom: 4px; }
  .title { font-family: ui-monospace, 'Menlo', monospace; font-size: 22px; font-weight: 800; color: #000; margin: 2px 0; }
  .subtitle { font-size: 11px; color: #555; margin-bottom: 10px; line-height: 1.2; }
  .instruction { font-size: 11px; font-weight: 700; margin: 10px 0 6px; color: #111; }
  img.qr { width: 240px; height: 240px; max-width: 100%; margin: 0 auto; display: block; }
  .url { font-family: ui-monospace, 'Menlo', monospace; font-size: 9px; color: #555; word-break: break-all; margin-top: 10px; line-height: 1.3; }
  .footer { font-size: 9px; color: #888; margin-top: 6px; font-style: italic; }
  .actions { text-align: center; margin-top: 14px; }
  .actions button { font-size: 13px; padding: 8px 14px; border: 1px solid #16a34a; background: #16a34a; color: #fff; border-radius: 6px; cursor: pointer; font-weight: 600; }
</style>
</head>
<body>
  <div class="label">
    <div class="brand">Pillado</div>
    <div class="title">${codigoSafe}</div>
    ${nombreSafe ? `<div class="subtitle">${nombreSafe}</div>` : ''}
    <div class="instruction">Escanee para realizar checklist diario</div>
    <img class="qr" src="${dataUrl}" alt="QR">
    <div class="url">${urlSafe}</div>
    <div class="footer">Uso interno operacional</div>
  </div>
  <div class="actions no-print">
    <button onclick="window.print()">Imprimir</button>
  </div>
  <script>window.addEventListener('load', function(){ setTimeout(function(){ window.print(); }, 350); });</script>
</body>
</html>`)
    win.document.close()
  }

  return (
    <section className="rounded-2xl border-2 border-gray-200 bg-white p-5">
      <div className="flex items-start justify-between gap-3 mb-4">
        <div>
          <h2 className="text-sm font-bold uppercase tracking-wide text-gray-500">
            QR del equipo para checklist
          </h2>
          <p className="text-xs text-gray-500 mt-1">
            Imprima esta etiqueta y péguela visible en el equipo. El operador la escanea
            para iniciar la inspección diaria.
          </p>
        </div>
        {habilitadoConocido && (
          <span className={`shrink-0 rounded-full border px-3 py-1 text-[11px] font-bold ${
            qrPublicoHabilitado
              ? 'bg-pillado-green-50 border-pillado-green-300 text-pillado-green-800'
              : 'bg-gray-100 border-gray-300 text-gray-600'
          }`}>
            {qrPublicoHabilitado ? 'QR habilitado' : 'QR deshabilitado'}
          </span>
        )}
      </div>

      {deshabilitado && (
        <div className="mb-4 rounded-lg border-2 border-orange-300 bg-orange-50 p-3 flex items-start gap-2">
          <AlertTriangle className="h-5 w-5 text-orange-700 shrink-0 mt-0.5" />
          <div>
            <p className="text-sm font-semibold text-orange-900">
              Este QR está deshabilitado
            </p>
            <p className="text-xs text-orange-800 mt-0.5">
              Actívelo en la ficha del equipo (campo <code>qr_publico_habilitado</code>) antes
              de imprimirlo, o el operador verá una página vacía al escanear.
            </p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-[auto,1fr] gap-5 items-center">
        {/* QR */}
        <div ref={wrapperRef} className="rounded-xl border border-gray-200 bg-white p-4 flex items-center justify-center mx-auto">
          {origin ? (
            <QRCodeCanvas
              value={url}
              size={224}
              level="M"
              includeMargin
              bgColor="#FFFFFF"
              fgColor="#000000"
            />
          ) : (
            <div className="h-56 w-56 animate-pulse rounded-lg bg-gray-100" />
          )}
        </div>

        {/* Info + acciones */}
        <div className="space-y-3">
          <div>
            <p className="text-[11px] uppercase tracking-wide font-bold text-gray-400">Equipo</p>
            <p className="font-mono text-lg font-bold text-gray-900">{codigo}</p>
            {nombre && <p className="text-sm text-gray-600">{nombre}</p>}
          </div>

          <div>
            <p className="text-[11px] uppercase tracking-wide font-bold text-gray-400">Enlace público</p>
            <div className="mt-1 flex items-center gap-2 rounded-lg bg-gray-50 border border-gray-200 px-3 py-2">
              <Link2 className="h-4 w-4 text-gray-400 shrink-0" />
              <p className="font-mono text-xs text-gray-700 break-all flex-1">
                {url || 'Cargando...'}
              </p>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 pt-2">
            <button
              type="button"
              onClick={handleCopiar}
              disabled={!url}
              className="flex items-center justify-center gap-2 rounded-lg bg-white border-2 border-gray-300 px-3 py-3 text-sm font-semibold text-gray-700 hover:bg-gray-50 disabled:opacity-50"
            >
              {copiado ? <Check className="h-4 w-4 text-pillado-green-600" /> : <Copy className="h-4 w-4" />}
              {copiado ? 'Enlace copiado' : 'Copiar enlace'}
            </button>
            <button
              type="button"
              onClick={handleDescargar}
              disabled={!url}
              className="flex items-center justify-center gap-2 rounded-lg bg-white border-2 border-gray-300 px-3 py-3 text-sm font-semibold text-gray-700 hover:bg-gray-50 disabled:opacity-50"
            >
              <Download className="h-4 w-4" />
              Descargar QR
            </button>
            <button
              type="button"
              onClick={handleImprimir}
              disabled={!url}
              className="flex items-center justify-center gap-2 rounded-lg bg-pillado-green-600 px-3 py-3 text-sm font-semibold text-white hover:bg-pillado-green-700 disabled:opacity-50"
            >
              <Printer className="h-4 w-4" />
              Imprimir etiqueta
            </button>
          </div>
        </div>
      </div>

      <p className="mt-4 text-[11px] text-gray-500">
        El QR no contiene tokens ni datos sensibles — solo el ID público del equipo.
        La ruta destino es de solo escritura para anónimos vía RPC controlada.
      </p>
    </section>
  )
}
