# Mack Granite GU813 / GR (MP8) — conocimiento para diagnóstico

Flota Pillado: Mack Granite GU813 6x4 2014 (VIN 1M2AX38C1EM…, motor MP8 N° MP81044986, riego),
GU813 VIN 1M2AX38C..GM… (aljibes 20 kL), GR 2019 VIN 1M2GR3HC..KM/LM… (aljibe y riego).
Documentos locales ya existentes (carpeta `_Descargados oficiales 2026-09/Mack/`) = copias de los PDF
públicos de macktrucks.com citados abajo. Nuevos PDF en `_Investigacion web 2026-09-19/Mack/`.

Advertencia general: el diagrama 21628497 ("WIRE DIAGRAM-CONVENTIONAL, 12V MACK, 2013BP") es la
arquitectura Conventional GEN I (CHU/CXU/GU) del período de fabricación 2013 en adelante. Los GR
fabricados desde el 1-1-2018 usan otra generación de VECU/BBM (ver ficha de ubicación de módulos);
para el GR 2019 confirmar con el diagrama que corresponda antes de medir.

---

## [general] Decodificación del VIN Mack (construidos hasta el 31-12-2017): GU813 2014/2015
- Aplica: Mack GU (Granite) construidos hasta 31-12-2017 (VIN 1M2AX38C…)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/parts-and-service/support/body-builders/manuals/heavy-duty/mack-section-0.pdf (Mack Body Builder Instructions Sección 0, USA173626874, 7.2023, pág. 33 y 37)

| Posición | Valor en flota | Significado según Mack |
|---|---|---|
| 1 | 1 | País de fabricación: Estados Unidos |
| 2 | M | Mack Trucks, Inc. |
| 3 | 2 | Vehículo incompleto |
| 4-5 | AX | Modelo GU (Granite) |
| 6-7 | 38 | Código de motor AX38 = **GU813E**, serie 800 (Axle Back), 6 cil. 783 CID (**12,7 L = MP8**), 335-434 BHP (250-323 kW) |
| 8 | C | Camión clase 8, freno de aire |
| 10 | E / G | Año modelo: D=2013, E=2014, F=2015, **G=2016**, H=2017, J=2018, K=2019, L=2020 |
| 11 | M | Planta Macungie, Pennsylvania |

Nota para la flota: el camión registrado como "2015" con VIN `1M2AX38C..GM…` tiene **G en la posición 10 = año modelo 2016**
según esta tabla (puede ser fabricado en 2015). Usar año modelo 2016 al buscar boletines/recalls.
En este formato de VIN (pre-2018) no hay código de mercado doméstico/exportación.

## [general] Decodificación del VIN Mack (construidos desde el 1-1-2018): GR 2019 = MP8 exportación
- Aplica: Mack GR (Granite) construidos desde 1-1-2018 (VIN 1M2GR3HC…)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/parts-and-service/support/body-builders/manuals/heavy-duty/mack-section-0.pdf (Sección 0, USA173626874, pág. 31-32)

| Posición | Valor en flota | Significado |
|---|---|---|
| 4-5 | GR | Granite |
| 6 | 3 | Motor código 3 = Mack **MP8 13 L diésel, 335-434 HP** (código 4 = MP8 435-534 HP) |
| 7 | H | Chasis **6x4 – mercado EXPORT** (G = 6x4 doméstico) |
| 8 | C | Camión clase 8, freno de aire |
| 10 | K / L | K = 2019, L = 2020 |
| 11 | M | Macungie |

Conclusión: el GR 2019 es una unidad **de exportación** (no configuración EPA doméstica). Esto confirma
que su software/postratamiento puede diferir de los manuales US (US17/OBD).

## [postratamiento] Norma de emisiones probable de los MP8 de exportación en Chile (inferencia a verificar)
- Aplica: Mack GU813/GR MP8 vendidos por el canal de exportación LatAm 2011-2019
- Tipo: especificacion
- Confiabilidad: tecnica_terceros
- Fuente: https://www.mch.cl/granite-el-faenero-de-mack/ (Minería Chilena, "Granite, el faenero de Mack", 2011) ; https://dealers.rewebmkt.com/files/20200303071031lyf1a-ficha-tecnica-mack-granite.pdf (ficha técnica Mack Granite 2019, distribuidor Mack Colombia) ; https://www.macktrucks.com/media/files/parts-and-service/support/body-builders/manuals/heavy-duty/mack-section-0.pdf (Sección 0, pág. 5, abreviaturas "MP8 EU4 / MP8 EU5")

- Minería Chilena (2011, declaraciones de Salfa, distribuidor Mack en Chile): Granite GU813 440 HP con
  MP8 13 L "normativa **Euro III**, inyección electrónica de alta presión por **inyectores bomba**", caja
  **Allison RDS 4500 con retardador**, freno motor PowerLeash.
- Ficha Mack Colombia modelos 2019: MP8-360C "**Euro 4 sin urea con EGR**", turbo de geometría variable,
  controlador **V-MAC IV**.
- Mack lista oficialmente variantes MP8 EU4 y MP8 EU5 (Euro 4 / Euro 5) además de US07/US2010/US2014.
- Por lo tanto, lo más probable para la flota: **MP8 exportación con EGR + VGT, SIN SCR/DEF** (Euro III o
  Euro 4). Presencia de DPF: NO confirmada con fuente → verificar físicamente (¿hay DPF/tanque DEF/sensores
  NOx en el escape?) y leer la etiqueta de emisiones del motor y el "Engine family" con Premium Tech Tool.
- Consecuencia práctica: los códigos de SCR/DEF/NOx (US10+OBD13) solo aplican si el camión tiene SCR.

## [transmision] ¿Qué caja automática lleva el GU813/GR? Allison 4500 RDS (probable) vs mDRIVE
- Aplica: Mack GU813 2014-2016 "GU813E Allison"/"autom", GR 2019 "autom"
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://delivery-p107394-e1241111.adobeaemcloud.com/adobe/assets/urn:aaid:aem:aba4ff74-2839-4f2f-9b64-cf4a5cb30f91/original/as/section-4-transmission-0905.pdf (Mack Body Builder Sección 4 Transmisión, USA178367065, 5.2024, pág. 2 y 12-15) ; https://www.mch.cl/granite-el-faenero-de-mack/ ; https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (diagrama 21628497, pág. 44-45)

- Mack lista para GR/GU solo dos Allison: **4500 RDS** y **3000 Series** (Sección 4). En Chile Salfa
  comercializó el GU813 6x4 y 8x4 con **Allison RDS 4500 con retardador** (Minería Chilena 2011).
- El diagrama eléctrico conventional 2013BP muestra "ALLISON TRANSMISSION **GEN 5** CONTROL MODULE" con
  conector de transmisión "MODEL 3000/4000", retardador y selector "ALLISON G5 SHIFT SELECTOR".
  Allison liberó los controles 5ª generación a todos los OEM a inicios de 2013 → GU 2014-2016 casi seguro Gen 5.
- La alternativa "autom" en Mack es **mDRIVE** (caja mecánica automatizada Mack, TmD12/TmD13/TmD14). En
  Colombia 2019 se vendió Granite mDRIVE (Euro 4). Para el GR 2019 "autom" verificar físicamente.
- Cómo distinguir en taller: Allison = selector de botonera R-N-D-↑-↓-MODE (o palanca "bump") con display,
  varilla de aceite en la caja (tubo de varilla Mack p/n 23171580 para 4500 RDS), convertidor de torque;
  mDRIVE = selector de palanca Mack (GSECU) en la columna/tablero ("mDRIVE Gear Selector", Sección 8 pág. 6)
  y aceite de transmisión según SB 175-61.
- Relaciones Allison 4500 RDS (Mack Sección 4 pág. 12): 1ª 4,70 · 2ª 2,21 · 3ª 1,53 · 4ª 1,00 · 5ª 0,76 · 6ª 0,67 · R −5,55.
- Capacidad 4500 RDS (sin circuitos externos): con PTO y cárter bajo (shallow) 45 L (47,5 qt); sin PTO cárter bajo 38 L (40 qt). Fluido TES 295 / TES 389.

## [electrico] Arquitectura electrónica y redes de datos Mack (VECU, EECU/ECM, ACM, TCM, cluster, ABS, BBM)
- Aplica: Mack CHU/CXU/GU (y GR) con motor Mack MP7/MP8, 2010-2019
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.auroramack.com/sites/default/files/2024-09/Fault%20Codes%20MACK%202014-2017.pdf (Mack Service Information Grupo 28 "ECM, ACM, VMAC IV DTC", PV776-89091093, pág. 1-2) ; https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 70-73)

Módulos: ECM/EECU (motor), ICM/cluster, **VECU** (control de vehículo: crucero, relés accesorios, apagado
por ralentí), TCM (transmisión), GSCM/GSECU (selector), ACM (postratamiento, si existe), ABS, BBM (módulo de
carrocero, opcional).
Redes:
| Red | Uso | Velocidad / detalle |
|---|---|---|
| SAE J1939 (CAN1, "backbone", DL1) | VECU, cluster, ABS, TCM, ECM | cables trenzados amarillo (H) / verde (L) |
| SAE J1939-7 (CAN2, subred motor) | ECM, ACM, sensores NOx, actuador VGT (SRA), TECU | resistencias: una dentro del ECM, otra cerca de sensores NOx |
| ISO 14229 / SAE J2284 (DL2, 500 kbit/s) | programación/diagnóstico ECM-ACM-TCM (OBD) | cables DL2H/DL2L blanco con franja naranja |
| SAE J1708/J1587 (9600 bit/s) | "information data link" | **motores Mack y mDRIVE NO usan J1587** |
- VECU y ECM dependen uno del otro: intercambian datos y cálculos; el ECM hace de pasarela de DTC de VECU,
  sensores NOx y VGT-SRA hacia la herramienta OBD.
- ISO 14229 no usa FMI sino "failure type bytes" (FTB). El ECU que reporta un DTC de red puede no ser el
  sitio de la falla (ej.: el ECM reporta falla de enlace que está en la VECU).
- Falla de J1587: síntoma típico = códigos de un módulo que no se pueden borrar/resetear.

## [electrico] Identificadores de módulo (MID) y equivalencias de formato de código Mack
- Aplica: Mack MP7/MP8 EPA07-US10 (formato MID/PID/SID-FMI y SPN-FMI) y US2013+ (P-code + FTB)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2021/MC-10204023-0001.pdf (Mack, SPN 1231 FMI 9 troubleshooting US10) ; https://static.nhtsa.gov/odi/tsbs/2021/MC-10204019-0001.pdf (Mack, turbo actuator coolant leak) ; https://www.auroramack.com/sites/default/files/2024-09/Fault%20Codes%20MACK%202014-2017.pdf (pág. 3)

- MID 128 = Engine Management System (EMS/ECM); MID 233 = ACM; MID 130 = TECU (I-Shift/mDRIVE).
- Un mismo evento aparece con tres formatos según generación/herramienta. Ejemplo oficial (actuador VGT):
  **SID 27 FMI 9 = SPN 641 FMI 9 = U010C** ; **SID 27 FMI 7 = SPN 641 FMI 7 = P0046**.
- OBD2013 (US2013 en adelante): letra + 4 dígitos + (opcional) 2 dígitos de FTB (ej. P0087-00, P2200-13):
  el FTB indica categoría/subtipo de falla (circuito abierto, corto a masa, algoritmo, etc.).
- En US2013+ los DTC **ya no pueden borrarse desde el display del cluster con el control de palanca (stalk)**;
  se requiere herramienta de diagnóstico (Premium Tech Tool).

## [electrico] Ubicación física de VECU, BBM y cómo distinguirlos
- Aplica: Mack CHU/CXU/GU/TD y AN/PI/GR
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/parts-and-service/support/body-builders/manuals/mack-section-8.pdf (Mack Body Builder Sección 8 Cab, Instrument Panel, USA141896628, 3.2018, pág. 40-43)

- GU (CHU/CXU/GU/TD): **VECU detrás del panel "D"** del tablero. **BBM detrás de la tapa del motor**
  (engine cover, túnel interior de cabina).
- GR/AN/PI (desde 2018): VECU y BBM detrás del panel "D".
- Identificación: la **VECU tiene conectores azul y verde**; el **BBM tiene conectores blanco y naranja**
  (vale para construidos antes del 31-12-2017 y desde 1-1-2018).
- VECU GU: conector A verde 30 vías, B azul 30 vías, C verde 5 vías (Sección 3 pág. 20).

## [electrico] Conector de diagnóstico 16 pines (OBD, J1962 tipo A) – pinout Mack
- Aplica: Mack conventional (GU/GR) con OBD2013 y posteriores; la versión conventional 2013BP usa el mismo conector
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 79) ; https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (diagrama 21628497, hoja XA pág. 89)

| Pin | Función |
|---|---|
| 1 | Llave de encendido – señal IGN |
| 3 | J1939 CAN_H (J1939-15) |
| 4 | Masa chasis |
| 5 | Masa chasis |
| 6 | CAN_H de ISO (CAN2/ISO 14229) |
| 11 | J1939 CAN_L |
| 12 | J1587 (+) |
| 13 | J1587 (−) |
| 14 | CAN_L de ISO |
| 16 | + Batería (fusible **F10 "Diagnostic connector" 5 A**, bus BATT) |
| 2, 7-10, 15 | no usados |
Ubicación: lado conductor, parte baja del tablero. Si el scanner no enciende: medir pin 16-pin 4/5 (≈ tensión de batería) y revisar F10 5 A.

## [electrico] Conector de diagnóstico 9 pines (motores de exportación)
- Aplica: Mack con motores de exportación ("Export Engines Only")
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 78)

| Pin | Función |
|---|---|
| A | Masa |
| B | + Batería |
| C | CAN H (J1939 H – amarillo) |
| D | CAN L (J1939 L – verde) |
| E | No usado (malla) |
| F | J1587 + |
| G | J1587 − |
| H | No usado |
| J | + Encendido (llave) |
Relevante porque la flota es de exportación: puede tener conector 9 pines Deutsch en vez del de 16 pines.
Prueba de resistencias de terminación en este conector: entre **C y D**.

## [electrico] Prueba de resistencias de terminación J1939 e ISO 14229 (60 Ω)
- Aplica: Mack conventional GU/GR y todos los modelos Mack con motor Mack
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 70 y 76)

1. Llave en OFF.
2. J1939: medir entre pines **3 y 11** del conector 16 pines (o **C y D** del de 9 pines).
   Correcto: **50-70 Ω** (dos resistencias de 120 Ω en paralelo). Cada resistencia sola: **110-130 Ω**.
3. ISO 14229: el manual indica también medir "entre pines 3 y 11" con el mismo criterio 50-70 Ω. Ojo: según
   la tabla de pines del mismo manual (pág. 79) la CAN ISO está en pines **6 (H) y 14 (L)**; confirmar con el
   diagrama del camión antes de concluir sobre la red ISO.
- Ubicación de resistencias J1939: una en el centro de fusibles y relés (FRC) cerca de la VECU y otra en el
  extremo del ECM (en motores Mack va **dentro del ECM**; en Cummins, en el arnés junto al ECM).
- ISO 14229: una dentro del ECM y otra de 2 pines en el tablero cerca del conector de diagnóstico.
- Nunca más de dos resistencias por red. ≈120 Ω = falta una resistencia o red abierta; ≈40 Ω = hay una
  tercera resistencia; ≈0 Ω = H y L en corto.
- En la zona de transmisión hay un conector J1939 en el arnés de chasis: con Allison va conectado a la
  caja; con caja manual lleva un tapón ciego sin terminación.

## [electrico] Red J1939-7 (subred motor) – SPN 1231 FMI 9: pasos de diagnóstico
- Aplica: Mack MP7/MP8/MP10 US10 (2010-2012) y posteriores con ACM
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2021/MC-10204023-0001.pdf (Mack KB "SPN 1231 FMI 9 Troubleshooting – US10")

- SPN 1231 FMI 9 = perturbación en J1939-7 (motor ↔ ACM, sensores NOx, SRA/VGT, TECU MID 130).
- Si aparece **inactivo en múltiplos de 3** (3, 6, 9…) en camiones construidos 1-1-2010 a 1-1-2013:
  actualizar software EMS antes de diagnosticar (retardo de comunicación al conectar TT2).
- Resistencia de red: 60 Ω (120 Ω dentro del EMS + resistencia enchufada cerca de sensores NOx).
- Revisar: terminales de masa en el perno del bastidor (limpiar/inspeccionar), terminal + de batería que
  alimenta ACM, fusible en línea de la alimentación ACM (prueba de meneo), prueba de carga de baterías,
  alimentación y masa de todos los componentes de J1939-7, corrosión/tensión de pines en conector ACM,
  contaminación con DEF en bomba DEF/arnés/ACM.
- ≈0,5 Ω entre H y L = cables en corto (desconectar conector de interfaz motor EI para aislar lado motor/chasis).
  Resistencia muy alta = falta resistencia, módulo o cable dañado; desconectar componentes uno por uno.

## [electrico] Distribución de potencia 1/2 – fusibles bus BATT (panel EPDM/FRC)
- Aplica: Mack Conventional CHU/CXU/GU 12 V, período 2013BP (GU813 2014-2016)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (diagrama 21628497 ed. 09, hoja AA "Power Distribution 1/2", pág. 3)

| Fusible | Circuito | A |
|---|---|---|
| F7 | Llave de encendido (key SW) | 10 |
| F19 | Cluster instrumentos | 5 |
| F67 | Reserva | 15 |
| CB2 | Interruptor térmico: faros, módulo DRL, neblineros | 15 |
| CB3 | Int. térmico: luces estacionamiento, cola, posición | 15 |
| CB4 | Int. térmico: intermitentes, destellador | 15 |
| F5 | Luces de freno tractor | 10 |
| F11 | Borne batería (batt stud) | 15 |
| F6 | Luz techo/cortesía | 10 |
| F26 | Luces de enganche (hook-up) | 15 |
| F61 | Interruptor aux. batería / reserva | 15 |
| F62 | Reserva | 15 |
| F60 | Tomas de corriente (vía RLY31) | 20 |
| F57 | Consola central | 15 |
| F76 | mDRIVE / Cummins DEF PWR | 30 |
| F9 | Bornes CB (vía RLY28) | 15 |
| CB14 / CB81 | Luz baja faro izq. / der. | 10 / 10 |
| F15 | Espejo calefaccionado | 20 |
| CB12 | Cierre centralizado | 10 |
| F13 | ABS BATT1 | 15/30 |
| F20 | Espejos motorizados | 10 |
| F29 | Relés EMS (bobinas RLY01/RLY34) | 10 |
| F71 | Transmisión (BATT) – alimentación TCM Allison | 30/10 |
| F68 | Encendedor | 15 |
| F10 | Conector de diagnóstico | 5 |
| F55 | ECS | 10 |
| F75 | HVAC litera / BB PWR | 30 |
Valores "x/y" = el diagrama indica dos amperajes según opción; confirmar con la etiqueta de la tapa del panel.

## [electrico] Distribución de potencia 1/2 – fusibles bus EMS e IGN y relés principales
- Aplica: Mack Conventional CHU/CXU/GU 12 V, 2013BP
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja AA, pág. 3)

Bus **EMS** (alimentado por RLY01 "EMS #1"; se corta en arranque y por desconexión por bajo voltaje):
| Fusible | Circuito | A |
|---|---|---|
| F54 | BBM (ECU carrocero) | 5 |
| F63 | Cluster (EMS) | 5 |
| F16 | VECU (unidad de control del vehículo) | 10 |
| F17 | Entradas de control/interruptores VECU | 10 |
| F31 | Transmisión / reserva (IGN del TCM Allison) | 10 |
| F65 | ACC / reserva | 15 |
| F64 | Arranque en frío / reserva | 10 |
| F18 | Interruptor regeneración DPF | 10 |
| F69 | Keyless / reserva | 10 |
| F56 / F53 | Bendix Fusion | 10 / 10 |
| F58 | Reserva | 30 |
| F25 | HVAC cabina (vía RLY35) | 30 |
| F70 | HVAC litera / BB IGN 1 | 10 |
| F72 | HVAC B | 10 |
Bus **IGN** (vía RLY03 "IGN #1"):
| F8 | Solenoides de aire | 15 |
|---|---|---|
| CB21 | Limpiaparabrisas/lavador | 20 |
| CB22 / CB23 | Alzavidrios izq. / der. | 20 / 20 |
| F30 | Interruptor IGN aux. / reserva | 20 |
| F27 | Borne IGN (ign stud) | 15 |
| F28 | Asientos calefaccionados | 20 |
| F24 | Reserva | 15 |
Relés en esta hoja: RLY01 EMS #1, RLY34 pre-EMS, RLY03 IGN #1, RLY53 HVAC litera, RLY31 tomas de
corriente, RLY28 bornes CB, RLY35 HVAC cabina, RLY26 control HVAC cabina.

## [electrico] Distribución de potencia 2/2 – fusibles y relés (luces remolque, reversa, ECM, ABS)
- Aplica: Mack Conventional CHU/CXU/GU 12 V, 2013BP
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja AB "Power Distribution 2/2", pág. 4)

| Fusible | Bus | Circuito | A |
|---|---|---|---|
| F48 | BATT | Caja litera / carrocero BATT #1 | 30/40 |
| F34 | BATT | Potencia reversa/neutro (RLY17/RLY29) | 30 |
| F36 | BATT | Bocina (RLY14) | 15 |
| F37 | BATT | Luces cola remolque (RLY11) | 30 |
| F35 | BATT | Gálibo cabina y remolque (RLY13) | 30 |
| F33 | BATT | Luz freno remolque (RLY12) | 30 |
| F50 / F51 | BATT | Reserva (RLY39 / RLY38) | 5 / 10 |
| F52 | BATT | Reserva / Guard Dog | 15/10 |
| F32 | BATT | ISO CPH | 30 |
| F45 | IGN | Reserva / separador combustible / calefactor combustible | 30 |
| F44 | IGN | Secador de aire calefaccionado / válvula purga calefaccionada | 15 |
| F42 | IGN | Luces de retroceso | 20 |
| F40 | IGN | Válvula de purga calefaccionada | 15 |
| F39 | EMS | ABS remolque | 30 |
| F49 | EMS | ABS (IGN del módulo ABS) | 10 |
| F46 | EMS | ACM / IGN motor | 5 |
| F47 | EMS | Transmisión / reserva | 15 |
| F38 | EMS | Unidad de control del motor (ECM) | 30/10 |
| F43 | EMS | Motor comp. #2 / IGN Cummins | 15/5 |
| F41 | EMS | Motor comp. #1 | 15 |
Relés: RLY04 IGN #3, RLY02 EMS #2 (alimenta el bus EMS de esta hoja), RLY17 reversa, RLY29 neutro,
RLY14 bocina, RLY11 cola remolque, RLY13 gálibo, RLY12 freno remolque, RLY39/RLY38 reserva.
X16 = borne de potencia del EPDM.

## [electrico] Circuito de llave, arranque y carga (hoja AC)
- Aplica: Mack Conventional CHU/CXU/GU 12 V, 2013BP
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja AC "Key SW, Start & Charging", pág. 5)

Cadena de arranque: F7 (10 A, BATT) → S036 interruptor de llave → señal IGN a VECU **A14** y señal de
arranque (crank) a VECU **A6** (opcional botón S036B "push button start"; en manuales, interruptor S58B de
pedal de embrague) → VECU salida **B28 "starter"** → bobina **RLY36 "start control 1"** → solenoide del
motor de arranque de reducción A124/A124A.
Potencia: batería G01 → interruptor maestro S169 (versiones con/sin master switch) → motor de arranque;
**FM3 fusible potencia principal cabina 150 A** → X10 paso B+ a cabina; X109L borne de arranque auxiliar
(jump start); X16 borne EPDM. Carga: alternador G02 (o G02A con sensado remoto: fusible **FB8 10 A "remote
sense alt"**).
Diagnóstico "no arranca": 1) F7 10 A; 2) señal en VECU A6 al girar llave; 3) salida B28 de VECU (el
arranque puede estar inhibido por protección: ver ficha de VECU); 4) RLY36 (85/86 bobina, 30/87 contacto);
5) caída de tensión en cables de batería/master S169. Mack: no dar arranque más de 30 s seguidos (ver ficha motor).

## [electrico] VECU – pines del conector A (verde 30 vías)
- Aplica: Mack conventional con VECU (CHU/CXU/GU, GR)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 21)

DI-H = entrada digital activa alta; DI-L = activa baja; DO-L = salida a masa.
| Pin | Tipo | Función |
|---|---|---|
| PA-1 | DI-H | Crucero Set/Decel |
| PA-2 | DI-H | Crucero Resume/Accel |
| PA-3 | DI-H | Crucero On/Off |
| PA-4 | DI-H | A/C On |
| PA-5 | DI-H | Freno de servicio |
| PA-6 | DI-H | Llave posición arranque (crank) |
| PA-8 | DI-H | Embrague |
| PA-9 | DI-H | Neutro |
| PA-10 | DI-H | Enclavamiento suspensión neumática |
| PA-11 | DO-L 1 A | Control DRL |
| PA-12 | — | **Masa** |
| PA-13 | — | **+ Batería** (F16 10 A) |
| PA-14 | DI-H | Llave posición IGN |
| PA-15 / PA-16 | — | J1939 + / − hacia BBM |
| PA-17 | DI-H | CDS 2 / PTO 4 |
| PA-18 | DI-H | IVS2 (caja automática Volvo) |
| PA-19 | DI-H | Override ventilador |
| PA-20 / PA-21 | DI-H | Freno motor 2 / 1 |
| PA-22 | DI-H | EOL |
| PA-23 | DI-H | IVS 1 |
| PA-25 | DI-L | Bloqueo interrueda |
| PA-26 | DI-L | Quinta rueda |
| PA-27 | DI-L | Parada remota de motor |
| PA-28 | DI-L | Interruptor capó abatido |
| PA-29 | DI-H | PTO1 |
| PA-30 | DI-H | Override DRL |

## [electrico] VECU – pines de los conectores B (azul 30 vías) y C (verde 5 vías)
- Aplica: Mack conventional con VECU (CHU/CXU/GU, GR)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 22-23)

| Pin | Tipo | Función |
|---|---|---|
| PB-1 / PB-2 | DO-L 1 A | Relé de potencia #1 / #2 (desconexión de cargas) |
| PB-3 | DO-L 1 A | Bloqueo diferencial interrueda |
| PB-4 | DO-L 1 A | Enclavamiento quinta rueda / **regeneración inhibida** |
| PB-5 | 12 V 50 mA | Salida alimentación 4 |
| PB-6 / PB-20 | frecuencia | Sensor velocidad vehículo + / − |
| PB-7 | DI-H | PTO 2 |
| PB-8 | AI 4 kΩ | Señal pedal acelerador |
| PB-10 | 5 V 10 mA | Alimentación 1 (pedal) |
| PB-11 | DI-L | Freno de estacionamiento |
| PB-12 | DI-L | Freno motor en volante 1 |
| PB-13 | DI-L | Operación lado derecho |
| PB-15 | DO-L 0,2 A | **Relé EMS** |
| PB-16 | DO-L 1 A | Ventilador auxiliar |
| PB-17 | DO-H 10 mA | IVS 1 bufferizado (solo EMS) |
| PB-18 | DO-L 1 A | Salida PTO |
| PB-19 | 12 V 70 mA | Alimentación 3 |
| PB-21 | DI-H | CDS 1 / PTO 3 |
| PB-22 / PB-23 | — | Masa analógica |
| PB-25 | 6,5-9 V 15 mA | Alimentación 5 |
| PB-26 | 5 V 10 mA | Alimentación 2 |
| PB-28 | DO-H 2 A | **Control de arranque** (ASSIST o protección de arranque) |
| PB-29 | DI-L | Interruptor de puerta |
| PB-30 | DI-H | Override de apagado (shutdown override) |
| PC-1 / PC-2 | — | J1587 B / J1587 A |
| PC-4 / PC-5 | — | J1939 H / J1939 L |
Uso típico: sin arranque → medir PB-28 al dar arranque; acelerador errático → PB-8 señal, PB-10 5 V, PB-22/23 masa.

## [electrico] VECU – alimentación, relés EMS e interruptores de tablero (hoja BA)
- Aplica: Mack Conventional CHU/CXU/GU 12 V, 2013BP
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja BA "Vehicle ECU 1/4", pág. 12)

- A17 VECU: **A13 B+ desde F16 10 A**; **A12 masa**; F17 10 A alimenta los interruptores de entrada.
- Salidas **B1/B2 "power relay 1/2"** y **B15 "EMS relay"** comandan las bobinas de los relés EMS: si la
  VECU no activa B15/B1/B2 se cae todo el bus EMS (ECM, cluster EMS, TCM IGN F31, ABS F49…).
- Interruptores: S007 crucero Set/Resume (A1/A2), S006 On/Off crucero (A3), S07 freno motor (A20/A21),
  S011 override ventilador (A19), S008 override apagado (B30), S045 override DRL (A30), S43 presostato
  indicador freno de estacionamiento NC (B11).

## [electrico] Cluster de instrumentos – alimentación, red y botonera de información (hoja BE)
- Aplica: Mack Conventional CHU/CXU/GU 12 V, 2013BP
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja BE "Instrument Cluster 1/3", pág. 16)

Conector A del cluster (A03):
| Pin | Función |
|---|---|
| A:1 | + Batería (F19 5 A) |
| A:2 | Masa |
| A:3 | Encendido (F63 5 A, bus EMS) |
| A:4 / A:5 / A:6 / A:7 | Botonera de información S043: SELECT / ESCAPE / UP / DOWN |
| A:9 | Dimmer luces de panel |
| A:15 / A:16 | J1939 H / L |
| A:17 / A:18 | J1587 A / B |
| A:19 | Llave a VCU |
| A:29 | Reversa |
Cluster apagado/sin datos: F19 y F63 (5 A), masa A:2, luego red J1939 (A:15/A:16). La botonera S043
(select/escape/up/down) es la que se usa para navegar los menús del display.

## [electrico] Interfaz de motor X11 (conector de gestión de motor) – pines y fusibles
- Aplica: Mack Conventional CHU/CXU/GU con motor Mack MP, 2013BP (hoja rotulada "Engine interface MP11")
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja CA, pág. 32)

| Pin X11 | Función |
|---|---|
| 1 / 4 | J1939-1 H / L |
| 2 / 5 | CAN2 H / L |
| 34 / 36 | J1939-7 CAN H / L |
| 6 / 3 | J1939P3 L / H (hacia mDRIVE) |
| 8 | IVS |
| 13 / 15 | Alimentación EMS A / EMS B (desde **F38 30/10 A**) |
| 21 | Compresor motor (F41 15 A) |
| 25 | Alimentación SRA (actuador VGT) / precalentamiento |
| 33 | Control ventilador (solenoide Y35) |
| 35 | Control de arranque |
| 39 / 31 / 27 | Masa 2 / Masa 1 / Masa SRA-compresor |
| 23 | Embrague A/C |
| 18 / 28 | Masa sensor / nivel de refrigerante (B123) |
| 37 | Calefactor de combustible |
Fusibles: F38 "eng ctrl unit" 30/10 A, F41 "eng comp #1" 15 A, F43 "eng comp #2" 15/5 A (bus EMS).
Uso: ante códigos múltiples de sensores/inyectores o comunicación con ECM, revisar primero F38 y masas 31/39.

## [electrico] Conector DCL (Conventional GU) – PTO, relés de reserva y alimentación
- Aplica: Mack Conventional GU, CXU, CHU
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 34)

Ubicado bajo el módulo ABS, encintado al arnés principal.
| Pin | Circuito | Función |
|---|---|---|
| A | CA17 | PTO 4 / CDS 2 |
| B | CB21 | PTO 3 / CDS 1 |
| C | CB7; CB7B | PTO 2 |
| D | CB16 | Control relé de reserva 2 (VECU) – CDS 2 out / PTO 4 |
| E | CB18 | Control relé de reserva 1 (VECU) – CDS 1 out / PTO 3 |
| F | F17A18 | Alimentación bus IGN |
| G | F18A | Potencia EMS 1 |
| H | F17C3 | Crucero SET/DECEL |
| J | F17D3 | Crucero RESUME/ACCEL |
| K | — | No usado |
Útil en camiones de riego/aljibe: el mando de bomba/PTO del carrocero suele tomarse de aquí.

## [electrico] BodyLink III (conector carrocero 29 pines Granite) – pinout
- Aplica: Mack Granite GU (conector estándar de carrocero, bajo la parte trasera de la cabina)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 27-31)

| Polo | Función | Polo | Función |
|---|---|---|---|
| 1 | Batería (30 A) | 16 | Señal de NEUTRO |
| 2 | Encendido (30 A) | 17 | Interruptor indicador (lámpara tolva arriba, activa a masa) |
| 3 | Luz de freno | 18 (+12 V) | PTO #1 – CA29 |
| 4 | Luz de cola | 19 (+12 V) | PTO #2 – CB7 |
| 5 | Señal de reversa | 20 (+12 V) | Control de velocidad ON/OFF |
| 6 / 7 | Intermitente izq. / der. | 21 / 22 | BB J1939 + / − |
| 8 | AUX sw #1 (IGN) | 23 (+12 V) | Control velocidad SET/DECEL |
| 9 | AUX sw #2 (BATT) | 24 (+12 V) | Control velocidad RESUME/ACCEL |
| 10-12 | AUX sw #3-#5 (IGN) | 25, 26, 28 | — |
| 13 / 14 | AUX sw #6 (DOWN / UP) | 27 / 29 | Giro-freno izq. / der. |
| 15 | Freno de estacionamiento | | |
Conector de acoplamiento 21099975, kit de terminales 21750652 (carcasa 25177195 según pág. 27).
Interruptores asignables del tablero salen por pines 8-14.

## [electrico] Parada remota de motor (VECU A27) – precaución de cableado
- Aplica: Mack conventional con VECU
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 25)

- La entrada VECU **A27** (conector verde 30 vías) es digital activa baja y debe ir a una **masa de señal aislada**.
- **No** conmutar masa de chasis/cabina a A27: la interferencia puede **apagar el motor sin pedirlo** (causa
  a revisar ante apagones intermitentes en camiones con parada remota instalada por el carrocero).
- Usar interruptor con contactos dorados o relé. En conventional, si no venía de fábrica: relé p/n 25082390
  + reprogramación VECU (kit 85137397, solo concesionario).

## [electrico] Alimentación de equipos de carrocería: bus EMS se corta en arranque y por bajo voltaje
- Aplica: Mack Conventional GEN I (CHU/CXU/GU) y GEN II (AN/PI/GR)
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 32-33)

- Los circuitos en potencia EMS quedan **interrumpidos durante el arranque (crank) y durante la
  desconexión por bajo voltaje (low voltage disconnect)**; ahí están los ECU.
- Consecuencia de diagnóstico: equipos del carrocero (bombas de riego, válvulas, controladores) conectados a
  EMS se reinician al dar arranque o si baja el voltaje de baterías; con baterías débiles pueden aparecer
  códigos de comunicación "fantasma" en varios módulos.

## [electrico] Reglas Mack de ruteo y fijación de arneses (prevención de roce/chafing)
- Aplica: todos los Mack (PI/CHU, AN/CXU, GR/GU, TD, LR, TE/MRU)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 5-7 y 11-12)

- Arnés eléctrico: soporte cada **450 mm** máx. con amarra entre clips; a **100 mm** de la entrada del
  conector. Cables de batería: soporte cada **400 mm**; alivio de tensión a ≤ 500 mm del borne del arranque;
  radio mínimo de curvatura 3× diámetro.
- Distancias a calor: arneses a **130 mm** en toda dirección del turbo/escape; sin protección 150 mm arriba,
  130 mm lado, 100 mm abajo; con manga reflectante 76/63,5/51 mm. SCR, DPF y escape: mantener cables alejados.
- No atar cables eléctricos con líneas de combustible/hidráulicas (paralelas sí, separadas); no pasar
  cables de batería bajo líneas de combustible; no usar arandelas estrella en uniones de corriente/masa.
- Donde cables crucen, fijar con abrazadera para evitar el "aserrado" por vibración.

## [electrico] Interruptor de regeneración DPF S111A (si equipado)
- Aplica: Mack Conventional con DPF (US07/US10 y posteriores), 2013BP
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja CB "DPF Regeneration System", pág. 33)

S111A: pin 1 J1939 H, pin 2 J1939 L, pin 3 iluminación, pin 4 masa, pin 5 alimentación desde **F18 10 A**
(bus EMS). El interruptor es un nodo J1939 (no un contacto simple): si no responde, revisar F18, masa pin 4
y la red J1939.

## [postratamiento] Por qué no inicia la regeneración: estados de inhibición que emite el ECM (J1939)
- Aplica: Mack con DPF (desde 2007)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 81-83, PGN 64892 DPF Control 1)

El ECM (SA 0) transmite el motivo de inhibición de la regeneración activa; con un lector J1939 se ve cuál está activo:
| SPN | Inhibida por |
|---|---|
| 3702 | Regeneración activa inhibida (estado general) |
| 3703 | Interruptor de inhibición |
| 3706 | PTO activa |
| 3707 | Acelerador fuera de ralentí |
| 3709 | Velocidad sobre lo permitido |
| 3710 | Freno de estacionamiento no aplicado |
| 3711 | Temperatura de escape baja |
| 3712 | Falla de sistema activa |
| 3714 / 3715 | Bloqueo temporal / permanente del sistema |
| 3716 | Motor no calentado |
Otros: SPN 3719/3720 carga de hollín/ceniza % (PGN 64891); SPN 3251 presión diferencial DPF; SPN 3695/3696
interruptores inhibir/forzar regeneración (SA 23). La VECU PB-4 es salida "regeneración inhibida".
En camiones de riego que trabajan con PTO en ralentí, SPN 3706/3707 explican regeneraciones que nunca ocurren.

## [lectura_codigos_tablero] Lectura de códigos en el tablero Mack (cluster / Co-Pilot): lo que está documentado públicamente
- Aplica: Mack GU (V-MAC IV, Co-Pilot) y GR 2018+ (Driver Information Display)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja BE pág. 16) ; https://www.auroramack.com/sites/default/files/2024-09/Fault%20Codes%20MACK%202014-2017.pdf (pág. 1-3) ; https://www.macktrucks.com/media/files/parts-and-service/support/body-builders/manuals/mack-section-8.pdf (Sección 8 pág. 8 y 14-17)

- La navegación del display se hace con la botonera/palanca de información **S043: SELECT, ESCAPE, UP, DOWN**
  (cluster A:4-A:7). El GU tiene display Co-Pilot (en él aparece, p. ej., el aviso de tolva levantada, Sección 3 pág. 28).
- Formatos que puede mostrar: J1587 **MID-PID-FMI / MID-SID-FMI / MID-PSID** (EPA07/US10 y exportación) y
  J1939 **SPN-FMI**; en US2013+ los DTC OBD son **P-code + FTB**.
- **Desde US2013 los DTC ya no se pueden borrar con el display y la palanca**: se necesita Premium Tech Tool.
- Luces: **MIL** ámbar = falla crítica de emisiones (permanece hasta que el sistema verifica la reparación);
  **STOP** roja = detenerse (riesgo de apagado automático y pérdida de asistencia de dirección); DPF
  regeneración requerida; **HEST** (alta temperatura de escape: durante regeneración en movimiento solo
  enciende bajo 8 km/h).
- La secuencia exacta de menús del Co-Pilot ("Diagnostics → Fault codes") **no está en fuentes públicas
  oficiales**: está en el "V-MAC IV Operator's Manual" (Mack 21394651) que se vende en el Mack eMedia Store
  (https://emedia.macktrucks.com, categoría Driver's Manuals) y en la Mack Driver Guide
  (https://driverguide.macktrucks.com). No inventar la secuencia.

## [motor] Arranque del MP8: límites de tiempo y protección de arranque
- Aplica: Mack MP7, MP8, MP10
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section-2-final.pdf (Mack Body Builder Sección 2 Motor MP7/MP8/MP10, USA179720545, 8.2024, pág. 2)

- **No** dar arranque más de **30 segundos** seguidos; esperar **15 minutos** entre intentos para enfriar el motor de arranque.
- No usar éter ni ayudas de arranque combustibles (riesgo de explosión).
- Arranques con protección: se inhibe el arranque si el motor está en marcha, la temperatura del motor de
  arranque es excesiva, la transmisión no está en neutro o (manual) no se pisa el embrague → revisar señal de
  neutro de la Allison (TCM pin 41 "neutral start") antes de cambiar el motor de arranque.
- Dejar el motor en ralentí 3-5 min antes de apagar (enfriamiento del turbo).

## [motor] Actuador VGT (SRA) y sensor de velocidad del turbo (TSS): fretting de pines – FSB 255-023
- Aplica: Mack CHU, CXU, GU, LEU, MRU, TD, CMM, CMH con MP7/MP8/MP10
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2012/SB-10044247-9335.pdf (Mack FSB 255-023 "Connector Pin, Replacement", 4.2012)

- Síntoma: DTC del actuador VGT por señal no confiable; causa = **desgaste por micro-movimiento (fretting)**
  de pines en los conectores del actuador VGT y del TSS.
- Reparación: reemplazar pines/sockets: pin actuador 984945, socket actuador 3963409, pin TSS 984946,
  socket TSS 11039671, sellos 20734499 / 25325008. Herramientas extracción 9808646 (VGT) / 9809774 (TSS),
  alicate 88890003 con mordaza 88890004. Si conector dañado: conector componente VGT 984944, conector arnés
  VGT 3963412, conector arnés TSS 984849; tapón 970771 para cavidades vacías.
- Desconectar baterías (negativo) antes. Pelar 5 mm de aislación.

## [motor] Actuador del turbo con agua/refrigerante o fusible quemado → reemplazar turbo completo
- Aplica: Mack MP7/MP8 con VGT (SRA)
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2021/MC-10204019-0001.pdf (Mack KB "Diagnosing Turbo Actuator Faults and/or Symptoms (Coolant Cup Plug Leaks)")

- Síntomas: **fusible del actuador del turbo quemado**; agua/refrigerante dentro del actuador o su conector.
- Códigos asociados: **SID 27 FMI 9 / SPN 641 FMI 9 / U010C** y **SID 27 FMI 7 / SPN 641 FMI 7 / P0046**.
- Inspeccionar los tapones (cup plugs) de refrigerante del cuerpo de rodamientos del turbo: si hay
  refrigerante o residuo, **reemplazar el turbo completo** (cambiar solo el actuador provoca fallas repetidas).

## [motor] Sensor de presión diferencial EGR: fretting de pines – FSB 293-007 (MID 128 PID 411)
- Aplica: Mack CHU, CXU, GU, MRU con MP8 EPA2007
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2012/SB-10044962-1193.pdf (Mack FSB 293-007, 7.2012)

- Códigos: **MID 128 PID 411 FMI 3, 5, 12** por señal no confiable del sensor ΔP de EGR.
- Si se confirma fretting: reemplazar sensor 21442662 por el mejorado **21713917** (pigtail y conector
  encapsulados) + kit de arnés **21560217** (conector DIN 4 pines 984849, sello 970771).
- Aunque el boletín es EPA2007, los MP8 de exportación Euro III/IV usan arquitectura similar (verificar p/n con PTT/IMPACT).

## [motor] Válvula EGR MP7/MP8: kit nuevo sin tubo de drenaje – FSB 293-012
- Aplica: Mack MP7, MP8, MP10
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2012/SB-10048459-3000.pdf (Mack FSB 293-012, 11.2012)

- Kit de válvula EGR MP7/MP8 **85123198 reemplazado por 85133799** (MP10: 85123199 → 85135813).
- La válvula nueva **no lleva tubo de drenaje**: al instalarla en un motor que tenía tubo, retirar la
  abrazadera y el tubo. **No quitar el tapón** de la válvula nueva para poner el tubo (daña componentes).

## [motor] Diagnóstico de códigos de flujo EGR (alto/bajo) con prueba de velocidad del turbo
- Aplica: Mack GU/GR/CHU/CXU con MP7/MP8 US10 a US17 con VGT (procedimiento útil también en export con EGR+VGT)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2019/MC-10161908-9999.pdf (Mack/Volvo Solution K52535491, 2019)

Códigos cubiertos: SPN 412 FMI 15/0, SPN 2659 FMI 18/16, SPN 4752 FMI 7; P0401-00, P0402-00, P04DD-00, P1121-00/-98, P2457-00.
1. PTT: operación 2939-08-03-01 "Exhaust Gas Recirculation Function"; motor a **780-840 rpm** (ideal 800) con
   botones de crucero; VGT entre **6 y 14 %** (esperar si está más alto).
2. Con EGR al 0 %: velocidad del turbo debe ser **> 35 000 rpm**. < 30 000 rpm = posible EGR pegada;
   < 20 000 rpm = EGR pegada muy probable.
3. Activar la EGR al 95 %: el turbo debe bajar de **15 000 rpm en 10 s**. Si no cambia = válvula EGR pegada
   cerrada; si baja pero queda > 20 000 rpm = **enfriador EGR tapado**; si responde bien = sospechar sensor ΔP
   EGR o sensor de temperatura EGR.
4. ΔP EGR negativo o ≤ 0,2 psi (1,4 kPa) con válvula abierta = sensor ΔP y/o tubo venturi. Temperatura EGR
   menor que la del refrigerante o mayor que la del escape = sensor de temperatura EGR.
Nota de campo del boletín: los códigos de flujo insuficiente rara vez son eléctricos o de la válvula EGR.

## [motor] Sensor de temperatura EGR MP8 US2013-US2016: nuevo ruteo obligatorio – FSB 293-022
- Aplica: Mack CHU, CXU, GU con MP8 US2013 a US2016
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2017/MC-10110375-9999.pdf (Mack FSB 293-022, 3.2017)

Al reemplazar el sensor de temperatura EGR: usar sensor de 90° con pigtail **21164792** y **7 amarras
948211**, fijado al tubo de refrigerante, alrededor del tubo venturi y a lo largo del arnés principal.

## [combustible] Válvula ePRV del riel común MP7/MP8 (2016-2018): P009B-13 – FSB 237-021
- Aplica: Mack AN, CHU, CXU, GR, GU, PI, MRU, LR, TE con MP7/MP8 fabricados 14-11-2016 a 31-12-2018 (riel común)
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2021/MC-10189885-0001.pdf (Mack FSB 237-021, 3.2021)

- Falla: fuga interna o falla eléctrica de la válvula de alivio de presión electrónica (ePRV) del riel.
- Código: **P009B-13 "Fuel Pressure Relief Control Circuit Open"**.
- Reparación: kit de eliminación de ePRV **85156544** + kit accesorio de software **85156014**; si aplica,
  sensor de presión F2 riel (13 L: 23488939) y arnés trasero (13 L: 23502054).
- Relevante para el GR 2019 si fue fabricado antes del 31-12-2018 y tiene MP8 de riel común (verificar).

## [combustible] P0087 presión de riel baja (MP7/MP8 riel común US17): causa más probable = filtros
- Aplica: Mack GR/GU/AN/PI/CHU/CXU con MP7/MP8 US17+OBD16/OBD18 (años 2018-2019)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2018/MC-10143801-9999.pdf (Mack Solution K00585105, 2018)

- Se activa si la presión del riel cae bajo **≈ 260 bar (3370 psi) por más de 4 s** con motor en marcha →
  derrateo de torque + MIL o STOP.
- Causa más probable: **filtros de combustible restringidos** (falla intermitente, solo con alta demanda).
- Si también está **P008A** (presión baja del sistema de baja presión): verificar software EMS (si MSW <
  23033425.P01, actualizar) y seguir diagnóstico de P008A primero.
- Sin P008A: medir la presión de alimentación con herramental; puede requerir prueba en ruta con carga.
- Campaña PI0883 reduce la severidad (MIL en vez de STOP) pero no elimina P0087.

## [combustible] Todos los inyectores con circuito abierto (P020113 … P020613): probar alimentación y masa del ECM
- Aplica: Mack GU/CHU/CXU/LEU/LR/MRU/TD con MP7/MP8/MP10 (US07 a US17)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2019/MC-10165482-9999.pdf (Mack Solution K08236633, 2019)

Si aparecen juntos P020113, P020213, P020313, P020413, P020513, P020613 (inyector A circuito abierto,
cilindros 1-6), **no cambiar inyectores**: hacer la prueba de alimentación y masa del ECM (fusible F38,
pines X11 13/15 EMS A/B, masas 31/39, relés EMS RLY01/RLY02).

## [postratamiento] Sensores NOx (solo camiones con SCR): cuándo reemplazar y cuándo no
- Aplica: Mack US10+OBD13 y posteriores con SCR (no aplica a MP8 exportación sin SCR)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://static.nhtsa.gov/odi/tsbs/2022/MC-10217013-0001.pdf (Mack NOx Sensor Troubleshooting Guide, 2022)

- Dos sensores "inteligentes" en J1939-7: entrada (NOx 1, pre-SCR) y salida (NOx 2, post-SCR); IDs CAN
  únicos, **no se pueden intercambiar**; no operan hasta que el escape está caliente y sin humedad.
- Reemplazar sensor si activos/confirmados: NOx1 P22FB-92, P220E-93, P2200-13, P2203-00, P2205-13, P2206-00,
  P2208-00; NOx2 P220F-93, P229E-13, P22A6-00, P22A1-00, P22A3-13, P22A4-00, P22FE-00. No reemplazar por inactivos.
- Posible falla (hacer prueba PTT 2549-08-03-03 NOx Conversion Test u 2589-08-03-18): P026C-00, P026D-00, P2201-64, P225C-00, P225E-00.
- **No reemplazar el sensor** por: P220A-1C / P220B-1C (alimentación), P225D-00 / P225F-00 (lee aire fresco
  → fuga de escape), U029D-00 / U029E-00 (comunicación → arnés), P229F-64 (arnés/nuisance).
- No cortar el arnés del sensor (devolución obligatoria en garantía US).

## [boletin_recall] Recall NHTSA 14V078000: contaminación del EPDM (módulo de distribución de potencia) por filtración de agua
- Aplica: Mack CHU, CXU, GU, TD año modelo 2007-2015 producidos 13-10-2006 a 3-10-2014 (incluye GU 2014/2015)
- Tipo: boletin_recall
- Confiabilidad: oficial
- Fuente: https://api.nhtsa.gov/recalls/recallsByVehicle?make=MACK&model=GRANITE%20(GU)&modelYear=2015 (NHTSA campaña 14V078000)

- El **EPDM** puede contaminarse por filtraciones de agua en y alrededor del parabrisas; los depósitos
  pueden puentear circuitos (cortocircuito de alta resistencia) → **riesgo de incendio**.
- Remedio: el concesionario inspecciona el EPDM; si hay contaminación, reemplaza el EPDM y corrige la filtración.
- Uso en taller: fallas eléctricas intermitentes/múltiples, fusibles calientes o corrosión en el panel →
  revisar sellos del parabrisas y el EPDM. Verificar con el VIN si la campaña se aplicó (unidades de
  exportación pueden no haberla recibido).

## [boletin_recall] Recalls NHTSA con componente eléctrico/motor en GU 2014-2016
- Aplica: Mack Granite GU años modelo 2014-2016
- Tipo: boletin_recall
- Confiabilidad: oficial
- Fuente: https://api.nhtsa.gov/recalls/recallsByVehicle?make=MACK&model=GRANITE%20(GU)&modelYear=2015 (NHTSA)

| Campaña | Tema | Detalle |
|---|---|---|
| 15V522000 (Mack SC0393) | Arnés de chasis y líneas de aire mal fijados al travesaño | Pueden caer y enredarse en el cardán → daño eléctrico y de frenos. GU 2009-2010, 2012, 2014-2016. Remedio: fijar correctamente. |
| 14V738000 (SC0386) | Sistema de apagado automático de protección mal cableado | CXU/GU 2015 fabricados 1-1-2014 a 20-8-2014: puede no apagar ante sobre-revolución → daño motor/incendio. |
| 15V528000 (SC0394) | Volumen insuficiente de estanque de aire | GU 2011-2016 (24-9-2011 a 1-7-2015): no cumple FMVSS 121; se agrega volumen. |
| 16V099000 | Tuerca del yugo del eje intermedio (interaxle) se suelta | GU 2012-2016: riesgo de desacople del cardán; cambio de tuerca e inspección de estrías. |
| 16V929000 (SC0406) | Mazas delanteras sin capacidad para el GAWR | GU 2012, 2014-2015, 2017: cambio de mazas. |
| 15V804000 (SC0398) | Desbalance de frenos Granite 4x2 | No aplica a 6x4. |
| 14V554000 | Filtro de combustible Fleetguard FF63009 | Solo motores Cummins ISL (no MP8). |

## [boletin_recall] Recalls NHTSA GU 2017-2018 y GR 2019-2020
- Aplica: Mack Granite GU 2017-2018 y GR 2019-2020
- Tipo: boletin_recall
- Confiabilidad: oficial
- Fuente: https://api.nhtsa.gov/recalls/recallsByVehicle?make=MACK&model=GRANITE%20(GR)&modelYear=2019 (NHTSA) ; https://api.nhtsa.gov/recalls/recallsByVehicle?make=MACK&model=GRANITE%20(GU)&modelYear=2018 ; https://api.nhtsa.gov/recalls/recallsByVehicle?make=MACK&model=GRANITE%20(GU)&modelYear=2017

| Campaña | Tema |
|---|---|
| 16V098000 (SC0400) | GU/MRU 2016-2017 (9-11-2015 a 19-1-2016): falta pasador del yugo superior de dirección → pérdida de dirección. |
| 18V778000 (SC0413) | AN/GR/PI 2019: perno de apriete del eje de dirección superior sin torque → pérdida de dirección. |
| 21V233000 (SC0423) | AN/GR/GU/CHU/CXU/PI 2018-2022 con suspensión "camelback" y ESC: el vehículo no mantiene el carril (FMVSS 136) → **reprogramación de unidades de control del vehículo**. |
| 23V600000 (SC0448) | GU/GR 2015-2023: intermitentes con baja visibilidad → se agregan luces. |
| 19V054000 | GR 2019-2020: espejos exteriores. |
| 18V810000 / 24V773000 | Neumáticos. |
| 25V666000 | GR 2019-2020: anclaje de cinturones delanteros. |

## [frenos] Módulo ABS WABCO 6S/6M (A12A) – alimentación, red y componentes
- Aplica: Mack Conventional CHU/CXU/GU 12 V con ABS WABCO, 2013BP
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja EA "ABS-WABCO", pág. 47)

- Alimentación: **F13 "ABS BATT1"** (bus BATT; el diagrama rotula 20 A en esta hoja y 15/30 A en la hoja AA:
  confirmar con la tapa del panel) y **F49 "ABS" 10 A** (bus EMS).
- Red: conector A pin **A:3 J1939 H**, **A:1 J1939 L**, **A:10 J1587 A**, **A:11 J1587 B**.
- Sensores de rueda: B13/B14 delanteros; B15/B16 1er eje motriz izq./der.; B17/B18 2º eje motriz izq./der.
- Moduladores: Y11/Y12 delanteros, Y13/Y14 traseros izq./der.; Y57 válvula de diferencial/ATC; S016A interruptor ATC/deslizamiento limitado.
- El ABS (SA 11) envía a la transmisión la "solicitud de inhibición de cambio" (SPN 681) en camiones con caja
  automática (Sección 3 pág. 88): una falla ABS puede afectar la operación de la Allison (entrada TCM pin 21 "ABS").

## [electrico] Mensajes J1939 útiles que transmite el camión (direcciones de origen)
- Aplica: Mack conventional con motor Mack (mensajes "since 2007/2010")
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/2024/mack-section3-vecu4-pdf-final-1106.pdf (Sección 3, pág. 80-88, "Supported DL1 SAE J1939 Serial Messages")

| SA | Qué transmite (ejemplos) |
|---|---|
| 0 (motor) | EEC1/2/3 (rpm SPN 190, pedal SPN 91, carga SPN 92), presión combustible SPN 94, nivel/presión aceite SPN 98/100, refrigerante SPN 110/111, EGR SPN 2791, posición VGT SPN 2795, admisión SPN 102/105/106/107, escape SPN 173, DPF SPN 3251/3246/3242, voltaje llave SPN 158, VIN SPN 237 |
| 3 (transmisión) | ETC1/ETC2: marcha seleccionada SPN 524, actual SPN 523, lockup SPN 573, velocidad salida SPN 191; **temperatura aceite transmisión SPN 177** |
| 11 (ABS/EBS) | EBC1 (ABS activo SPN 563, lámpara ámbar SPN 1438), velocidades de rueda SPN 904-910, inhibición de cambios SPN 681 |
| 17 | Cruise control/velocidad (SPN 84, 595-602, PTO SPN 976, freno estacionamiento SPN 70), PTO governor SPN 980/984 |
| 23 | Presiones de aire de freno SPN 1087/1088, nivel combustible SPN 96, interruptores DPF SPN 3695/3696, reloj, distancia SPN 917 |
Con un lector J1939 genérico se puede confirmar que cada módulo está "vivo" en la red (si no aparecen mensajes de SA 3, el TCM no transmite).
