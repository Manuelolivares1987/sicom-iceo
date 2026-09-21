# Renault Trucks C440 6x4 — base de conocimiento para diagnóstico

Unidad de la flota: Renault Trucks C440 6x4 2024 (VIN VF630N358PD000096, fabricado en
Francia, motor DTI 13 N° 2296470, caja Optidriver), aljibe de combustible, Calama.

Fuente base (abreviada RT-VIN): Guía del conductor oficial Renault Trucks **generada para
el VIN VF630N358PD000096** en https://driverguide.renault-trucks.com (idioma español).
El portal identifica este VIN como "C Cab 2.5m", clase 23, montaje 16-05-2023, vehículo
rígido 6x4, motor 13 L (variante "ENG-VE13"). API del portal:
`https://rt.webbase.cloud/driverguide/chassiNfo?chassi=VF630N358PD000096`.
PDF local (338 págs., dividido en dos por tamaño):
`_Investigacion web 2026-09-19/Renault/Renault C440 VF630N358PD000096 - Guia del conductor por VIN parte 1 pags 1-185 (es).pdf`
y `... parte 2 pags 186-338 (es).pdf` (pág. N del original = pág. N−185 de la parte 2).
Las páginas citadas abajo son las del PDF original completo.

---

## [general] Identificación del Renault C440 de la flota y relación con la plataforma Volvo
- Aplica: Renault Trucks C440 6x4 (VIN VF630N358PD000096), DTI 13, Optidriver
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://rt.webbase.cloud/driverguide/chassiNfo?chassi=VF630N358PD000096 ; https://rt.webbase.cloud/driverguide/getTopicByChassi?chassi=VF630N358PD000096&l=es&topic=43909 ("Características del vehículo seleccionado")

- Portal oficial: modelo "C Cab 2.5m", clase de producto 23, fecha de montaje/especificación 16-05-2023 (timestamp 1684191600), no es vehículo demo.
- Características del VIN: vehículo rígido, **motor de 13 litros (variante ENG-VE13)**, 6x4, aviso de cambio de carril (LSS-DW), climatización automática.
- Inferencia técnica (no declarada textualmente por Renault): la guía Renault usa el mismo sistema documental y los mismos códigos de variante que Volvo (ENG-VE13 = motor 13 L del grupo Volvo; la sección de soldadura y fusibles tiene la misma numeración F01-F91 que el Volvo FMX). Por eso los códigos SPN-FMI del motor Volvo D13 son una referencia útil (ver `codigos/renault.json`, confiabilidad tecnica_terceros) — validar siempre con la herramienta de diagnóstico Renault.
- La guía por VIN incluye la sección "Gases de escape, motores Euro V" (pág. 292-293) → el camión probablemente es Euro V (SCR con AdBlue). Confirmar en la placa de emisiones.

## [general] Cómo generar la guía del conductor de un Renault por VIN
- Aplica: Renault Trucks T/C/K/D (portal global)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com

- Ingresar el VIN completo (17 caracteres) en el portal; la guía queda filtrada para el equipamiento real del camión (incluye su tabla de fusibles).
- Botón de descarga PDF: el portal genera el archivo (en esta investigación: 338 páginas, 64 MB, español). El enlace de descarga es temporal; volver a generarlo si expira.

## [fusibles_reles] Renault C: ubicación de fusibles, acceso y testigo de fusible/relé defectuoso
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 56, 279-281)

- La central de fusibles está en el **tablero de instrumentos** (ítem 7 "Fusibles" del puesto de conducción, pág. 56).
- Acceso: quitar la alfombra del tablero → girar las **3 tuercas 1/4 de vuelta** → retirar la tapa. Al cerrar, girar de nuevo las 3 tuercas 1/4 de vuelta. Cambiar fusibles con la **pinza** incluida (pág. 280).
- Si un fusible falla, aparecen un **indicador luminoso de fusible/relé** y mensajes informativos en el visualizador; cambiar el fusible y, si continúa, ir a servicio Renault Trucks.
- Reemplazar siempre por un fusible idéntico; revisar componentes y cableado antes de reponer. **Los fusibles identificados como "no utilizado" pueden usarse para la reparación**; además hay fusibles de repuesto F92-F98 en la misma caja.
- La calcomanía/cuadro de la caja de distribución eléctrica está en pág. 281 (imagen).

## [fusibles_reles] Renault C: fusibles F01 a F30 (caja de distribución eléctrica)
- Aplica: Renault Trucks C440 VIN VF630N358PD000096
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 282-283)

| F | A | Asignación |
|---|---|---|
| F01 | 10 | Tomas de 12 V |
| F02 | — | No utilizado |
| F03 | 10 | Predisposición alimentación televisor |
| F04 | 15 | Toma de remolque |
| F05 | 15 | Predisposiciones para carrocero en el chasis |
| F06 | 5 | Alimentación de interruptores para carroceros |
| F07 | 30 | Unidad de conexión carroceros |
| F08 | 20 | Unidad de conexión carroceros |
| F09 | — | No utilizado |
| F10 | 15 | Toma de 24 V en estante superior |
| F11 | 15 | Predisposición de luces desplazadas |
| F12 | 15 | Girofaros (balizas) |
| F13 | 10 | Asiento calefactado / Horómetro / Bloqueo alcoholímetro (según equipamiento) |
| F14 | — | No utilizado |
| F15 | 10 | Predisposición luces de personalización del techo |
| F16 | 10 | Predisposición luces de personalización del techo |
| F17 | — | No utilizado |
| F18 | 3 | Calculador de gestión de la visualización |
| F19 | 15 | **Alimentación de caja de carrocero** (equivalente al BBM Volvo) |
| F20 | 20 | Módulo puerta acompañante (mando puerta, alzavidrios, retrovisor) |
| F21 | 3 | Pantalla secundaria |
| F22 | 5 | Cortinas parasol |
| F23 | 3 | Tacógrafo |
| F24 | 3 | Visualizador (instrumento) |
| F25 | 3 | Caja de peaje |
| F26 | — | No utilizado |
| F27 | 10 | **Calculador de gestión del vehículo** |
| F28 | 20 | **Calculador de gestión del vehículo** |
| F29 | 10 | Antihielo retrovisor derecho |
| F30 | 10 | Antihielo retrovisor izquierdo |
Nota de lectura del PDF: la tabla se imprime "Asignación – F – Amp."; se verificó la alineación comparando con la central equivalente del Volvo FMX (F12 balizas, F19 carrocero 15 A, F27/F28 calculador vehículo coinciden).

## [fusibles_reles] Renault C: fusibles F31 a F60
- Aplica: Renault Trucks C440 VIN VF630N358PD000096
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 283-284)

| F | A | Asignación |
|---|---|---|
| F31 | 5 | Calculador de asistencia a la conducción |
| F32 | 10 | Gestión de aire centralizada (APM) |
| F33 | 3 | No utilizado |
| F34 | 5 | Faro de trabajo |
| F35, F36 | — | No utilizado |
| F37 | 20 | **Calculador EBS** |
| F38 | 20 | Panel de climatización y calefacción autónoma |
| F39 | 20 | Conducto de calentamiento del combustible |
| F40 | 3 | Tacógrafo |
| F41 | 15 | **Calculador de control del motor** |
| F42 | 15 | Calculador de control del motor |
| F43 | 10 | Calentador del filtro de combustible |
| F44 | 10 | Calculador de control del motor |
| F45 | 30 | Basculamiento de cabina |
| F46 | 20 | Toma ABS/EBS de remolque |
| F47, F48 | — | No utilizado |
| F49 | 50 | Predisposición horno microondas |
| F50 | 30 | Predisposición cafetera |
| F51 | 20 | Motor limpiaparabrisas |
| F52 | 15 | Escotilla de techo |
| F53 | 5 | Accesorios (cámara de marcha atrás) |
| F54 | — | No utilizado |
| F55 | 3 | Alarma |
| F56 | 10 | Alimentación principal carrocero en estante superior |
| F57 | 10 | Iluminación interior de cabina |
| F58 | 20 | Predisposiciones carrocero (compuerta o grúa) |
| F59 | 15 | Transformador 24 V/12 V en estante superior |
| F60 | 15 | Transformador 24 V/12 V en tablero |

## [fusibles_reles] Renault C: fusibles F61 a F98 (incluye fusibles de repuesto)
- Aplica: Renault Trucks C440 VIN VF630N358PD000096
- Tipo: fusibles_reles
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 284-285)

| F | A | Asignación |
|---|---|---|
| F61 | 20 | Módulo puerta conductor (mando puerta, alzavidrios, retrovisor) |
| F62 | 5 | **Toma de diagnóstico (OBD)** |
| F63 | 10 | **Calculador de gestión de la cabina** |
| F64 | 15 | Toma 24 V en tablero |
| F65 | 15 | Toma 24 V literas |
| F66 | 3 | Gestión embarcada (telemática) |
| F67 | 15 | Encendedor |
| F68 | 15 | **Calculador de gestión del vehículo** |
| F69 | 15 | Calefacción autónoma |
| F70 | 15 | **Alimentación del calculador de la caja de cambios automatizada (Optidriver)** |
| F71 | 15 | Bomba lavafaros |
| F72 | — | No utilizado |
| F73 | 30 | Unidad de conexión carroceros |
| F74 | 20 | Unidad de conexión carroceros |
| F75 | 10 | Predisposición nevera |
| F76 | 15 | Iluminación interior remolque |
| F77-F79 | — | No utilizado |
| F80 | 3 | Control remoto de la litera |
| F81 | 5 | No utilizado |
| F82-F84 | — | No utilizado |
| F85 | 3 | Gestión embarcada |
| F86, F87 | — | No utilizado |
| F88 | 5 | Bloqueo con alcoholímetro |
| F89 | — | No utilizado |
| F90 | 15 | No utilizado |
| F91 | 10 | Gestión embarcada |
| F92 / F93 / F94 / F95 / F96 / F97 / F98 | 50 / 30 / 20 / 15 / 10 / 5 / 3 | **Fusibles de sustitución (repuesto)** |
- Diagnóstico rápido: sin comunicación con herramienta → F62; Optidriver sin respuesta → F70; motor sin calculador → F41/F42/F44; equipo del carrocero (bomba de trasvasije, válvulas) sin alimentación → F05-F08, F19, F56, F58, F73-F74.
- La guía Renault no publica tabla de relés para este VIN.

## [lectura_codigos_tablero] Renault C: leer códigos de falla en el visualizador (menú Vehículo > Diagnóstico)
- Aplica: Renault Trucks C/T/K con visualizador multifunción (VIN VF630N358PD000096)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 100-102)

Ruta: visualizador multifunción → apartado **Vehículo** → **C - Diagnóstico**. Opciones:
- **Antiarranque**: muestra el código dinámico que pide la Techline (soporte Renault) y permite ingresar el código que ella entrega; indica la validez del PIN; se cierra a los 3 s.
- **Referencias calculadores**: lista de unidades de control (calculadores) y sus versiones de software.
- **Fallos**: "Enumera los códigos de fallo presentes".
Otros ítems del apartado Vehículo: A - Mantenimiento; B - Purga de agua en el combustible; D - Descarga de actualizaciones de software; E - Prueba del visualizador; F - Ajuste ralentí motor; G - Modo banco de rodillos.
- Si un menú aparece sombreado, no se cumplen sus condiciones. Sin acción durante ~30 s el visualizador vuelve a la pantalla favorita.
- Formato de los códigos: la guía no lo detalla; en la plataforma del grupo los códigos de motor son SPN-FMI (J1939) — ver tabla FMI en `volvo.md` y `codigos/renault.json`.

## [lectura_codigos_tablero] Renault C: página de inicio y visualización de defectos al dar contacto
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, pág. 88)

- Al dar contacto aparece una página de inicio que dura 30 s tras el arranque. Un **mensaje + indicador luminoso** señalan un posible fallo (sustitución de fusible, mantenimiento necesario, agua en combustible, etc.).
- **Si hay varios defectos, hay que resolver primero los dos primeros para ver los siguientes.**
- La página muestra además: km totales, tiempo en la actividad seleccionada y **nivel de aceite del motor**.
- Autoprueba del visualizador: al dar contacto se hace una comprobación automática de 4 s (pág. 191).

## [lectura_codigos_tablero] Renault C: testigos de falla relevantes para diagnóstico en el cuadro
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 79-82)

Testigos listados en el cuadro de mandos (según equipamiento): parada del motor; avería del equipamiento del motor; **defecto en fusible o relé**; alerta de mantenimiento; **agua en el combustible**; anomalía de alimentación de combustible; reserva de combustible; **reserva mínima de AdBlue**; temperatura del refrigerante; nivel bajo de refrigerante; **anomalía del captador de nivel de refrigerante**; **colmatado del filtro de aire**; regeneración del filtro de partículas; **anomalía del sistema de descontaminación**; temperatura de escape alta; defecto del antirrobo electrónico; ASR desactivado (banco de rodillos); ralentizador; **tomas de fuerza en la caja** (marcas 1-2-3 según TdF enclavadas); **defecto de toma de fuerza en la caja**; velocidad máx./mín. de TdF; bloqueos de diferencial; anomalía de basculamiento de cabina; desgaste y calentamiento de embrague (caja automatizada).
- Colmatado de filtro de aire y agua en combustible son alertas frecuentes en faena con polvo (Calama).

## [procedimiento_diagnostico] Renault C: menú Mantenimiento (datos de desgaste) y purga de agua del prefiltro
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 100-101)

- Vehículo → A - Mantenimiento: correas del motor, filtro de aire, refrigerante, APM, aceite de caja, aceite de motor, forros de freno, último cambio de frenos, **embrague**, escobillas del alternador, escobillas del motor de arranque, aceite de dirección, visita reglamentaria, verificación de tacógrafo.
- Si se cambian las baterías por otras distintas a las de origen, seleccionar tipo "Otro" (se desactivan parcialmente las funciones de gestión de baterías para evitar datos erróneos).
- Vehículo → B - Purga de agua en el combustible (desde el prefiltro). Condiciones: agua detectada en el prefiltro, vehículo parado, **motor parado**, contacto dado, freno de estacionamiento aplicado → seleccionar "Sí"; la pantalla muestra el progreso. Poner bandeja y hacerlo en lugar adecuado.

## [motor] Renault C: ajuste del ralentí desde el visualizador (menú F)
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, pág. 103)

- Condiciones: vehículo parado, motor en ralentí, acelerador sin pisar, freno de estacionamiento apretado, **pedal de freno presionado durante el ajuste**.
- Vehículo → F - Ajuste ralentí motor: reducir / aumentar / validar. Si el ajuste se hace demasiado rápido no se podrá validar.

## [implemento] Renault C: ralentí acelerado y régimen automático con toma de fuerza
- Aplica: Renault Trucks C con tomas de fuerza (VIN VF630N358PD000096)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 195-196)

- Ralentí acelerado (vehículo parado, freno de estacionamiento, caja en punto muerto): mando (1) activa; mando (2) A/B sube/baja progresivo o por pasos; pulsar (+/-) memoriza el régimen actual al pisar el acelerador; mando (4) recupera el **régimen nominal de 900 rpm**. No pisar el acelerador durante el uso.
- **Con TdF enclavadas, al pulsar el mando (3) el motor va automáticamente a un valor de consigna (900, 1.000, 1.100 y 1.200 rpm respectivamente).** El régimen se define por configuración **entre 600 y 2.550 rpm**; régimen y condiciones de entrada/salida se modifican con la herramienta Renault Trucks.
- Las condiciones de desactivación del ralentí acelerado son configurables en servicio Renault.

## [implemento] Renault C: uso de la toma de fuerza en parada (bomba de trasvasije) y N1/N2
- Aplica: Renault Trucks C con Optidriver y TdF (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 270-271)

Condiciones para enclavar en parada: **régimen del motor < 1.000 rpm**, anillo del selector en **N** (punto muerto), **freno de estacionamiento activado** → pulsar el mando (1); el indicador (4) queda encendido.
Ajuste de régimen: pulsar (1) y ajustar con (2).
Aumento de régimen de la TdF: palanca en N, elegir **N1 o N2** con el selector del volante (+ = máxima, − = mínima); el display muestra N1/N2. **N2 ≈ 30 % más régimen de TdF que N1.**
- Diagnóstico de "TdF no enclava": verificar las tres condiciones (rpm < 1.000, N, freno de estacionamiento) y el testigo "defecto en toma de fuerza en la caja".

## [implemento] Renault C: toma de fuerza en marcha y regímenes de salida por tipo de TdF
- Aplica: Renault Trucks C con Optidriver y TdF (VIN VF630N358PD000096)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 272-273, 257)

- En marcha: no puede haber otra TdF de caja enclavada; con el vehículo parado elegir la marcha (solo las 6 primeras). **Marchas 1, 3, 5 = velocidad mínima de TdF; 2, 4, 6 = máxima.** Una vez en movimiento ya no se puede cambiar de marcha; la regulación de régimen no está disponible (se usa el acelerador).
- Desacople: pulsar el interruptor **más de 0,5 s**. Algunas condiciones se modifican con el software de carroceros Renault Trucks.
- Régimen de la TdF para **1.000 rpm de motor**:
| TdF | Baja (N, 1ª, 3ª, 5ª) | Alta (N, 2ª, 4ª, 6ª) |
|---|---|---|
| S81 | 705/880 rpm | 897/1.100 rpm |
| S84 | 910/1.140 rpm | 1.159/1.420 rpm |
| PTRD-D1D | 600/760 rpm | 770/950 rpm |
- Con caja Optidriver XTENDED se puede usar la TdF con marchas ultralentas y otras según parametrización (pág. 257).

## [transmision] Optidriver: componentes y uso del selector
- Aplica: Renault Trucks C con Optidriver (VIN VF630N358PD000096)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 244-247)

- 5 componentes: (1) visualizador de marcha, (2) **selector con calculador integrado**, (3) **módulo de control de velocidades con calculador integrado** (sobre la caja), (4) **dispositivo de control del embrague**, (5) caja mecánica de garras. La caja tiene bomba de aceite (ver capítulo de remolque antes de remolcar).
- Selector: anillo (2) N/D (D engrana la marcha de arranque); anillo (3) C/R = modo maniobras (C: 1ª adelante en manual; R: R1); palanca + / − corrige marchas; tirar hacia el conductor = alterna automático/manual permanente ("Auto"/"Manu").
- Marcha atrás: R1 (preferente), R2, R3 (rápida, no para maniobras). R1→R2 en movimiento sobre ~1.000 rpm. Pitido al cambiar de sentido.
- Al cortar el contacto la caja pasa sola a neutro. Si se abre la puerta con D seleccionado, aparece aviso + alarma pidiendo pasar a N.

## [transmision] Optidriver: marcha de arranque, protección del embrague y anomalías
- Aplica: Renault Trucks C con Optidriver (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 248-251)

- Marcha de arranque: automática según carga y pendiente; corregible **máximo 2 marchas**; la **5ª es la máxima seleccionable (6ª si se usa TdF)**. Una marcha demasiado alta desgasta prematuramente el embrague.
- Protección del embrague: testigo + mensaje **"CALENTAMIENTO EMBRAGUE"** → limitar el patinaje. Si aparece en movimiento, seguir circulando para enfriar; si aparece detenido, poner el motor en ralentí y dejar el anillo en D hasta que se apague. Nunca sostener el camión en subida con el acelerador.
- Anomalías: **aparecen líneas (– –) en el indicador de marcha cuando la marcha actual tiene error, no está disponible o está fuera de valores normales** → leer códigos (Vehículo > Diagnóstico > Fallos).
- Banco de rodillos (2 ruedas): N→D y acelerar a fondo; subidas de dos en dos a ~1.700 rpm, bajadas a ~1.100 rpm; sale al girar ruedas delanteras o 10 s después de cortar contacto.
- Bajo **−20 °C**: dejar el motor 10 min en marcha para que la caja llegue a temperatura.
- El sistema no engrana marchas que causen sobrerrégimen; en bajadas fuertes con retardador puede mantener la marcha y avisar en el display.

## [postratamiento] Renault C: AdBlue — llenado mínimo tras vaciado, reducción de par y códigos no borrables
- Aplica: Renault Trucks C con SCR (VIN VF630N358PD000096)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 34-35, 182-184, 266)

- Usar solo AdBlue de distribución comercial (norma DIN 70070); nunca mezclar ni reutilizar el AdBlue drenado; dejar aire sobre el nivel; recipientes y bombas limpios y exclusivos.
- **Si el depósito se vació, cargar al menos 7 litros** para evitar daño del sistema. Llenar siempre al máximo.
- Indicador por segmentos; al apagarse el último se enciende la reserva y el visualizador muestra la distancia recorrida desde la reserva. Con depósito vacío: testigo "Información" + mensaje.
- Si el sistema detecta **descontaminación insuficiente**: mensaje de que el motor no está descontaminado y que **se aplicará reducción de par en la próxima parada del motor**; desde el siguiente arranque **el defecto queda memorizado y no puede borrarse** (consultable por autoridades).
- **Tras rellenar AdBlue después de una reducción de par: dar contacto y esperar 15 s con el vehículo inmóvil para inhibir la reducción.**
- Al apagar el motor se hace automáticamente un ciclo de vaciado del circuito de AdBlue (se oye la bomba): no cortar el interruptor general inmediatamente.
- Salpicaduras en conectores: si el conector está puesto, enjuagar con agua; si estaba desconectado, **cambiar el conector** (pág. 292).

## [postratamiento] Renault C: catalizador Euro V — temperatura y tiempos antes de intervenir
- Aplica: Renault Trucks C Euro V (sección incluida en la guía del VIN VF630N358PD000096)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 292-293)

- El catalizador sube de temperatura y se enfría más lento que un silenciador: gases de escape muy calientes en marcha y estacionado con motor en marcha. No estacionar sobre aceite, gasóleo o pasto seco (riesgo en faena).
- Vapor blanco al arrancar en frío (hasta 5 °C) es normal.
- **Esperar aprox. 2 horas antes de intervenir el catalizador** para que baje a ~50 °C.
- Combustible: gasóleo EN 590; con filtros de partículas/EGR usar diésel <10 ppm de azufre (pág. 289).

## [electrico] Renault C: interruptor general, modos START/STOP y bajo consumo
- Aplica: Renault Trucks C con botón START/STOP y control remoto (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, págs. 18, 36, 188-190, 266)

- Interruptor general (maestro) detrás de la cabina: girar la manilla 1/4 de vuelta → modo "Estacionado", módulos en bajo consumo; los intermitentes indican que está abierto. **No es un cortacorriente de batería.** Esperar **30 s** tras cortar el contacto antes de abrirlo. **Nunca abrirlo con el motor en marcha** (daña alternador y electrónica).
- Bajo consumo automático: 12 h con la llave en cabina, 2 h sin llave (configurable en taller).
- Arranque: START/STOP solo funciona si detecta el control remoto (llave) en cabina y el interruptor general está cerrado. Falla del transpondedor → mensaje y no arranca (ver Antiarranque en menú Diagnóstico).
- Modos: parada/habitabilidad → accesorios → contacto → arranque (pie en freno + START, o pulsación >3 s).
- **El motor pasa a "contacto" (se apaga) si se cala, si lo apaga la unidad del carrocero, o si supera el tiempo de ralentí de la parada automática** — relevante cuando la bomba se detiene "sola".
- Sin control remoto detectado: pasa a parada tras 10 min en contacto o 1 h en accesorios.

## [especificacion] Renault C: baterías — carga externa y descarga
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, pág. 303)

- El alternador carga como máximo ~90 %. Cargar externamente **al menos cada tres semanas**, aunque el camión se use; con equipos que consumen con el motor apagado, cargar con más frecuencia.
- Evitar descargas profundas (daño permanente). Agregar consumidores no previstos requiere revisar la especificación de baterías.

## [frenos] Renault C: APM (gestión de aire) — alerta de consumo excesivo de aire
- Aplica: Renault Trucks C (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, pág. 293)

- Si el visualizador muestra alerta de **consumo excesivo de aire**, comprobar presencia de agua en los depósitos de aire; si hay agua, revisar el sistema (secador/APM) en servicio Renault Trucks.
- El intervalo de mantenimiento del APM figura en Vehículo > Mantenimiento > APM.

## [electrico] Renault C: actualización de software desde el visualizador
- Aplica: Renault Trucks C conectado (VIN VF630N358PD000096)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://driverguide.renault-trucks.com (RT-VIN, pág. 102)

- Mensaje de actualización disponible: tiempo estimado 1-60 min. Estacionar en plano, detener el motor, dejar en modo contacto hasta terminar, control remoto dentro de la cabina. Menú Mantenimiento → "Actualización de software".
- Si aparece "La actualización ha fallado. El camión no puede conducirse por razones de seguridad" o la pantalla queda negra: falla crítica → servicio de disponibilidad (tel. +800 777 500 00).
- Implicancia para diagnóstico: un comportamiento nuevo tras una actualización puede deberse a cambio de parámetros/software.

## [implemento] Renault Trucks: documentación de carrocero (body builder) — acceso restringido
- Aplica: Renault Trucks C/T/K
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://bodybuilder.renault-trucks.com/ (portal "ikros", requiere cuenta)

- Las instrucciones de carrocero Renault (conectores de la "unidad de conexión carroceros", parámetros de TdF, esquemas) están en el portal bodybuilder.renault-trucks.com, que exige inicio de sesión/registro. No se descargaron.
- Mientras tanto: los fusibles de carrocero de la guía por VIN (F05-F08, F19, F56, F58, F73-F74) y la documentación NA del BBM Volvo (ver `volvo.md`, fichas BBM) sirven como orientación de arquitectura, no como pinout del Renault.
