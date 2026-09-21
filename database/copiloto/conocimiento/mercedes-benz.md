# Mercedes-Benz — Conocimiento técnico para diagnóstico (flota Pillado)

Flota cubierta (13 camiones):
- Actros 3341 6x4 (2012-2013), VIN WDB930…, motor 541.9xx (= OM 501 LA V6), aljibe combustible.
- Actros 3336 K 6x4 (2017-2019), VIN WDB932…, motor 541.9xx (OM 501 LA), serie 932 "fora de estrada", riego/agua industrial.
- Axor 2633 / 2633-45 (2016-2017), VIN WDF950…, motor 926.9xx (= OM 926 LA), aljibe.
- Atego 1624 A 4x4 (2013), VIN WDB970…, motor "902916" (familia NO confirmada con fuente, ver ficha correspondiente), aljibe 5 kL.
- Accelo 1016 (2018, 2022), VIN 9BM979…, motor 924.9xx (= OM 924 LA Euro 5), aljibe y carrocería.

Nota general de fuentes: los manuales de operación/mantención "Mercedes Brasil" citados se descargaron del portal oficial
https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (copias locales en `_Descargados oficiales 2026-09/Mercedes Brasil`).
Los "Manuales de Implementação" (guías para carroceros) están en `_Investigacion web 2026-09-19/Mercedes-Benz/` con su URL en `_descargas.json`.
Los esquemas eléctricos de taller completos, pinouts de MR/FR/GS y tablas de códigos MR/FR/GS de 4 dígitos
**requieren licencia: Mercedes-Benz XENTRY / WIS (o bases comerciales Jaltest, Texa, Noregon JPRO)**; no se publicaron aquí valores que no tengan fuente.

---

## [general] Identificación de familia de motor por el número de motor Mercedes
- Aplica: Mercedes-Benz Actros 3341 / 3336K, Axor 2633, Accelo 1016 (toda la flota)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: esquema MR "Motor 924.9, 926.9 con Código (MS5) BlueTec 5" en https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (Manual de Implementação Atego Euro 5, pág. 347 del PDF, esquema PE07.15-B-2002KB)

Los primeros dígitos del número de motor Mercedes corresponden al tipo de motor (código de agregado). Solo 924.9 y 926.9 están confirmados en el documento citado; el resto es nomenclatura habitual Mercedes **sin fuente pública verificada: confirmar en la placa del motor / EPC**.
| Nº motor flota | Tipo | Motor comercial |
|---|---|---|
| 924.9xx (Accelo) | 924.9 | OM 924 LA — confirmado: el esquema oficial MR rotula "Motor 924.9, 926.9" |
| 926.919 / 926.945 (Axor) | 926.9 | OM 926 LA — confirmado (misma fuente) |
| 541.9xx (Actros 3341 y 3336K) | 541.9 | OM 501 LA (V6), familia PLD con MR — no verificado con fuente pública |
| 902.916 (Atego 1624A) | — | NO verificado: el prefijo 902 no aparece en ninguna fuente pública revisada. Verificar placa del motor / EPC. Las fichas de Atego 1624/1725 4x4 de esa época publicadas en internet indican OM 906 LA, pero sin fuente oficial para este VIN. |

Mercedes identifica también el módulo FR por número de pieza en el tablero (ver ficha "Leer número del módulo FR/CPC en el tablero").

## [electrico] Arquitectura electrónica Atego/Axor/Accelo Brasil (serie 958 / 979): unidades de control y red CAN
- Aplica: Mercedes-Benz Atego 958 (Brasil), Axor 958, Accelo 979, Euro 5 BlueTec 5 (2012-2019); por analogía Axor 2633 2016-17 y Accelo 1016 2018/2022
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (Manual de Implementação Atego Euro 5, esquema "Punto neutro CAN" PE54.18-B-2000CA, Tipo 958.0, pág. 364 del PDF)

Unidades de control (designación del esquema oficial):
| Código | Unidad | Red |
|---|---|---|
| A3 | FR – regulación de marcha (control vehículo) | CAN 1 (vehículo) |
| A6 | MR – regulación del motor (PLD) | CAN 12 (SCR) + CAN 4 (motor) |
| A7 | GM – Módulo básico (central eléctrica, fusibles/relés) | — |
| A10 | ABS | CAN 1 |
| A22 | PSM – módulo especial parametrizable (carrocero) | CAN 1 y CAN 9 (telemática) |
| A30 | WS – sistema de mantenimiento | CAN 1 |
| A95 | Módulo de bastidor SCR | CAN 12 |
| P2 | INS – instrumento | CAN 1 |
| X13 | Toma de diagnóstico | CAN 1 (y CAN 12 en BlueTec) |
| Z1 | Punto neutro (estrella) CAN cabina-antepecho | — |
| Z3 | Punto neutro CAN adicional (SCR) | — |

Redes: CAN 1 = CAN del vehículo; CAN 4 = CAN del motor; CAN 9 = CAN de telemática; CAN 12 = CAN SCR (válido BlueTec 4/5, variante U444).
Colores de cable CAN 1 en el esquema: High = bl (azul), Low = ge (amarillo), sección 0,75 mm². CAN 12 usa pares gr/ws – gr/gn con GND (gr/bl, gr/br).
La conexión física entre módulos es en estrella (Z1), no en línea: un corto en un ramal tumba toda la red; desconectar ramales en Z1 uno a uno para aislar.

## [electrico] Punto neutro CAN (Z1/Z3): pines por módulo (Atego 958 Euro 5)
- Aplica: Mercedes-Benz Atego 958 Brasil Euro 5 (esquema 02/2010); referencia para Axor/Accelo misma plataforma
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (esquema PE54.18-B-2000CA "Punto neutro CAN", pág. 364 del PDF)

| Módulo | Conector/pin HIGH | Conector/pin LOW | Red |
|---|---|---|---|
| A3 FR | X2 18/18 | X2 18/16 | CAN 1 |
| P2 INS | X1 18/9 | X1 18/18 | CAN 1 |
| A10 ABS (hasta 10/2007) | X1 18/3 | X1 18/1 | CAN 1 |
| A10 ABS (desde 11/2007) | X1 18/8 | X1 18/7 | CAN 1 |
| A30 WS | X1 18/1 | X1 18/3 | CAN 1 |
| X13 diagnóstico | pin 6 | pin 14 | CAN 1 |
| A22 PSM | X3 15/15 | X3 15/13 | CAN 9 (en esquema PSM: CAN 1 en X3, ver ficha PSM) |
| A95 SCR | X3 62/11 (GND 62/5, 62/9) | X3 62/16 | CAN 12 |
| A6 MR | X3 16/7 (GND 16/14, 16/16) | X3 16/10 | CAN 12 |
Masa del punto neutro Z1: X1 18/2 → XB.31.R (soldadura masa derecha) / perno XX.31.2.
Uso en diagnóstico: con llave OFF y baterías desconectadas medir resistencia entre High y Low en la toma X13 pines 6-14 (ver ficha "Resistencia CAN").

## [electrico] Toma de diagnóstico X13 (16 pines): asignación de pines (Atego/Axor/Accelo 958/979 Euro 5)
- Aplica: Mercedes-Benz Atego 958 Brasil (esquema 02/2010), plataforma común Axor/Accelo Euro 5
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (esquema PE54.22-B-2000EA "Acoplamiento de comprobación para diagnós", pág. 372 del PDF)

| Pin X13 | Señal | Origen |
|---|---|---|
| 4, 5 | Masa (br, 0,75) | XB.31.L / perno XX.31.1 |
| 6 | CAN High (bl) | Z1 X1 18/16 (CAN 1); en BlueTec 4/5 también Z3 (CAN 12) |
| 14 | CAN Low (ge) | Z1 X1 18/18 (CAN 1); en BlueTec 4/5 también Z3 (CAN 12) |
| 7 | Línea K diagnóstico (gr/sw/ws) | ZV A23, FFB A43, INS P2 vía XB.1 |
| 8 | Borne 15 (bl/sw/ws) | Fusible F39-A7 10 A (GM X5 9/5) |
| 9 | Línea diagnóstico MR (li/ge) | A6 MR X1 16/13 vía X2.2 18/6 |
| 16 | Borne 30 (rt/bl) | Fusible F10-A7 10 A (GM X1 12/10), también alimenta INS X1 18/2 |
Chequeo rápido sin escáner: con llave ON, pin 16 y pin 8 deben tener tensión de batería respecto a pines 4/5. Si el escáner no enciende, revisar F10 (borne 30) y F39 (borne 15) en la central.

## [electrico] Módulo MR (PLD): ubicación, conectores y precauciones (Atego/Axor/Accelo Brasil)
- Aplica: Mercedes-Benz Atego 958, Axor, Accelo Euro 5 con OM 924 LA / OM 926 LA (PLD/MR)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://salandingpagespaasprod.blob.core.windows.net/institutional-public/storage/assets/gallery/docs/bmd-br000002ce1.pdf (Diretrizes Atego 958.1XX Parte Eletroeletrônica, 01.06.2017, cap. 2.9, pág. 33)

- A6 = Módulo MR ("Gerenciamento do motor PLD"). Está en el costado del motor.
- Conexión a sensores del motor: conector de **55 vías**; conexión al vehículo: conector de **16 vías**.
- El MR tiene un **sensor de presión atmosférica en su placa**, con entrada de aire en la parte trasera del módulo: no taparla ni lavarla a presión.
- Controla el tiempo de inyección en las unidades inyectoras (bomba-tubo-inyector) Y6…Y11 (cilindros 1…6).
- Desmontaje de conectores: se sueltan a mano levantando la traba amarilla, nunca con herramientas (manual de implementación Accelo Euro 5, cap. 5.1.2).
- El cableado del motor (conector 55 vías) **no está protegido contra cortocircuito a positivo**: un corto puede dañar el MR (Manual de Operación Axor Euro 5, "Gestión electrónica del motor").
- No conectar/desconectar MR ni FR con borne 15 activo (llave en posición marcha).

## [electrico] Componentes del esquema MR (PLD) OM 924/926 BlueTec 5: lista de sensores y actuadores
- Aplica: Mercedes-Benz Atego 958 / Axor / Accelo con motor 924.9 / 926.9 BlueTec 5 (código MS5)
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (esquema PE07.15-B-2002KB "Regulación del motor (MR)", pág. 347 del PDF)

Designaciones del esquema oficial (útil para interpretar mensajes y buscar en el motor):
| Ref. | Componente |
|---|---|
| B10 | Sensor temperatura combustible |
| B11 | Sensor temperatura aceite motor |
| B12 | Sensor presión aceite |
| B14 | Sensor nivel aceite |
| B15 | Sensor posición cigüeñal |
| B16 | Sensor posición árbol de levas |
| B65 | Sensor temperatura refrigerante |
| B104 | Sensor rpm turbina (turbo) |
| B111 | Sensor combinado temperatura/presión aire de sobrealimentación |
| B122 | Sensor rpm acoplamiento ventilador |
| B128 | Sensor presión aire comprimido |
| B129 | Sensor presión AdBlue (SCR) |
| B130 | Sensor temperatura AdBlue (SCR) |
| Y6…Y11 | Unidad bomba-inyector cilindro 1…6 (Y6-Y9 en motor 4 cil.) |
| Y49 | Válvula estranguladora constante (freno motor) |
| Y70 / Y71 | Válvulas ventilador velocidad 1 / 2 |
| Y87 | Convertidor electroneumático (EPW) |
| Y107 | Válvula calefacción estanque (SCR) |
| Y109 | Válvula dosificadora AdBlue SCR |
| R21 | Elemento calefactor precalentamiento aire admisión (FLA, módulo A4) |
| S10 / S11 | Pulsador arranque / parada del motor (en motor) |
| A42 | Electrónica lectura inmovilizador |
| F30-A7 | Fusible regulación motor (MR) borne 15 |
| G2 / M1 | Alternador / motor de arranque |
Los números de pin del conector X2 (55 vías) del esquema no son legibles con calidad suficiente en el PDF público; para pinout exacto usar WIS (requiere licencia).

## [electrico] Arquitectura electrónica Actros MP3 / serie 932 (off-road): abreviaturas de sistemas en el tablero
- Aplica: Mercedes-Benz Actros 3336 K (serie 932, 2017-2019); por analogía Actros MP2/MP3 3341 (serie 930)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, ed. 09/2017, "Abreviaturas dos sistemas electrónicos", pág. 121-122)

El computador de a bordo identifica la unidad en falla con estas abreviaturas:
ABA (asistente activo de frenado), ABS, AG (selección automática de marchas), APU (Air Processing Unit – secador/regulador electrónico), ART (control de distancia), BS (sistema de frenos Telligent = EBS), BTS (desconectador de baterías), EAB (freno remolque electrónico), FLA (ayuda arranque en frío), FM (módulo delantero), **FR (regulación de marcha)**, **GS/"Comando da caixa" (control de caja Telligent)**, HM (módulo trasero), HPS (sistema de cambio mecánico), HZR (calefacción/AC), KB (accionamiento embrague), KOM (interfaz comunicación), KS (control embrague), KSA (cierre confort), **MR (regulación motor Telligent)**, MSF (zona modular de interruptores), NR (regulación de nivel de suspensión), **PSM (módulo especial parametrizable)**, RAD (radio/navegación), RS (control retarder), **SCR (postratamiento BlueTec)**, SPA (asistente de trayectoria), SRS (airbag), TCO (tacógrafo), TEL, TK (embrague hidráulico/turboembrague), TMB/TMF (módulos de puerta acompañante/conductor), TP (plataforma telemática), WR (amortiguación de oscilaciones), WS (mantenimiento Telligent), WSK (embrague del convertidor), ZDS (memoria central de datos), ZHE (calefacción adicional), ZL (eje arrastrado).
Los mensajes muestran además el lugar de la falla: tractor o remolque.

## [electrico] Leer fallas memorizadas en el tablero sin escáner — Actros 932 (MP3 off-road)
- Aplica: Mercedes-Benz Actros 3336 K serie 932 (2017-2019); procedimiento análogo en Actros MP2/MP3 3341 con volante multifunción
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, 09/2017, "Validar os menus Diagnóstico", pág. 117 y "Menu Diagnóstico", pág. 119-122)

1. El menú "Diagnóstico" **no viene habilitado de fábrica**. Habilitar: teclas del volante `V/U` → **Definições** → `W/X` **Configuração** → `&/*` **Validar menu diag.** → `W/X` **Ligar**.
2. Consultar: `V/U` → **Diagnóstico** → `W/X` **Inform. de controlo** (mensajes ya confirmados) o **Diagnóstico** (lista de todas las unidades de control montadas y datos para el taller).
3. Mensajes en pantalla: franja de estado **blanca** (información/estado especial), **amarilla** (falla de baja prioridad, p.ej. ampolleta; también toma de fuerza activa), **roja** (falla de alta prioridad, p.ej. alternador). Si además se enciende la luz **STOP**: detener, freno de estacionamiento, apagar motor.
4. Cada mensaje muestra: abreviatura del sistema (ver ficha de abreviaturas), lugar de falla (tractor/remolque), restricción de funcionamiento e instrucción. Confirmar con tecla T, V o U; si la causa persiste el mensaje reaparece en el siguiente arranque.
5. En el mismo menú Definições se habilita "Serv. reserva cmd. cx. veloc." (modo emergencia de la caja), ver ficha GS.
Los códigos numéricos detallados MR/FR/GS de 4-5 dígitos solo se leen con XENTRY/Star Diagnosis (requiere licencia).

## [electrico] Leer eventos y diagnóstico en el tablero INS2014 — Axor / Atego / Accelo Euro 5
- Aplica: Mercedes-Benz Axor 2633 (2016-17), Atego Euro 5, Accelo 1016 Euro 5 con computador de a bordo INS2014
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Axor Euro 5, ES, ed. V, "Menú Eventos y Diagnóstico", pág. 106; mismo menú en Manual de Operación Accelo Euro 5, pág. 90)

1. Con las teclas del volante `V/U` ir al menú **"Eventos y Diagnóstico"**.
2. `&/*` → **Eventos** → `W/X` **Mensajes en el monitor**: se ven los mensajes almacenados (primero y último). En modo evento se muestra solo la abreviatura del sistema / símbolo y el lugar de falla en rojo o amarillo. Si la causa se eliminó, el mensaje desaparece.
3. `&/*` → **Diagnóstico**: lista de todas las unidades de mando instaladas en el vehículo (información para taller).
4. Colores: segmento amarillo = seguir con restricciones y llevar a taller; rojo = detener.
5. Luz de diagnóstico del motor (MIL) — ver ficha "Luz diagnóstico motor BlueTec".
Los códigos numéricos de falla de cada unidad (MR, FR, ABS, SCR) no se despliegan como tabla en el INS; se requiere escáner (XENTRY – licencia; o Jaltest/Texa).

## [electrico] Leer número del módulo FR/CPC en el tablero (identificar versión Light / MPS)
- Aplica: Mercedes-Benz Axor, Atego, Accelo Brasil Euro 3/5
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (Manual de Implementação Atego Euro 5, cap. 6.15, pág. 130); Axor: https://web.archive.org/web/2015/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/axor/manual-de-implementacao/manual-de-implementacao-euro-3-axor-es.pdf (cap. 6.14, pág. 137)

- Pulsar la tecla de selección del instrumento ("Exibir menus de informação") hasta que aparezca el símbolo **"FR"** (o "FR/CPC") y el **número de pieza del módulo** (ejemplos del manual: 002 446 18 02 Atego/Accelo; 001 446 12 02 Axor).
- Con ese número, el concesionario (EPC) informa la versión: **"Light"** (sin control de rpm variable) o **"MPS"** (permite control de rotación para toma de fuerza).
- Útil antes de programar ralentí de bomba o reemplazar un FR (el reemplazo debe llevar la misma versión/parametrización).

## [electrico] Mensaje "CODE" o "MR" al arrancar (inmovilizador) — Accelo
- Aplica: Mercedes-Benz Accelo Euro 5 (y plataforma INS2014)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Accelo Euro 5, ES, ed. S, pág. 171-172)

- Si no se respeta el tiempo de espera o se usa una llave no válida, el computador de a bordo muestra **CODE** o **MR** y el segmento de estado en **amarillo**; el arranque queda bloqueado.
- Remedio: volver la llave a desconectado, luego a marcha; el arranque se puede accionar **tras 2 s de espera** o cuando deja de sonar la chicharra.
- Tras **5 intentos con llave no válida**, el segmento pasa a **rojo** y el tiempo de espera aumenta **1 minuto por cada intento**; la llave debe quedar en posición marcha durante la espera.
- Después de 3 intentos de arranque fallidos, esperar ~3 minutos antes de reintentar. Arrancar con baterías bajas insistiendo puede dañar la gestión electrónica.

## [transmision] Caja Telligent / Mercedes PowerShift (GS): proceso de sincronización pequeño y grande
- Aplica: Mercedes-Benz Actros 3336 K / 3341 con caja automatizada Telligent (EPS) o Mercedes PowerShift; Axor/Atego con PowerShift
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, 09/2017, "Processo de sincronização", pág. 188-190; Manual de Operación Axor Euro 5, ES, pág. 330-333)

Cuándo:
- **Pequeño**: tras cambiar sensores de la caja en el embrague o el embrague.
- **Grande**: se reemplazó la unidad GS, se reemplazó el motor, o el visor muestra **código de falla "2 1011"** (girar llave a OFF, esperar ~5 s, llave a marcha) o **"2 8093"**.
Requisitos: presión de reserva suficiente (si no, aparece aviso), freno de estacionamiento aplicado.

Telligent con pedal de embrague – pequeño: llave OFF → pisar embrague a fondo y mantener → mantener tecla de punto muerto → llave a marcha (suena señal y ruido de engrane; flechas del divisor parpadean) → soltar embrague dentro de 3 s → pisar a fondo dentro de 3 s y mantener → al aparecer **N** termina → soltar embrague y tecla N.
Telligent – grande: igual pero con **tecla de punto muerto + tecla de conmutación** simultáneas; al aparecer **N** arrancar el motor y repetir el ciclo soltar/pisar embrague (3 s) hasta **N grande**.
PowerShift / Telligent automático – pequeño: llave OFF → mantener tecla N → llave marcha → cuando aparece **N pequeño** arrancar motor → termina con **N grande**.
PowerShift – grande: tecla N + tecla de conmutación → llave marcha → **N pequeño** → arrancar → **N grande**.
Si falla la sincronización grande: activar el servicio de reserva (modo emergencia) y llevar a taller.
Los códigos de sincronización (GS 01…GS 32) **no se memorizan**: anotarlos para el taller (ver JSON).

## [transmision] Servicio de reserva del comando de caja (modo emergencia GS) — Actros
- Aplica: Mercedes-Benz Actros 932 / MP3 con Telligent o PowerShift
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, 09/2017, pág. 191-192)

Si el sistema de cambio está averiado se puede seguir en modo reserva: marcha lenta o rápida, marcha atrás, punto muerto, modo remolque; **no se cambia en movimiento**.
1. Detener fuera del tránsito, freno de estacionamiento, motor en marcha.
2. Volante: `V/U` Ajustes → `W/X` Configuração → `&/*` **Validar serv. res. cmd. cx. veloc.** → `W/X` **Ligar**. Queda habilitado mientras la llave esté en marcha; al girar la llave a tope atrás se bloquea de nuevo.
3. Con Telligent: confirmar con & o *, el visor pide "Carregar embraiagem" → pisar a fondo → confirmar con W → confirmar de nuevo & o *; la caja engrana.
4. Con caja fría puede no mostrarse la marcha seleccionada: repetir; si persiste, apagar y reactivar.

## [transmision] Caja automática: leer códigos de 5 dígitos en el selector por teclas
- Aplica: Mercedes-Benz Axor / Atego / Accelo Euro 5 con caja automática y selector por teclas
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Axor Euro 5, ES, "Sistema de engrane averiado", pág. 137; igual en Atego Euro 5 y Accelo Euro 5)

- Pulsar **dos veces y simultáneamente** las teclas `&` (flecha arriba) y `*` (flecha abajo) del selector por teclas.
- El visor del selector muestra los **códigos de falla de 5 dígitos**; tecla **MODE** = siguiente código. Se memorizan **máximo 5** códigos.
- Salir: pulsar `&` y `*` simultáneamente, o poner la caja en neutro.
- También visibles en el submenú **Diagnóstico** del computador de a bordo.
(No aplica a cajas manuales ni a Telligent; para Allison la tabla de significados es del fabricante de la caja.)

## [transmision] Mensaje "Sistema de engranaje averiado" / "Sist. regul. régimen de marcha con daños"
- Aplica: Mercedes-Benz Axor Euro 5 (INS2014), plataforma Atego/Accelo
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Axor Euro 5, ES, "Indicaciones del monitor", pág. 135-137)

- "Pres. res. caj. cam./embr. muy baja": presión de reserva del circuito de caja/embrague muy baja → ya no se acoplan marchas correctamente. Detener, freno estacionamiento, dejar motor en marcha hasta que el mensaje se apague; si ocurre de repente, revisar fugas del circuito de aire.
- "Sistema regul. régimen de marcha con daños" (texto: Visitar el taller) = falla en el **FR**.
- "Motor averiado": falla en motor, refrigeración, gestión del motor o inyección.
- "Refrigeración del motor averiada": revisar correa trapezoidal dentada (deteriorada o tensión insuficiente).
- "Sistema de engranaje averiado": falla del sistema de cambio; se puede seguir con restricciones.
- "Temp. líquido refrigerante muy elevada" / "Protección del motor: potencia reducida": el MR reduce potencia; bajar marcha o detener, limpiar rejilla del radiador.

## [postratamiento] Luz de diagnóstico del motor (MIL) BlueTec 5: parpadea vs fija
- Aplica: Mercedes-Benz Actros 932 Euro 5, Axor / Atego / Accelo Euro 5 BlueTec 5 (SCR con AdBlue/ARLA 32)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, pág. 141; Manual de Operación Accelo Euro 5, ES, pág. 144)

| Estado | Significado | Acción |
|---|---|---|
| Se enciende breve al dar contacto y se apaga | Test de lámparas, sin falla | — |
| **Parpadea** + mensaje con estado rojo | AdBlue agotado **o** existe una falla; la potencia puede reducirse | Seguir instrucciones del visor; cargar AdBlue |
| **Fija** | Postratamiento BlueTec averiado o falla relevante para emisiones; puede reducir potencia | Revisar SCR de inmediato |
Tras cargar AdBlue o eliminar la falla vuelve la potencia completa; la lámpara se apaga cuando el autodiagnóstico ya no detecta error, **lo que puede tardar varios viajes**.

## [postratamiento] BlueTec 5: sistema de limpieza de cañerías de AdBlue al apagar y desconectador de baterías
- Aplica: Mercedes-Benz Atego / Atron / Accelo / Axor BlueTec 5 (Proconve P7 / Euro 5)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (Manual de Implementação Atego Euro 5, cap. 6.13, pág. 125-126)

- Tras apagar el motor, el sistema sopla aire para limpiar cañerías, válvulas, bomba dosificadora e inyector de AdBlue.
- Sin llave general: si se alcanzaron condiciones de inyección, **5 pulsos de aire de 30 s con intervalos de 15 s**. Si no se alcanzaron, no limpia.
- Con llave general (kit de válvula solenoide + estanque auxiliar 5,4 L): tras los 5 pulsos, pulso continuo hasta vaciar el estanque auxiliar (~4 min si no hubo inyección).
- **No se admite instalar un corta-corriente interrumpiendo el cable de batería en BlueTec 5**: impide la limpieza y daña el sistema de inyección de AdBlue (cristalización). En faena: no cortar baterías inmediatamente tras apagar; esperar el ciclo de limpieza.

## [postratamiento] Módulo SCR y sensores: ubicación y prohibición de empalmes
- Aplica: Mercedes-Benz Atego / Accelo / Axor BlueTec 5 Brasil
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (cap. 3.7.6-3.7.7, pág. 40-43); Accelo: https://web.archive.org/web/20140813205332/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/accelo/manual-de-implementacao/manual-de-implementacao-euro-5-accelo-pt.pdf (cap. 5.1.2, pág. 64)

- Atego: módulo SCR en el interior del larguero. **Accelo: módulo SCR (A96) entre la caja de baterías y el larguero del chasis.**
- Sensores del catalizador: A113 sensor NOx, B115 temperatura antes del catalizador, B116 temperatura después; B117 sensor de nivel y temperatura de ARLA 32 en el estanque.
- Prolongar cables solo con el arnés de interfaz de piezas originales (p.ej. conector lado arnés NOx A 029 545 95 28, lado sensor A 015 545 65 26); **prohibido cortar y soldar el arnés original** y prohibido cualquier empalme en el arnés del módulo SCR.
- El módulo SCR debe quedar protegido de golpes, calor y agua (respiradero libre).
- ARLA 32 se congela a ~-11 °C; cristales en el flexible escape se limpian con agua limpia. No reutilizar AdBlue extraído del estanque (pureza no garantizada); contaminación → fallas y daño del catalizador.

## [electrico] Central eléctrica (Global Cockpit) Axor / Atego Euro 5: ubicación y fusibles F1-F42
- Aplica: Mercedes-Benz Axor 2633 (2016-17) y Atego Euro 5 Brasil con Global Cockpit (INS2014)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Axor Euro 5, ES, ed. V, "Fusibles", pág. 360-363; igual en Manual de Operación Atego Euro 5, ES, pág. 364-367)

Ubicación: centralita en el extremo del tablero, **lado del acompañante**; quitar coberturas superior e inferior girando las presillas ~1/4 de vuelta (Axor) / ~1 vuelta (Atego). La etiqueta de fusibles, relés y diodos está pegada en la cara interna de la tapa. Siempre manda la etiqueta del vehículo.
| F | Circuito | A |
|---|---|---|
| F1 | Faro antiniebla | 10 |
| F2 | Iluminación instrumentos y teclas (58) | 10 |
| F3 / F4 | Luces de posición izq. / der. | 10 |
| F5 / F6 | Luz de cruce izq. / der. | 10 |
| F7 / F8 | Luz de carretera izq. / der. | 10 |
| F9 | Reserva (Axor) / Encendedor 15R (Atego) | —/10 |
| F10 | Tablero de interruptores puerta conductor | 15 |
| F11 | Vidrio eléctrico pasajero | 15 |
| F12 | A/C y ventilación (15R) | 20 |
| F13 | **Toma de fuerza (15)** | 10 |
| F14 | Bloqueo eje trasero (15) | 10 |
| F15 | Tacógrafo y tablero (15) | 10 |
| F16 | **Alternador (15)** / luces marcha atrás (Atego) | 15 |
| F17 | Espejos (15) / **postratamiento Euro V (15)** | 10 |
| F18 | **PLD (15)** | 10 |
| F19 | Reserva (Axor) / antirrobo (30) 5 A (Atego) | — |
| F20 | Intermitentes de advertencia (30) | 10 |
| F21 | Iluminación interior (30) | 10 |
| F22 | Direccionales remolque (30) | 20 |
| F23 | Toma luces remolque (30) | 15 |
| F24 | **Tablero de instrumentos y diagnóstico (30)** | 10 |
| F25 | Toma ABS remolque (15) | 10 |
| F26 | Luces direccionales | 10 |
| F27 | Limpia/lavaparabrisas (15) | 10 |
| F28 | **Diagnóstico** y bocina electroneumática (15) | 10 |
| F29 | Luces de freno / luces-alarma de reversa | 15 |
| F30 | Convertidor 24/12 V | 15 |
| F31 | **Relé D+** | 15 |
| F32 | Toma ABS remolque (30) | 20 |
| F33 | Eje HL5 / toma de fuerza (Axor); caja Telligent EPS 2 (Atego) | 15 |
| F34 | Techo solar (15) | 10 |
| F35 | Calefacción espejos (D+) | 10 |
| F36 | Ajuste nivel de faros | 5 |
| F37 | Cierre centralizado y mando a distancia (30) | 15 |
| F38 | Climatizador | 10 |
| F39 | Toma luces remolque (15) | 5 |
| F40 | Preparación FleetBoard | 10 |
| F41 | **Postratamiento Euro V (30)** | 10 |
| F42 | Cierre centralizado, mando a distancia y retardador (30) | 10 |
Relés central: K1 direccionales, K5 relé D+, K6 luces freno (15), K7 luces/alarma reversa, K73 motor limpiador, K74 auxiliar audible, K75/K76 direccionales remolque, K77 auxiliar ABS corte bloqueo ejes, K78/K79 iluminación (58/56), K80 faro alto (56a), K81 eje HL5, K82/K83 basurero, K121 caja Allison.
Diagnóstico típico "sin comunicación con escáner / tablero muerto": F24 (30) y F28 (15). "No carga batería / testigo D+": F16 y F31. Falla SCR sin causa aparente: F17 y F41. Motor no arranca con MR sin alimentación: F18 PLD.

## [electrico] Regleta A1 (fusibles adicionales) y A31 (relés) — Axor / Atego Euro 5
- Aplica: Mercedes-Benz Axor 2633, Atego Euro 5 Brasil
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Axor Euro 5, ES, pág. 362-363; Atego Euro 5 pág. 367 donde la regleta se llama A24)

| F (A1/A24) | Circuito | A |
|---|---|---|
| F1 | Cambio G140 / Telligent EPS 2 | 10 |
| F2 | Luz de trabajo | 10 |
| F3, F4 | Cambio PowerShift (EPS 3) / G140 | 15 |
| F5 | Cambio PowerShift (EPS 3) | 10 |
| F6 | Enfriador / refrigerador | 15 |
| F7 | Allison / sistema GGVS | 10 |
| F8 | Allison | 15 |
| F9 | Radio 24 V | 10 |
| F10 | Subwoofer / baliza (beacon) | 10 |
| F11 | **KL.30 ABS WABCO** | 30 |
| F12 | **KL.15 ABS WABCO** | 5 |
| F13 | Calefacción/ventilación asiento | 10 |
| F14 | Sistema GGVS | 10 |
Regleta de relés A31: **K3** auxiliar toma de fuerza (indicación de accionamiento), K4 luz de trabajo, K5/K7 GGVS, **K8** toma de fuerza (desaceleración), **K9** toma de fuerza (reset control de aceleración), **K10** toma de fuerza (aceleración).
Testigo ABS encendido sin código de rueda: revisar primero F11 (30 A) y F12 (5 A) de A1.

## [electrico] Central eléctrica Accelo Euro 5: fusibles F1-F42 y relés
- Aplica: Mercedes-Benz Accelo 1016 Euro 5 (2018, 2022), central A979…
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Accelo Euro 5, ES, ed. S(xx25), "Fusibles", pág. 285-287)

Ubicación: bajo el tablero lado acompañante, tras el porta-objetos (girar presillas y retirarlo); etiqueta en el vano de acceso. La edición del manual es 2025: puede incluir cajas EATON automatizadas; en camiones con caja manual los fusibles "Módulo EATON" quedan sin uso. Validar con la etiqueta.
| F | Circuito | A |
|---|---|---|
| F1 / F2 | Luz larga izq. / der. | 5 |
| F3 | Tacógrafo | 3 |
| F4 | Intermitente y direccionales | 7,5 |
| F5 | Motor ventilador | 15 |
| F7 / F8 | Luz corta izq. / der. | 5 |
| F9 | Iluminación instrumentos | 3 |
| F10 | **Módulo CPC – KL.30** | 5 |
| F11 | Iluminación interna | 3 |
| F12 | Conversor 24/12 V | 7,5 |
| F13 / F14 | Posición der. / izq. | 5 |
| F16 | Radio 24 V | 10 |
| F17, F26, F32 | Módulo EATON | 10 |
| F18 | **ABS** | 25 |
| F19 / F20 | Vidrio pasajero / conductor | 15 |
| F21 | Luces retroceso y relé auxiliar ventilador | 5 |
| F22 | **PLD y CPC** | 5 |
| F23 | **Alternador – KL.15** | 5 |
| F24 | **ABS** | 10 |
| F25 | Calefacción del combustible | 15 |
| F27 / F28 | Mando / calefacción espejos | 3 / 7,5 |
| F29 | Bocina | 5 |
| F30 | Temporizador limpiaparabrisas | 20 |
| F31 | Aire acondicionado | 4 |
| F33 | Luz de freno | 5 |
| F34 | Tacógrafo e instrumentos | 10 |
| F35 | Bloqueo diferencial | 5 |
| F36 | Módulo EATON | 40 |
| F37 / F38 | **Sistema de postratamiento** | 10 / 15 |
| F39 | **Toma de diagnosis (OBD) KL.30** | 10 |
| F40 | **Toma de diagnosis (OBD) KL.15** | 10 |
| F41 | **Toma de fuerza** | 10 |
| F6, F15, F42 | Reserva | — |
Relés: K1 direccionales, K3 luz larga, K3.1 luz corta, K6 luces freno, K7 retroceso, K38/K39 direccionales der./izq., K101 motor ventilador, K102 KL.15, K103 A/C, K104/K105 iluminación instrumentos KL.58, K105.1 temporizador limpiaparabrisas, K117 motor limpiaparabrisas, K118-K120 vidrios, **K121a/b/c toma de fuerza (reset control, desaceleración, aceleración)**, K97 arranque EATON.

## [electrico] Actros 932 (off-road): caja de fusibles, fusibles F1-F32 y bloques A1/A2
- Aplica: Mercedes-Benz Actros 3336 K serie 932 (2017-2019)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, 09/2017, "Fusíveis eléctricos", pág. 292-295)

Ubicación: **zona de los pies del lado acompañante**; correr la alfombra hacia atrás, soltar los cierres y retirar la tapa. En vehículos con embrague del convertidor/turboembrague + refrigeración del compartimento trasero, el esquema de ocupación está al lado izquierdo de la caja.
Bloque A:
| F | Circuito | A |
|---|---|---|
| F1 | Puerta conductor, borne 30 | 20 |
| F2 | Calefacción / calefacción adicional | 20 |
| F3 | Puerta acompañante, borne 30 | 20 |
| F4 | **Comando caja de velocidades borne 30.1** | 15 |
| F5 | Remolque borne 30 | 20 |
| F6 | Unidad modular de interruptores | 10 |
| F7 | Distribución borne 30.2, sirena alarma | 30 |
| F8 | **Distribución borne 30.1 – carrocero borne 30** | 30 |
| F9 | ABS remolque borne 30 | 20 |
| F10 | **Distribución borne 15.2 – carrocero borne 15** | 30 |
| F11 | **Sistema de frenos Telligent (BS) borne 30.1** | 15 |
| F12 | **Comando caja borne 30.2** | 15 |
| F13 | Manos libres, radio 24 V, FleetBoard borne 30 | 10 |
| F14 | Rastreo robo (Brasil), **regulación de marcha (FR)**, cerradura ignición borne 30 | 10 |
| F15 | Ventilador borne 30 | 20 |
| F16 | Iluminación habitáculo borne 30 | 5 |
| F17 | **Tacógrafo, toma de diagnóstico, tablero** borne 30 | 10 |
| F18 | Techo corredizo borne 30 | 10 |
| F19 | **Frenos Telligent borne 30.2** | 15 |
| F20 | **Comando caja borne 15.2** | 10 |
| F21 | **Gestión motor (MR) borne 15.2, alternador borne 15** | 10 |
| F22 | ABS remolque borne 15 | 10 |
| F23 | Luz freno remolque/carrocería | 15 |
| F24 | Distribución borne D+, **filtro de combustible (calefactor)** | 15 |
| F25 | **Toma diagnóstico, unidad postratamiento borne 15** | 10 |
| F26 | Distribución borne 15.1 | 30 |
| F27 | Calefacción adicional, A/C, gestión de flota borne 15.1 | 5 |
| F28 | **Regulación de marcha (FR) borne 15** | 10 |
| F29 | **Frenos Telligent borne 15** | 5 |
| F30 | Tablero, airbag borne 15 | 10 |
| F31 | Techo, navegación, radio 12 V, sensor temp. habitáculo borne 15R | 5 |
| F32 | Encendedor borne 15R | 10 |
Bloque A1: F1 **unidad postratamiento borne 30** 15 A; F2/F3 calefacción parabrisas 25 A; F4 nevera/teléfono 10 A; F5 plataforma de carga 10 A; F6 acoplamiento remolque 5 A; F7 toma 12 V 15 A; F8 dirección adicional electrohidráulica borne 30 15 A; F9 ídem borne 15 10 A; F10 cinturones/asientos 10 A; F11/F12 A/C auxiliar 10 A; F13 conversor 24/12 V 10 A (8 A) o 15 A (15 A); F14 SPA 5 A.
Bloque A2: F1 **ayuda arranque en frío (FLA) 20 A**; F2 bomba electrohidráulica de volteo 20 A; F3 ART/ABA borne 15 5 A; F4 **retarder / embrague hidráulico 5 A**; F5 alarma EDW / nivel suspensión 2ª unidad 5 A; F6 baliza rotativa, estrella 10 A; F7 / F8 refrigeración aceite caja de transferencia 5 / 20 A; F9 tomas 24 V 15 A; F10 focos 10 A; F11 **EAPU (Electronic Air-Processing Unit) borne 15** 10 A; F12 **EAPU borne 30** 10 A; F13 Toll Collect 5 A; **F14 sistema eléctrico de carroceros 15 A**.
Algunos circuitos usan **disyuntor automático**: si salta, el pino queda en "Desactivado 2"; sacarlo, empujar pino a "Activado 1", presionar botón de disparo (el pino debe saltar = disyuntor OK), rearmar e instalar. Si vuelve a saltar, revisar el circuito.

## [electrico] Actros 932: mensaje de luces/fusible y chequeo de lámparas en el INS
- Aplica: Mercedes-Benz Actros 3336 K serie 932
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, pág. 123-124)

- Mensaje al encender luces: falla en luz de posición, cruce, trasera, patente o neblinero **o en su fusible**.
- Mensaje al frenar: ampolleta de freno. Mensaje tras el chequeo del tablero al dar contacto: **fusible de luces de freno**.
- Mensaje al activar direccional: ampolleta de direccional.
- Acción: revisar fusible (pág. 292), luego ampolleta. En algunos casos el monitoreo de luces puede estar desactivado: hacer inspección visual diaria.

## [electrico] Masa (negativo) centralizada: no usar el chasis como retorno
- Aplica: Mercedes-Benz Atego, Axor, Accelo Brasil (y Actros con gestión electrónica)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (cap. 6.12, pág. 124); Manual de Operación Axor Euro 5, "Conexión al masa", pág. 365 (https://www.mercedes-benz-trucks.com.br/caminhoes/manuais)

- El retorno negativo de los consumidores va a un **punto de masa centralizado unido al polo negativo de la batería**; cabina, motor y chasis están eléctricamente aislados entre sí.
- Si se usa el chasis como retorno pueden dañarse componentes del **motor y de la caja de cambios** (corrientes por rodamientos/ejes). Si el sub-chasis del carrocero se usa como masa, debe unirse eléctricamente al punto de masa de la **carcasa del embrague**.
- Todo circuito adicional (bomba, luces, sensores de sobrellenado) debe llevar su negativo al punto de conexión del larguero que va al negativo de batería.
- Síntomas de masa mala: fallas intermitentes de varios módulos a la vez, mensajes CAN aleatorios, indicación errática de sensores. Medir caída de tensión masa-batería con carga (< 0,2 V es la práctica habitual; valor no especificado por Mercedes en la fuente).

## [electrico] Instalación de consumidores adicionales (bombas, luces, radios): reglas Mercedes
- Aplica: Mercedes-Benz Atego / Axor / Accelo Brasil
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (cap. 6.14, pág. 127-128)

- No conectar consumidores a fusibles ya ocupados: usar fusibles de reserva o agregar base de fusibles en el espacio libre de la central; relés adicionales en los espacios previstos.
- **Prohibido empalmar cortando cables existentes**; cables FLR de igual sección/color; terminales originales; unir solo en cajas de derivación; proteger con tubo corrugado.
- Cables de sensores ABS solo se prolongan con arneses aprobados.
- Equipos 12 V solo mediante **conversor de tensión**; prohibido tomar 12 V de una sola batería (desbalancea el banco 24 V).
- Válvulas solenoides adicionales (p.ej. válvulas de la bomba/aljibe) deben tener **diodo integrado** para evitar picos de tensión que afectan otros módulos.
- Luces adicionales en exceso sobrecargan el interruptor de luces: instalar relé auxiliar + fusible.
- En el Actros 932, el carrocero dispone de F8 (borne 30, 30 A), F10 (borne 15, 30 A) y A2-F14 (15 A).

## [electrico] Alternador y soldadura: precauciones oficiales
- Aplica: Mercedes-Benz Atego / Axor / Accelo / Actros con gestión electrónica
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813205332/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/accelo/manual-de-implementacao/manual-de-implementacao-euro-5-accelo-pt.pdf (cap. 5.1-5.1.2, pág. 62-64); Manual de Operación Axor Euro 5 pág. 364 (https://www.mercedes-benz-trucks.com.br/caminhoes/manuais)

- No mover el vehículo para hacer arrancar el motor con batería desconectada; no desconectar baterías con motor en marcha; no cargar baterías con cables conectados; no "polarizar" el alternador; no probar batería en cortocircuito.
- Alternador adicional: mismas características, en paralelo, con regulador rectificado por diodo zener.
- Soldadura: desconectar cables de batería, alternador y conectores de todos los módulos (MR con traba amarilla, módulos bajo el tablero, módulo SCR); masa de la soldadora directo a la pieza; no soldar cerca de sensores/arneses.
- Para ayudar arranque: baterías auxiliares en paralelo; **no usar cargador rápido conectado** ni conexión directa al motor de arranque.
- Desmontar módulos si el vehículo va a horno de pintura > 80 °C. No lavar a presión el MR, sensores ni conectores.

## [implemento] PSM (módulo especial parametrizable): ubicación, función y señales disponibles
- Aplica: Mercedes-Benz Atego 958 Brasil (código EM8), plataforma Axor; Actros 932 (PSM en lista de sistemas)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://salandingpagespaasprod.blob.core.windows.net/institutional-public/storage/assets/gallery/docs/bmd-br000002ce1.pdf (Diretrizes Atego 958.1XX Parte Eletroeletrônica, 2017, cap. 2.9.4, pág. 34-35)

- Ubicación: **detrás del asiento del acompañante** (código de venta EM8). Variante con CAN ISO 11898 de 5 V para carrocería: código EM9 (reemplaza al CAN 24 V ISO 11992).
- Conectado al HS-CAN (sistema IES); lee todos los mensajes (freno estacionamiento, freno servicio, velocidad C3, rpm motor, etc.) y los convierte en salidas digitales (high/low), PWM o PPM; y convierte entradas (p.ej. acelerador manual) en mensajes CAN (solicitud de rpm al FR).
- Interfaces: 1 alimentación; 2 HS-CAN al punto neutro; 3 interruptor toma de fuerza; 4 LS-CAN electrónica de carrocería; 5 LS-CAN remolque; 6 salidas digitales (relés, p.ej. "D+ activo"); 7 salidas PPM/PWM (p.ej. señal de velocidad); 8 entradas digitales (p.ej. arranque motor); 9 entradas analógicas (p.ej. acelerador manual).
- Funciones típicas: arranque/parada del motor desde carrocería, control de rpm (toma de fuerza), limitador de velocidad y bloqueo de marcha atrás, retardador sin CAN, caja automática sin CAN.
- Parámetros se programan con **Star Diagnosis/XENTRY (requiere licencia)**. No modificar cables CAN del vehículo: genera errores en otros módulos.
- Actros 932: con PSM, si no está aplicado el freno de estacionamiento no se activa la toma de fuerza y aparece "Accionar travão estacionam." con estado amarillo.

## [implemento] PSM: pinout de alimentación y CAN (Atego 958)
- Aplica: Mercedes-Benz Atego 958 Brasil Euro 5 (esquema 02/2010); referencia para Axor
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (esquema PE54.21-B-2500DA "Módulo especial parametrizable (PSM)", pág. 371 del PDF)

| A22 PSM pin | Señal | Desde |
|---|---|---|
| X3 15/1 | Borne 30 (2,5 mm² rt) | GM A7 X11 12/1 |
| X3 15/2 | Borne 31 masa (2,5 br) | GM A7 X6 15/1 |
| X3 15/3 | Borne 15 (2,5 sw) | GM A7 X9 18/7 |
| X3 15/13 / 15/14 / 15/15 | CAN 1 Low / GND / High (ge / – / bl) | Z1 X2 18/3 (L), 18/1 (H) |
| X1 18/16 / 18/17 / 18/18 | CAN 9 telemática Low / GND / High | X125.1 21/20, 21/19 → FMS X215, FleetBoard A119, tacógrafo DTCO P1 |
| X4 18/6 | Borne 31 (2,5 br) | GM A7 X6 15/2 |
PSM sin comunicación: verificar 30/15/31 en X3 antes de sospechar del módulo.

## [implemento] Control de rpm para bomba (acelerador auxiliar / toma de fuerza): FR MPS y código MT5
- Aplica: Mercedes-Benz Axor, Atego, Accelo Brasil (FR / FR-CPC)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (cap. 6.15, pág. 129-131); https://web.archive.org/web/20140813205332/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/accelo/manual-de-implementacao/manual-de-implementacao-euro-5-accelo-pt.pdf (cap. 6.15, pág. 113-115); Axor: https://web.archive.org/web/2015/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/axor/manual-de-implementacao/manual-de-implementacao-euro-3-axor-es.pdf (cap. 6.14, pág. 136-139)

| Versión FR | Control | rpm |
|---|---|---|
| FR/CPC – MPS (serie) | Fija | 700 → 1200 (*) |
| FR/CPC – MPS + código **MT5** (opcional) | Variable | 700 hasta 1800 (*) |
(*) Programadas de fábrica; modificables solo por concesionario con equipo de diagnóstico (XENTRY – licencia).
- Con toma de fuerza original de fábrica (Atego código **NL5**, Axor **N04**) la conexión ya existe: solo falta parametrizar el módulo; con PTO de fábrica solo se habilita rpm **fija** conjugada con el interruptor de PTO.
- Identificar MT5: en la central (bajo tablero lado acompañante) deben estar los relés **K8, K9, K10** en la regleta A31/A31.1 (Atego central A958 584 22 21; Axor relés A004 545 35 05). En Accelo los relés son **K121.a, K121.b, K121.c** (central A979 589 30 21), con el arnés adicional A 979 540 42 05.
- Conector para acelerador externo: **X4.1** en la caja de conectores con acceso por la **tapa frontal** (Atego/Axor); en Accelo **X1.1 / X1 conector gris "de espera"** detrás de la guantera.

## [implemento] Acelerador externo (MT5): conexión de interruptores en X4.1 (Axor) y X1 (Accelo)
- Aplica: Mercedes-Benz Axor 958 (Euro 3/5), Accelo 979 Euro 5
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/2015/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/axor/manual-de-implementacao/manual-de-implementacao-euro-3-axor-es.pdf (cap. 11.1 "Complementación del acelerador exterior", pág. 259-261); Accelo: https://web.archive.org/web/20140813205332/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/accelo/manual-de-implementacao/manual-de-implementacao-euro-5-accelo-pt.pdf (cap. 11.1, pág. 178)

Axor: abrir tapa frontal, retirar rejilla frontal y la toma de aire del motor para acceder a la central; retirar tapa. El conector **X4.1** tiene preparadas las **posiciones 1, 2, 3 y 18** para los interruptores de mando exterior: S1 desconecta, S2 desacelera, S3 acelera; **18 = alimentación**. (La asignación exacta S1/S2/S3 a 1/2/3 está en el dibujo del manual; verificar con el esquema del vehículo antes de conectar.)
Piezas: terminales MCP 2,8 (013 545 75 26), conexión MCP 2,8 18 vías (013 545 64 26), interruptores 003 545 23 14, etc.
Accelo: conector gris "de espera" **X1** detrás de la guantera; interruptores S1 apagado de emergencia, S2 acelera, S2 desacelera (según esquema del manual). La instalación sin preparación MT5 debe hacerla la red Mercedes.
Uso en aljibe/riego: la bomba se controla con rpm estable; si "no sube rpm" con PTO activa, revisar freno de estacionamiento aplicado, neutro, relés K8-K10 / K121 y fusible de toma de fuerza (F13 Axor/Atego, F41 Accelo).

## [implemento] Operación de toma de fuerza (PTO) y condiciones de habilitación — Actros 932
- Aplica: Mercedes-Benz Actros 3336 K serie 932 (PTO de caja y NMV dependiente del motor)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, "Tomadas de força", pág. 247-249)

- **PTO dependiente de la caja**: solo se activa con vehículo detenido, **freno de estacionamiento aplicado**, motor en ralentí, embrague pisado (si tiene pedal) y **caja en neutro**. Esperar **10 s** después de pisar embrague antes de activar/desactivar. Desactivar solo en ralentí.
- **PTO dependiente del motor (NMV)**: activar/desactivar con motor funcionando **máx. 1700 rpm**, detenido o en marcha, bajo carga.
- Tras pulsar el interruptor la luz parpadea ~1,5 s antes de activar. Visor: "0" activada (estado amarillo), "/" desactivada.
- Si "/" **parpadea**: la electrónica no reconoce neutro, vehículo detenido o freno de estacionamiento → no activa. Revisar esas señales (interruptor freno estacionamiento, sensor de neutro de la caja, velocidad). Si persiste: taller.
- Dos rpm de servicio preseleccionables con el interruptor de desmultiplicación / tecla de velocidad intermedia; estabilización de rpm solo con vehículo detenido, freno de estacionamiento, neutro y PTO activa.
- Acoplamiento de emergencia de la NMV: solo con motor apagado (el eje puede girar).

## [implemento] Operación de toma de fuerza — Axor / Atego (caja manual y automatizada)
- Aplica: Mercedes-Benz Axor 2633 (2016-17), Atego Euro 5
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Axor Euro 5, ES, "Toma de fuerza", pág. 238-240)

- Caja manual: acoplar/desacoplar solo con freno de estacionamiento, motor en ralentí y neutro. Pisar embrague a fondo **~10 s**, con el pedal pisado accionar el interruptor; la luz del interruptor y el indicador de equipos del monitor confirman. No cambiar marchas con PTO acoplada. Ruido de dientes al acoplar → revisar embrague (no desembraga completo).
- Modos parametrizables: rpm fija, rpm variable, o variable + fija.
- rpm fija: con freno de estacionamiento aplicado activar el interruptor del cuadro; el motor sube al valor programado y el **torque se limita** al valor parametrizado. Al soltar el freno de estacionamiento se sale del modo; al aplicarlo de nuevo vuelve.
- rpm variable: con pedal acelerador (escalones predefinidos) o palanca multifunción del regulador.

## [implemento] Tomas de fuerza en caja: datos técnicos (Accelo) y fórmula de potencia
- Aplica: Mercedes-Benz Accelo 979 Euro 3/5 (1016 con caja G56-6 / ZF / Eaton)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://salandingpagespaasprod.blob.core.windows.net/institutional-public/storage/assets/gallery/docs/manual-de-implementacao-accelo-2023.pdf (Diretrizes Accelo 979.0XX Euro 3/5, 28.07.2023, cap. 3.12, pág. 58-59)

- Accelo **no trae PTO de fábrica**: se pide en Centro de Customización o preparación para PTO de mercado **código N6T** (tubería, válvula neumática, módulo XMC rpm variable, parámetros y arnés). Sin N6T no hay control correcto de la PTO.
- Potencia admisible: **P (kW) = M (Nm) · n (rpm) · i / 9550**. Par necesario de la bomba: **M = 9550 · P / n**.
- Límites: aceite de caja **120 °C** y refrigerante **100 °C** no deben excederse. Par continuo = 70 % del pico tabulado.
| Caja | PTO | Accionamiento | i | Potencia continua | Par |
|---|---|---|---|---|---|
| MB G56-6 | Chelsea 442 (bomba/flange) | Neumático | 1,000 / 1,020 | 28,3 kW / 1000 rpm | 271 Nm |
| ZF S5-580 TO | NS42/2 c / b | Neumático | — | — | 265 Nm |
| Eaton FSO-4405A | 3003678 / 3003718 | Neumático | 0,980 | 24,3 kW / 1000 rpm | 237 Nm |
| MB G70-6 (N0C/N0D/N0E) | NA MB 56-1C/2C | Engranaje | 1,679 | 80 kW / 1000 rpm | 450 Nm |
Rotación de salida PTO = rpm motor × i.

## [general] Recall airbag Takata — Actros y Arocs 2012-2017 (Chile, SERNAC)
- Aplica: Mercedes-Benz Actros 2012-2017 en Chile (354 unidades) — incluye Actros 3341 2012-13 y posiblemente 3336K 2017
- Tipo: boletin_recall
- Confiabilidad: oficial
- Fuente: https://www.sernac.cl/portal/619/w3-article-62705.html (Alerta de seguridad SERNAC, 08-04-2021)

- Defecto: el propulsor del airbag del conductor puede degradarse químicamente con ciertas condiciones climáticas; al desplegarse el inflador puede romperse y proyectar fragmentos metálicos.
- Solución: inspección y reemplazo gratuito del airbag (~30 min). Importador: Comercial Kaufmann, tel. 562 2481 4848. Verificar por VIN.

## [general] Recall Axor: soporte de estanque de aire bajo cabina (Brasil 2011-2018)
- Aplica: Mercedes-Benz Axor fabricados 02/2011 a 11/2018 (chasis 9BM958453BB813628 a 9BM958443JB112371)
- Tipo: boletin_recall
- Confiabilidad: tecnica_terceros
- Fuente: https://www.autossegredos.com.br/caminhoes-2/mercedes-benz-caminhoes/recall-mercedes-benz-axor-e-convocado-por-falha-estrutural/ (nota de prensa del recall Mercedes-Benz do Brasil, 12/2018)

- Defecto: el soporte del estanque (cilindro) de aire, lado derecho bajo la cabina, puede trizarse o romperse → el estanque puede desprenderse.
- Solución: reemplazo del soporte. Nuestros Axor son VIN WDF950…: verificar con Kaufmann si la campaña aplica al mercado chileno. Inspección visual del soporte en cada mantención.

## [general] Recall Accelo/Atego/Axor 2015-2017: escotilla del techo
- Aplica: Mercedes-Benz Accelo, Atego, Axor fabricados 01/2015-06/2017 (excepto con techo eléctrico y A/C)
- Tipo: boletin_recall
- Confiabilidad: tecnica_terceros
- Fuente: https://dana.com.br/canaldana/2017/09/15/mercedes-benz-comunica-recall-de-caminhoes-dos-modelos-accelo-atego-e-axor/ (nota del recall Mercedes-Benz do Brasil, 09/2017)

- Escotilla de techo con espesor reducido o traslape incorrecto (fabricados 5 a 20-09-2015 pueden tener poco adhesivo) → trizaduras o desprendimiento. Solución: canal de refuerzo o reemplazo. Aplica potencialmente al Axor 2016-17.

## [general] Recall Atego/Atron/Axor 2018-2019: soportes de estanques de aire
- Aplica: Mercedes-Benz Atego 8x2, Atron, Axor fabricados 01/2018-06/2019 (~11 mil camiones Brasil)
- Tipo: boletin_recall
- Confiabilidad: tecnica_terceros
- Fuente: https://estradas.com.br/mercedes-faz-recall-de-11-mil-caminhoes-mas-nao-paga-despesas-para-atender-convocacao/

- Soportes de estanques de aire no conformes: trizadura/rotura y desprendimiento. Fuera del rango de nuestros Axor 2016-17, pero útil como falla conocida del diseño: inspeccionar soportes de estanques de aire (vibración en faena).

## [general] Recall Accelo/Atego/Axor 08/2011-11/2012: torque de pernos del cubo delantero
- Aplica: Mercedes-Benz Axor, Atego, Accelo, Atron fabricados 08/2011-11/2012 (Brasil)
- Tipo: boletin_recall
- Confiabilidad: tecnica_terceros
- Fuente: https://www.gazetadopovo.com.br/economia/recall-mercedes-benz-identifica-falhas-em-caminhoes-60y86rw7qy1a3bn0tr7i1ltqb/

- Torque bajo en pernos de traba del cubo de rueda del eje delantero y eje de apoyo → riesgo de soltura del cubo. Posible relación con el Atego 1624A 2013 si fue fabricado en ese rango (es VIN WDB970, fabricación alemana: verificar con Kaufmann).

## [general] Recall Actros/Axor 6x4 2013-2016: cardán entre 2º y 3º eje
- Aplica: Mercedes-Benz Actros 2646/2651/2655 y Axor 2644 6x4 fabricados 11/2013-09/2016 (chasis 9BM934241DS021146 a 9BM934241GS040857)
- Tipo: boletin_recall
- Confiabilidad: tecnica_terceros
- Fuente: https://www.autossegredos.com.br/caminhoes-2/mercedes-benz-caminhoes/mercedes-benz-axor-e-actros-sao-convocados-para-recall-por-falha-em-transmissao/

- Cordón de soldadura no conforme en el cardán entre 2º y 3º eje → trizadura/rotura. No incluye nuestros modelos (3336K 932 / 3341 930) según la lista, pero sirve como punto de inspección en 6x4.

## [frenos] Códigos de parpadeo WABCO: advertencia de aplicabilidad
- Aplica: Solo ECU ABS WABCO "C-Version" (Norteamérica). NO confirmado para Mercedes Brasil/Europa (ABS WABCO / EBS Telligent BS)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/tp94157_web.pdf (WABCO TP-94157 "ABS Blink Code Diagnostics, All C-Version ECUs")

- Formato: 1er dígito = configuración (1 = 6S/6M, 2 = 4S/4M, 4 = 6S/4M); los dos siguientes = falla (ej. x-6-8 señal errática rueda delantera derecha; x-7-2 circuito sensor trasero izquierdo; x-0-0 sin fallas).
- En los Mercedes de la flota las fallas ABS/EBS se muestran en el INS como mensaje "ABS"/"BS"; **no usar esta tabla** salvo que se confirme ECU WABCO con función blink. Para Actros (BS = EBS Telligent) el diagnóstico es con XENTRY o Jaltest (licencia).
- Chequeos genéricos válidos para cualquier ABS: sensor de rueda (holgura, empujar sensor contra la rueda fónica), rodamiento suelto, rueda fónica dañada, conectores del sensor con barro/agua; fusibles ABS (Axor/Atego A1-F11 30 A y F12 5 A; Accelo F18 25 A y F24 10 A).

## [electrico] Resistencia del bus CAN: prueba rápida en la toma X13
- Aplica: Mercedes-Benz Axor / Atego / Accelo (X13 pines 6-14) y cualquier red CAN J1939/ISO 11898 de alta velocidad
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.csselectronics.com/products/terminal-resistor-can-bus (CSS Electronics – terminación CAN 120 Ω); pinout X13 en esquema PE54.22-B-2000EA del Manual de Implementação Atego Euro 5 (https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf)

1. Llave OFF, baterías desconectadas (o esperar que el bus "duerma").
2. Medir resistencia entre **pin 6 (CAN High)** y **pin 14 (CAN Low)** de X13.
3. Referencia de una red HS-CAN terminada en ambos extremos: **~60 Ω** (dos terminaciones de 120 Ω en paralelo). ~120 Ω = falta una terminación / ramal abierto; ~0 Ω = corto entre H y L; infinito = circuito abierto hasta el punto neutro.
4. Con llave ON medir tensiones a masa (pin 4/5): típico H ≈ 2,5-3,5 V y L ≈ 1,5-2,5 V (valores ISO 11898 genéricos, no publicados por Mercedes).
5. En la topología en estrella de Mercedes (Z1), desconectar ramales en Z1 para aislar el módulo que tira la red. Nota: la ubicación exacta de las resistencias terminales en la red Mercedes no está publicada (WIS – licencia).

## [motor] Lámparas del motor MBE 900 / MR2 (familia OM 906/926): ámbar, roja STOP y override
- Aplica: Motores Mercedes MBE 900 EuroV (versión Detroit de OM 904/906/924/926 con MR2) — referencia técnica para OM 924/926 PLD de la flota
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://dtnacontent-dtna.prd.freightliner.com/content/dam/public/dtna-servicelit/ddc/pdfs/OperatorsManual/MBE/DDC-SVC-MAN-0207_2020.pdf (EuroV MBE 900 Operators Manual DDC-SVC-MAN-0207, cap. 5-6, 12-13)

- Los códigos de falla se guardan en la **memoria del MR2**.
- Protección del motor: vigila bajo nivel de refrigerante, alta temperatura de refrigerante, baja presión de aceite, alta temperatura de aceite. Falla crítica → ámbar + roja; secuencia de apagado escalonada de **30 s** (o reducción de rpm sin apagar, según parámetro).
- Override: pulsar el interruptor cada **15-20 s**; mantenerlo apretado no evita el apagado. El sistema registra cuántas veces se usó.
- MIL: falla de emisiones; nunca parpadea (en DDC). DEF: barra de 4 segmentos (25 %); DEF vacío e ignorado → vehículo limitado a **5 mph** hasta detectar DEF.
- **Tapar la parrilla (cubre-radiador) genera códigos falsos** de motor y postratamiento.
(En Mercedes Brasil la lógica de reducción de potencia es la del manual de operación BlueTec; ver ficha MIL.)

## [postratamiento] Diagnóstico básico SCR/ARLA 32 (BlueTec 5) en taller
- Aplica: Mercedes-Benz Axor / Atego / Accelo / Actros Euro 5 BlueTec 5
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://omecanico.com.br/veja-como-diagnosticar-problemas-no-sistema-scr-arla-32/ (Revista O Mecânico, "Veja como diagnosticar problemas no sistema SCR / Arla 32")

1. Leer códigos con escáner (DM1/SPN o códigos del MR/SCR).
2. Verificar calidad y vencimiento del ARLA 32 (contaminación en tapa, filtros, líneas).
3. Revisar sensores NOx antes/después del catalizador y sensores de temperatura (B115/B116 en Mercedes).
4. Síntomas: testigo de emisiones, reducción de torque/velocidad, olor a amoníaco.
5. Causas típicas: falta de inyección (dosificador Y109 / presión B129), calefactor del estanque que no funciona (Y107, clima frío), catalizador obstruido, sensor NOx, contrapresión de escape.
6. Tras reparar: adaptación y borrado de códigos con escáner.
En faena: ARLA fuera de norma o contaminado con polvo es causa frecuente; mantener tapa y embudo limpios.

## [electrico] Accelo: fallas crónicas reportadas en taller (arnés, ABS, tablero)
- Aplica: Mercedes-Benz Accelo (715C reportado; plataforma 979 común con 1016)
- Tipo: falla_conocida
- Confiabilidad: tecnica_terceros
- Fuente: https://oficinabrasil.com.br/noticia/reparador-diesel/mb-accelo-715c-possui-alguns-problemas-cronicos-nas-visitas-as-oficinas-de-reparacao (Oficina Brasil, reparador diésel)

- Eléctricas: testigos en el tablero, fallas del sensor ABS, velocímetro intermitente, atribuidas al **deterioro del arnés sobre ~200.000 km**; recomiendan pruebas de continuidad y cambio de conectores.
- Mecánicas: desgaste prematuro de embrague, trizaduras de chasis/suspensión delantera, bujes y pivotes, sistema de enfriamiento (bomba de agua, fugas).
- Relacionar con fusibles ABS F18/F24 y alimentación del tacógrafo/instrumento F3/F34 antes de cambiar sensores.

## [transmision] Telligent / GS: fallas de campo frecuentes (sin respaldo documental suficiente)
- Aplica: Mercedes-Benz Actros MP2/MP3 con caja Telligent (EPS) / PowerShift
- Tipo: falla_conocida
- Confiabilidad: experiencia_campo
- Fuente: https://www.classtrucks.com/en/buyers-guide/mercedes-benz/mercedes-benz-fault-codes/mercedes-benz-gear-shift-fault-codes (ClassTrucks, guía de códigos GS – descripción general, sin tabla)

Causas que se repiten en foros y talleres (no verificadas con documento oficial; usar como lista de chequeo, no como diagnóstico):
- Presión de aire insuficiente o fugas en el circuito de caja/embrague (el INS lo avisa como "presión de reserva caja/embrague").
- Cilindros de cambio contaminados con aceite/agua (secador de aire APU/EAPU saturado) o con aire atrapado.
- Sensor de posición de marcha/recorridos (en el bloque de válvulas) con falla eléctrica o mecánica.
- Bobinas del bloque de válvulas abiertas o en corto; conector del módulo GS con humedad.
- Tensión baja (el propio GS muestra "U <<<<" = GS 20).
Primer paso oficial: sincronización pequeña/grande (ver ficha) y revisar fusibles de caja (Actros 932: F4, F12, F20).

## [electrico] Desmontaje de conectores y módulos: procedimiento seguro
- Aplica: Mercedes-Benz Accelo / Atego / Axor Brasil
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813205332/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/accelo/manual-de-implementacao/manual-de-implementacao-euro-5-accelo-pt.pdf (cap. 5.1.2 "Remoção dos componentes eletroeletrônicos", pág. 63-64)

1. Retirar cable negativo y luego positivo de batería y aislarlos (al conectar: primero positivos, luego negativos).
2. Conectores del MR: tirar la **traba amarilla hacia arriba**, el conector desliza; el segundo conector: levantar la traba delantera. Proteger terminales.
3. Módulos bajo el tablero (retirar porta-objetos): tirar traba amarilla hacia abajo hasta que el conector salga.
4. Módulo SCR: soltar la traba del conector (Accelo: en el alojamiento de la caja de baterías).
5. Nunca usar puntas de prueba o alambres dentro de los terminales (genera falso contacto posterior): medir con adaptadores/backprobe.

## [electrico] Esquemas eléctricos Atego 958 disponibles en PDF público (índice)
- Aplica: Mercedes-Benz Atego 958 Brasil Euro 5 (y Atron); referencia para Axor/Accelo misma generación
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (Manual de Implementação Atego e Atron, 01.06.2012, cap. 6.16 y anexos, pág. 347-388 del PDF; archivo local "Mercedes-Benz Atego Euro 5 - Manual de implementacao (PT).pdf")

Esquemas (imagen, estado 02/2010, "ATEGO L", tipo 958.0) en el orden del PDF: MR PE07.15-B-2002KB (p.347), SCR (p.348), motor de arranque (p.349), alternador (p.350), sistema de llama (p.351), toma de fuerza (p.352), caja de transferencia (p.353), Tempomat (p.354), **FR I y II PE30.35-B-2001JA/JB (p.355-356)**, enganche remolque, bloqueo diferencial delantero/trasero (p.359), **ABS PE42.30-B-2000EB (p.360)**, prefiltro combustible, **batería/alimentación PE54.10-B-2000GA (p.362)**, transformador 24/12, **punto neutro CAN PE54.18-B-2000CA (p.364)**, **módulo básico GM I-IV PE54.21-B-2400QD…QG (p.365-368)**, módulos de puerta, **PSM PE54.21-B-2500DA (p.371)**, **toma diagnóstico PE54.22-B-2000EA (p.372)**, **instrumento INS PE54.30-B-2200NA/NB (p.373-374)**, tacógrafo, alumbrado exterior PE82.10-B-2000GA (p.380) y resto de confort. Atron HPN/FPN p.390-427 y HSK p.429-467 (incluyen centrales F1-F42).
Accelo Euro 5: el manual de implementación Accelo (https://web.archive.org/web/20140813205332/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/accelo/manual-de-implementacao/manual-de-implementacao-euro-5-accelo-pt.pdf) incluye "Esquema elétrico geral" Accelo 815/1016 (plano A979 540 05 00) y 915 (A979 540 04 00) en páginas finales (imagen).

## [electrico] Instrumento INS Atego 958: alimentación y señales (esquema I)
- Aplica: Mercedes-Benz Atego 958 Brasil (esquema 02/2010)
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://web.archive.org/web/20140813204945/http://mercedes-benz.com.br/resources/files/documentos/caminhoes/atego/manual-de-implementacao/manual-de-implementacao-euro-5-atego-pt.pdf (esquema PE54.30-B-2200NA "Instrumentos (INS) esquema I", pág. 373 del PDF)

Elementos del esquema: P2 instrumento; A3 FR; A7 GM; A30 WS; B17 transmisor de velocidad; B22 sensor nivel combustible; B25 presión circuito freno 3; B71 presión circuitos 1 y 2; B71b1/B71b2 presión freno 1/2; S47 contacto puerta conductor; S124 eje desmultiplicación; S188 interruptor basculante instrumento; X13 diagnóstico; Z1 punto neutro CAN; CAN 1 vehículo y CAN 10 tacógrafo.
Fusibles asociados: **F10-A7 caja diagnóstico borne 30**, **F2-A7 iluminación instrumentos borne 58**, **F26-A7 luz de carretera izq. borne 56a**, **F38-A7 ABS borne 15**.
Indicador de combustible errático: revisar B22 y masa del estanque antes que el INS.

## [frenos] Presión mínima de reserva de aire antes de operar (Accelo)
- Aplica: Mercedes-Benz Accelo Euro 5 (INS2014)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operación Accelo Euro 5, ES, "Verificaciones de seguridad", pág. 172)

- Presión de reserva en los depósitos del freno: **mínimo 8,5 bar en ambos circuitos** de freno de servicio antes de iniciar la jornada.
- Accelo 4x2: dos depósitos de 20 L (circuito trasero y delantero); la línea de accesorios (salida 24 de la válvula de 4 circuitos) es la única recomendada para consumidores neumáticos adicionales (manual de implementação Accelo Euro 5, cap. 10.4).

## [electrico] Actros 932: ubicación de diagnóstico y advertencia sobre equipos conectados
- Aplica: Mercedes-Benz Actros 3336 K serie 932
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (Manual de Operação Actros fora de estrada 932/934/936, PT, 09/2017, "Acoplamento para diagnóstico", Introdução pág. 24; fusibles pág. 293-294)

- Advertencia oficial: si se conectan aparatos a la toma de diagnóstico **pueden ocurrir fallas de funcionamiento de los sistemas del vehículo**; conectar solo aparatos aprobados por Mercedes-Benz.
- Fusibles de la toma: F17 (borne 30, 10 A) y F25 (borne 15, 10 A).
- Práctica de taller (no dicha por Mercedes): si el camión tiene GPS/telemetría conectado a la toma y aparecen fallas CAN aleatorias o baterías descargadas, desconectarlo como primera prueba.

## [general] Documentación que requiere licencia (no disponible públicamente)
- Aplica: Toda la flota Mercedes-Benz (Actros MP2/MP3, Axor, Atego, Accelo)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.mercedes-benz-trucks.com.br/caminhoes/manuais (portal público: solo manuales de operación, mantenimiento e implementación)

- Tablas de códigos de falla MR/PLD, FR, GS, INS, BS/EBS de 4-5 dígitos, textos de falla y pruebas guiadas: **XENTRY Diagnosis** (licencia Mercedes-Benz Trucks). Alternativas comerciales con licencia: Jaltest (Cojali), Texa IDC, Noregon JPRO.
- Esquemas de taller completos con pinouts legibles (MR 55/16 vías, FR, GS, EBS), valores de resistencia de inyectores unitarios PLD y sensores: **WIS / XENTRY (licencia)**.
- Parametrización de PSM, ralentí de PTO, límites de velocidad: Star Diagnosis / XENTRY con acceso de concesionario.
- Actros MP2/MP3 europeo (serie 930, VIN WDB930) manual de operación: no disponible en portal público; manuals.daimlertruck.com solo publica la generación 963/964.
- Bodybuilder portal europeo (bb-portal.mercedes-benz-trucks.com) requiere registro para documentos de modelos anteriores.
