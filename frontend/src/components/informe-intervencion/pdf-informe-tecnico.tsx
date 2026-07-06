'use client'

import {
  Document, Page, Text, View, StyleSheet, Image, pdf,
} from '@react-pdf/renderer'
import type { InformeIntervencionDetalle } from '@/lib/services/informe-intervencion'

// ============================================================================
// PDF del Informe técnico de intervención (18 secciones).
// SOLO información técnica/operacional. NO incluye información comercial ni de
// recobro al cliente. Los costos que aparecen son costos internos (materiales
// FIFO y mano de obra por tiempo efectivo).
// ============================================================================

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 9, fontFamily: 'Helvetica', color: '#111827' },
  header: {
    backgroundColor: '#1f2937', color: 'white', padding: 12, marginBottom: 12, borderRadius: 4,
  },
  title: { fontSize: 15, fontWeight: 'bold', marginBottom: 2 },
  subtitle: { fontSize: 8, color: '#d1d5db' },
  section: { marginBottom: 10 },
  sectionTitle: {
    fontSize: 10, fontWeight: 'bold', color: '#1f2937',
    borderBottomWidth: 1, borderBottomColor: '#d1d5db', paddingBottom: 2, marginBottom: 5,
  },
  row: { flexDirection: 'row', marginBottom: 2 },
  label: { width: '32%', color: '#6b7280' },
  value: { width: '68%' },
  paragraph: { fontSize: 9, lineHeight: 1.4 },
  muted: { color: '#6b7280', fontStyle: 'italic' },
  tableHeader: {
    flexDirection: 'row', backgroundColor: '#f3f4f6', padding: 4, fontWeight: 'bold', fontSize: 8,
  },
  tableRow: {
    flexDirection: 'row', padding: 4, borderBottomWidth: 0.5, borderBottomColor: '#e5e7eb', fontSize: 8,
  },
  itemBox: {
    borderWidth: 0.5, borderColor: '#e5e7eb', borderRadius: 3, padding: 5, marginBottom: 4,
  },
  ncBox: {
    borderWidth: 1, borderColor: '#fed7aa', backgroundColor: '#fff7ed',
    padding: 5, marginBottom: 4, borderRadius: 3,
  },
  chip: { fontSize: 7, color: '#374151' },
  totalRow: {
    flexDirection: 'row', justifyContent: 'flex-end', marginTop: 4, paddingTop: 4,
    borderTopWidth: 1, borderTopColor: '#d1d5db',
  },
  totalLabel: { width: 160, textAlign: 'right', color: '#374151' },
  totalValue: { width: 90, textAlign: 'right', fontWeight: 'bold' },
  firmaWrap: { flexDirection: 'row', marginTop: 24, gap: 24 },
  firma: { flex: 1, textAlign: 'center' },
  firmaBox: { height: 44, borderBottomWidth: 1, borderBottomColor: '#000' },
  firmaLabel: { fontSize: 8, marginTop: 4, color: '#4b5563' },
  footer: {
    marginTop: 20, paddingTop: 8, borderTopWidth: 1, borderTopColor: '#e5e7eb',
    fontSize: 7, color: '#9ca3af', textAlign: 'center',
  },
})

const ESTADO_TRABAJO_LABEL: Record<string, string> = {
  pendiente: 'Pendiente',
  en_ejecucion: 'En ejecución',
  realizado: 'Realizado',
  realizado_parcial: 'Realizado parcial',
  no_realizado: 'No realizado',
  no_aplica: 'No aplica',
}

function fmtCLP(n: number | null | undefined): string {
  return `$${Number(n ?? 0).toLocaleString('es-CL')}`
}
function fmtDate(s: string | null | undefined): string {
  return s ? new Date(s).toLocaleDateString('es-CL') : '—'
}
function fmtNum(n: number | null | undefined): string {
  return n == null ? '—' : Number(n).toLocaleString('es-CL')
}
function fmtHoras(seg: number | null | undefined): string {
  if (!seg) return '—'
  const h = Math.floor(seg / 3600)
  const m = Math.round((seg % 3600) / 60)
  return `${h}h ${m}m`
}

function Field({ label, value }: { label: string; value?: string | null }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}:</Text>
      <Text style={styles.value}>{value && value.trim() ? value : '—'}</Text>
    </View>
  )
}

function TextSection({ title, value }: { title: string; value?: string | null }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {value && value.trim() ? (
        <Text style={styles.paragraph}>{value}</Text>
      ) : (
        <Text style={styles.muted}>Sin información.</Text>
      )}
    </View>
  )
}

export function InformeTecnicoPDF({ data }: { data: InformeIntervencionDetalle }) {
  const { informe, activo, ot, trabajos, materiales, manoobra, pruebas } = data

  const trabajosNC = trabajos.filter((t) => t.nc_id)
  const evidencias = trabajos.flatMap((t) =>
    [
      { url: t.evidencia_antes_url, etiqueta: 'Antes' },
      { url: t.evidencia_durante_url, etiqueta: 'Durante' },
      { url: t.evidencia_despues_url, etiqueta: 'Después' },
    ].filter((e) => e.url),
  )
  const totalMateriales = materiales.reduce((s, m) => s + Number(m.costo_total ?? 0), 0)
  const totalManoObra = manoobra.reduce((s, m) => s + Number(m.costo_total_snapshot ?? 0), 0)
  const totalSegundos = manoobra.reduce((s, m) => s + Number(m.tiempo_efectivo_segundos ?? 0), 0)

  return (
    <Document>
      <Page size="A4" style={styles.page} wrap>
        {/* Encabezado */}
        <View style={styles.header}>
          <Text style={styles.title}>INFORME TÉCNICO DE INTERVENCIÓN</Text>
          <Text style={styles.subtitle}>
            Folio {informe.folio} · Versión {informe.version} · Estado {informe.estado}
            {informe.aprobado_at ? ` · Aprobado ${fmtDate(informe.aprobado_at)}` : ''}
          </Text>
        </View>

        {/* 1. Identificación del activo */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>1. Identificación del equipo</Text>
          <Field label="Patente / Código" value={activo.patente ?? activo.codigo} />
          <Field label="Equipo" value={activo.nombre} />
          <Field label="Marca / Modelo" value={[activo.marca, activo.modelo].filter(Boolean).join(' ') || null} />
        </View>

        {/* 2. Orden de trabajo */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>2. Orden de trabajo</Text>
          <Field label="Folio OT" value={ot?.folio} />
          <Field label="Tipo / Estado OT" value={ot ? `${ot.tipo ?? '—'} · ${ot.estado ?? '—'}` : null} />
          <Field label="Ingreso" value={fmtDate(informe.fecha_ingreso)} />
          <Field label="Inicio / Término" value={`${fmtDate(informe.fecha_inicio)} — ${fmtDate(informe.fecha_termino)}`} />
        </View>

        {/* 3. Tipo y motivo de intervención */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>3. Tipo y motivo de intervención</Text>
          <Field label="Tipo de intervención" value={informe.tipo_intervencion} />
          <Field label="Motivo de ingreso" value={informe.motivo_ingreso} />
          <Field label="Condición de ingreso" value={informe.condicion_ingreso} />
        </View>

        {/* 4. Lecturas de ingreso/salida */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>4. Lecturas de ingreso y salida</Text>
          <Field label="Kilometraje (ingreso → salida)" value={`${fmtNum(informe.kilometraje_ingreso)} → ${fmtNum(informe.kilometraje_salida)}`} />
          <Field label="Horómetro (ingreso → salida)" value={`${fmtNum(informe.horometro_ingreso)} → ${fmtNum(informe.horometro_salida)}`} />
        </View>

        {/* 5. Diagnóstico */}
        <TextSection title="5. Diagnóstico" value={informe.diagnostico_resumen} />

        {/* 6. Trabajos planificados */}
        <TextSection title="6. Trabajos planificados" value={informe.trabajo_planificado_resumen} />

        {/* 7. Trabajos realizados (resumen + detalle por ítem) */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>7. Trabajos realizados</Text>
          {informe.trabajo_realizado_resumen?.trim() ? (
            <Text style={[styles.paragraph, { marginBottom: 5 }]}>{informe.trabajo_realizado_resumen}</Text>
          ) : (
            <Text style={[styles.muted, { marginBottom: 5 }]}>Sin resumen.</Text>
          )}
          {trabajos.length === 0 ? (
            <Text style={styles.muted}>Sin ítems de trabajo registrados.</Text>
          ) : (
            trabajos.map((t, i) => (
              <View key={t.id} style={styles.itemBox}>
                <Text style={{ fontWeight: 'bold', fontSize: 9 }}>
                  {i + 1}. {t.trabajo_planificado || t.diagnostico || t.sintoma || t.componente || 'Trabajo'}
                  {t.es_adicional ? '  [adicional]' : ''}
                </Text>
                <Text style={styles.chip}>
                  {[t.sistema, t.componente].filter(Boolean).join(' / ') || 's/sistema'}
                  {'  ·  '}Estado: {ESTADO_TRABAJO_LABEL[t.estado] ?? t.estado}
                  {t.resultado ? `  ·  Resultado: ${t.resultado}` : ''}
                  {t.horas_hombre != null ? `  ·  ${t.horas_hombre} HH` : ''}
                </Text>
                {t.trabajo_realizado ? <Text style={{ fontSize: 8, marginTop: 2 }}>{t.trabajo_realizado}</Text> : null}
                {t.observacion ? <Text style={{ fontSize: 8, marginTop: 1, color: '#6b7280' }}>Obs: {t.observacion}</Text> : null}
              </View>
            ))
          )}
        </View>

        {/* 8. Trabajos pendientes */}
        <TextSection title="8. Trabajos pendientes" value={informe.trabajos_pendientes_resumen} />

        {/* 9. No conformidades */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>9. No conformidades asociadas</Text>
          {trabajosNC.length === 0 ? (
            <Text style={styles.muted}>Sin no conformidades asociadas.</Text>
          ) : (
            trabajosNC.map((t, i) => (
              <View key={t.id} style={styles.ncBox}>
                <Text style={{ fontWeight: 'bold', fontSize: 9 }}>
                  NC {i + 1}. {t.sintoma || t.componente || 'No conformidad'}
                </Text>
                {t.diagnostico ? <Text style={{ fontSize: 8, marginTop: 2 }}>Acción: {t.diagnostico}</Text> : null}
                {t.observacion ? <Text style={{ fontSize: 8, marginTop: 1, color: '#6b7280' }}>{t.observacion}</Text> : null}
              </View>
            ))
          )}
        </View>

        {/* 10. Materiales (costo interno) */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>10. Materiales consumidos (costo interno)</Text>
          {materiales.length === 0 ? (
            <Text style={styles.muted}>Sin materiales consumidos.</Text>
          ) : (
            <View>
              <View style={styles.tableHeader}>
                <Text style={{ width: '18%' }}>Código</Text>
                <Text style={{ width: '42%' }}>Descripción</Text>
                <Text style={{ width: '13%', textAlign: 'right' }}>Cant.</Text>
                <Text style={{ width: '12%', textAlign: 'right' }}>C. unit.</Text>
                <Text style={{ width: '15%', textAlign: 'right' }}>C. total</Text>
              </View>
              {materiales.map((m) => (
                <View key={m.id} style={styles.tableRow}>
                  <Text style={{ width: '18%' }}>{m.producto_codigo ?? '—'}</Text>
                  <Text style={{ width: '42%' }}>{m.producto_descripcion ?? '—'}</Text>
                  <Text style={{ width: '13%', textAlign: 'right' }}>
                    {fmtNum(m.cantidad_consumida ?? m.cantidad_entregada)} {m.unidad ?? ''}
                  </Text>
                  <Text style={{ width: '12%', textAlign: 'right' }}>{fmtCLP(m.costo_unitario)}</Text>
                  <Text style={{ width: '15%', textAlign: 'right' }}>{fmtCLP(m.costo_total)}</Text>
                </View>
              ))}
              <View style={styles.totalRow}>
                <Text style={styles.totalLabel}>Total materiales (costeo FIFO):</Text>
                <Text style={styles.totalValue}>{fmtCLP(totalMateriales)}</Text>
              </View>
            </View>
          )}
        </View>

        {/* 11. Mano de obra y tiempo efectivo */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>11. Mano de obra y tiempo efectivo</Text>
          {manoobra.length === 0 ? (
            <Text style={styles.muted}>Sin mano de obra registrada.</Text>
          ) : (
            <View>
              <View style={styles.tableHeader}>
                <Text style={{ width: '40%' }}>Técnico</Text>
                <Text style={{ width: '22%', textAlign: 'right' }}>T. efectivo</Text>
                <Text style={{ width: '18%', textAlign: 'right' }}>$ / hora</Text>
                <Text style={{ width: '20%', textAlign: 'right' }}>Costo</Text>
              </View>
              {manoobra.map((m) => (
                <View key={m.id} style={styles.tableRow}>
                  <Text style={{ width: '40%' }}>{m.tecnico_nombre_snapshot ?? '—'}</Text>
                  <Text style={{ width: '22%', textAlign: 'right' }}>{fmtHoras(m.tiempo_efectivo_segundos)}</Text>
                  <Text style={{ width: '18%', textAlign: 'right' }}>{fmtCLP(m.costo_hora_snapshot)}</Text>
                  <Text style={{ width: '20%', textAlign: 'right' }}>{fmtCLP(m.costo_total_snapshot)}</Text>
                </View>
              ))}
              <View style={styles.totalRow}>
                <Text style={styles.totalLabel}>Tiempo efectivo total: {fmtHoras(totalSegundos)}  ·  Costo MO:</Text>
                <Text style={styles.totalValue}>{fmtCLP(totalManoObra)}</Text>
              </View>
            </View>
          )}
        </View>

        {/* 12. Pruebas */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>12. Pruebas de salida</Text>
          {informe.pruebas_resumen?.trim() ? (
            <Text style={[styles.paragraph, { marginBottom: 4 }]}>{informe.pruebas_resumen}</Text>
          ) : null}
          {pruebas.length === 0 ? (
            <Text style={styles.muted}>Sin pruebas registradas.</Text>
          ) : (
            <View>
              <View style={styles.tableHeader}>
                <Text style={{ width: '30%' }}>Prueba</Text>
                <Text style={{ width: '18%' }}>Resultado</Text>
                <Text style={{ width: '22%', textAlign: 'right' }}>Medido</Text>
                <Text style={{ width: '30%', textAlign: 'right' }}>Rango</Text>
              </View>
              {pruebas.map((p) => (
                <View key={p.id} style={styles.tableRow}>
                  <Text style={{ width: '30%' }}>{p.tipo_prueba}</Text>
                  <Text style={{ width: '18%' }}>{p.resultado ?? '—'}</Text>
                  <Text style={{ width: '22%', textAlign: 'right' }}>
                    {p.valor_medido == null ? '—' : `${fmtNum(p.valor_medido)} ${p.unidad ?? ''}`}
                  </Text>
                  <Text style={{ width: '30%', textAlign: 'right' }}>
                    {p.rango_min == null && p.rango_max == null ? '—' : `${fmtNum(p.rango_min)} — ${fmtNum(p.rango_max)}`}
                  </Text>
                </View>
              ))}
            </View>
          )}
          {informe.resultado_pruebas ? (
            <Field label="Resultado global pruebas" value={informe.resultado_pruebas} />
          ) : null}
        </View>

        {/* 13. Evidencias */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>13. Evidencias</Text>
          {evidencias.length === 0 ? (
            <Text style={styles.muted}>Sin evidencias fotográficas asociadas.</Text>
          ) : (
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
              {evidencias.slice(0, 9).map((e, i) => (
                <View key={i} style={{ width: 90, alignItems: 'center' }}>
                  {/* eslint-disable-next-line jsx-a11y/alt-text */}
                  <Image src={e.url as string} style={{ width: 84, height: 63, objectFit: 'cover' }} />
                  <Text style={styles.chip}>{e.etiqueta}</Text>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* 14. Estado de salida */}
        <TextSection title="14. Estado de salida del equipo" value={informe.estado_salida} />

        {/* 15. Restricciones operacionales */}
        <TextSection title="15. Restricciones operacionales" value={informe.restricciones_operacionales} />

        {/* 16. Recomendaciones */}
        <TextSection title="16. Recomendaciones" value={informe.recomendaciones} />

        {/* 17. Firmas */}
        <View style={styles.section} wrap={false}>
          <Text style={styles.sectionTitle}>17. Firmas y responsables</Text>
          <View style={styles.firmaWrap}>
            <View style={styles.firma}>
              {informe.firma_ejecutor_url ? (
                // eslint-disable-next-line jsx-a11y/alt-text
                <Image src={informe.firma_ejecutor_url} style={{ height: 38, marginBottom: 4 }} />
              ) : null}
              <View style={styles.firmaBox} />
              <Text style={styles.firmaLabel}>Ejecutor / Técnico responsable</Text>
            </View>
            <View style={styles.firma}>
              {informe.firma_jefe_url ? (
                // eslint-disable-next-line jsx-a11y/alt-text
                <Image src={informe.firma_jefe_url} style={{ height: 38, marginBottom: 4 }} />
              ) : null}
              <View style={styles.firmaBox} />
              <Text style={styles.firmaLabel}>Jefe de taller / Aprobador</Text>
            </View>
          </View>
        </View>

        {/* 18. Folio, versión y hash */}
        <Text style={styles.footer} fixed>
          {informe.folio} · v{informe.version} · Estado {informe.estado}
          {informe.pdf_sha256 ? `\nSHA-256: ${informe.pdf_sha256}` : ''}
          {'\n'}SICOM-ICEO · Documento técnico interno generado automáticamente
        </Text>
      </Page>
    </Document>
  )
}

/** Genera el PDF del informe técnico como Blob. */
export async function generarPDFInformeTecnico(data: InformeIntervencionDetalle): Promise<Blob> {
  return pdf(<InformeTecnicoPDF data={data} />).toBlob()
}
