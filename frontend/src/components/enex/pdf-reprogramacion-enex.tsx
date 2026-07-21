'use client'

// Registro de Reprogramación de Actividades (formato ESM/PILLADO) — MIG234.
// Réplica del formulario que se entrega a ENEX cuando una actividad programada
// se mueve de fecha. Se llena desde enex_reprogramaciones, se sube al bucket
// documentos/enex-reprogramaciones y se descarga para el mandante.

import { Document, Page, Text, View, StyleSheet, Image, pdf } from '@react-pdf/renderer'
import { supabase } from '@/lib/supabase'
import { aDataUrl } from './pdf-informe-enex'
import {
  getReprogramacion, setReprogramacionPdf,
  REPROG_RESPONSABLE, REPROG_CAUSA, type EnexReprogramacion,
} from '@/lib/services/enex'

const S = StyleSheet.create({
  page: { padding: 32, fontSize: 9, fontFamily: 'Helvetica', color: '#111827' },
  headerRow: { flexDirection: 'row', borderWidth: 1, borderColor: '#111', marginBottom: 10, alignItems: 'stretch' },
  logoBox: { width: 120, padding: 6, justifyContent: 'center', alignItems: 'center' },
  logoR: { borderLeftWidth: 1, borderLeftColor: '#111' },
  logo: { width: 100, height: 30, objectFit: 'contain' },
  logoTxt: { fontSize: 12, fontWeight: 'bold', color: '#1d4ed8' },
  titleBox: { flex: 1, padding: 8, justifyContent: 'center', borderLeftWidth: 1, borderRightWidth: 1, borderColor: '#111' },
  title: { fontSize: 11, fontWeight: 'bold', textAlign: 'center' },
  section: { backgroundColor: '#dbe4f0', fontWeight: 'bold', fontSize: 9, padding: 3, marginTop: 10, marginBottom: 2 },
  row: { flexDirection: 'row', borderBottomWidth: 0.5, borderLeftWidth: 0.5, borderRightWidth: 0.5, borderColor: '#555' },
  rowTop: { borderTopWidth: 0.5, borderTopColor: '#555' },
  cellLabel: { width: '32%', padding: 4, fontSize: 8, backgroundColor: '#eef2f7', color: '#374151', borderRightWidth: 0.5, borderRightColor: '#555' },
  cellValue: { flex: 1, padding: 4, fontSize: 8 },
  small: { width: '30%' },
  chkLine: { flexDirection: 'row', flexWrap: 'wrap', marginTop: 3 },
  descBox: { borderWidth: 0.5, borderColor: '#555', minHeight: 46, padding: 5, fontSize: 8, marginTop: 2 },
  firmasRow: { flexDirection: 'row', marginTop: 28, borderTopWidth: 0.5, borderColor: '#555' },
  firmaCol: { flex: 1, borderRightWidth: 0.5, borderColor: '#555', alignItems: 'center', paddingTop: 4, paddingBottom: 6, minHeight: 70 },
  firmaColLast: { borderRightWidth: 0 },
  firmaHead: { fontSize: 8, fontWeight: 'bold', marginBottom: 4 },
  firmaImg: { height: 40, width: 110, objectFit: 'contain' },
  footer: { position: 'absolute', bottom: 18, left: 32, right: 32, fontSize: 7, color: '#9ca3af', textAlign: 'center' },
  cbWrap: { flexDirection: 'row', alignItems: 'center', marginRight: 12, marginBottom: 2 },
  cbBox: { width: 9, height: 9, borderWidth: 0.8, borderColor: '#111', marginRight: 3, alignItems: 'center', justifyContent: 'center' },
  cbX: { fontSize: 7, fontWeight: 'bold', lineHeight: 1 },
  cbLabel: { fontSize: 8 },
})

// Casilla dibujada (Helvetica no trae los glifos ☑/☐).
function Chk({ on, label }: { on: boolean; label: string }) {
  return (
    <View style={S.cbWrap}>
      <View style={S.cbBox}>{on ? <Text style={S.cbX}>X</Text> : null}</View>
      <Text style={S.cbLabel}>{label}</Text>
    </View>
  )
}

function fmtFecha(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

function CampoRow({ label, value, small }: { label: string; value?: string | null; small?: boolean }) {
  return (
    <View style={S.row}>
      <Text style={[S.cellLabel, ...(small ? [S.small] : [])]}>{label}</Text>
      <Text style={S.cellValue}>{value && value.trim() ? value : ' '}</Text>
    </View>
  )
}

type Datos = { r: EnexReprogramacion; logoUrl: string }

export function RegistroReprogramacion({ r, logoUrl }: Datos) {
  const tipos = ['eds', 'petrolera', 'semimovil', 'camion']
  const tiposLbl: Record<string, string> = { eds: 'EDS', petrolera: 'Petrolera', semimovil: 'Semimóvil', camion: 'Camión' }
  return (
    <Document>
      <Page size="A4" style={S.page}>
        {/* Encabezado */}
        <View style={S.headerRow}>
          <View style={S.logoBox}><Text style={S.logoTxt}>esm</Text></View>
          <View style={S.titleBox}><Text style={S.title}>REGISTRO DE REPROGRAMACIÓN DE ACTIVIDADES</Text></View>
          <View style={[S.logoBox, S.logoR]}>{logoUrl ? <Image src={logoUrl} style={S.logo} /> : <Text style={S.logoTxt}>PILLADO</Text>}</View>
        </View>

        {/* Información General */}
        <Text style={S.section}>Información General</Text>
        <View style={S.rowTop}>
          <CampoRow label="Faena" value={r.faena} />
        </View>
        <CampoRow label="Hora Ingreso a Faena" value={r.hora_ingreso} />
        <CampoRow label="Instalación / Equipo" value={r.instalacion ? `${r.instalacion}${r.patente ? ` · ${r.patente}` : ''}` : r.patente} />
        <View style={S.row}>
          <Text style={S.cellLabel}>Tipo de activo</Text>
          <View style={[S.cellValue, S.chkLine]}>
            {tipos.map((t) => <Chk key={t} on={r.tipo_activo === t} label={tiposLbl[t]} />)}
          </View>
        </View>
        <View style={S.row}>
          <Text style={S.cellLabel}>Actividad programada</Text>
          <View style={[S.cellValue, S.chkLine]}>
            <Chk on={r.actividad === 'mantencion'} label="Mantención" />
            <Chk on={r.actividad === 'calibracion'} label="Calibración" />
          </View>
        </View>
        <CampoRow label="Supervisor / Jefe Turno ESM" value={r.supervisor_esm} />
        <CampoRow label="Técnicos PILLADO" value={r.tecnicos_pillado} />

        {/* Programación Original */}
        <Text style={S.section}>Programación Original</Text>
        <View style={S.rowTop}><CampoRow label="Fecha programada" value={fmtFecha(r.fecha_original)} small /></View>
        <CampoRow label="Hora programada" value={r.hora_original} small />
        <CampoRow label="Semana" value={r.semana} small />
        <CampoRow label="Trimestre" value={r.trimestre} small />

        {/* Nueva programación */}
        <Text style={S.section}>Nueva Programación</Text>
        <View style={S.rowTop}><CampoRow label="Nueva fecha" value={fmtFecha(r.nueva_fecha)} small /></View>
        <CampoRow label="Nueva hora" value={r.nueva_hora} small />

        {/* Motivo */}
        <Text style={S.section}>Motivo de la Reprogramación</Text>
        <View style={[S.row, S.rowTop]}>
          <Text style={S.cellLabel}>Responsable</Text>
          <View style={[S.cellValue, S.chkLine]}>
            {Object.entries(REPROG_RESPONSABLE).map(([k, v]) => <Chk key={k} on={r.responsable === k} label={v} />)}
          </View>
        </View>
        <View style={S.row}>
          <Text style={S.cellLabel}>Causa</Text>
          <View style={[S.cellValue, S.chkLine]}>
            {Object.entries(REPROG_CAUSA).map(([k, v]) => <Chk key={k} on={r.causa === k} label={v} />)}
          </View>
        </View>

        <Text style={[S.section, { backgroundColor: 'transparent', paddingLeft: 0 }]}>Descripción de la causa de la reprogramación</Text>
        <Text style={S.descBox}>{r.descripcion ?? ' '}</Text>

        {/* Firmas */}
        <Text style={[S.section]}>Firmas</Text>
        <View style={S.firmasRow}>
          <View style={S.firmaCol}>
            <Text style={S.firmaHead}>Técnico PILLADO</Text>
            {r.firma_tecnico_url ? <Image src={r.firma_tecnico_url} style={S.firmaImg} /> : null}
          </View>
          <View style={S.firmaCol}>
            <Text style={S.firmaHead}>Responsable ESM</Text>
            {r.firma_esm_url ? <Image src={r.firma_esm_url} style={S.firmaImg} /> : null}
          </View>
          <View style={[S.firmaCol, S.firmaColLast]}>
            <Text style={S.firmaHead}>Mandante (Si aplica)</Text>
            {r.firma_mandante_url ? <Image src={r.firma_mandante_url} style={S.firmaImg} /> : null}
          </View>
        </View>

        <Text style={S.footer}>
          Registro generado por SICOM-ICEO · {fmtFecha(r.created_at)}
          {r.creado_por_nombre ? ` · ${r.creado_por_nombre}` : ''} · Contrato ENEX/ESM VA_24_068
        </Text>
      </Page>
    </Document>
  )
}

// Genera el PDF del registro, lo sube al bucket, guarda la URL y lo descarga.
export async function generarReprogramacionPdf(reprogramacionId: string): Promise<string> {
  const r = await getReprogramacion(reprogramacionId)
  if (!r) throw new Error('Reprogramación no encontrada')

  const logoUrl = await aDataUrl(`${window.location.origin}/images/logo_empresa_2.png`)
  r.firma_tecnico_url = await aDataUrl(r.firma_tecnico_url)
  r.firma_esm_url = await aDataUrl(r.firma_esm_url)
  r.firma_mandante_url = await aDataUrl(r.firma_mandante_url)

  const doc = <RegistroReprogramacion r={r} logoUrl={logoUrl ?? ''} />
  const blob = await Promise.race([
    pdf(doc).toBlob(),
    new Promise<Blob>((_, reject) => setTimeout(() => reject(new Error('Timeout generando PDF')), 15000)),
  ])

  const anio = (r.created_at ?? '').slice(0, 4) || 'sin-fecha'
  const path = `enex-reprogramaciones/${anio}/reprog_${reprogramacionId}_${Date.now()}.pdf`
  const { error } = await supabase.storage.from('documentos').upload(path, blob, { contentType: 'application/pdf', upsert: false })
  if (error) throw error
  const url = supabase.storage.from('documentos').getPublicUrl(path).data.publicUrl
  await setReprogramacionPdf(reprogramacionId, url)

  // Descarga directa para entregar a ENEX
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `Registro_Reprogramacion_${(r.instalacion ?? r.patente ?? 'ENEX').replace(/\s+/g, '_')}.pdf`
  a.click()
  URL.revokeObjectURL(a.href)
  return url
}
