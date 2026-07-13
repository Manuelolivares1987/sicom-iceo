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

type Datos = { reporte: EnexReporte; items: EnexReporteItem[]; logoUrl: string }

// ── CERTIFICADO DE CALIBRACIÓN (NCh1436 · PN.OM.DM.MN.F.01) ─────────────────
export function CertificadoCalibracion({ reporte, items, logoUrl }: Datos) {
  const inst = reporte.programacion?.instalacion
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

        {/* Firmas */}
        <View style={S.firmasRow}>
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
        <Text style={S.footer}>SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM VA_24_068 · Documento generado automáticamente desde la ejecución en terreno</Text>
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
    const b = it.item?.bloque ?? ''
    const cod = it.item?.codigo ?? ''
    if (b.startsWith('0.') || cod.startsWith('FOT.') || cod.startsWith('DS.')) continue
    let g = bloques.find((x) => x.bloque === b)
    if (!g) { g = { bloque: b, items: [] }; bloques.push(g) }
    g.items.push(it)
  }
  const fotos = [
    ...items.filter((i) => i.foto_url).map((i) => i.foto_url!),
    ...(reporte.evidencia_urls ?? []),
  ].slice(0, 6)

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
          ['HORA INICIO', txt(items, 'DS.HORA_INI')],
          ['HORA TÉRMINO', txt(items, 'DS.HORA_FIN')],
          ['MOTIVO DEL LLAMADO', txt(items, 'DS.MOTIVO')],
        ].map(([l, v], i) => (
          <View key={i} style={[S.row, i === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]}>
            <Text style={S.cellLabel}>{l}</Text><Text style={S.cellValue}>{v || ' '}</Text>
          </View>
        ))}

        <Text style={S.sectionTitle}>PAUTA DE REVISIÓN DE MANTENIMIENTO</Text>
        {bloques.map((g) => (
          <View key={g.bloque} wrap={false}>
            <Text style={[S.sectionTitle, { backgroundColor: '#f3f4f6', marginTop: 4 }]}>{g.bloque.replace(/^\d+\.\s*/, '').toUpperCase()}</Text>
            {g.items.map((i, k) => (
              <View key={k} style={[S.row, k === 0 ? { borderTopWidth: 0.5, borderTopColor: '#444' } : {}]}>
                <Text style={[S.cellLabel, { width: '58%' }]}>{i.item?.descripcion}</Text>
                <Text style={[S.cellValue, { width: '14%', flex: 0, borderRightWidth: 0.5, borderRightColor: '#444', color: i.resultado === 'no_ok' ? '#b91c1c' : '#111' }]}>
                  {i.item?.tipo_campo === 'medicion'
                    ? (i.valor_medicion != null ? `${i.valor_medicion} ${i.item?.unidad ?? ''}` : '—')
                    : (RES_LABEL[i.resultado ?? ''] ?? '—')}
                </Text>
                <Text style={[S.cellValue, { fontWeight: 'normal', fontSize: 7, color: '#4b5563' }]}>
                  Obs: {i.observacion ?? 'S/N'}
                </Text>
              </View>
            ))}
          </View>
        ))}

        {reporte.observacion && (<>
          <Text style={S.sectionTitle}>OBSERVACIÓN GENERAL</Text>
          <Text style={S.obsBox}>{reporte.observacion}</Text>
        </>)}

        {fotos.length > 0 && (<>
          <Text style={S.sectionTitle}>REGISTRO FOTOGRÁFICO — TÉCNICO EJECUTOR</Text>
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
              <Text style={S.firmaCargo}>REVISADO POR (ESM / ENEX)</Text>
            </View>
          </View>
        </View>
        <Text style={S.footer}>SICOM-ICEO · Pillado y Cía. Ltda. · Contrato ENEX/ESM VA_24_068 · Documento generado automáticamente desde la ejecución en terreno</Text>
      </Page>
    </Document>
  )
}

// ── Generación + almacenamiento del PDF ─────────────────────────────────────

// react-pdf se cuelga (promesa que nunca resuelve) si su fetch interno de una
// imagen remota falla: convertimos TODO a data URL nosotros, con timeout.
async function aDataUrl(url: string | null | undefined, timeoutMs = 8000): Promise<string | null> {
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

// Genera el informe (formato según tipo de servicio), lo sube al bucket
// documentos/enex-informes y guarda la URL en la ejecución. Devuelve la URL.
export async function generarYGuardarInformeEnex(ejecucionId: string): Promise<string> {
  const { reporte, items } = await getEjecucionReporte(ejecucionId)
  if (!reporte) throw new Error('Ejecución no encontrada')

  // Pre-cargar imágenes como data URLs (logo, firmas, fotos de ítems, evidencias)
  const logoUrl = await aDataUrl(`${window.location.origin}/images/logo_empresa_2.png`)
  reporte.firma_tecnico_url = await aDataUrl(reporte.firma_tecnico_url)
  reporte.firma_mandante_url = await aDataUrl(reporte.firma_mandante_url)
  for (const it of items) it.foto_url = await aDataUrl(it.foto_url)
  reporte.evidencia_urls = (await Promise.all((reporte.evidencia_urls ?? []).map((u) => aDataUrl(u))))
    .filter(Boolean) as string[]

  const esCalibracion = reporte.programacion?.tipo_servicio === 'calibracion'
  const doc = esCalibracion
    ? <CertificadoCalibracion reporte={reporte} items={items} logoUrl={logoUrl ?? ''} />
    : <OtMantenimiento reporte={reporte} items={items} logoUrl={logoUrl ?? ''} />
  // Timeout de seguridad: si react-pdf se cuelga, avisar en vez de esperar eterno.
  const blob = await Promise.race([
    pdf(doc).toBlob(),
    new Promise<never>((_, rej) => setTimeout(() => rej(new Error('La generación del PDF tardó demasiado — reintenta')), 45_000)),
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
