'use client'

// Informe trimestral ENEX (MIG590) — consolidado de los informes de servicio
// del período: cumplimiento, detalle por punto, cobertura de la pauta,
// hallazgos, requerimientos y reprogramaciones. Sin fotos (cada informe
// individual las trae y se enlaza en el anexo): un PDF con fotos de un
// trimestre pesaría cientos de MB.

import { Document, Page, Text, View, StyleSheet, Image, Link, pdf } from '@react-pdf/renderer'
import { aDataUrl } from './pdf-informe-enex'
import { MESES, REQ_PRIORIDAD_LABEL, REQ_TIPO_LABEL, REPROG_CAUSA, type EnexFaena } from '@/lib/services/enex'
import type { InformeTrimestral } from '@/lib/enex-informe-trimestral'

const S = StyleSheet.create({
  page: { padding: 30, paddingBottom: 40, fontSize: 8.5, fontFamily: 'Helvetica', color: '#111827' },
  header: { flexDirection: 'row', borderWidth: 1, borderColor: '#111', marginBottom: 10 },
  logoBox: { width: 110, padding: 6, borderRightWidth: 1, borderRightColor: '#111', justifyContent: 'center' },
  logo: { width: 90, height: 28, objectFit: 'contain' },
  titleBox: { flex: 1, padding: 6, justifyContent: 'center' },
  title: { fontSize: 12, fontFamily: 'Helvetica-Bold', textAlign: 'center' },
  subtitle: { fontSize: 9, textAlign: 'center', marginTop: 2, color: '#374151' },
  metaBox: { width: 140, padding: 6, borderLeftWidth: 1, borderLeftColor: '#111', fontSize: 7.5, justifyContent: 'center' },
  h2: { backgroundColor: '#1e3a5f', color: '#fff', fontFamily: 'Helvetica-Bold', fontSize: 9, padding: 4, marginTop: 10, marginBottom: 4 },
  kpis: { flexDirection: 'row', flexWrap: 'wrap', marginBottom: 4 },
  kpi: { width: '24%', marginRight: '1%', marginBottom: 4, borderWidth: 0.5, borderColor: '#9ca3af', padding: 5 },
  kpiLbl: { fontSize: 7, color: '#6b7280' },
  kpiVal: { fontSize: 13, fontFamily: 'Helvetica-Bold', marginTop: 1 },
  kpiSub: { fontSize: 6.5, color: '#6b7280' },
  parrafo: { fontSize: 8.5, lineHeight: 1.4, textAlign: 'justify' },
  th: { flexDirection: 'row', backgroundColor: '#e5e7eb', borderWidth: 0.5, borderColor: '#6b7280', fontFamily: 'Helvetica-Bold', fontSize: 7.5 },
  tr: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#9ca3af', fontSize: 7.5 },
  td: { padding: 3 },
  vacio: { fontSize: 8, color: '#6b7280', fontStyle: 'italic', padding: 3 },
  firmas: { flexDirection: 'row', marginTop: 34 },
  firma: { flex: 1, marginHorizontal: 20, borderTopWidth: 0.7, borderTopColor: '#111', paddingTop: 4, alignItems: 'center', fontSize: 8 },
  footer: { position: 'absolute', bottom: 16, left: 30, right: 30, fontSize: 7, color: '#9ca3af', flexDirection: 'row', justifyContent: 'space-between' },
  link: { color: '#1d4ed8', textDecoration: 'none' },
})

const pct = (n: number | null) => (n == null ? '—' : `${n.toLocaleString('es-CL', { maximumFractionDigits: 1 })} %`)
const fecha = (iso?: string | null) => (iso ? `${iso.slice(8, 10)}-${iso.slice(5, 7)}-${iso.slice(0, 4)}` : '—')

function Tabla({ cols, filas, vacio }: { cols: { t: string; w: string; align?: 'right' | 'center' }[]; filas: (string | JSX.Element)[][]; vacio: string }) {
  return (
    <View>
      <View style={S.th} fixed>
        {cols.map((c, i) => <Text key={i} style={[S.td, { width: c.w, textAlign: c.align ?? 'left' }]}>{c.t}</Text>)}
      </View>
      {filas.length === 0 ? <Text style={[S.tr, S.vacio]}>{vacio}</Text> : filas.map((f, k) => (
        <View key={k} style={S.tr} wrap={false}>
          {f.map((v, i) => typeof v === 'string'
            ? <Text key={i} style={[S.td, { width: cols[i].w, textAlign: cols[i].align ?? 'left' }]}>{v}</Text>
            : <View key={i} style={[S.td, { width: cols[i].w }]}>{v}</View>)}
        </View>
      ))}
    </View>
  )
}

type Props = {
  inf: InformeTrimestral; faena: EnexFaena; periodo: string; desde: string; hasta: string
  comentarios: string; elaboradoPor: string; logoUrl: string | null; emitido: string
}

export function InformeTrimestralDoc({ inf, faena, periodo, desde, hasta, comentarios, elaboradoPor, logoUrl, emitido }: Props) {
  const r = inf.resumen
  return (
    <Document title={`Informe trimestral ${faena.nombre} ${periodo}`}>
      <Page size="A4" style={S.page}>
        <View style={S.header}>
          <View style={S.logoBox}>{logoUrl ? <Image src={logoUrl} style={S.logo} /> : <Text>PILLADO</Text>}</View>
          <View style={S.titleBox}>
            <Text style={S.title}>INFORME TRIMESTRAL DE MANTENIMIENTO</Text>
            <Text style={S.subtitle}>{faena.nombre} · {periodo}</Text>
          </View>
          <View style={S.metaBox}>
            <Text>Contrato: {faena.contrato_minero ?? 'VA_24_068'}</Text>
            <Text>Mandante: ESM / ENEX{faena.cliente_minero ? ` · ${faena.cliente_minero}` : ''}</Text>
            <Text>Período: {fecha(desde)} al {fecha(hasta)}</Text>
            <Text>Emitido: {fecha(emitido)}</Text>
          </View>
        </View>

        <Text style={S.h2}>1. RESUMEN EJECUTIVO</Text>
        <View style={S.kpis}>
          <View style={S.kpi}><Text style={S.kpiLbl}>Cumplimiento contractual</Text><Text style={S.kpiVal}>{pct(r.pctCumplimiento)}</Text><Text style={S.kpiSub}>{r.cumplidos} de {r.programados} con firma mandante · {r.tramo.etiqueta}</Text></View>
          <View style={S.kpi}><Text style={S.kpiLbl}>Ejecución en terreno</Text><Text style={S.kpiVal}>{pct(r.pctEjecucion)}</Text><Text style={S.kpiSub}>{r.ejecutados} ejecutados · {r.sinFirma} sin firma</Text></View>
          <View style={S.kpi}><Text style={S.kpiLbl}>Actividades registradas</Text><Text style={S.kpiVal}>{r.actividades}</Text><Text style={S.kpiSub}>{r.informesPdf} informes PDF · {r.horasTerreno.toLocaleString('es-CL')} h con cronómetro</Text></View>
          <View style={S.kpi}><Text style={S.kpiLbl}>Hallazgos / requerimientos</Text><Text style={S.kpiVal}>{r.hallazgos} / {r.requerimientos}</Text><Text style={S.kpiSub}>{r.requerimientosAlta} de prioridad alta · {r.reprogramaciones} reprogramaciones</Text></View>
        </View>
        <Text style={S.parrafo}>{inf.conclusion}</Text>
        {comentarios.trim() !== '' && (
          <View style={{ marginTop: 6 }}>
            <Text style={{ fontFamily: 'Helvetica-Bold', fontSize: 8.5, marginBottom: 2 }}>Comentarios del administrador de contrato</Text>
            <Text style={S.parrafo}>{comentarios.trim()}</Text>
          </View>
        )}

        <Text style={S.h2}>2. CUMPLIMIENTO POR MES</Text>
        <Tabla vacio="Sin servicios programados."
          cols={[{ t: 'Mes', w: '28%' }, { t: 'Programados', w: '18%', align: 'right' }, { t: 'Ejecutados', w: '18%', align: 'right' }, { t: 'Cumplidos (firma)', w: '18%', align: 'right' }, { t: 'KPI', w: '18%', align: 'right' }]}
          filas={inf.porMes.map((m) => [`${MESES[m.mes - 1]} ${m.anio}`, String(m.programados), String(m.ejecutados), String(m.cumplidos), pct(m.pct)])} />

        <Text style={S.h2}>3. DETALLE POR PUNTO</Text>
        <Tabla vacio="Sin puntos en el período."
          cols={[{ t: 'Punto', w: '24%' }, { t: 'Prog.', w: '7%', align: 'center' }, { t: 'Ejec.', w: '7%', align: 'center' }, { t: 'Firma', w: '7%', align: 'center' }, { t: 'Fechas ejecución', w: '19%' }, { t: 'Actividades', w: '9%', align: 'center' }, { t: 'NO OK', w: '7%', align: 'center' }, { t: 'Req.', w: '6%', align: 'center' }, { t: 'Técnico(s)', w: '14%' }]}
          filas={inf.puntos.map((p) => [
            p.area && !p.instalacion.startsWith(p.area) ? `${p.area} · ${p.instalacion}` : p.instalacion,
            String(p.programados), String(p.ejecutados), String(p.cumplidos), p.fechas.map(fecha).join(', ') || '—',
            String(p.actividades), String(p.hallazgos), String(p.requerimientos), p.tecnicos.join(' / ') || '—',
          ])} />

        {inf.pautaLugar ? (
          <View>
            <Text style={S.h2}>4. AVANCE DE LA PAUTA TRIMESTRAL POR LUGAR</Text>
            <Tabla vacio=""
              cols={[{ t: 'Área', w: '28%' }, { t: 'Actividades', w: '12%', align: 'right' }, { t: 'Ejecutadas', w: '12%', align: 'right' }, { t: 'n/a', w: '8%', align: 'right' }, { t: 'Atrasadas', w: '12%', align: 'right' }, { t: '% real', w: '14%', align: 'right' }, { t: '% proyectado', w: '14%', align: 'right' }]}
              filas={[...inf.pautaLugar.areas, inf.pautaLugar.total].map((a) => [a.area === 'Total' ? 'Total faena' : a.area, String(a.total), String(a.ejecutadas), String(a.noAplica), String(a.atrasadas), pct(a.pctReal), pct(a.pctProyectado)])} />
            {inf.pautaLugar.faltantes.length > 0 && (
              <View style={{ marginTop: 4 }}>
                <Tabla vacio="" cols={[{ t: 'Área', w: '16%' }, { t: 'Lugar', w: '26%' }, { t: 'Cód.', w: '7%' }, { t: 'Actividad sin ejecutar en el trimestre', w: '35%' }, { t: 'Estado', w: '16%' }]}
                       filas={inf.pautaLugar.faltantes.map((x) => [x.area.replace('Truck Shop ', ''), x.lugar, x.codigo, x.descripcion, `${x.estado}${x.fecha ? ` ${fecha(x.fecha)}` : ''}`])} />
              </View>
            )}
            {inf.pautaLugar.sinInforme.length > 0 && (
              <Text style={[S.parrafo, { marginTop: 4, color: '#92400e' }]}>
                {inf.pautaLugar.sinInforme.length} actividades figuran ejecutadas en la planilla sin informe de terreno en SICOM que las respalde: {inf.pautaLugar.sinInforme.map((x) => `${x.area.replace('Truck Shop ', '')} ${x.codigo}`).join(', ')}.
              </Text>
            )}
          </View>
        ) : (<View>
        <Text style={S.h2}>4. COBERTURA DE LA PAUTA TRIMESTRAL</Text>
        {inf.cobertura.length === 0 ? <Text style={S.vacio}>Sin ejecuciones con pauta en el período.</Text> : inf.cobertura.map((c) => (
          <View key={c.pauta_id} style={{ marginBottom: 4 }}>
            <Text style={S.parrafo}>
              {c.hechas} de {c.trimestrales - c.noAplica} actividades trimestrales aplicables registradas al menos una vez ({pct(c.pct)}){c.noAplica ? ` · ${c.noAplica} marcadas «no aplica»` : ''}.
            </Text>
            {c.pendientes.length > 0 && (
              <View style={{ marginTop: 3 }}>
                <Tabla vacio="" cols={[{ t: 'Código', w: '14%' }, { t: 'Actividad trimestral sin registro en el período', w: '86%' }]}
                       filas={c.pendientes.map((x) => [x.codigo ?? '—', x.descripcion])} />
              </View>
            )}
          </View>
        ))}

        </View>)}

        <Text style={S.h2}>5. HALLAZGOS (NO OK / FUERA DE TOLERANCIA)</Text>
        <Tabla vacio="Sin hallazgos en el período."
          cols={[{ t: 'Fecha', w: '11%' }, { t: 'Punto', w: '20%' }, { t: 'Cód.', w: '7%' }, { t: 'Actividad', w: '30%' }, { t: 'Observación', w: '32%' }]}
          filas={inf.hallazgos.map((h) => [fecha(h.fecha), h.instalacion, h.codigo ?? '—', h.descripcion ?? '—', [h.observacion, h.medicion ? `Medición: ${h.medicion}` : null].filter(Boolean).join(' · ') || '—'])} />

        <Text style={S.h2}>6. REQUERIMIENTOS Y COMENTARIOS AL MANDANTE</Text>
        <Tabla vacio="Sin requerimientos ni comentarios en el período."
          cols={[{ t: 'Fecha', w: '11%' }, { t: 'Punto', w: '18%' }, { t: 'Tipo', w: '12%' }, { t: 'Prioridad', w: '9%' }, { t: 'Detalle', w: '40%' }, { t: 'Plazo', w: '10%' }]}
          filas={inf.requerimientos.map((q) => [
            fecha(q.fecha), q.instalacion, REQ_TIPO_LABEL[q.tipo] ?? q.tipo, REQ_PRIORIDAD_LABEL[q.prioridad] ?? q.prioridad,
            [q.titulo, q.descripcion, q.item_codigo ? `(ítem ${q.item_codigo})` : null].filter(Boolean).join(' — '), fecha(q.plazo),
          ])} />

        <Text style={S.h2}>7. REPROGRAMACIONES</Text>
        <Tabla vacio="Sin reprogramaciones en el período."
          cols={[{ t: 'Punto', w: '24%' }, { t: 'Fecha original', w: '13%' }, { t: 'Nueva fecha', w: '13%' }, { t: 'Causa', w: '20%' }, { t: 'Motivo', w: '30%' }]}
          filas={inf.reprogramaciones.map((x) => [x.instalacion ?? x.patente ?? '—', fecha(x.fecha_original), fecha(x.nueva_fecha), REPROG_CAUSA[x.causa ?? ''] ?? x.causa ?? '—', x.descripcion ?? '—'])} />

        <Text style={S.h2}>ANEXO · INFORMES DE SERVICIO DEL PERÍODO</Text>
        <Tabla vacio="Sin informes PDF generados."
          cols={[{ t: 'Fecha', w: '13%' }, { t: 'Punto', w: '37%' }, { t: 'Servicio', w: '15%' }, { t: 'Documento', w: '35%' }]}
          filas={inf.puntos.flatMap((p) => p.informes.map((i) => [
            fecha(i.fecha), p.instalacion, i.tipo === 'calibracion' ? 'Calibración' : 'Mantención',
            <Link key={i.url} src={i.url} style={S.link}>Abrir informe PDF</Link>,
          ]))} />

        <View style={S.firmas} wrap={false}>
          <View style={S.firma}><Text>{elaboradoPor || 'Elaborado por'}</Text><Text style={{ color: '#6b7280' }}>Pillado y Cía · Administrador de contrato</Text></View>
          <View style={S.firma}><Text>Revisado por</Text><Text style={{ color: '#6b7280' }}>ESM / ENEX</Text></View>
        </View>

        <View style={S.footer} fixed>
          <Text>Informe trimestral generado por SICOM-ICEO desde los informes de servicio registrados</Text>
          <Text render={({ pageNumber, totalPages }) => `Página ${pageNumber} de ${totalPages}`} />
        </View>
      </Page>
    </Document>
  )
}

export async function descargarInformeTrimestral(p: Omit<Props, 'logoUrl'>) {
  const logoUrl = await aDataUrl(`${window.location.origin}/images/logo_empresa_2.png`)
  const blob = await Promise.race([
    pdf(<InformeTrimestralDoc {...p} logoUrl={logoUrl} />).toBlob(),
    new Promise<Blob>((_, reject) => setTimeout(() => reject(new Error('Timeout generando PDF')), 20000)),
  ])
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `Informe_Trimestral_${p.faena.codigo}_${p.desde}_a_${p.hasta}.pdf`
  a.click()
  URL.revokeObjectURL(a.href)
}
