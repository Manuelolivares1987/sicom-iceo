'use client'

// ============================================================================
// Informe de Gestión GRP Mensual — CMP Romeral (PDF, MIG547)
// ----------------------------------------------------------------------------
// Replica la lámina «GESTIÓN MENSUAL EMPRESAS COLABORADORAS» del formato GRP
// de CMP: indicadores de seguridad, gestión VCT (con abiertos/cerrados),
// gestión GRP (VAT/RIT), emergencia, CPHS, gestión SSO, campañas y fotos.
// Todo sale de lo que cargaron los supervisores + los indicadores del mes.
// ============================================================================

import { Document, Page, Text, View, StyleSheet, Image, pdf } from '@react-pdf/renderer'
import type {
  FaenaConfigDatos, GestionMensualFila, IndicadoresFila, PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'
import { urlEvidencia } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

const AZUL = '#1f4e78'

const S = StyleSheet.create({
  page: { padding: 20, fontSize: 8, fontFamily: 'Helvetica', color: '#111827' },
  titulo: {
    backgroundColor: AZUL, color: '#ffffff', fontSize: 12, fontWeight: 'bold',
    padding: 6, textAlign: 'center', marginBottom: 2,
  },
  subtitulo: { fontSize: 8, textAlign: 'center', color: '#4b5563', marginBottom: 8 },
  fila: { flexDirection: 'row', gap: 6 },
  caja: { flex: 1, borderWidth: 0.5, borderColor: '#9ca3af', marginBottom: 6 },
  cajaTitulo: {
    backgroundColor: AZUL, color: '#ffffff', fontWeight: 'bold', fontSize: 8,
    padding: 3, textAlign: 'center',
  },
  tr: { flexDirection: 'row', borderBottomWidth: 0.5, borderBottomColor: '#d1d5db' },
  th: { flex: 1, padding: 2.5, fontWeight: 'bold', backgroundColor: '#f3f4f6', fontSize: 7, textAlign: 'center' },
  td: { flex: 1, padding: 2.5, fontSize: 7.5, textAlign: 'center' },
  tdIzq: { flex: 2, padding: 2.5, fontSize: 7.5 },
  kpiLabel: { flex: 2, padding: 3, fontSize: 7.5, backgroundColor: '#f3f4f6' },
  kpiValor: { flex: 1, padding: 3, fontSize: 8, fontWeight: 'bold', textAlign: 'center' },
  foto: { width: 118, height: 88, objectFit: 'cover', margin: 3, borderWidth: 0.5, borderColor: '#9ca3af' },
  fotoCaption: { fontSize: 6.5, color: '#4b5563', width: 118, marginLeft: 3 },
  footer: { position: 'absolute', bottom: 12, left: 20, right: 20, fontSize: 6.5, color: '#9ca3af', textAlign: 'center' },
})

type FotoEmbebida = { url: string; caption: string }

function DocInforme({ config, indicadores, gestion, fotos, anio, mes, faenaNombre }: {
  config: FaenaConfigDatos
  indicadores: IndicadoresFila | null
  gestion: GestionMensualFila[]
  fotos: FotoEmbebida[]
  anio: number
  mes: number
  faenaNombre: string
}) {
  const g = (codigo: string) => gestion.find((x) => x.tipo_codigo === codigo)
  const vct = g('VCT'); const vat = g('VAT'); const rit = g('RIT')
  const simulacros = g('SIMULACRO'); const campanas = g('CAMPANA')
  const pct = (x?: GestionMensualFila) =>
    !x ? '—' : x.pct_cumplimiento === null ? (x.realizados > 0 ? 'extra' : '—') : `${x.pct_cumplimiento}%`

  return (
    <Document>
      <Page size="A4" orientation="landscape" style={S.page}>
        <Text style={S.titulo}>GESTIÓN GRP MENSUAL — EMPRESAS COLABORADORAS</Text>
        <Text style={S.subtitulo}>
          {(config.empresa as any)?.razon_social ?? 'Pillado y Cía. Ltda.'} · Faena {faenaNombre} ·{' '}
          {MESES[mes - 1]} {anio} · Elaborado: {(config.experto as any)?.nombre ?? ''}
        </Text>

        <View style={S.fila}>
          {/* Indicadores de seguridad */}
          <View style={[S.caja, { flex: 1 }]}>
            <Text style={S.cajaTitulo}>INDICADORES DE SEGURIDAD</Text>
            {[
              ['Dotación', indicadores?.dotacion_total],
              ['HH', indicadores?.hh_total],
              ['Accidente CTP', indicadores?.accidentes_ctp],
              ['Días perdidos', indicadores?.dias_perdidos],
              ['Índice de frecuencia', indicadores?.indice_frecuencia],
              ['Índice de gravedad', indicadores?.indice_gravedad],
              ['Accidente STP', indicadores?.accidentes_stp],
              ['Alto potencial', indicadores?.incidentes_alto_potencial],
              ['Accidente de trayecto', indicadores?.accidentes_trayecto],
            ].map(([l, v]) => (
              <View key={String(l)} style={S.tr}>
                <Text style={S.kpiLabel}>{String(l)}</Text>
                <Text style={S.kpiValor}>{v ?? 'S/D'}</Text>
              </View>
            ))}
          </View>

          {/* Gestión VCT + GRP */}
          <View style={{ flex: 1.6 }}>
            <View style={S.caja}>
              <Text style={S.cajaTitulo}>GESTIÓN VCT MENSUAL</Text>
              <View style={S.tr}>
                {['Gestión', 'Planif.', 'Real', '% Cumpl.', 'Abiertos', 'Cerrados'].map((h) => (
                  <Text key={h} style={S.th}>{h}</Text>
                ))}
              </View>
              <View style={S.tr}>
                <Text style={S.td}>VCT Empresa Colaboradora</Text>
                <Text style={S.td}>{vct?.meta ?? 0}</Text>
                <Text style={S.td}>{vct?.realizados ?? 0}</Text>
                <Text style={S.td}>{pct(vct)}</Text>
                <Text style={S.td}>{vct?.abiertos ?? 0}</Text>
                <Text style={S.td}>{vct?.cerrados ?? 0}</Text>
              </View>
            </View>

            <View style={S.caja}>
              <Text style={S.cajaTitulo}>GESTIÓN GRP MENSUAL</Text>
              <View style={S.tr}>
                {['Gestión', 'Planificado', 'Real', '% Cumplimiento'].map((h) => (
                  <Text key={h} style={S.th}>{h}</Text>
                ))}
              </View>
              {[['VAT mensuales', vat], ['RIT mensuales', rit]].map(([nombre, x]) => (
                <View key={String(nombre)} style={S.tr}>
                  <Text style={S.td}>{String(nombre)}</Text>
                  <Text style={S.td}>{(x as GestionMensualFila)?.meta ?? 0}</Text>
                  <Text style={S.td}>{(x as GestionMensualFila)?.realizados ?? 0}</Text>
                  <Text style={S.td}>{pct(x as GestionMensualFila)}</Text>
                </View>
              ))}
            </View>

            <View style={S.caja}>
              <Text style={S.cajaTitulo}>EMERGENCIA / CPHS / CAMPAÑAS</Text>
              <View style={S.tr}>
                {['Ámbito', 'Planificado', 'Real', '% Cumplimiento'].map((h) => (
                  <Text key={h} style={S.th}>{h}</Text>
                ))}
              </View>
              {[['Simulacros', simulacros], ['Campañas', campanas]].map(([nombre, x]) => (
                <View key={String(nombre)} style={S.tr}>
                  <Text style={S.td}>{String(nombre)}</Text>
                  <Text style={S.td}>{(x as GestionMensualFila)?.meta ?? 0}</Text>
                  <Text style={S.td}>{(x as GestionMensualFila)?.realizados ?? 0}</Text>
                  <Text style={S.td}>{pct(x as GestionMensualFila)}</Text>
                </View>
              ))}
            </View>

            <View style={S.caja}>
              <Text style={S.cajaTitulo}>OTRAS ACTIVIDADES DEL MES</Text>
              <View style={S.tr}>
                {['Actividad', 'Planif.', 'Real', '% Cumpl.', 'Abiertos', 'Cerrados'].map((h) => (
                  <Text key={h} style={S.th}>{h}</Text>
                ))}
              </View>
              {gestion
                .filter((x) => !['VCT', 'VAT', 'RIT', 'SIMULACRO', 'CAMPANA'].includes(x.tipo_codigo))
                .filter((x) => x.meta > 0 || x.realizados > 0)
                .map((x) => (
                  <View key={x.tipo_codigo} style={S.tr}>
                    <Text style={S.td}>{x.tipo_nombre}</Text>
                    <Text style={S.td}>{x.meta}</Text>
                    <Text style={S.td}>{x.realizados}</Text>
                    <Text style={S.td}>{pct(x)}</Text>
                    <Text style={S.td}>{x.requiere_cierre ? x.abiertos : '—'}</Text>
                    <Text style={S.td}>{x.requiere_cierre ? x.cerrados : '—'}</Text>
                  </View>
                ))}
            </View>
          </View>

          {/* Fotos de actividades relevantes */}
          <View style={[S.caja, { flex: 1.2 }]}>
            <Text style={S.cajaTitulo}>FOTOGRAFÍAS ACTIVIDADES RELEVANTES</Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', padding: 3 }}>
              {fotos.length === 0 && (
                <Text style={{ fontSize: 7.5, padding: 6, color: '#6b7280' }}>
                  Sin fotografías cargadas este mes.
                </Text>
              )}
              {fotos.map((foto, i) => (
                <View key={i}>
                  {/* eslint-disable-next-line jsx-a11y/alt-text */}
                  <Image src={foto.url} style={S.foto} />
                  <Text style={S.fotoCaption}>{foto.caption}</Text>
                </View>
              ))}
            </View>
          </View>
        </View>

        <Text style={S.footer}>
          Formato GRP CMP · Generado por SICOM desde los registros de supervisión — revisar antes de enviar ·{' '}
          {new Date().toLocaleDateString('es-CL')}
        </Text>
      </Page>
    </Document>
  )
}

/** Genera el PDF. Toma hasta 4 fotos de los registros del mes (campañas y
 *  actividades con evidencia) vía URL firmada. */
export async function generarInformeCmpPdf(params: {
  config: FaenaConfigDatos
  indicadores: IndicadoresFila | null
  gestion: GestionMensualFila[]
  registros: PrevencionRegistro[]
  anio: number
  mes: number
  faenaNombre: string
}): Promise<Blob> {
  const conFoto = params.registros
    .filter((r) => (r.evidencias?.length ?? 0) > 0)
    .sort((a, b) => (a.tipo_codigo === 'CAMPANA' ? -1 : 1) - (b.tipo_codigo === 'CAMPANA' ? -1 : 1))
    .slice(0, 4)

  const fotos: FotoEmbebida[] = []
  for (const r of conFoto) {
    const ev = (r.evidencias ?? []).find((e) => e.content_type.startsWith('image/'))
    if (!ev) continue
    const url = await urlEvidencia(ev.path)
    if (url) fotos.push({ url, caption: `${r.tipo_codigo} · ${r.titulo}` })
  }

  return pdf(
    <DocInforme
      config={params.config}
      indicadores={params.indicadores}
      gestion={params.gestion}
      fotos={fotos}
      anio={params.anio}
      mes={params.mes}
      faenaNombre={params.faenaNombre}
    />,
  ).toBlob()
}
