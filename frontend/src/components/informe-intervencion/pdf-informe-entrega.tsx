'use client'

// ============================================================================
// Acta de Entrega en Arriendo — el informe PROPIO de la entrega (MIG538/539).
// Manuel: «el informe que se hace para entrega sea distinto, un informe
// profesional que tome la firma del que entregó y del que aceptó».
// La fuente es el Check-List de Entrega V02: las verificaciones por bloque
// y las DOS firmas del cierre (ED.08 técnico que entrega, ED.09 representante
// del cliente que acepta), con nombre y RUT.
// ============================================================================

import {
  Document, Page, Text, View, StyleSheet, Image, pdf,
} from '@react-pdf/renderer'

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
    backgroundColor: VERDE, color: 'white', padding: 12, marginBottom: 12, borderRadius: 4,
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
  // Fila compacta de verificación (la entrega son ~30 chequeos: tabla, no cajas)
  itemRow: {
    flexDirection: 'row', borderBottomWidth: 0.5, borderBottomColor: '#e5e7eb',
    paddingVertical: 2.5, alignItems: 'flex-start',
  },
  itemDesc: { flex: 1, fontSize: 9 },
  itemRes: { width: 58, fontSize: 8.5, fontWeight: 'bold', textAlign: 'right' },
  obsBox: {
    borderWidth: 1, borderColor: '#fde68a', backgroundColor: '#fffbeb',
    padding: 6, marginBottom: 4, borderRadius: 3,
  },
  firmaCol: {
    flex: 1, borderWidth: 1, borderColor: '#d1d5db', borderRadius: 4, padding: 10,
  },
  firmaRotulo: { fontSize: 9, fontWeight: 'bold', color: VERDE, marginBottom: 6 },
  firmaImgBox: {
    height: 56, borderBottomWidth: 1, borderBottomColor: '#111827',
    justifyContent: 'flex-end', alignItems: 'center', marginBottom: 4,
  },
  firmaDato: { fontSize: 9, textAlign: 'center' },
  firmaDatoSec: { fontSize: 8, color: '#6b7280', textAlign: 'center' },
  footer: { fontSize: 8, color: '#9ca3af', textAlign: 'center', marginTop: 20 },
})

export interface FirmaEntrega {
  url: string | null
  nombre: string | null
  rut: string | null
}

export interface ItemEntrega {
  id: string
  bloque: string
  descripcion: string
  resultado: string | null
  observacion: string | null
  fotos: string[]
}

export interface DatosActaEntrega {
  ot: { folio: string | null; fecha_inicio: string | null; fecha_termino: string | null }
  activo: {
    patente?: string | null; codigo?: string | null; nombre?: string | null
    marca?: string | null; modelo?: string | null
    horas_uso_actual?: number | null; kilometraje_actual?: number | null
    cliente?: string | null
  }
  items: ItemEntrega[]
  firmaEntrega: FirmaEntrega   // ED.08 · técnico Pillado que entrega
  firmaAcepta: FirmaEntrega    // ED.09 · representante del cliente que acepta
  logo?: string | null
}

const BLOQUE_LABEL: Record<string, string> = {
  b_pruebas_funcionales: 'Pruebas funcionales',
  c_estado_entrega: 'Estado del equipo a la entrega',
  d_cierre_entrega: 'Cierre de la entrega',
}

const fmtFecha = (s: string | null | undefined) =>
  s ? new Date(s).toLocaleDateString('es-CL') : '—'

function ResultadoTag({ r }: { r: string | null }) {
  if (r === 'ok') return <Text style={[styles.itemRes, { color: '#15803d' }]}>OK</Text>
  if (r === 'no_ok') return <Text style={[styles.itemRes, { color: '#b91c1c' }]}>NO OK</Text>
  if (r === 'na') return <Text style={[styles.itemRes, { color: '#6b7280' }]}>N/A</Text>
  return <Text style={[styles.itemRes, { color: '#6b7280' }]}>{r ?? '—'}</Text>
}

function FirmaBox({ rotulo, firma, rol }: { rotulo: string; firma: FirmaEntrega; rol: string }) {
  return (
    <View style={styles.firmaCol}>
      <Text style={styles.firmaRotulo}>{rotulo}</Text>
      <View style={styles.firmaImgBox}>
        {firma.url ? (
          /* eslint-disable-next-line jsx-a11y/alt-text */
          <Image src={firma.url} style={{ height: 48 }} />
        ) : null}
      </View>
      <Text style={styles.firmaDato}>{firma.nombre || '____________________'}</Text>
      <Text style={styles.firmaDatoSec}>{firma.rut ? `RUT ${firma.rut}` : 'RUT ______________'}</Text>
      <Text style={styles.firmaDatoSec}>{rol}</Text>
    </View>
  )
}

export function ActaEntregaPDF({ datos }: { datos: DatosActaEntrega }) {
  const { ot, activo, items } = datos
  const verificados = items.filter((i) => i.resultado && i.resultado !== 'pendiente')
  const noOk = verificados.filter((i) => i.resultado === 'no_ok')
  const bloques = Array.from(new Set(items.map((i) => i.bloque)))
  return (
    <Document>
      <Page size="A4" style={styles.page}>
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
          <Text style={styles.title}>ACTA DE ENTREGA EN ARRIENDO</Text>
          <Text style={styles.subtitle}>
            OT {ot.folio ?? '—'} · Check-List de Entrega V02 · Emitida {new Date().toLocaleDateString('es-CL')}
          </Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Identificación del equipo</Text>
          <View style={styles.row}><Text style={styles.label}>Patente / Código:</Text><Text style={styles.value}>{activo.patente ?? activo.codigo ?? '—'}</Text></View>
          <View style={styles.row}><Text style={styles.label}>Equipo:</Text><Text style={styles.value}>{activo.nombre ?? '—'}</Text></View>
          {activo.marca ? <View style={styles.row}><Text style={styles.label}>Marca / Modelo:</Text><Text style={styles.value}>{activo.marca} {activo.modelo ?? ''}</Text></View> : null}
          {activo.cliente ? <View style={styles.row}><Text style={styles.label}>Cliente:</Text><Text style={styles.value}>{activo.cliente}</Text></View> : null}
          <View style={styles.row}><Text style={styles.label}>Fecha de entrega:</Text><Text style={styles.value}>{fmtFecha(ot.fecha_termino ?? ot.fecha_inicio)}</Text></View>
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
          <View style={styles.row}>
            <Text style={styles.label}>Verificación:</Text>
            <Text style={styles.value}>
              {verificados.length} ítems revisados · {verificados.length - noOk.length} conformes
              {noOk.length > 0 ? ` · ${noOk.length} con observación` : ' · sin observaciones'}
            </Text>
          </View>
        </View>

        {bloques.map((b) => {
          const del = items.filter((i) => i.bloque === b)
          if (del.length === 0) return null
          return (
            <View key={b} style={styles.section}>
              <Text style={styles.sectionTitle}>{BLOQUE_LABEL[b] ?? b}</Text>
              {del.map((i) => (
                <View key={i.id} wrap={false}>
                  <View style={styles.itemRow}>
                    <Text style={styles.itemDesc}>
                      {i.descripcion}
                      {i.observacion ? `  —  ${i.observacion}` : ''}
                    </Text>
                    <ResultadoTag r={i.resultado} />
                  </View>
                  {i.fotos.length > 0 && (
                    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginTop: 2, marginBottom: 3 }}>
                      {i.fotos.slice(0, 3).map((url, j) => (
                        /* eslint-disable-next-line jsx-a11y/alt-text */
                        <Image key={j} src={url} style={{ width: 110, height: 82, objectFit: 'cover' }} />
                      ))}
                    </View>
                  )}
                </View>
              ))}
            </View>
          )
        })}

        {noOk.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Observaciones a la entrega ({noOk.length})</Text>
            {noOk.map((i) => (
              <View key={i.id} style={styles.obsBox} wrap={false}>
                <Text style={{ fontSize: 9, fontWeight: 'bold' }}>{i.descripcion}</Text>
                {i.observacion ? <Text style={{ fontSize: 9, marginTop: 1 }}>{i.observacion}</Text> : null}
              </View>
            ))}
          </View>
        )}

        {/* Las dos firmas del acta: quien ENTREGA y quien ACEPTA. Vienen del
            cierre del Check-List (ED.08 / ED.09), firmadas en terreno. */}
        <View style={{ flexDirection: 'row', gap: 14, marginTop: 10 }} wrap={false}>
          <FirmaBox rotulo="ENTREGA CONFORME" firma={datos.firmaEntrega} rol="Técnico Pillado Empresas" />
          <FirmaBox rotulo="RECIBE Y ACEPTA" firma={datos.firmaAcepta} rol="Representante del cliente" />
        </View>

        <Text style={{ fontSize: 8, color: '#6b7280', marginTop: 8 }}>
          El representante del cliente declara recibir el equipo individualizado en las
          condiciones descritas en esta acta, verificadas en su presencia.
        </Text>

        <Text style={styles.footer}>
          Pillado y Cía. Ltda. · Fono: 051 – 2232159 · contacto@pilladoempresas.cl
          {'\n'}SICOM-ICEO · Documento emitido automáticamente desde la plataforma
        </Text>
      </Page>
    </Document>
  )
}

/** Genera el acta con fotos y firmas embebidas como data URLs (lección ENEX). */
export async function generarPDFActaEntrega(datos: DatosActaEntrega): Promise<Blob> {
  const { aDataUrlComprimida, aDataUrl, enLotes } = await import('@/lib/utils/foto-pdf')
  const items = await enLotes(datos.items, 4, async (i) => {
    const fotos = (await Promise.all(i.fotos.slice(0, 3).map((u) => aDataUrlComprimida(u, 1200, 0.7))))
      .filter((u): u is string => !!u)
    return { ...i, fotos }
  })
  const [firmaEntregaUrl, firmaAceptaUrl, logo] = await Promise.all([
    aDataUrl(datos.firmaEntrega.url),
    aDataUrl(datos.firmaAcepta.url),
    aDataUrl('/images/logo.jpg'),
  ])
  return pdf(
    <ActaEntregaPDF
      datos={{
        ...datos, items, logo,
        firmaEntrega: { ...datos.firmaEntrega, url: firmaEntregaUrl },
        firmaAcepta: { ...datos.firmaAcepta, url: firmaAceptaUrl },
      }}
    />
  ).toBlob()
}
