# Volvo Trucks (FMX / VM) — base de conocimiento para diagnóstico

Flota Pillado (grupo Volvo, 11 Volvo + 1 Renault en archivo aparte):
- 4 × Volvo VM 6x4 2023 (VIN 93KKYM0D…, Curitiba, motor D8 N° D8600352C2EP) — riego/aljibe.
- 6 × Volvo FMX 420 6x4 2024 (VIN 93KXG10D…, motor D13 N° D138097104C5E) — riego, polibrazo, pluma.
- 1 × Volvo FMX 540 6x4 2024 (VIN 93KXG40D…) — pluma.

Chasis Volvo (N° de chasis = factoryCode + últimos 6 del VIN, verificado en el portal):
| Patente | VIN | Chasis portal | Modelo portal | Montaje |
|---|---|---|---|---|
| SVBJ-55 | 93KKYM0D5RE191064 | E191064 | VM VMX (clase 06) | 2023-02 |
| SVBJ-56 | 93KKYM0D1RE190968 | E190968 | VM VMX | 2023-02 |
| SVBJ-57 | 93KKYM0D5RE190769 | E190769 | VM VMX | 2023-02 |
| SVCZ-38 | 93KKYM0D8RE191065 | E191065 | VM VMX | 2023-02 |
| TGGF-56 | 93KXG10D1RE941303 | E941303 | FMX (clase 24) | 2023-08 |
| TRDP-96 | 93KXG10DXSE603547 | **EE603547** | FMX | 2024-04 |
| TGGF-60 | 93KXG40D4RE944562 | E944562 | FMX | 2023-10 |
Fuente: `https://vteu.webbase.cloud/driverguide/chassiNfo?chassi=<chasis>`.
Las guías reales de los FMX (FMX-R = guía por chasis real) están en
`_Investigacion web 2026-09-19/Volvo/Volvo FMX 420 2024 chasis E941303 (TGGF-56) - Guia del conductor (es).pdf`
(y equivalentes EE603547 y E944562). Las páginas citadas "FMX-R pág. N" son páginas del PDF de E941303.

Advertencia general: las fichas marcadas "(NA)" vienen de documentación Volvo Trucks
North America (VNL/VHD). Sirven como referencia de la arquitectura del grupo, pero
pines, fusibles y parámetros deben validarse en el FMX/VM brasileño con Tech Tool o con
la calcomanía de la central eléctrica. Las fichas de la "Guía del conductor" se tomaron
del chasis demo FMX del portal oficial (mercado europeo); el FMX brasileño es LHD
(volante a la izquierda).

Fuentes base (abreviadas en las fichas):
- DG-FMX = Volvo Trucks Driver Guide, chasis demo FMX "000FMX" (nueva generación). API oficial del portal: `https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=<oid>`; portal: https://driverguide.volvotrucks.com. PDF local: `_Investigacion web 2026-09-19/Volvo/Volvo FMX (nueva generacion, demo EU Euro 6) - Guia del conductor (es).pdf`.
- DG-FMXC = Idem chasis demo "CL0FMX" (FMX Classic). PDF local `Volvo FMX Classic - Guia del conductor completa (es).pdf`.
- NA-S3 = PDF local `_Descargados oficiales 2026-09/Volvo/Volvo NA Body Builder Seccion 3 - Electrico VECU4 fusibles reles (ref FMX).pdf` (Volvo Body Builder Instructions VN/VHD/VAH Section 3, USA170229709, fecha 4.2023), publicado en https://www.volvotrucks.us/parts-and-services/services/body-builder-support/manuals/
- ECM-DTC = http://www.wheelingtruck.com/wp-content/uploads/diag-codes.pdf (Volvo Trucks NA Service Information Grupo 28, "ECM DTC Guide, 2010 Emissions", PV776-89046912). Copia local en `_Investigacion web 2026-09-19/Volvo/`.

---

## [general] Identificación de variantes de la flota Volvo (VM y FMX) y nivel de emisiones
- Aplica: Volvo VM 6x4 2023 (D8K), Volvo FMX 420/540 6x4 2024 (D13)
- Tipo: especificacion
- Confiabilidad: tecnica_terceros
- Fuente: https://elconstructor.com/una-nueva-version-de-camiones-semipesados-mas-eficientes-y-versatiles/ (El Constructor, Chile, 19-01-2026) ; https://www.volvogroup.com/br/news-and-media/news/2022/oct/linha-vm-euro-6-traz-novo-motor-volvo-com-mais-potencia-e-ate-10-mais-economico.html (Volvo Group Brasil, oct-2022)

- VM para Chile: fabricado en Curitiba (Brasil), motor **D8K de 8 L, 6 cilindros, 280 a 350 CV, "tecnología Euro 5"**, caja I-Shift de 12 velocidades; configuraciones 4x2, 6x2, 6x4, 8x4 (El Constructor). El N° de motor "D8…350…" del VM de la flota es coherente con un **D8K 350 Euro 5** (SCR con AdBlue; confirmar si lleva DPF en la placa de emisiones o con Tech Tool).
- VM para Brasil (Proconve P8 = Euro 6, desde 2023): D8K 8 L con turbo nuevo y common rail, versiones **290 cv/1.050 Nm y 360 cv/1.400 Nm**, freno motor 210 cv o VEB 300 cv, I-Shift de 7ª generación (manual de 9 velocidades opcional), EBS, ESP, auxilio de partida en rampa, panel con display color 4,3", modos Económico/Performance/Off Road, I-Roll, nuevas tomas de fuerza de fábrica (Volvo Group Brasil).
- Conclusión práctica: el VM brasileño de mercado interno es Euro 6 (P8) pero el exportado a Chile se comercializa Euro 5. **Los FMX de la flota quedaron confirmados por su guía real: motor D13C, Euro 5 / PROCONVE P7, SCR con ARLA 32, sin DPF** (ver ficha "FMX flota: norma de emisiones"). Por lo tanto las fichas Euro 6 / DPF de este archivo NO aplican a los FMX de la flota. El VM sigue sin confirmación documental del nivel (guía del portal vacía).

## [general] Cómo obtener la guía del conductor exacta de cada camión Volvo (por N° de chasis)
- Aplica: Volvo FH/FM/FMX/FE/FL (portal global)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicWithoutChassi?l=pt-BR&topic=102706&level=5 (Driver Guide, "Encontre o número do chassi do caminhão") ; https://www.volvotrucks.cl/es-cl/trucks/information/handbook-online.html

- El número de chasis Volvo son **los últimos 7 caracteres del VIN**. Ubicación de la placa: FH/FH16 dentro de la escotilla delantera; **FM/FMX dentro de la puerta derecha**; FE/FL dentro de la puerta izquierda.
- En https://driverguide.volvotrucks.com se ingresa el N° de chasis y se obtiene la guía filtrada para ese camión (solo el equipamiento real, incluida la tabla de fusibles de ese camión) y se puede generar un PDF descargable. Volvo Chile: "podrá ver su Manual del conductor exclusivo en función del número de chasis de su camión y de su idioma".
- En los camiones de nueva generación la guía completa está además en la pantalla lateral del camión.
- Recomendación: generar el PDF de cada uno de los 11 Volvo con su VIN completo (no disponible en esta investigación) y guardarlo en la carpeta de manuales; el VM no apareció entre los modelos demo del portal, hay que probar con el chasis real.

## [electrico] Arquitectura electrónica FMX nueva generación: unidades de control (según central de fusibles)
- Aplica: Volvo FMX/FM nueva generación (VMCU) 2020+; FMX 2024 Brasil a validar
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX "Fuses and relays"; PDF es pág. 44-48)

Unidades de control que aparecen alimentadas desde la central de fusibles del FMX nueva generación:
| Sigla | Unidad | Fusible(s) |
|---|---|---|
| VMCU | Vehicle Master Control Unit (reemplaza a la VECU de la generación anterior) | F27 10 A, F28 20 A, F68 15 A |
| EMS | Engine Management System (ECM motor) | F41 15 A; cargas controladas por EMS F42 15 A, F44 10 A; relé K27 |
| TECU | Unidad de control de caja (I-Shift) | F70 20 A; relé K17 |
| ABS/EBS | Frenos | F37 20 A (camión), F46 20 A (remolque) |
| CIOM | Cab Input/Output Module | F63 10 A |
| FCIOM / CCIOM / RCIOM | Módulos de E/S de chasis delantero, central y trasero | fusibles principales 30 A |
| ACM | Aftertreatment Control Unit (postratamiento) | fusible principal 23 A |
| BBM | Body Builder Module (carrocero) | F19 15 A |
| CCM | Climatización | F38 20 A |
| DACU | Asistencia al conductor | F31 5 A |
| APM | Air Pressure Monitoring / secador | F32 10 A |
| LECM | Panel de control trasero (litera) | F80 3 A |
| Instrumento | Cluster | F24 5 A |
| OBD | Conector de diagnóstico | F62 5 A |
| FMS / Volvo Connect | Telemática | F66 3 A, F85 3 A, F91 10 A |
- Nota: la guía NA de 2010 describe la arquitectura antigua (VECU + ECM + ICM + TCM + GSCM + ACM); ver ficha NA.

## [electrico] Arquitectura NA de referencia: VECU, ECM, BBM, TCM, LCM (NA)
- Aplica: Volvo VN/VHD (referencia para FMX generación VECU)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: NA-S3 págs. 140-150 ; http://www.wheelingtruck.com/wp-content/uploads/diag-codes.pdf (ECM-DTC pág. 1-2)

- VECU: recoge los mandos del conductor (palanca de crucero, pedal acelerador + interruptor IVS, llave, presión A/C, freno de estacionamiento, interruptor PTO, pedales freno/embrague, presostato de freno, freno motor, sensor de velocidad VSS) y los envía por J1587/1708 y J1939. Salidas físicas: IVS redundante cableado al ECM, **alimentación del ECM** (motor Volvo) y salida PTO. Con motor Volvo, VECU y ECM se reparten control crucero, PTO y freno motor.
- "El ECM depende de la VECU para recibir los mandos de cabina; sin esa información el motor no funcionará correctamente" (NA-S3 pág. 41).
- BBM: extensión de la VECU para carroceros (grúas, mixer, etc.), montado junto a la VECU bajo el tablero (ver fichas BBM).
- TCM I-Shift: montado **sobre la caja**. Todas las cajas usan el bus ISO para pedir al motor modos de cambio y freno motor. No modificar sensores ni actuadores de la caja.
- LCM: controla toda la iluminación exterior y el limpiaparabrisas intermitente; sus salidas tienen protección tipo interruptor térmico y detectan sobrecorriente y circuito abierto (ver ficha iluminación añadida).
- ECM-DTC (EPA2010): 6 unidades (ECM, ICM instrumento, VECU, TCM, GSCM selector, ACM postratamiento). VECU en J1939 CAN1; ACM, sensores NOx y actuador VGT en **J1939-7 CAN2** hacia el ECM.

## [electrico] Redes de datos: J1939, J1587/J1708 e ISO 14229 — velocidades y resistencias (NA)
- Aplica: Volvo con motor Volvo (referencia NA; mismo principio en FMX/VM)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: NA-S3 págs. 60-62

| Red | Uso | Velocidad | Cableado |
|---|---|---|---|
| SAE J1939 (control) | señales de control entre ECU | 250 kbit/s | par trenzado CAN_H/CAN_L, 33 vueltas/m |
| SAE J1587/J1708 (información) | diagnóstico e información; respaldo si falla J1939 | 9,6 kbit/s | par trenzado, 40 vueltas/m |
| ISO 14229 (tren motriz) | programación y control ECM–ACM–TCM | 500 kbit/s | par 18 AWG blanco/naranja (DL2H/DL2L) |
- J1939: dos resistencias terminales (una cerca de la central de fusibles de cabina, otra dentro del ECM en motores Volvo). **Nunca tres.** Con llave OFF, resistencia CAN_H–CAN_L en el conector de diagnóstico = **50–70 Ω**.
- ISO 14229: medir entre cavidades **3 y 11 del conector de 16 pines = 50–70 Ω**; cada resistencia terminal por separado **110–130 Ω**.
- Colores: el texto de NA-S3 pág. 60 dice "verde (CAN_H) y amarillo (CAN_L)", mientras la tabla del conector de 9 pines (pág. 41) asigna "J1939 Bus (+) (Yellow)" y "(-) (Green)". El documento es contradictorio: identificar por pin, no por color.
- No empalmar ni conectar equipos a los cables J1939/J1587 (fallas de todos los sistemas electrónicos).

## [pinout_conector] Conector de diagnóstico de 9 pines (Deutsch) — pinout (NA)
- Aplica: Volvo VN/VHD (NA); verificar si el FMX/VM Brasil usa 9 o 16 pines
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 41 (Fig. 2 Diagnostic Connector Z01)

| Pin | Circuito | Función |
|---|---|---|
| A | X03DA11 | Masa |
| B | F12A1 | +Batería con fusible (permanente) |
| C | J1939HN4 | J1939 (+) |
| D | J1939LN4 | J1939 (-) |
| E | AD8A4 | ABS |
| F | J1587HN15 | J1708/J1587 (A) |
| G | J1587LN15 | J1708/J1587 (B) |
| H | AD7A4 | ABS |
| J | F15D5 | +Contacto (ignición) |

## [pinout_conector] Conector de diagnóstico OBD de 16 pines (SAE J1962) — asignación Volvo (NA)
- Aplica: Volvo con OBD 2013+ (NA); FMX nueva generación tiene fusible "OBD" F62 5 A
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 42-63

| Pin | Asignación |
|---|---|
| 1 | Señal de llave (ignición) para herramienta |
| 3 | SAE J1939-15 CAN_H |
| 4 | Masa de chasis |
| 5 | Masa de señal |
| 6 | CAN_H ISO 15765-4 |
| 11 | SAE J1939-15 CAN_L |
| 12 | J1708/J1587 (+) |
| 13 | J1708/J1587 (-) |
| 14 | CAN_L ISO 15765-4 |
| 16 | +Batería |
| 2, 7, 10, 15 | no usados; 8, 9 no asignados |
- Ubicación NA: panel lateral inferior (kick panel) del lado del conductor. Con PC/herramienta se leen los códigos de todas las unidades y se programa.

## [fusibles_reles] Ubicación de las centrales de fusibles/relés en FMX nueva generación y acceso
- Aplica: Volvo FMX/FM nueva generación
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX; PDF es pág. 44-45)

- En la cabina hay **dos ubicaciones**: (1) **central de fusibles y relés en el centro del tablero de instrumentos**; (2) **fusibles y relés para la carrocería delante del asiento del acompañante**. En o bajo cada tapa hay una calcomanía con la posición y función.
- Acceso a la central del tablero: retirar la goma protectora de la bandeja, girar los tornillos de bloqueo 90° antihorario (con una moneda), tirar la manilla hacia arriba y retirar la tapa.
- Acceso a la de carrocería: girar los tornillos de bloqueo 90° antihorario.
- Poner el sistema en modo "Estacionado" (Parked) y, si se puede, apagar el circuito antes de cambiar un fusible: el portafusible puede quemarse si queda con tensión. Si un fusible se repite en la misma posición, revisar el sistema eléctrico. Nunca sobredimensionar.
- Los fusibles/relés específicos del carrocero están en la documentación del carrocero (Body Builder).

## [fusibles_reles] FMX nueva generación: fusibles F1 a F30 (central del tablero)
- Aplica: Volvo FMX 420 2024 (E941303), FMX 420 2025 (EE603547), FMX 540 2024 (E944562) — tabla CONFIRMADA en sus guías reales (FMX-R pág. 308-310), con las diferencias de la ficha "FMX flota: diferencias de la central de fusibles"; también FMX/FM nueva generación UE
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX "List of blade fuses"; PDF es pág. 45)

| N° | A | Función |
|---|---|---|
| F1 | 10 | Toma 12 V |
| F2 | — | (libre) |
| F3 | 10 | TV; ERA GLONASS |
| F4, F5 | — | (libres) |
| F6 | 5 | Carrocería, interruptor |
| F7 | 30 | Carrocería |
| F8 | 20 | Carrocería |
| F9 | 10 | Sistema de cámaras-monitor (espejos) |
| F10 | 3 | Puertos USB |
| F11 | 15 | Faro auxiliar en techo |
| F12 | 15 | Baliza giratoria en techo |
| F13 | 15 | Calefacción de asiento; Alcolock |
| F14 | — | (libre) |
| F15 | 10 | Letrero de cabina |
| F16 | 10 | Iluminación total del letrero |
| F17 | — | (libre) |
| F18 | 3 | — |
| F19 | 15 | **Body Builder Module (BBM)** |
| F20 | 20 | Panel de puerta / alzavidrios derecho |
| F21 | 3 | Pantalla lateral |
| F22 | 5 | Parasoles; elevación eléctrica de litera |
| F23 | 3 | Tacógrafo |
| F24 | 5 | **Instrumento (cluster)** |
| F25 | 3 | Sistema de peaje |
| F26 | — | (libre) |
| F27 | 10 | **VMCU** |
| F28 | 20 | **VMCU** |
| F29 | 10 | Espejo calefaccionado derecho |
| F30 | 10 | Espejo calefaccionado izquierdo |

## [fusibles_reles] FMX nueva generación: fusibles F31 a F60
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024 de la flota (confirmado en FMX-R pág. 309, ver diferencias en ficha aparte); FMX/FM nueva generación UE
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX; PDF es pág. 46)

| N° | A | Función |
|---|---|---|
| F31 | 5 | DACU asistencia al conductor |
| F32 | 10 | APM monitoreo presión de aire, secador |
| F33 | 3 | Cargador control remoto de trabajo |
| F34 | 5 | Bloqueo de tapa de servicio |
| F35 | 15 | Ventilador del enfriador de estacionamiento |
| F36 | 5 | Cámara |
| F37 | 20 | **ABS/EBS unidad de freno** |
| F38 | 20 | CCM climatización |
| F39 | 20 | Calefactor de línea de combustible |
| F40 | 3 | Ignición del tacógrafo |
| F41 | 15 | **EMS (ECM motor)** |
| F42 | 15 | Cargas controladas por EMS |
| F43 | 10 | Calefactor del filtro de combustible |
| F44 | 10 | Cargas controladas por EMS |
| F45 | 30 | Bomba de volteo de cabina |
| F46 | 20 | ABS/EBS remolque |
| F47, F48 | — | (libres) |
| F49 | 50 | Toma de corriente para carrocería |
| F50 | 30 | Cafetera |
| F51 | 20 | Motor limpiaparabrisas |
| F52 | 15 | Motor escotilla de techo |
| F53 | 5 | — |
| F54 | — | (libre) |
| F55 | 3 | Alarma |
| F56 | 10 | — |
| F57 | 10 | Iluminación interior |
| F58 | 15 | Amplificador |
| F59 | 15 | Convertidor de voltaje, TV |
| F60 | 15 | Convertidor de voltaje, radio, teléfono, toma 12 V |

## [fusibles_reles] FMX nueva generación: fusibles F61 a F91
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024 de la flota (confirmado en FMX-R pág. 309-310, ver diferencias en ficha aparte); FMX/FM nueva generación UE
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX; PDF es pág. 46-47)

| N° | A | Función |
|---|---|---|
| F61 | 20 | Panel de puerta / alzavidrios izquierdo |
| F62 | 5 | **Conector de diagnóstico OBD** |
| F63 | 10 | **CIOM módulo E/S de cabina** |
| F64 | 15 | Toma 24 V en tablero |
| F65 | 15 | Toma 24 V pie de litera |
| F66 | 3 | Volvo Connect / telemática |
| F67 | 15 | Puertos USB |
| F68 | 15 | **VMCU** |
| F69 | 15 | Calefactor de estacionamiento |
| F70 | 20 | **TECU caja de cambios (I-Shift)** |
| F71 | 15 | Lavafaros |
| F72 | 5 | — |
| F73 | 30 | Carrocería activa en modo conducción |
| F74 | 20 | Carrocería activa en modo conducción |
| F75 | 10 | Refrigerador |
| F76 | 15 | — |
| F77, F78 | — | (libres) |
| F79 | 10 | Sensor de seguridad |
| F80 | 3 | Panel de control trasero (LECM) |
| F81 | 5 | Airbag |
| F82 | 3 | ERA GLONASS |
| F83, F84 | — | (libres) |
| F85 | 3 | FMS gestión de flota |
| F86, F87 | — | (libres) |
| F88 | 5 | Alcolock |
| F89 | — | (libre) |
| F90 | 15 | Asiento eléctrico |
| F91 | 10 | FMS gestión de flota |
- Diagnóstico rápido: sin comunicación con el camión por OBD → revisar F62; caja I-Shift muerta → F70 y relé K17; motor sin ECM → F41 y relé K27; carrocero/BBM sin funciones → F19, F6-F8, F73-F74, relés K07/K20.

## [fusibles_reles] FMX nueva generación: relés K01 a K28
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024 de la flota (confirmado en FMX-R pág. 310-311; K03/K04 escotilla, K08 = "Accesorios" y K22 = "Encendido" en la guía real); FMX/FM nueva generación UE
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX "List of relays"; PDF es pág. 47) ; FMX-R pág. 310-311

| N° | Tipo | Función |
|---|---|---|
| K01 | ISO micro 10 A | — |
| K02 | ISO micro 10 A | Refrigerador |
| K03 | ISO mini 20 A | Motor escotilla techo 2 |
| K04 | ISO mini 20 A | Motor escotilla techo 1 |
| K05 | ISO mini 20 A | Limpiaparabrisas on/off |
| K06 | ISO mini 20 A | Limpiaparabrisas baja/alta |
| K07 | ISO power 40 A | **Carrocería, fusibles** |
| K08 | ISO power 40 A | Cafetera |
| K09 | ISO micro 10 A | Calefacción asiento; Alcolock |
| K10 | ISO mini 20 A | Faro auxiliar techo |
| K11 | ISO power 40 A | Amplificador; convertidor; iluminación interior |
| K12 | ISO micro 10 A | Letrero de cabina |
| K13 | ISO mini 20 A | Baliza giratoria techo |
| K14 | ISO power 40 A | Toma 24 V; USB; Alcolock |
| K15 | ISO micro 10 A | Iluminación total letrero |
| K16 | ISO mini 20 A | Lavafaros |
| K17 | ISO mini 20 A | **TECU (caja)** |
| K18 | ISO micro 10 A | — |
| K19 | ISO mini 20 A | — |
| K20 | ISO power 40 A | **Ignición para carrocería, activa en posición conducción** |
| K21 | ISO micro 10 A | Espejos calefaccionados |
| K22 | ISO mini 20 A | Ignición FMS, ERA GLONASS |
| K23 | ISO power 40 A | — |
| K24 | ISO micro 10 A | Asiento eléctrico |
| K25 | ISO micro 10 A | — |
| K26 | ISO micro 10 A | Cámara |
| K27 | ISO power 40 A | **EMS (ECM motor)** |
| K28 | ISO power 40 A | Bomba volteo cabina |

## [fusibles_reles] FMX: fusibles principales en la caja de baterías y torque de apriete
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024 de la flota (idéntico en FMX-R pág. 311-312, fusibles numerados 1 a 12 en ese orden); FMX/FM nueva generación y FMX Classic
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=66531 (DG-FMX "Main fuses"; PDF es pág. 48)

- Ubicación: caja de fusibles principales **dentro de la caja de baterías en el bastidor** (FMX: caja de baterías lado izquierdo, detrás de la cabina). Normalmente duran toda la vida útil; si uno se funde, revisar el sistema eléctrico.
| Fusible | Circuito |
|---|---|
| 200 A | Carrocero (bodybuilder) |
| 100 A | FRC central de fusibles y relés de cabina |
| 30 A (×2) | FCIOM control chasis delantero |
| 30 A (×2) | CCIOM control chasis central |
| 30 A (×2) | RCIOM control chasis trasero |
| 30 A | FAS dirección eje delantero |
| 40 A | PCCU enfriador de estacionamiento |
| 23 A | **ACM unidad de postratamiento** |
| 23 A | Dirección eje auxiliar |
- Torques de las tuercas de los fusibles de enlace (con arandela elástica cautiva): **M5 = 4,5 Nm ±5 %; M8 = 20,0 Nm ±5 %; M10 = 40,0 Nm ±5 %**. Poco torque genera calentamiento; exceso deforma y agrieta.
- Síntoma típico: pérdida de un CIOM de chasis (luces, sensores de chasis) o del ACM (sin dosificación AdBlue, códigos de comunicación CAN2) → revisar estos fusibles principales antes que las unidades.

## [fusibles_reles] FMX Classic: diferencias de la central de fusibles respecto a la nueva generación
- Aplica: Volvo FMX Classic (chasis demo CL0FMX)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=ACL0FMX&l=en&topic=151433 (DG-FMXC "Fuses and relays")

La numeración es la misma (F1-F91, K01-K28, mismos fusibles principales y torques). Diferencias relevantes:
- F4 15 A y F5 15 A existen (sin función asignada); F18 3 A = HMI (unidad de interfaz del conductor); F24 3 A (no 5 A) = instrumento; F51 limpiaparabrisas 15 A (no 20 A); F53 5 A conmutador de video; F56 10 A escotilla (FM); F60 15 A convertidor; F66 3 A Dynafleet/telemática; F67 15 A encendedor; F85 3 A alimentación FMS en conducción; F91 10 A alimentación FMS con contacto.
- Relés: K03/K04 sin función; K08 accesorios; K14 toma 24 V, encendedor, alcolock; K22 ignición.
- Coinciden: F19 15 A BBM, F27/F28/F68 VMCU, F41 15 A EMS, F62 5 A OBD, F63 10 A CIOM, F70 20 A TECU, K17 TECU, K20 ignición carrocería, K27 EMS.

## [procedimiento_diagnostico] Seguridad antes de trabajar en el sistema eléctrico (interruptor principal, baterías)
- Aplica: Volvo FMX/FM
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=67885 ("Electrical system work") y topic=84840 ("Main switch")

- El interruptor principal (detrás de la cabina) lleva el camión directo al modo "Estacionado"; los intermitentes indican que está desconectado. **No es un cortacorriente de batería.**
- Desconexión de batería: desconectar el interruptor principal → **esperar 30 segundos** → soltar el cable negativo. El sistema debe estar en modo "Parked".
- Reglas: negativo se desconecta primero y se conecta al último; nunca hacer funcionar el alternador sin batería ni desconectar baterías con el motor en marcha; al cargar, desconectar un cable de batería pero cargar **a través del sensor de batería** (en el negativo) si existe; abrir el interruptor principal para cambiar fusibles; con baterías desconectadas no se puede accionar el freno de estacionamiento.
- **No conectar equipos de ayuda de arranque (boosters/arrancadores)**: generan tensiones muy altas que dañan unidades de control.

## [procedimiento_diagnostico] Soldadura eléctrica en el chasis (proteger unidades de control)
- Aplica: Volvo FMX/FM; Renault Trucks C (mismo texto en su guía)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=68671 ("Electric welding, regulations")

- Proteger o retirar componentes sensibles al calor (cables eléctricos y de aire) cerca del punto.
- Limpiar pintura, óxido, grasa en el punto a soldar y en el punto de masa.
- La masa de la máquina **siempre conectada a la pieza que se suelda, lo más cerca posible** del punto; si se unen dos piezas, ambas a la masa.
- Evitar que las carcasas de unidades de control toquen el electrodo o la pinza de masa. Usar preferentemente corriente continua.
- Soldando en cabina: desconectar el airbag. Pintar el punto después.
- (Complemento operacional, no del documento: combinar con la desconexión de baterías de la ficha anterior.)

## [electrico] Arranque de emergencia con cables (24 V)
- Aplica: Volvo FMX/FM con caja de baterías lateral
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=53173 ("Emergency starting")

1. Llave en 0. Verificar que la batería de ayuda sea de 24 V. Motor del vehículo donante apagado, vehículos sin tocarse.
2. Rojo: + batería donante → + batería del camión.
3. Negro: − batería donante → **punto de masa alejado de la batería** del camión (limpio y sin pintura; toda la corriente debe pasar por el sensor de batería).
4. Arrancar el donante y mantener ~1000 rpm unos minutos; arrancar el camión.
5. Retirar negro de la masa, negro del donante, luego el rojo.
- Después: cargar la batería con cargador (~20 h para carga completa). Un problema de arranque indica consumo excesivo con motor apagado o falla de carga: buscar la causa raíz.

## [especificacion] Baterías: reglas de carga y descarga profunda
- Aplica: Volvo FMX/FM (y Renault Trucks C: mismas recomendaciones)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=67985 ("Batteries")

- El alternador no carga al 100 %; en condiciones óptimas llega a ~90 %.
- Cargar con cargador externo **al menos cada tres semanas**; si hay equipos que consumen con motor apagado (ej. plataforma/elevador, bomba eléctrica) cargar **a diario**.
- **No descargar bajo 45 %** de capacidad: la descarga profunda daña permanentemente la batería.
- Ubicación FMX: caja de baterías lado izquierdo del chasis, justo detrás de la cabina.

## [electrico] Modos de función de la alimentación (Parked/Living/Accessory/Driving/Crank)
- Aplica: Volvo FMX/FM con llave
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=84709 ("Function positions, power supply")

| Modo | Llave | Comentario |
|---|---|---|
| Parked (0) | sin llave | mínimo de funciones; automático 2 h después de sacar la llave (+2 h cada vez que se abre la puerta); con llave puesta pasa a Parked a las 4 h (cabina día) |
| Living (0) | llave en 0 | radio, luz interior, calefactor; ~1 noche; pasa a Parked a las 4 h. **Algunas funciones de carrocero solo quedan activas 4 h** |
| Accessory (1) | posición 1 | trabajo con motor apagado: plataforma, luces de trabajo, Volvo Connect |
| Driving (2) | posición 2 | todas las funciones |
| Crank (3) | posición 3 | arranque; muchas funciones se cortan temporalmente |
- Si el interruptor principal se desconecta, el camión va directo a Parked. El taller puede cambiar los tiempos.
- Diagnóstico: equipos de carrocero que "se apagan solos" con motor detenido → revisar si el camión pasó a Parked por temporizador.

## [lectura_codigos_tablero] FMX nueva generación: notificaciones del display (rojo/amarillo/blanco) y menú
- Aplica: Volvo FMX/FM/FH nueva generación
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=62361 ("Messages in the instrument display") y topic=62408 ("Instrument display menu")

- **Rojo** (más crítico, símbolo rojo + señal acústica + halo rojo): detener el camión y apagar el motor; no seguir hasta reparar. Se puede reconocer con OK/Back pero reaparece a los **30 s** si la falla sigue.
- **Amarillo** (medio): reparar lo antes posible; reaparece en el siguiente arranque si sigue la falla.
- **Blanco**: información de estado; reparar en la próxima mantención.
- Las notificaciones rojas y amarillas reconocidas y aún activas quedan en el menú **NOTIFICATIONS**. El símbolo de notificación abajo al centro indica la más crítica (color) y el número de notificaciones activas. Los "toasts" son avisos breves (máx. 10 s).
- Menú del display (tecla Menu del teclado del volante): RESET TRIP COMPUTER, NOTIFICATIONS, RECENT CALLS, **MAINTENANCE** (Pre-trip check, Service information, Fuel Priming*, Water Draining*, Software Update, Vehicle Data).
- Limitación: el menú del conductor de nueva generación muestra mensajes en texto; los códigos DTC (SPN/FMI) completos se leen con Tech Tool por el conector OBD.

## [lectura_codigos_tablero] FMX Classic / display DID: menú Mantenimiento > Diagnóstico (unidades y códigos)
- Aplica: Volvo FMX/FM Classic con display de información al conductor (DID)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=ACL0FMX&l=en&topic=207874 ("Maintenance menu, driver information display")

Ruta: **Display de información → Mantenimiento → Diagnóstico**.
- "Aquí encontrará información sobre las unidades de control del camión. Si una unidad de control tiene uno o más códigos de falla, también se listan aquí."
- "Prueba de instrumento": prueba de símbolos (enciende todos los testigos), de indicadores (agujas de mínimo a máximo), de display y de altavoces. ESC cancela.
- Mantenimiento → **Mensajes del vehículo**: mensajes ordenados por gravedad (rojo: detener y apagar; amarillo: seguir instrucciones/taller; blanco: próxima mantención). Se reconocen con ESC.
- Mantenimiento → Datos de uso (distancia, consumo, horas motor, ralentí, **tiempo y combustible de PTO**): el reseteo pide contraseña; de fábrica **0000**.
- Mantenimiento → Datos del vehículo: totales de vida (horas, ralentí, PTO, revoluciones) — útil para verificar uso de bomba de riego/trasvasije.

## [lectura_codigos_tablero] Formato de los códigos Volvo: SA/SPN/FMI (J1939) y MID/PID/SID/PPID/PSID (J1587)
- Aplica: Volvo con EMS (D13/D11/D16; D8K mismo esquema)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: http://www.wheelingtruck.com/wp-content/uploads/diag-codes.pdf (ECM-DTC pág. 2-4)

- J1939: **SA** (dirección de origen = unidad), **SPN** (parámetro), **FMI** (tipo de falla).
- J1587 (formato antiguo, aún usado por Volvo): **MID** (unidad; ECM = MID 128 según ECM-DTC; instrumento = MID 140 según NA-S3 pág. 142; VECU = MID 144, mensajes J1587 "MID 144 (since 1998)" en NA-S3 pág. 52), **PID** (parámetro), **PPID** (parámetro propietario Volvo), **SID** (componente), **PSID** (componente propietario Volvo), **FMI**.
- Ejemplos de equivalencia: SPN 110 = MID 128 PID 110 (temperatura refrigerante); SPN 637 = MID 128 SID 22 (sensor cigüeñal); SPN 5246 = MID 128 PSID 46 (inducción SCR).
- MID 144 VECU y MID 140 instrumento: la guía NA de instrumento es "Group 38 MID 140 DTC Guide" PV776-88955132 (http://www.wheelingtruck.com/wp-content/uploads/PV77688955132.pdf, VN desde 01.2007).

## [lectura_codigos_tablero] Tabla FMI J1939 (0-31) — significado
- Aplica: todas las ECU J1939 (Volvo, Renault)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: http://www.wheelingtruck.com/wp-content/uploads/diag-codes.pdf (ECM-DTC pág. 3)

| FMI | Significado |
|---|---|
| 0 | Dato válido sobre rango normal — nivel más severo |
| 1 | Dato válido bajo rango normal — nivel más severo |
| 2 | Dato errático, intermitente o incorrecto |
| 3 | Voltaje sobre lo normal o corto a positivo |
| 4 | Voltaje bajo lo normal o corto a masa |
| 5 | Corriente bajo lo normal o circuito abierto |
| 6 | Corriente sobre lo normal o circuito a masa |
| 7 | Sistema mecánico no responde o desajustado |
| 8 | Frecuencia, ancho de pulso o período anormal |
| 9 | Tasa de actualización anormal (mensaje CAN faltante) |
| 10 | Tasa de cambio anormal |
| 11 | Causa raíz desconocida |
| 12 | Dispositivo o componente inteligente defectuoso |
| 13 | Fuera de calibración |
| 14 | Instrucciones especiales |
| 15 | Sobre rango — nivel menos severo |
| 16 | Sobre rango — nivel moderadamente severo |
| 17 | Bajo rango — nivel menos severo |
| 18 | Bajo rango — nivel moderadamente severo |
| 19 | Dato de red recibido con error |
| 20-30 | Reservados SAE |
| 31 | Condición existe |
- FMI J1587 (0-15) igual hasta 14, salvo 10 = "vibraciones anormalmente fuertes" y 15 = reservado (ECM-DTC pág. 4).

## [lectura_codigos_tablero] Borrado de códigos: no se borran desde el instrumento (usar herramienta)
- Aplica: Volvo EPA2010 en adelante (NA); criterio general grupo Volvo
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: http://www.wheelingtruck.com/wp-content/uploads/diag-codes.pdf (ECM-DTC pág. 1-2)

- "Los DTC ya no se pueden borrar usando el display digital del instrumento y la palanca": se requiere herramienta de diagnóstico (Premium Tech Tool, www.premiumtechtool.com) conectada al puerto de comunicación.
- Algunas fallas provocan **modo derrateo** (sustituye un valor de sensor, potencia limitada) o apagado del motor si puede dañarse.
- Excepciones de campo documentadas: códigos de freno temporales se borran con la **prueba de pedal de freno** (ficha frenos); los códigos de NOx "no borrables" de Euro 5 quedan 400 días (ficha postratamiento).

## [frenos] Prueba de pedal de freno para borrar códigos de freno temporales
- Aplica: Volvo FMX/FM nueva generación con llave
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=70016 ("Brake system")

- Uso: fallas temporales de frenos (fuga de aire del remolque, sistema de remolque sin llenar). Para borrar el código cuando la falla ya no está se hace una prueba de pedal.
- Condiciones para que aparezca "Brake pedal test": código de freno activo **y** el camión pasó por el modo Parked (0). Se puede forzar Parked con el interruptor principal.
- Seguir las instrucciones del display. Resultado: "Test correctly performed. Brakes working correctly." (código borrado) o "… Brake fault remains." (falla persiste → taller). Si la prueba falla, se vuelve a pedir al pasar de Parked a un modo superior.

## [frenos] Secador de aire (APM): control, reseteo de servicio y punto de llenado externo
- Aplica: Volvo FMX/FM nueva generación
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=70016 ("Brake system")

- El postratamiento Euro 6 consume aire continuamente: el compresor trabaja a intervalos regulares.
- Revisar agua en estanques al menos semanalmente (tirar anillos de purga). Si hay agua: cambiar desecante y revisar secador. Usar solo cartuchos Volvo con filtro de aceite. **No usar anticongelante (alcohol)** con secador.
- Reset de servicio del cartucho: MAINTENANCE → Service Information → Options → Air Dryer Cartridge (protegido por contraseña; la de fábrica figura en las especificaciones del camión). Solo tras cambiar el cartucho.
- Llenado de aire desde fuente externa: usar siempre la toma **SF (system fill)** del soporte (atrás o lado izquierdo del chasis) para que el aire pase por el secador. **PX2, PX3, PX4** = tomas de prueba de presión de freno de ejes traseros.

## [postratamiento] FMX Euro 6: SCR + DPF, sistema OBD y patrones de la lámpara MIL
- Aplica: Volvo FMX/FM Euro 6 (variante EM-EU6). NO aplica a los FMX de la flota (son Euro 5/P7 sin DPF)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=53778 ("Exhaust gas cleaning system")

- Euro 6: AdBlue inyectado en el silenciador que integra catalizador SCR y **filtro de partículas (DPF)**. Requiere diésel sin azufre (<10 ppm); combustible incorrecto daña el sistema.
- OBD vigila: nivel de NOx, nivel de partículas (PM), calidad y disponibilidad de AdBlue y otras funciones de motor/postratamiento. Fallas clasificadas A (efecto grande), B (medio), C (menor).
- MIL (Check engine): con llave en "Drive" y motor detenido, la MIL parpadea en patrones para informar el estado (también parpadea cuando todo está bien). Conduciendo: si queda encendida los primeros 15 s o durante la marcha hay una falla → taller.

## [postratamiento] FMX Euro 6: vigilancia SCR y derrateo (25 % de par y 20 km/h)
- Aplica: Volvo FMX/FM Euro 6. NO aplica a los FMX de la flota (Euro 5/P7: derrateo 40 %, ver ficha propia)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=53778 ("SCR System monitoring")

- Se vigila: nivel bajo de AdBlue, consumo incorrecto de AdBlue, calidad incorrecta de AdBlue, componentes que afectan NOx.
- Si la falla no se corrige, el rendimiento baja gradualmente: aviso de reducción de potencia → **par del motor reducido 25 %** → aviso de limitación de velocidad → **velocidad limitada a 20 km/h**. Al reparar la causa vuelve el rendimiento normal.
- Códigos asociados típicos en `codigos/volvo.json`: SPN 5246 (inducción), 4094/4095 (NOx por calidad/dosificación), 1761 (nivel), 3226/3216 (sensores NOx).

## [postratamiento] FMX Classic / Euro 5: vigilancia de NOx, códigos no borrables 400 días y derrateo
- Aplica: Volvo FM/FMX Euro 5 (EM-EU5). Superada para los FMX de la flota por la ficha "FMX flota: ARLA 32, control de NOx y derrateo 40 %"; posible referencia para VM D8K Euro 5 (validar)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=ACL0FMX&l=en&topic=129284 ("Exhaust gas cleaning system", variante EM-EU5)

- Euro 5: AdBlue inyectado antes del silenciador con catalizador SCR (sin DPF en este texto). Diésel ≤10 ppm de azufre.
- Aviso de AdBlue: con ~10 % restante se enciende el indicador + mensaje; tanque vacío → indicador + mensaje + MIL; falla de circulación de AdBlue → CHECK amarilla + mensaje + MIL. La circulación de AdBlue también enfría componentes.
- Sin AdBlue: la siguiente vez que el camión esté detenido con motor en marcha (p. ej. semáforo) se reduce la potencia; el display avisa antes. Vuelve a normal al rellenar.
- "Códigos no borrables": se generan por (1) nivel bajo de AdBlue, (2) nivel de NOx incorrecto, (3) falla del sistema de monitoreo de NOx. Se guardan **400 días** aunque la falla esté reparada, y registran las horas de motor con la falla activa.
- Derrateo Euro 5 (precedido por CHECK + MIL): NOx incorrecto, estanque AdBlue vacío, o **el sistema no pudo monitorear NOx durante 36 h de operación**. La monitorización se limita con motor frío, temperatura ambiente baja y altura extremadamente alta (relevante en faenas de altura).

## [postratamiento] AdBlue: especificación, consumo, congelamiento y daño a conectores
- Aplica: Volvo FMX/FM/VM con SCR
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=53778 (sección AdBlue) y topic=70168 ("AdBlue tank cleaning")

- AdBlue = urea 32,5 % en agua destilada, norma **ISO 22241-1**. Fluido fuera de norma: se pierde la limpieza y puede dañarse el SCR.
- Consumo normal aprox. 10 % del diésel (ej. 100 L diésel ≈ 8 L AdBlue según la guía).
- Congela a aprox. **−11 °C**; el sistema es calefaccionado.
- La bomba hace un "tic" en cada carrera: es normal.
- **AdBlue es muy corrosivo para conectores: si un conector o cable tuvo contacto con AdBlue debe reemplazarse, limpiarlo no basta.** Derrame: enjuagar con agua.
- Limpieza del estanque (si se llenó con diésel u otro fluido): enjuagar con agua (detergente doméstico si hace falta) y enjuagar a fondo para no dejar residuos que dañen el catalizador; drenar por el tapón inferior.

## [postratamiento] DPF (Euro 6): regeneración automática, desconexión y regeneración manual
- Aplica: Volvo FMX/FM Euro 6 con motor D11/D13 (DRC-AMII). NO aplica a los FMX de la flota (sin DPF según su guía real)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=54119 ("Diesel particulate filter")

- Automática: solo conduciendo con carga suficiente; sube levemente el ralentí y el freno auxiliar se activa parcialmente (cambia el ruido). Mensaje "Automatic regeneration in progress" + símbolo de alta temperatura de escape.
- Desactivar la automática (zonas con riesgo de incendio): parte superior del interruptor; solo se desactiva **bajo ~40 km/h** y la velocidad queda **limitada a ~40 km/h** mientras esté desactivada.
- Manual (necesaria tras horas a baja carga o **ralentí continuo**, típico de riego): mensajes "Regeneration possible at standstill. Regeneration needed.", "Start regeneration immediately. Park vehicle safely.", "Allow for regeneration…", "…Regeneration inhibited.". Dura **30 a 60 min**, ralentí muy elevado.
- Condiciones para la manual: hollín alto pero no crítico; camión detenido; freno de estacionamiento aplicado; caja en neutro; motor a temperatura de operación; **toma de fuerza desconectada**. Iniciar: parte inferior del interruptor; se interrumpe pulsando de nuevo. "Regeneration not needed" si el hollín no es alto.
- Si el hollín llega a nivel crítico, el filtro debe repararse o desmontarse en taller. Cenizas: aceite VDS-4.5 recomendado para mayor intervalo de servicio.

## [motor] Ajuste permanente del ralentí (vibraciones tras carrozar o equipos)
- Aplica: Volvo FMX/FM nueva generación (teclado izquierdo del volante)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=53402 ("Engine speed control")

Recomendado: refrigerante sobre ~50 °C, camión detenido en ralentí sin acelerador.
1. Soltar acelerador y **pisar el freno** (mantenerlo pisado todo el ajuste). El control de régimen constante no debe estar activo.
2. Mantener la tecla "resume" (1) ≥ 2 s → el régimen baja al mínimo ajustable. Soltar.
3. Ajustar con + (2) / − (3).
4. Mantener "resume" (1) ≥ 2 s → mensaje de guardado. Soltar tecla y freno.
- Si hay un error en la secuencia se conserva el ralentí anterior. Durante regeneración del DPF el ralentí sube levemente y no se puede cambiar.

## [motor] Control de régimen constante (para bombas / equipos) desde el teclado del volante
- Aplica: Volvo FMX/FM nueva generación
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=53402 ("Engine speed control")

- Solo disponible a baja velocidad. Tecla de encendido (6) → menú en display → elegir control de régimen con +/− → SET (4).
- + / − suben/bajan el régimen; **resume (1) lleva al valor preprogramado (normalmente 1000 rpm)**; tecla cero (5) vuelve al régimen original; mantener (5) desactiva.
- Con opción ULC (ultra low crawler): mantener velocidades bajo 4 km/h (bajar a 600 rpm con el camión rodando).

## [implemento] Toma de fuerza (PTO) Volvo: reglas de acople y régimen
- Aplica: Volvo FMX/FM con PTO de motor o de caja (I-Shift AMT) — guía UE demo. Para los FMX de la flota ver ficha "FMX flota: toma de fuerza" (difiere en el rearranque)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=85014 ("Power take-off")

- Todas las PTO se desacoplan al apagar el motor y quedan desacopladas al volver a arrancar. **Excepción: si el motor se apagó con parada remota, la PTO no se desacopla y se acopla al rearrancar.**
- Régimen para acoplar la PTO: **bajo 1000 rpm**. No subir el régimen más allá de lo recomendado por el carrocero; se puede programar un régimen máximo para proteger el equipo.
- PTO de caja I-Shift: se acopla con el interruptor (cualquier programa); símbolo PTO en display. Si se acopla con la palanca en N, se puede mover el camión eligiendo A o M (la PTO se detiene mientras la caja cambia). El camión debe estar detenido al acoplar/desacoplar; no cambiar de marcha en trayecto con PTO.
- Régimen aumentado en N: con palanca en N elegir **N1 o N2** con +/−; **N2 da ~30 % más régimen de PTO que N1**.

## [implemento] BBM (Body Builder Module): qué es y cuándo se instala (NA)
- Aplica: Volvo VHD con motor Volvo (NA); FMX nueva gen tiene BBM (fusible F19 15 A)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 140

- El BBM es una extensión de la VECU para superestructuras (mixer, recolector, grúas). Va en una unidad junto a la VECU, bajo el tablero. En NA es opcional (variante ELCE-CK).
- Se requiere cuando hay: más de un modo PTO; límites conmutables de régimen o par; parada remota del motor; entrada de ralentí forzado (interlock de acelerador); límite de velocidad conmutable; segundo pedal/acelerador remoto; programación PTO compleja (varios modos, interlocks, split-shaft); control remoto del motor por J1939; salidas generadas según velocidad/estado.

## [pinout_conector] BBM conector A (naranja, 30 vías) — pinout (NA)
- Aplica: Volvo VHD BBM VECU4 (NA); validar en FMX Brasil
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 123-124

| Pin | Función | Tipo |
|---|---|---|
| A1 | PTO remoto velocidad DEC | entrada activa alta |
| A2 | PTO remoto velocidad INC | entrada activa alta |
| A3 | PTO Modo 3 | entrada activa alta |
| A4 | PTO Modo 1 | entrada activa alta |
| A5 | PTO Modo 4 | entrada activa alta |
| A6 | Parada de motor, interruptor NA a +V | siempre habilitada: cerrar = apaga motor |
| A7 | Ralentí forzado | entrada activa alta |
| A8-A10, A21 | uso fábrica — no conectar | |
| A12 | Masa principal ECU | |
| A13 | Alimentación principal ECU | |
| A15 / A16 | CAN4 High / Low (bus J1939 del carrocero) | bidireccional |
| A17 | Límite de régimen del motor | entrada activa alta |
| A18 / A19 / A20 | PTO2 / PTO3 / PTO4 entrada-interruptor tablero | activas altas |
| A24 | Marcha neutro | entrada activa alta |
| A25 | Límite de par 1 | entrada activa baja |
| A26 | Límite de velocidad de ruta | entrada activa baja |
| A27 | Parada de motor, interruptor NC a masa | debe habilitarse por software: abrir = apaga |
| A28 | Split bajo | entrada activa baja |
| A29 | Caja divisora (split box) | entrada activa alta |
| A14, A22, A23, A30 | reserva | |
- Notas: NEUTRO y SPLIT BAJO son bloqueos programables de PTO; si llega el mensaje J1939 ETC2 de la caja, tiene prioridad sobre el pin. La entrada split box permite superar temporalmente el límite de velocidad con freno de estacionamiento (PTO split-shaft).

## [pinout_conector] BBM conector B (blanco, 30 vías) y C (verde, 5 vías) — pinout (NA)
- Aplica: Volvo VHD BBM VECU4 (NA); validar en FMX Brasil
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 125-126

Conector B:
| Pin | Función | Tipo |
|---|---|---|
| B1 | Habilitación arranque remoto | salida activa baja |
| B2 / B3 / B4 | Salida PTO2 / PTO3 / PTO4 (B4 también HSA) | salidas activas bajas (máx. 1 A c/u) |
| B5 | Alimentación de interruptores PTO dual I-Shift | solo para interruptores del BBM |
| B9 | Sensor 2º acelerador | analógica (≥1 kΩ) |
| B10 / B26 | Alimentación sensores #1 / #2 (~5 V) | solo sensores del BBM |
| B12 | Habilitación 2º pedal/acelerador remoto | entrada activa baja |
| B16 | Salida de advertencia | activa baja |
| B18 | Salida activada por bus de datos | activa baja |
| B19 | Alimentación #3 (~Vbatt) | solo interruptores del BBM |
| B21 | PTO Modo 2 | entrada activa alta |
| B22 / B23 | Masa analógica | solo sensores del BBM |
| B25 | Alimentación #5 (6,5-9 V) | VSS alimentado |
| B28 | Salida de velocidad | activa alta |
| B30 | IVS del 2º acelerador | entrada activa alta |
Conector C: C1 J1587 (B), C2 J1587 (A), C3 sin conexión, **C4 J1939 CAN_H, C5 J1939 CAN_L** (bus principal).

## [implemento] BBM: modos de régimen PTO 1-4 — parámetros y valores por defecto (NA)
- Aplica: Volvo VHD BBM/VECU4 (NA, Premium Tech Tool 2); referencia para parametrizar bomba de riego/trasvasije
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 110-116

- Hasta 4 regímenes PTO preprogramados por cable: PTO_Mode1 (pin A4, actúa en la VECU), Mode2 (B21), Mode3 (A3), Mode4 (A5). Solo uno activo a la vez (el primero que se activó). Ajuste fino con INC (A2)/DEC (A1) o con SET+/SET− del crucero.
| Parámetro | Código | Defecto | Rango |
|---|---|---|---|
| PTO_MIN_ENGINE SPEED | DC | 500 rpm | 500-2500 |
| PTO_MAX_ENGINE SPEED | AA | 2500 rpm | 500-3500 (pág. 116: 500-2500) |
| PTO_ENGINE_ADJUST_RAMP | IF | 50 rpm/s | 0-250 |
| PTO_MODE1_DEF_RES_ESPD | HB | 800 rpm | 500-2500 |
| PTO_MODE2_DEF_RES_ESPD | HC | 1000 rpm | 500-2500 |
| PTO_MODE3_DEF_RES_ESPD | HD | 1200 rpm | 500-2500 |
| PTO_MODE4_DEF_RES_ESPD | YN | 1400 rpm | dentro de DC-AA |
| PTO_MODEx_PARKBR_COND_ENABLE | HH/HI/HJ/YQ | 1 (exige freno estac.) | 0/1 |
| PTO_MODEx_EDGE_TRIG_ENABLE | YJ/YK/YL/YM | 1 (flanco) | 0/1 |
| PTO_MODEx_BRAKE_ENABLE | BRR/BRS/BRT/BRU | 0 | 0/1 (1 = el freno de servicio corta) |
| PTO_MODEx_DELAY | HE/HF/HG/YR | 0 s | 0-25 s (Mode4 0-100 s) |
| ESM_MODE_ENTRY/EXIT_RAMP | IHV/IHW | 0 (escalón) | 0-250 rpm/s |
- Condiciones: un PTO_ModeX_ENABLE activo, entrada activada, motor girando sin códigos de régimen, condiciones programadas cumplidas y, **la primera vez en cada ciclo de llave, la entrada debe verse OFF y luego ON**.

## [implemento] BBM: salidas de control PTO (PTO2-PTO4) — condiciones y parámetros (NA)
- Aplica: Volvo VHD BBM (NA)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 117-120

- 3 pares entrada/salida: entradas A18/A19/A20 (interruptor tablero) → salidas B2/B3/B4 **activas bajas, máx. 1 A** (solenoide de PTO o válvula de bypass).
- Para activar la salida: entrada activa; freno de estacionamiento (programable); **régimen sobre un mínimo durante ≥2 s**; régimen bajo un máximo; velocidad bajo un máximo; caja en neutro (programable, requiere cablear la entrada A24 si no hay ETC2); split bajo (programable); y ciclo OFF→ON la primera vez.
| Parámetro (PTO2) | Código | Defecto |
|---|---|---|
| PTO_OUT2_ON_EDGE | YT | 1 |
| PTO_OUT2_PARK_BRAKE | YU | 0 |
| PTO_OUT2_NEUTRAL_GEAR | YV | 0 |
| PTO_OUT2_ENGINE_SPEED_HIGH | YY | 2500 rpm |
| PTO_OUT2_VEHICLE_SPEED | YZ | 250 km/h |
| PTO_OUT2_TYPE | ZA | 4 (motor 2) |
| PTO_OUT2_ENGINE_MIN_SPEED | IGF | 500 rpm |
(PTO3: ZC…ZK, tipo 1 = caja 1; PTO4: ZL…ZT, tipo 2 = caja 2.) PTO_OUTx_TYPE solo importa con caja Volvo (I-Shift). "Nota: el BBM también puede acoplar la PTO del I-Shift por el bus de datos".

## [falla_conocida] PTO que no acopla o se desacopla al arrancar: disparo por flanco y alimentación de interruptores del BBM (NA)
- Aplica: Volvo con BBM (NA; principio aplicable a FMX)
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 115

- Con disparo por NIVEL, la PTO se reanuda sola si se cae; con disparo por FLANCO (defecto) exige un nuevo OFF→ON.
- La primera vez en cada ciclo de llave el BBM debe ver la entrada OFF→ON (evita acoples con un interruptor olvidado encendido).
- **Por eso los interruptores de entrada del BBM deben alimentarse desde las salidas propias del BBM (pines B5 y B19; conector ELCE-CK #3 pines A y B).** Si el carrocero alimenta el interruptor desde otra fuente que cae durante el arranque, el BBM interpreta un OFF→ON o un OFF y la PTO no acopla o se comporta errática.
- Prioridad: los modos PTO del BBM tienen prioridad sobre la PTO de palanca de la VECU.

## [electrico] Bus J1939 del carrocero (BB CAN) en el BBM: escuchar o controlar el motor (NA)
- Aplica: Volvo VHD BBM (NA)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 121-122

- Bus J1939 dedicado, aislado físicamente del J1939 principal (pines A15 H / A16 L del BBM; no vienen al conector ELCE-CK: hay que agregar terminales). Cableado según SAE J1939-15/-11.
- BB_BUS_LISTEN (código AET, defecto 0): retransmite ETC1, ETC2 (caja), CCVS (VECU), EEC1, EEC2 (motor) al bus del carrocero.
- BB_BUS_CONTROL: permite al carrocero enviar TSC1 (régimen/par) al motor con chequeos. Mientras está activo se deshabilitan en el BBM: entradas de régimen PTO, límite de régimen, límite de par y ralentí forzado.
- BB_ENGINESPD_CONTROL (DWC, defecto 0): control de régimen vía CAN del carrocero (requiere DVE). F_ENABLE_ESC_BBCAN_BRAKE_SWITCH (NWT, defecto 1): el freno inhibe ese control.

## [electrico] Iluminación adicional (faros de trabajo, balizas) y el módulo de luces LCM (NA)
- Aplica: Volvo con LCM (NA); principio aplicable a módulos de luces con protección electrónica
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: NA-S3 pág. 144-148

- Las salidas del LCM tienen protección electrónica: si la carga añadida supera su capacidad, el LCM corta todo el circuito y registra un código. También detecta corriente insuficiente (lámpara quemada) → cambiar ampolletas por LED o retirar luces de fábrica puede generar códigos.
- No empalmar en interruptores del tablero ni en luces altas/bajas ni en intermitentes delanteros (son DRL).
- Opciones: (1) conectar directo si hay capacidad (medir consumo real), (2) **relé con fusible propio comandado por la salida del LCM** (bobina típica <200 mA), (3) circuito independiente con fusible y switch desde barras BAT/IGN de la central.
- Capacidades de ejemplo: faros neblineros 10 A (1 mm²), luces de retroceso incl. alarma 5,5 A, luces traseras de cabina 8,5 A, stop/giro trasero 9,5 A cada lado (2 mm²).
- Conexiones fuera de cabina: conectores sellados o soldadura con termorretráctil con adhesivo; cinta aislante NO es aceptable.

## [transmision] I-Shift: modos de conducción y tecla MODE
- Aplica: Volvo FMX/FM con I-Shift (AMT), selector GSS-AGS
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=57584 ("Gearbox, drive modes")

- Modos: **Economy → Standard → Performance → Off-road** (tecla MODE del selector; doble pulsación salta dos pasos). **Heavy duty: mantener MODE 3 s** (si está equipado). Al arrancar se selecciona Economy; Heavy duty se mantiene si estaba activo al apagar.
- Retorno automático: de Off-road a Performance con marcha ≥11 sobre cierta velocidad; de Performance a Economy/Standard con marcha ≤11 cerca del límite legal un tiempo, o 30 s con marcha ≥10, acelerador poco pisado y camino plano.
- Funciones de software (según compra): selección de marcha de partida por peso y pendiente, estrategia mejorada con ESP/EBS, arranque pesado, conducción en ralentí sin patinar embrague, I-Roll, adaptación a alto peso (hasta 325 t GCW con AT2412/AT2612/ATO2612/AT2812/ATO3112/ATO3512), funciones PTO básicas/mejoradas, temperatura de aceite de caja en display. El taller puede cambiar funciones por software.

## [transmision] I-Shift: embrague, sobrecalentamiento, arranque sin aire y salida de atascos
- Aplica: Volvo FMX/FM con I-Shift (AMT)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=57458 ("Gearbox, starting") y topic=57429 ("Gearbox, starting without air pressure")

- Embrague monodisco seco (no convertidor): no patinar en marcha alta; no sostener el camión en pendiente con el acelerador.
- Embrague sobrecalentado (mensaje en display): si se está moviendo, seguir conduciendo; si está detenido, palanca en A o R y motor en ralentí hasta que se apague el mensaje.
- Marcha de partida: automática por peso y pendiente; manual con +/−; mantener "−" y mover a A/M va directo a la marcha más baja (maniobras). Tras desenganchar remolque se usa marcha más baja hasta avanzar unos metros.
- **Sin presión de aire**: el motor solo arranca con la caja en N. Si se apagó con la caja en marcha y el aire bajo el nivel de alerta, no se puede pasar a N ni arrancar → **llenar aire desde fuente externa (toma SF)**.
- Atascado: Off-road + bloqueos diferenciales; "arranque pesado" con marcha 1 y acelerador a fondo (mayor par con embrague frío); "arranque a tirón": Off-road, C2/1 o R1, mantener "−" y acelerar a fondo (sube a 1500 rpm), soltar "−" para embragar.

## [transmision] I-Shift: capacidades de aceite y aceite adicional por PTO/enfriador (NA)
- Aplica: I-Shift AT2612/ATO2612/ATO3112 (NA 2.2023)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: PDF local `_Descargados oficiales 2026-09/Volvo/Volvo NA Body Builder Seccion 4 - Transmision I-Shift (ref FMX).pdf` (Body Builder Instructions VN/VHD/VAH Section 4, USA170557174, 2.2023, pág. 2-5), publicado en https://www.volvotrucks.us/parts-and-services/services/body-builder-support/manuals/

- Llenado de servicio: **AT2612-C/D/F, ATO2612-C/D/F, ATO3112-C/D: 16 L (16,9 qt)**.
- Adicional: PTO directa PTR-D/F +0,1 L; PTO directa PTRD-F/D/D1/D1D/D2 +0,8 L; enfriador montado en caja TC-MWOH2 +0,8 L; enfriador en radiador TC-MWOR +1,0 L; crawler ASO-ULC/ASO-C +1,6 L.
- Solo aceite sintético aprobado por Volvo. Con enfriador en radiador usar 75/80 (no 75/90 HD).
- Remolque: **desmontar el cardán antes de remolcar** o se daña la caja.
- Relaciones (ej. ATO 12D): 1ª 14,94 … ; crawler ATO 13D: C1 17,54 / C2 19,38 (ATO 12O: 1ª 11,73).

## [combustible] Purga del sistema de combustible y drenaje de agua desde el menú
- Aplica: Volvo FMX/FM nueva generación
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=A000FMX&l=en&topic=70168 ("Fuel system")

- Cambiar filtro en cada cambio de aceite o si baja la presión de combustible, baja la potencia o el combustible es irregular (con combustible malo se tapa antes). El filtro nuevo se monta **vacío** (nunca prellenado): apretar a mano hasta el sello + 3/4 a 1 vuelta.
- Purga manual (PRIM-MAN): motor apagado, freno de estacionamiento, volcar cabina, retirar aislamiento sobre el larguero izquierdo, **bombear 200-300 veces la bomba manual del soporte de filtro** hasta sentir resistencia (no se abre ningún tornillo); arrancar y dejar en ralentí; repetir si arranca mal. **Nunca purgar con el motor de arranque.**
- Otras versiones: "Fuel Priming" desde el menú MAINTENANCE.
- Separador de agua: símbolo de agua en filtro → MAINTENANCE → Water Draining (motor apagado, llave en Accessory o superior, freno de estacionamiento). "Water draining not possible" con condiciones cumplidas = falla → taller.
- Estanque: drenar lodo y agua una vez al año por el tapón inferior.

## [boletin_recall] Recalls públicos Volvo VM/FMX y Renault C: estado de la búsqueda
- Aplica: Volvo VM/FMX Brasil 2023-2024; Renault Trucks C 2023
- Tipo: boletin_recall
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (consulta por VIN VF630N358PD000096: temas "news/criticalNews" = 0) ; https://www.gov.br/mj/pt-br/assuntos/seus-direitos/consumidor (Senacon)

- No se pudo verificar recalls: el buscador de recalls de Senacon (gov.br) no respondió a consultas automatizadas y no se ubicó un listado público de Volvo Brasil/Chile. La guía Renault del VIN de la flota no tiene "noticias críticas" asociadas.
- Acción recomendada: consultar a Volvo Chile/Renault Trucks Chile por VIN (campañas abiertas) y revisar SERNAC "alertas de seguridad" y Senacon "consulta de recall" manualmente con marca/modelo.

---
# Fichas por chasis real de la flota (guías generadas 2026-09-19)

## [postratamiento] FMX flota: norma de emisiones declarada — D13C Euro 5 / PROCONVE P7, SCR sin DPF
- Aplica: Volvo FMX 420 2024 (E941303, TGGF-56), FMX 420 2025 (EE603547, TRDP-96), FMX 540 2024 (E944562, TGGF-60)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía del conductor chasis E941303, PDF pág. 15, 256, 340; mismo texto en EE603547 y E944562)

- "Volvo utiliza tecnología SCR … para cumplir con los nuevos límites de emisiones - **fase P7 CONAMA (similar a la norma EURO V en Europa)**", vigente desde 01/01/2012 (pág. 256).
- "El motor tiene un sistema para la depuración de gases de escape con solución de urea **ARLA 32 (AdBlue)**, que se inyecta en el sistema de escape antes del silenciador. El silenciador tiene un catalizador SCR integrado … cumpla los requisitos de la norma **Euro 5 y PROCONVE P7**."
- Las tablas de mantenimiento de la misma guía identifican el motor como **"D13C Euro 5"** (pág. 340-342). La guía declara conformidad PROCONVE/CONAMA "solo válido para el mercado brasileño" (pág. 15).
- No hay DPF ni regeneración en estas guías (el DPF solo aparece en un texto genérico sobre aceites). → Ignorar las fichas Euro 6/DPF para estos camiones. EGR: la guía no lo menciona.
- Combustible: diésel sin azufre <10 ppm para cumplir de forma constante el nivel de emisiones.

## [postratamiento] FMX flota: ARLA 32 / AdBlue, control de NOx, códigos imborrables 400 días y derrateo 40 %
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024 (D13C Euro 5 / P7)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía E941303, PDF pág. 257-259)

- AdBlue/ARNoX urea 32,5 %, ISO 22241-1; congela a ~−11 °C (sistema calefaccionado). **Si el AdBlue cae sobre conectores y cables, se deben sustituir; no basta con limpiarlos.**
- MIL: se enciende por fallas de emisiones con **retardo** (puede encenderse mucho después) y **sigue encendida un período después de reparada** la falla.
- Nivel: ~10 % → testigo AdBlue + mensaje; vacío → testigo + mensaje + MIL; falla de circulación → mensaje + MIL. La circulación de AdBlue también refrigera componentes.
- El control de NOx vigila el nivel de NOx, el nivel de AdBlue y las fallas del sistema; se limita con motor frío, baja temperatura ambiente y **altitud muy elevada**.
- "Códigos de avería imborrables" por: nivel de AdBlue bajo, NOx incorrecto, avería del monitoreo de NOx. Se guardan **400 días** y registran las horas de motor con la falla activa.
- **Derrateo: la potencia de tracción se reduce un 40 %** la primera vez que se detiene el camión después de aparecer la avería (p. ej. en un semáforo), si: NOx incorrecto, tanque de urea vacío, o **36 h de motor sin poder monitorear NOx**. Aviso previo en pantalla + MIL. Vuelve a potencia normal al reparar/rellenar.

## [fusibles_reles] FMX flota: diferencias de la central de fusibles real respecto a la guía demo
- Aplica: Volvo FMX 420 2024 (E941303), FMX 420 2025 (EE603547), FMX 540 2024 (E944562) — las tres guías tienen la tabla de fusibles, relés y fusibles principales **idéntica**
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía E941303, PDF pág. 307-312)

Iguales a las fichas demo (F1-F91, K01-K28) salvo:
| Pos. | Guía real FMX flota | (demo UE) |
|---|---|---|
| F3 | 10 A TV/DVD | TV; ERA GLONASS |
| F9 | libre | 10 A cámaras-monitor |
| F15 | 10 A placa de luz en techo / luces de posición | letrero de cabina |
| F22 | 5 A visera izq./der. | parasoles + litera |
| F53 | 5 A interruptor de video | 5 A — |
| F59 / F60 | 15 A convertidor de voltaje / convertidor de voltaje | TV / radio-teléfono |
| F67 | 15 A encendedor de cigarrillos | USB |
| F79 | libre | 10 A sensor de seguridad |
| F85 / F91 | 3 A FMS (energía en conducción) / 10 A FMS (energía de conector) | FMS |
| K08 | 40 A Accesorios | cafetera |
| K22 | 20 A Encendido | ignición FMS/ERA |
- Confirmados en la guía real: F19 15 A BBM; F24 5 A instrumento; F27 10 A, F28 20 A y F68 15 A VMCU; F37 20 A ABS/EBS; F41 15 A EMS; F62 5 A OBD; F63 10 A CIOM; F70 20 A TECU; F81 5 A SRS; K17 TECU; K20 encendido carrocería en posición conducción; K27 EMS. Fusibles principales 1-12: 200 A carrocero, 100 A FRC, 30 A FCIOM/CCIOM/RCIOM (×2), 30 A FAS, 40 A PCCU, **23 A ACM**, 23 A eje auxiliar; torques M5 4,5 / M8 20 / M10 40 Nm ±5 %.
- Acceso idéntico: central del tablero (goma de la bandeja, tornillo 90° antihorario, manija hacia arriba); fusibles de carrocería con tornillo 90° antihorario.

## [electrico] FMX flota: reglas eléctricas de la guía real (baterías, accesorios, fusibles al 70 %)
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía E941303, PDF pág. 306-307)

- Usar **batería original Volvo**: con otras marcas el sensor de monitoreo puede no medir bien y su calibración puede fallar (el instrumento mostraría un estado de batería erróneo).
- Sistema en modo "Estacionado" para desconectar/reemplazar baterías; negativo primero al desconectar y último al conectar. **Tuercas de los soportes de batería: 16 Nm.**
- Accesorios: fusible del tamaño especificado y sección de cable correcta; **carga continua máx. 70 % del valor nominal del fusible**; usar conectores/terminales/fusibles originales Volvo. Fusible sobredimensionado = riesgo de incendio.
- Encendedor: diseñado para ~4 A, no usarlo como toma de corriente. Tomas de 12 V y 24 V junto al encendedor: **máx. 10 A**.

## [implemento] FMX flota: toma de fuerza — se reactiva al arrancar si el interruptor quedó encendido
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024 (riego, polibrazo, pluma)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía E941303, PDF pág. 204)

- Todas las tomas de fuerza se desconectan al apagar el motor. **Al volver a arrancar: si el interruptor de PTO está apagado, queda desconectada; si quedó encendido, la PTO se activa al encender el motor** ("NOTA: si el interruptor de la toma de fuerza está en la posición de encendido cuando arranque el motor, se activará"). Esto difiere de la guía demo UE.
- Implicancia de seguridad/diagnóstico: la bomba de riego, el polibrazo o la grúa pueden quedar operativos apenas arranca el motor; verificar el interruptor antes de arrancar. Si una PTO no se comporta así, revisar la parametrización del carrocero (BBM): el carrocero adapta las condiciones.
- Se puede programar régimen aumentado con PTO y un régimen máximo para proteger el equipo; nunca superar el régimen recomendado por el carrocero.

## [motor] FMX flota: control de régimen del motor y ajuste permanente del ralentí (guía real)
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía E941303, PDF pág. 148-149)

- Régimen constante (solo a baja velocidad): tecla Encender (6) → menú en el display → +/− hasta "control de velocidad del motor" → SET (4). +/− ajusta; **Reanudar (1) = valor preprogramado, normalmente 1.000 rpm**; cero (5) vuelve al original; mantener (5) desactiva.
- Ralentí permanente (refrigerante > ~50 °C, camión quieto en ralentí): soltar el acelerador y **pisar el freno durante todo el procedimiento; régimen constante inactivo y control de crucero adaptativo apagado** → mantener Reanudar (1) ≥ 2 s → soltar → ajustar con +/− → mantener (1) ≥ 2 s (mensaje de guardado) → soltar la tecla y el freno. Si hay un error en la secuencia, se conserva el ralentí anterior.

## [lectura_codigos_tablero] FMX flota: notificaciones del display y prueba de pedal de freno (guía real)
- Aplica: Volvo FMX 420 2024/2025 y FMX 540 2024
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://driverguide.volvotrucks.com/driverguide/chassiPdfFile?chassi=E941303&l=es-AR (Guía E941303, PDF pág. 75-76 y 331)

- Menú de la pantalla de instrumento (tecla Menú del volante, con el foco en el instrumento): en la guía real solo figura "REINICIAR LA COMPUTADORA DE A BORDO"; otras funciones y ajustes están en la **pantalla lateral**. La guía del conductor **no** describe un menú de lectura de códigos DTC → usar Tech Tool/herramienta por el conector OBD (fusible F62 5 A).
- Notificaciones: roja (símbolo rojo, señal acústica, halo rojo; detener y apagar; reaparece a los 30 s si no se corrige), amarilla (halo amarillo; reaparece en el siguiente arranque). Las aceptadas y aún activas quedan en el menú de notificaciones.
- Prueba de pedal de freno: tras pasar por modo Estacionamiento con un código de freno activo aparece el pedido de prueba; seguir la pantalla. "Test correctly performed. Brakes working correctly." = código eliminado.
- Forros de freno: grosor mínimo **5 mm** (revisar por las ventanas de inspección en cada Servicio básico). Llenado de aire externo por el conector SF; PX2-PX4 = prueba de presión de ejes traseros.

## [general] VM 350 flota: la guía del conductor del portal está vacía — fusibles y diagnóstico no disponibles
- Aplica: Volvo VM 350 6x4 2023 (E191064 SVBJ-55, E190968 SVBJ-56, E190769 SVBJ-57, E191065 SVCZ-38)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://vteu.webbase.cloud/driverguide/chassiNfo?chassi=E191064 ; https://vteu.webbase.cloud/driverguide/getTopicByChassi?chassi=E191064&l=es&topic=351294

- Los 4 VM están registrados en el portal oficial como "VM VMX", clase de producto 06 (familia "06-MDV"), montaje febrero 2023.
- Sin embargo, la guía del VM **no tiene contenido publicado**: los capítulos "Guía completa", "Comenzar", "Navegación visual" y "Consejos" están vacíos, y el PDF generado (es-AR y pt-BR) tiene solo 4 páginas de índice sin texto. La búsqueda del portal no devuelve temas (fusibles, diagnóstico, ARLA, tomada de força).
- Por lo tanto **no hay fuente pública para fusibles/relés, menú de diagnóstico, AdBlue/derrateo, PTO ni norma de emisiones del VM**. No aplicar las tablas del FMX al VM (plataforma distinta, clase 06).
- Cómo obtenerlo: Manual do Motorista impreso del VM (Volvo do Brasil) entregado con el camión, calcomanía de la central eléctrica, o concesionario Volvo Chile / Tech Tool. Norma de emisiones del VM Chile: solo referencia de prensa (Euro 5, ver ficha de identificación).
