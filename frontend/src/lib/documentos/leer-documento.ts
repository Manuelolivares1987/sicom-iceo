// ============================================================================
// El sistema lee el papel cuando lo subes.
// ----------------------------------------------------------------------------
// Manuel: «¿es factible que el sistema sea inteligente e identifique si le subo
// basura?».
//
// Sí, y hace falta: los 468 certificados sin fecha de la flota entraron
// exactamente así —alguien adjuntó un PDF y nadie lo abrió—. Si el archivo se
// revisa EN EL MOMENTO de subirlo, el problema no se vuelve a crear.
//
// Cuatro preguntas, en orden de gravedad:
//
//   1. ¿Es un archivo de verdad?      un .exe renombrado a .pdf se detecta
//   2. ¿Es de ESTE equipo?            la patente tiene que aparecer en el papel
//   3. ¿Es del tipo que se pidió?     un SOAP subido como hermeticidad se nota
//   4. ¿Hasta cuándo vale?            si lo dice, se rellena la fecha sola
//
// NINGUNA BLOQUEA POR SÍ SOLA, salvo la primera. Un certificado legítimo puede
// identificar el equipo por número de chasis en vez de patente, o venir
// escaneado sin texto. Bloquear eso dejaría a alguien sin poder cargar un papel
// bueno — que es peor que el problema que se está resolviendo. Se avisa fuerte
// y se pide confirmar.
// ============================================================================

export type Severidad = 'bloqueante' | 'grave' | 'aviso' | 'ok'

export type Aviso = { severidad: Severidad; titulo: string; detalle: string }

export type LecturaDocumento = {
  avisos: Aviso[]
  /** Vencimiento leído del documento, si lo declara. */
  vencimiento: string | null
  /** Fecha del documento (emisión, instalación, inspección). */
  emision: string | null
  /** De dónde salió el vencimiento, para dejarlo escrito al guardar. */
  origen: 'documento' | 'regla_2_anios' | null
  reglaUsada: string | null
  evidencia: string | null
  /** Caracteres de texto extraídos. 0 = es un escaneo. */
  caracteres: number
  /** true si nada impide guardar (puede haber avisos que pidan confirmar). */
  puedeGuardar: boolean
}

// ── Palabras que identifican cada tipo de papel ─────────────────────────────
// Sólo los tipos donde confundirse tiene consecuencias. Un tipo que no está acá
// simplemente no se verifica: es mejor no opinar que opinar mal.
const HUELLA_TIPO: Record<string, string[]> = {
  hermeticidad:          ['hermeticidad', 'hidroestatica', 'hidrostatica', 'estanquedad'],
  laminas_seguridad:     ['lamina de seguridad', 'laminas de seguridad', 'film de seguridad'],
  revision_tecnica:      ['revision tecnica', 'planta revisora'],
  soap:                  ['seguro obligatorio', 'ley 18.490', 'ley n 18.490', 'soap'],
  permiso_circulacion:   ['permiso de circulacion', 'municipalidad'],
  seguro_rc:             ['poliza', 'responsabilidad civil', 'asegurado'],
  analisis_gases:        ['analisis de gases', 'gases de escape', 'opacidad'],
  tacografo:             ['tacografo'],
  torque_ruedas:         ['torque', 'apriete'],
  grilletes_eslingas:    ['grillete', 'eslinga'],
  ausencia_falla_ecm:    ['ecm', 'codigos de falla', 'ecu'],
  cert_cabina:           ['cabina'],
  barra_antivuelco:      ['antivuelco', 'rops'],
  inventario_neumaticos: ['neumatico'],
  aire_acondicionado:    ['aire acondicionado', 'climatizacion'],
  optico_sobrellenado:   ['sobrellenado', 'optico'],
  flujo_descarga:        ['flujo', 'descarga'],
}

const MESES: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6, julio: 7,
  agosto: 8, septiembre: 9, setiembre: 9, octubre: 10, noviembre: 11, diciembre: 12,
}

function normalizar(t: string): string {
  return t.replace(/\s+/g, ' ')
    .replace(/[áÁ]/g, 'a').replace(/[éÉ]/g, 'e').replace(/[íÍ]/g, 'i')
    .replace(/[óÓ]/g, 'o').replace(/[úÚ]/g, 'u').replace(/[ñÑ]/g, 'n')
}

type Fecha = { iso: string; pos: number }

function fechasEn(t: string): Fecha[] {
  const out: Fecha[] = []
  // El target del proyecto no permite iterar matchAll: se recorre con exec.
  const reNum = /\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b/g
  for (let m = reNum.exec(t); m; m = reNum.exec(t)) {
    let y = Number(m[3]); const d = Number(m[1]), mo = Number(m[2])
    if (y < 100) y += y < 70 ? 2000 : 1900
    if (d < 1 || d > 31 || mo < 1 || mo > 12 || y < 2000 || y > 2100) continue
    out.push({ iso: `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`, pos: m.index ?? 0 })
  }
  const reTxt = /\b(\d{1,2})\s+de\s+([a-z]+)\s+(?:de\s+|del\s+)?(20\d{2})\b/gi
  for (let m = reTxt.exec(t); m; m = reTxt.exec(t)) {
    const mo = MESES[m[2].toLowerCase()]
    if (!mo) continue
    out.push({ iso: `${m[3]}-${String(mo).padStart(2, '0')}-${String(Number(m[1])).padStart(2, '0')}`, pos: m.index ?? 0 })
  }
  return out
}

function sumarAnios(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number)
  return new Date(Date.UTC(y + n, m - 1, d)).toISOString().slice(0, 10)
}

const RE_VENCE = /(vence|vencimiento|valido hasta|valida hasta|vigente hasta|caduca|expira)/i
const RE_EMISION = /(fecha de emision|fecha emision|fecha de inspeccion|fecha inspeccion|fecha de instalacion|fecha instalacion|fecha de certificacion|fecha de control|emitido el|fecha)/i
const RE_VIGENCIA = /valid[oa]?\s+por\s+(un|una|\d+)\s*(anos?|ano|meses|mes)|periodo\s+de\s+(un|una|\d+)\s*(anos?|ano|meses|mes)/i
const RE_PAGO = /cuota|dividendo|forma de pago|plan de pago/

/** Saca el texto de un PDF con pdfjs, que ya viene con el proyecto. */
async function textoDePdf(file: File): Promise<string> {
  const pdfjs = await import('pdfjs-dist')
  // El worker va inline: sin esto pdfjs intenta bajarlo de un CDN y la CSP lo corta.
  const w = await import('pdfjs-dist/build/pdf.worker.mjs?url' as string).catch(() => null)
  if (w && 'default' in (w as Record<string, unknown>)) {
    ;(pdfjs as unknown as { GlobalWorkerOptions: { workerSrc: string } })
      .GlobalWorkerOptions.workerSrc = (w as { default: string }).default
  }
  const buf = await file.arrayBuffer()
  const doc = await (pdfjs as unknown as {
    getDocument: (o: unknown) => { promise: Promise<{ numPages: number; getPage: (n: number) => Promise<{ getTextContent: () => Promise<{ items: Array<{ str?: string }> }> }>; destroy: () => Promise<void> }> }
  }).getDocument({ data: new Uint8Array(buf), isEvalSupported: false }).promise

  let texto = ''
  const paginas = Math.min(doc.numPages, 5) // con 5 basta: la fecha va al principio
  for (let p = 1; p <= paginas; p++) {
    const tc = await (await doc.getPage(p)).getTextContent()
    texto += tc.items.map((i) => i.str ?? '').join(' ') + '\n'
  }
  await doc.destroy()
  return texto
}

/** Los primeros bytes dicen qué es de verdad, no la extensión. */
async function tipoReal(file: File): Promise<'pdf' | 'jpg' | 'png' | 'otro'> {
  const b = new Uint8Array(await file.slice(0, 8).arrayBuffer())
  if (b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46) return 'pdf'   // %PDF
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpg'
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'png'
  return 'otro'
}

/**
 * Lee el archivo que se está subiendo y dice qué encontró.
 * No guarda nada: sólo informa para que la persona decida.
 */
export async function leerDocumento(
  file: File,
  ctx: { patente?: string | null; tipo: string },
): Promise<LecturaDocumento> {
  const avisos: Aviso[] = []
  const vacio: LecturaDocumento = {
    avisos, vencimiento: null, emision: null, origen: null,
    reglaUsada: null, evidencia: null, caracteres: 0, puedeGuardar: true,
  }

  // ── 1. ¿Es un archivo de verdad? ──────────────────────────────────────────
  const real = await tipoReal(file)
  if (real === 'otro') {
    avisos.push({
      severidad: 'bloqueante',
      titulo: 'Esto no es un PDF ni una imagen',
      detalle: `«${file.name}» no tiene la forma de un documento. Puede estar dañado o ser otro tipo de archivo con el nombre cambiado.`,
    })
    return { ...vacio, puedeGuardar: false }
  }
  if (file.size < 8_000) {
    avisos.push({
      severidad: 'grave',
      titulo: 'El archivo es muy chico',
      detalle: `Pesa ${Math.round(file.size / 1024)} KB. Un certificado escaneado suele pesar más; revisa que no sea una página en blanco.`,
    })
  }

  if (real !== 'pdf') {
    avisos.push({
      severidad: 'aviso',
      titulo: 'Es una imagen, no se puede leer el texto',
      detalle: 'Se guarda igual, pero nadie va a poder buscar dentro. Si tienes el PDF original, es mejor.',
    })
    return vacio
  }

  // ── 2. Leerlo ─────────────────────────────────────────────────────────────
  let crudo = ''
  try {
    crudo = await textoDePdf(file)
  } catch {
    avisos.push({
      severidad: 'grave',
      titulo: 'El PDF no se pudo abrir',
      detalle: 'Puede estar dañado o protegido con clave. Se puede guardar igual, pero conviene revisarlo.',
    })
    return vacio
  }

  const t = normalizar(crudo)
  const bajo = t.toLowerCase()
  const caracteres = t.trim().length

  if (caracteres < 40) {
    avisos.push({
      severidad: 'aviso',
      titulo: 'Es un escaneo: no tiene texto',
      detalle: 'Es una foto de papel, así que el sistema no puede verificar nada ni sacar la fecha. Anótala a mano abajo.',
    })
    return { ...vacio, caracteres }
  }

  // ── 3. ¿Es de ESTE equipo? ────────────────────────────────────────────────
  const pat = (ctx.patente ?? '').trim().toUpperCase()
  if (pat.length >= 6) {
    // La patente aparece escrita de varias formas: TGGF-57, TGGF57, TG-GF57-4.
    const soloLetras = pat.replace(/[^A-Z0-9]/g, '')
    const textoPlano = t.toUpperCase().replace(/[^A-Z0-9]/g, '')
    if (!textoPlano.includes(soloLetras)) {
      avisos.push({
        severidad: 'grave',
        titulo: `No dice ${pat} en ninguna parte`,
        detalle: 'Puede ser el papel de otro equipo. Algunos certificados identifican por número de chasis y no por patente — si es el caso, sigue adelante; si no, revisa el archivo.',
      })
    } else {
      avisos.push({
        severidad: 'ok', titulo: `Dice ${pat}`,
        detalle: 'El documento menciona la patente de este equipo.',
      })
    }
  }

  // ── 4. ¿Es del tipo que se pidió? ─────────────────────────────────────────
  const huella = HUELLA_TIPO[ctx.tipo]
  if (huella && !huella.some((h) => bajo.includes(h))) {
    avisos.push({
      severidad: 'grave',
      titulo: 'No parece el documento de este tipo',
      detalle: `No encontré nada que hable de «${huella[0]}». Revisa que no sea otro certificado.`,
    })
  }

  // ── 5. ¿Hasta cuándo vale? ────────────────────────────────────────────────
  const fechas = fechasEn(t)
  let vencimiento: string | null = null
  let emision: string | null = null
  let origen: LecturaDocumento['origen'] = null
  let reglaUsada: string | null = null
  let evidencia: string | null = null

  const cercaDe = (pos: number, max = 140) =>
    fechas.map((f) => ({ ...f, d: f.pos - pos }))
          .filter((f) => f.d > 0 && f.d < max)
          .sort((a, b) => a.d - b.d)[0]

  // Vencimiento explícito, saltando las tablas de cuotas de las pólizas.
  const reVence = new RegExp(RE_VENCE.source, 'gi')
  for (let m = reVence.exec(bajo); m; m = reVence.exec(bajo)) {
    const i = m.index ?? 0
    if (RE_PAGO.test(bajo.slice(Math.max(0, i - 90), i + 90))) continue
    const f = cercaDe(i)
    if (f) {
      vencimiento = f.iso; origen = 'documento'
      reglaUsada = 'el documento dice hasta cuándo vale'
      evidencia = t.slice(Math.max(0, i - 40), i + 120).trim()
      break
    }
  }

  // Fecha del documento + vigencia declarada.
  const mEmi = bajo.match(RE_EMISION)
  if (mEmi) {
    const f = cercaDe(mEmi.index ?? 0, 170)
    if (f) emision = f.iso
  }

  if (!vencimiento) {
    const mVig = bajo.match(RE_VIGENCIA)
    const n = mVig ? Number(String(mVig[1] ?? mVig[3]).replace(/^un[a]?$/, '1')) : null
    if (mVig && n && emision) {
      const esMes = String(mVig[2] ?? mVig[4] ?? '').startsWith('mes')
      vencimiento = esMes ? emision : sumarAnios(emision, n)
      origen = 'documento'
      reglaUsada = `el documento dice que vale ${n} ${esMes ? 'mes(es)' : 'año(s)'}`
      evidencia = t.slice(Math.max(0, (mVig.index ?? 0) - 50), (mVig.index ?? 0) + 110).trim()
    } else if (emision) {
      vencimiento = sumarAnios(emision, 2)
      origen = 'regla_2_anios'
      reglaUsada = 'el documento no dice hasta cuándo vale: 2 años desde su fecha'
    }
  }

  if (vencimiento) {
    const hoy = new Date().toISOString().slice(0, 10)
    avisos.push(
      vencimiento < hoy
        ? {
            severidad: 'grave',
            titulo: `Este documento ya está vencido (${vencimiento})`,
            detalle: 'Se puede guardar para dejar el antecedente, pero el equipo va a quedar marcado como vencido.',
          }
        : {
            severidad: 'ok',
            titulo: `Vence el ${vencimiento}`,
            detalle: reglaUsada ?? '',
          },
    )
  } else {
    avisos.push({
      severidad: 'aviso',
      titulo: 'No encontré hasta cuándo vale',
      detalle: 'Tiene texto, pero ninguna fecha con etiqueta clara. Anótala a mano abajo.',
    })
  }

  return { avisos, vencimiento, emision, origen, reglaUsada, evidencia, caracteres, puedeGuardar: true }
}

/** La peor severidad encontrada, para pintar el resumen. */
export function peorSeveridad(avisos: Aviso[]): Severidad {
  if (avisos.some((a) => a.severidad === 'bloqueante')) return 'bloqueante'
  if (avisos.some((a) => a.severidad === 'grave')) return 'grave'
  if (avisos.some((a) => a.severidad === 'aviso')) return 'aviso'
  return 'ok'
}
