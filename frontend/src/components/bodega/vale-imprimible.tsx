'use client'

// ============================================================================
// El papel del vale (MIG376)
// ----------------------------------------------------------------------------
// Salió de /vale/[id] cuando el portal por link necesitó imprimir el mismo
// documento sin sesión. Es el papel y nada más: quién lo consultó —con cuenta
// o con token— lo resuelve cada pantalla.
//
// TRES VALES, UN SOLO PAPEL
// El del taller va contra un equipo y una OT. El de oficina va contra un centro
// de costo. El del link es un vale de oficina que además dice quién lo pidió
// sin tener cuenta. Lo que cambia son dos casillas, no el documento.
// ============================================================================

import { QRCodeCanvas } from 'qrcode.react'

const ESTADO_LABEL: Record<string, string> = {
  emitido: 'EMITIDO — pendiente de entrega',
  parcial: 'ENTREGA PARCIAL',
  entregado: 'ENTREGADO',
  anulado: 'ANULADO',
}

/** Lo mínimo que el papel necesita saber, venga de la vista o del RPC del portal. */
export type ValePapel = {
  id: string
  folio: string
  estado: string
  created_at: string
  origen: string
  motivo: string | null
  ceco_codigo?: string | null
  ceco_nombre?: string | null
  activo_codigo?: string | null
  activo_nombre?: string | null
  activo_patente?: string | null
  ot_folio?: string | null
  firma_jefe_url?: string | null
  emitido_por_nombre?: string | null
  /** [MIG376] Quién responde por el vale, tenga cuenta o haya entrado por link. */
  pedido_por_nombre?: string | null
  solicitante_nombre?: string | null
}

export type ValePapelItem = {
  id?: string
  descripcion?: string | null
  producto_nombre?: string | null
  producto_codigo?: string | null
  comentario?: string | null
  unidad?: string | null
  unidad_medida?: string | null
  cantidad_solicitada: number | string
  cantidad_entregada?: number | string | null
}

export function ValeImprimible({ ticket, items }: { ticket: ValePapel; items: ValePapelItem[] }) {
  const fecha = new Date(ticket.created_at).toLocaleString('es-CL', {
    day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
  })
  const esOficina = ticket.origen === 'oficina'
  const quien = ticket.pedido_por_nombre ?? ticket.solicitante_nombre ?? ticket.emitido_por_nombre ?? '—'

  return (
    <div className="vale-doc rounded-xl border-2 border-gray-800 print:rounded-none print:border">
      <div className="flex items-start justify-between border-b-2 border-gray-800 p-4 print:p-2">
        <div>
          <h1 className="text-lg font-black tracking-tight text-[#0b2a4a] print:text-base">VALE DE BODEGA — PILLADO</h1>
          <p className="mt-0.5 font-mono text-2xl font-black print:text-lg">{ticket.folio}</p>
          <p className="mt-1 text-xs text-gray-600 print:mt-0">{fecha}</p>
          <p className={`mt-1 inline-block rounded px-2 py-0.5 text-[11px] font-bold ${
            ticket.estado === 'entregado' ? 'bg-green-100 text-green-800'
            : ticket.estado === 'anulado' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}`}>
            {ESTADO_LABEL[ticket.estado] ?? ticket.estado}
          </p>
        </div>
        <div className="text-center">
          {/* QR = link: cualquier teléfono lo abre en la pantalla de despacho de bodega */}
          <QRCodeCanvas value={`${typeof window !== 'undefined' ? window.location.origin : ''}/dashboard/bodega/tickets?folio=${ticket.folio}`}
                        size={110} className="print:h-[84px] print:w-[84px]" />
          <p className="mt-1 font-mono text-[10px] text-gray-500">{ticket.folio}</p>
          <p className="text-[9px] text-gray-400">Escanear = abre el despacho en bodega</p>
        </div>
      </div>

      {/* [MIG375] Un vale se carga a un equipo o a un centro de costo, nunca a
          los dos. Imprimir «Equipo: —» en el de oficina dejaba el papel sin
          decir a quién se le cobra, que es justo lo que viene a dejar escrito. */}
      <div className="grid grid-cols-2 gap-3 border-b border-gray-300 p-4 text-sm print:p-2">
        {esOficina ? (
          <div>
            <p className="text-[11px] uppercase text-gray-500">Centro de costo</p>
            <p className="text-lg font-bold print:text-base">{ticket.ceco_nombre ?? '—'}</p>
            <p className="font-mono text-xs text-gray-600">{ticket.ceco_codigo}</p>
          </div>
        ) : (
          <div>
            <p className="text-[11px] uppercase text-gray-500">Equipo / Patente</p>
            <p className="text-lg font-bold print:text-base">{ticket.activo_patente ?? ticket.activo_codigo}</p>
            <p className="text-xs text-gray-600">{ticket.activo_nombre}</p>
          </div>
        )}
        <div>
          {esOficina ? (
            <>
              <p className="text-[11px] uppercase text-gray-500">Retira</p>
              <p className="font-bold">{quien}</p>
            </>
          ) : (
            <>
              <p className="text-[11px] uppercase text-gray-500">Orden de trabajo</p>
              <p className="font-mono font-bold">{ticket.ot_folio ?? '—'}</p>
              <p className="mt-1 text-[11px] uppercase text-gray-500 print:mt-0">Autoriza</p>
              <p className="text-xs font-medium">{quien}</p>
            </>
          )}
        </div>
      </div>

      {/* [MIG371/375] Un vale sin hallazgo detrás no se explica solo: el motivo
          escrito es lo único que dice por qué salió el material. */}
      {ticket.origen !== 'ot' && ticket.motivo && (
        <div className="border-b border-gray-300 px-4 py-2 print:px-2 print:py-1">
          <p className="text-[11px] uppercase text-gray-500">
            {esOficina ? 'Pedido de oficina' : 'Pedido manual'} — para qué es
          </p>
          <p className="text-sm text-gray-800 print:text-xs">{ticket.motivo}</p>
        </div>
      )}

      <table className="w-full text-sm print:text-xs">
        <thead>
          <tr className="border-b border-gray-300 text-left text-[11px] uppercase text-gray-500">
            <th className="p-2 pl-4 print:py-1 print:pl-2">#</th>
            <th className="p-2 print:py-1">Material / repuesto</th>
            <th className="p-2 text-right print:py-1">Cantidad</th>
            <th className="p-2 pr-4 text-right print:py-1 print:pr-2">Entregado</th>
          </tr>
        </thead>
        <tbody>
          {items.map((it, i) => (
            <tr key={it.id ?? i} className="border-b border-gray-200">
              <td className="p-2 pl-4 text-gray-500 print:py-1 print:pl-2">{i + 1}</td>
              <td className="p-2 print:py-1">
                <span className="font-medium">{it.producto_nombre ?? it.descripcion}</span>
                {it.producto_codigo && <span className="ml-1 font-mono text-[10px] text-gray-400">{it.producto_codigo}</span>}
                {it.comentario && <div className="text-[10px] italic text-gray-500">{it.comentario}</div>}
              </td>
              <td className="whitespace-nowrap p-2 text-right font-semibold print:py-1">
                {it.cantidad_solicitada} {it.unidad ?? it.unidad_medida ?? 'un'}
              </td>
              <td className="p-2 pr-4 text-right text-gray-400 print:py-1 print:pr-2">
                {Number(it.cantidad_entregada ?? 0) > 0 ? it.cantidad_entregada : '____'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="vale-firmas grid grid-cols-3 gap-4 p-4 pt-8 print:p-2 print:pt-4">
        <div className="text-center">
          {ticket.firma_jefe_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={ticket.firma_jefe_url} alt="firma" className="mx-auto h-14 object-contain print:h-10" />
          ) : <div className="h-14 print:h-10" />}
          {/* [MIG375] En el vale de oficina no hay jefe de taller que autorice:
              firma quien retira, y ésa es la firma que ya está. */}
          <div className="border-t border-gray-800 pt-1 text-[11px] font-medium">
            {esOficina ? 'Solicita' : 'Jefe de Taller (autoriza)'}
          </div>
        </div>
        <div className="text-center">
          <div className="h-14 print:h-10" />
          <div className="border-t border-gray-800 pt-1 text-[11px] font-medium">
            {esOficina ? 'Recibe conforme' : 'Operador (retira)'}
          </div>
        </div>
        <div className="text-center">
          <div className="h-14 print:h-10" />
          <div className="border-t border-gray-800 pt-1 text-[11px] font-medium">Bodega (entrega)</div>
        </div>
      </div>

      {/* [MIG375] El vale de oficina lo retira quien lo pidió, no un operador
          de taller: mandarlo a buscar a alguien que no existe sobra. */}
      <p className="border-t border-gray-300 p-3 text-center text-[10px] text-gray-500 print:p-1.5">
        {esOficina
          ? 'Presentar este vale en bodega para retirar. El bodeguero escanea el QR en Bodega → Tickets y registra la entrega (total o parcial). El costo queda cargado al centro de costo de arriba.'
          : 'Presentar este vale en bodega. El bodeguero escanea el QR en Bodega → Tickets y registra la entrega (total o parcial). Ticket de un solo uso — al completarse queda ENTREGADO.'}
      </p>
    </div>
  )
}

/** Los estilos de impresión: hoja carta, una página, sin adornos. */
export function EstilosImpresionVale() {
  return (
    <style jsx global>{`
      @media print {
        @page { size: letter portrait; margin: 8mm 10mm; }
        html, body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        .vale-doc { font-size: 11px; }
        .vale-doc tr { break-inside: avoid; }
        .vale-firmas { break-inside: avoid; }
      }
    `}</style>
  )
}
