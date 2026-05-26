import { Document, Page, View, Text, StyleSheet, pdf } from '@react-pdf/renderer'

export interface ReporteFlotaData {
  fecha: string | null
  total: number
  por_estado: Record<string, number> | null
  por_operacion: Record<string, number> | null
  por_cliente: Array<{ cliente: string; equipos: number }> | null
  disponibilidad: number | null
  utilizacion: number | null
  equipos?: Array<{
    patente: string | null
    equipamiento: string | null
    estado: string | null
    dias_arrendado: number
    ultimo_cliente: string | null
    dias_sin_arriendo: number | null
  }> | null
}

const LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta', U: 'Uso interno', L: 'Leasing',
}
const ORDEN = ['A', 'C', 'L', 'U', 'D', 'M', 'T', 'F', 'H', 'R', 'V']
const COLOR: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  M: '#F59E0B', T: '#FB923C', F: '#DC2626', H: '#A855F7', R: '#06B6D4', V: '#9333EA',
}

const s = StyleSheet.create({
  page: { padding: 36, fontSize: 10, color: '#1f2937', fontFamily: 'Helvetica' },
  h1: { fontSize: 18, fontWeight: 'bold', color: '#0b2a4a' },
  sub: { fontSize: 10, color: '#6b7280', marginTop: 2, marginBottom: 14 },
  kpiRow: { flexDirection: 'row', gap: 10, marginBottom: 16 },
  kpi: { flex: 1, border: '1 solid #e5e7eb', borderRadius: 6, padding: 10 },
  kpiN: { fontSize: 20, fontWeight: 'bold', color: '#0b2a4a' },
  kpiL: { fontSize: 8, color: '#6b7280', marginTop: 2 },
  h2: { fontSize: 12, fontWeight: 'bold', color: '#0b2a4a', marginTop: 10, marginBottom: 6, borderBottom: '1 solid #e5e7eb', paddingBottom: 3 },
  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 3, borderBottom: '0.5 solid #f3f4f6' },
  cell: { fontSize: 10 },
  bold: { fontWeight: 'bold' },
  barRow: { flexDirection: 'row', alignItems: 'center', marginVertical: 2 },
  barLabel: { width: 110, fontSize: 9 },
  barTrack: { flex: 1, height: 9, backgroundColor: '#f3f4f6', borderRadius: 2, marginHorizontal: 6 },
  barFill: { height: 9, borderRadius: 2 },
  barN: { width: 22, fontSize: 9, textAlign: 'right', fontWeight: 'bold' },
  th: { flexDirection: 'row', backgroundColor: '#f3f4f6', paddingVertical: 4, paddingHorizontal: 4, borderBottom: '1 solid #e5e7eb' },
  tr: { flexDirection: 'row', paddingVertical: 2.5, paddingHorizontal: 4, borderBottom: '0.5 solid #f3f4f6' },
  thc: { fontSize: 8, fontWeight: 'bold', color: '#374151' },
  tc: { fontSize: 8, color: '#1f2937' },
  cPat: { width: '16%' }, cEq: { width: '34%' }, cEst: { width: '14%' }, cDias: { width: '10%', textAlign: 'right' }, cCli: { width: '26%' },
  footer: { position: 'absolute', bottom: 24, left: 36, right: 36, fontSize: 8, color: '#9ca3af', borderTop: '1 solid #e5e7eb', paddingTop: 6, flexDirection: 'row', justifyContent: 'space-between' },
})

function ReporteFlotaPDF({ data }: { data: ReporteFlotaData }) {
  const est = data.por_estado ?? {}
  const oper = data.por_operacion ?? {}
  return (
    <Document>
      <Page size="A4" style={s.page}>
        <Text style={s.h1}>Reporte de Flota — Pillado</Text>
        <Text style={s.sub}>Estado real de la flota al {data.fecha ?? '—'} · SICOM-ICEO</Text>

        <View style={s.kpiRow}>
          <View style={s.kpi}><Text style={s.kpiN}>{data.total}</Text><Text style={s.kpiL}>Equipos de flota</Text></View>
          <View style={s.kpi}><Text style={s.kpiN}>{data.disponibilidad ?? '—'}%</Text><Text style={s.kpiL}>Disponibilidad física (mes)</Text></View>
          <View style={s.kpi}><Text style={s.kpiN}>{data.utilizacion ?? '—'}%</Text><Text style={s.kpiL}>Utilización bruta (mes)</Text></View>
        </View>

        <Text style={s.h2}>Distribución por estado</Text>
        {ORDEN.filter((e) => est[e]).map((e) => (
          <View key={e} style={s.barRow}>
            <Text style={s.barLabel}>{LABEL[e]}</Text>
            <View style={s.barTrack}>
              <View style={[s.barFill, { width: `${data.total > 0 ? Math.round((est[e] / data.total) * 100) : 0}%`, backgroundColor: COLOR[e] ?? '#9ca3af' }]} />
            </View>
            <Text style={s.barN}>{est[e]}</Text>
          </View>
        ))}

        <Text style={s.h2}>Por operación</Text>
        {Object.entries(oper).map(([k, v]) => (
          <View key={k} style={s.row}><Text style={s.cell}>{k}</Text><Text style={[s.cell, s.bold]}>{v}</Text></View>
        ))}

        <Text style={s.h2}>Por cliente</Text>
        {(data.por_cliente ?? []).map((c) => (
          <View key={c.cliente} style={s.row}><Text style={s.cell}>{c.cliente}</Text><Text style={[s.cell, s.bold]}>{c.equipos}</Text></View>
        ))}

        <View style={s.footer} fixed>
          <Text>Pillado · SICOM-ICEO</Text>
          <Text>Generado {new Date().toLocaleDateString('es-CL')}</Text>
        </View>
      </Page>

      {data.equipos && data.equipos.length > 0 && (
        <Page size="A4" style={s.page}>
          <Text style={s.h1}>Días arrendado por equipo</Text>
          <Text style={s.sub}>Días en arriendo/contrato en el año · último cliente arrendado</Text>

          <View style={s.th}>
            <Text style={[s.thc, s.cPat]}>Patente</Text>
            <Text style={[s.thc, s.cEq]}>Equipo</Text>
            <Text style={[s.thc, s.cEst]}>Estado</Text>
            <Text style={[s.thc, s.cDias]}>Días</Text>
            <Text style={[s.thc, s.cCli]}>Último cliente</Text>
          </View>
          {data.equipos.map((e, i) => (
            <View key={(e.patente ?? '') + i} style={s.tr} wrap={false}>
              <Text style={[s.tc, s.cPat]}>{e.patente ?? '—'}</Text>
              <Text style={[s.tc, s.cEq]}>{e.equipamiento ?? '—'}</Text>
              <Text style={[s.tc, s.cEst]}>{e.estado ? LABEL[e.estado] ?? e.estado : '—'}</Text>
              <Text style={[s.tc, s.cDias]}>{e.dias_arrendado}</Text>
              <Text style={[s.tc, s.cCli]}>{e.ultimo_cliente ?? 'Sin contrato'}</Text>
            </View>
          ))}

          <View style={s.footer} fixed>
            <Text>Pillado · SICOM-ICEO</Text>
            <Text>Generado {new Date().toLocaleDateString('es-CL')}</Text>
          </View>
        </Page>
      )}
    </Document>
  )
}

export async function generarReporteFlotaPDF(data: ReporteFlotaData): Promise<Blob> {
  return await pdf(<ReporteFlotaPDF data={data} />).toBlob()
}
