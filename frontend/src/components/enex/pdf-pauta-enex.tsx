'use client'

// PDF de las PAUTAS ENEX (plantillas de checklist) para enviar a validación
// del mandante (ESM/ENEX). No es el informe de una ejecución: es la pauta en
// blanco, con sus bloques, ítems, periodicidad, tipo de registro y tolerancias,
// más un bloque de firmas Elaborado (Pillado) / Validado (ESM) y una columna de
// observaciones para que el revisor anote sobre el documento.

import { Document, Page, Text, View, StyleSheet, Image, pdf } from '@react-pdf/renderer'
import {
  getPautas, getPautaItems, TIPO_CAMPO_LABEL, TIPO_INSTALACION_LABEL,
  type EnexPauta, type EnexPautaItem,
} from '@/lib/services/enex'
import { aDataUrl } from './pdf-informe-enex'

const S = StyleSheet.create({
  page: { padding: 28, fontSize: 9, fontFamily: 'Helvetica', color: '#111827' },
  headerRow: { flexDirection: 'row', borderWidth: 1, borderColor: '#111', marginBottom: 8 },
  logoBox: { width: 110, padding: 6, borderRightWidth: 1, borderRightColor: '#111', justifyContent: 'center' },
  logo: { width: 90, height: 28, objectFit: 'contain' },
  titleBox: { flex: 1, padding: 6, justifyContent: 'center' },
  title: { fontSize: 11, fontWeight: 'bold', textAlign: 'center' },
  subtitle: { fontSize: 8, textAlign: 'center', marginTop: 2 },
  metaBox: { width: 110, borderLeftWidth: 1, borderLeftColor: '#111' },
  metaRow: { flexDirection: 'row', borderBottomWidth: 0.5, borderBottomColor: '#111' },
  metaCell: { padding: 3, fontSize: 7 },
  sectionTitle: {
    backgroundColor: '#e5e7eb', fontWeight: 'bold', fontSize: 9,
    padding: 3, borderWidth: 0.5, borderColor: '#111', textAlign: 'center', marginTop: 8,
  },
  bloqueTitle: {
    backgroundColor: '#f3f4f6', fontWeight: 'bold', fontSize: 8.5,
    padding: 3, borderWidth: 0.5, borderColor: '#444', marginTop: 4,
  },
  row: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#444' },
  th: { padding: 3, fontSize: 7.5, fontWeight: 'bold', backgroundColor: '#f3f4f6', borderRightWidth: 0.5, borderRightColor: '#444', textAlign: 'center' },
  td: { padding: 3, fontSize: 8, borderRightWidth: 0.5, borderRightColor: '#444' },
  tdCenter: { padding: 3, fontSize: 7.5, borderRightWidth: 0.5, borderRightColor: '#444', textAlign: 'center', color: '#374151' },
  firmasRow: { flexDirection: 'row', marginTop: 28 },
  firmaCol: { flex: 1, alignItems: 'center', marginHorizontal: 10 },
  firmaLinea: { borderTopWidth: 1, borderTopColor: '#111', width: '100%', marginTop: 46, paddingTop: 3, alignItems: 'center' },
  firmaNombre: { fontSize: 8, fontWeight: 'bold' },
  firmaCargo: { fontSize: 7, color: '#4b5563', textAlign: 'center' },
  footer: { position: 'absolute', bottom: 16, left: 28, right: 28, fontSize: 7, color: '#9ca3af', textAlign: 'center' },
  indiceRow: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#444' },
})

type PautaConItems = { pauta: EnexPauta; items: EnexPautaItem[] }

function registroLabel(it: EnexPautaItem): string {
  if (it.tipo_campo !== 'medicion') return TIPO_CAMPO_LABEL[it.tipo_campo]
  const partes: string[] = ['Medición']
  if (it.unidad) partes.push(`en ${it.unidad}`)
  if (it.valor_referencia != null) partes.push(`ref ${it.valor_referencia}`)
  if (it.tolerancia_min != null || it.tolerancia_max != null)
    partes.push(`tol ${it.tolerancia_min ?? '−∞'} a ${it.tolerancia_max ?? '+∞'}`)
  return partes.join(' ')
}

function PautaPagina({ pauta, items, logoUrl, fecha }: PautaConItems & { logoUrl: string; fecha: string }) {
  const bloques: { bloque: string; items: EnexPautaItem[] }[] = []
  for (const it of items) {
    let g = bloques.find((x) => x.bloque === it.bloque)
    if (!g) { g = { bloque: it.bloque, items: [] }; bloques.push(g) }
    g.items.push(it)
  }
  return (
    <Page size="LETTER" style={S.page}>
      <View style={S.headerRow}>
        <View style={S.logoBox}>{logoUrl ? <Image src={logoUrl} style={S.logo} /> : <Text>PILLADO</Text>}</View>
        <View style={S.titleBox}>
          <Text style={S.title}>{pauta.nombre.toUpperCase()}</Text>
          <Text style={S.subtitle}>
            Pauta de {pauta.tipo_servicio === 'calibracion' ? 'calibración y certificación' : 'mantención'} · Aplica a: {pauta.aplica_tipos.map((t) => TIPO_INSTALACION_LABEL[t] ?? t).join(', ')}
          </Text>
          <Text style={S.subtitle}>DOCUMENTO PARA VALIDACIÓN DEL MANDANTE (ESM / ENEX)</Text>
        </View>
        <View style={S.metaBox}>
          <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Código</Text><Text style={S.metaCell}>{pauta.codigo}</Text></View>
          <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Versión</Text><Text style={S.metaCell}>{pauta.version}{pauta.es_borrador ? ' (borrador)' : ''}</Text></View>
          <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Emisión</Text><Text style={S.metaCell}>{fecha}</Text></View>
        </View>
      </View>

      {/* Encabezado de tabla */}
      <View style={[S.row, { borderTopWidth: 0.5, borderTopColor: '#444' }]}>
        <Text style={[S.th, { width: '7%' }]}>Cód.</Text>
        <Text style={[S.th, { width: '41%', textAlign: 'left' }]}>Descripción de la tarea</Text>
        <Text style={[S.th, { width: '11%' }]}>Periodicidad</Text>
        <Text style={[S.th, { width: '18%' }]}>Registro</Text>
        <Text style={[S.th, { width: '5%' }]}>Foto</Text>
        <Text style={[S.th, { width: '18%', borderRightWidth: 0 }]}>Observación validación</Text>
      </View>
      {bloques.map((g) => (
        <View key={g.bloque}>
          <Text style={S.bloqueTitle}>{g.bloque.toUpperCase()}</Text>
          {g.items.map((it, k) => (
            <View key={it.id} style={[S.row, k === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]} wrap={false}>
              <Text style={[S.tdCenter, { width: '7%', fontFamily: 'Courier' }]}>{it.codigo ?? ''}</Text>
              <Text style={[S.td, { width: '41%' }]}>{it.descripcion}</Text>
              <Text style={[S.tdCenter, { width: '11%', textTransform: 'capitalize' }]}>{it.periodicidad}</Text>
              <Text style={[S.tdCenter, { width: '18%' }]}>{registroLabel(it)}</Text>
              <Text style={[S.tdCenter, { width: '5%' }]}>{it.requiere_foto ? 'Sí' : ''}</Text>
              <Text style={[S.td, { width: '18%', borderRightWidth: 0 }]}> </Text>
            </View>
          ))}
        </View>
      ))}

      {/* Firmas de validación */}
      <View style={S.firmasRow} wrap={false}>
        <View style={S.firmaCol}>
          <View style={S.firmaLinea}>
            <Text style={S.firmaNombre}> </Text>
            <Text style={S.firmaCargo}>Elaborado por{'\n'}Pillado y Cía. Ltda. — Nombre / Cargo / Firma / Fecha</Text>
          </View>
        </View>
        <View style={S.firmaCol}>
          <View style={S.firmaLinea}>
            <Text style={S.firmaNombre}> </Text>
            <Text style={S.firmaCargo}>Validado por{'\n'}ESM / ENEX — Nombre / Cargo / Firma / Fecha</Text>
          </View>
        </View>
      </View>
      <Text style={S.footer} fixed>
        SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM VA_24_068 · Pauta {pauta.codigo} v{pauta.version} · Emitida {fecha}
      </Text>
    </Page>
  )
}

function PautasDoc({ pautas, logoUrl, fecha }: { pautas: PautaConItems[]; logoUrl: string; fecha: string }) {
  return (
    <Document>
      {/* Índice cuando va el paquete completo */}
      {pautas.length > 1 && (
        <Page size="LETTER" style={S.page}>
          <View style={S.headerRow}>
            <View style={S.logoBox}>{logoUrl ? <Image src={logoUrl} style={S.logo} /> : <Text>PILLADO</Text>}</View>
            <View style={S.titleBox}>
              <Text style={S.title}>PAUTAS DE MANTENCIÓN Y CALIBRACIÓN — CONTRATO ENEX/ESM</Text>
              <Text style={S.subtitle}>Paquete de pautas para revisión y validación del mandante</Text>
            </View>
            <View style={S.metaBox}>
              <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Emisión</Text><Text style={S.metaCell}>{fecha}</Text></View>
              <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Pautas</Text><Text style={S.metaCell}>{pautas.length}</Text></View>
            </View>
          </View>
          <Text style={S.sectionTitle}>ÍNDICE</Text>
          <View style={[S.indiceRow, { borderTopWidth: 0.5, borderTopColor: '#444' }]}>
            <Text style={[S.th, { width: '14%' }]}>Código</Text>
            <Text style={[S.th, { width: '42%', textAlign: 'left' }]}>Pauta</Text>
            <Text style={[S.th, { width: '14%' }]}>Servicio</Text>
            <Text style={[S.th, { width: '22%' }]}>Aplica a</Text>
            <Text style={[S.th, { width: '8%', borderRightWidth: 0 }]}>Ítems</Text>
          </View>
          {pautas.map(({ pauta, items }) => (
            <View key={pauta.id} style={S.indiceRow}>
              <Text style={[S.tdCenter, { width: '14%', fontFamily: 'Courier' }]}>{pauta.codigo}</Text>
              <Text style={[S.td, { width: '42%' }]}>{pauta.nombre}{pauta.es_borrador ? '  (borrador)' : ''}</Text>
              <Text style={[S.tdCenter, { width: '14%' }]}>{pauta.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</Text>
              <Text style={[S.tdCenter, { width: '22%' }]}>{pauta.aplica_tipos.map((t) => TIPO_INSTALACION_LABEL[t] ?? t).join(', ')}</Text>
              <Text style={[S.tdCenter, { width: '8%', borderRightWidth: 0 }]}>{items.length}</Text>
            </View>
          ))}
          <Text style={S.footer} fixed>SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM VA_24_068 · Emitido {fecha}</Text>
        </Page>
      )}
      {pautas.map((p) => <PautaPagina key={p.pauta.id} {...p} logoUrl={logoUrl} fecha={fecha} />)}
    </Document>
  )
}

// Genera y descarga el PDF. Sin pautaId descarga TODAS las pautas activas en un
// solo documento (índice + una pauta por sección) para enviar a validación.
export async function descargarPautasEnexPdf(pautaId?: string): Promise<void> {
  const todas = await getPautas()
  const seleccion = pautaId ? todas.filter((p) => p.id === pautaId) : todas
  if (seleccion.length === 0) throw new Error('No hay pautas para descargar')

  const conItems: PautaConItems[] = []
  for (const pauta of seleccion) conItems.push({ pauta, items: await getPautaItems(pauta.id) })

  const logoUrl = await aDataUrl(`${window.location.origin}/images/logo_empresa_2.png`)
  const fecha = new Date().toLocaleDateString('es-CL')
  const doc = <PautasDoc pautas={conItems} logoUrl={logoUrl ?? ''} fecha={fecha} />
  const blob = await Promise.race([
    pdf(doc).toBlob(),
    new Promise<never>((_, rej) => setTimeout(() => rej(new Error('La generación del PDF tardó demasiado — reintenta')), 45_000)),
  ])

  const hoy = new Date().toISOString().slice(0, 10)
  const nombre = seleccion.length === 1
    ? `Pauta_${seleccion[0].codigo}_${hoy}.pdf`
    : `Pautas_ENEX_validacion_${hoy}.pdf`
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombre
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}
