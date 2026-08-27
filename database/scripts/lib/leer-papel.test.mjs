// ============================================================================
// Casos reales de la flota. Todos salieron de papeles que existen.
// ----------------------------------------------------------------------------
// Los tres primeros bloques son los errores que se pagaron caro: la
// hermeticidad que se leía mal, la póliza cuya tabla de cuotas se tomaba por
// vigencia, y el SOAP que declara su vigencia sin usar la palabra.
//
//   node database/scripts/lib/leer-papel.test.mjs
// ============================================================================
import { veredicto, emisionDeclarada, fechasDe } from './leer-papel.mjs'

let ok = 0, fallos = []
const test = (nombre, fn) => {
  try { fn(); ok++ } catch (e) { fallos.push(`${nombre}: ${e.message}`) }
}
const igual = (a, b, q) => { if (a !== b) throw new Error(`${q ?? ''} esperaba ${b}, dio ${a}`) }

// ── La hermeticidad: la fecha del vencimiento va después de la palabra ──────
// DJKL-18, Certificado Nº 12/2025. La trampa: la línea de inspección y la de
// vencimiento son parecidas y están juntas.
test('hermeticidad DJKL-18', () => {
  const l = [
    'Lugar de la prueba : Avda. Gerónimo Mendez 2125, Coquimbo.',
    'Fecha de inspección : 29 de diciembre de 2025',
    'Fecha de vencimiento : 29 de junio de 2026',
  ]
  igual(veredicto(l).vencimiento, '2026-06-29', 'vencimiento')
  igual(emisionDeclarada(l).fecha, '2025-12-29', 'emisión')
})

test('hermeticidad DCHD-83 con día de la semana', () => {
  const l = [
    'Fecha de inspección martes, 27 de enero de 2026',
    'Fecha de vencimiento lunes, 27 de julio de 2026',
  ]
  igual(veredicto(l).vencimiento, '2026-07-27')
  igual(emisionDeclarada(l).fecha, '2026-01-27')
})

// ── La póliza: la tabla de cuotas NO es la vigencia ─────────────────────────
// Tres camiones compartían «vencimiento» 2014-12-29: era la cuota del pagaré.
test('tabla de cuotas no es vigencia', () => {
  const l = [
    'PÓLIZA N° 8783721-1 Ramo : VEHICULOS COMERCIALES',
    'Tipo Nro. Sec. Vencimiento Situación Valor 1/10 20-02-2023 PAGADO 1,73',
  ]
  igual(veredicto(l).veredicto, 'NO_DECLARA', 'no debe leer la cuota como vigencia')
})

// ── El SOAP: declara su vigencia sin decir «vencimiento» ───────────────────
// Cabecera con los títulos, fila de abajo con las fechas. La que vale es la
// SEGUNDA: la primera es cuándo empieza a regir.
test('SOAP con cabecera RIGE DESDE / HASTA', () => {
  const l = [
    'MODELO AÑO RUT RIGE DESDE HASTA 9738411860DCHD83',
    'Canter 7.5 2011 77316540-8 01/10/2025 30/09/2026',
    'NUMERO DE MOTOR PRIMA',
  ]
  const v = veredicto(l)
  igual(v.veredicto, 'DECLARA')
  igual(v.vencimiento, '2026-09-30', 'debe tomar la segunda fecha, no la primera')
})

test('SOAP: «permanente» de la cobertura no es una declaración de vigencia', () => {
  const l = [
    'IMPORTANTE COBERTURA : El SOAP cubre la muerte, En el caso de incapacidad permanente parcial, los pagos',
  ]
  const v = veredicto(l)
  if (v.regla === 'dice_que_no_vence') throw new Error('confundió la cobertura con la vigencia')
})

// ── Casos que sí deben dar «no declara» ────────────────────────────────────
test('certificado de taller sin vigencia declarada', () => {
  const l = [
    'CERTIFICADO DE TORQUE DE RUEDAS',
    'Coquimbo, 03 de noviembre de 2025',
    'Se certifica que se aplicó el torque especificado por el fabricante.',
  ]
  igual(veredicto(l).veredicto, 'NO_DECLARA')
})

test('documento que dice que no caduca', () => {
  const l = ['El presente certificado tiene vigencia indefinida.']
  const v = veredicto(l)
  igual(v.veredicto, 'NO_DECLARA')
  igual(v.regla, 'dice_que_no_vence')
})

test('escaneo sin texto', () => {
  igual(veredicto([]).veredicto, 'ILEGIBLE')
  igual(veredicto(['', '  ']).veredicto, 'ILEGIBLE')
})

// ── Formatos de fecha ──────────────────────────────────────────────────────
test('formatos', () => {
  igual(fechasDe('vence el 29/06/2026')[0].fecha, '2026-06-29')
  igual(fechasDe('vence el 29-06-2026')[0].fecha, '2026-06-29')
  igual(fechasDe('2026-06-29')[0].fecha, '2026-06-29')
  igual(fechasDe('2026-06-29').length, 1, 'el ISO no debe leerse ademas como 26-06-29')
  igual(fechasDe('29 de junio de 2026')[0].fecha, '2026-06-29')
  igual(fechasDe('vigente hasta junio 2026')[0].fecha, '2026-06-30', 'mes sin día = fin de mes')
})

test('no inventa fechas de números sueltos', () => {
  igual(fechasDe('RUT 77.316.540-8 motor 4M50D62846').length, 0)
  igual(fechasDe('Canter 7.5 2011').length, 0)
})

test('rango desde/hasta en una sola línea', () => {
  const l = ['VIGENCIA: desde 01/10/2025 hasta 30/09/2026']
  igual(veredicto(l).vencimiento, '2026-09-30')
})


// ── La revisión técnica chilena ────────────────────────────────────────────
// Declara la vigencia como MES AÑO, y en la misma línea va el sello de la
// firma electrónica con su hora. El lector tomaba el sello: 15 revisiones
// técnicas quedaron con la fecha de la firma en vez de la de vigencia.
test('RT: mes y año, no el sello de la firma', () => {
  const l = ['FIRMA ELECTRONICA AVANZADA VALIDO HASTA SEPTIEMBRE 2026 22/10/2025 12:20:25 2GDG353588']
  const v = veredicto(l)
  igual(v.veredicto, 'DECLARA')
  igual(v.vencimiento, '2026-09-30', 'debe ser fin del mes declarado')
})

test('RT: dia mes año sin los «de»', () => {
  const l = ['REVISION TECNICA VALIDA HASTA: RESULTADO: FIRMA ELECTRONICA AVANZADA',
             '14 MAYO 2026 14/11/2025 10:31:39']
  igual(veredicto(l).vencimiento, '2026-05-14')
})

test('el sello de firma no se toma como vigencia', () => {
  const f = fechasDe('14/11/2025 10:31:39')
  igual(f.length, 1)
  igual(f[0].sello, true)
})

test('una fecha sin hora no es un sello', () => {
  igual(!!fechasDe('vence el 29/06/2026')[0].sello, false)
})

test('«29 de junio de 2026» no se cuenta ademas como «junio 2026»', () => {
  igual(fechasDe('Fecha de vencimiento : 29 de junio de 2026').length, 1)
})


// ── Los cuatro casos que aparecieron al contrastar contra los 871 ──────────

test('SOAP con las columnas impresas al reves: vale la fecha MAYOR', () => {
  // KVWW-68. La columna HASTA quedó impresa antes que DESDE; «la última
  // fecha» daba el inicio de vigencia.
  const l = ['ANO RIGE DESDE HASTA MODELO RUT 30/09/2026 Actros 3336 K 2019 01/10/2025 97036000-K']
  igual(veredicto(l).vencimiento, '2026-09-30')
})

test('RT donde solo queda el sello: no se reporta como vigencia', () => {
  // TGGF-56. La vigencia está en el timbre (imagen); en el texto sólo queda la
  // hora de la firma.
  const l = ['REVISION TECNICA VALIDA HASTA: FIRMA ELECTRONICA AVANZADA', '04/03/2026 12:55:25 o']
  igual(veredicto(l).veredicto, 'NO_DECLARA', 'mejor decir que no se pudo leer')
})

test('cuadro de cuotas sin la palabra cuota en la cabecera', () => {
  // GCSY-66 y SPRY-29: la cabecera dice «Tipo Nro. Sec. Vencimiento», y la
  // fila delata el cuadro con PAGADO / PENDIENTE.
  const l = ['Tipo Nro. Sec. Vencimiento Situacion Valor', '1/10 20-02-2023 PAGADO 1,73']
  igual(veredicto(l).veredicto, 'NO_DECLARA')
  const l2 = ['Tipo Nro. Sec. Vencimiento Situacion Valor', '1/6 20-03-2023 PENDIENTE 2,55']
  igual(veredicto(l2).veredicto, 'NO_DECLARA')
})

test('una factura no vence: no se le busca vencimiento', () => {
  // SVCZ-38: la letra chica sobre intereses de mora daba «vencimiento 2008».
  const l = ['hasta su cobraran fecha de intereses vencimiento. Res 142 de 30-10-2008']
  igual(veredicto(l, 'factura_compra').veredicto, 'NO_CADUCA')
  igual(veredicto(l, 'padron').veredicto, 'NO_CADUCA')
  // pero un tipo que sí caduca se sigue analizando
  igual(veredicto(['Fecha de vencimiento : 29 de junio de 2026'], 'hermeticidad').vencimiento, '2026-06-29')
})

// ── Resultado ──────────────────────────────────────────────────────────────
console.log(`\n${ok} casos pasan, ${fallos.length} fallan`)
for (const f of fallos) console.log('  ✗ ' + f)
process.exit(fallos.length ? 1 : 0)
