'use client'

import {
  Document, Page, Text, View, StyleSheet, Image, pdf,
} from '@react-pdf/renderer'
import type {
  InformeRecepcion, InformeHallazgo, InformeCosto,
} from '@/lib/services/informe-recepcion'

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 10, fontFamily: 'Helvetica', color: '#111827' },
  header: {
    backgroundColor: '#1f2937',
    color: 'white',
    padding: 12,
    marginBottom: 12,
    borderRadius: 4,
  },
  title: { fontSize: 16, fontWeight: 'bold', marginBottom: 2 },
  subtitle: { fontSize: 9, color: '#d1d5db' },
  section: { marginBottom: 12 },
  sectionTitle: {
    fontSize: 11, fontWeight: 'bold',
    borderBottomWidth: 1, borderBottomColor: '#d1d5db',
    paddingBottom: 2, marginBottom: 6,
  },
  row: { flexDirection: 'row', marginBottom: 2 },
  label: { width: '30%', color: '#6b7280' },
  value: { width: '70%' },
  hallazgoBox: {
    borderWidth: 1, borderColor: '#fecaca',
    backgroundColor: '#fef2f2',
    padding: 6, marginBottom: 4, borderRadius: 3,
  },
  hallazgoTitle: { fontSize: 10, fontWeight: 'bold' },
  hallazgoMeta: { fontSize: 8, color: '#6b7280', marginTop: 2 },
  tableHeader: {
    flexDirection: 'row', backgroundColor: '#f3f4f6',
    padding: 4, fontWeight: 'bold', fontSize: 9,
  },
  tableRow: { flexDirection: 'row', padding: 4, borderBottomWidth: 0.5, borderBottomColor: '#e5e7eb', fontSize: 9 },
  col1: { width: '15%' },
  col2: { width: '50%' },
  col3: { width: '10%', textAlign: 'right' },
  col4: { width: '15%', textAlign: 'right' },
  col5: { width: '10%', textAlign: 'center' },
  totals: { marginTop: 8, paddingTop: 6, borderTopWidth: 1, borderTopColor: '#000' },
  totalRow: { flexDirection: 'row', justifyContent: 'flex-end', marginBottom: 2 },
  totalLabel: { width: 160, textAlign: 'right' },
  totalValue: { width: 100, textAlign: 'right', fontWeight: 'bold' },
  grandTotal: { fontSize: 14, color: '#16a34a' },
  firma: { flex: 1, textAlign: 'center', marginTop: 24 },
  firmaBox: { height: 50, borderBottomWidth: 1, borderBottomColor: '#000' },
  firmaLabel: { fontSize: 9, marginTop: 4, color: '#4b5563' },
  footer: { fontSize: 8, color: '#9ca3af', textAlign: 'center', marginTop: 24 },
})

interface Props {
  informe: InformeRecepcion
  activo: { patente?: string | null; codigo?: string | null; nombre?: string | null; marca?: string | null; modelo?: string | null }
  hallazgos: InformeHallazgo[]
  costos: InformeCosto[]
}

export function InformeRecepcionPDF({ informe, activo, hallazgos, costos }: Props) {
  const fmt = (n: number) => `$${Number(n).toLocaleString('es-CL')}`
  const hallazgosCliente = hallazgos.filter((h) => h.atribuible_cliente)
  const hallazgosEmpresa = hallazgos.filter((h) => !h.atribuible_cliente)
  const costosCliente = costos.filter((c) => c.cobrable_cliente)

  return (
    <Document>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <Text style={styles.title}>INFORME DE RECEPCIÓN DE EQUIPO ARRENDADO</Text>
          <Text style={styles.subtitle}>
            Folio {informe.folio ?? informe.id.slice(0, 8)} · Emitido {informe.emitido_en ? new Date(informe.emitido_en).toLocaleDateString('es-CL') : '—'}
          </Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Identificación del equipo</Text>
          <View style={styles.row}><Text style={styles.label}>Patente / Código:</Text><Text style={styles.value}>{activo.patente ?? activo.codigo ?? '—'}</Text></View>
          <View style={styles.row}><Text style={styles.label}>Equipo:</Text><Text style={styles.value}>{activo.nombre ?? '—'}</Text></View>
          {activo.marca && <View style={styles.row}><Text style={styles.label}>Marca / Modelo:</Text><Text style={styles.value}>{activo.marca} {activo.modelo ?? ''}</Text></View>}
          <View style={styles.row}><Text style={styles.label}>Cliente:</Text><Text style={styles.value}>{informe.cliente_nombre ?? '—'}</Text></View>
          <View style={styles.row}><Text style={styles.label}>Entregado el:</Text><Text style={styles.value}>{informe.fecha_entrega_arriendo ?? '—'}</Text></View>
          <View style={styles.row}><Text style={styles.label}>Recibido el:</Text><Text style={styles.value}>{informe.fecha_recepcion}</Text></View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Hallazgos atribuibles al cliente ({hallazgosCliente.length})</Text>
          {hallazgosCliente.length === 0 ? (
            <Text style={{ color: '#6b7280', fontStyle: 'italic' }}>Sin hallazgos atribuibles al cliente.</Text>
          ) : hallazgosCliente.map((h, i) => (
            <View key={i} style={styles.hallazgoBox}>
              <Text style={styles.hallazgoTitle}>{i + 1}. {h.descripcion}</Text>
              <Text style={styles.hallazgoMeta}>Sección: {h.seccion ?? '—'} · Gravedad: {h.gravedad}</Text>
              {h.observacion && <Text style={{ fontSize: 9, marginTop: 2 }}>{h.observacion}</Text>}
              {(h.fotos ?? []).length > 0 && (
                <View style={{ flexDirection: 'row', gap: 4, marginTop: 4 }}>
                  {(h.fotos ?? []).slice(0, 3).map((url, j) => (
                    /* eslint-disable-next-line jsx-a11y/alt-text */
                    <Image key={j} src={url} style={{ width: 80, height: 60 }} />
                  ))}
                </View>
              )}
            </View>
          ))}
        </View>

        {hallazgosEmpresa.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Hallazgos no atribuibles (absorbidos por la empresa)</Text>
            {hallazgosEmpresa.map((h, i) => (
              <Text key={i} style={{ fontSize: 9, marginBottom: 2 }}>· {h.descripcion}</Text>
            ))}
          </View>
        )}

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Detalle de cobro</Text>
          <View style={styles.tableHeader}>
            <Text style={styles.col1}>Tipo</Text>
            <Text style={styles.col2}>Descripción</Text>
            <Text style={styles.col3}>Cant.</Text>
            <Text style={styles.col4}>Precio unit.</Text>
            <Text style={styles.col5}>Total</Text>
          </View>
          {costosCliente.map((c) => (
            <View key={c.id} style={styles.tableRow}>
              <Text style={styles.col1}>{c.tipo}</Text>
              <Text style={styles.col2}>{c.descripcion}</Text>
              <Text style={styles.col3}>{c.cantidad} {c.unidad ?? ''}</Text>
              <Text style={styles.col4}>{fmt(c.precio_unitario)}</Text>
              <Text style={styles.col5}>{fmt(c.total)}</Text>
            </View>
          ))}
          <View style={styles.totals}>
            <View style={styles.totalRow}><Text style={styles.totalLabel}>Subtotal neto:</Text><Text style={styles.totalValue}>{fmt(Number(informe.total_cobrable_cliente))}</Text></View>
            <View style={styles.totalRow}><Text style={styles.totalLabel}>IVA (19%):</Text><Text style={styles.totalValue}>{fmt(Number(informe.iva))}</Text></View>
            <View style={styles.totalRow}>
              <Text style={[styles.totalLabel, styles.grandTotal]}>TOTAL A COBRAR:</Text>
              <Text style={[styles.totalValue, styles.grandTotal]}>{fmt(Number(informe.total))}</Text>
            </View>
          </View>
        </View>

        {informe.observaciones_finales && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Observaciones</Text>
            <Text style={{ fontSize: 9 }}>{informe.observaciones_finales}</Text>
          </View>
        )}

        <View style={{ flexDirection: 'row', marginTop: 24, gap: 16 }}>
          <View style={styles.firma}>
            {informe.inspector_firma_url && (
              /* eslint-disable-next-line jsx-a11y/alt-text */
              <Image src={informe.inspector_firma_url} style={{ height: 40, marginBottom: 4 }} />
            )}
            <View style={styles.firmaBox} />
            <Text style={styles.firmaLabel}>Técnico Inspector</Text>
          </View>
          <View style={styles.firma}>
            {informe.encargado_firma_url && (
              /* eslint-disable-next-line jsx-a11y/alt-text */
              <Image src={informe.encargado_firma_url} style={{ height: 40, marginBottom: 4 }} />
            )}
            <View style={styles.firmaBox} />
            <Text style={styles.firmaLabel}>Encargado de Cobros</Text>
          </View>
        </View>

        <Text style={styles.footer}>
          SICOM-ICEO · Pillado Empresas · Documento emitido automáticamente desde la plataforma
        </Text>
      </Page>
    </Document>
  )
}

// Helper para generar el PDF como Blob y obtener un File/url
export async function generarPDFInforme(props: Props): Promise<Blob> {
  const blob = await pdf(<InformeRecepcionPDF {...props} />).toBlob()
  return blob
}
