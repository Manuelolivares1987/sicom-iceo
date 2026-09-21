# Scania: conocimiento técnico para diagnóstico (flota Pillado)

Flota: 7 Scania P450 B 6x4 (2024-2025, VIN 9BSP6X400R4.../S4..., armados en São Bernardo do Campo, Brasil).
Usos: carrocería plana, camión pluma de 10 t, aljibe de combustible de 20 kL y riego de 20 kL. Faenas en Calama.
Investigación del 2026-09-19. Todo dato va con su fuente. Si una ficha dice "requiere licencia", el dato NO está en fuentes públicas.

---

## [general] Identificación del P450 B6x4 que se vende en Chile: DC13 143 Euro 5, Opticruise GRSO905R
- Aplica: Scania P 450 B6X4HZ (XT) vendido en Chile, motor DC13 143, 2025
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://fimaj.cl/wp-content/uploads/2025/06/FICHA-TECNICA-CAMION-SCANIA-P450B-6X4-XT.pdf (ficha técnica "P 450 B6X4HZ DC13 143 E5", formato de especificación Scania)

La ficha chilena del P450 B6x4HZ XT indica:
| Ítem | Valor |
|---|---|
| Motor | DC13 143, 450 hp, **Euro 5** |
| Caja | **Opticruise GRSO905R** |
| Retardador | R3500 |
| Tomas de fuerza | ED (con), EG |
| Ejes traseros | RBP735 + RP735 |
| PBTC | 45.000 kg |
| Cuadro de instrumentos | "Con 03888A" (información para carrocero en el instrumento) |
| Otros | ESP desconectable, Hill Hold, AEB, LDW, Infotainment C300 |

Cómo confirmar cada camión: leer la placa del motor. Si dice **DC13 143** es Euro 5 (SCR, sin DPF). Si dice otro código (por ejemplo DC13 147/148 u otro Euro 6), el camión tiene DPF: ver la ficha de regeneración del DPF. Compruébalo contra la ficha de especificación del chasis (FPC) que entrega Scania Chile.

## [general] ¿Euro 5 o Euro 6? Normativa chilena para camiones pesados nuevos
- Aplica: camiones pesados nuevos en Chile, 2024-2026
- Tipo: especificacion
- Confiabilidad: oficial (MMA) + tecnica_terceros (fecha de exigencia)
- Fuente: https://mma.gob.cl/entra-en-vigencia-nueva-norma-de-emisiones-para-camiones-y-buses-nuevos-que-ingresen-al-pais/ ; https://www.chiletransportistas.com/blog/norma-euro-6-en-chile-2026/

- El MMA anunció la norma que exige emisiones "equivalentes a Euro VI o a la norma de los Estados Unidos" para camiones y buses nuevos que ingresen al país. El DS N° 50/2023 del MMA se publicó en el Diario Oficial el 5-jul-2024.
- Según la fuente de terceros, rige 18 meses después de la publicación: desde el **5 de enero de 2026**. Los vehículos inscritos antes de esa fecha mantienen su homologación.
- Consecuencia para la flota: es consistente que los P450 2024-2025 sean **DC13 143 Euro 5 con SCR**, como indica la ficha chilena. La placa del motor tiene la última palabra.

## [general] Motor Euro 6 de 450 hp solo con SCR (DC13 147), para comparar
- Aplica: Scania DC13 147 Euro 6 (450 hp), en caso de que alguna unidad sea Euro 6
- Tipo: especificacion
- Confiabilidad: tecnica_terceros
- Fuente: https://dieselnet.com/news/2014/06scania.php ; https://www.oemoffhighway.com/engines/press-release/11502053/scania-introduces-new-scronly-euro-6-engine

- El DC13 147 cumple Euro 6 **sin EGR** y sin turbo de geometría variable: usa solo SCR (con DPF). Entrega 450 hp y 2.350 Nm desde 1.000 rpm.
- Un motor solo SCR consume más AdBlue: "en promedio ~6 % del diésel", contra ~3 % de un motor EGR+SCR.
- La página de Scania Chile lista el P 450 hp como Euro 6 con SCR, de 2.350 Nm (https://www.scania.com/cl/es/home/products/trucks/p-series/p-series-specifications.html).

## [electrico] Generación del sistema eléctrico: Gen 6 (9742A) vs Gen 7 (9742B) y la herramienta de diagnóstico
- Aplica: Scania P/G/R/S 2024-2025; unidades brasileñas desde abril de 2025
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/newsletter/BBC_Newsletter_March_2024.pdf (BBC Newsletter 27-mar-2024) ; https://bodybuilder.scania.com/trucks/en/tools-and-services/electric-configuration.html ; https://alphaautos.com.br/2024/11/inovacao-e-seguranca-marcam-nova-fase-dos-caminhoes-scania

- Durante 2024 Scania introdujo gradualmente el **Sistema eléctrico Generación 7** (código de variante **9742B**, "SESAMM7"), junto con el nuevo tablero digital (Smart Dash) y ciberseguridad (UNECE R155/R156).
- Brasil: "A partir de abril de 2025, todos os caminhões Scania sairão de fábrica equipados com a sétima geração eletrônica." Los P450 2025 armados en São Bernardo pueden ser Gen 7. Los de 2024 probablemente son Gen 6 (9742A). Confirmar por el código de variante del chasis.
- **SWS (Scania Workshop Suite) + VCI4** es la única forma de conectarse a un vehículo Gen 7. También es compatible con Gen 6. En Gen 7 **SDP3 no sirve**. Según Scania, SWS por ahora está disponible solo para concesionarios.
- Para el carrocero, el sistema eléctrico de carrocería (BWE) no cambia: se mantienen P9, P11, la consola de carrocería (C259, C493...) y el BCI.

## [general] Herramientas de diagnóstico Scania y licencias (acceso de talleres independientes)
- Aplica: toda la gama Scania
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.scania.com/group/en/home/products-and-services/services/rmi/diagnostics.html (Scania RMI Diagnostics)

- **SDP3**: herramienta de diagnóstico para camiones de la serie 3 a la 6. La licencia queda ligada al PC y se compra por tiempo a través de TIS.
- **SWS**: reemplaza gradualmente a SDP3. Es obligatoria para vehículos ciberseguros (Gen 7) y trabajos de seguridad. Además del VCI requiere un WCU o una Remote box.
- **VCI**: interfaz obligatoria. Para SDP3 sirve una Scania o una compatible ISO 22900-2. Para SWS debe ser compatible SAE J2534.
- Requiere licencia: los manuales de taller, los diagramas eléctricos completos y el diagnóstico guiado están en TIS/SDP3/SWS (portal RMI de Scania).

## [electrico] Manual del conductor por chasis (app oficial): allí están las tablas de fusibles de cada camión
- Aplica: Scania P/G/R/S nueva generación
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://sws.scania.com/driversguide ; https://bodybuilder.scania.com/trucks/es/instructions/drivers-manual.html ; https://www.scania.com/cl/es/home/about-scania/newsroom/news/2024/scania-presenta--driver-app---la-herramienta-digital-para-conduc.html

- Scania no publica el Manual del conductor como PDF. Se descarga en la app **"Scania Driver's Manual"** (Android/iOS), que permite bajar el manual **del chasis específico**, en español, y usarlo sin conexión.
- Procedimiento: instalar la app, ingresar el número de chasis (en la placa y en la documentación del camión) y buscar la sección de fusibles y relés.
- Los amperajes y posiciones exactas de fusibles de la central eléctrica **no están en fuentes públicas descargables**. Hay que sacarlos de la app para cada chasis o de la etiqueta dentro de la tapa de la central (ver la ficha P2).

## [electrico] Tres buses CAN Scania: rojo, amarillo y verde (qué ECU va en cada uno)
- Aplica: Scania P/R/T/G (serie PGR, 2004 en adelante); el concepto de colores sigue en la nueva generación
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (Scania 16:07-01 Issue 3, 2005, "Electrical system in P, R, T series – Introduction and general troubleshooting", págs. 7-10)

| Bus | Prioridad | ECU (ejemplo PRT) |
|---|---|---|
| **Rojo** (C480) | la más alta | EMS motor, BMS frenos (ABS/EBS), SMS suspensión neumática, GMS caja/retardador (Opticruise), COO coordinador |
| **Amarillo** (C481) | media | APS aire comprimido, ICL instrumento, VIS luces/visibilidad/bocina, LAS cierre/alarma, BWS interfaz de carrocería, TCO tacógrafo |
| **Verde** (C479) | la más baja | CSS airbag, ACC climatización, AUS radio, RTI, RTG, CTS/ATA/WTA calefactores |

- **El COO es el gateway** entre los tres buses.
- La herramienta de diagnóstico (Scania Diagnos/SDP3) se conecta al **bus verde**, y el COO enruta la consulta al bus rojo o amarillo (ver también https://uu.diva-portal.org/smash/get/diva2:913722/FULLTEXT01.pdf, Uppsala 2016, págs. 15 y 44).
- Un vehículo simple tiene al menos 5 ECU: EMS, COO, VIS, APS e ICL.
- En la nueva generación (2016+) hay más ECU y más buses (por ejemplo, la caja se llama TMS en documentos recientes). La asignación exacta por bus del NTG requiere licencia: TIS/SWS.

## [electrico] Síntomas de falla por bus: el amarillo afecta al instrumento, el verde bloquea el diagnóstico
- Aplica: Scania PGR/NTG con buses CAN rojo, amarillo y verde
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (16:07-01, págs. 7 y 12)

- El ICL está en el bus amarillo. Una falla en el bus amarillo no debería detener el vehículo, pero el ICL deja de "escuchar" los otros buses y **pide al conductor detenerse**.
- **Sobrecarga del bus**: una ECU defectuosa que transmite mensajes erróneos sin parar puede saturar el bus. Faltan funciones y, si el saturado es el bus verde, **SDP3 no se puede usar**. Para aislar la ECU culpable, desconectar ECU del bus una por una.
- Un sensor con información errónea puede generar códigos en varias ECU que usan o reenvían ese dato. Hay que seguir la ruta de la información (por ejemplo, temperatura de refrigerante: EMS → COO → ICL).

## [electrico] Activación de las ECU: alimentación 30, señal X15, fusible adicional y conectores C482/C483
- Aplica: Scania P/R/T (PGR 2004+); el principio aplica a la nueva generación
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (16:07-01, págs. 12-13)

- Para recibir mensajes CAN, una ECU necesita **alimentación 30** (batería) y una **señal de activación**, normalmente **X15** desde la cerradura de encendido en posición de marcha.
- La cerradura recibe el 30 a través de un **fusible de 10 A**. Las ECU de los buses verde y amarillo tienen un fusible adicional, para que una falla en ellos no deje sin 15 al bus rojo.
- Serie PRT: **C483** alimenta con 15 los buses amarillo y verde (bajo el centro del tablero). **C482** alimenta el bus rojo (bajo la central eléctrica).
- Excepciones: LAS funciona con el camión cerrado, AUS se activa en posición radio y ATA/WTA solo por orden de CTS/ACC.
- Prefijo "X" en el cableado = cable de información (por ejemplo X15), no de potencia.

## [electrico] Archivo SOPS en COO/ICL: al reemplazar una ECU hay que parametrizarla
- Aplica: Scania P/R/T y posteriores
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (16:07-01, pág. 14)

- La configuración del vehículo (número de ejes, frenos, suspensión, estanque, etc.) va en el **archivo SOPS**, guardado en el COO y en el ICL.
- El COO vigila que no se hayan reemplazado ECU críticas. **Una ECU nueva debe cargarse con los parámetros del SOPS** usando la herramienta Scania (SDP3/SWS).
- Los cambios menores del SOPS (por ejemplo, estanque de combustible más grande) se hacen con SDP3. Los mayores pueden requerir enviar el SOPS a Scania.
- Implicancia en faena: no intercambiar ECU entre camiones "para probar" sin la herramienta, porque la ECU queda sin la configuración del vehículo.

## [electrico] Direcciones J1939 (source address) de las ECU Scania
- Aplica: Scania trucks (interfaz CAN externa de carrocería, J1939)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-trucks-Fault-Codes-PDF-CAN-interface-for-bodywork.pdf (Scania 11:90-01 Issue 1, 2013, "CAN interface for bodywork", pág. 136, tabla 1)

| ECU | Source address (hex) |
|---|---|
| EMS motor | 00 |
| GMS caja | 03 |
| BMS frenos | 0B |
| RET retardador | 10 |
| ICL instrumento | 17 |
| LAS cierre/alarma | 1D |
| VIS visibilidad | 1E |
| COO coordinador | 27 |
| BWS carrocería | 2E |
| SMS suspensión | 2F |
| APS aire | 30 |
| TCO tacógrafo | EE |

Sirve para leer con un escáner J1939 genérico o un registrador CAN qué ECU emite cada DM1 (el último byte del identificador es la dirección).

## [electrico] CAN externo para carrocería: pines, terminación de 120 ohm, largo máximo y colores
- Aplica: Scania con BWS/BCI (interfaz CAN para carrocería)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-trucks-Fault-Codes-PDF-CAN-interface-for-bodywork.pdf (11:90-01, págs. 1 y 133-135)

- Protocolo basado en **SAE J1939**. Capa física "J1939-15 Light", con par trenzado sin blindaje (40 vueltas/m).
- BWS (generación anterior): CAN de carrocería en **C259 pin 21 = CAN_H y pin 20 = CAN_L**. En el chasis: **C487 pin 6 = CAN_H y pin 7 = CAN_L**.
- Colores obligatorios del CAN externo: **CAN_H azul y CAN_L blanco**.
- **Terminación: 120 ohm en cada extremo.** La unidad de carrocería trae una terminación dividida interna (2 × 60 ohm + 100 nF). El otro extremo debe terminarse en la ECU del carrocero más lejana.
- Límites: cable principal ≤30 m desde C259, derivaciones ≤3 m, ≤9 ECU y ≥0,1 m entre nodos.
- Si solo se usa CAN dentro de la cabina, hay que retirar el puente de fábrica C259-20/21 → C494-6/7 para no dejar cable sin terminar hacia los DIN del chasis.
- **IMPORTANTE (Scania):** no conectar ningún otro bus CAN ni conector. Un error puede alterar funciones del vehículo y dejarlo detenido.
- Comprobación de taller (principio J1939): con el contacto cortado, medir la resistencia entre CAN_H y CAN_L. Dos terminaciones de 120 ohm en paralelo deben dar aproximadamente 60 ohm.

## [electrico] BCI (nueva generación): CAN externo en C493 pin 3 (CAN-L) y pin 4 (CAN-H)
- Aplica: Scania P/G/R/S nueva generación con BCI (FPC5837)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Bodywork-information-in-the-instrument-cluster.pdf (Scania TBB 22:10-051 Issue 5, 2017, pág. 31) ; https://bodybuilder.scania.com/trucks/en/tools-and-services/electric-configuration/logikscheman-foer-bict/reglering-av-motorvarvtal-med-can.html

- La conexión CAN externa del BCI va directo al conector **C493: CAN-low en pin 3 y CAN-high en pin 4**.
- Por ese CAN el carrocero puede, por ejemplo, controlar el régimen del motor con mensajes J1939 (control tipo "External CAN" del parámetro Engine speed 1) o activar indicaciones en el instrumento (Driver Information Request 1-10).
- Si una grúa o sistema de cisterna con CAN falla en comunicación, revisar en C493 la continuidad de los pines 3/4, la terminación y la resistencia CAN.

## [electrico] Bloques de conexión CAN con resistencia de terminación incorporada
- Aplica: Scania P/R/T (PGR) y posteriores
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (16:07-01, sección Connectors)

- Algunos bloques de conexión del bus CAN traen **resistencias de terminación integradas**. Si la resistencia está dañada, **se reemplaza el bloque completo**.
- La **fila central del bloque CAN está inactiva**: no conectar nada ahí.
- Tipos de conector: MCP en interruptores y uniones de cabina, DIN y Deutsch fuera de la cabina, MQS en sensores de cabina.

## [electrico] Central eléctrica principal P2 (cabina): ubicación y etiqueta de fusibles
- Aplica: Scania P/G/R/S nueva generación
- Tipo: fusibles_reles
- Confiabilidad: experiencia_campo (ubicación) + oficial (etiqueta)
- Fuente: https://www.scegliauto.com/en/video/vari-altri/tutorial/98481/ (ubicación NTG, tutorial en video) ; https://www.youtube.com/watch?v=GhPGNE3frfI ("Scania Fuse Box Location and opening 2018 to 2022") ; https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/scania-parts-for-bodybuilding/Electrical_system.pdf (Bodybuilding Part numbers – Electrical system: "Fuses and relays information sticker")

- En la nueva generación, la central de fusibles y relés de cabina está **en el lado del acompañante, detrás del panel inferior del tablero**. Se abre la puerta del acompañante, se retira el panel central haciendo palanca, se gira 90° el tornillo plástico del borde superior y se retira el panel inferior. (Fuente de terceros: confirmar en el primer camión y actualizar esta ficha.)
- En el reverso del panel/tapa hay una **etiqueta con la tabla de fusibles y relés** (Scania la vende como repuesto, "Fuses and relays information sticker").
- La numeración y el amperaje por posición varían según la especificación. Deben leerse en la etiqueta del camión o en la app Driver's Manual del chasis. **No hay tabla pública confiable.**
- Gen 7 (9742B): se eliminó la alimentación de 12 V desde las posiciones de fusible de P2. Para equipos de 12 V se usa un conversor 24/12 V (repuesto Scania). Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/newsletter/BBC_Newsletter_March_2024.pdf

## [electrico] Central eléctrica de carrocería P9 (cabina): máximo 90 A total
- Aplica: Scania P/G/R/S (PGR y nueva generación; se mantiene en Gen 7)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (Scania GB, "Bodybuilder Quick Reference Guide – Electrical", 24-oct-2019, pág. 2)

- Alimentación recomendada para funciones de carrocería de bajo consumo: **central eléctrica de carrocería P9**.
- **Salida máxima total de P9: 90 A.** Los fusibles **F7-F12 suman 30 A en total** (según la guía).
- Masa en cabina asociada: **G70, máximo 90 A**.
- Detalle en el TBB bwm_0001046_01 (til.scania.com). Requiere login: Truck Bodybuilder Portal.
- Diagnóstico: si una luz de trabajo, baliza o señal de carrocería falla, revisar primero los fusibles de P9 antes que el BCI.

## [electrico] Central eléctrica de chasis P11 (detrás de la rueda delantera izquierda): mega fusibles de 40-250 A
- Aplica: Scania P/G/R/S (PGR y nueva generación)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (pág. 2) ; archivo local "Scania - Body builder cisternas Tank and Bulk.pdf" (_Descargados oficiales 2026-09/Scania, pág. 2)

- **P11** es la central de fusibles principales del vehículo, **detrás de la rueda delantera izquierda**. Usa **mega fusibles de 40 a 250 A**.
- Allí llegan los cables de baterías, motor de arranque y consumos grandes de carrocería.
- Consumos de carrocería de alta corriente: posición **P11.F, máximo 250 A**. El fusible de P11.F **no viene de fábrica: lo instala el carrocero**.
- El folleto Tank bulk indica "BB electrical supply 150 A continually, 250 A max", con salida dedicada detrás del guardabarros del primer eje delantero.
- Diagnóstico de bombas eléctricas, calefactores o equipos grandes de carrocería sin energía: revisar el mega fusible del carrocero en P11.F y sus terminales (corrosión y torque del terminal).

## [electrico] Masas para carrocería: G46/G47 en el larguero izquierdo, nunca G32
- Aplica: Scania P/G/R/S
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (pág. 3)

- Masas de carrocería en el chasis: **G46 y G47**, con tornillo de rosca exterior **M10** en la brida. Se conecta sin soltar el tornillo del larguero.
- **G32 (masa de batería) nunca debe usarse para carrocería.**
- Todas las masas de carrocería en el chasis van al **larguero izquierdo**. Una masa en el larguero derecho provoca caídas de tensión.
- Una masa adicional en el larguero izquierdo debe hacerse con el tornillo de masa Scania **2 261 990**.
- En cabina: **G70 (máx. 90 A)**. Hay 5 bloques de masa con **máx. 6,4 A por bloque** y **32 A en total**. En el techo: G64 y G65.
- Diagnóstico: si la grúa/pluma o la bomba de la cisterna tienen fallas intermitentes, revisar si la masa del equipo quedó en el larguero derecho o en G32.

## [electrico] Perno de masa en el bastidor: máximo 3 terminales y torques
- Aplica: Scania P/R/T (PGR) y posteriores
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (16:07-01, sección Earthing)

- Las masas principales son el larguero izquierdo, el bloque de motor y caja, y la estructura de la cabina.
- **Máximo 3 terminales de ojo por punto de masa.** Si se necesitan más, agregar puntos de masa.
- Tuerca de conexión de masa (P/N 815133): **30 Nm con herramienta manual**. Debe quedar visible al menos 1 hilo.
- Perno de masa del bastidor (P/N 1743995, tuerca 815134): apretar a mano hasta que la brida haga contacto, **máximo 50 Nm** (con más se corta). Holgura máxima entre brida y bastidor: 0,2 mm. Si el perno gira con facilidad, el agujero está sobredimensionado.
- Limpiar óxido y pintura del agujero. **Prohibido perforar las alas del bastidor.**

## [electrico] Colores de fusibles ATO, Maxi y Mega usados por Scania
- Aplica: Scania P/G/R/S (repuestos para carrocería)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/scania-parts-for-bodybuilding/Electrical_system.pdf (Bodybuilding Part numbers – Electrical system)

| Tipo | Amperaje: color |
|---|---|
| ATO | 2 A gris, 5 A naranjo, 7,5 A café, 10 A rojo, 15 A azul, 20 A amarillo, 25 A blanco, 30 A verde |
| Maxi | 40 A naranjo, 60 A azul |
| Mega | 40, 60 y 80 A negro; 100 A amarillo; 125 A verde claro; 150 A naranjo; 200 A azul |

Relés: micro relay, mini relay y power relay, con portarrelés y trabas propias. Los números de parte están en el mismo documento. Verificar los números de parte en el PDF, porque la tabla del PDF tiene las columnas desalineadas.

## [electrico] Cortacorriente (chave geral): qué queda energizado
- Aplica: Scania P/G/R (y buses K/N/F), 2016
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/master/pdf/w_wsm000106pt-BR03.pdf (Scania 00:01-06 Ed. 3 pt-BR, "Informações do produto para serviços de resgate", págs. 15-17)

- Con el cortacorriente activado, en la mayoría de los vehículos **solo el tacógrafo y la alarma quedan con energía**.
- **Según cómo esté conectada la carrocería, puede quedar energizada** con el cortacorriente activado. Hay que revisarlo en aljibes y cisternas antes de intervenir.
- Formas de accionamiento: palanca junto a la caja de baterías, interruptor externo detrás de la cabina lado izquierdo, o interruptor en el tablero (por ejemplo en vehículos ADR).
- Si las baterías van atrás, existe una toma de arranque auxiliar que queda activa aun con el cortacorriente activado.
- Sin cortacorriente, hay que desconectar la batería para cortar la alimentación.

## [electrico] Arranque con cables (jump start) y límites del motor de arranque
- Aplica: Scania P/G/R/S nueva generación (24 V)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (Extracts from the Driver's Manual – Jump start)

- Ambos sistemas deben ser de **24 V**. Usar **cables de al menos 25 mm²** con pinzas aisladas.
- Orden (opción 1): (1) + de la **batería de servicio** del camión descargado; (2) + del camión cargado; (3) − del camión cargado; (4) − del camión descargado, al final porque puede saltar chispa. Arrancar. Al desconectar, retirar primero el cable del − del camión descargado.
- Si no arranca, repetir, pero en el paso 1 conectar al + de la **batería interior**.
- **El motor de arranque se bloquea automáticamente a los 35 s.** Arrancar como máximo 30 s. Si no parte, llevar la llave a posición radio y esperar unos 30 s. Después de 2 intentos, dejar descansar el arranque **al menos 5 minutos** antes de otros 2 intentos, e investigar otra causa (por ejemplo, el sistema de combustible).

## [electrico] Circuito de potencia: alternador → arranque → C41 → batería; C55 alimenta P2 y VIS
- Aplica: Scania P/R/T (PGR); referencia de principio para la nueva generación
- Tipo: diagrama_electrico
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Electrical-system-in-P-R-T-series-Introduction-and-general-troubleshooting.pdf (16:07-01, sección Power supply)

- El cable del **alternador P3** va por el **motor de arranque M1** y el **bloque de unión C41** a la **batería P1**. Normalmente hay un cortacorriente antes de la batería.
- De **C41** sale un cable al bloque **C55**, que alimenta la **central eléctrica P2** y el sistema de visibilidad **VIS**.
- Denominaciones: 15 (marcha), 30 (batería), 12V/30 y 12V/RA (conversor), 31 (masa), 58 (luces de posición), 61 (estado de carga).
- Diagnóstico de caída de tensión o falla de carga: medir la caída en C41 y C55 y en las masas del motor y del larguero izquierdo.

## [implemento] BCI: unidad programable de interfaz con la carrocería (C259, C493 y BICT)
- Aplica: Scania P/G/R/S con BCI (FPC5837 / variante 5837A)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (pág. 7) ; https://bodybuilder.scania.com/trucks/en/tools-and-services/electric-configuration.html

- El **BCI (Bodywork Communication Interface)** es la unidad de control de las funciones de carrocería. Lee la información de las demás ECU por el CAN interno y decide si la activación está permitida.
- Conexión: **C259 y C493** y/o CAN de carrocería. Los pines de C259 **no tienen una función fija**: se configuran con **BICT** (Body Interface Configuration Tool), que define qué señal va en cada pin y si activa con +24 V o con masa.
- BICT viene integrado en SDP3 y también existe como programa independiente. El proyecto BIC puede entregarse a un taller Scania para programarlo.
- Diagnóstico: si una función de carrocería "no hace nada" pero el cableado está bien, la causa puede ser la lógica BICT (condiciones de freno de estacionamiento, PTO, velocidad). Para leer la lógica programada se necesita SDP3/SWS (requiere licencia).

## [implemento] Arnés cabina-chasis: C494 → conectores DIN C486/C487/C488 (7 pines) detrás de la rueda delantera izquierda
- Aplica: Scania P/G/R/S con familia de variante 2411
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (pág. 1)

| N° de DIN | Pines | Variante | Marcación |
|---|---|---|---|
| 1 | 7 | 2411B | C487 |
| 2 | 7+7 | 2411E | C486 y C487 |
| 3 | 7+7+7 | 2411F | C486, C487 y C488 |

- Las señales de la consola de carrocería salen del **conector C494** y llegan a 1, 2 o 3 DIN de 7 pines en el bastidor, **detrás de la rueda delantera izquierda**.
- Extensiones de fábrica: 2 m (3023A), 8 m (3023D) y 12 m (3023C). **Si se piden de fábrica, incluyen una caja de conexiones con clasificación ADR.** Vienen sin conectar, guardadas en la cabina.
- Diagnóstico en cisterna/pluma: la mayoría de las fallas de carrocería se producen por agua o barro en los DIN C486-C488. Revisarlos primero.

## [implemento] Conector C234: 10 entradas para testigos de carrocería en el instrumento (+24 V o masa) y pin 12 de despertar
- Aplica: Scania P/G/R/S con opción 3888A (información de carrocería en ICL); el P450 de la ficha chilena tiene 03888A
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-Bodywork-information-in-the-instrument-cluster.pdf (Scania TBB 22:10-051 Issue 5, págs. 4, 22-24, 28, 32)

- Las indicaciones de carrocería (10 posiciones de testigo, sonidos y mensajes) se activan por **C234 con +24 V o masa**, por BIC o por CAN externo.
- **C234 pines 1-10**: de fábrica, el pin 1 es **activo bajo (masa)** y los pines 2-10 son **activos altos (+24 V)**. Se cambian con parámetros de SDP3 ("Driver's information").
- **Pin 12 de C234 con +24 V = señal de despertar del ICL**: permite mostrar las indicaciones aun con la llave en posición bloqueada.
- Posiciones: 1-2 advertencia/info (amarillo/verde), 3 advertencia/info (amarillo/azul), 4-5 alarma/info (rojo/verde), 6 alarma (rojo), 7-10 advertencia/alarma (amarillo/rojo).
- Ejemplo de fábrica: pos. 1 EXT; pos. 8, 9 y 10 = testigos de PTO 1, 2 y 3; pos. 2 = PTO 4.
- Si un testigo de la pluma o del estabilizador no enciende, medir +24 V o masa en el pin correspondiente de C234 y revisar el parámetro de polaridad.

## [implemento] Entradas del BCI en C259 para arranque/parada remota y régimen (según lógicas oficiales)
- Aplica: Scania P/G/R/S con BCI (lógicas BICT de ejemplo)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/tools-and-services/electric-configuration/logikscheman-foer-bict.html (Logic diagrams for BICT)

| Función (lógica de ejemplo Scania) | Entrada en C259 (opcional, preconfigurar en BICT) |
|---|---|
| Arranque remoto del motor | pin 9 (señal alta o baja) |
| Parada remota del motor | pin 10 |
| Subir régimen | pin 1 |
| Bajar régimen | pin 2 |
| Mensaje al conductor en el ICL | pin 1 |

- Son asignaciones **de las lógicas de ejemplo**. En cada camión el pin real depende del proyecto BICT cargado. **No asumir sin leer la configuración.**
- Para llevar las señales fuera de la cabina se usa C494 → DIN C486/C487/C488.
- **Las salidas del BCI no pueden entregar más de 3 A.** Para solenoides o válvulas de mayor consumo se deben usar relés.

## [implemento] Ralentí de trabajo para bombas y grúa: "Engine speed 1" (valor fijo, botonera de crucero o CAN externo)
- Aplica: Scania P/G/R/S con BCI; camión pluma, aljibe y riego
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/tools-and-services/electric-configuration/logikscheman-foer-bict.html (Preset engine speed / Engine speed control / Engine speed control using CAN)

- **Preset engine speed**: sube el motor a un régimen predefinido bajo ciertas condiciones, por ejemplo al conectar la PTO EG ("preparar el motor para levantar la grúa"). Se configura el parámetro **Engine speed 1** en SDP3 con **Type of control = Fixed value**.
- **Engine speed control**: el régimen se ajusta desde fuera de la cabina con el interruptor EXT y la PTO conectada. Type of control = **Switch module for cruise control**.
- **Engine speed control using CAN**: régimen por mensajes J1939 al BCI por C493-3/4. Type of control = **External CAN**.
- Si la bomba no alcanza su régimen de trabajo, revisar si la PTO está realmente conectada (testigo en el ICL), si está activo EXT (cuando la lógica lo exige) y cuál es el valor de Engine speed 1. Leer ese valor requiere SDP3/SWS.

## [implemento] Parada de emergencia con PTO EG para cisternas y grúas (lógica oficial)
- Aplica: Scania con BCI; cisternas y camiones grúa
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/tools-and-services/electric-configuration/logikscheman-foer-bict.html (Emergency Stop)

- La lógica "Emergency Stop" (aplicaciones: camiones forestales, **tankers** y **crane trucks**) detiene el motor si se acciona el interruptor de emergencia **con la PTO EG activada**.
- Con la PTO EG conectada, el motor también se detiene por **baja presión de aceite** o **alta temperatura de refrigerante**.
- Sin la PTO EG conectada, la parada de emergencia no afecta al motor.
- Si el motor se apaga solo mientras bombea, revisar primero si la lógica de parada está programada, y después el nivel y la presión de aceite y la temperatura de refrigerante (códigos DM1 SPN 100/110).

## [implemento] PTO EG (en la caja): condiciones y procedimiento de acople
- Aplica: Scania P/G/R/S con PTO EG (FPC6392), Opticruise
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (EG Power Take-off)

- La EG la mueve el eje intermedio de la caja y **depende del embrague**. Para activarla: **llave en marcha y presión de aire sobre 5 bar**. El carrocero puede agregar otras condiciones (BICT).
- Acople: vehículo detenido → pisar el embrague o poner neutro → presionar el interruptor → esperar el **símbolo de PTO en el instrumento** → soltar el embrague lentamente (caja manual).
- Sin símbolo después de 10 s: soltar el embrague lentamente para que los engranajes se acomoden, sin volver a pulsar. **Caja automática: si el símbolo no aparece en 20-30 s, repetir.** Si hay ruido anormal, pulsar el interruptor: la PTO se desacopla sola.
- Con la EG conectada **se bloquean los cambios en marcha**. Si se avanza con la EG activa, aparece un mensaje en el ICL.
- Con caja con splitter, el split alto o bajo (seleccionado con la palanca del freno auxiliar) cambia la velocidad de la PTO al mismo régimen de motor.
- El régimen se ajusta con **+/- del interruptor de crucero**. Solo acoplar o desacoplar sin carga.

## [implemento] PTO ED (en el motor, independiente del embrague) y PTO EK
- Aplica: Scania con PTO ED (FPC4827; el P450 de la ficha chilena tiene "Toma de fuerza ED: Con") o EK
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (ED / EK Power Take-off)

- **ED**: la mueve directamente la distribución del motor y **gira siempre que el motor está en marcha**. El interruptor **activa la hidráulica y da presión al sistema**. Acople = activar el interruptor. Desacople = desactivarlo. El régimen se ajusta con +/- del crucero.
- Si hay presión hidráulica sin haber accionado el interruptor, o no hay presión con el interruptor activado, revisar la señal eléctrica a la válvula o bomba (salida del BCI/P9) antes que la PTO.
- **EK** (entre motor y caja): **se acopla con el motor apagado**. Motor apagado → neutro → llave en marcha → activar el interruptor → arrancar.

## [implemento] Interruptor EXT y sistema hidráulico Wet kit
- Aplica: Scania P/G/R/S con BCI y/o wet kit
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (EXT switch / Wet Kit)

- **EXT**: función de seguridad que habilita el control de algunas funciones desde **fuera del vehículo**. Al activarla se enciende el símbolo EXT en el instrumento. Qué se puede controlar depende de la lógica de carrocería.
- **Wet kit**: la presión del sistema hidráulico se fija en **150 o 220 bar** (2 posiciones fijas, sin posiciones intermedias) con la perilla. Antes de conectar un equipo, verificar su presión máxima.

## [implemento] Preparaciones de fábrica para camión pluma, hook lift y cisterna (códigos FPC)
- Aplica: Scania P/G/R/S nueva generación
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/factory-fitted-options/booklets/new-en/HOOK_LIFT.pdf ; https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/booklets/5197502-11_Truck-Bodybuilder_210x297mm_Flat-bed-crane_print.pdf

| FPC | Función |
|---|---|
| 5837 | BCI, interfaz de carrocería programable |
| 6793 | Espacios en el tablero para interruptores programados en el BCI |
| 7682 | Interruptores programables vía BICT |
| 3821 | Dos límites de velocidad adicionales programados en el BCI |
| 3888 | Información de carrocería en el ICL (8 testigos, sonido y mensajes) |
| 2411 | Arnés precableado desde la central de carrocería al bastidor |
| 3023 | Extensiones de 7 pines de 2, 8 o 12 m |
| 3314 | Arnés extra para interruptores adicionales |
| 6392 | PTO EG en caja (depende del embrague) |
| 4827 | PTO ED en motor (independiente del embrague) |
| 4801 / 4802 / 4803 | Tipo y cilindrada de la bomba hidráulica |
| 5030 | Espacio para patas estabilizadoras detrás de la cabina |
| 384 | Bastidor reforzado para grúa trasera |
| 1330 | Preparación para baliza |

Pedir a Scania Chile la lista FPC de cada chasis por su VIN. Con ella se sabe qué preparaciones eléctricas tiene de fábrica.

## [implemento] Mensajes CAN de carrocería (J1939) y dirección 2E del BWS
- Aplica: Scania con BWS/BCI (camiones desde 2005 en adelante)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.truckspares365.co.uk/hub/wp-content/uploads/2022/08/Scania-trucks-Fault-Codes-PDF-CAN-interface-for-bodywork.pdf (11:90-01, págs. 5-7 y 136-137)

- Mensajes que recibe el vehículo: Scania Bodywork Control Message 1 (0C FF F8 xx), 2 (0C FF F9 xx) y 3 (0C FF E6 xx, desde oct-2008).
- **No usar la dirección 2E**: es la de la unidad de carrocería.
- Mensajes que salen del vehículo, por ejemplo: EEC1 0C F0 04 00 (EMS), EEC2 0C F0 03 00, Engine Temperature 18 FE EE 00, Engine Hours 18 FE E5 00, **PTO information 18 FF 90 27 (COO)**, y Software identification 18 FE DA 2E (BWS).
- PGN propietarios Scania reservados: 00 FF B4 Alarm Status, 00 FF 90 PTO Information, 00 FF 81 DLN2, 00 FF A0 Transmission Proprietary, etc.
- Uso en faena: un registrador CAN conectado al CAN externo permite ver el estado de la PTO y del motor sin la herramienta Scania.

## [implemento] Nueva PTO EG Hot-Shift (2025): TMS limita el régimen y hay señales para BICT
- Aplica: Scania con EG10R/EG9R/EG8R MCP1-xx y EG6R MDP1-xx Hot-Shift (desde oct-2025)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/newsletter/BBC_Newsletter_October_2025.pdf (BBC Newsletter 10-oct-2025)

- Es una PTO de eje intermedio con embrague multidisco húmedo. Entrega **hasta 1.000 Nm y 160 kW**.
- El acople del embrague de garras debe hacerse **con el vehículo detenido y la caja en neutro**. Después, el embrague húmedo puede activarse detenido o en marcha.
- El **TMS (Transmission Management System) calcula el régimen máximo admisible del motor** para una operación segura.
- Las señales de estado ("Hot-Shift Engaged") están disponibles por lógica BICT o por el CAN externo del BCI.
- Nota: en la nueva generación, la ECU de la caja se denomina **TMS** (antes GMS).

## [electrico] Leer los códigos de falla en el instrumento sin herramienta (IVD)
- Aplica: Scania P/G/R/S nueva generación (2016+)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/www/market/uk/about-us/brochures/truck/brochure/brochure-scania-next-gen-quick-guide.pdf (Scania "Quick Guide – Instrument cluster and steering wheel", sección "Menus in the display")

Pasos:
1. Contacto en marcha (motor detenido o en ralentí, vehículo detenido).
2. Con el **botón de navegación de menú del volante**, entrar al menú del display.
3. Ir a **Settings (Ajustes) → Information (Información) → IVD, In-vehicle Diagnostics (diagnóstico a bordo)**.
4. Allí se listan los códigos de falla. Anotar la **unidad de control** (EMS, TMS/GMS, EBS/BMS, APS, COO, ICL, BCI...), el código, y si está activo o inactivo.
5. Botones del volante: OK (16), Atrás (14), Menú (15) y Selección rápida (13), según la numeración de la guía.

- El formato exacto del código que muestra el IVD y su tabla de significados por ECU **no están en documentación pública**. Requiere licencia: SDP3/SWS o TIS.
- Colores de los mensajes: **rojo** = riesgo de lesión o daño grave, actuar de inmediato; **amarillo** = falla grave, corregir lo antes posible; **blanco/azul/verde** = información de una función que opera normalmente.

## [electrico] Códigos de destello y pantalla SED: solo motores industriales (EMS S6 con COO) — no aplica al camión
- Aplica: motores industriales Scania DC9/DC12/DC16 con EMS S6 (PDE) e instrumentación industrial. **NO aplica al camión P450.**
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://til.scania.com/groups/opm_pub/documents/opm/mdaw/njg2/~edisp/opm_0000366_01.pdf (Scania EMS Instrumentation 1 588 955, 2008; copia local "Scania - EMS Instrumentation codigos motor.pdf", págs. 8-11 y 24-25)

- Este PDF local describe el panel analógico industrial. El interruptor S53 a la izquierda (EMS) o a la derecha (COO) durante ≥1 s emite códigos de destello en la lámpara W21: **destello largo (~1 s) = decenas y corto (0,3 s) = unidades**. Memoria vacía = un destello largo de ~4 s.
- Borrado: llave en OFF → mantener el interruptor hacia el lado del sistema → dar contacto manteniendo 3 s. Solo borra los códigos pasivos.
- Ejemplos (EMS S6): 11 sobrerrégimen (>3.000 rpm); 12/13 sensor de rpm 1/2; 14 sensor de temperatura de refrigerante; 16 sensor de presión de carga; 18 sensor de presión de aceite; 33 tensión de batería; 51-58 electroválvula de la bomba-inyector PDE de los cilindros 1-8; 94 parada por alta temperatura de refrigerante.
- Sirve **solo** para grupos electrógenos y bombas industriales Scania. **En el camión NTG los códigos se leen en IVD o con SDP3/SWS.**

## [electrico] Estructura de los códigos DM1 (SPN + FMI) que emiten las ECU Scania
- Aplica: Scania DC09/DC13/DC16 (EMS J1939); válido para leer DM1 con un escáner J1939 en el P450
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (Scania Installation Manual "Fault codes DM1" 03:10 Issue 6.0, 2016, págs. 3-11; copia local en _Descargados oficiales 2026-09/Scania)

- Los códigos que se generan en la red CAN se envían en el **mensaje DM1**. Cada código = **SPN** (qué parámetro o componente) + **FMI** (modo de falla).
- FMI: 0/1 = fuera de rango alto/bajo (condición real), 2 = errático, 3/4 = voltaje alto/bajo (corto a + / a masa), 5/6 = corriente baja/alta (abierto/a masa), 7 = mecánico, 9 = tasa de actualización (CAN), 12 = componente defectuoso, 13 = calibración, 19 = dato de red con error.
- La lista completa de SPN con descripción está en `codigos/scania.json` (86 SPN y 22 FMI).
- Regla práctica: un FMI 3, 4, 5 o 6 apunta a **cableado o conector** antes que al sensor. Un FMI 0, 1 o 15-18 apunta a la **condición física real** (presión, temperatura o nivel).

## [transmision] Opticruise: modos C (embrague) y L (limp home), y modos de manejo
- Aplica: Scania Opticruise, nueva generación (GRSO905R en el P450 chileno)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/www/market/uk/about-us/brochures/truck/brochure/brochure-scania-next-gen-quick-guide.pdf (Quick Guide, sección Opticruise / Performance modes)

- Selector: R, N y D. Palanca hacia el conductor = subir marcha, hacia afuera = bajar. Posición M manual o A automático. En el display se ven la marcha actual y la siguiente.
- **Modo C (Clutch mode)**: se activa **automáticamente cuando se detectan ciertas fallas** y no se puede seleccionar manualmente. Significa que hay una falla de caja o embrague: leer códigos TMS/GMS.
- **Modo L (Limp home)**: modo de emergencia que "requiere manejo especial". Hay una falla más grave y el camión debe llevarse al taller.
- **Modo m (maniobra)**: para maniobrar y enganchar remolques.
- Modos de desempeño: Standard, Power, Economy y **Off-road**, este último para caminos con pendiente y mala superficie, útil en faena.

## [transmision] Opticruise GRSO905R: calibración y códigos — qué se puede hacer sin licencia
- Aplica: Scania GRSO905R Opticruise (12+2, overdrive, con retardador)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial (ficha) / experiencia_campo (síntomas)
- Fuente: https://fimaj.cl/wp-content/uploads/2025/06/FICHA-TECNICA-CAMION-SCANIA-P450B-6X4-XT.pdf ; https://www.heavymachineryclub.com/scania-opticruise-problems/

- El P450 chileno usa la **GRSO905R**: Opticruise de 12+2 marchas, overdrive y retardador R3500.
- La **calibración del embrague y de la caja** y la lista de códigos de la unidad de caja (TMS/GMS) **requieren licencia: SDP3/SWS**. No hay procedimiento público de calibración.
- Causas frecuentes según fuentes de campo (confiabilidad baja): desgaste del embrague, falla de actuadores de cambio, **baja presión de aire**, calibración inestable y fallas de comunicación de sensores. Síntomas: cambios lentos o bruscos y "caza" de marchas.
- En faena: antes de condenar la caja, verificar la presión de aire y las fugas (APS), la tensión de batería, y los conectores del actuador de caja por agua o barro.

## [transmision] Recall Australia REC-006566: pasador espiral de la horquilla de cambios (cajas G25-G38)
- Aplica: Scania PGRS 2024-2026 con cajas de la familia **G25-G38** (Australia). **Verificar si aplica a la GRSO905R: probablemente no, porque es de otra familia de caja.**
- Tipo: boletin_recall
- Confiabilidad: oficial
- Fuente: https://www.vehiclerecalls.gov.au/recalls/rec-006566 (REC-006566, Scania Australia, "Scania PGRS 2024 - 2026")

- Defecto: **el pasador espiral de la horquilla de cambios puede soltarse** y provocar una falla interna de la transmisión. Riesgo de **movimiento no intencional del vehículo**.
- Alcance informado en prensa: 965 unidades PGRS con cajas G25-38 más 278 unidades P/G/R/S 2024-2025 (fuente secundaria: https://www.yourlifechoices.com.au/government/over-1000-scania-trucks-recalled-in-australia-over-tiny-pin-that-could-cause-big-problems/).
- Acción: consultar a Scania Chile, **con el VIN de cada uno de los 7 camiones**, si tienen campañas abiertas. En Brasil (Senacon) no se encontró un recall público de Scania para 2024-2026 en esta búsqueda.

## [postratamiento] Componentes SCR y designaciones Scania: sensores NOx, temperaturas y dosificador
- Aplica: Scania DC09/DC13/DC16 con SCR (manual de instalación industrial; el camión usa la misma tecnología SCR, pero las posiciones pueden diferir)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/industrial-and-genset/september-2018/Industrial-and-Genset-Exhaust-gas-aftertreatment-Issue-16.pdf (Scania Installation manual 01:07 Issue 17, "Exhaust gas aftertreatment", págs. 4-5 y 18)

- Componentes: catalizador de oxidación, (DPF en Stage V/Euro 6), evaporador/catalizador de hidrólisis, catalizador SCR, estanque de reductor calefaccionado por refrigerante, dosificador **V117**, sensores NOx **T131** (entrada) y **T115** (salida) con su unidad de control, y sensores de temperatura de escape **T4010, T4012 y T113**.
- Hay 2 sensores NOx, cada uno con su propia unidad de control. **Los sensores NOx y sus unidades no deben pintarse, y sus cables no deben empalmarse.**
- **Temperatura ambiente máxima en las unidades de control de los sensores NOx: 90 °C.** Si se superan, se dañan. Revisar que no les llegue calor radiante del escape.
- El sensor NOx T115 se daña con humedad: debe ir inclinado y protegido del agua. Relevante para los camiones de riego.
- Torque del sensor de temperatura de escape: ver la pág. 32 del mismo manual.

## [postratamiento] AdBlue (ARLA 32 / DEF): concentración ISO 22241 y cuidado de conectores
- Aplica: Scania con SCR (Euro 5 y Euro 6)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/industrial-and-genset/september-2018/Industrial-and-Genset-Exhaust-gas-aftertreatment-Issue-16.pdf (01:07 Issue 17, pág. 3)

- El reductor según **ISO 22241** contiene **32,5 % en peso de urea**, con límites de **31,8 a 33,2 %**.
- **El reductor es muy corrosivo.** Solo pueden usarse tubos y acoples resistentes a la urea. Los derrames se lavan con agua tibia.
- **Si el AdBlue entra en conectores o cables eléctricos, esos conectores y cables deben reemplazarse**, no solo limpiarse. Es causa típica de fallas intermitentes del sensor NOx y del dosificador.
- Para lubricar juntas del SCR solo sirven agua jabonosa o agua destilada con 3 % de urea. Otros lubricantes obstruyen los componentes.
- Límite de vibración de los componentes SCR no montados en el motor: 3,0 g entre 8 y 500 Hz.

## [postratamiento] Códigos OBD de NOx: SPN 4090, 4094, 4095, 4096 y 4225 (qué significa cada uno)
- Aplica: Scania DC13 con SCR (DM1 J1939)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (Fault codes DM1 Issue 6.0, págs. 9-10)

| SPN | Significado (límite de NOx excedido por...) | Primera revisión |
|---|---|---|
| 4090 | causa raíz desconocida | otros códigos SCR activos y sensores NOx (SPN 3216/3226) |
| 4094 | calidad insuficiente de AdBlue | concentración del AdBlue (ISO 22241), contaminación o agua; SPN 3516/5841 |
| 4095 | dosificación interrumpida | bomba y dosificador (SPN 3361/4374/5435), línea obstruida o cristalizada, calefactores |
| 4096 | estanque de AdBlue vacío | nivel y sensor de nivel (SPN 1761) |
| 4225 | error en el sistema de control de NOx | cableado y alimentación de los sensores NOx y del controlador SCR |

Estos códigos llevan a la **limitación de par del sistema de inducción del SCR**. Los valores de derrateo del camión Euro 5 en Chile no están en fuentes públicas. Requiere licencia: TIS/SDP3.

## [postratamiento] Calefacción del AdBlue: estanque, líneas, bomba y dosificador (SPN 3363, 4341-4347, 5706, 5745)
- Aplica: Scania DC13 con SCR
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (págs. 9-11) ; https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/industrial-and-genset/september-2018/Industrial-and-Genset-Exhaust-gas-aftertreatment-Issue-16.pdf (pág. 4)

- El estanque y la bomba de reductor se calefaccionan con **mangueras de refrigerante del motor**. Además hay calefactores eléctricos de línea (1 a 4), de bomba y de la unidad dosificadora.
- SPN: 3363 calefactor del estanque; 4341/4343/4345/4347 calefactores de línea 1-4; 5706 calefactor de bomba; 5745 calefactor del dosificador.
- En Calama las noches bajo 0 °C pueden congelar el AdBlue. Con estos códigos, revisar el circuito eléctrico del calefactor (FMI 5 = abierto, 6 = corto) y las mangueras de refrigerante hacia el estanque.

## [postratamiento] Regeneración manual del filtro de partículas (solo camiones Euro 6 con DPF)
- Aplica: Scania P/G/R/S nueva generación con filtro de partículas (Euro 6). **El DC13 143 Euro 5 no tiene DPF.**
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/www/market/uk/about-us/brochures/truck/brochure/brochure-scania-next-gen-quick-guide.pdf (Quick Guide, "Particulate filter")

Avisos en el ICL:
- **Blanco**: el filtro empieza a llenarse. Manejar en carretera ayuda a la regeneración automática.
- **Amarillo**: el filtro está lleno. Hacer la regeneración manual lo antes posible.
- **Rojo**: el filtro está excesivamente lleno y puede dañarse. **Acudir a un taller Scania.** No regenerar manualmente.

Regeneración manual (con el motor en marcha y a temperatura normal):
1. Palanca en neutro.
2. Freno de estacionamiento aplicado.
3. Mantener presionado **2 segundos** el interruptor de regeneración.
4. Mantener el vehículo detenido hasta que termine.

**Advertencia:** los gases de escape se calientan mucho. Alejar personas y materiales de la salida del escape. En faena, **no regenerar junto a estanques de combustible ni en zonas con material inflamable** (aljibes).

## [postratamiento] Fallas de campo en SCR: sensor NOx, dosificador y calidad de AdBlue
- Aplica: Scania Euro 5/Euro 6 con SCR
- Tipo: falla_conocida
- Confiabilidad: experiencia_campo
- Fuente: https://www.heavymachineryclub.com/scania-scr-system-problems/ ; https://www.robiel.com/problemas-comuns-no-sistema-arla32-e-como-a-robiel-pode-ajudar-com-reparos-eficientes

- Varias fuentes de campo coinciden en que los **sensores NOx, los módulos dosificadores y la calidad del AdBlue** son las causas más frecuentes de derrateo en Scania con SCR.
- Un AdBlue de baja pureza genera subproductos que obstruyen la boquilla dosificadora y dañan los sensores. La contaminación con metales envenena el catalizador.
- Un sensor de presión de AdBlue defectuoso puede sobredosificar, lo que acelera la cristalización en el dosificador, o subdosificar, lo que deja el NOx alto.
- Antes de cambiar un sensor NOx, verificar la calidad del AdBlue con refractómetro (32,5 %, ver la ficha ISO 22241), los conectores (corrosión por urea) y los códigos asociados de dosificación.

## [electrico] Tensión de batería y carga: SPN 167/168 y arranque (SPN 677, 1675)
- Aplica: Scania DC13 EMS (DM1)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (págs. 4-7)

- **SPN 167**: tensión del sistema de carga en la salida del alternador. **SPN 168**: tensión de batería en la entrada de la ECU.
- **SPN 677**: relé del motor de arranque. **SPN 1675**: el arranque no puede realizarse por alguna razón (condiciones de arranque no cumplidas).
- **SPN 1485**: relé principal de la ECU del motor.
- Diagnóstico: si hay 168 FMI 4 (voltaje bajo) junto con fallas CAN en varias ECU, sospechar primero de las baterías, la masa o el bloque C41/C55 (ver la ficha del circuito de potencia) antes que de las ECU.

## [motor] Admisión y turbo en altura y con polvo: SPN 102, 105, 107, 108, 3563 y 5421
- Aplica: Scania DC13 EMS (DM1)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (págs. 4, 9 y 11)

- **SPN 107**: presión diferencial del filtro de aire. Mide la restricción por el filtro y la materia sólida acumulada. **Es el código clave en faena con polvo.**
- **SPN 108**: presión barométrica. En altura, la ECU compensa por la menor densidad del aire. Un sensor con falla altera la sobrealimentación.
- **SPN 102 / 3563**: presión manométrica y absoluta del múltiple. **SPN 105**: temperatura del aire de admisión. **SPN 5421**: actuador de la wastegate. **SPN 103**: velocidad del turbo.
- Si hay baja potencia con SPN 102 bajo rango, revisar fugas en las mangueras del intercooler, el filtro de aire (SPN 107) y el actuador de la wastegate.

## [combustible] Combustible: SPN 94, 97, 156, 174, 1239 e inyectores SPN 651-656
- Aplica: Scania DC13 XPI (EMS, DM1)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (págs. 4-6)

- **SPN 94**: presión de entrega de la bomba de alimentación (circuito de baja). Revisar filtros, prefiltro y aire en el sistema.
- **SPN 97**: agua en el combustible. Drenar el separador; es frecuente con diésel de mala calidad.
- **SPN 156**: presión del riel. **SPN 174**: temperatura del combustible. **SPN 1239**: fuga de combustible en el riel.
- **SPN 651-656**: inyector de los cilindros 1-6. Con FMI 5/6 revisar el arnés de inyectores bajo la tapa de balancines y el conector de la ECU.
- **SPN 1322-1328**: fallos de combustión (misfire) en varios cilindros o en los cilindros 1-6.

## [motor] Protección del motor: SPN 100, 110, 111, 1569, 1110 y 3607
- Aplica: Scania DC13 EMS (DM1)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.scania.com/content/dam/scanianoe/market/au/products-and-services/engines/electrical-system/Fault-codes-DM1_Issue-6.pdf (págs. 4-9)

- **SPN 100**: presión de aceite. **SPN 110**: temperatura de refrigerante. **SPN 111**: nivel de refrigerante. **SPN 98 y 175**: nivel y temperatura de aceite.
- **SPN 1569**: el par se redujo para proteger el motor (derrateo). **SPN 1110**: el sistema de protección detuvo el motor. **SPN 3607**: indicación de parada inmediata.
- Con FMI 1/18 (bajo rango) en SPN 100, **verificar la presión con un manómetro mecánico** antes de cambiar el sensor. Si es real, detener el motor.
- Operación con PTO: la lógica de emergencia de la carrocería puede detener el motor por baja presión de aceite o alta temperatura cuando la PTO EG está conectada (ver la ficha de parada de emergencia).

## [frenos] AEB y cámara frontal: condiciones de funcionamiento y calibración
- Aplica: Scania P/G/R/S nueva generación con AEB (el P450 chileno lo trae)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (Automatic Emergency Braking)

- AEB funciona **sobre 15 km/h**, con cámara frontal y sensor de distancia (radar). Se activa solo al dar contacto. El interruptor muestra **verde = activo** y **amarillo = desactivado**. El mismo interruptor (con resorte) lo reactiva.
- Se limita o se desactiva si el sensor de distancia o la cámara están **bloqueados o con falla**, si hay falla de frenos del camión o del remolque, si la suspensión neumática está muy fuera de la altura de marcha, o si se maneja de noche.
- "System malfunction" = AEB desactivado por falla del sensor de distancia. "Reduced functionality" = AEB limitado.
- **Después de cambiar el parabrisas hay que calibrar la cámara frontal.** Requiere herramienta Scania. En faena con polvo, mantener limpios la cámara y el radar.
- Manipular la señal de velocidad del vehículo puede hacer que AEB falle o se active mal.

## [frenos] Hill Hold: condiciones de funcionamiento
- Aplica: Scania P/G/R/S con Hill Hold (el P450 chileno lo trae)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (Hill Hold)

- Se activa con su interruptor, que queda encendido. Se pisa el freno, se oye un clic y se mantiene la presión. Si estaba activo al apagar, queda activo en el siguiente arranque.
- **No se activa si la presión de freno es demasiado baja o si el ABS estaba activo al final de la frenada.**
- Se suelta a los pocos segundos de soltar los pedales, con aviso sonoro y mensaje. **No usarlo en condiciones invernales.** Siempre aplicar el freno de estacionamiento antes de dejar el puesto.

## [general] Volteo de cabina (manual o eléctrico) antes de trabajar en el motor
- Aplica: Scania P/G/R/S nueva generación
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (Cab Tilting)

- Antes de voltear: motor apagado, freno de estacionamiento aplicado, palanca en neutro, cabina sin objetos sueltos, puertas cerradas y **paneles laterales de la parrilla abiertos**. Pendiente máxima del 10 %.
- Manual: válvula de la bomba en posición de volteo, bombear con la barra hasta que la cabina pase por su propio peso y siga hasta el ángulo máximo. **La válvula debe quedar en posición de bajada para circular.**
- Eléctrico: pulsar el interruptor de volteo y usar el **control remoto que está bajo la parrilla frontal** (botón de activación trasero + botón de volteo).
- **No trabajar bajo la cabina en posición intermedia.** Durante la última parte de la bajada la cabina cae libre.

## [tren_rodaje] Tuercas de rueda: 600 Nm y reapriete a los 100 km
- Aplica: Scania P/G/R/S nueva generación
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (Wheel change)

- **Torque de las tuercas de rueda: 600 Nm**, en la secuencia de apriete del manual. **Reapretar a 600 Nm después de unos 100 km.**
- No usar llaves de impacto tipo volante. Limpiar las superficies de contacto con cepillo de acero, porque la pintura gruesa, el óxido o la suciedad aflojan las tuercas. Recolocar la rueda en su posición marcada.
- Antes de cambiar una rueda del eje de arrastre (tag): **cortar el contacto y el cortacorriente**.

## [general] Tacómetro: franjas de régimen y advertencia de turbo al apagar
- Aplica: Scania P/G/R/S nueva generación
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/trucks/en/instructions/drivers-manual.html (Instruments for vehicle information; EG Power Take-off)

- Tacómetro: **blanco** de 0 a 2.000 rpm y de 2.200 a 2.400 rpm; **azul** de 2.000 a 2.400 rpm, donde el freno auxiliar del motor es más efectivo; **rojo** sobre 2.400 rpm, con riesgo de daño al motor.
- El retardador trabaja mejor sobre 1.800 rpm (Quick Guide).
- **Después de conducir, dejar el motor en ralentí ~1 minuto antes de apagarlo**, para no dañar el turbo. Especialmente después de bombear con PTO.

## [general] Documentos del Truck Bodybuilder (TBB) que requieren login
- Aplica: Scania P/G/R/S
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (referencias TBB)

Requieren login en til.scania.com / truckbodybuilder.scania.com (Microsoft login de Scania; se pide a Scania Chile como carrocero o cliente):
- bwm_0001083_01: arnés cabina-bastidor
- bwm_0001046_01: central eléctrica de carrocería P9, **con los fusibles F1-F12**
- bwm_0001157_01: central de chasis P11
- bwm_0001038_01: alimentación y masas
- bwm_0001079_01 y bwm_0001119_01: BCI
- bwm_0001044_01: preparación para plataforma trasera
- "Power take-off data sheet"

Con esos documentos se completaría la tabla de amperajes de P9 y P11.

## [electrico] Balizas, luces laterales y alimentación en el techo
- Aplica: Scania P/G/R/S (desde 2017-03-03 para C450)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf (págs. 4-6)

- Luces laterales adicionales (vehículos desde 2017-03-03): conectores **C450-1 y C450-2** en los largueros. **Señal/+24 V en la posición 7 u 8 y masa en la 16.**
- Las luces laterales adicionales también pueden alimentarse desde **C489 posición 13** en la consola de carrocería, vía C494 y el arnés de extensión.
- Preparación para baliza 1330B: arnés al techo (3024A) e interruptor de fábrica.
- Y-cable para luces traseras adicionales o toma de 7 pines: P/N **1858746**. No sobrecargar los fusibles del vehículo.

## [general] Fallas de campo frecuentes en la flota Scania con SCR: lista de chequeo rápida
- Aplica: Scania P450 DC13 SCR en faena minera (polvo, altura, frío nocturno, ralentí largo con PTO)
- Tipo: falla_conocida
- Confiabilidad: experiencia_campo
- Fuente: https://www.heavymachineryclub.com/scania-scr-system-problems/ ; https://www.heavymachineryclub.com/scania-opticruise-problems/ ; https://bodybuilder.scania.com/content/dam/bodybuilder/tbb-files/uk/quick-reference-guides/Bodybuilder_Quick_Reference_Guide_-_Electrical.pdf

Chequeo ordenado, antes de usar la herramienta Scania:
1. Tensión de batería y masas: larguero izquierdo, G46/G47 y nunca G32.
2. Agua, barro o urea en los conectores DIN C486-C488 y en los conectores SCR.
3. Filtro de aire (SPN 107) y fugas del intercooler (SPN 102).
4. Calidad y nivel del AdBlue y calefacción (SPN 1761, 3516, 3363).
5. Presión de aire para Opticruise y PTO EG (mínimo 5 bar para acoplar la EG).
6. Fusibles de P9 y P11.F para los equipos de carrocería.

La confiabilidad es experiencia_campo porque la lista combina fuentes oficiales con coincidencias de foros y talleres.
