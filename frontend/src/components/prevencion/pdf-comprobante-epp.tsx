'use client'

// Comprobante de entrega de EPP (MIG687): lo que se archiva en la carpeta del
// trabajador y se muestra en una fiscalización (DS 44 art. 13).

import { Document, Image, Page, StyleSheet, Text, View, pdf } from '@react-pdf/renderer'
import { MOTIVO_EPP, urlFirmaEpp, type EppEntrega } from '@/lib/services/prevencion-epp'

const S = StyleSheet.create({
  page: { padding: 32, fontSize: 9, fontFamily: 'Helvetica', color: '#111827' },
  head: { flexDirection: 'row', borderWidth: 1, borderColor: '#111', marginBottom: 10 },
  logoBox: { width: 120, padding: 6, borderRightWidth: 1, borderRightColor: '#111', justifyContent: 'center' },
  logo: { width: 105, height: 40, objectFit: 'contain' },
  titleBox: { flex: 1, padding: 6, justifyContent: 'center' },
  title: { fontSize: 12, fontFamily: 'Helvetica-Bold', textAlign: 'center' },
  sub: { fontSize: 8, textAlign: 'center', marginTop: 2, color: '#374151' },
  row: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#6b7280' },
  lbl: { width: '30%', padding: 4, color: '#374151', borderRightWidth: 0.5, borderRightColor: '#6b7280' },
  val: { flex: 1, padding: 4, fontFamily: 'Helvetica-Bold' },
  sec: { backgroundColor: '#1f2937', color: '#fff', fontFamily: 'Helvetica-Bold', padding: 3, marginTop: 10 },
  th: { padding: 4, fontFamily: 'Helvetica-Bold', backgroundColor: '#f3f4f6', borderRightWidth: 0.5, borderRightColor: '#6b7280' },
  td: { padding: 4, borderRightWidth: 0.5, borderRightColor: '#6b7280' },
  decl: { marginTop: 10, fontSize: 8.5, lineHeight: 1.4, textAlign: 'justify' },
  firmas: { flexDirection: 'row', marginTop: 24 },
  firma: { flex: 1, alignItems: 'center', marginHorizontal: 12 },
  firmaImg: { height: 60, width: 160, objectFit: 'contain' },
  linea: { borderTopWidth: 1, borderTopColor: '#111', width: '100%', paddingTop: 3, alignItems: 'center' },
  anulada: { marginTop: 8, padding: 6, backgroundColor: '#fee2e2', color: '#991b1b', fontFamily: 'Helvetica-Bold', textAlign: 'center' },
  footer: { position: 'absolute', bottom: 18, left: 32, right: 32, fontSize: 6.5, color: '#9ca3af', textAlign: 'center' },
})

const fmt = (s: string) => new Date(s + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: '2-digit', year: 'numeric' })

function ComprobanteDoc({ e, logo, firma }: { e: EppEntrega, logo: string | null, firma: string | null }) {
  return (
    <Document title={`Entrega EPP ${e.trabajador_nombre} ${e.fecha}`} author="SICOM — Pillado Empresas">
      <Page size="LETTER" style={S.page}>
        <View style={S.head}>
          <View style={S.logoBox}>{logo ? <Image src={logo} style={S.logo} /> : <Text>PILLADO</Text>}</View>
          <View style={S.titleBox}>
            <Text style={S.title}>REGISTRO DE ENTREGA DE ELEMENTOS DE PROTECCIÓN PERSONAL</Text>
            <Text style={S.sub}>DS 44 art. 13 · Folio {e.id.slice(0, 8).toUpperCase()}</Text>
          </View>
        </View>

        {[
          ['Trabajador', e.trabajador_nombre],
          ['RUT', e.trabajador_rut ?? '—'],
          ['Faena', e.faena_nombre],
          ['Fecha de entrega', fmt(e.fecha)],
          ['Motivo', MOTIVO_EPP[e.motivo] ?? e.motivo],
          ['Entregado por', e.entregado_por_nombre ?? '—'],
        ].map(([l, v], i) => (
          <View key={l} style={[S.row, i === 0 ? { borderTopWidth: 0.5 } : {}]}>
            <Text style={S.lbl}>{l}</Text><Text style={S.val}>{v}</Text>
          </View>
        ))}

        <Text style={S.sec}>ELEMENTOS ENTREGADOS</Text>
        <View style={[S.row, { borderTopWidth: 0.5 }]}>
          <Text style={[S.th, { flex: 1 }]}>Elemento</Text>
          <Text style={[S.th, { width: '18%' }]}>Categoría</Text>
          <Text style={[S.th, { width: '10%' }]}>Cant.</Text>
          <Text style={[S.th, { width: '10%' }]}>Talla</Text>
          <Text style={[S.th, { width: '18%', borderRightWidth: 0 }]}>Reposición sugerida</Text>
        </View>
        {e.items.map((it) => (
          <View key={it.epp_codigo} style={S.row}>
            <Text style={[S.td, { flex: 1 }]}>{it.nombre}</Text>
            <Text style={[S.td, { width: '18%' }]}>{it.categoria}</Text>
            <Text style={[S.td, { width: '10%' }]}>{it.cantidad}</Text>
            <Text style={[S.td, { width: '10%' }]}>{it.talla ?? '—'}</Text>
            <Text style={[S.td, { width: '18%', borderRightWidth: 0 }]}>{it.proxima_reposicion ? fmt(it.proxima_reposicion) : 'Según desgaste'}</Text>
          </View>
        ))}

        {e.observacion && (
          <View style={[S.row, { borderTopWidth: 0.5, marginTop: 6 }]}>
            <Text style={S.lbl}>Observación</Text><Text style={[S.val, { fontFamily: 'Helvetica' }]}>{e.observacion}</Text>
          </View>
        )}

        <Text style={S.decl}>
          Declaro haber recibido gratuitamente los elementos de protección personal individualizados,
          en buen estado y de mi talla{e.instruccion_uso ? ', y haber sido instruido sobre su correcto uso, cuidado y mantención' : ''}.
          Me comprometo a usarlos durante mi jornada en las tareas que lo requieran, a cuidarlos y a
          solicitar su reposición cuando se deterioren o pierdan su efectividad.
        </Text>
        {!e.instruccion_uso && (
          <Text style={[S.decl, { color: '#b45309' }]}>
            Sin registro de instrucción de uso en esta entrega.
          </Text>
        )}

        {e.anulada && <Text style={S.anulada}>ENTREGA ANULADA — {e.anulada_motivo}</Text>}

        <View style={S.firmas}>
          <View style={S.firma}>
            {firma ? <Image src={firma} style={S.firmaImg} /> : <View style={{ height: 60 }} />}
            <View style={S.linea}>
              <Text style={{ fontFamily: 'Helvetica-Bold' }}>{e.trabajador_nombre}</Text>
              <Text style={{ fontSize: 7, color: '#4b5563' }}>Firma del trabajador</Text>
            </View>
          </View>
          <View style={S.firma}>
            <View style={{ height: 60 }} />
            <View style={S.linea}>
              <Text style={{ fontFamily: 'Helvetica-Bold' }}>{e.entregado_por_nombre ?? ' '}</Text>
              <Text style={{ fontSize: 7, color: '#4b5563' }}>Entrega (supervisor / prevención)</Text>
            </View>
          </View>
        </View>

        <Text style={S.footer}>
          SICOM · Pillado Empresas · Registrado el {new Date(e.created_at).toLocaleString('es-CL')} · Firma digital capturada en la entrega
        </Text>
      </Page>
    </Document>
  )
}

async function aDataUrl(url: string): Promise<string | null> {
  try {
    const r = await fetch(url)
    if (!r.ok) return null
    const b = await r.blob()
    return await new Promise((res) => { const f = new FileReader(); f.onload = () => res(f.result as string); f.onerror = () => res(null); f.readAsDataURL(b) })
  } catch { return null }
}

export async function descargarComprobanteEpp(e: EppEntrega) {
  const logo = await aDataUrl(`${window.location.origin}/images/logo_pillado_empresas.png`)
  const u = await urlFirmaEpp(e.firma_path)
  const firma = u ? await aDataUrl(u) : null
  const blob = await pdf(<ComprobanteDoc e={e} logo={logo} firma={firma} />).toBlob()
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `EPP_${e.fecha}_${e.trabajador_nombre.replace(/[^A-Za-z0-9]+/g, '_')}.pdf`
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
}
