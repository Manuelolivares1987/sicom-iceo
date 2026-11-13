'use client'

// ============================================================================
// Informe PDF — Inspección de terreno APR (MIG685)
// ----------------------------------------------------------------------------
// Lo que se archiva y se muestra al mandante: resultado, cuadrilla con su
// estado documental del DÍA de la inspección, encuesta de fatiga, cada punto
// por etapa con su foto, y las desviaciones con responsable y plazo.
// ============================================================================

import { Document, Image, Page, StyleSheet, Text, View, pdf } from '@react-pdf/renderer'
import {
  ESTADO_LABEL, ESTADO_REQ_LABEL, RESULTADO_LABEL, getInspeccionDetalle, urlEvidencia,
  type InspeccionDetalle,
} from '@/lib/services/prevencion-inspeccion'

const S = StyleSheet.create({
  page: { padding: 28, paddingBottom: 40, fontSize: 8.5, fontFamily: 'Helvetica', color: '#111827' },
  head: { flexDirection: 'row', borderWidth: 1, borderColor: '#111', marginBottom: 8 },
  logoBox: { width: 120, padding: 6, borderRightWidth: 1, borderRightColor: '#111', justifyContent: 'center' },
  logo: { width: 105, height: 40, objectFit: 'contain' },
  titleBox: { flex: 1, padding: 6, justifyContent: 'center' },
  title: { fontSize: 12, fontFamily: 'Helvetica-Bold', textAlign: 'center' },
  subtitle: { fontSize: 8, textAlign: 'center', marginTop: 2, color: '#374151' },
  metaBox: { width: 120, borderLeftWidth: 1, borderLeftColor: '#111', justifyContent: 'center', padding: 4 },
  meta: { fontSize: 7, marginBottom: 1 },
  sec: { backgroundColor: '#1f2937', color: '#fff', fontFamily: 'Helvetica-Bold', fontSize: 8.5, padding: 3, marginTop: 8 },
  row: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#6b7280' },
  lbl: { width: '26%', padding: 3, color: '#374151', borderRightWidth: 0.5, borderRightColor: '#6b7280' },
  val: { flex: 1, padding: 3, fontFamily: 'Helvetica-Bold' },
  kpis: { flexDirection: 'row', marginTop: 6 },
  kpi: { flex: 1, borderWidth: 0.5, borderColor: '#6b7280', padding: 4, marginRight: 3, alignItems: 'center' },
  kpiN: { fontSize: 14, fontFamily: 'Helvetica-Bold' },
  kpiL: { fontSize: 6.5, color: '#4b5563' },
  th: { padding: 3, fontFamily: 'Helvetica-Bold', backgroundColor: '#f3f4f6', borderRightWidth: 0.5, borderRightColor: '#6b7280' },
  td: { padding: 3, borderRightWidth: 0.5, borderRightColor: '#6b7280' },
  etapa: { backgroundColor: '#e5e7eb', fontFamily: 'Helvetica-Bold', padding: 3, marginTop: 6, borderWidth: 0.5, borderColor: '#6b7280' },
  punto: { borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#6b7280', padding: 4 },
  puntoTop: { flexDirection: 'row' },
  cod: { width: 22, fontFamily: 'Helvetica-Bold' },
  preg: { flex: 1 },
  resp: { width: 62, textAlign: 'center', fontFamily: 'Helvetica-Bold', fontSize: 7.5, padding: 2, borderRadius: 2 },
  obs: { marginLeft: 22, marginTop: 2, color: '#374151', fontSize: 7.5 },
  fotos: { flexDirection: 'row', flexWrap: 'wrap', marginLeft: 22, marginTop: 3 },
  foto: { width: 120, height: 90, objectFit: 'cover', marginRight: 4, marginBottom: 4, borderWidth: 0.5, borderColor: '#9ca3af' },
  firmas: { flexDirection: 'row', marginTop: 30 },
  firma: { flex: 1, alignItems: 'center', marginHorizontal: 10 },
  linea: { borderTopWidth: 1, borderTopColor: '#111', width: '100%', paddingTop: 3, alignItems: 'center' },
  footer: { position: 'absolute', bottom: 16, left: 28, right: 28, fontSize: 6.5, color: '#9ca3af', flexDirection: 'row', justifyContent: 'space-between' },
})

const COLOR_RESP: Record<string, { bg: string, fg: string, t: string }> = {
  cumple: { bg: '#d1fae5', fg: '#065f46', t: 'CUMPLE' },
  no_cumple: { bg: '#fee2e2', fg: '#991b1b', t: 'NO CUMPLE' },
  no_aplica: { bg: '#f3f4f6', fg: '#374151', t: 'NO APLICA' },
  pendiente: { bg: '#fef3c7', fg: '#92400e', t: 'PENDIENTE' },
}
const COLOR_RESULTADO: Record<string, string> = { conforme: '#047857', con_desviaciones: '#b45309', critico: '#b91c1c' }

const fmtFecha = (s: string | null) =>
  s ? new Date(s.length === 10 ? s + 'T12:00:00' : s).toLocaleDateString('es-CL', { day: '2-digit', month: '2-digit', year: 'numeric' }) : '—'

function InformeDoc({ d, faena, logo, fotos }: {
  d: InspeccionDetalle, faena: string, logo: string | null, fotos: Map<string, string>
}) {
  const etapas: { nombre: string, items: InspeccionDetalle['items'] }[] = []
  const orden = [...d.items].sort((a, b) => a.item_codigo.localeCompare(b.item_codigo))
  // Respeta el orden de la plantilla: T, A, D, E, J, C, F, R.
  const ORDEN = ['T', 'A', 'D', 'E', 'J', 'C', 'F', 'R']
  orden.sort((a, b) => ORDEN.indexOf(a.item_codigo[0]) - ORDEN.indexOf(b.item_codigo[0]) || a.item_codigo.localeCompare(b.item_codigo))
  for (const it of orden) {
    let e = etapas.find((x) => x.nombre === it.etapa)
    if (!e) { e = { nombre: it.etapa, items: [] }; etapas.push(e) }
    e.items.push(it)
  }
  const abiertas = d.desviaciones.filter((x) => x.estado === 'abierta').length

  return (
    <Document title={`Inspección APR ${d.fecha} ${faena}`} author="SICOM — Pillado Empresas">
      <Page size="LETTER" style={S.page} wrap>
        <View style={S.head} fixed>
          <View style={S.logoBox}>{logo ? <Image src={logo} style={S.logo} /> : <Text>PILLADO</Text>}</View>
          <View style={S.titleBox}>
            <Text style={S.title}>INSPECCIÓN DE TERRENO — PREVENCIÓN DE RIESGOS</Text>
            <Text style={S.subtitle}>Verificación de controles antes, durante y al término del trabajo</Text>
          </View>
          <View style={S.metaBox}>
            <Text style={S.meta}>Fecha: {fmtFecha(d.fecha)}{d.hora_inicio ? ` ${d.hora_inicio.slice(0, 5)}` : ''}</Text>
            <Text style={S.meta}>Estado: {ESTADO_LABEL[d.estado]}</Text>
            <Text style={S.meta}>Folio: {d.id.slice(0, 8).toUpperCase()}</Text>
          </View>
        </View>

        <Text style={S.sec}>1. ANTECEDENTES</Text>
        {[
          ['Faena', faena],
          ['Instalación / área', [d.instalacion, d.area_sector].filter(Boolean).join(' · ') || '—'],
          ['Trabajo inspeccionado', d.trabajo],
          ['Supervisor a cargo', d.supervisor ?? '—'],
          ['Inspector (APR)', d.inspector_nombre ?? '—'],
          ['Trabajos cruzados', d.trabajo_cruzado ? `Sí — ${d.empresas_cruzadas ?? ''}` : 'No'],
        ].map(([l, v]) => (
          <View key={l} style={S.row}><Text style={S.lbl}>{l}</Text><Text style={S.val}>{v}</Text></View>
        ))}

        <View style={S.kpis}>
          <View style={[S.kpi, { borderColor: COLOR_RESULTADO[d.resultado], borderWidth: 1.5 }]}>
            <Text style={[S.kpiN, { color: COLOR_RESULTADO[d.resultado], fontSize: 11 }]}>{RESULTADO_LABEL[d.resultado].toUpperCase()}</Text>
            <Text style={S.kpiL}>Resultado</Text>
          </View>
          <View style={S.kpi}><Text style={S.kpiN}>{d.pct_cumplimiento == null ? '—' : `${d.pct_cumplimiento}%`}</Text><Text style={S.kpiL}>Cumplimiento</Text></View>
          <View style={S.kpi}><Text style={[S.kpiN, { color: '#047857' }]}>{d.items_cumple}</Text><Text style={S.kpiL}>Cumple</Text></View>
          <View style={S.kpi}><Text style={[S.kpiN, { color: '#b91c1c' }]}>{d.items_no_cumple}</Text><Text style={S.kpiL}>No cumple</Text></View>
          <View style={S.kpi}><Text style={S.kpiN}>{d.items_no_aplica}</Text><Text style={S.kpiL}>No aplica</Text></View>
          <View style={[S.kpi, { marginRight: 0 }]}><Text style={[S.kpiN, { color: d.personas_no_habilitadas ? '#b91c1c' : '#111' }]}>{d.personas_no_habilitadas}</Text><Text style={S.kpiL}>No habilitados</Text></View>
        </View>

        <Text style={S.sec}>2. CUADRILLA — ESTADO DOCUMENTAL Y FATIGA (al día de la inspección)</Text>
        <View style={[S.row, { borderTopWidth: 0.5 }]}>
          <Text style={[S.th, { width: '24%' }]}>Trabajador</Text>
          <Text style={[S.th, { width: '12%' }]}>Función</Text>
          <Text style={[S.th, { width: '14%' }]}>Habilitación</Text>
          <Text style={[S.th, { flex: 1, borderRightWidth: 0 }]}>Observaciones</Text>
        </View>
        {d.personas.map((p) => {
          const fallas = p.requisitos.filter((r) => !r.ok).map((r) => `${r.nombre}: ${ESTADO_REQ_LABEL[r.estado] ?? r.estado}`)
          const fat = p.es_conductor
            ? `Fatiga: ${p.fatiga_resultado === 'apto' ? 'APTO' : p.fatiga_resultado === 'apto_observacion' ? 'APTO c/obs.' : 'NO APTO'}${p.fatiga_motivos?.length ? ` (${p.fatiga_motivos.join('; ')})` : ''}`
            : ''
          return (
            <View key={p.id} style={S.row} wrap={false}>
              <Text style={[S.td, { width: '24%' }]}>{p.nombre}{p.rut && !p.rut.startsWith('PEND') ? `\n${p.rut}` : ''}</Text>
              <Text style={[S.td, { width: '12%' }]}>{p.es_conductor ? 'Conductor' : 'Ejecutante'}</Text>
              <Text style={[S.td, { width: '14%', fontFamily: 'Helvetica-Bold', color: p.habilitado ? '#047857' : '#b91c1c' }]}>
                {p.habilitado ? 'HABILITADO' : 'NO HABILITADO'}
              </Text>
              <Text style={[S.td, { flex: 1, borderRightWidth: 0 }]}>
                {[fallas.join(' · '), fat].filter(Boolean).join('\n') || 'Documentación al día'}
              </Text>
            </View>
          )
        })}

        <Text style={S.sec}>3. VERIFICACIÓN POR ETAPA</Text>
        {etapas.map((e) => (
          <View key={e.nombre}>
            <Text style={S.etapa} minPresenceAhead={40}>{e.nombre}</Text>
            {e.items.map((it) => {
              const c = COLOR_RESP[it.respuesta ?? 'pendiente']
              return (
                <View key={it.id} style={S.punto} wrap={false}>
                  <View style={S.puntoTop}>
                    <Text style={S.cod}>{it.item_codigo}</Text>
                    <Text style={S.preg}>{it.pregunta}</Text>
                    <Text style={[S.resp, { backgroundColor: c.bg, color: c.fg }]}>{c.t}</Text>
                  </View>
                  {it.automatico && it.evidencia_tipo !== 'foto' && (
                    <Text style={S.obs}>
                      {it.evidencia_tipo === 'documental' ? 'Verificado contra el control documental.'
                        : it.evidencia_tipo === 'fatiga' ? 'Según encuesta de fatiga y somnolencia de los conductores.'
                        : 'No hubo trabajos cruzados.'}
                    </Text>
                  )}
                  {it.observacion && <Text style={S.obs}>Obs.: {it.observacion}</Text>}
                  {it.evidencias.length > 0 && (
                    <View style={S.fotos}>
                      {it.evidencias.map((ev) => fotos.get(ev.path)
                        ? <Image key={ev.path} src={fotos.get(ev.path)!} style={S.foto} />
                        : null)}
                    </View>
                  )}
                </View>
              )
            })}
          </View>
        ))}

        <Text style={S.sec}>4. DESVIACIONES ({d.desviaciones.length} · {abiertas} abiertas)</Text>
        {d.desviaciones.length === 0 ? (
          <View style={[S.row, { borderTopWidth: 0.5 }]}><Text style={S.td}>Sin desviaciones.</Text></View>
        ) : (
          <>
            <View style={[S.row, { borderTopWidth: 0.5 }]}>
              <Text style={[S.th, { width: '6%' }]}>Pto.</Text>
              <Text style={[S.th, { width: '9%' }]}>Criticidad</Text>
              <Text style={[S.th, { flex: 1 }]}>Desviación / acción</Text>
              <Text style={[S.th, { width: '16%' }]}>Responsable</Text>
              <Text style={[S.th, { width: '11%' }]}>Plazo</Text>
              <Text style={[S.th, { width: '10%', borderRightWidth: 0 }]}>Estado</Text>
            </View>
            {d.desviaciones.map((x) => (
              <View key={x.id} style={S.row} wrap={false}>
                <Text style={[S.td, { width: '6%' }]}>{x.item_codigo ?? '—'}</Text>
                <Text style={[S.td, { width: '9%', color: x.criticidad === 'alta' ? '#b91c1c' : '#111' }]}>{x.criticidad.toUpperCase()}</Text>
                <Text style={[S.td, { flex: 1 }]}>{x.descripcion}{x.accion ? `\nAcción: ${x.accion}` : ''}{x.cierre_observacion ? `\nCierre: ${x.cierre_observacion}` : ''}</Text>
                <Text style={[S.td, { width: '16%' }]}>{x.responsable ?? '—'}</Text>
                <Text style={[S.td, { width: '11%' }]}>{fmtFecha(x.fecha_compromiso)}</Text>
                <Text style={[S.td, { width: '10%', borderRightWidth: 0, fontFamily: 'Helvetica-Bold' }]}>{x.estado === 'abierta' ? 'ABIERTA' : 'CERRADA'}</Text>
              </View>
            ))}
          </>
        )}

        {d.observacion && (
          <>
            <Text style={S.sec}>5. OBSERVACIÓN GENERAL</Text>
            <View style={[S.row, { borderTopWidth: 0.5 }]}><Text style={S.td}>{d.observacion}</Text></View>
          </>
        )}

        <View style={S.firmas} wrap={false}>
          {[['Inspector (APR)', d.inspector_nombre ?? ''], ['Supervisor a cargo', d.supervisor ?? ''], ['Administrador de contrato', '']].map(([c, n]) => (
            <View key={c} style={S.firma}>
              <View style={S.linea}>
                <Text style={{ fontFamily: 'Helvetica-Bold' }}>{n || ' '}</Text>
                <Text style={{ fontSize: 7, color: '#4b5563' }}>{c}</Text>
              </View>
            </View>
          ))}
        </View>

        <View style={S.footer} fixed>
          <Text>SICOM · Pillado Empresas · Inspección de terreno APR</Text>
          <Text render={({ pageNumber, totalPages }) => `Página ${pageNumber} de ${totalPages}`} />
        </View>
      </Page>
    </Document>
  )
}

async function aDataUrl(url: string): Promise<string | null> {
  try {
    const r = await fetch(url)
    if (!r.ok) return null
    const blob = await r.blob()
    return await new Promise((res) => {
      const fr = new FileReader()
      fr.onload = () => res(fr.result as string)
      fr.onerror = () => res(null)
      fr.readAsDataURL(blob)
    })
  } catch { return null }
}

/** Arma el PDF de la inspección y lo descarga. */
export async function descargarPdfInspeccion(id: string, faenaNombre: string) {
  const d = await getInspeccionDetalle(id)
  const logo = await aDataUrl(`${window.location.origin}/images/logo_pillado_empresas.png`)
  const fotos = new Map<string, string>()
  const paths = d.items.flatMap((i) => i.evidencias.map((e) => e.path))
  await Promise.all(paths.map(async (p) => {
    const u = await urlEvidencia(p)
    const data = u ? await aDataUrl(u) : null
    if (data) fotos.set(p, data)
  }))
  const blob = await pdf(<InformeDoc d={d} faena={faenaNombre} logo={logo} fotos={fotos} />).toBlob()
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `Inspeccion_APR_${d.fecha}_${faenaNombre.replace(/[^A-Za-z0-9]+/g, '_')}.pdf`
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
}
