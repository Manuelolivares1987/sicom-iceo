# Metodología de diagnóstico universal — camiones pesados diésel 24 V (flota Pillado)

Base de conocimiento genérica (no específica de marca) para el Copiloto Técnico. Cada ficha es autocontenida.
Investigación: 2026-09-19. Los valores numéricos provienen SOLO de la fuente citada en cada ficha; cuando el
fabricante (Mercedes, Mack, Volvo, Renault, Scania, Allison) publica un valor propio, ese valor prevalece.
Documentación OEM detallada requiere licencia: XENTRY/WIS (Mercedes), Premium Tech Tool/Impact (Volvo, Mack, Renault),
SDP3/SWS (Scania), Allison DOC.

---

## [electrico] SAE J1939: qué es un DTC (SPN + FMI + OC + CM)
- Aplica: Todos los camiones con red J1939 (Mercedes Actros/Axor/Atego/Accelo electrónicos, Mack MP8, Volvo D8/D13, Renault DTI13, Scania DC13), Euro 3 a Euro 6
- Tipo: arquitectura_can
- Confiabilidad: tecnica_terceros
- Fuente: https://www.csselectronics.com/pages/j1939-73-dm1-diagnostic-message-dtc (CSS Electronics — J1939-73 Diagnostics Explained)

Un código de falla J1939 (DTC) tiene 4 partes:
| Campo | Tamaño | Qué significa |
|---|---|---|
| SPN (Suspect Parameter Number) | 19 bits | QUÉ componente/parámetro falla (p. ej. SPN 110 = temperatura de refrigerante) |
| FMI (Failure Mode Identifier) | 5 bits (0-31) | CÓMO falla (voltaje alto, circuito abierto, dato fuera de rango…) |
| OC (Occurrence Count) | 7 bits | Cuántas veces pasó de inactivo a activo (máx. 126) |
| CM (Conversion Method) | 1 bit | 0 = versión 4 / estándar actual |

Además cada DTC viaja con la dirección de origen (Source Address) del módulo que lo informa: el mismo SPN puede venir del motor, de la caja o del ABS. Para el mecánico: anotar siempre SPN, FMI, OC y el módulo que lo reporta. Un OC alto con código inactivo = falla intermitente (buscar conectores, roces, masas).

## [electrico] Tabla completa de FMI 0-31 (J1939 / J1587)
- Aplica: Todos los ECUs J1939 y J1587/J1708 (FMI es común a ambos protocolos)
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fcarusa.com/TechSupport/KB/introduction-mid-pid-sid-fmi (FCAR Tech USA — The introduction of MID, PID, SID & FMI); FMI 0 confirmado en https://www.csselectronics.com/pages/j1939-73-dm1-diagnostic-message-dtc

| FMI | Significado (SAE) | Qué pensar primero |
|---|---|---|
| 0 | Dato válido pero SOBRE el rango normal — nivel más severo | Condición real (sobretemperatura, sobrepresión). Verificar con instrumento físico |
| 1 | Dato válido pero BAJO el rango normal — nivel más severo | Condición real (presión de aceite baja, nivel bajo) |
| 2 | Dato errático, intermitente o incorrecto (racionalidad) | Conector intermitente, señal no plausible vs. otro sensor |
| 3 | Voltaje sobre lo normal, o en corto a fuente alta | Señal en corto a +5 V/+24 V, o masa del sensor abierta |
| 4 | Voltaje bajo lo normal, o en corto a fuente baja (masa) | Señal a masa, referencia 5 V caída |
| 5 | Corriente bajo lo normal, o circuito abierto | Actuador/bobina abierta, cable cortado |
| 6 | Corriente sobre lo normal, o circuito a masa | Bobina en corto, salida a masa |
| 7 | Sistema mecánico no responde o fuera de ajuste | Actuador trabado (EGR, VGT, válvula), mecánico |
| 8 | Frecuencia, ancho de pulso o período anormal | Sensores de frecuencia/PWM |
| 9 | Tasa de actualización anormal | Mensaje CAN que no llega (módulo caído, red) |
| 10 | Tasa de cambio anormal | Señal que cambia demasiado rápido (salto, falso contacto) |
| 11 | Causa raíz no identificable | Leer códigos acompañantes |
| 12 | Dispositivo o componente inteligente defectuoso | Módulo/sensor inteligente con falla interna |
| 13 | Fuera de calibración | Falta aprendizaje/calibración tras reemplazo |
| 14 | Instrucciones especiales | Ver procedimiento del fabricante |
| 15 | Dato válido sobre rango — nivel menos severo | Aviso temprano |
| 16 | Dato válido sobre rango — nivel moderadamente severo | Advertencia |
| 17 | Dato válido bajo rango — nivel menos severo | Aviso temprano |
| 18 | Dato válido bajo rango — nivel moderadamente severo | Advertencia |
| 19 | Dato recibido de la red con error | El dato vino por CAN marcado como erróneo por el módulo emisor |
| 20 | Dato derivó alto | Sensor descalibrado (deriva) |
| 21 | Dato derivó bajo | Sensor descalibrado (deriva) |
| 22-30 | Reservados SAE | — |
| 31 | Condición existe | Código de "estado" (p. ej. derate, regeneración incompleta); buscar la causa en otros códigos |

Nota: la fuente FCAR transcribe FMI 4 como "shorted to high source" por error tipográfico; la definición SAE correcta es "shorted to low source" (ver p. ej. la tabla Cummins https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf, códigos FMI 4 "Voltage below normal, or shorted to low source").
Regla práctica: FMI 3/4/5/6 = problema ELÉCTRICO (arnés, conector, sensor). FMI 0/1/15-18 = el sensor mide algo real (verificar la condición física antes de cambiar el sensor). FMI 9/19 = problema de RED o del módulo emisor.

## [electrico] Mensajes de diagnóstico DM1, DM2, DM3 y DM11
- Aplica: Todos los ECUs J1939
- Tipo: arquitectura_can
- Confiabilidad: tecnica_terceros
- Fuente: https://www.csselectronics.com/pages/j1939-73-dm1-diagnostic-message-dtc (CSS Electronics — J1939-73 Diagnostics Explained)

| Mensaje | PGN | Contenido | Uso en taller |
|---|---|---|---|
| DM1 | 65226 | Códigos ACTIVOS + estado de lámparas | Se transmite cada 1 s (1 Hz) y al cambiar de estado. Con 0-1 DTC es una trama; con 2 o más se envía en multipaquete (BAM) |
| DM2 | 65227 | Códigos PREVIAMENTE ACTIVOS (históricos) desde el último borrado | Misma estructura que DM1; clave para intermitentes |
| DM3 | — | Borra los códigos previamente activos | Se solicita con la herramienta |
| DM11 | — | Borra los códigos activos y toda la información de diagnóstico (activos, históricos, freeze frame, contadores) | No borrar antes de anotar todo |

Buenas prácticas: (1) leer DM1 y DM2 de TODOS los módulos antes de borrar; (2) anotar OC y freeze frame; (3) tras la reparación, borrar y hacer prueba de ruta para ver si el código vuelve a DM1.

## [electrico] Lámparas del DM1: MIL, RSL, AWL y PL
- Aplica: Todos los ECUs J1939
- Tipo: lectura_codigos_tablero
- Confiabilidad: tecnica_terceros
- Fuente: https://www.csselectronics.com/pages/j1939-73-dm1-diagnostic-message-dtc (CSS Electronics — J1939-73 Diagnostics Explained)

Los 2 primeros bytes del DM1 informan el estado de 4 lámparas, 2 bits cada una, más 2 bits de parpadeo:
| Lámpara | SPN | Significado operativo |
|---|---|---|
| PL — Protect Lamp | 987 | Problema no electrónico relacionado a protección del sistema (p. ej. postratamiento/emisiones según OEM) |
| AWL — Amber Warning Lamp | 624 | Falla que no requiere detener el vehículo de inmediato |
| RSL — Red Stop Lamp | 623 | Falla grave: detener el vehículo en forma segura |
| MIL — Malfunction Indicator Lamp | 1213 | Falla relacionada con emisiones |

Parpadeo: valor 0 = parpadeo lento (1 Hz), valor 1 = parpadeo rápido (2 Hz). Para el copiloto: si el técnico reporta "luz roja de STOP", priorizar seguridad (detener, revisar presión de aceite, temperatura, nivel de refrigerante) antes de diagnosticar.

## [electrico] Conector de diagnóstico Deutsch 9 pines (J1939-13): pinout
- Aplica: Mack GU, Volvo VM/FMX, camiones con conector 9 pines norteamericano; muchos equipos off-road. (Mercedes, Scania y Renault europeos usan normalmente conector OBD 16 pines o conector propio: verificar en el vehículo)
- Tipo: pinout_conector
- Confiabilidad: tecnica_terceros
- Fuente: https://copperhilltech.com/blog/sae-j193913-offboard-diagnostic-connector-deutsch-hd1091939-/ (Copperhill — SAE J1939/13 Off-Board Diagnostic Connector Deutsch HD10-9-1939)

| Pin | Señal |
|---|---|
| A | Batería (−) / masa |
| B | Batería (+) |
| C | CAN_H (J1939 principal) |
| D | CAN_L (J1939 principal) |
| E | Malla/blindaje CAN (shield) |
| F | J1708 (+) |
| G | J1708 (−) |
| H | Uso OEM propietario o CAN_H de bus de implemento |
| J | Uso OEM propietario o CAN_L de bus de implemento |

Tipo 1 = carcasa NEGRA (red a 250 kbit/s). Tipo 2 = carcasa VERDE, introducida para impedir conectar herramientas incompatibles (red a 500 kbit/s) — ver ficha siguiente. Medición rápida sin herramienta: con batería DESCONECTADA, C-D ≈ 60 Ω (dos terminadores de 120 Ω en paralelo).

## [electrico] Conector 9 pines Tipo 1 (negro) vs Tipo 2 (verde) y velocidad 250k/500k
- Aplica: Camiones norteamericanos 2014+ (Mack, Volvo NA) y adaptadores de diagnóstico
- Tipo: pinout_conector
- Confiabilidad: tecnica_terceros
- Fuente: https://www.csselectronics.com/pages/j1939-explained-simple-intro-tutorial (CSS Electronics — J1939 Explained); https://copperhilltech.com/blog/sae-j193913-offboard-diagnostic-connector-deutsch-hd1091939-/

- J1939 estándar usa 250 kbit/s; recientemente se soporta 500 kbit/s (J1939-14).
- El conector negro (Tipo 1) es el original; el verde (Tipo 2) comenzó a introducirse hacia 2013-2016 y está diseñado para que un adaptador Tipo 1 (250k) no pueda enchufarse físicamente en una red de 500k.
- Algunos vehículos exponen una red secundaria en pines F/G o H/J (CSS Electronics).
- Síntoma típico: "el escáner no comunica" con un adaptador incorrecto o forzado. Verificar color del conector y usar el adaptador/cable correcto; no forzar un conector negro en uno verde.

## [electrico] J1708/J1587: MID, PID, SID — tabla de MID comunes
- Aplica: Camiones con red J1708/J1587 (Volvo/Mack hasta aprox. EPA 2010 conviven J1587 + J1939; Allison y ABS antiguos). Euro 3 típicamente
- Tipo: arquitectura_can
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fcarusa.com/TechSupport/KB/introduction-mid-pid-sid-fmi (FCAR Tech USA — The introduction of MID, PID, SID & FMI)

Formato de código J1587: MID (módulo) + PID (parámetro) o SID (subsistema) + FMI. Nunca hay PID y SID a la vez. Los PID van de 0 a 511. Ejemplo: MID 128 SID 6 = motor, inyector N° 6.
| MID | Módulo |
|---|---|
| 128 | Motor (EECU/ECM) |
| 130 | Unidad de control de transmisión (TECU/TCM) |
| 136 | Frenos ABS |
| 140 | Cuadro de instrumentos |
| 142 | Comunicaciones satelitales |
| 144 | ECU del vehículo (VECU) |
| 146 | Climatización |
| 206 | Radio |
| 216 | Módulo de control de luces |
| 219 | VORAD / crucero adaptativo |
| 232 | Airbag |
| 249 | Módulo del carrocero (Body Builder) |
| 250 | Módulo del volante |

J1708 viaja en los pines F (+) y G (−) del conector 9 pines (Copperhill, ficha de pinout). Los FMI son los mismos de la tabla J1939.

## [electrico] Red CAN: niveles de tensión recesivo/dominante
- Aplica: Toda red CAN de alta velocidad ISO 11898 (J1939)
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.ti.com/lit/an/sloa101b/sloa101b.pdf (Texas Instruments SLOA101B — Introduction to the Controller Area Network, pág. 7)

- Estado recesivo (bus en reposo): CAN_H y CAN_L polarizados pasivamente a ≈2,5 V.
- Estado dominante: CAN_H sube ≈1 V a ≈3,5 V y CAN_L baja ≈1 V a ≈1,5 V → diferencial típico de 2 V.
- Con multímetro (que promedia), en una red con tráfico se ve CAN_H algo sobre 2,5 V y CAN_L algo bajo 2,5 V. Rangos de referencia con multímetro: CAN_H 2,5-3,5 V y CAN_L 1,5-2,5 V (https://jcom1939.com/sae-j1939-network-wiring-and-connectors/).
- Según ISO 11898 no se debe poner la resistencia terminal dentro de un nodo desmontable, porque al desconectarlo la red pierde terminación (TI SLOA101B pág. 7).

## [electrico] Red CAN: medición de terminación 60 Ω / 120 Ω / 40 Ω
- Aplica: Toda red J1939 (backbone del camión, bus de carrocería, bus de implemento)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.kvaser.com/developer-blog/how-to-test-your-can-termination-works-correctly/ (Kvaser — How to test if your CAN termination works correctly); https://jcom1939.com/sae-j1939-network-wiring-and-connectors/ (JCOM1939 — SAE J1939 Network Wiring and Connectors)

Procedimiento (con TODO apagado y batería desconectada; medir resistencia con la red energizada da lecturas falsas):
1. Medir entre CAN_H y CAN_L (conector 9 pines: pines C y D).
2. Interpretar:
| Lectura | Diagnóstico |
|---|---|
| ≈60 Ω | Correcto: dos terminadores de 120 Ω en paralelo |
| ≈120 Ω | Falta un terminador (o hay un tramo abierto entre el conector y un extremo) |
| ≈40 Ω | Hay un tercer terminador de 120 Ω (120/3 = 40 Ω): típico tras instalar GPS/telemetría o carrocería con terminador propio |
| < 40 Ω hasta ~0 Ω | Corto entre CAN_H y CAN_L en el arnés o transceptor dañado |
| Muy alto / abierto | Ambos terminadores ausentes o backbone cortado |
3. Kvaser agrega: CAN_H a masa y CAN_L a masa sin comunicación ≈10 kΩ (orden de magnitud de la polarización interna de los nodos); lecturas muy bajas indican corto a masa.
Límites físicos J1939 (JCOM1939): backbone máx. 40 m, derivaciones (stubs) ≤1 m, máx. 30 ECUs, terminadores 120 Ω 1 % 1/4 W en los extremos del backbone.

## [electrico] Red CAN: criterio Eaton para prueba en conector de diagnóstico (50-70 Ω y 4,5-5,5 V)
- Aplica: Cualquier camión con conector 9 pines (procedimiento publicado por Eaton para cajas AMT; el criterio de medición es aplicable al backbone J1939)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://productinfo.serviceranger4.com/books/TRTS0960/lang/en-us/section/TS0960FC115 (Eaton TRTS0960 — Fault Code 115: Primary Data Link J1939A)

- Resistencia en conector 9 vías, pin C a pin D (o F a G si el módulo está en la red secundaria): esperado 50-70 Ω.
- Tensión: medir pin C a pin A (masa) y pin D a pin A con llave ON; la SUMA de ambas lecturas debe estar entre 4,5 y 5,5 V.
- Si el fallo desaparece al desconectar el conector de enlace secundario, el problema está en esa rama.
- Inspeccionar el conector del módulo sospechoso por contaminación/daño y repetir la medición de resistencia en el conector del módulo (esperado 50-70 Ω) antes de reemplazar un módulo.

## [electrico] Red CAN: cómo aislar un módulo que "tira" la red
- Aplica: Toda red J1939; síntomas: múltiples códigos FMI 9/19 de varios módulos, tablero que se apaga, escáner que no comunica
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.kvaser.com/developer-blog/how-to-test-your-can-termination-works-correctly/ ; https://productinfo.serviceranger4.com/books/TRTS0960/lang/en-us/section/TS0960FC115 ; https://www.ti.com/lit/an/sloa101b/sloa101b.pdf

Pasos (de más probable a menos):
1. Batería desconectada: medir C-D en el conector 9 pines. Clasificar según la ficha de terminación (60/120/40/0 Ω).
2. Si hay corto (≈0 Ω) o <40 Ω: desconectar los módulos UNO A UNO (empezar por los agregados: telemetría/GPS, tacógrafo, módulo de carrocería, luego ABS, caja, cabina) midiendo cada vez. El módulo cuya desconexión devuelve la lectura a ≈60 Ω es el culpable (transceptor dañado o conector con agua).
3. Si la resistencia es correcta pero la red no funciona: llave ON y medir CAN_H y CAN_L a masa. Recesivo ≈2,5 V ambos (TI SLOA101B pág. 7). CAN_H o CAN_L ≈0 V = corto a masa; cerca de tensión de batería = corto a positivo. Desconectar módulos uno a uno hasta que los niveles vuelvan.
4. Revisar el blindaje (pin E) y masas de los módulos; en minería, revisar conectores de chasis expuestos a lavado a presión y barro.
5. Recordar que un módulo sin alimentación NO tira la red, pero genera FMI 9 en los demás (su mensaje no llega).

## [electrico] J1939: longitud de derivaciones (stubs) y por qué importan
- Aplica: Instalaciones de accesorios (GPS, telemetría, sensores de carrocería) conectadas al backbone
- Tipo: arquitectura_can
- Confiabilidad: oficial
- Fuente: https://www.ti.com/lit/an/slla270/slla270.pdf (Texas Instruments SLLA270 — Controller Area Network Physical Layer Requirements, secc. 4.8)

- Las derivaciones no están terminadas y generan reflexiones de señal. TI indica que la norma recomienda derivación máxima de 0,3 m a 1 Mbit/s; a menor velocidad se toleran mayores longitudes (J1939 a 250 kbit/s especifica ≤1 m según JCOM1939: https://jcom1939.com/sae-j1939-network-wiring-and-connectors/).
- Error típico de instaladores de GPS: "pinchar" la red con cables largos no trenzados o agregar un terminador → errores intermitentes de comunicación. Revisar instalaciones recientes cuando aparecen FMI 9/19 nuevos.

## [electrico] Prueba de caída de tensión (voltage drop): valores admisibles por elemento
- Aplica: Circuitos eléctricos de 12 y 24 V (iluminación, sensores, alimentación de módulos, masas)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fluke.com/en-us/learn/blog/automotive/electrical-automotive-troubleshooting (Fluke — Diagnosing Voltage Drops: Electrical Automotive Troubleshooting)

Principio: la caída de tensión se mide con el circuito FUNCIONANDO (con corriente circulando), con el multímetro en paralelo sobre el tramo a probar. Una resistencia que no se ve con el óhmetro aparece bajo carga.
Máximos orientativos Fluke:
| Elemento | Caída máxima |
|---|---|
| Conexión (terminal, empalme) | 0,00 V |
| Cable o conductor | 0,20 V |
| Interruptor | 0,30 V |
| Masa | 0,10 V |
| Cables e interruptores de circuitos de computador (baja corriente) | 0,10 V |
Usar multímetro de alta impedancia (10 MΩ) en circuitos de baja corriente. Prevalecen los valores del fabricante cuando existan. Para arranque y carga de 24 V usar las fichas Delco Remy.

## [electrico] Circuito de arranque 24 V: caída de tensión en cables de batería (Delco Remy)
- Aplica: Motores de partida pesados 37MT/40MT/41MT/42MT/50MT y equivalentes en sistemas de 24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — Diagnostic Procedures Manual for Starters and Alternators, pág. 12-13, párr. 3-7 a 3-9)

Prueba de cables (después de verificar que las baterías están buenas y bornes limpios):
1. Usar pila de carbón de 24 V, o convertir temporalmente a 12 V dejando conectada una sola batería (pero usando la corriente especificada para 24 V). Reconectar a 24 V al terminar.
2. Carga: 500 A en sistema de 12 V / 250 A en sistema de 24 V.
3. Medir caída en cable positivo (V4: borne BAT del solenoide a positivo de batería) y en cable negativo (V5: masa del motor de partida a negativo de batería). Medir en el terminal, no en la pinza de la pila.
4. Pérdida total V3 = V4 + V5. Máximo: 12 V con 37/40/41/42MT = 0,500 V; 12 V con 50MT = 0,400 V; 24 V con 37/40/41/42/50MT = 1,000 V.
5. Con baterías en dos ubicaciones: probar cada juego por separado con 250 A (125 A en 24 V), mismos límites (párr. 3-10/3-11).

## [electrico] Circuito de arranque 24 V: solenoide, relé magnético y cableado de mando (Delco Remy)
- Aplica: Motores de partida pesados con relé/interruptor magnético (IMS o separado), 24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — Diagnostic Procedures Manual, pág. 15-17, párr. 3-14 a 3-20)

| Prueba | Carga (24 V) | Límite 12 V | Límite 24 V |
|---|---|---|---|
| Circuito del solenoide (V6) | 60 A (100 A en 12 V) | 1,0 V | 2,0 V |
| Cableado total del solenoide (V9 + V10) | 60 A | 0,8 V | 1,8 V |
| Contactos del interruptor magnético (V11) | 60 A | 0,2 V | 0,2 V |
| Circuito de mando del relé (V13 vs batería V12) | llave ON + botón | dentro de 1,0 V | dentro de 2,0 V |
Si V13 está más de 2,0 V (24 V) bajo la tensión de batería, mover la punta y medir sucesivamente: masa del relé (V14), cable botón-relé (V15), botón (V16), cable botón-llave (V17), llave (V18), cable llave-BAT del solenoide (V19); reparar el tramo fuera de límite.
Prueba de frío: si con puente entre los dos bornes grandes del relé magnético el motor arranca bien, reemplazar el relé magnético (párr. 3-22).

## [electrico] Tensión disponible de arranque y diferencia entre baterías (Delco Remy)
- Aplica: Sistemas de 24 V con 2 o 4 baterías de 12 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — Diagnostic Procedures Manual, pág. 17-18, párr. 3-23 y 3-24)

- Medir entre borne BAT del solenoide y masa del motor de partida mientras se da arranque: si es 9,0 V o menos (18 V o menos en 24 V), revisar cables de interconexión entre baterías.
- Medir cada batería durante el arranque: si la diferencia entre dos baterías del mismo cajón es mayor a 0,5 V, o algún cable/conexión se calienta, revisar o reemplazar cables de interconexión.
- Antes de cambiar el motor de partida: inspeccionar piñón y corona girando el motor con barra (corona dañada → reemplazar corona; probablemente también el piñón).
- En pruebas de baterías de electrolito líquido: diferencia de densidad entre celdas mayor a 0,050 → reemplazar la batería (pág. 11).

## [electrico] Sistema de carga 24 V: caída de tensión y tensión máxima del alternador (Delco Remy)
- Aplica: Alternadores pesados en sistemas de 12/24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — Diagnostic Procedures Manual, pág. 18-20, párr. 3-26 a 3-32)

1. Prueba de cableado del alternador (motor detenido, pila de carbón en la salida del alternador a la corriente nominal del alternador): caída positiva V24 (salida alternador → positivo batería) + caída negativa V25 (masa alternador → negativo batería) = V23. Máximo: 12 V = 0,500 V; 24 V = 1,000 V.
2. Tensión de salida: con cargas apagadas y ralentí acelerado hasta que la tensión se estabilice 2 minutos, no debe superar 15,5 V (31 V en sistemas de 24 V).
3. Corriente de salida: pinza amperimétrica sobre TODOS los cables de salida, motor acelerado, pila de carbón hasta la máxima lectura. Reemplazar si no está dentro del 10 % de la corriente nominal (estampada en la carcasa). La mayoría de alternadores pesados tienen su nominal a 5000 rpm del alternador.
4. Si la salida es cero: remagnetizar el rotor puenteando momentáneamente positivo de batería al terminal R o I; si sigue en cero, reemplazar.

## [electrico] Prueba de rizado AC (ripple) del alternador — diodos
- Aplica: Alternadores de 12/24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fluke.com/en-us/learn/blog/digital-multimeters/how-to-test-alternator-ripple-voltage-with-a-multimeter (Fluke — How to test alternator ripple voltage with a multimeter)

1. Motor en ralentí 30 s con consumos encendidos (luces, climatización).
2. Multímetro en V AC, rango 600 mV (subir a 6 V si se sale de escala). Punta roja en B+ del alternador o positivo de batería; negra en negativo o masa.
3. Registrar en ralentí y luego a 2000-2500 rpm; opcional MIN/MAX para picos.
| Rizado AC | Interpretación (Fluke) |
|---|---|
| ≤ 50 mV (0,05 V) | Deseable |
| 0,05-0,10 V | Zona de precaución, vigilar |
| ≥ 0,30-0,50 V | Normalmente al menos un diodo o el estator fallado |
El rizado que aumenta con rpm o carga indica falla interna del alternador. Rizado alto provoca códigos erráticos en módulos y parpadeo de luces.

## [electrico] Consumo parásito (batería que se descarga con el camión detenido)
- Aplica: Camiones pesados con telemetría, tacógrafo, GPS y módulos que "duermen"
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fleetmaintenance.com/equipment/battery-and-electrical/article/55309049/electrical-system-load-testing-diagnosing-parasitic-draws-in-modern-commercial-vehicles (Fleet Maintenance — Diagnosing parasitic draws in modern commercial vehicles)

1. Batería cargada; cerrar puertas y dejar que los módulos entren en reposo (no interrumpir: cada apertura de puerta "despierta" módulos y reinicia la espera).
2. Conectar el amperímetro EN SERIE entre el borne negativo y el cable negativo desconectado (o pinza inductiva de baja corriente).
3. Consumo aceptable en vehículos nuevos: típicamente 50-80 mA (Fleet Maintenance), variable por vehículo y accesorios.
4. Si está alto: retirar fusibles uno a uno hasta que baje; el circuito que lo reduce es el sospechoso (típicos en flota minera: GPS/telemetría instalados por terceros, radios, luces de carrocería, relés pegados de PTO/bombas).
Nota: en camiones con cortacorriente general, verificar también el consumo con el cortacorriente abierto (debe ser prácticamente nulo salvo equipos cableados antes del corte).

## [electrico] Sensores de 3 hilos con referencia 5 V (presión, posición)
- Aplica: Sensores de presión de riel, boost, aceite, DPF ΔP, pedal acelerador en ECUs diésel
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://autoditex.com/page/common-rail-pressure-sensor-27-1.html (Autoditex — Common rail pressure sensor); https://cloreautomotive.com/troubleshooting-5v-reference-circuits/ (Clore Automotive — Troubleshooting 5V reference circuits)

- Tres hilos: +5 V de referencia desde el ECU, señal de salida y masa (retorno de sensor).
- Rango de salida del sensor de presión de riel: 0,5-4,5 V (Bosch, Delphi, Siemens) y 1,0-4,2 V (Denso) (Autoditex). Tensiones fuera de ese rango = el ECU lo interpreta como falla de circuito (FMI 3/4).
- La referencia se mide con llave ON, motor detenido: debe estar cerca de 5,0 V (Clore). Si está baja, desconectar uno a uno los sensores que comparten esa referencia mientras se mide; el que al desconectarse la recupera está en corto (Clore).
- La masa de sensor es una masa del ECU (no del chasis): medir caída de tensión en masa ≤0,10 V (Fluke, ficha de caída de tensión).

## [electrico] Sensores de 2 hilos pasivos: inductivos (velocidad) y termistores
- Aplica: Sensores de velocidad de rueda ABS, sensores inductivos de velocidad, sensores de temperatura NTC
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (Bendix SD-13-4869 — EC-60 ABS/ATC/ESP Controllers, pág. 27-28 "Speed Sensor Repair Tests")

Sensor inductivo (ejemplo Bendix, sensor de rueda ABS):
| Medición en conector del ECU | Valor esperado |
|---|---|
| Resistencia del sensor | 1500-2500 Ω |
| Sensor a tensión o a masa | Circuito abierto (sin continuidad) |
| Tensión de salida girando la rueda a ~0,5 rev/s | > 0,25 V AC |
- Medir en los pines del conector del ECU (así se prueba arnés + sensor), sondeando con cuidado para no abrir los terminales.
- El DTC del sensor se mantiene hasta ciclar la alimentación del ECU y circular sobre 15 mph (~24 km/h), o borrarlo con herramienta (Bendix).
Termistores NTC (temperatura): son de 2 hilos; la resistencia baja al subir la temperatura. Probar comparando la lectura del ECU con un termómetro, y la resistencia con la tabla del fabricante (no hay valor universal).

## [electrico] Sensores Hall (3 hilos, onda cuadrada) y señales PWM
- Aplica: Sensores de posición de cigüeñal/árbol de levas Hall, sensores de velocidad de salida, actuadores y sensores PWM
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.picoauto.com/library/automotive-guided-tests/sensors/crankshaft-position/AGT-012-crankshaft-position-hall-effect-running/ (Pico Technology — Crankshaft position Hall effect, running)

- El sensor Hall necesita alimentación y masa para su electrónica interna (a diferencia del inductivo, que genera su propia señal).
- Entrega una onda CUADRADA que conmuta entre 0 V y 5 V con frecuencia proporcional a la velocidad (Pico).
- Prueba: osciloscopio en el cable de señal, motor en ralentí; buscar flancos limpios y conmutación completa 0-5 V. Un multímetro sólo muestra un promedio (útil para ver que "algo" conmuta, no para la calidad de la señal).
- Fallas típicas: contaminación metálica en la punta del sensor, entrehierro excesivo, rueda fónica dañada, circuito de alimentación abierto (Pico).
- Señales PWM (actuadores VGT/EGR, ventiladores): usar osciloscopio o multímetro con función de ciclo de trabajo (%) y frecuencia; comparar el % comandado por el ECU (datos en vivo) con el medido.

## [electrico] Backprobing y cuidado de conectores Deutsch/AMP sellados
- Aplica: Conectores sellados de motor, chasis y ABS (Deutsch DT/DTM/HD, AMP/TE)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (Bendix SD-13-4869, pág. 28: "Probe the connector carefully so that the terminals are not damaged"); https://www.fluke.com/en-us/learn/blog/automotive/electrical-automotive-troubleshooting (Fluke: back-probe de masas de computador con el sistema operando)

- Medir por la parte trasera del conector (backprobe) con puntas finas SIN perforar el aislamiento ni el sello del cable: una perforación permite entrada de agua/polvo y corrosión que avanza por el cable.
- Medir por el frente del terminal hembra sólo con adaptadores/puntas del tamaño correcto; una punta gruesa abre el terminal y crea un falso contacto intermitente nuevo.
- Nunca perforar cables CAN ni de sensores de 5 V.
- Tras intervenir, verificar que los sellos de cable y los tapones de cavidades vacías estén en su lugar; en ambiente minero con lavado a presión, un tapón faltante es causa frecuente de corrosión.

## [electrico] Corrosión y humedad en conectores: patrón de fallas intermitentes
- Aplica: Toda la flota; especialmente conectores de chasis, ABS de ruedas, sensores de postratamiento y luces de carrocería expuestos a lavado, barro y polvo
- Tipo: falla_conocida
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fluke.com/en-us/learn/blog/automotive/electrical-automotive-troubleshooting (Fluke — caída de tensión en conexiones debe ser 0,00 V); https://cloreautomotive.com/troubleshooting-5v-reference-circuits/ (Clore — limpieza y ajuste de masas en casos de estudio)

- Síntomas: códigos FMI 2 (errático), FMI 3/4 que aparecen y desaparecen, OC alto en DM2, luces que parpadean.
- Prueba: caída de tensión bajo carga en la conexión (ideal 0,00 V según Fluke); wiggle test (mover arnés/conector con el parámetro en pantalla).
- Reparación: limpiar terminales, reemplazar terminales corroídos (no sólo "lijar"), reponer sellos, aplicar grasa dieléctrica sólo si el fabricante del conector lo permite, asegurar alivio de tensión del arnés.

## [electrico] Luces e indicadores intermitentes o "fantasmas": masas
- Aplica: Iluminación de cabina y carrocería, indicadores del tablero, módulos de carrocería 24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fluke.com/en-us/learn/blog/automotive/electrical-automotive-troubleshooting (Fluke — Diagnosing Voltage Drops); https://static.nhtsa.gov/odi/tsbs/2020/MC-10174571-0001.pdf (Kia Tech Tip 97-20-01TT Voltage Drop Testing Procedures, técnica general)

Árbol (de más probable a menos):
1. Encender el circuito (con carga real). Medir caída de tensión entre la masa de la lámpara/módulo y el negativo de batería: > 0,10 V indica masa deficiente (Fluke).
2. Revisar masas comunes de chasis-cabina y chasis-motor (trenzas de masa); una masa de cabina deficiente hace que varios circuitos "se alimenten" por otros caminos (luces que encienden débil al activar otra función).
3. Medir caída en el lado positivo (fusible, relé, interruptor ≤0,30 V según Fluke).
4. Revisar conectores de remolque/carrocería (agua, corrosión) y portalámparas.
5. Revisar rizado del alternador (> 0,30-0,50 V AC indica diodo fallado, ficha de ripple) si el parpadeo sigue las rpm.

## [electrico] Árbol: el motor NO gira (no da arranque)
- Aplica: Camiones pesados 24 V con motor de partida y relé magnético
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — Diagnostic Procedures Manual, secciones II-III)

Herramientas: multímetro digital (resolución 0,01 V), pinza amperimétrica, pila de carbón de 24 V (o una batería de 12 V para prueba temporal), escáner.
1. Seguridad y bloqueos: palanca en neutro, interruptor de neutro/embrague, bloqueo por PTO o por carrocería (algunos camiones impiden arranque con PTO o con cortacorriente abierto). Revisar cortacorriente general.
2. Baterías: tensión en reposo y prueba de carga (Delco Remy: carga de 1/2 CCA durante 15 s y comparar con tabla por temperatura).
3. ¿Hace "clic"? Medir en borne S del solenoide al dar arranque; si llega tensión y no gira → cables de potencia (prueba de caída: ≤1,000 V total en 24 V) o motor de partida.
4. ¿No hace clic? Circuito de mando: relé magnético, llave, botón, fusibles; tensión en la bobina del relé dentro de 2,0 V de la batería en 24 V.
5. Puente entre bornes grandes del relé magnético: si gira, el relé magnético está malo.
6. Revisar piñón y corona; motor trabado mecánicamente (hidrobloqueo por refrigerante/combustible en cilindros): girar a mano con barra antes de insistir.
7. Si el ECU bloquea el arranque: leer códigos (p. ej. inmovilizador, SPN 1675 FMI 31 protección de sobre-arranque — ver JSON j1939-generico).

## [motor] Árbol: el motor gira pero NO parte
- Aplica: Diésel common rail y bomba-inyector, Euro 3 a Euro 6
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (Diesel Laptops — DD15 fault codes: SPN 157 FMI 17 "Minimum Rail Pressure Not Achieved While Engine Cranking", SPN 94 FMI 1); https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (tensión de arranque ≥18 V en 24 V)

De más probable a menos:
1. Leer códigos y ver datos en vivo DURANTE el arranque: rpm de arranque, presión de riel real vs. deseada, tensión de batería.
2. Velocidad de arranque insuficiente: si la tensión en el motor de partida cae a 18 V o menos (24 V) revisar baterías y cables (Delco Remy). Un ECU puede no inyectar si no detecta rpm suficientes o sincronía cigüeñal/levas.
3. Combustible: nivel real del estanque (el indicador puede fallar), filtros tapados, aire en el sistema tras cambio de filtros o quedarse sin combustible, válvula de corte, combustible parafinado/contaminado. Código típico: presión mínima de riel no alcanzada en arranque (SPN 157 FMI 17 en DD15; SPN 5585 FMI 18 en Cummins).
4. Señal de posición: sin señal de cigüeñal o de levas (p. ej. SPN 636/723/190) el ECU no sincroniza. Verificar con escáner que se lean rpm durante el arranque.
5. Inmovilizador / alimentación del ECU: ECU sin alimentación o masa (no comunica con el escáner).
6. Admisión/escape: mariposa de admisión cerrada, freno de escape trabado cerrado, filtro de aire colapsado.
7. Mecánico: compresión baja, distribución.

## [motor] Árbol: el motor se apaga (en marcha o en ralentí)
- Aplica: Diésel electrónicos Euro 3 a Euro 6
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (Diesel Laptops — DD15: SPN 158 FMI 2 "Ignition Switch Not Plausible", SPN 168 FMI 9 "Battery Connection Lost", SPN 94 FMI 1); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins: SPN 100, 110, 111 con lámpara roja)

1. ¿Protección del motor? Si hubo lámpara roja (RSL) antes del apagado: presión de aceite (SPN 100), temperatura (SPN 110), nivel de refrigerante (SPN 111). Muchas calibraciones apagan el motor por protección. Verificar la condición física.
2. Alimentación del ECU: interrupción de la línea de llave o de batería al ECU (DD15: SPN 158 FMI 2, SPN 168 FMI 9). Revisar relé principal, fusibles, bornes de batería y masas; caída de tensión bajo carga.
3. Combustible: filtro tapado/aire (SPN 94 FMI 1 presión de baja), estanque con toma obstruida, combustible con agua (SPN 97).
4. Señal de rpm: pérdida de señal de cigüeñal/levas (SPN 190 FMI 2, SPN 636) por conector o sensor.
5. Temporizador de ralentí (idle shutdown) programado en el ECU: típico en camiones con PTO/ralentí largo si no está parametrizado el modo PTO.
6. Válvula de corte de combustible / relé de parada del carrocero (algunos equipos de carrocería detienen el motor ante alarmas).

## [motor] Árbol: pérdida de potencia / modo protección (derate)
- Aplica: Diésel turbo Euro 3 a Euro 6, operación en altura
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4 Fault Codes: SPN 1569 FMI 31 "Engine Protection Torque Derate", SPN 102 FMI 18, SPN 1127 FMI 7, SPN 103, SPN 5246 FMI 0); https://www.donaldson.com/content/dam/donaldson/engine-hydraulics-bulk/catalogs/air-intake/north-america/F110027-ENG/accessories/Air-Intake-Accessories.pdf (Donaldson, restricción de admisión)

1. Leer códigos: un derate normalmente tiene un código "consecuencia" (SPN 1569 FMI 31) y un código "causa". Buscar la causa.
2. Causas de emisiones: SCR/DEF (SPN 5246 inducción, 3364 calidad, 1761 nivel, 4364 eficiencia), DPF (3719 hollín, 3251 ΔP). Ver fichas de postratamiento.
3. Causas de protección: temperatura de refrigerante/aceite/admisión alta (SPN 110/175/105), presión de aceite, sobrevelocidad de turbo en altura (SPN 103 FMI 15/16).
4. Sin códigos: revisar restricción de admisión (indicador de filtro de aire), fugas de aire de carga (boost bajo, SPN 102 FMI 18), restricción de escape (DPF, freno de escape), filtros de combustible (presión de baja), calidad del combustible.
5. Datos en vivo con carga (prueba de ruta o dinamómetro): boost real vs. deseado, presión de riel real vs. deseada, porcentaje de carga, temperatura de admisión.
6. Altura: la menor densidad del aire reduce la potencia disponible; algunas calibraciones limitan torque en altura por diseño (no es falla). Ver ficha de altura.

## [motor] Árbol: humo negro
- Aplica: Motores diésel turboalimentados
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://highwayandheavyparts.com/blog/diesel-engine-smoke-colors/ (Highway and Heavy Parts — Diesel Engine Smoke Colors)

Causa general: exceso de combustible o falta de aire para una combustión completa. Un diésel moderno en buen estado opera con poco o nada de humo visible.
De más probable a menos (orden sugerido para faena con polvo y altura):
1. Filtro de aire restringido → revisar indicador de restricción (Donaldson: limpiar/cambiar al llegar a la marca roja).
2. Fugas de aire de carga (mangueras, abrazaderas, intercooler roto) → boost bajo (SPN 102 FMI 18).
3. Turbo dañado o VGT/wastegate sin control.
4. EGR con falla (válvula pegada abierta).
5. Inyectores con fuga/goteo o pulverización deficiente → prueba de contribución de cilindros.
6. Compresión baja.
En altura, el humo negro bajo carga aumenta por menor densidad del aire; comparar con camiones iguales operando en el mismo lugar.

## [motor] Árbol: humo blanco
- Aplica: Motores diésel
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://highwayandheavyparts.com/blog/diesel-engine-smoke-colors/ (Highway and Heavy Parts — Diesel Engine Smoke Colors)

Humo blanco = combustible no quemado o refrigerante entrando a la cámara. Una bocanada breve en arranque en frío puede ser normal; si persiste, investigar.
1. ¿Olor a combustible o a refrigerante (dulce)? ¿Baja el nivel de refrigerante? → junta de culata, enfriador de EGR con fuga, culata fisurada (SPN 111 nivel de refrigerante).
2. Combustible con agua (SPN 97) → drenar separador.
3. Inyectores defectuosos / sincronización incorrecta.
4. Compresión baja (anillos, válvulas).
5. En Euro 5/6: vapor de agua normal en frío y humo blanco durante/después de regeneración; distinguir por olor y persistencia.

## [motor] Árbol: humo azul
- Aplica: Motores diésel turboalimentados
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://highwayandheavyparts.com/blog/diesel-engine-smoke-colors/ (Highway and Heavy Parts — Diesel Engine Smoke Colors)

Humo azul = aceite quemándose.
1. Descartar primero el TURBO: los sellos del turbo pueden dejar pasar aceite a la admisión o al escape (revisar aceite en la salida del compresor, intercooler y juego del eje). Retorno de aceite del turbo obstruido o presión de cárter alta empeoran la fuga.
2. Nivel de aceite sobre lo normal o viscosidad incorrecta.
3. Guías/sellos de válvula gastados.
4. Anillos/camisas gastados (medir consumo de aceite, blow-by).
Un consumo de aceite alto acelera la acumulación de ceniza en el DPF (SPN 3720).

## [motor] Árbol: sobrecalentamiento (con énfasis en altura y calor)
- Aplica: Motores diésel con enfriamiento por líquido operando en altura (Calama 2.300 m) y ambiente caluroso
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.engineeringtoolbox.com/boiling-points-water-altitude-d_1344.html (Engineering ToolBox — Water boiling points vs altitude); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins: SPN 110 FMI 0/16, SPN 111)

Hecho físico: el agua hierve a menor temperatura en altura. Agua pura a presión atmosférica: 100,0 °C a nivel del mar; 92,1 °C a 2.286 m; 89,6 °C a 3.048 m; 86,6 °C a 3.962 m (Engineering ToolBox). Por eso la tapa de presión y la mezcla anticongelante en buen estado son CRÍTICAS en altura: una tapa que no sostiene presión provoca ebullición y pérdida de refrigerante antes que al nivel del mar.
Árbol (de más probable a menos):
1. Nivel de refrigerante y fugas (con motor frío). Presurizar el sistema y buscar fugas.
2. Radiador/intercooler/condensador tapados externamente por polvo o barro: limpiar desde el lado del motor hacia afuera.
3. Embrague de ventilador (viscoso o electromagnético) que no engancha; correa.
4. Tapa de presión: probar que sostiene la presión nominal del fabricante.
5. Termostato pegado; bomba de agua (rodete).
6. Concentración de anticongelante (refractómetro) y presencia de gases de combustión en el refrigerante (junta de culata).
7. Operación: subidas largas cargadas en marcha baja; ralentí prolongado con PTO en equipos con enfriamiento marginal.
8. Verificar sensor: comparar temperatura del ECU con termómetro infrarrojo antes de desarmar.

## [motor] Árbol: baja presión de aceite
- Aplica: Motores diésel pesados
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (Diesel Laptops — DD15 SPN 100 FMI 1 "Low Engine Oil Pressure", FMI 17 "Very Low", FMI 18 "Oil Pressure Low", FMI 3/4 sensor); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins SPN 100 FMI 3/4/18)

1. Si la lámpara roja está encendida: detener el motor. No seguir operando para "ver qué pasa".
2. Diferenciar eléctrico vs. real: FMI 3/4 = circuito del sensor; FMI 1/17/18 = el sensor lee presión baja. Instalar manómetro mecánico y comparar con el valor del ECU en ralentí caliente y a régimen.
3. Si la presión real es baja: nivel de aceite; dilución por combustible (olor, viscosidad, nivel que SUBE); viscosidad incorrecta; filtro de aceite incorrecto/obstruido; válvula de alivio pegada; chupador tapado; bomba desgastada; desgaste de cojinetes (análisis de aceite con metales).
4. Si la presión real es buena: arnés, conector o sensor (SPN 100 FMI 3/4).
5. Temperatura de aceite alta reduce viscosidad y presión en ralentí (SPN 175).

## [postratamiento] Árbol: consumo de AdBlue/DEF anormal y derate SCR
- Aplica: Euro 5/Euro 6 con SCR (Mercedes BlueTec, Mack/Volvo/Renault SCR, Scania SCR)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.crownoil.co.uk/fuel-specifications/adblue-iso-22241/ (Crown Oil — AdBlue ISO 22241 specifications); https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15: SPN 3364, 4364, 5246, 1761); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins SPN 4094, 3362, 5394)

Especificación del reactivo (ISO 22241, Crown Oil): urea 31,8-33,2 % (m/m); densidad a 20 °C 1,0870-1,0930 g/cm³; índice de refracción a 20 °C 1,3814-1,3843; materia insoluble ≤ 20 mg/kg.
Árbol:
1. Leer códigos: calidad (SPN 3364, 4094), nivel (1761), eficiencia SCR (4364), dosificación (3361, 3362, 5394), NOx (3216, 3226), inducción (5246).
2. Medir el AdBlue con refractómetro. Fuera de especificación → vaciar, lavar y rellenar. Revisar almacenamiento en faena (bidones abiertos, polvo, sol, reutilización de envases de otros fluidos).
3. Consumo ALTO: fuga en líneas/uniones (cristales blancos), dosificador que gotea, sensor de nivel erróneo.
4. Consumo BAJO con derate: inyector DEF tapado por cristales, filtro de la bomba DEF obstruido, línea doblada/congelada, bomba débil → prueba de dosificación con escáner OEM (cantidad dosificada vs. comandada).
5. Eficiencia SCR baja con DEF bueno y dosificación correcta: sensor NOx de salida desplazado, catalizador con depósitos de urea (típico con mucho ralentí/PTO: escape frío), fuga de escape antes del sensor.
6. Tras reparar, la salida de la inducción/derate puede requerir procedimiento OEM (ver SPN 5246).

## [postratamiento] Árbol: regeneración del DPF que no termina / regeneraciones frecuentes
- Aplica: Euro 5/Euro 6 con DPF (y Euro 5 EEV con DPF donde aplique)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fleetmaintenance.com/equipment/emissions-and-efficiency/article/12182572/the-good-and-bad-of-diesel-particulate-filter-regenerations (Fleet Maintenance — The good and bad of DPF regenerations, citando a Daimler Trucks North America); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins SPN 5319 FMI 31, SPN 5397 FMI 31)

Causa principal de regeneración fallida (Daimler Trucks NA): no alcanzar la temperatura de escape requerida en el DOC y DPF para quemar el hollín.
1. Condiciones de operación: regeneración interrumpida por apagado, movimiento, PTO o por el operador (SPN 5319 FMI 31 regeneración incompleta).
2. DOC con la cara de entrada tapada: ocurre tras periodos largos de baja carga y baja velocidad; restringe el flujo y limita la temperatura (Daimler).
3. Dosificador de combustible (HC doser / 7° inyector) o su línea obstruidos: no hay combustible para elevar temperatura en el DOC (Daimler).
4. Sensores de temperatura de escape (entrada DOC, salida DOC, salida DPF) o sensor ΔP con tomas tapadas → el ECU aborta o calcula mal.
5. Ceniza: la ceniza NO se quema ("es como tratar de quemar roca"); si la ΔP sigue alta tras regenerar, el DPF necesita limpieza de ceniza (SPN 3720).
6. Regeneraciones demasiado frecuentes (SPN 5397): exceso de hollín por combustión (inyectores, EGR, fugas de aire, filtro de aire restringido) o sensor ΔP leyendo alto.
Durante la regeneración estacionaria: estacionar en zona despejada (sin pasto/combustible cerca), temperaturas de escape muy altas.

## [postratamiento] Ralentí prolongado y uso de PTO: efecto en DPF, EGR y SCR
- Aplica: Camiones aljibe, de riego, pluma y polibrazo con largas horas de ralentí o PTO a bajo régimen, Euro 5/6
- Tipo: falla_conocida
- Confiabilidad: tecnica_terceros
- Fuente: https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/8375705 (US Patent 8,375,705 — la regeneración pasiva rinde mal en ralentí cuando la temperatura de escape cae bajo el rango de activación de 250-400 °C); https://www.fleetmaintenance.com/equipment/emissions-and-efficiency/article/12182572/the-good-and-bad-of-diesel-particulate-filter-regenerations (DOC con cara tapada tras periodos largos de baja carga)

- La regeneración pasiva del DPF (oxidación del hollín con NO2) necesita temperaturas de escape de aproximadamente 250-400 °C; en ralentí el escape queda por debajo de ese rango y el hollín se acumula (patente US 8,375,705).
- El trabajo prolongado a baja carga favorece el taponamiento de la cara del DOC (Daimler vía Fleet Maintenance), lo que a su vez impide que las regeneraciones activas terminen.
- Consecuencias típicas en la flota: SPN 3719 (hollín alto), SPN 5319 (regeneración incompleta), VGT/EGR trabados por carbón (SPN 641 FMI 7, SPN 2791 FMI 7), eficiencia SCR baja (SPN 4364).
- Medidas: no interrumpir regeneraciones; programar regeneraciones estacionarias cuando el hollín sube; usar el modo PTO/ralentí elevado que el OEM permita; incluir el % de hollín en la inspección diaria; limitar ralentí innecesario.

## [frenos] Árbol: no carga presión de aire / carga lenta
- Aplica: Sistemas de freno neumático de camiones (compresor, gobernador, secador, circuitos)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.lowestpricetrafficschool.com/handbooks/cdl/en/5/3 (Florida CDL Handbook, Sección 5.3 — Inspecting Air Brake Systems)

Valores de verificación (manual CDL, EE. UU.):
| Prueba | Valor |
|---|---|
| Tiempo de carga (sistema doble) | de 85 a 100 psi en 45 s o menos, motor a régimen de operación |
| Tiempo de carga (sistema simple) | de 50 a 90 psi en 3 min |
| Corte del gobernador (cut-out) | ≈125 psi |
| Reinicio de carga (cut-in) | ≈100 psi |
| Alarma de baja presión | debe activarse antes de caer bajo 60 psi |
| Fuga, frenos liberados | < 2 psi/min (vehículo solo), < 3 psi/min (combinación) |
| Fuga, frenos aplicados | no más de 3 psi/min (solo), 4 psi/min (combinación) |
| Aplicación de frenos de resorte | entre 20 y 40 psi (según fabricante) |
Árbol (de más probable a menos): fugas (escuchar/agua jabonosa en uniones, válvulas, cámaras); gobernador desajustado o válvula de descarga del compresor pegada; secador de aire saturado/purga pegada abierta; línea de descarga del compresor obstruida por carbón (común en ralentí prolongado); filtro de admisión del compresor tapado (polvo); compresor desgastado (aceite en el sistema).
Prevalecen los valores del fabricante del camión (ver body builder y manual de operación).

## [frenos] Árbol: frenos que se pegan / rueda que calienta
- Aplica: Frenos neumáticos de tambor/disco con ABS
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.lowestpricetrafficschool.com/handbooks/cdl/en/5/3 (Florida CDL Handbook 5.3 — slack adjuster); https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (Bendix EC-60 — prueba de moduladoras PMV)

1. Identificar la(s) rueda(s) calientes (termómetro infrarrojo) tras un recorrido.
2. Freno de estacionamiento (resorte) que no libera completamente: presión insuficiente en la cámara de resorte (fugas, válvula relé), cámara dañada. Los frenos de resorte aplican entre 20 y 40 psi (manual CDL): con presión baja en el sistema pueden quedar parcialmente aplicados.
3. Ajuste: un regulador (slack adjuster) que se mueve más de ~1 pulgada donde se une el vástago probablemente necesita ajuste (manual CDL); un regulador automático que "sobreajusta" o está agarrotado.
4. Mecánico: leva en S agarrotada (bujes secos/polvo), resortes de retorno de zapatas, pistón/caliper trabado (disco).
5. Válvula relé o moduladora ABS que no descarga: prueba de moduladora (Bendix: 4,9-5,5 Ω REL-CMN y HLD-CMN; 9,8-11,0 Ω REL-HLD).
6. Válvula de pedal que no retorna.

## [transmision] Árbol: caja automatizada (AMT) que no cambia o entra en modo emergencia
- Aplica: Volvo I-Shift, Mack mDRIVE, Scania Opticruise, Mercedes PowerShift, Renault Optidriver (principios comunes de AMT neumáticas/electroneumáticas)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://productinfo.serviceranger4.com/books/TRTS0960/lang/en-us/section/TS0960FC115 (Eaton TRTS0960 — comunicación J1939 de la TCM); https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (tensión de sistema); https://www.lowestpricetrafficschool.com/handbooks/cdl/en/5/3 (presión de aire)

Requisito específico de cada OEM: requiere licencia (Volvo PTT/Impact, Scania SDP3/SWS, Mercedes XENTRY).
Árbol genérico (de más probable a menos):
1. Leer códigos de la TCU (MID 130 / SA de transmisión). Anotar si hay códigos de presión de aire, embrague, sensores de posición o comunicación.
2. Presión de aire: la AMT actúa neumáticamente. Presión baja o aire húmedo/con aceite (secador saturado) → cambios lentos o bloqueados. Verificar carga de aire (ficha de frenos: 85→100 psi en ≤45 s).
3. Tensión: baterías débiles/caída de tensión alteran la TCU (ver fichas Delco Remy). Revisar masas de la caja.
4. Comunicación J1939 con motor y tablero: resistencia 50-70 Ω en la red y suma de tensiones C+D 4,5-5,5 V (Eaton).
5. Embrague: desgaste/patinamiento, recalibración pendiente tras reparación (FMI 13 "fuera de calibración"): ejecutar calibración/aprendizaje con herramienta OEM.
6. Sensores de posición de la palanca/horquillas, velocidad de eje (conectores con aceite).
7. Temperatura de aceite de caja alta.

## [transmision] Allison: luz CHECK TRANS, "modo de emergencia" y lectura de códigos en el selector
- Aplica: Allison serie 3000/4000 (p. ej. Mack GU813 + Allison), controles 5ª generación
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (Allison OM8491EN — Operator's Manual 3000 and 4000 Series, 2021, secc. 4 y 6.2.1-6.3)

- Al arrancar, CHECK TRANS enciende brevemente (prueba de lámpara). Si queda encendida con DTC activo: el selector deja en blanco SELECT y el display MONITOR muestra la marcha en que la caja quedó BLOQUEADA. No acepta cambios de selector hasta que el DTC se inactive. Se puede operar poco tiempo en la marcha alcanzada para llevar el camión a lugar seguro.
- Si se apaga el motor con el DTC activo, al rearrancar la caja puede quedar bloqueada en N (neutro).
- Leer códigos (selector de teclas): presionar simultáneamente ↑ y ↓ dos veces (prognóstico apagado) o cinco veces (prognóstico encendido); MODE pasa al siguiente código (hasta 5, de 5 caracteres, con estado activo/inactivo). Selector de palanca: botón DISPLAY MODE/DIAGNOSTIC.
- Borrar: en modo diagnóstico mantener MODE ~3 s borra activos; ~10 s borra todos los almacenados.
- Inhibición de cambio N→D/R: también puede estar programada por la TCM al detectar equipo auxiliar operando (PTO/carrocería) — no es falla.

## [transmision] Allison: temperaturas de sobrecalentamiento y nivel de aceite
- Aplica: Allison serie 3000/4000
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (Allison OM8491EN — secc. 3.4 High Fluid Temperature y 5.8 Periodic Fluid Level Checks)

| Punto | Límite de sobretemperatura |
|---|---|
| Aceite en cárter (sump) | 121 °C (250 °F) |
| Aceite hacia el enfriador | 149 °C (300 °F) |
| Salida del retardador | 165 °C (330 °F) |
Temperatura continua típica del cárter: 93 °C (200 °F).
- Si sobrecalienta: verificar primero el nivel de aceite correcto.
- No mantener más de 10 s a acelerador a fondo con la caja en marcha y la salida detenida (calado de convertidor).
- Chequeo en caliente (HOT CHECK) a 71-93 °C (160-200 °F), que es el que se usa para fijar nivel. El chequeo en frío sólo confirma nivel suficiente para arrancar.
- Por debajo de la temperatura mínima: operar en N con motor en ralentí al menos 20 min antes de usar marchas (en frío extremo, según tabla del manual).

## [implemento] Árbol: la PTO no engancha
- Aplica: PTO de caja (Chelsea/Parker, Muncie) accionadas por aire, hidráulicas (powershift) o cable, en aljibes, riego, pluma y polibrazo
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.munciepower.com/cms/files/Products/Literature/Documents/Troubleshooting/TRG08-04.pdf (Muncie Power Products TRG08-04 — Power Take-Off Solenoid Troubleshooting Guide); https://www.chelseaptopart.com/pto-troubleshooting (Chelsea PTO troubleshooting, tecnica_terceros)

1. Interbloqueos del vehículo: freno de estacionamiento, neutro, velocidad/rpm, parámetros del VECU/módulo de carrocería que habilitan la PTO. Leer códigos del módulo de carrocería/VECU.
2. Eléctrico: interruptor del tablero recibe alimentación y masa; fusible (Muncie: fusible de 10 A; 40 A en serie TG con Lectra-Shift); se escucha el "clic" del solenoide.
3. Tensión en el solenoide: Muncie especifica mínimo 10,2 y máximo 14 V DC para su solenoide de 12 V — en camiones de 24 V verificar que el solenoide sea de 24 V o que exista reductor/relé adecuado.
4. Resistencia de bobina (Muncie): solenoide estándar 8,5-10 Ω; consumo 1,2-1,4 A (12 V). Lectra-Shift: bobina ENGAGE 0,3-0,5 Ω (cable blanco a masa), bobina HOLD 4,7-5,9 Ω (cable rojo a masa).
5. Aire (PTO neumática): presión de suministro en la tapa de cambio — causa más común cuando es baja (Chelsea); plumbing según diagrama; solenoide/cartucho doblado o montado muy cerca de un objeto sólido; basura en solenoide o filtro.
6. Hidráulica (powershift): presión hidráulica en la PTO vs. requerimiento del manual de instalación; mangueras/fittings obstruidos; paquete de embrague "congelado" (engancha pero patina o no desengancha).
7. Mecánica (cable/palanca): cable estirado o mal ruteado, backlash, retén de cambio gastado.
Ruidos: silbido = engranes muy apretados (backlash 0,006-0,012 pulg según Chelsea); traqueteo = muy sueltos o vibración torsional.

## [tren_rodaje] Árbol: vibración en el cardán (línea de transmisión)
- Aplica: Cardanes de camiones pesados (Spicer/Dana y similares), incluidos cardanes de PTO a bombas
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.trailer-bodybuilders.com/distributors-upfitters/article/21739166/what-every-shop-must-know-about-drivelines (Trailer/Body Builders — What every shop must know about drivelines, citando guías Spicer)

- Frecuencia: vibración transversal = UNA vez por vuelta del cardán (desbalance, eje doblado); vibración torsional = DOS veces por vuelta (ángulos de operación o fase incorrectos).
- Ángulos: mantener los ángulos reales de operación bajo 3° si es posible; ángulos de 3° no producen vibraciones dañinas.
- Ángulos iguales en ambos extremos dentro de 1° para que se cancele la vibración torsional; nunca exactamente iguales: se necesita al menos 0,5° de diferencia para que giren los rodillos de las crucetas.
- Fase: marcar antes de desarmar; un diente de error en el estriado equivale a 22,5° fuera de fase. No retirar el cardán tirando de la horquilla deslizante (se pierde la fase).
- Balance: siempre balancear cardanes reparados.
Árbol: (1) crucetas con juego/secas y rodamiento central; (2) fase tras intervención; (3) ángulos (cambio de altura de suspensión, soportes de motor/caja, carrocería o PTO agregada); (4) balance/eje doblado; (5) estrías de la horquilla deslizante gastadas.

## [motor] Efecto de la altura en la densidad del aire (atmósfera estándar)
- Aplica: Todos los motores de combustión; faenas en Calama (~2.300 m) y alta cordillera hasta 4.000 m
- Tipo: especificacion
- Confiabilidad: tecnica_terceros
- Fuente: https://www.engineeringtoolbox.com/standard-atmosphere-d_604.html (Engineering ToolBox — U.S. Standard Atmosphere, tabla SI)

| Altura (m) | Temperatura estándar (°C) | Presión (kPa) | Densidad (kg/m³) |
|---|---|---|---|
| 0 | 15,0 | 101,3 | 1,225 |
| 1.000 | 8,5 | 89,9 | 1,112 |
| 2.000 | 2,0 | 79,5 | 1,007 |
| 3.000 | −4,5 | 70,1 | 0,909 |
| 4.000 | −11,0 | 61,7 | 0,819 |
A 2.000 m la densidad del aire es ~18 % menor que a nivel del mar; a 4.000 m ~33 % menor (cálculo con los valores de la tabla). Consecuencias: menos oxígeno por ciclo → el turbo debe girar más para lograr el mismo boost; el sensor barométrico (SPN 108) informa la presión ambiente al ECU para corregir; lecturas de boost "absoluto" vs. "relativo" cambian con la altura (cuidado al comparar con valores de manual medidos al nivel del mar).

## [motor] Altura: derate, temperatura de escape y sobrevelocidad del turbo
- Aplica: Diésel turboalimentados pesados en altura
- Tipo: especificacion
- Confiabilidad: tecnica_terceros
- Fuente: https://www.techscience.com/fdmp/v19n4/50365/html (FDMP — A Strategy to Control the Turbocharger Energy of a Diesel Engine at Different Altitudes, 2023); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins SPN 103 FMI 15/16 velocidad de turbo sobre lo normal; SPN 3555 densidad de aire ambiente)

- Al subir de 0 a 4.500 m, la relación de presión del compresor requerida para mantener el desempeño sube de 2,4 a 4,3 y la energía de compresión requerida llega al 240 % de la de nivel del mar (a 1.000 rpm) (FDMP).
- Con un turbo no adaptado, a 3.000 m se observan pérdidas de torque del orden de 25 % en régimen nominal (FDMP).
- Los límites para recuperar potencia en altura son: presión máxima de cilindro, velocidad del turbo y temperatura de escape. Por eso los ECUs limitan torque (derate) en altura para proteger el turbo de sobrevelocidad y el motor de temperaturas de escape excesivas.
- En la flota: códigos de velocidad de turbo alta (p. ej. Cummins SPN 103 FMI 15/16) o reducción de torque sin códigos en subidas cargadas a más de 3.000 m pueden ser comportamiento de diseño. Antes de reparar: descartar restricción de admisión (filtro), fugas de aire de carga y lectura correcta del sensor barométrico.

## [motor] Polvo: servicio del filtro de aire por restricción (no por tiempo)
- Aplica: Filtros de aire secos de camiones en faena minera con polvo
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.donaldson.com/en-us/engine/filters/technical-articles/servicing-by-restriction/ (Donaldson — Servicing your air filter: to change or not to change); https://www.donaldson.com/content/dam/donaldson/engine-hydraulics-bulk/catalogs/air-intake/north-america/F110027-ENG/accessories/Air-Intake-Accessories.pdf (Donaldson — Air Intake Accessories catalog, pág. 210-211)

- La única forma precisa de saber cuándo cambiar el filtro es medir la restricción de admisión (Donaldson). Un filtro que se ve muy sucio puede tener mucha vida restante; la inspección visual no sirve.
- Sobre-servicio (cambiar/soplar muy seguido) es dañino: cada apertura de la carcasa arriesga contaminar el lado limpio, instalar mal el filtro y dañarlo; además el polvo retenido mejora la eficiencia del filtro.
- La restricción se mide en el lado limpio (salida) del filtro; el máximo lo define el fabricante del motor. Para medir la restricción máxima real el motor debe estar a alta velocidad y plena carga (máximo flujo de aire).
- Indicadores Donaldson disponibles con puntos de disparo de 15" H2O (3,7 kPa), 20" H2O (5 kPa), 25" H2O (6,2 kPa) y 30" H2O (7,5 kPa): usar el que corresponda al límite del fabricante del motor.
- Reset del indicador: botón amarillo tras el cambio.
- En polvo severo: revisar también prefiltros/eyectores (válvula Vacuator), mangueras entre filtro y turbo (una fuga aguas abajo del filtro deja pasar polvo sin filtrar y destruye el turbo y el motor).

## [general] Método de diagnóstico: orden de trabajo recomendado para el técnico
- Aplica: Toda la flota
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — "Don't jump to early conclusions. Perform the diagnostic procedures in the exact order listed", pág. 21; definición de diagnóstico en 3 pasos, pág. 1); https://www.csselectronics.com/pages/j1939-73-dm1-diagnostic-message-dtc (DM1/DM2)

Delco Remy define el diagnóstico como un proceso de tres partes: confirmar la falla, aislar la causa y reparar/reemplazar. Secuencia práctica:
1. Entrevista: síntoma, cuándo ocurre (frío/caliente, carga, altura, PTO), desde cuándo, reparaciones recientes.
2. Leer DM1 y DM2 de todos los módulos + freeze frame; anotar SPN, FMI, OC y módulo.
3. Historial: OT anteriores del mismo camión y casos resueltos de la flota con el mismo código.
4. Clasificar el FMI: eléctrico (3/4/5/6), condición real (0/1/15-18), red (9/19), mecánico (7), calibración (13), estado (31).
5. Verificar físicamente la condición (manómetro, termómetro, refractómetro, multímetro) antes de cambiar piezas.
6. Pruebas en orden de más probable/más barato a menos probable/más caro.
7. Reparar, borrar, prueba de ruta, confirmar que no vuelve a DM1. Registrar causa raíz en la OT (alimenta el conocimiento de la flota).


## [electrico] Técnica FMI 3 ↔ FMI 4: desconectar el sensor para ubicar la falla
- Aplica: Sensores de 3 hilos con referencia 5 V en ECUs J1939
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.fcarusa.com/TechSupport/KB/introduction-mid-pid-sid-fmi (definiciones FMI 3 y FMI 4); https://cloreautomotive.com/troubleshooting-5v-reference-circuits/ (Clore — desconexión progresiva de sensores en circuito de 5 V)

Lógica (basada en las definiciones FMI 3 = voltaje alto/corto a fuente alta, FMI 4 = voltaje bajo/corto a masa):
1. Con código FMI 4 activo, desconectar el sensor. Si el ECU cambia a FMI 3 (señal abierta), el arnés y el ECU están bien y el sensor es el sospechoso (en corto interno). Si sigue en FMI 4 con el sensor desconectado, el cable de señal está a masa o la referencia está caída.
2. Con FMI 3 activo: puentear señal a retorno (masa de sensor) en el conector del arnés con un puente con fusible; si cambia a FMI 4, el arnés responde y el sensor está abierto; si no cambia, cable abierto o ECU.
3. Si varios sensores de la misma referencia marcan FMI 3/4 a la vez: sospechar referencia 5 V o masa de sensor común (Clore: desconectar uno a uno).
Nota: la polaridad exacta (a qué FMI cambia un circuito abierto) depende del diseño de entrada del ECU (pull-up o pull-down); confirmar con el manual OEM.

## [electrico] Prueba de baterías de 12 V en sistemas de 24 V (Delco Remy)
- Aplica: Baterías plomo-ácido (inundadas libres de mantención y AGM) en camiones 24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy — Diagnostic Procedures Manual, pág. 11-12, sección 3-1)

1. Inspeccionar cada batería (caja, bornes, indicadores).
2. Baterías con tapones: si la diferencia de densidad entre la celda más alta y la más baja supera 0,050 → reemplazar; si es menor pero alguna celda está bajo 1,230 → recargar.
3. Carga de 300 A por 15 s para eliminar carga superficial; en baterías con tapones, si aparece neblina azul en alguna celda → reemplazar.
4. Prueba de capacidad: aplicar carga de 1/2 del CCA (a 0 °F) durante 15 s, medir tensión en bornes con la carga aplicada y comparar con la tabla de temperatura del manual.
5. En 24 V, probar CADA batería de 12 V por separado: una batería débil en serie arrastra a la otra y reduce la vida de ambas.

## [motor] Códigos de hollín y presión diferencial del DPF (SPN 3719, 3720, 3251)
- Aplica: Motores Euro 5/6 con DPF (genérico J1939; los mismos SPN se usan en Detroit, Cummins, Volvo/Mack y otros)
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (Diesel Laptops — DD15 2014-2016 fault codes); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4)

| Código | Significado |
|---|---|
| SPN 3719 FMI 16 | Nivel de hollín alto (DD15) |
| SPN 3719 FMI 0 | Nivel de hollín muy alto (DD15) |
| SPN 3720 FMI 15/16 | DPF alcanzó fin de vida de servicio: ceniza (DD15) |
| SPN 3251 FMI 16 / 0 | Presión diferencial del DPF alta / muy alta (DD15) |
| SPN 3251 FMI 2 | ΔP errática (Cummins) — mangueras del sensor |
| SPN 3251 FMI 3 / 4 | Circuito del sensor ΔP alto / bajo (Cummins) |
| SPN 5319 FMI 31 | Regeneración incompleta (Cummins) |
| SPN 5397 FMI 31 | Regeneración demasiado frecuente (Cummins) |
Hollín se quema en regeneración; ceniza no. ΔP alta con hollín bajo tras regenerar = ceniza o tomas del sensor tapadas. Detalle de causas/comprobaciones: `codigos/j1939-generico.json`.

## [postratamiento] Códigos de AdBlue/DEF y SCR más frecuentes (SPN 1761, 3031, 3364, 4094, 4364, 5246)
- Aplica: Euro 5/6 con SCR (genérico J1939)
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4)

| Código | Significado |
|---|---|
| SPN 1761 FMI 18 / 1 | Estanque DEF vacío / nivel 0 con velocidad limitada (DD15) |
| SPN 1761 FMI 3 / 4 | Circuito del sensor de nivel DEF alto / bajo (Cummins) |
| SPN 3031 FMI 3 / 4 | Circuito del sensor de temperatura del estanque DEF (Cummins) |
| SPN 3364 FMI 2 / 17 / 18 / 1 | Calidad de DEF inadecuada: advertencia → advertencia final (DD15) |
| SPN 4094 FMI 31 | Límites de NOx excedidos por calidad insuficiente de reactivo (Cummins) |
| SPN 4364 FMI 18 / 1 | Eficiencia de conversión SCR baja / muy baja (DD15, Cummins) |
| SPN 3361 FMI 31 | Error de unidad dosificadora DEF (DD15) |
| SPN 3362 FMI 31 | Líneas de entrada de la unidad dosificadora (Cummins) |
| SPN 5394 FMI 5 / 7 | Válvula dosificadora DEF abierta / no responde (Cummins) |
| SPN 5246 FMI 15 / 16 / 0 | Falla regulatoria ignorada: derate → acción final pendiente → limitación (DD15/Cummins) |
Primera prueba siempre: refractómetro al AdBlue (ver árbol de consumo de AdBlue). Detalle en `codigos/j1939-generico.json`.

## [motor] Códigos de inyectores y falla de encendido (SPN 651-656, 1322-1328)
- Aplica: Motores de 6 cilindros J1939 (Mercedes OM457/OM460/OM906, Mack MP8, Volvo D13, Renault DTI13 — la numeración SPN es estándar; la estrategia de cada OEM varía)
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15: SPN 651-656 FMI 3/4/5/6/7); https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins: SPN 651-656 FMI 7, SPN 1322-1328 FMI 31)

| SPN | Cilindro |
|---|---|
| 651 | 1 |
| 652 | 2 |
| 653 | 3 |
| 654 | 4 |
| 655 | 5 |
| 656 | 6 |
FMI 5 = circuito abierto; FMI 6 = en corto; FMI 7 = sistema mecánico no responde (DD15 / Cummins). SPN 1322 FMI 31 = misfire en múltiples cilindros; SPN 1323-1328 FMI 31 = misfire cilindro 1 a 6 (Cummins).
Diagnóstico: códigos de circuito de un solo cilindro → arnés bajo tapa de válvulas / conector / bobina del inyector; varios cilindros de un mismo banco o driver → alimentación común o ECU; FMI 7 o misfire → prueba de contribución de cilindros, compresión, calidad de combustible.

## [motor] Códigos de presión de riel y combustible de baja (SPN 157, 94, 97, 5585)
- Aplica: Motores common rail J1939
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4: SPN 157 FMI 0/1/2/3/4/7/15/16/18, SPN 5585 FMI 18, SPN 97 FMI 3/4/16); https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15: SPN 94 FMI 1/2/4/15/16, SPN 157 FMI 17)

| Código | Significado |
|---|---|
| SPN 157 FMI 3 / 4 | Circuito del sensor de presión de riel alto / bajo |
| SPN 157 FMI 18 / 1 | Presión de riel bajo lo normal (moderado / severo) |
| SPN 157 FMI 16 / 0 | Presión de riel sobre lo normal (moderado / severo) |
| SPN 157 FMI 7 | Presión de riel: sistema mecánico no responde |
| SPN 157 FMI 17 | Presión mínima no alcanzada en arranque (DD15) |
| SPN 5585 FMI 18 | Presión de riel en arranque bajo lo normal (Cummins) |
| SPN 94 FMI 1 | Presión de combustible de baja demasiado baja (DD15) |
| SPN 94 FMI 15 / 16 | Aviso de servicio / reemplazo de filtro de combustible (DD15) |
| SPN 97 FMI 16 | Agua en combustible (Cummins) |
Regla: presión de riel baja → revisar SIEMPRE primero el circuito de baja (filtros, succión, aire, agua) antes de la bomba de alta o inyectores.

## [motor] Códigos de admisión, turbo y EGR (SPN 102, 103, 105, 108, 1127, 641, 411, 2791)
- Aplica: Motores turbo J1939, Euro 3 a Euro 6
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4); https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15)

| Código | Significado |
|---|---|
| SPN 102 FMI 18 / 16 | Presión de múltiple (boost) bajo / sobre lo normal (Cummins) |
| SPN 103 FMI 15 / 16 | Velocidad del turbo sobre lo normal (Cummins) — típico en altura/restricción |
| SPN 105 FMI 0 | Temperatura de admisión muy alta (Cummins) — intercooler sucio |
| SPN 108 FMI 3 / 4 | Sensor barométrico circuito alto / bajo (Cummins) |
| SPN 1127 FMI 7 | Presión de boost: sistema mecánico no responde (Cummins) |
| SPN 1127 FMI 10 | Respuesta de boost lenta (DD15) |
| SPN 641 FMI 7 / 13 | Actuador VGT no responde / fuera de calibración (Cummins) |
| SPN 411 FMI 0 / 3 / 4 | Presión diferencial EGR alta / circuito alto / bajo (DD15) |
| SPN 2791 FMI 5 / 7 | Válvula EGR circuito abierto / no responde (Cummins) |
En la flota (polvo, ralentí, altura): priorizar filtro de aire, fugas de aire de carga, carbonización de VGT/EGR por ralentí prolongado.

## [motor] Códigos de temperatura y protección (SPN 110, 111, 175, 100, 1569)
- Aplica: Motores J1939
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4); https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15)

| Código | Significado |
|---|---|
| SPN 110 FMI 0 / 16 | Temperatura de refrigerante muy alta / alta (Cummins) |
| SPN 110 FMI 18 | Termostato fallado — no alcanza temperatura (DD15) |
| SPN 111 FMI 1 / 18 | Nivel de refrigerante muy bajo / bajo (DD15) |
| SPN 175 FMI 0 | Temperatura de aceite alta (DD15) |
| SPN 100 FMI 1 / 17 / 18 | Presión de aceite baja / muy baja / baja (DD15) |
| SPN 100 FMI 3 / 4 | Circuito del sensor de presión de aceite alto / bajo (Cummins) |
| SPN 1569 FMI 31 | Reducción de torque por protección del motor (Cummins) — código consecuencia |
Primero seguridad: con lámpara roja detener el motor y verificar físicamente (nivel, manómetro, termómetro).

## [electrico] Códigos eléctricos y de red (SPN 168, 158, 3509-3514, 639, 629, 1675)
- Aplica: ECUs J1939
- Tipo: codigo_falla
- Confiabilidad: tecnica_terceros
- Fuente: https://www.alliedsystems.com/pdf/Wagner/Forms/80/80-1235.pdf (Cummins Tier 4); https://repair.diesellaptops.com/detroit-diesel-dd15-2014-2016-fault-codes-list/ (DD15)

| Código | Significado |
|---|---|
| SPN 168 FMI 1 / 18 | Tensión de batería baja (DD15 / Cummins) |
| SPN 168 FMI 16 | Tensión de batería sobre lo normal (Cummins) — regulador |
| SPN 168 FMI 9 | Conexión de batería perdida (DD15) |
| SPN 158 FMI 2 | Interruptor de encendido no plausible (DD15) |
| SPN 3510 FMI 3 / 4 | Alimentación de sensores 2 (5 V) alta / baja (Cummins) |
| SPN 3511 / 3512 | Alimentación de sensores 3 / 4 (Cummins) |
| SPN 639 FMI 14 | Falla del enlace J1939 (DD15) |
| SPN 629 FMI 12 | Falla interna crítica del ECM (Cummins) |
| SPN 1675 FMI 31 | Protección de sobre-arranque del motor de partida (Cummins) |
Varias FMI 9/19 en distintos módulos al mismo tiempo = revisar la red (fichas de CAN) antes que cada módulo.

## [frenos] Códigos ABS de sensores de rueda y moduladoras (SPN 789-798, 802)
- Aplica: ABS Bendix EC-60 (referencia pública); los SPN 789-798 son SAE y los usan también WABCO/Knorr, pero los FMI son propios de cada fabricante
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (Bendix SD-13-4869 — EC-60 ABS/ATC/ESP Controllers, tablas de DTC y apéndice)

| SPN | Ubicación |
|---|---|
| 789 | Sensor rueda eje direccional izquierdo |
| 790 | Sensor rueda eje direccional derecho |
| 791 | Sensor rueda eje motriz izquierdo |
| 792 | Sensor rueda eje motriz derecho |
| 793 / 794 | Sensor eje adicional izquierdo / derecho |
| 795-798 | Moduladoras (PMV) por rueda (795 = dir. izq., 798 = motriz der.) |
| 802 | ECU / común de moduladoras |
FMI Bendix para sensor de rueda: 1 = entrehierro excesivo; 2 = abierto o en corto; 7 = extremo de rueda; 8 = señal errática; 10 = pérdida de señal; 14 = salida baja al iniciar marcha. Moduladora: 5 = abierto, 4 = corto a masa, 3 = corto a tensión.
Valores de prueba (Bendix): sensor 1500-2500 Ω, > 0,25 V AC a ~0,5 rev/s; moduladora 4,9-5,5 Ω (REL-CMN, HLD-CMN) y 9,8-11,0 Ω (REL-HLD).

## [frenos] ABS: árbol de diagnóstico de sensor de rueda (entrehierro, rueda fónica, rodamiento)
- Aplica: ABS de camiones con sensores inductivos de rueda
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (Bendix SD-13-4869, pág. 27-28)

1. Empujar el sensor hasta que toque la rueda fónica (se autoajusta al girar).
2. Girar la rueda a ~0,5 rev/s y verificar al menos 0,25 V AC de salida.
3. Revisar la cabeza del sensor (daño/limadura metálica), montaje de la rueda fónica y estado de los dientes.
4. Verificar juego axial del rodamiento de la maza (un juego excesivo aleja la rueda fónica).
5. Verificar el buje de retención (clamping sleeve) y el ruteo/sujeción del cable del sensor.
6. Medir resistencia 1500-2500 Ω y aislamiento a masa/tensión desde el conector del ECU.
7. Tamaño de neumático y número de dientes correctos si hay código de calibración de neumático.
8. Borrar: ciclo de encendido y circular sobre ~15 mph (24 km/h) o borrar con herramienta.

## [general] Cómo registrar un caso resuelto para que sirva al resto de la flota
- Aplica: Toda la flota (alimenta el historial de OT y casos resueltos del Copiloto)
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.brakeandfrontend.com/real-fixes-available-on-new-snap-on-suretrack-blog/ (Snap-on SureTrack Real Fixes: formato queja-causa-corrección); https://www.csselectronics.com/pages/j1939-73-dm1-diagnostic-message-dtc (campos de un DTC)

Formato "queja → causa → corrección" (usado por Snap-on SureTrack Real Fixes), con estos datos mínimos:
- Camión (patente/código interno), marca, modelo, motor, caja, año, km/horas, faena y altura.
- Queja del operador (síntoma con condiciones: carga, PTO, frío/caliente, altura).
- Códigos: SPN, FMI, OC, módulo (SA/MID), activo o histórico; freeze frame si existe.
- Pruebas realizadas CON sus valores medidos (p. ej. "C-D = 118 Ω", "refractómetro 28 %").
- Causa raíz confirmada y pieza cambiada (N° de parte).
- Corrección y verificación (código no volvió tras prueba de ruta de X km).
- Tiempo real de diagnóstico y reparación.
Un caso sin valores medidos ni causa raíz confirmada no debe usarse como "caso resuelto".

## [general] Inspección diaria orientada a diagnóstico temprano (faena minera)
- Aplica: Toda la flota en faena con polvo, altura y ralentí largo
- Tipo: procedimiento_diagnostico
- Confiabilidad: tecnica_terceros
- Fuente: https://www.donaldson.com/en-us/engine/filters/technical-articles/servicing-by-restriction/ (Donaldson — servicio por restricción); https://www.lowestpricetrafficschool.com/handbooks/cdl/en/5/3 (Florida CDL Handbook 5.3 — pruebas de aire); https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (Allison OM8491EN — CHECK TRANS al arranque)

Chequeos de 5 minutos que anticipan fallas:
1. Indicador de restricción del filtro de aire (no abrir el filtro si no está en rojo).
2. Luces de tablero: todas encienden en la prueba de lámparas y se apagan (CHECK TRANS en Allison debe encender brevemente y apagarse).
3. Presión de aire: tiempo de carga y alarma de baja presión (ver ficha de aire).
4. Nivel y aspecto de AdBlue (bidón cerrado, sin contaminación), nivel de refrigerante en frío, drenaje del separador de agua.
5. % de hollín del DPF en el tablero si el camión lo muestra; si una regeneración está pendiente, no interrumpirla.
6. Fugas visibles (cristales blancos de urea, aceite en turbo/intercooler, humedad en conectores).
7. Anotar cualquier código activo en la OT del día aunque "el camión ande bien".
