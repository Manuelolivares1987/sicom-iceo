// ============================================================================
// PSGCC del Inicio Seguro (MIG735) — controles críticos por EDC
// ----------------------------------------------------------------------------
// Preguntas de verificación en terreno armadas DESDE los controles de cada
// Estrategia de Control (EDC) de Minera Centinela descargadas del Campus el
// 26-11-2026. Cada pregunta lleva su fuente. No se agregan controles que no
// estén en las EDC. Catálogo inicial: lo valida prevención (Hersaly / APR).
// ============================================================================

export type EdcId = 'electrica' | 'hidraulica' | 'combustibles' | 'confinados' | 'altura'

export type ControlPsgcc = { id: string; pregunta: string; fuente: string }

export const EDC_PSGCC: Record<EdcId, { nombre: string; cuando: string; controles: ControlPsgcc[] }> = {
  electrica: {
    nombre: 'Interacción con Energía Eléctrica',
    cuando: 'Tableros, motores de bombas y surtidores, iluminación, cualquier circuito eléctrico.',
    controles: [
      { id: 'el-1', pregunta: '¿Se aisló, bloqueó (candado y tarjeta) y se comprobó energía cero con instrumento?', fuente: 'EDC Energía Eléctrica, CC1' },
      { id: 'el-2', pregunta: '¿Quien interviene es personal calificado y autorizado (credencial y en el listado de bloqueo)?', fuente: 'EDC Energía Eléctrica, CC2' },
      { id: 'el-3', pregunta: '¿Las protecciones eléctricas del equipo están operativas?', fuente: 'EDC Energía Eléctrica, CC3' },
      { id: 'el-4', pregunta: '¿Se cuenta con el equipamiento para maniobras y el instrumento de medición certificado?', fuente: 'EDC Energía Eléctrica, CC4' },
      { id: 'el-5', pregunta: '¿Se usa el EPP para trabajo eléctrico que corresponde?', fuente: 'EDC Energía Eléctrica, CC5' },
      { id: 'el-6', pregunta: '¿La puesta a tierra está conectada según el esquema definido?', fuente: 'EDC Energía Eléctrica, CC6' },
    ],
  },
  hidraulica: {
    nombre: 'Interacción con Energía Hidráulica',
    cuando: 'Bombas, líneas de presión, válvulas y actuadores hidráulicos (sala de bombas).',
    controles: [
      { id: 'hi-1', pregunta: '¿Se despresurizó el sistema siguiendo la secuencia de maniobra de válvulas?', fuente: 'EDC Energía Hidráulica, control 1' },
      { id: 'hi-2', pregunta: '¿Se verificó en el manómetro/PIT que la presión es CERO, fuera de la línea de fuego?', fuente: 'EDC Energía Hidráulica, control 2' },
      { id: 'hi-3', pregunta: '¿Los dispositivos físicos de bloqueo están en buen estado y aplicados?', fuente: 'EDC Energía Hidráulica, control 3' },
      { id: 'hi-4', pregunta: '¿El manómetro/PIT está calibrado, legible y con escala acorde a la presión?', fuente: 'EDC Energía Hidráulica, control 4' },
      { id: 'hi-5', pregunta: '¿Quien interviene está acreditado para intervenir sistemas hidráulicos?', fuente: 'EDC Energía Hidráulica, control 1 a' },
    ],
  },
  combustibles: {
    nombre: 'Manejo de Elementos Combustibles',
    cuando: 'Estanques, surtidores, líneas y filtros con combustible presente.',
    controles: [
      { id: 'co-1', pregunta: '¿Se controló la electricidad estática (medición y puesta a tierra)?', fuente: 'EDC Elementos Combustibles, control 2' },
      { id: 'co-2', pregunta: '¿Se usan herramientas antichispa?', fuente: 'EDC Elementos Combustibles, control 3' },
      { id: 'co-3', pregunta: '¿Se usa ropa antiestática?', fuente: 'EDC Elementos Combustibles, control 4' },
      { id: 'co-4', pregunta: '¿La zona de riesgo de incendio está señalizada y prohíbe elementos que generen chispa?', fuente: 'EDC Elementos Combustibles, controles 8 y 9' },
      { id: 'co-5', pregunta: '¿El supervisor confirmó los resguardos de la tarea?', fuente: 'EDC Elementos Combustibles, controles 10 y 11' },
    ],
  },
  confinados: {
    nombre: 'Trabajos en Espacios Confinados',
    cuando: 'Ingreso a estanques, fosas o cámaras.',
    controles: [
      { id: 'cf-1', pregunta: '¿Las energías del sistema están bloqueadas?', fuente: 'EDC Espacios Confinados, control 3' },
      { id: 'cf-2', pregunta: '¿Están identificados los puntos de acceso y evacuación?', fuente: 'EDC Espacios Confinados, control 4' },
      { id: 'cf-3', pregunta: '¿Se usa la protección respiratoria que corresponde?', fuente: 'EDC Espacios Confinados, control 5' },
      { id: 'cf-4', pregunta: '¿Hay vigía de espacio confinado?', fuente: 'EDC Espacios Confinados, control 9' },
      { id: 'cf-5', pregunta: '¿Trabajan mínimo dos personas?', fuente: 'EDC Espacios Confinados, control 11' },
      { id: 'cf-6', pregunta: '¿Están disponibles los elementos y equipos de rescate?', fuente: 'EDC Espacios Confinados, controles 13 y 14' },
      { id: 'cf-7', pregunta: '¿El trabajador está acreditado y en condiciones físicas y psicológicas aptas?', fuente: 'EDC Espacios Confinados, control 2' },
    ],
  },
  altura: {
    nombre: 'Trabajos en Altura (desde 1,8 m)',
    cuando: 'Techos de salas, estanques, plataformas, escalas.',
    controles: [
      { id: 'al-1', pregunta: '¿El anclaje es un punto certificado?', fuente: 'EDC Trabajos en Altura, CC1' },
      { id: 'al-2', pregunta: '¿El arnés (SPDC) está certificado, con TAG y revisado antes de usar?', fuente: 'EDC Trabajos en Altura, CC2' },
      { id: 'al-3', pregunta: 'Sobre 5 m: ¿se usa amortiguador y sistema antitrauma?', fuente: 'EDC Trabajos en Altura, CC3' },
      { id: 'al-4', pregunta: '¿Los vanos tienen doble baranda rígida con rodapié?', fuente: 'EDC Trabajos en Altura, CC4' },
      { id: 'al-5', pregunta: '¿La plataforma o andamio está certificado y con tarjeta verde?', fuente: 'EDC Trabajos en Altura, CC5' },
      { id: 'al-6', pregunta: '¿El personal está calificado (OTEC) para trabajar en altura?', fuente: 'EDC Trabajos en Altura, CC6' },
    ],
  },
}

export const ENERGIAS = [
  { id: 'electrica', nombre: 'Eléctrica' },
  { id: 'hidraulica', nombre: 'Hidráulica' },
  { id: 'combustible', nombre: 'Combustible (válvula)' },
  { id: 'neumatica', nombre: 'Neumática' },
] as const
