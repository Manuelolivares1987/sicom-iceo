'use client'

// ============================================================================
// Copiloto Técnico — piezas de la interfaz del mecánico (2026-09-19).
// Respuesta en markdown con citas [Fn] tocables, fuentes con miniatura de la
// página (diagramas) y visor a pantalla completa con zoom, tarjetas de
// códigos de falla y la ficha técnica del camión.
// ============================================================================

import { useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  X, ExternalLink, FileText, Image as ImageIcon, ChevronDown, ChevronUp, Cpu, AlertTriangle,
  ZoomIn, ZoomOut, Truck,
} from 'lucide-react'
import type { FuenteCopiloto, CodigoCopiloto } from '@/lib/copiloto/tipos'

const TIPO_LABEL: Record<string, string> = {
  manual_oficial: 'Manual oficial',
  procedimiento_interno: 'Procedimiento Pillado',
  guia_tecnica_web: 'Guía técnica',
  catalogo_partes: 'Catálogo',
  ficha_tecnica: 'Ficha técnica',
  reporte_falla: 'Falla conocida',
  web: 'Fuente web',
}
const CONF_LABEL: Record<string, { t: string; c: string }> = {
  oficial: { t: 'oficial', c: 'bg-green-100 text-green-700' },
  tecnica_terceros: { t: 'técnica', c: 'bg-blue-100 text-blue-700' },
  experiencia_campo: { t: 'campo · no oficial', c: 'bg-amber-100 text-amber-700' },
}

// ── Respuesta en markdown con citas [Fn] → chips ────────────────────────────
export function RespuestaMarkdown({ texto, onCita }: { texto: string; onCita: (n: number) => void }) {
  const conLinks = texto.replace(/\[F(\d+)\]/g, '[F$1](#cita-$1)')
  return (
    <div className="copiloto-md space-y-2 text-sm leading-relaxed text-gray-800">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          a: ({ href, children }) => {
            const m = href?.match(/^#cita-(\d+)$/)
            if (m) {
              return (
                <button type="button" onClick={() => onCita(Number(m[1]))}
                        className="mx-0.5 inline-flex -translate-y-px items-center rounded bg-indigo-100 px-1 text-[10px] font-bold text-indigo-700">
                  {children}
                </button>
              )
            }
            return <a href={href} target="_blank" rel="noreferrer" className="text-indigo-600 underline">{children}</a>
          },
          p: ({ children }) => <p className="my-1">{children}</p>,
          ul: ({ children }) => <ul className="my-1 list-disc space-y-0.5 pl-5">{children}</ul>,
          ol: ({ children }) => <ol className="my-1 list-decimal space-y-0.5 pl-5">{children}</ol>,
          h1: ({ children }) => <p className="mt-2 font-bold text-gray-900">{children}</p>,
          h2: ({ children }) => <p className="mt-2 font-bold text-gray-900">{children}</p>,
          h3: ({ children }) => <p className="mt-2 font-semibold text-gray-900">{children}</p>,
          strong: ({ children }) => <strong className="font-semibold text-gray-900">{children}</strong>,
          table: ({ children }) => (
            <div className="my-2 overflow-x-auto rounded-lg border">
              <table className="w-full text-left text-[12px]">{children}</table>
            </div>
          ),
          th: ({ children }) => <th className="border-b bg-gray-50 px-2 py-1 font-semibold">{children}</th>,
          td: ({ children }) => <td className="border-b px-2 py-1 align-top">{children}</td>,
          code: ({ children }) => <code className="rounded bg-gray-100 px-1 text-[12px]">{children}</code>,
          blockquote: ({ children }) => <blockquote className="border-l-4 border-amber-300 bg-amber-50 px-2 py-1">{children}</blockquote>,
        }}
      >
        {conLinks}
      </ReactMarkdown>
    </div>
  )
}

// ── Lista de fuentes (con miniatura si la página tiene imagen) ──────────────
export function ListaFuentes({
  fuentes, resaltada, onVer,
}: { fuentes: FuenteCopiloto[]; resaltada: number | null; onVer: (f: FuenteCopiloto) => void }) {
  const [abierta, setAbierta] = useState(true)
  if (!fuentes.length) return null
  const conImagen = fuentes.filter((f) => f.imagen)
  return (
    <div className="mt-2 border-t pt-2">
      {conImagen.length > 0 && (
        <div className="-mx-1 mb-2 flex gap-2 overflow-x-auto px-1 pb-1">
          {conImagen.map((f) => (
            <button key={f.n} type="button" onClick={() => onVer(f)}
                    className="relative h-24 w-20 shrink-0 overflow-hidden rounded-lg border bg-gray-100">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={f.imagen!} alt={`Página ${f.pagina}`} className="h-full w-full object-cover object-top" loading="lazy" />
              <span className="absolute left-1 top-1 rounded bg-indigo-600 px-1 text-[9px] font-bold text-white">F{f.n}</span>
              <span className="absolute inset-x-0 bottom-0 bg-black/55 px-1 py-0.5 text-[9px] text-white">
                <ZoomIn className="mr-0.5 inline h-2.5 w-2.5" />pág. {f.pagina}
              </span>
            </button>
          ))}
        </div>
      )}
      <button type="button" onClick={() => setAbierta((v) => !v)}
              className="flex w-full items-center gap-1 text-[10.5px] font-semibold uppercase tracking-wide text-gray-400">
        Fuentes ({fuentes.length}) {abierta ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
      </button>
      {abierta && (
        <ul className="mt-1 space-y-1">
          {fuentes.map((f) => {
            const conf = f.confiabilidad ? CONF_LABEL[f.confiabilidad] : null
            return (
              <li key={f.n}
                  className={`flex items-start gap-1.5 rounded-md px-1 py-0.5 text-[11.5px] ${resaltada === f.n ? 'bg-indigo-50 ring-1 ring-indigo-300' : ''}`}>
                <span className="mt-px shrink-0 rounded bg-gray-100 px-1 text-[10px] font-bold text-gray-600">F{f.n}</span>
                <div className="min-w-0 flex-1">
                  <p className="leading-tight text-gray-700">
                    {f.titulo} {f.tipo === 'web'
                      ? <span className="text-gray-400">· web</span>
                      : <span className="text-gray-400">· pág. {f.pagina}</span>}
                  </p>
                  <div className="mt-0.5 flex flex-wrap items-center gap-1">
                    <span className="rounded bg-gray-100 px-1 text-[9.5px] text-gray-500">{TIPO_LABEL[f.tipo] ?? f.tipo}</span>
                    {conf && <span className={`rounded px-1 text-[9.5px] ${conf.c}`}>{conf.t}</span>}
                    {f.imagen && (
                      <button type="button" onClick={() => onVer(f)} className="flex items-center gap-0.5 text-[10.5px] font-semibold text-indigo-600">
                        <ImageIcon className="h-3 w-3" /> Ver página
                      </button>
                    )}
                    {f.url && (
                      <a href={f.url} target="_blank" rel="noreferrer" className="flex items-center gap-0.5 text-[10.5px] font-semibold text-indigo-600">
                        <ExternalLink className="h-3 w-3" /> Documento
                      </a>
                    )}
                  </div>
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}

// ── Visor de página a pantalla completa (diagramas) ─────────────────────────
export function VisorPagina({ fuente, onClose }: { fuente: FuenteCopiloto | null; onClose: () => void }) {
  const [zoom, setZoom] = useState(1)
  if (!fuente?.imagen) return null
  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-black">
      <div className="flex items-center gap-2 px-3 py-2 text-white">
        <FileText className="h-4 w-4 shrink-0 text-indigo-300" />
        <p className="min-w-0 flex-1 truncate text-xs">
          <b>F{fuente.n}</b> · {fuente.titulo} · pág. {fuente.pagina}
        </p>
        <button onClick={() => setZoom((z) => Math.max(1, z - 0.5))} className="rounded-full bg-white/10 p-1.5" aria-label="Alejar">
          <ZoomOut className="h-4 w-4" />
        </button>
        <button onClick={() => setZoom((z) => Math.min(4, z + 0.5))} className="rounded-full bg-white/10 p-1.5" aria-label="Acercar">
          <ZoomIn className="h-4 w-4" />
        </button>
        <button onClick={() => { setZoom(1); onClose() }} className="rounded-full bg-white/10 p-1.5" aria-label="Cerrar">
          <X className="h-4 w-4" />
        </button>
      </div>
      {/* touch-action: pan + pinch nativo del navegador sobre la imagen */}
      <div className="flex-1 overflow-auto bg-neutral-900" style={{ touchAction: 'pan-x pan-y pinch-zoom' }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={fuente.imagen} alt={`Página ${fuente.pagina}`}
             style={{ width: `${zoom * 100}%`, maxWidth: 'none' }} className="mx-auto block bg-white" />
      </div>
      {fuente.url && (
        <a href={fuente.url} target="_blank" rel="noreferrer"
           className="flex items-center justify-center gap-1 bg-neutral-800 py-2.5 text-xs font-semibold text-indigo-200">
          <ExternalLink className="h-3.5 w-3.5" /> Abrir documento oficial completo
        </a>
      )}
    </div>
  )
}

// ── Tarjetas de códigos de falla ────────────────────────────────────────────
export function TarjetasCodigos({
  codigos, onPreguntar,
}: { codigos: CodigoCopiloto[]; onPreguntar?: (c: CodigoCopiloto) => void }) {
  if (!codigos.length) return null
  return (
    <div className="space-y-2">
      {codigos.map((c, i) => {
        const conf = CONF_LABEL[c.confiabilidad]
        return (
          <div key={`${c.codigo}-${i}`} className="rounded-xl border border-orange-200 bg-orange-50/60 p-2.5">
            <div className="flex items-start gap-2">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-orange-500" />
              <div className="min-w-0 flex-1">
                <p className="text-[13px] font-bold text-gray-900">
                  {c.codigo}
                  <span className="ml-1 text-[10px] font-normal text-gray-500">{c.formato}{c.marca ? ` · ${c.marca}` : ' · genérico'}</span>
                </p>
                <p className="text-[12.5px] text-gray-800">{c.descripcion}</p>
                {c.aplica && <p className="text-[10.5px] text-gray-500">Aplica: {c.aplica}</p>}
              </div>
            </div>
            {c.causas.length > 0 && (
              <div className="mt-1.5 text-[12px]">
                <p className="font-semibold text-gray-700">Causas probables</p>
                <ol className="list-decimal pl-5 text-gray-700">{c.causas.map((x, j) => <li key={j}>{x}</li>)}</ol>
              </div>
            )}
            {c.comprobaciones.length > 0 && (
              <div className="mt-1 text-[12px]">
                <p className="font-semibold text-gray-700">Comprobaciones</p>
                <ol className="list-decimal pl-5 text-gray-700">{c.comprobaciones.map((x, j) => <li key={j}>{x}</li>)}</ol>
              </div>
            )}
            <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
              {conf && <span className={`rounded px-1 text-[9.5px] ${conf.c}`}>{conf.t}</span>}
              {c.coincidencia === 'mismo_spn' && <span className="rounded bg-gray-100 px-1 text-[9.5px] text-gray-500">mismo SPN, otro FMI</span>}
              {c.fuente && /^https?:/.test(c.fuente) && (
                <a href={c.fuente} target="_blank" rel="noreferrer" className="flex items-center gap-0.5 text-[10.5px] font-semibold text-indigo-600">
                  <ExternalLink className="h-3 w-3" /> Fuente
                </a>
              )}
              {c.fuente && !/^https?:/.test(c.fuente) && <span className="text-[10px] text-gray-400">Fuente: {c.fuente}</span>}
              {onPreguntar && (
                <button type="button" onClick={() => onPreguntar(c)}
                        className="ml-auto rounded-lg bg-indigo-600 px-2 py-1 text-[11px] font-semibold text-white">
                  Diagnosticar con el copiloto
                </button>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}

// ── Ficha técnica del equipo ────────────────────────────────────────────────
export type FichaCliente = {
  patente: string; marca: string | null; modelo: string | null; anio: number | null
  vin: string | null; numero_motor: string | null; motor: string | null; transmision: string | null
  emisiones: string | null; ecus: string | null; equipamiento: string | null; implemento: string | null
  lectura_codigos: string | null; fuente_oem: string | null
}

export function FichaEquipoCard({ ficha }: { ficha: FichaCliente }) {
  const [abierta, setAbierta] = useState(false)
  const filas: [string, string | number | null][] = [
    ['VIN', ficha.vin], ['N° motor', ficha.numero_motor], ['Motor', ficha.motor],
    ['Transmisión', ficha.transmision], ['Emisiones', ficha.emisiones], ['Electrónica', ficha.ecus],
    ['Equipamiento', ficha.equipamiento], ['Implemento', ficha.implemento],
  ]
  return (
    <div className="rounded-xl border border-gray-200 bg-white px-3 py-2">
      <button type="button" onClick={() => setAbierta((v) => !v)} className="flex w-full items-center gap-2 text-left">
        <Truck className="h-4 w-4 shrink-0 text-gray-500" />
        <span className="min-w-0 flex-1 truncate text-xs font-semibold text-gray-800">
          Ficha técnica · {ficha.modelo ?? ''} {ficha.anio ?? ''}{ficha.motor ? ` · ${ficha.motor}` : ''}
        </span>
        {abierta ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
      </button>
      {abierta && (
        <div className="mt-2 space-y-1 text-[11.5px]">
          {filas.filter(([, v]) => v).map(([k, v]) => (
            <div key={k} className="flex gap-2">
              <span className="w-24 shrink-0 text-gray-400">{k}</span>
              <span className="min-w-0 break-words text-gray-800">{v}</span>
            </div>
          ))}
          {ficha.lectura_codigos && (
            <div className="mt-1 rounded-lg bg-indigo-50 p-2 text-[11.5px] text-indigo-900">
              <p className="flex items-center gap-1 font-semibold"><Cpu className="h-3.5 w-3.5" /> Leer códigos en el tablero</p>
              <p className="mt-0.5 whitespace-pre-line">{ficha.lectura_codigos}</p>
            </div>
          )}
          {ficha.fuente_oem && (
            <a href={ficha.fuente_oem} target="_blank" rel="noreferrer"
               className="mt-1 flex items-center gap-1 text-[11px] font-semibold text-indigo-600">
              <ExternalLink className="h-3 w-3" /> Portal OEM (manual de taller por VIN)
            </a>
          )}
        </div>
      )}
    </div>
  )
}
