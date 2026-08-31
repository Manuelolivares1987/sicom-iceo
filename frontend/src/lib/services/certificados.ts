// ============================================================================
// Emitir certificados desde el sistema. [MIG431/432]
// ----------------------------------------------------------------------------
// Hasta acá el sistema sólo registraba papeles que alguien traía de afuera.
// Ahora también los emite, empezando por la hermeticidad del estanque.
//
// Dos decisiones que están en la base y conviene tener presentes al usar esto:
//
//   · el VENCIMIENTO no se escribe. Sale de la fecha de prueba más lo que dura
//     el documento (6 meses). Toda la auditoría documental empezó porque
//     alguien tecleó un año donde iban seis meses.
//   · el FOLIO lo asigna la base, correlativo por año, saltando los que ya se
//     emitieron en papel. Llevado a mano se repetía: hay tres camiones con el
//     mismo «Nº 10/2025».
// ============================================================================
import { supabase } from '@/lib/supabase'

export type CertificadoHermeticidad = {
  id: string
  activo_id: string
  patente: string
  equipo_nombre: string | null
  tipo: string
  folio: string
  fecha_prueba: string
  fecha_vencimiento: string
  informe: string

  instrumento_desc: string | null
  instrumento_marca: string | null

  estanque_serie: string | null
  anio_fabricacion: string | null
  propietario: string | null
  propietario_direccion: string | null
  fabricante: string | null

  norma_revision: string | null
  tipo_estanque: string | null
  capacidad_nominal: string | null
  n_compartimientos: string | null
  cap_compartimientos: string | null
  protocolo: string | null
  presion_diseno: string | null
  presion_prueba: string | null
  longitud_nominal: string | null
  diametro_nominal: string | null
  ancho_nominal: string | null
  alto_nominal: string | null

  manto_material: string | null
  manto_forma: string | null
  manto_espesor: string | null
  cabezal_material: string | null
  cabezal_forma: string | null
  cabezal_espesor: string | null
  union_longitudinal: string | null
  union_rectangular: string | null
  union_manto_cabezal: string | null

  medio_deteccion: string | null
  rango_manometro: string | null
  alcance_prueba: string | null
  numero_plano: string | null
  especificacion_diseno: string | null
  duracion_prueba: string | null
  metodo_prueba: string | null
  lugar_prueba: string | null

  foto_inicio_url: string | null
  foto_termino_url: string | null

  firmante_nombre: string | null
  firmante_titulo: string | null
  firmante_cargo: string | null

  emitido_por_nombre: string | null
  vencido: boolean
  anulado: boolean
  created_at: string
  /** [MIG467] La firma con la que se emitió. Congelada: no cambia si el firmante cambia la suya. */
  firmante_firma_url: string | null
}

export type DatosPrevios = {
  patente: string
  equipo: string | null
  meses_vigencia: number
  hay_anterior: boolean
  folio_anterior: string | null
  datos: Record<string, string | null>
}

/**
 * Con qué se abre el formulario.
 *
 * Es lo que hace que esto sea usable: el certificado tiene más de treinta
 * campos, y veintiocho son del estanque y no cambian entre una prueba y la
 * siguiente. Se traen de la última emisión de ESE camión, así renovar es
 * confirmar y no tipear.
 */
export async function getDatosPrevios(activoId: string, tipo = 'hermeticidad'): Promise<DatosPrevios> {
  const { data, error } = await supabase.rpc('rpc_certificado_datos_previos', {
    p_activo_id: activoId, p_tipo: tipo,
  })
  if (error) throw error
  return data as DatosPrevios
}

export async function emitirCertificado(datos: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('rpc_emitir_certificado', { p_datos: datos })
  if (error) throw error
  return data as {
    success: boolean; id: string; folio: string; patente: string
    fecha_prueba: string; fecha_vencimiento: string; certificacion_id: string
  }
}

/** Los certificados ya emitidos de un equipo, para poder reimprimirlos. */
export async function getCertificadosEmitidos(activoId: string): Promise<CertificadoHermeticidad[]> {
  const { data, error } = await supabase
    .from('v_certificados_emitidos').select('*')
    .eq('activo_id', activoId).eq('anulado', false)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as CertificadoHermeticidad[]
}

export async function getCertificadoEmitido(id: string): Promise<CertificadoHermeticidad> {
  const { data, error } = await supabase
    .from('v_certificados_emitidos').select('*').eq('id', id).single()
  if (error) throw error
  return data as CertificadoHermeticidad
}

/** Sube una foto del control fotográfico y devuelve su URL pública. */
/**
 * Sube una foto de la prueba de hermeticidad.
 *
 * OJO CON LA CARPETA. El bucket `documentos` tiene RLS por prefijo de ruta, y
 * la politica de certificados solo admite `certificaciones/...` y `cert/...`.
 * Esto escribia en `certificados/...` —una tercera grafia que no existe— y el
 * upload moria con «new row violates row-level security policy», sin decir por
 * que. No era un problema de rol: le pasaba a cualquiera que adjuntara una
 * foto, administrador incluido.
 *
 * `cert/` es la carpeta que ya usa el resto del modulo (taller-planificacion).
 * Si hace falta una carpeta nueva, hay que agregarla a la politica ANTES.
 */
export async function subirFotoCertificado(activoId: string, momento: 'inicio' | 'termino', file: File) {
  const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `cert/hermeticidad/${activoId}/${Date.now()}-${momento}-${safe}`
  const { error } = await supabase.storage.from('documentos').upload(path, file, { upsert: false })
  if (error) {
    // El mensaje crudo de storage no le dice nada a quien esta emitiendo.
    if (/row-level security/i.test(error.message)) {
      throw new Error(
        `No se pudo guardar la foto de ${momento}: el sistema no tiene permiso para ` +
        `escribir en esa carpeta. Avisa a soporte — no es tu perfil, es la ruta.`)
    }
    throw new Error(`No se pudo subir la foto de ${momento}: ${error.message}`)
  }
  return supabase.storage.from('documentos').getPublicUrl(path).data.publicUrl
}

// ── [MIG467] La firma de quien emite ────────────────────────────────────────
//
// Vive en el perfil, no en el certificado: se sube una vez y sirve para todos
// los documentos que emita esa persona. Se guarda con el mismo RPC que ya usaba
// el vale de bodega desde MIG396 — una sola puerta.

export type MiFirma = {
  nombre: string | null
  cargo: string | null
  firma_url: string | null
  actualizada_at: string | null
}

export async function getMiFirma(): Promise<MiFirma> {
  const { data, error } = await supabase.rpc('rpc_mi_firma')
  if (error) throw new Error(error.message)
  return (data ?? {}) as MiFirma
}

/**
 * Guarda una firma a partir de una imagen.
 *
 * Manuel la manda como foto o PNG; el resto del sistema la captura dibujándola
 * en pantalla. Las dos terminan en lo mismo: un data URL que se sube y se
 * apunta desde el perfil.
 */
export async function guardarMiFirmaDesdeArchivo(file: File) {
  const dataUrl = await new Promise<string>((ok, fail) => {
    const r = new FileReader()
    r.onload = () => ok(String(r.result))
    r.onerror = () => fail(new Error('No se pudo leer la imagen'))
    r.readAsDataURL(file)
  })
  const { guardarMiFirma } = await import('@/lib/services/ot-recursos')
  return guardarMiFirma(dataUrl)
}

// ── Qué se le pide a quien emite ────────────────────────────────────────────
// Agrupado como está en el papel, para que el formulario se pueda ir llenando
// con el certificado anterior al lado.

export type CampoCert = { k: string; label: string; ph?: string; ancho?: 'full' }

export const GRUPOS_HERMETICIDAD: { titulo: string; nota?: string; campos: CampoCert[] }[] = [
  {
    titulo: 'El instrumento con que se midió',
    campos: [
      { k: 'instrumento_desc', label: 'Descripción', ph: 'Manómetro Análogo 0 a 15 psi (0 a 1 bar)', ancho: 'full' },
      { k: 'instrumento_marca', label: 'Marca / Modelo', ph: 'Tempres EN 837-1' },
      { k: 'rango_manometro', label: 'Rango del manómetro', ph: '0 - 15 PSI' },
    ],
  },
  {
    titulo: 'El estanque',
    nota: 'Esto no cambia entre una prueba y la siguiente: si el camión ya tuvo certificado, viene puesto.',
    campos: [
      { k: 'estanque_serie', label: 'Serie Nº', ph: '1609' },
      { k: 'anio_fabricacion', label: 'Año de fabricación', ph: 'Junio 2023' },
      { k: 'fabricante', label: 'Fabricante', ph: 'Akita SPA' },
      { k: 'propietario', label: 'Propietario', ph: 'PILLADO Y COMPAÑÍA LTDA.' },
      { k: 'propietario_direccion', label: 'Dirección del propietario', ancho: 'full' },
      { k: 'norma_revision', label: 'Norma de revisión', ph: 'DOT 406' },
      { k: 'tipo_estanque', label: 'Tipo de estanque', ph: 'Sobrecamión' },
      { k: 'capacidad_nominal', label: 'Capacidad nominal', ph: '15.000 Litros' },
      { k: 'n_compartimientos', label: 'Nº compartimientos', ph: 'UNO' },
      { k: 'cap_compartimientos', label: 'Cap. por compartimiento', ph: '15.000 Litros' },
      { k: 'numero_plano', label: 'Número de plano', ph: 'Est-c 15x5670+1030 01/02-02/02 Rev-1', ancho: 'full' },
      { k: 'especificacion_diseno', label: 'Especificación de diseño', ph: 'DOT 406 ED 2011' },
      { k: 'presion_diseno', label: 'Presión de diseño', ph: 'Atmosférica' },
      { k: 'longitud_nominal', label: 'Longitud nominal', ph: '4823 mm.' },
      { k: 'diametro_nominal', label: 'Diámetro nominal', ph: 'N. A.' },
      { k: 'ancho_nominal', label: 'Ancho nominal', ph: '2450 mm.' },
      { k: 'alto_nominal', label: 'Alto nominal', ph: '1480 mm.' },
    ],
  },
  {
    titulo: 'Mantos y cabezales',
    campos: [
      { k: 'manto_material', label: 'Manto · material', ph: 'Acero Carbono A-36' },
      { k: 'cabezal_material', label: 'Cabezal · material', ph: 'Acero Carbono A-36' },
      { k: 'manto_forma', label: 'Manto · forma o tipo', ph: 'ELÍPTICOS' },
      { k: 'cabezal_forma', label: 'Cabezal · forma o tipo', ph: 'BOMBEADO' },
      { k: 'manto_espesor', label: 'Manto · espesor', ph: '5.0 mm.' },
      { k: 'cabezal_espesor', label: 'Cabezal · espesor', ph: '5.0 mm.' },
      { k: 'union_longitudinal', label: 'Unión longitudinal manto', ph: 'Tope' },
      { k: 'union_rectangular', label: 'Unión rectangular manto', ph: 'Tope' },
      { k: 'union_manto_cabezal', label: 'Unión manto / cabezal', ph: 'Tope' },
    ],
  },
  {
    titulo: 'Cómo se hizo la prueba',
    campos: [
      { k: 'medio_deteccion', label: 'Medio de detección', ph: 'Solución de Jabón' },
      { k: 'alcance_prueba', label: 'Alcance de la prueba', ph: 'Estanque Completo' },
      { k: 'presion_prueba', label: 'Presión de prueba', ph: '3 PSI' },
      { k: 'duracion_prueba', label: 'Duración', ph: '20 Minutos' },
      { k: 'metodo_prueba', label: 'Método', ph: 'Aire Comprimido' },
      { k: 'protocolo', label: 'Protocolo de inspección', ph: 'PC 110' },
      { k: 'lugar_prueba', label: 'Lugar de la prueba', ancho: 'full',
        ph: 'Avda. Gerónimo Mendez 2125, Coquimbo.' },
    ],
  },
  {
    titulo: 'Quién firma',
    campos: [
      { k: 'firmante_nombre', label: 'Nombre', ph: 'Alejandro Monroy Ríos' },
      { k: 'firmante_titulo', label: 'Título', ph: 'Ing. Civil Mecánico' },
      { k: 'firmante_cargo', label: 'Cargo', ph: 'Jefe de Operaciones' },
    ],
  },
]

/** Sin estos el certificado no dice nada: se exigen antes de emitir. */
export const OBLIGATORIOS_HERMETICIDAD = [
  'estanque_serie', 'capacidad_nominal', 'presion_prueba', 'firmante_nombre',
]
