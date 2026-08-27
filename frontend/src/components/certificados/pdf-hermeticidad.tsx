'use client'

// ============================================================================
// El certificado de hermeticidad, tal como se emite en papel
// ----------------------------------------------------------------------------
// Copia la estructura del certificado Nº 07/2024 del SVBJ-57, que es el modelo
// que entregó Manuel: tres páginas —descripción del estanque, aprobación de la
// prueba con la fecha de vencimiento, y control fotográfico— cada una con el
// membrete, la patente arriba a la derecha y la firma abajo.
//
// El formato importa: este papel se presenta ante terceros y se compara con los
// anteriores. Un certificado que se ve distinto al de la carpeta genera la
// pregunta equivocada.
// ============================================================================

import {
  Document, Page, Text, View, StyleSheet, Image, pdf,
} from '@react-pdf/renderer'
import type { CertificadoHermeticidad } from '@/lib/services/certificados'

const s = StyleSheet.create({
  page: { padding: 28, fontSize: 9.5, fontFamily: 'Helvetica', color: '#111' },
  marco: { borderWidth: 1.5, borderColor: '#111', padding: 14, minHeight: '96%' },

  cabecera: { flexDirection: 'row', alignItems: 'center', marginBottom: 10 },
  logo: { width: 118, height: 34, objectFit: 'contain' },
  ppuBox: { marginLeft: 'auto', flexDirection: 'row', alignItems: 'baseline' },
  ppuLabel: { fontSize: 11, fontFamily: 'Helvetica-Bold', marginRight: 22 },
  ppu: { fontSize: 13, fontFamily: 'Helvetica-Bold' },

  titulo: { fontSize: 16, fontFamily: 'Helvetica-Bold', textAlign: 'center', marginBottom: 4 },
  folio: { fontSize: 12, fontFamily: 'Helvetica-Bold', textAlign: 'right', marginBottom: 10 },

  informe: { fontSize: 12, fontFamily: 'Helvetica-Bold', marginBottom: 4 },
  seccion: {
    fontSize: 11, fontFamily: 'Helvetica-Bold', marginTop: 12, marginBottom: 5,
    textDecoration: 'underline',
  },

  fila: { flexDirection: 'row', marginBottom: 2.5 },
  etiqueta: { width: '42%', paddingLeft: 12 },
  valor: { width: '58%' },

  parrafo: { marginBottom: 8, lineHeight: 1.45, textAlign: 'justify' },

  tresCol: { flexDirection: 'row', marginTop: 10 },
  colTitulo: { fontFamily: 'Helvetica-Bold', textDecoration: 'underline', textAlign: 'center', marginBottom: 4 },

  firma: { marginTop: 'auto', alignItems: 'flex-end', paddingTop: 24 },
  firmaLinea: { width: 200, borderTopWidth: 1, borderTopColor: '#111', marginBottom: 3 },
  firmaTexto: { fontSize: 9, textAlign: 'center', width: 200 },
  firmaNombre: { fontSize: 9.5, fontFamily: 'Helvetica-Bold', textAlign: 'center', width: 200 },

  fotoFila: { flexDirection: 'row', borderWidth: 1, borderColor: '#111', minHeight: 210 },
  fotoLabel: { width: 90, justifyContent: 'center', paddingLeft: 8, fontFamily: 'Helvetica-Bold' },
  fotoBox: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 6 },
  foto: { maxHeight: 200, objectFit: 'contain' },
  sinFoto: { fontSize: 9, color: '#777', fontStyle: 'italic' },
})

const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado']
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
               'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

/** «lunes, 22 de julio de 2024» — como lo escribe el certificado en papel. */
function fechaLarga(iso: string | null, conDia = true): string {
  if (!iso) return ''
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  // Se arma con UTC a propósito: `new Date('2024-07-22')` en un huso al oeste
  // de Greenwich cae en el 21 y el certificado sale con la fecha del día
  // anterior.
  const dt = new Date(Date.UTC(a, m - 1, d))
  const cuerpo = `${d} de ${MESES[m - 1]} de ${a}`
  return conDia ? `${DIAS[dt.getUTCDay()]}, ${cuerpo}` : cuerpo
}

function Cabecera({ ppu, logoUrl }: { ppu: string; logoUrl: string }) {
  return (
    <View style={s.cabecera}>
      {/* eslint-disable-next-line jsx-a11y/alt-text */}
      <Image style={s.logo} src={logoUrl} />
      <View style={s.ppuBox}>
        <Text style={s.ppuLabel}>PPU:</Text>
        <Text style={s.ppu}>{ppu}</Text>
      </View>
    </View>
  )
}

function Dato({ k, v }: { k: string; v?: string | null }) {
  return (
    <View style={s.fila}>
      <Text style={s.etiqueta}>{k}</Text>
      <Text style={s.valor}>: {v || '—'}</Text>
    </View>
  )
}

function Firma({ c }: { c: CertificadoHermeticidad }) {
  return (
    <View style={s.firma}>
      <View style={s.firmaLinea} />
      <Text style={s.firmaNombre}>{c.firmante_nombre || '—'}</Text>
      <Text style={s.firmaTexto}>{c.firmante_titulo || ''}</Text>
      <Text style={s.firmaTexto}>{c.firmante_cargo || ''}</Text>
      <Text style={s.firmaTexto}>{c.propietario || 'PILLADO Y CÍA. LTDA.'}</Text>
    </View>
  )
}

export function CertificadoHermeticidadPDF({ c, logoUrl }: {
  c: CertificadoHermeticidad; logoUrl: string
}) {
  return (
    <Document title={`Certificado de Hermeticidad ${c.folio} — ${c.patente}`}>

      {/* ── 1. Descripción del estanque ─────────────────────────────────── */}
      <Page size="LETTER" style={s.page}>
        <View style={s.marco}>
          <Cabecera ppu={c.patente} logoUrl={logoUrl} />
          <Text style={s.titulo}>CERTIFICADO DE HERMETICIDAD</Text>
          <Text style={s.folio}>CERTIFICADO Nº {c.folio}</Text>

          <Text style={s.informe}>INFORME: {c.informe}</Text>
          <View style={s.fila}>
            <Text style={{ ...s.etiqueta, paddingLeft: 0, width: '25%', fontFamily: 'Helvetica-Bold' }}>
              Fecha de Prueba:
            </Text>
            <Text style={{ width: '75%' }}>{fechaLarga(c.fecha_prueba)}</Text>
          </View>

          <Text style={s.seccion}>IDENTIFICACION DEL INSTRUMENTO</Text>
          <Dato k="Descripción" v={c.instrumento_desc} />
          <Dato k="Marca / Modelo" v={c.instrumento_marca} />

          <Text style={s.seccion}>DESCRIPCION DEL EQUIPO</Text>
          <Dato k="Camión Patente" v={c.patente} />
          <Dato k="Estanque Serie Nº" v={c.estanque_serie} />
          <Dato k="Año de Fabricación" v={c.anio_fabricacion} />
          <Dato k="Nombre Propietario" v={c.propietario} />
          <Dato k="Dirección de propietario" v={c.propietario_direccion} />
          <Dato k="Fabricante" v={c.fabricante} />

          <Text style={s.seccion}>CARACTERISTICAS DE DISEÑO</Text>
          <Dato k="Norma de Revisión" v={c.norma_revision} />
          <Dato k="Tipo de estanque" v={c.tipo_estanque} />
          <Dato k="Capacidad Nominal" v={c.capacidad_nominal} />
          <Dato k="Nº Compartimientos" v={c.n_compartimientos} />
          <Dato k="Cap. Compartimientos" v={c.cap_compartimientos} />
          <Dato k="Protocolo Inspección" v={c.protocolo} />
          <Dato k="Presión de Diseño" v={c.presion_diseno} />
          <Dato k="Presión de Prueba" v={c.presion_prueba} />
          <Dato k="Longitud Nominal" v={c.longitud_nominal} />
          <Dato k="Diámetro Nominal" v={c.diametro_nominal} />
          <Dato k="Ancho Nominal" v={c.ancho_nominal} />
          <Dato k="Alto Nominal" v={c.alto_nominal} />

          <View style={s.tresCol}>
            <View style={{ width: '34%' }} />
            <View style={{ width: '33%' }}><Text style={s.colTitulo}>MANTOS</Text></View>
            <View style={{ width: '33%' }}><Text style={s.colTitulo}>CABEZALES</Text></View>
          </View>
          {([
            ['Material', c.manto_material, c.cabezal_material],
            ['Forma o Tipo', c.manto_forma, c.cabezal_forma],
            ['Espesor de Diseño', c.manto_espesor, c.cabezal_espesor],
          ] as const).map(([k, a, b]) => (
            <View key={k} style={s.fila}>
              <Text style={{ width: '34%', paddingLeft: 12 }}>{k}</Text>
              <Text style={{ width: '33%', textAlign: 'center' }}>{a || '—'}</Text>
              <Text style={{ width: '33%', textAlign: 'center' }}>{b || '—'}</Text>
            </View>
          ))}

          <View style={s.tresCol}>
            <View style={{ width: '25%' }} />
            <View style={{ width: '25%' }}><Text style={s.colTitulo}>Longitudinal Manto</Text></View>
            <View style={{ width: '25%' }}><Text style={s.colTitulo}>Rectangular Manto</Text></View>
            <View style={{ width: '25%' }}><Text style={s.colTitulo}>Manto / Cabezal</Text></View>
          </View>
          <View style={s.fila}>
            <Text style={{ width: '25%', paddingLeft: 12 }}>Uniones Soldadas</Text>
            <Text style={{ width: '25%', textAlign: 'center' }}>{c.union_longitudinal || 'Tope'}</Text>
            <Text style={{ width: '25%', textAlign: 'center' }}>{c.union_rectangular || 'Tope'}</Text>
            <Text style={{ width: '25%', textAlign: 'center' }}>{c.union_manto_cabezal || 'Tope'}</Text>
          </View>

          <Firma c={c} />
        </View>
      </Page>

      {/* ── 2. Aprobación de la prueba ──────────────────────────────────── */}
      <Page size="LETTER" style={s.page}>
        <View style={s.marco}>
          <Cabecera ppu={c.patente} logoUrl={logoUrl} />
          <Text style={s.titulo}>APROBACION DE PRUEBA REALIZADA</Text>
          <Text style={s.folio}>CERTIFICADO Nº {c.folio}</Text>

          <Text style={s.parrafo}>
            {'      '}Al realizar las pruebas de presión a estanque {c.capacidad_nominal || '—'}, con{' '}
            {c.presion_prueba || '—'} de presión, no presentó fugas de aire, descenso de presión ni
            deformaciones permanente en el estanque uno, ni en sus válvulas de escape como en sus
            válvulas de fondo.
          </Text>

          <Dato k="Números de Compartimientos" v={c.n_compartimientos} />
          <Dato k="Medio de detección" v={c.medio_deteccion} />
          <Dato k="Rango de Manómetro de prueba" v={c.rango_manometro} />
          <Dato k="Alcance de Prueba" v={c.alcance_prueba} />
          <Dato k="Tipo de estanque" v={c.tipo_estanque} />
          <Dato k="Numero de plano" v={c.numero_plano} />
          <Dato k="Especificación de Diseño" v={c.especificacion_diseno} />
          <Dato k="Duración de la Prueba" v={c.duracion_prueba} />
          <Dato k="Métodos de prueba" v={c.metodo_prueba} />
          <Dato k="Lugar de la prueba" v={c.lugar_prueba} />
          <View style={s.fila}>
            <Text style={s.etiqueta}>Fecha de Inspección</Text>
            <Text style={s.valor}>{fechaLarga(c.fecha_prueba, false)}</Text>
          </View>
          <View style={s.fila}>
            <Text style={{ ...s.etiqueta, fontFamily: 'Helvetica-Bold' }}>Fecha de vencimiento</Text>
            <Text style={{ ...s.valor, fontFamily: 'Helvetica-Bold' }}>
              : {fechaLarga(c.fecha_vencimiento, false)}
            </Text>
          </View>

          <Text style={s.seccion}>Notas</Text>
          <Text style={s.parrafo}>
            Cualquier reparación o modificación después de esta fecha quedará inválida la prueba de
            presión ejecutada al compartimiento de dicho estanque.
          </Text>
          <Text style={s.parrafo}>
            El certificado no libera la responsabilidad del propietario ante deficiencias del
            conductor y/u operacional de seguridad, que se puedan presentarse cuando el estanque
            esté de servicio.
          </Text>
          <Text style={s.parrafo}>
            Se extiende el presente certificado de aprobación para ser presentado donde estime el
            dueño del vehículo camión estanque.
          </Text>

          <Firma c={c} />
        </View>
      </Page>

      {/* ── 3. Control fotográfico ──────────────────────────────────────── */}
      <Page size="LETTER" style={s.page}>
        <View style={s.marco}>
          <Cabecera ppu={c.patente} logoUrl={logoUrl} />
          <Text style={{ ...s.titulo, fontSize: 11 }}>
            CONTROL FOTOGRÁFICO PRUEBA DE PRESIÓN Y HERMETICIDAD COMBUSTIBLES LÍQUIDOS{' '}
            {c.protocolo || 'PC-110'}
          </Text>
          <Text style={s.folio}>CERTIFICADO Nº {c.folio}</Text>

          {([['INICIO', c.foto_inicio_url], ['TERMINO', c.foto_termino_url]] as const).map(([k, url]) => (
            <View key={k} style={{ ...s.fotoFila, marginBottom: 6 }}>
              <Text style={s.fotoLabel}>{k}</Text>
              <View style={s.fotoBox}>
                {url
                  // eslint-disable-next-line jsx-a11y/alt-text
                  ? <Image style={s.foto} src={url} />
                  : <Text style={s.sinFoto}>Sin fotografía cargada</Text>}
              </View>
            </View>
          ))}

          <Firma c={c} />
        </View>
      </Page>
    </Document>
  )
}

/** Genera el archivo y lo baja. Devuelve el nombre con que quedó. */
export async function descargarCertificadoHermeticidad(
  c: CertificadoHermeticidad, logoUrl: string,
): Promise<string> {
  const blob = await pdf(<CertificadoHermeticidadPDF c={c} logoUrl={logoUrl} />).toBlob()
  const nombre = `Cert. Hermeticidad ${c.folio.replace('/', '-')} - ${c.patente}.pdf`
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombre
  a.click()
  // Sin esto el blob queda retenido; con 3 páginas y dos fotos son varios MB.
  setTimeout(() => URL.revokeObjectURL(url), 4000)
  return nombre
}
