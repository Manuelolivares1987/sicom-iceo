'use client'

// ============================================================================
// Guía de uso — SICOM en Franke (MIG696)
// ----------------------------------------------------------------------------
// «No se ocupa porque la señal es malísima y no se ha dado a conocer, eso es
// clave» (Manuel, 15-11-2026). Esta página es el material de difusión: se
// muestra en la charla de inicio de turno, se imprime para el comedor/bodega y
// se manda el enlace al grupo. Abre sin señal (caché de 30 días de /m/franke).
// ============================================================================

import Link from 'next/link'
import { ChevronLeft, CloudOff, MessagesSquare, Printer, ScanBarcode, ArrowLeftRight, Fuel, ClipboardList } from 'lucide-react'

const PASOS = [
  {
    icono: CloudOff, titulo: 'Funciona sin señal',
    texto: [
      'Abra cada pantalla UNA vez con señal (en el campamento o en Taltal). Desde ahí queda guardada en el teléfono.',
      'Lo que registre sin señal queda guardado y sube solo cuando vuelva la señal. Abajo a la izquierda aparece «N sin subir».',
      'No cierre sesión: si cierra sesión sin señal, no podrá volver a entrar hasta tener señal.',
    ],
  },
  {
    icono: MessagesSquare, titulo: 'Bitácora del turno (todos los días)', href: '/m/franke/bitacora',
    texto: [
      'Escriba lo que pasó en el turno: 10 segundos. Elija categoría y si es Normal, Importante o Crítica.',
      'Crítica = algo que el otro supervisor TIENE que saber (seguridad, camión con falla, exigencia del mandante).',
      'Al entrar, revise «Para leer» y marque «Leído y entendido»: el otro supervisor ve su nombre y la hora.',
      'Si una crítica no se lee en 12 horas, el resumen del día siguiente avisa a jefatura.',
      'Pendientes: lo que queda por hacer, para qué turno y para cuándo. Se cierran diciendo cómo se resolvió.',
    ],
  },
  {
    icono: ArrowLeftRight, titulo: 'Entrega de turno (cada cambio 7×7)', href: '/m/franke/entrega',
    texto: [
      'El día antes del cambio, con señal, abra la entrega: queda guardada para el día del cambio.',
      'El que entra lee primero «Resumen 7 días» en la bitácora; después conversan en persona o por teléfono.',
      'Firma el que entrega y firma el que recibe. Sin señal las firmas quedan guardadas y suben solas.',
    ],
  },
  {
    icono: ScanBarcode, titulo: 'Bodega con lector', href: '/m/franke/bodega',
    texto: [
      'Sacar: dispare el lector sobre la etiqueta. Los repuestos piden el camión; el agua y el EPP van a la operación.',
      'Recibir: lo que llega desde Coquimbo. Contar: el inventario (lo aprueba administración).',
      'Si algo queda bajo el mínimo, se avisa solo a los supervisores y a bodega Coquimbo.',
    ],
  },
  {
    icono: Fuel, titulo: 'Despacho de combustible', href: '/m/franke/despacho',
    texto: ['Cada carga con su folio de ticket. Funciona sin señal.'],
  },
  {
    icono: ClipboardList, titulo: 'Revisión de equipos (mecánico)', href: '/m/franke/pauta',
    texto: ['La pauta diaria por equipo. Funciona sin señal; las fotos suben después.'],
  },
]

export default function GuiaFrankePage() {
  return (
    <div className="min-h-screen bg-white pb-16 print:pb-0">
      <header className="border-b px-4 pb-3 pt-[max(1rem,env(safe-area-inset-top))] print:border-0">
        <Link href="/m/franke" className="mb-1 inline-flex items-center gap-1 text-xs text-gray-500 print:hidden"><ChevronLeft className="h-3.5 w-3.5" /> Franke</Link>
        <div className="flex items-start justify-between gap-2">
          <div>
            <p className="text-xl font-bold text-gray-900">SICOM en Franke: cómo se usa</p>
            <p className="text-sm text-gray-600">Para supervisores, mecánicos y conductores · funciona sin señal</p>
          </div>
          <button onClick={() => window.print()} className="flex items-center gap-1 rounded-lg border px-3 py-1.5 text-xs font-medium print:hidden">
            <Printer className="h-4 w-4" /> Imprimir
          </button>
        </div>
      </header>

      <main className="space-y-4 px-4 py-4">
        <div className="rounded-xl border-2 border-gray-900 p-3 text-sm">
          <p className="font-bold">La regla del turno</p>
          <p className="mt-1">Lo crítico que no está en la bitácora <b>no cuenta como entregado</b>. WhatsApp sirve para coordinar, pero lo que el otro turno tiene que saber va a SICOM.</p>
        </div>
        {PASOS.map((p) => (
          <section key={p.titulo} className="break-inside-avoid rounded-xl border p-3">
            <p className="flex items-center gap-2 text-base font-bold text-gray-900"><p.icono className="h-5 w-5" /> {p.titulo}</p>
            <ol className="mt-2 list-decimal space-y-1 pl-5 text-sm text-gray-700">
              {p.texto.map((t) => <li key={t}>{t}</li>)}
            </ol>
            {p.href && <Link href={p.href} className="mt-2 inline-block text-sm font-semibold text-emerald-800 underline print:hidden">Abrir</Link>}
          </section>
        ))}
        <p className="text-xs text-gray-500">Dudas o algo que no funciona: use el botón de sugerencias de la app o avise a Manuel Olivares. Dirección: pilladoiceo.netlify.app/m/franke</p>
      </main>
    </div>
  )
}
