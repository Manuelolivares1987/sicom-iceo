'use client'

// ============================================================================
// Informe de trabajos realizados — EL MISMO FORMATO del informe de recobro
// (components/recepcion/pdf-informe.tsx), pedido así por Manuel: «simplemente
// un informe con lo que realmente se ha hecho, el mismo informe de recobro,
// con el mismo formato». Sin estados, sin revisión, sin aprobación: un botón
// lo genera y listo. La fuente es la ejecución real del checklist V03.
// ============================================================================

import {
  Document, Page, Text, View, StyleSheet, Image, pdf,
} from '@react-pdf/renderer'
import type { EjecucionItemInforme } from '@/lib/services/informe-intervencion'

// Estilos calcados del informe de recobro, con los colores institucionales
// Pillado (verde de la marca + logo en el membrete).
const VERDE = '#1E5929'
const VERDE_CLARO = '#A7D3B0'

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 10, fontFamily: 'Helvetica', color: '#111827' },
  membrete: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end',
    marginBottom: 8,
  },
  membreteTexto: { fontSize: 8, color: '#6b7280', textAlign: 'right' },
  header: {
    backgroundColor: VERDE,
    color: 'white',
    padding: 12,
    marginBottom: 12,
    borderRadius: 4,
  },
  title: { fontSize: 16, fontWeight: 'bold', marginBottom: 2 },
  subtitle: { fontSize: 9, color: '#d7e8da' },
  section: { marginBottom: 12 },
  sectionTitle: {
    fontSize: 11, fontWeight: 'bold', color: VERDE,
    borderBottomWidth: 1, borderBottomColor: VERDE_CLARO,
    paddingBottom: 2, marginBottom: 6,
  },
  row: { flexDirection: 'row', marginBottom: 2 },
  label: { width: '30%', color: '#6b7280' },
  value: { width: '70%' },
  // La caja del trabajo: la misma del hallazgo del recobro, en verde (esto es
  // trabajo hecho, no un daño que cobrar).
  trabajoBox: {
    borderWidth: 1, borderColor: '#bbf7d0',
    backgroundColor: '#f0fdf4',
    padding: 6, marginBottom: 4, borderRadius: 3,
  },
  trabajoNoOkBox: {
    borderWidth: 1, borderColor: '#fecaca',
    backgroundColor: '#fef2f2',
    padding: 6, marginBottom: 4, borderRadius: 3,
  },
  trabajoTitle: { fontSize: 10, fontWeight: 'bold' },
  trabajoMeta: { fontSize: 8, color: '#6b7280', marginTop: 2 },
  firma: { flex: 1, textAlign: 'center', marginTop: 24 },
  firmaBox: { height: 50, borderBottomWidth: 1, borderBottomColor: '#000' },
  firmaLabel: { fontSize: 9, marginTop: 4, color: '#4b5563' },
  footer: { fontSize: 8, color: '#9ca3af', textAlign: 'center', marginTop: 24 },
})

export interface DatosInformeTrabajos {
  ot: { folio: string | null; tipo: string | null; fecha_inicio: string | null; fecha_termino: string | null }
  activo: {
    patente?: string | null; codigo?: string | null; nombre?: string | null
    marca?: string | null; modelo?: string | null
    horas_uso_actual?: number | null; kilometraje_actual?: number | null
  }
  ejecucion: EjecucionItemInforme[]
  tecnicoNombre?: string | null
  firmaTecnicoUrl?: string | null
  estadoSalida?: string | null
  logo?: string | null
}

const fmtFecha = (s: string | null | undefined) =>
  s ? new Date(s).toLocaleDateString('es-CL') : '—'

export function InformeTrabajosPDF({ datos }: { datos: DatosInformeTrabajos }) {
  const { ot, activo, ejecucion } = datos
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        {/* Membrete institucional */}
        <View style={styles.membrete}>
          {datos.logo ? (
            /* eslint-disable-next-line jsx-a11y/alt-text */
            <Image src={datos.logo} style={{ height: 42 }} />
          ) : (
            <Text style={{ fontSize: 13, fontWeight: 'bold', color: VERDE }}>PILLADO EMPRESAS</Text>
          )}
          <View>
            <Text style={styles.membreteTexto}>Pillado y Compañía Ltda.</Text>
            <Text style={styles.membreteTexto}>Trayectoria y compromiso</Text>
          </View>
        </View>

        <View style={styles.header}>
          <Text style={styles.title}>INFORME TÉCNICO DE TRABAJOS REALIZADOS</Text>
          <Text style={styles.subtitle}>
            OT {ot.folio ?? '—'} · Emitido {new Date().toLocaleDateString('es-CL')}
          </Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Identificación del equipo</Text>
          <View style={styles.row}><Text style={styles.label}>Patente / Código:</Text><Text style={styles.value}>{activo.patente ?? activo.codigo ?? '—'}</Text></View>
          <View style={styles.row}><Text style={styles.label}>Equipo:</Text><Text style={styles.value}>{activo.nombre ?? '—'}</Text></View>
          {activo.marca ? <View style={styles.row}><Text style={styles.label}>Marca / Modelo:</Text><Text style={styles.value}>{activo.marca} {activo.modelo ?? ''}</Text></View> : null}
          <View style={styles.row}><Text style={styles.label}>Orden de trabajo:</Text><Text style={styles.value}>{ot.folio ?? '—'} · {ot.tipo ?? '—'}</Text></View>
          <View style={styles.row}><Text style={styles.label}>Trabajado:</Text><Text style={styles.value}>{fmtFecha(ot.fecha_inicio)} — {fmtFecha(ot.fecha_termino)}</Text></View>
          {(activo.horas_uso_actual != null || activo.kilometraje_actual != null) ? (
            <View style={styles.row}>
              <Text style={styles.label}>Medidores:</Text>
              <Text style={styles.value}>
                {activo.horas_uso_actual != null ? `${Math.round(Number(activo.horas_uso_actual)).toLocaleString('es-CL')} h` : ''}
                {activo.horas_uso_actual != null && activo.kilometraje_actual != null ? ' · ' : ''}
                {activo.kilometraje_actual != null ? `${Math.round(Number(activo.kilometraje_actual)).toLocaleString('es-CL')} km` : ''}
              </Text>
            </View>
          ) : null}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Trabajos realizados ({ejecucion.length})</Text>
          {ejecucion.length === 0 ? (
            <Text style={{ color: '#6b7280', fontStyle: 'italic' }}>Sin trabajos registrados en el checklist.</Text>
          ) : ejecucion.map((e, i) => (
            <View key={e.instance_item_id} style={e.resultado === 'no_ok' ? styles.trabajoNoOkBox : styles.trabajoBox} wrap={false}>
              <Text style={styles.trabajoTitle}>{i + 1}. {e.descripcion}</Text>
              <Text style={styles.trabajoMeta}>
                {e.bloque ? `Sección: ${e.bloque} · ` : ''}
                Resultado: {e.resultado === 'ok' ? 'EJECUTADO OK' : e.resultado === 'no_ok' ? 'NO OK (No Conformidad)' : e.resultado}
              </Text>
              {e.observacion ? <Text style={{ fontSize: 9, marginTop: 2 }}>{e.observacion}</Text> : null}
              {e.fotos.length > 0 && (
                <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginTop: 4 }}>
                  {e.fotos.slice(0, 3).map((url, j) => (
                    /* eslint-disable-next-line jsx-a11y/alt-text */
                    <Image key={j} src={url} style={{ width: 110, height: 82, objectFit: 'cover' }} />
                  ))}
                </View>
              )}
            </View>
          ))}
        </View>

        {datos.estadoSalida ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Estado de salida del equipo</Text>
            <Text style={{ fontSize: 9 }}>{datos.estadoSalida}</Text>
          </View>
        ) : null}

        <View style={{ flexDirection: 'row', marginTop: 24, gap: 16 }}>
          <View style={styles.firma}>
            {datos.firmaTecnicoUrl ? (
              /* eslint-disable-next-line jsx-a11y/alt-text */
              <Image src={datos.firmaTecnicoUrl} style={{ height: 40, marginBottom: 4 }} />
            ) : null}
            <View style={styles.firmaBox} />
            <Text style={styles.firmaLabel}>{datos.tecnicoNombre || 'Técnico responsable'}</Text>
          </View>
          <View style={styles.firma}>
            <View style={styles.firmaBox} />
            <Text style={styles.firmaLabel}>Jefe de Taller</Text>
          </View>
        </View>

        <Text style={styles.footer}>
          Pillado y Cía. Ltda. · Fono: 051 – 2232159 · contacto@pilladoempresas.cl
          {'\n'}SICOM-ICEO · Documento emitido automáticamente desde la plataforma
        </Text>
      </Page>
    </Document>
  )
}

/** Genera el informe con las fotos ya comprimidas y embebidas (lección ENEX). */
export async function generarPDFTrabajos(datos: DatosInformeTrabajos): Promise<Blob> {
  const { aDataUrlComprimida, aDataUrl, enLotes } = await import('@/lib/utils/foto-pdf')
  const ejecucion = await enLotes(datos.ejecucion, 4, async (e) => {
    const fotos = (await Promise.all(e.fotos.slice(0, 3).map((u) => aDataUrlComprimida(u, 1200, 0.7))))
      .filter((u): u is string => !!u)
    return { ...e, fotos }
  })
  const firmaTecnicoUrl = await aDataUrl(datos.firmaTecnicoUrl)
  const logo = await aDataUrl('/images/logo.jpg')
  return pdf(<InformeTrabajosPDF datos={{ ...datos, ejecucion, firmaTecnicoUrl, logo }} />).toBlob()
}
