'use client'

// Informes ENEX con el formato del mandante (MIG231):
//  · Calibración → CERTIFICADO VERIFICACIÓN DE VOLÚMENES / CONTROL DE SELLOS
//    NCh1436 (PN.OM.DM.MN.F.01)
//  · Mantención  → OT MANTENIMIENTO INTERMEDIO (formato Kizeo del mandante)
// Los datos se llenan AUTOMÁTICAMENTE desde el checklist ejecutado en terreno,
// con las firmas del técnico y del mandante. El PDF se sube al bucket
// documentos/enex-informes y su URL queda en enex_ejecuciones.informe_pdf_url.

import { Document, Page, Text, View, StyleSheet, Image, pdf } from '@react-pdf/renderer'
import { supabase } from '@/lib/supabase'
import { getEjecucionReporte, type EnexReporte, type EnexReporteItem } from '@/lib/services/enex'

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
  row: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#444' },
  cellLabel: { width: '38%', padding: 3, fontSize: 8, color: '#374151', borderRightWidth: 0.5, borderRightColor: '#444' },
  cellValue: { flex: 1, padding: 3, fontSize: 8, fontWeight: 'bold' },
  th: { padding: 3, fontSize: 8, fontWeight: 'bold', backgroundColor: '#f3f4f6', borderRightWidth: 0.5, borderRightColor: '#444', textAlign: 'center' },
  td: { padding: 3, fontSize: 8, borderRightWidth: 0.5, borderRightColor: '#444', textAlign: 'center' },
  firmasRow: { flexDirection: 'row', marginTop: 24 },
  firmaCol: { flex: 1, alignItems: 'center', marginHorizontal: 6 },
  firmaImg: { height: 42, width: 120, objectFit: 'contain' },
  firmaLinea: { borderTopWidth: 1, borderTopColor: '#111', width: '100%', marginTop: 2, paddingTop: 3, alignItems: 'center' },
  firmaNombre: { fontSize: 8, fontWeight: 'bold' },
  firmaCargo: { fontSize: 7, color: '#4b5563' },
  obsBox: { borderWidth: 0.5, borderColor: '#444', minHeight: 30, padding: 4, fontSize: 8 },
  foto: { width: 150, height: 110, objectFit: 'cover', margin: 4, borderWidth: 0.5, borderColor: '#999' },
  fotosWrap: { flexDirection: 'row', flexWrap: 'wrap' },
  footer: { position: 'absolute', bottom: 16, left: 28, right: 28, fontSize: 7, color: '#9ca3af', textAlign: 'center' },

  // ── Resumen de la intervención ──
  kpiRow: { flexDirection: 'row', marginTop: 4 },
  kpiBox: {
    flex: 1, borderWidth: 0.5, borderColor: '#444', padding: 4, marginRight: 3,
    alignItems: 'center', backgroundColor: '#f9fafb',
  },
  kpiNum: { fontSize: 13, fontWeight: 'bold' },
  kpiLbl: { fontSize: 6.5, color: '#4b5563', textAlign: 'center', marginTop: 1 },

  // ── Anexo antes/después ──
  fichaHead: {
    flexDirection: 'row', backgroundColor: '#1f2937', padding: 4, marginTop: 8,
    alignItems: 'center',
  },
  fichaNum: { fontSize: 8, fontWeight: 'bold', color: '#fff', width: 40 },
  fichaTitulo: { flex: 1, fontSize: 8, fontWeight: 'bold', color: '#fff' },
  fichaEstado: { fontSize: 7.5, fontWeight: 'bold', color: '#fff', paddingLeft: 6 },
  adRow: { flexDirection: 'row', borderWidth: 0.5, borderColor: '#444', borderTopWidth: 0 },
  adCol: { width: '50%', padding: 4 },
  adColSep: { borderRightWidth: 0.5, borderRightColor: '#444' },
  adTag: { fontSize: 7.5, fontWeight: 'bold', marginBottom: 3, textAlign: 'center', padding: 2 },
  adTagAntes: { backgroundColor: '#fef3c7', color: '#92400e' },
  adTagDespues: { backgroundColor: '#dcfce7', color: '#166534' },
  adFoto: { width: 74, height: 56, objectFit: 'cover', borderWidth: 0.5, borderColor: '#9ca3af' },
  adFotoCell: { width: 78, marginBottom: 3, alignItems: 'center' },
  adFotoLbl: { fontSize: 5.5, color: '#6b7280', marginTop: 0.5 },
  adVacio: { fontSize: 7, color: '#9ca3af', fontStyle: 'italic', textAlign: 'center', paddingVertical: 10 },
  adObs: {
    fontSize: 7.5, color: '#374151', paddingHorizontal: 4, paddingVertical: 3,
    borderWidth: 0.5, borderTopWidth: 0, borderColor: '#444', backgroundColor: '#f9fafb',
  },
  nota: { fontSize: 7, color: '#6b7280', marginTop: 3, fontStyle: 'italic' },
})

// ── helpers de datos ─────────────────────────────────────────────────────────
const porCodigo = (items: EnexReporteItem[], codigo: string): EnexReporteItem | undefined =>
  items.find((i) => i.item?.codigo === codigo)
const txt = (items: EnexReporteItem[], codigo: string): string =>
  porCodigo(items, codigo)?.observacion ?? ''
const num = (items: EnexReporteItem[], codigo: string): number | null =>
  porCodigo(items, codigo)?.valor_medicion ?? null

const RES_LABEL: Record<string, string> = { ok: 'Bueno', no_ok: 'Malo', na: 'N/A', si: 'Sí', no: 'No' }
const RES_CAL: Record<string, string> = { ok: 'OK', no_ok: 'NO OK', na: 'N/A', si: 'Sí', no: 'No' }

function fmtFecha(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

/** Hora local hh:mm de un timestamp (el que registró la app de terreno). */
function fmtHora(ts?: string | null): string {
  if (!ts) return ''
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ''
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

function fmtDuracion(seg?: number | null): string {
  if (!seg || seg <= 0) return ''
  const h = Math.floor(seg / 3600), m = Math.round((seg % 3600) / 60)
  return h > 0 ? `${h} h ${String(m).padStart(2, '0')} min` : `${m} min`
}

/**
 * Ancho de columna a prueba de bordes: con width en % los bordes y el padding
 * suman de más y Yoga termina imprimiendo una celda encima de la otra. Con
 * flexGrow/flexBasis el reparto es exacto sea cual sea el número de columnas.
 */
const col = (n: number) => ({ flexGrow: n, flexBasis: 0, flexShrink: 1, width: undefined })

const nAntes = (i: EnexReporteItem) => i.fotos_antes?.length ?? 0
const nDespues = (i: EnexReporteItem) => i.fotos_despues?.length ?? 0

/** ¿La actividad fue realmente intervenida? Los datos del servicio (bloque 0)
 *  y el registro fotográfico general no son actividades de pauta. */
const esActividad = (i: EnexReporteItem): boolean => {
  const b = i.item?.bloque ?? ''
  const cod = i.item?.codigo ?? ''
  return !b.startsWith('0.') && !cod.startsWith('DS.') && !cod.startsWith('FOT.')
}

const ESTADO_TXT: Record<string, string> = {
  ok: 'CONFORME', no_ok: 'NO CONFORME', na: 'NO APLICA', si: 'SÍ', no: 'NO',
}

type Datos = { reporte: EnexReporte; items: EnexReporteItem[]; logoUrl: string }

// ── Anexo: ficha de antes/después por actividad ──────────────────────────────
// Es la evidencia con la que el mandante da el trabajo por hecho: cada punto
// intervenido en su propia ficha, con las dos columnas enfrentadas y las fotos
// numeradas para poder citarlas ("ficha 3, foto D2").
function FichaAntesDespues({ it, n }: { it: EnexReporteItem; n: number }) {
  const antes = it.fotos_antes ?? []
  const despues = it.fotos_despues ?? []
  // Una ficha partida a la mitad sale en blanco y se lleva por delante lo que
  // venía después: si no cabe, que salte entera a la página siguiente. Las muy
  // cargadas se dejan fluir, porque no caben enteras en ninguna página.
  const cabeEntera = Math.max(antes.length, despues.length) <= 6
  const estado = it.item?.tipo_campo === 'medicion' && it.valor_medicion != null
    ? `${it.valor_medicion} ${it.item?.unidad ?? ''}`
    : (ESTADO_TXT[it.resultado ?? ''] ?? 'SIN ESTADO')
  const malo = it.resultado === 'no_ok' || it.resultado === 'no' || it.dentro_tolerancia === false

  return (
    <View wrap={!cabeEntera}>
      <View style={S.fichaHead} wrap={false}>
        <Text style={S.fichaNum}>N° {n}</Text>
        <Text style={S.fichaTitulo}>
          {it.item?.codigo ? `${it.item.codigo} · ` : ''}{it.item?.descripcion ?? ''}
        </Text>
        <Text style={[S.fichaEstado, { color: malo ? '#fca5a5' : '#86efac' }]}>{estado}</Text>
      </View>
      <View style={S.adRow}>
        {([['ANTES', antes, 'A'], ['DESPUÉS', despues, 'D']] as const).map(([tag, fotos, pre]) => (
          <View key={tag} style={[S.adCol, pre === 'A' ? S.adColSep : {}]}>
            <Text style={[S.adTag, pre === 'A' ? S.adTagAntes : S.adTagDespues]}>
              {tag}{fotos.length > 0 ? ` — ${fotos.length} foto${fotos.length !== 1 ? 's' : ''}` : ''}
            </Text>
            {fotos.length === 0 ? (
              <Text style={S.adVacio}>Sin registro fotográfico</Text>
            ) : (
              <View style={S.fotosWrap}>
                {fotos.map((u, k) => (
                  <View key={k} style={S.adFotoCell}>
                    <Image src={u} style={S.adFoto} />
                    <Text style={S.adFotoLbl}>{pre}{k + 1}</Text>
                  </View>
                ))}
              </View>
            )}
          </View>
        ))}
      </View>
      {it.observacion ? (
        <Text style={S.adObs}>Observación del técnico: {it.observacion}</Text>
      ) : null}
    </View>
  )
}

// ── CERTIFICADO DE CALIBRACIÓN (NCh1436 · PN.OM.DM.MN.F.01) ─────────────────
export function CertificadoCalibracion({ reporte, items, logoUrl }: Datos) {
  const inst = reporte.programacion?.instalacion
  const conAntesDespues = items.filter((i) => esActividad(i) && (nAntes(i) > 0 || nDespues(i) > 0))
  const corridas = Array.from({ length: 6 }, (_, k) => {
    const med = num(items, `C${k + 1}.MED`)
    const pat = num(items, `C${k + 1}.PAT`)
    const pct = med != null && pat != null && pat !== 0 ? ((med - pat) / pat) * 100 : null
    return { n: k + 1, med, pat, pct }
  })
  const conValores = corridas.filter((c) => c.pct != null)
  const seguridad = items.filter((i) => i.item?.codigo?.startsWith('SEG.'))
  const sellosOk = porCodigo(items, 'CIE.SELLOS_OK')

  return (
    <Document>
      <Page size="LETTER" style={S.page}>
        {/* Encabezado con código de formato del mandante */}
        <View style={S.headerRow}>
          <View style={S.logoBox}>{logoUrl ? <Image src={logoUrl} style={S.logo} /> : <Text>PILLADO</Text>}</View>
          <View style={S.titleBox}>
            <Text style={S.title}>CERTIFICADO VERIFICACIÓN DE VOLÚMENES DE MEDIDORES DE COMBUSTIBLES</Text>
            <Text style={S.title}>CONTROL DE SELLOS NCh1436</Text>
            <Text style={S.subtitle}>PN.OM.DM.MN.F.01 Movimientos Internos en Minería</Text>
          </View>
          <View style={S.metaBox}>
            <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Versión</Text><Text style={S.metaCell}>1</Text></View>
            <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Fecha</Text><Text style={S.metaCell}>{fmtFecha(reporte.fecha_ejecucion)}</Text></View>
            <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Faena</Text><Text style={S.metaCell}>{inst?.faena?.nombre ?? ''}</Text></View>
          </View>
        </View>

        {/* Identificación del surtidor */}
        <Text style={S.sectionTitle}>IDENTIFICACIÓN DEL SURTIDOR</Text>
        {[
          ['Surtidor N° Serie / Camión / Petrolera', `${inst?.nombre ?? ''}${inst?.patente ? ' · ' + inst.patente : ''}${txt(items, 'ID.SURTIDOR') ? ' · ' + txt(items, 'ID.SURTIDOR') : ''}`],
          ['Sello ajuste N°', txt(items, 'ID.SELLO_AJUSTE')],
          ['Sellos cabezal N°', txt(items, 'ID.SELLOS_CAB')],
          ['Sellos cabezal cuerpo medidor', txt(items, 'ID.SELLOS_CPO')],
          ['Modelo medidor / N° serie', txt(items, 'ID.MODELO')],
          ['Tipo de combustible', txt(items, 'ID.COMBUSTIBLE')],
          ['Tanque N°', txt(items, 'ID.TANQUE')],
          ['Totalizador inicio (L)', num(items, 'TOT.INI')?.toLocaleString('es-CL') ?? ''],
          ['Totalizador final (L)', num(items, 'TOT.FIN')?.toLocaleString('es-CL') ?? ''],
          ['Litros recirculados', num(items, 'TOT.REC')?.toLocaleString('es-CL') ?? ''],
        ].map(([l, v], i) => (
          <View key={i} style={[S.row, i === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]}>
            <Text style={S.cellLabel}>{l}</Text><Text style={S.cellValue}>{v || ' '}</Text>
          </View>
        ))}

        {/* Corridas */}
        <Text style={S.sectionTitle}>RESULTADOS — CORRIDAS MEDIDOR vs PATRÓN</Text>
        <View style={[S.row, { borderTopWidth: 0.5, borderTopColor: '#444' }]}>
          <Text style={[S.th, { width: '10%' }]}>N°</Text>
          <Text style={[S.th, { width: '30%' }]}>Lectura Litros Medidor</Text>
          <Text style={[S.th, { width: '30%' }]}>Lectura Litros Patrón</Text>
          <Text style={[S.th, { width: '15%' }]}>Error %</Text>
          <Text style={[S.th, { width: '15%', borderRightWidth: 0 }]}>EMP ±0,5%</Text>
        </View>
        {corridas.map((c) => (
          <View key={c.n} style={S.row}>
            <Text style={[S.td, { width: '10%' }]}>{c.n}</Text>
            <Text style={[S.td, { width: '30%' }]}>{c.med != null ? c.med.toLocaleString('es-CL', { minimumFractionDigits: 1 }) : ''}</Text>
            <Text style={[S.td, { width: '30%' }]}>{c.pat != null ? c.pat.toLocaleString('es-CL', { minimumFractionDigits: 1 }) : ''}</Text>
            <Text style={[S.td, { width: '15%' }]}>{c.pct != null ? `${c.pct >= 0 ? '+' : ''}${c.pct.toFixed(2)}%` : ''}</Text>
            <Text style={[S.td, { width: '15%', borderRightWidth: 0, fontWeight: 'bold', color: c.pct == null ? '#111' : Math.abs(c.pct) <= 0.5 ? '#166534' : '#b91c1c' }]}>
              {c.pct != null ? (Math.abs(c.pct) <= 0.5 ? 'CUMPLE' : 'NO CUMPLE') : ''}
            </Text>
          </View>
        ))}
        {conValores.length > 0 && (
          <View style={[S.row, { backgroundColor: '#f9fafb' }]}>
            <Text style={[S.td, { width: '70%', textAlign: 'right', fontWeight: 'bold' }]}>RESULTADO FINAL</Text>
            <Text style={[S.td, { width: '30%', borderRightWidth: 0, fontWeight: 'bold', color: conValores.every((c) => Math.abs(c.pct!) <= 0.5) ? '#166534' : '#b91c1c' }]}>
              {conValores.every((c) => Math.abs(c.pct!) <= 0.5) ? 'CONFORME' : 'NO CONFORME'}
            </Text>
          </View>
        )}

        {/* Seguridad previa + sellos */}
        <Text style={S.sectionTitle}>VERIFICACIÓN PREVIA E INSPECCIÓN DE SELLOS</Text>
        {seguridad.map((i, k) => (
          <View key={k} style={[S.row, k === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]}>
            <Text style={[S.cellLabel, { width: '78%' }]}>{i.item?.descripcion}</Text>
            <Text style={S.cellValue}>{RES_CAL[i.resultado ?? ''] ?? '—'}</Text>
          </View>
        ))}
        {[
          ['Inspección de sellos conforme', RES_CAL[sellosOk?.resultado ?? ''] ?? '—'],
          ['Sello nuevo instalado N°', txt(items, 'CIE.SELLO_NVO')],
          ['¿Requirió ajuste?', txt(items, 'CIE.AJUSTE')],
        ].map(([l, v], i) => (
          <View key={`c${i}`} style={S.row}><Text style={S.cellLabel}>{l}</Text><Text style={S.cellValue}>{v || ' '}</Text></View>
        ))}
        <Text style={[S.sectionTitle, { marginTop: 6 }]}>OBSERVACIONES</Text>
        <Text style={S.obsBox}>{[txt(items, 'CIE.OBS'), reporte.observacion].filter(Boolean).join(' · ') || ' '}</Text>

        {/* La calibración también deja evidencia por punto (sellos, cabezal):
            va en el mismo formato de ficha que la mantención. */}
        {conAntesDespues.length > 0 && (
          <View break>
            <Text style={S.sectionTitle}>ANEXO FOTOGRÁFICO — ANTES Y DESPUÉS POR PUNTO VERIFICADO</Text>
            {conAntesDespues.map((i, k) => <FichaAntesDespues key={`ad-${i.id}`} it={i} n={k + 1} />)}
          </View>
        )}

        {/* Firmas */}
        <View style={S.firmasRow} wrap={false}>
          <View style={S.firmaCol}>
            {reporte.firma_tecnico_url ? <Image src={reporte.firma_tecnico_url} style={S.firmaImg} /> : <View style={{ height: 42 }} />}
            <View style={S.firmaLinea}>
              <Text style={S.firmaNombre}>{reporte.tecnico_nombre ?? reporte.ejecutor ?? ''}</Text>
              <Text style={S.firmaCargo}>Verificación realizada por{'\n'}Nombre / Cargo / Firma</Text>
            </View>
          </View>
          <View style={S.firmaCol}>
            <View style={{ height: 42 }} />
            <View style={S.firmaLinea}>
              <Text style={S.firmaNombre}> </Text>
              <Text style={S.firmaCargo}>Supervisor a cargo del Proceso{'\n'}Nombre / Cargo / Firma</Text>
            </View>
          </View>
          <View style={S.firmaCol}>
            {reporte.firma_mandante_url ? <Image src={reporte.firma_mandante_url} style={S.firmaImg} /> : <View style={{ height: 42 }} />}
            <View style={S.firmaLinea}>
              <Text style={S.firmaNombre}>{reporte.firmante_mandante_nombre ?? ''}</Text>
              <Text style={S.firmaCargo}>Representante del Cliente{'\n'}Nombre / Cargo / Firma</Text>
            </View>
          </View>
        </View>
        <Text style={S.footer} fixed render={({ pageNumber, totalPages }) => (
          `SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM VA_24_068 · ` +
          `${inst?.nombre ?? ''} · ${fmtFecha(reporte.fecha_ejecucion)} · Página ${pageNumber} de ${totalPages}`
        )} />
      </Page>
    </Document>
  )
}

// ── OT MANTENIMIENTO INTERMEDIO (formato Kizeo del mandante) ────────────────
export function OtMantenimiento({ reporte, items, logoUrl }: Datos) {
  const inst = reporte.programacion?.instalacion
  // Bloques de pauta (excluye datos de servicio y registro fotográfico)
  const bloques: { bloque: string; items: EnexReporteItem[] }[] = []
  for (const it of items) {
    if (!esActividad(it)) continue
    const b = it.item?.bloque ?? ''
    let g = bloques.find((x) => x.bloque === b)
    if (!g) { g = { bloque: b, items: [] }; bloques.push(g) }
    g.items.push(it)
  }
  const fotos = [
    ...items.filter((i) => i.foto_url).map((i) => i.foto_url!),
    ...(reporte.evidencia_urls ?? []),
  ]
  // [MIG265] Evidencia del antes/después por actividad: es lo que el mandante
  // pide para dar el trabajo por hecho. Antes no salía en el informe.
  const conAntesDespues = items.filter((i) => esActividad(i) && (nAntes(i) > 0 || nDespues(i) > 0))
  // La ficha del anexo se numera una sola vez y la tabla de la pauta la cita,
  // para que el mandante salte de la actividad a su evidencia.
  const fichaDe = new Map(conAntesDespues.map((i, k) => [i.id, k + 1]))

  const actividades = items.filter(esActividad)
  const cta = {
    ejecutadas: actividades.length,
    ok: actividades.filter((i) => i.resultado === 'ok' || i.resultado === 'si').length,
    noOk: actividades.filter((i) => i.resultado === 'no_ok' || i.resultado === 'no' || i.dentro_tolerancia === false).length,
    na: actividades.filter((i) => i.resultado === 'na').length,
    antes: actividades.reduce((s, i) => s + nAntes(i), 0),
    despues: actividades.reduce((s, i) => s + nDespues(i), 0),
  }
  const noConformes = actividades.filter(
    (i) => i.resultado === 'no_ok' || i.resultado === 'no' || i.dentro_tolerancia === false)
  // Trabajadas sin las dos caras de la evidencia: el mandante puede objetarlas.
  const evidenciaIncompleta = actividades.filter(
    (i) => i.resultado && i.resultado !== 'na' && (nAntes(i) === 0 || nDespues(i) === 0))

  const horaIni = txt(items, 'DS.HORA_INI') || fmtHora(reporte.inicio_at)
  const horaFin = txt(items, 'DS.HORA_FIN') || fmtHora(reporte.fin_at)
  const duracion = fmtDuracion(reporte.duracion_segundos)

  return (
    <Document>
      <Page size="LETTER" style={S.page}>
        <View style={S.headerRow}>
          <View style={S.logoBox}>{logoUrl ? <Image src={logoUrl} style={S.logo} /> : <Text>PILLADO</Text>}</View>
          <View style={S.titleBox}>
            <Text style={S.title}>OT MANTENIMIENTO INTERMEDIO {inst?.tipo === 'semimovil' ? 'SM' : ''}</Text>
            <Text style={S.subtitle}>Contrato ENEX / ESM — Mantenimiento de instalaciones de combustibles y lubricantes</Text>
          </View>
          <View style={S.metaBox}>
            <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>Fecha</Text><Text style={S.metaCell}>{fmtFecha(reporte.fecha_ejecucion)}</Text></View>
            <View style={S.metaRow}><Text style={[S.metaCell, { width: 45, fontWeight: 'bold' }]}>N° OT</Text><Text style={S.metaCell}>{reporte.ot_numero ?? '—'}</Text></View>
          </View>
        </View>

        <Text style={S.sectionTitle}>MANTENIMIENTO INTERMEDIO {inst?.faena?.nombre?.toUpperCase() ?? ''}</Text>
        {[
          ['DIVISIÓN', inst?.faena?.nombre ?? ''],
          ['CLIENTE', 'ESM / ENEX'],
          ['EDS / PETROLERA', `${inst?.nombre ?? ''}${inst?.patente ? ' · ' + inst.patente : ''}`],
          ['FECHA', fmtFecha(reporte.fecha_ejecucion)],
          ['HORA INICIO', horaIni],
          ['HORA TÉRMINO', horaFin],
          ['DURACIÓN EN TERRENO', duracion],
          ['TÉCNICO(S) EJECUTOR(ES)', txt(items, 'DS.RUT_TEC') || reporte.tecnico_nombre || reporte.ejecutor || ''],
          ['PAUTA APLICADA', `${reporte.pauta?.codigo ?? ''} ${reporte.pauta?.nombre ?? ''}${reporte.pauta?.version ? ' · v' + reporte.pauta.version : ''}`.trim()],
          ['MOTIVO DEL LLAMADO', txt(items, 'DS.MOTIVO')],
        ].map(([l, v], i) => (
          <View key={i} style={[S.row, i === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]}>
            <Text style={S.cellLabel}>{l}</Text><Text style={S.cellValue}>{v || ' '}</Text>
          </View>
        ))}

        {/* Resumen de la intervención: lo que el supervisor del mandante mira
            primero — cuánto se intervino y con cuánta evidencia se respalda. */}
        <Text style={S.sectionTitle}>RESUMEN DE LA INTERVENCIÓN</Text>
        <View style={S.kpiRow}>
          {[
            { n: String(cta.ejecutadas), l: 'Actividades\nintervenidas', c: '#111827' },
            { n: String(cta.ok), l: 'Conformes', c: '#166534' },
            { n: String(cta.noOk), l: 'No conformes', c: cta.noOk > 0 ? '#b91c1c' : '#111827' },
            { n: String(cta.na), l: 'No aplica', c: '#6b7280' },
            { n: String(cta.antes), l: 'Fotos ANTES', c: '#92400e' },
            { n: String(cta.despues), l: 'Fotos DESPUÉS', c: '#166534' },
          ].map((k, i) => (
            <View key={i} style={[S.kpiBox, i === 5 ? { marginRight: 0 } : {}]}>
              <Text style={[S.kpiNum, { color: k.c }]}>{k.n}</Text>
              <Text style={S.kpiLbl}>{k.l}</Text>
            </View>
          ))}
        </View>
        <Text style={S.nota}>
          Cada actividad intervenida se respalda con su ficha de antes y después en el anexo fotográfico
          {conAntesDespues.length > 0 ? ` (fichas N° 1 a ${conAntesDespues.length})` : ''}.
        </Text>

        {/* Hallazgos: si algo quedó no conforme, va arriba y no enterrado en la
            tabla — es lo que dispara la siguiente OT. */}
        {noConformes.length > 0 && (<>
          <Text style={[S.sectionTitle, { backgroundColor: '#fee2e2' }]}>HALLAZGOS NO CONFORMES ({noConformes.length})</Text>
          {noConformes.map((i, k) => (
            <View key={`nc-${i.id}`} style={[S.row, k === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]}>
              <Text style={[S.cellLabel, col(46)]}>{i.item?.codigo ? `${i.item.codigo} · ` : ''}{i.item?.descripcion}</Text>
              <Text style={[S.cellValue, col(40), { fontWeight: 'normal', fontSize: 7.5, color: '#b91c1c', borderRightWidth: 0.5, borderRightColor: '#444' }]}>
                {i.observacion ?? 'Sin detalle registrado en terreno'}
              </Text>
              <Text style={[S.cellValue, col(14), { textAlign: 'center', fontSize: 7, fontWeight: 'normal' }]}>
                {fichaDe.get(i.id) ? `Ficha ${fichaDe.get(i.id)}` : '—'}
              </Text>
            </View>
          ))}
        </>)}

        <Text style={S.sectionTitle}>PAUTA DE REVISIÓN DE MANTENIMIENTO</Text>
        {bloques.map((g) => (
          <View key={g.bloque} wrap={false}>
            <Text style={[S.sectionTitle, { backgroundColor: '#f3f4f6', marginTop: 4 }]}>{g.bloque.replace(/^\d+\.\s*/, '').toUpperCase()}</Text>
            {/* Columnas por flexGrow, no por %: los bordes hacían que la última
                celda terminara impresa encima de la del estado. */}
            <View style={[S.row, { borderTopWidth: 0.5, borderTopColor: '#444' }]}>
              <Text style={[S.th, col(46), { textAlign: 'left' }]}>ACTIVIDAD</Text>
              <Text style={[S.th, col(13)]}>ESTADO</Text>
              <Text style={[S.th, col(25)]}>OBSERVACIÓN</Text>
              <Text style={[S.th, col(16), { borderRightWidth: 0 }]}>EVIDENCIA</Text>
            </View>
            {g.items.map((i, k) => {
              const a = nAntes(i), d = nDespues(i), ficha = fichaDe.get(i.id)
              return (
                <View key={k} style={S.row}>
                  <Text style={[S.cellLabel, col(46)]}>
                    {i.item?.codigo ? `${i.item.codigo}  ` : ''}{i.item?.descripcion}
                  </Text>
                  <Text style={[S.cellValue, col(13), { textAlign: 'center', borderRightWidth: 0.5, borderRightColor: '#444', color: i.resultado === 'no_ok' || i.resultado === 'no' ? '#b91c1c' : '#111' }]}>
                    {i.item?.tipo_campo === 'medicion'
                      ? (i.valor_medicion != null ? `${i.valor_medicion} ${i.item?.unidad ?? ''}` : '—')
                      : (RES_LABEL[i.resultado ?? ''] ?? '—')}
                  </Text>
                  <Text style={[S.cellValue, col(25), { fontWeight: 'normal', fontSize: 7, color: '#4b5563', borderRightWidth: 0.5, borderRightColor: '#444' }]}>
                    {i.observacion ?? '—'}
                  </Text>
                  <Text style={[S.cellValue, col(16), { textAlign: 'center', fontSize: 6.5, fontWeight: 'normal', color: a > 0 && d > 0 ? '#166534' : a + d > 0 ? '#92400e' : '#9ca3af' }]}>
                    {a + d === 0 ? 'sin fotos' : `A:${a} / D:${d}${ficha ? `\nFicha ${ficha}` : ''}`}
                  </Text>
                </View>
              )
            })}
          </View>
        ))}

        {reporte.observacion && (<>
          <Text style={S.sectionTitle}>OBSERVACIÓN GENERAL DEL SERVICIO</Text>
          <Text style={S.obsBox}>{reporte.observacion}</Text>
        </>)}

        {fotos.length > 0 && (<>
          <Text style={S.sectionTitle}>REGISTRO FOTOGRÁFICO COMPLEMENTARIO</Text>
          <View style={S.fotosWrap}>
            {fotos.map((u, i) => <Image key={i} src={u} style={S.foto} />)}
          </View>
        </>)}

        <View style={S.firmasRow} wrap={false}>
          <View style={S.firmaCol}>
            {reporte.firma_tecnico_url ? <Image src={reporte.firma_tecnico_url} style={S.firmaImg} /> : <View style={{ height: 42 }} />}
            <View style={S.firmaLinea}>
              <Text style={S.firmaNombre}>{reporte.tecnico_nombre ?? reporte.ejecutor ?? ''}</Text>
              {txt(items, 'DS.RUT_TEC') ? <Text style={S.firmaCargo}>RUT: {txt(items, 'DS.RUT_TEC')}</Text> : null}
              <Text style={S.firmaCargo}>TÉCNICO EJECUTOR</Text>
            </View>
          </View>
          <View style={S.firmaCol}>
            {reporte.firma_mandante_url ? <Image src={reporte.firma_mandante_url} style={S.firmaImg} /> : <View style={{ height: 42 }} />}
            <View style={S.firmaLinea}>
              <Text style={S.firmaNombre}>{reporte.firmante_mandante_nombre ?? ''}</Text>
              <Text style={S.firmaCargo}>
                REVISADO POR (ESM / ENEX)
                {reporte.firmante_mandante_at ? `\n${fmtFecha(reporte.firmante_mandante_at)} ${fmtHora(reporte.firmante_mandante_at)}` : ''}
              </Text>
            </View>
          </View>
        </View>

        <Text style={S.footer} fixed render={({ pageNumber, totalPages }) => (
          `SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM VA_24_068 · ` +
          `${inst?.nombre ?? ''} · ${fmtFecha(reporte.fecha_ejecucion)} · Página ${pageNumber} de ${totalPages}`
        )} />
      </Page>

      {/* [MIG265] Antes y después de cada actividad: la evidencia que respalda
          el trabajo ante el mandante. Va en páginas propias — como anexo, y
          porque intercalarlo con el cuerpo dejaba fichas impresas en blanco. */}
      {conAntesDespues.length > 0 && (
        <Page size="LETTER" style={S.page}>
          <Text style={[S.sectionTitle, { marginTop: 0 }]}>ANEXO FOTOGRÁFICO — ANTES Y DESPUÉS POR ACTIVIDAD</Text>
          <Text style={S.nota}>
            {inst?.nombre ?? ''} · {fmtFecha(reporte.fecha_ejecucion)} ·
            {' '}{conAntesDespues.length} actividad{conAntesDespues.length !== 1 ? 'es' : ''} con evidencia ·
            {' '}{cta.antes} foto(s) del antes y {cta.despues} del después, en el orden en que las capturó el
            técnico en terreno.
          </Text>
          {conAntesDespues.map((i, k) => <FichaAntesDespues key={`ad-${i.id}`} it={i} n={k + 1} />)}
          {evidenciaIncompleta.length > 0 && (
            <Text style={[S.nota, { marginTop: 6 }]}>
              Nota: {evidenciaIncompleta.length} actividad(es) intervenida(s) quedaron sin una de las dos
              caras de la evidencia (antes o después).
            </Text>
          )}
          <Text style={S.footer} fixed render={({ pageNumber, totalPages }) => (
            `SICOM-ICEO · Pillado y Cía. Ltda. · Anexo fotográfico · ` +
            `${inst?.nombre ?? ''} · ${fmtFecha(reporte.fecha_ejecucion)} · Página ${pageNumber} de ${totalPages}`
          )} />
        </Page>
      )}
    </Document>
  )
}

// ── Generación + almacenamiento del PDF ─────────────────────────────────────

// react-pdf se cuelga (promesa que nunca resuelve) si su fetch interno de una
// imagen remota falla: convertimos TODO a data URL nosotros, con timeout.
export async function aDataUrl(url: string | null | undefined, timeoutMs = 8000): Promise<string | null> {
  if (!url) return null
  try {
    const ctl = new AbortController()
    const t = setTimeout(() => ctl.abort(), timeoutMs)
    const res = await fetch(url, { signal: ctl.signal })
    clearTimeout(t)
    if (!res.ok) return null
    const blob = await res.blob()
    return await new Promise((resolve) => {
      const fr = new FileReader()
      fr.onload = () => resolve(fr.result as string)
      fr.onerror = () => resolve(null)
      fr.readAsDataURL(blob)
    })
  } catch { return null }
}

/**
 * Las fotos llegan del teléfono sin comprimir (~2,3 MB cada una) y una visita
 * trae decenas: embebidas tal cual, el PDF se va sobre los 100 MB y la
 * generación revienta antes de terminar. Se reescalan a JPEG antes de entrar.
 */
async function aDataUrlComprimida(
  url: string | null | undefined, maxPx = 1100, calidad = 0.72,
): Promise<string | null> {
  const original = await aDataUrl(url, 15_000)
  if (!original) return null
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new window.Image()
      el.onload = () => resolve(el)
      el.onerror = () => reject(new Error('imagen ilegible'))
      el.src = original
    })
    const escala = Math.min(1, maxPx / Math.max(img.width, img.height))
    if (escala >= 1 && original.length < 400_000) return original
    const cv = document.createElement('canvas')
    cv.width = Math.round(img.width * escala)
    cv.height = Math.round(img.height * escala)
    const ctx = cv.getContext('2d')
    if (!ctx) return original
    ctx.drawImage(img, 0, 0, cv.width, cv.height)
    return cv.toDataURL('image/jpeg', calidad)
  } catch {
    return original   // si el canvas falla, mejor pesada que ausente
  }
}

/** Descarga en paralelo con tope: 40 fotos de una vez tumban el teléfono. */
async function enLotes<T, R>(xs: T[], n: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(xs.length)
  let i = 0
  await Promise.all(Array.from({ length: Math.min(n, xs.length) }, async () => {
    while (i < xs.length) { const k = i++; out[k] = await fn(xs[k]) }
  }))
  return out
}

// Genera el informe (formato según tipo de servicio), lo sube al bucket
// documentos/enex-informes y guarda la URL en la ejecución. Devuelve la URL.
export async function generarYGuardarInformeEnex(ejecucionId: string): Promise<string> {
  const { reporte, items } = await getEjecucionReporte(ejecucionId)
  if (!reporte) throw new Error('Ejecución no encontrada')

  // Pre-cargar imágenes como data URLs (logo, firmas, fotos de ítems, evidencias)
  const logoUrl = await aDataUrl(`${window.location.origin}/images/logo_empresa_2.png`)
  reporte.firma_tecnico_url = await aDataUrl(reporte.firma_tecnico_url)
  reporte.firma_mandante_url = await aDataUrl(reporte.firma_mandante_url)

  // [MIG265] Las galerías también: react-pdf necesita data URLs. Se resuelven
  // todas juntas (antes era una tras otra: con 40 fotos se iba al timeout).
  type Slot = { set: (v: string | null) => void; url: string }
  const slots: Slot[] = []
  for (const it of items) {
    if (it.foto_url) slots.push({ url: it.foto_url, set: (v) => { it.foto_url = v } })
    for (const campo of ['fotos_antes', 'fotos_despues'] as const) {
      const arr = it[campo]
      if (!arr?.length) continue
      const resueltas: (string | null)[] = new Array(arr.length)
      arr.forEach((u, k) => slots.push({ url: u, set: (v) => { resueltas[k] = v } }))
      // El array final se arma después de resolver todos los slots.
      ;(it as unknown as Record<string, unknown>)[`__${campo}`] = resueltas
    }
  }
  const evidResueltas: (string | null)[] = new Array((reporte.evidencia_urls ?? []).length)
  ;(reporte.evidencia_urls ?? []).forEach((u, k) => slots.push({ url: u, set: (v) => { evidResueltas[k] = v } }))

  await enLotes(slots, 5, async (s) => s.set(await aDataUrlComprimida(s.url)))

  for (const it of items) {
    for (const campo of ['fotos_antes', 'fotos_despues'] as const) {
      const pend = (it as unknown as Record<string, unknown>)[`__${campo}`] as (string | null)[] | undefined
      if (pend) {
        it[campo] = pend.filter(Boolean) as string[]
        delete (it as unknown as Record<string, unknown>)[`__${campo}`]
      }
    }
  }
  reporte.evidencia_urls = evidResueltas.filter(Boolean) as string[]

  const esCalibracion = reporte.programacion?.tipo_servicio === 'calibracion'
  const doc = esCalibracion
    ? <CertificadoCalibracion reporte={reporte} items={items} logoUrl={logoUrl ?? ''} />
    : <OtMantenimiento reporte={reporte} items={items} logoUrl={logoUrl ?? ''} />
  // Timeout de seguridad: si react-pdf se cuelga, avisar en vez de esperar eterno.
  // Un anexo de decenas de fotos toma su tiempo, de ahí el margen amplio.
  const blob = await Promise.race([
    pdf(doc).toBlob(),
    new Promise<never>((_, rej) => setTimeout(() => rej(new Error('La generación del PDF tardó demasiado — reintenta')), 120_000)),
  ])

  const fecha = (reporte.fecha_ejecucion ?? new Date().toISOString()).slice(0, 10)
  const nombre = esCalibracion ? 'certificado-calibracion' : 'ot-mantenimiento'
  // Nombre único por generación (sin upsert: el x-upsert de Storage exige
  // políticas extra y falla con RLS; además así queda histórico de versiones).
  const path = `enex-informes/${fecha.slice(0, 4)}/${nombre}_${fecha}_${ejecucionId}_${Date.now()}.pdf`
  const { error } = await supabase.storage.from('documentos').upload(path, blob, {
    contentType: 'application/pdf', upsert: false,
  })
  if (error) throw error
  const url = supabase.storage.from('documentos').getPublicUrl(path).data.publicUrl

  const { error: e2 } = await supabase.rpc('rpc_enex_guardar_informe_pdf', {
    p_ejecucion_id: ejecucionId, p_url: url,
  })
  if (e2) throw e2
  return url
}
