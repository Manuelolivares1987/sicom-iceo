# Allison 3000/4000 (4500 RDS) – controles 4ª/5ª generación – conocimiento para diagnóstico

Contexto flota: Mack Granite GU813 2014-2016 (y posiblemente GR 2019) con Allison **4500 RDS con
retardador** (ver ficha de identificación en mack.md). Controles probables: **5ª generación** (TCM A61/A62/A63,
conector de 80 pines, selector de botonera con display). Documentos en
`_Investigacion web 2026-09-19/Allison/`.

---

## [transmision] Generaciones de control Allison y compatibilidad selector/TCM
- Aplica: Allison 3000/4000 Series (incl. 4500 RDS) controles 4ª, 5ª y 6ª generación
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://rtsallison.com/Allison%205th_6th%20Gen%20Shift%20Selector%20Booklet_Digital.pdf (Allison 5th and 6th Gen Shift Selector Operation + Code Manual, PDF pág. 10) ; https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (Allison OM8491EN, 2021-09, pág. 141)

- TCM 5ª Gen: modelos **A61, A62, A63** (A63 "Max-Feature" admite 24 V; todos 12 V). TCM 6ª Gen: C71M, C72M, C73M.
  El TCM se conecta al arnés del vehículo con **un conector de 80 pines**.
- Allison liberó la 5ª Gen para todos los OEM a inicios de 2013 → GU813 2014-2016: 5ª Gen (el diagrama Mack
  2013BP muestra "Allison Transmission Gen 5 Control Module").
- Compatibilidad: selector 4ª Gen solo con TCM 5ª Gen; botonera 5ª Gen solo con TCM 5ª Gen; palanca (bump
  lever) y selector de franja (strip) 5ª Gen funcionan con TCM 5ª y 6ª; botonera 6ª Gen solo con TCM 6ª Gen.
- Con controles 6ª Gen, pulsar ↑↓ simultáneo **6 veces** muestra "HW LVL 6th GEN" (nivel de hardware).
- Al reemplazar TCM o selector, respetar esta tabla (un selector 5ª Gen botonera no funciona con TCM 6ª Gen).

## [transmision] Leer y borrar códigos de falla Allison desde el selector (5ª/6ª Gen)
- Aplica: Allison 3000/4000 con selector de botonera o palanca 5ª/6ª Gen (el selector de franja "strip" no tiene display ni diagnóstico)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, sección 6.3, pág. 112-115) ; https://rtsallison.com/Allison%205th_6th%20Gen%20Shift%20Selector%20Booklet_Digital.pdf (PDF pág. 9)

1. Detener el vehículo, freno de estacionamiento aplicado.
2. Botonera: presionar **↑ y ↓ simultáneamente 5 veces** si el paquete de pronósticos está ACTIVO, o **2 veces**
   si está DESACTIVADO. Palanca: botón **DISPLAY MODE/DIAGNOSTIC (DMD) 5 veces** (pronósticos ON) o 2 veces (OFF).
   (En 3700 SP y 4700/4800 con retardador el número de pulsaciones difiere; no es el caso de la 4500 RDS.)
3. Se muestran hasta **5 códigos (d1-d5)**, de 5 caracteres, con estado **ACTIVE / INACTIVE** debajo;
   activos primero, del más nuevo al más antiguo. **MODE** = pasar al siguiente código.
4. Borrar: en modo diagnóstico mantener **MODE ~3 s** hasta que "MODE" parpadee = borra códigos **activos**;
   mantener **MODE 10 s** (parpadea por segunda vez) = borra **todos** los códigos guardados.
5. Salir: ↑↓ una vez, o cualquier botón de rango (D, N, R), o esperar ~10 min sin actividad; en palanca, DMD
   hasta volver al rango. Apagar el encendido también sale.
- Anotar TODOS los códigos antes de borrar. Si se borra un código mientras la caja está bloqueada en rango, sigue
  bloqueada hasta seleccionar N o ciclar el encendido. Algunos códigos requieren ciclo de encendido para pasar a inactivos.
- Códigos inactivos se borran solos (d5 → d1) tras varios arranques sin reaparecer.

## [transmision] Leer códigos con selector 4ª Gen (formato d1, P, 07, 22)
- Aplica: Allison 3000/4000 con selector 4ª Gen (y "Model Year '09" con pronósticos)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://assets.wellertruck.com/reference-materials/owners-manuals/fourthgenshift-selector-manual.pdf (Allison Shift Selector Operation and Code Manual 3000/4000, pág. 10-12 y 31-34)

- Botonera: ↑↓ simultáneo **5 veces**; palanca: botón Diagnostics 5 veces.
- El display muestra 2 caracteres por vez: ejemplo P0722 se ve como **d1, P, 07, 22** (cada ítem ~1 s, se repite).
  **MODE** avanza a la siguiente posición (d2…d5).
- Borrar: mantener **MODE 10 s** (borra activos e inactivos).
- Lista de códigos MY09/4ª Gen en pág. 31-34 del mismo manual (C1312 … U0592).

## [transmision] Respuesta del TCM ante un código: qué ve el operador (CHECK TRANS, bloqueo en rango)
- Aplica: Allison 3000/4000 5ª/6ª Gen
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 6.1-6.2, pág. 110-112)

| Respuesta | Acción del TCM |
|---|---|
| DNS (Do Not Shift) | Libera y bloquea el lock-up, inhibe cambios desde el rango actual, enciende CHECK TRANS, muestra en MONITOR el rango logrado y deja en blanco SELECT; no responde a pedidos del selector |
| SOL OFF | Todos los solenoides apagados → operación hidráulica por defecto (PCS1 y PCS2 quedan aplicados hidráulicamente) |
| RPR | Return to Previous Range: vuelve al rango anterior si fallan pruebas de relación de velocidad o PS1 |
| NNC | Neutral No Clutches: neutro sin embragues aplicados |
| DNA | Do Not Adapt: detiene el aprendizaje adaptativo mientras el código está activo |
- CHECK TRANS enciende un instante al dar contacto (prueba de lámpara). Si queda encendida con SELECT en blanco:
  se puede mover el camión un tramo corto en el rango logrado hasta un lugar seguro. **Al apagar y volver a
  arrancar puede quedar trabada en N (neutro)** si el código sigue activo.
- Algunos códigos se registran sin encender CHECK TRANS.

## [transmision] Mensajes y estados del display del selector (cat-eyes, todo encendido, parpadeo)
- Aplica: Allison 3000/4000 5ª/6ª Gen, selectores botonera y palanca
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 7.5-7.6, pág. 132-133)

| Display | Significado / acción |
|---|---|
| SELECT en blanco, MONITOR con un rango | Código activo, caja bloqueada en ese rango, CHECK TRANS encendida |
| Rango SELECT parpadeando | Cambio pedido inhibido (temporal o permanente); si la causa no se despeja en 3 s, volver a seleccionar |
| Llave (wrench) encendida | Pronósticos: servicio de aceite, filtro o embragues (ver ficha de pronósticos) |
| Todos los segmentos encendidos > 12 s | El TCM no completó la inicialización (hay DTC asociado) |
| SELECT y MONITOR ambos en blanco | Sin alimentación al selector o falla del enlace **J1939**; blanco continuo = sin alimentación |
| **Doble "cat-eye"** (tras ~12 s en blanco) | Falla de comunicación **J1939** selector–TCM (puede venir con DTC) |
- Modo de emergencia: sin J1939, el selector aún puede pedir **D, N, R por el cable de señal de dirección
  134** (no hay cambios manuales ↑↓ y el display muestra cat-eyes). Acelerar suavemente tras cada cambio de
  dirección para confirmar el sentido de marcha.

## [transmision] Inhibiciones de cambio (parpadeo): regla de 900 rpm y cambio de dirección
- Aplica: Allison 3000/4000 5ª/6ª Gen
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 4.1.3, pág. 51-52)

- **Inhibición por velocidad de motor**: no pasa de N a D o R si el motor está **sobre 900 rpm** (se
  autodespeja si baja dentro de 3 s). Típico en camiones de riego con PTO/acelerador de mano activo.
- **Inhibición de cambio de dirección**: no pasa D↔R si hay velocidad de salida o % de acelerador sobre el límite.
- También puede inhibir N→D/R si el TCM está programado para detectar equipo auxiliar operando (función I/O).
- Siempre aplicar freno de servicio al seleccionar R (puede existir inhibición por freno de servicio).

## [transmision] Nivel de aceite electrónico desde el selector (sensor OLS) – 5ª/6ª Gen
- Aplica: Allison 3000/4000 5ª Gen o posterior con sensor de nivel OLS (estándar en todos salvo 3700 SP y 4700/4800 con retardador; la 4500 RDS con retardador SÍ lo tiene)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 5.8.2, pág. 89-92) ; https://rtsallison.com/Allison%205th_6th%20Gen%20Shift%20Selector%20Booklet_Digital.pdf (PDF pág. 5-6)

1. Superficie nivelada, **N**, freno de estacionamiento, motor en ralentí (500-800 rpm), salida a 0 rpm.
2. Esperar **2 minutos** de asentamiento.
3. Botonera: ↑↓ simultáneo **1 vez**. Palanca: DMD 1 vez.
4. Lectura: "TRANS OIL LEVEL OK"; "**2QT LO**" = faltan 2 cuartos; "**3QT HI**" = sobran 3 cuartos.
   Rango del OLS: **LO 4 a HI 3** (puede faltar/sobrar más que eso). Confirmar un nivel bajo con varilla.
5. Salir: botonera → N; palanca → DMD dos veces (o hasta volver al rango).
Condiciones que el TCM exige (si no, muestra cuenta regresiva o mensaje): fluido entre **40 °C y 104 °C**,
N seleccionado, 2 min detenido, motor en ralentí.
| Mensaje | Causa |
|---|---|
| SETTLING (con cuenta regresiva) | Tiempo de asentamiento insuficiente |
| ENG RPM TOO LO / TOO HI | Rpm motor fuera de rango |
| MUST BE IN NEUTRAL | Seleccionar N |
| OIL TEMP TOO LO / TOO HI | Temperatura del cárter fuera de 40-104 °C |
| VEH SPD TOO HI | Velocidad de salida no es cero |
| SENSOR FAILED / SENSOR ERROR | Falla del sensor OLS → usar varilla y diagnosticar (DTC P070C/P070D) |
El selector de franja (strip) no puede mostrar nivel.

## [transmision] Nivel de aceite con selector 4ª Gen: códigos numéricos de "oL"
- Aplica: Allison 3000/4000 4ª Gen / MY09
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://assets.wellertruck.com/reference-materials/owners-manuals/fourthgenshift-selector-manual.pdf (Allison Shift Selector Operation and Code Manual, pág. 8-9)

Entrada: ↑↓ una vez (botonera) o Diagnostics una vez (palanca). "oL oK" = correcto; "oL Lo 02" = faltan 2 qt;
"oL HI 01" = sobra 1 qt. Si no se puede medir: "oL" + "--" + código:
| Código | Causa |
|---|---|
| 0X (8 a 1, parpadea) | Tiempo de asentamiento muy corto (cuenta regresiva) |
| 50 o EL | Rpm de motor muy baja |
| 59 o EH | Rpm de motor muy alta |
| 65 o SN | Debe seleccionarse neutro |
| 70 o TL | Temperatura del cárter muy baja |
| 79 o TH | Temperatura del cárter muy alta |
| 89 o SH | Velocidad de salida alta |
| 95 o FL | Sensor de nivel de aceite fallado |

## [transmision] Nivel de aceite con varilla: chequeo en FRÍO y en CALIENTE
- Aplica: Allison 3000/4000 Series (todas)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 5.8.1, pág. 84-89)

- **COLD CHECK** (fluido 16-49 °C): solo para confirmar que hay aceite suficiente para arrancar/moverse, **no**
  para ajustar el nivel definitivo. Con motor apagado el nivel estático debe estar cerca de HOT FULL.
  Procedimiento: nivelado, N, freno; motor en ralentí 500-800 rpm; pasar a D y luego R para purgar aire; 1 min en
  N; limpiar alrededor del tubo; varilla limpia, introducir **suelta (sin roscar)**; leer banda COLD.
- **HOT CHECK** (fluido **71-93 °C**): método válido para ajustar. Mismas condiciones; el nivel debe quedar
  en la banda HOT RUN. Medir más de una vez; lecturas inconsistentes = revisar **respiradero (breather)
  tapado**.
- Nivel bajo → cavitación de bomba, aireación, cambios erráticos. Sobre HOT → el aceite toca piezas
  rotatorias, espuma, sobrecalentamiento, pérdida de potencia, aceite saliendo por el respiradero.
- Varilla/tubo 4500 RDS en Mack GR/GU: tubo 23171580 (Mack Sección 4 pág. 15).

## [transmision] Pronósticos (Oil Life, Filter Life, Trans Health): consulta y reseteo desde el selector
- Aplica: Allison 3000/4000 5ª/6ª Gen con paquete de pronósticos habilitado
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://rtsallison.com/Allison%205th_6th%20Gen%20Shift%20Selector%20Booklet_Digital.pdf (PDF pág. 6-8) ; https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN 5.9, pág. 92-97)

Consulta (vehículo nivelado, N, freno aplicado):
| Pulsaciones ↑↓ (o DMD) | Pantalla |
|---|---|
| 1 | Nivel de aceite |
| 2 | **OIL LIFE xx %** (vida de fluido restante; nuevo = 100 %) |
| 3 | **FILTERS OK** o **REPLACE FILTERS** |
| 4 | **TRANS HEALTH OK / LO** (LO = requiere mantención de embragues C1-C5) |
| 5 | Códigos de falla |
Llave (wrench) al dar contacto: se enciende un instante = pronósticos habilitados; encendida fija o
parpadeando = servicio pendiente. Si no se atiende, luego enciende CHECK TRANS.
Reseteo (encendido ON, motor apagado, sin pausas de más de 3 s):
- Oil Life: MODE ~10 s dentro de la pantalla OIL LIFE, o secuencia **N-D-N-D-N-R-N**.
- Filter Life: MODE ~10 s dentro de FILTERS, o secuencia **N-R-N-R-N-D-N**.
- Trans Health: solo con **Allison DOC®** tras reparar embragues.
Habilitar pronósticos (si la calibración lo permite): contacto ON sin arrancar, esperar "N N", secuencia
**N-D-N-R-N-D-N-R-N-D-N-R-N**; la llave se enciende y apaga = habilitado.
Requisitos: cable **118** (interruptor de vida de filtro) en el arnés, fluido TES 295/TES 668/TES 389 y filtros
Allison de alta capacidad. **Si falta el cable 118 queda activo P0848.** Con otro fluido/filtro, apagar pronósticos.

## [transmision] Arranque en frío: límites de rango y precalentamiento
- Aplica: Allison 3000/4000 5ª/6ª Gen
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 3.3, pág. 36-37)

- Bajo **−5 °C** ambiente la caja queda limitada a **2ª, N y R** (3ª en 4700/4800) hasta que el cárter
  supere **−1 °C**.
- Con fluido bajo **10 °C**: para cambiar de sentido pasar siempre por N (D→N→R, R→N→D); si no, puede
  encender CHECK TRANS y quedar en N.
- Temperatura mínima de operación sin precalentar: **TES 295 / TES 668: −35 °C**; **TES 389: −25 °C**.
  Precalentar con calefactor de cárter o 20 min en N en ralentí.
(Relevante en faenas de altura/Calama en invierno.)

## [transmision] Sobretemperatura de la transmisión: umbrales y qué hacer
- Aplica: Allison 3000/4000 5ª/6ª Gen
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 3.4, pág. 38)

- Sobrecalentada si se supera: **cárter 121 °C**, **fluido hacia el enfriador 149 °C**, **salida del
  retardador 165 °C**. Temperatura típica continua de cárter: **93 °C**.
- Nunca más de **10 s a plena carga con la salida detenida** (stall).
- Acción: verificar nivel de aceite; revisar sistema de enfriamiento; si funciona, **1200-1500 rpm en N** 2-3
  min para bajar temperaturas. Si no baja, reducir rpm y detener para inspección.

## [transmision] Retardador hidráulico: reducción de capacidad por temperatura y P273F
- Aplica: Allison 3000/4000 con retardador (4500 RDS con retardador)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 4.3.1, pág. 76-77)

- Retardador > **143 °C**: el TCM adelanta rebajes (preselect) para aumentar flujo por el enfriador.
- > **149 °C**: comienza a reducir capacidad hasta ~**27 %** del máximo (se restablece si la velocidad de salida
  sube 300 rpm sobre la del inicio de la reducción).
- > **166 °C**: se activa la luz de sobretemperatura del retardador (se apaga bajo 159 °C). **Sobre 166 °C por
  10 s seguidos → DTC P273F** (queda inactivo cuando baja de 166 °C por 10 s).
- Cárter > **117 °C** también reduce capacidad; indicador y DTC de sobretemperatura si cárter > 121 °C por 15 min,
  > 128 °C por más de 1 min o llega a 132 °C.
- Temperatura de agua del motor alta también puede reducir capacidad del retardador.
- Retardador desactivado automáticamente en piso resbaloso con ABS; si el retardador **no es autodetectado**, no funciona.

## [transmision] Fluidos aprobados y capacidades 4500 RDS (Mack)
- Aplica: Allison 3000/4000; 4500 RDS en Mack GR/GU
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 5.4, pág. 81) ; https://delivery-p107394-e1241111.adobeaemcloud.com/adobe/assets/urn:aaid:aem:aba4ff74-2839-4f2f-9b64-cf4a5cb30f91/original/as/section-4-transmission-0905.pdf (Mack Sección 4, pág. 2)

- Solo fluidos **TES 295®, TES 668™ o TES 389®** (lista vigente en allisontransmission.com → Service → Fluids).
  TES 295/668 preferidos, aptos para servicio severo e intervalos extendidos; TES 389 es el mínimo.
- 4500 RDS en Mack: con PTO y cárter bajo **45 L (47,5 qt)**; sin PTO cárter bajo **38 L (40 qt)**
  (capacidad sin circuitos externos). Intervalos de cambio: ver biblioteca de intervalos severos (no se repiten aquí).

## [electrico] Allison Gen 5 en Mack GU: alimentación, masas y redes del TCM (conector del vehículo)
- Aplica: Mack Conventional CHU/CXU/GU con Allison 3000/4000 Gen 5, diagrama 2013BP
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (diagrama 21628497, hoja DD "Transmission Control 2/2", pág. 45)

| Pin TCM (A57) | Función |
|---|---|
| 10 y 70 | **B+ alimentación** (desde **F71 "Trans (BATT)" 30/10 A**, bus BATT) |
| 9 y 69 | **B− masa** |
| 63 | **Encendido IGN** (desde **F31 "Trans. spare" 10 A**, bus EMS) |
| 66 / 27 / 67 / 6 / 26 | CAN 2 datalink (red DL2, compartida con el selector J2284 y el conector de diagnóstico): CAN+, CAN−, malla, CAN+, TERM |
| 48 / 8 / 49 / 28 / 7 | CAN 1 datalink (red DL1 = J1939 backbone del camión): CAN+, CAN−, malla, CAN+, TERM |
| 46 | ISO 9141 – herramienta de diagnóstico |
| 32 / 72 | J1708 + / − (interfaz motor) |
| 25 | Salida velocímetro |
Selector "Allison G5 Shift Selector" (A19D): pin 5 B−, 12 IGN, 13 B+, 11 señal de dirección (cable 134),
8 J2284+, 15 J2284− (red DL2, hacia CAN 2 del TCM), 14 malla J1939, 3 dimmer, 6 shift sel 2, 7/16 puente.
Selector con doble cat-eye: revisar pines 8/15 del selector, la red DL2 y los pines 66/27/6 del TCM.
Diagnóstico de P0562/P0882 (voltaje bajo) o TCM muerto: medir tensión en 10/70 respecto a 9/69 con carga,
revisar F71 y F31, y la cadena de relés EMS (ver mack.md).

## [electrico] Allison Gen 5 en Mack GU: entradas/salidas, sensores y solenoides del TCM
- Aplica: Mack Conventional CHU/CXU/GU con Allison 3000/4000 Gen 5, diagrama 2013BP
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hojas DC y DD, pág. 44-45)

Sensores de velocidad (TCM → conector de la caja A58):
| Sensor | Pines TCM (− / +) | Pines conector caja |
|---|---|---|
| Motor (engine) | 39 / 59 | EB / EA |
| Salida (output) | 40 / 60 | OB / OA |
| Turbina | 20 / 80 | TB / TA (4000) ; 14 / 13 (3000) |
Solenoides/interfaz de la caja: TCI-A 15, SS1 51, PCS4 33, PCS3 52, PCS2 36, HSD2 71, PCS1 74, PCS7 78,
PCS5 55, HSD1 11, C3PS 77, TRANS ID 76, temp. cárter 54, 16. Retardador: solenoides 37 (−)/31 (+); temp.
retardador 75; temp. agua 35; RMR 56; TPS PWM 44; alimentación sensores 12.
Entradas digitales: 2 freno motor, 23 RELS, 62 freno de servicio, 42 aux hold, 1 inhibición de rango, 61
habilitación retardador, 21 ABS, 22 cambio directo, 57 preselección freno motor, 17 auto-neutro, 3 retorno de señal.
Salidas: 45 indicación de rango, 4 habilitación freno motor, 13 inhibición de rango, 64 temp. retardador, 24
retardador, 5 velocidad de salida, 65 alarma de reversa, **29 CHECK TRANS**, **30 habilitación PTO**, **41 neutral start**.
Prueba típica de sensor de velocidad: desconectar TCM y caja, medir continuidad de cada par y aislamiento a
masa; comparar lado sensor (valor de resistencia del sensor: no publicado en estas fuentes).

## [electrico] Conector de carrocero Allison X06D (Mack GU) y circuito del retardador
- Aplica: Mack Conventional CHU/CXU/GU con Allison, diagrama 2013BP
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.macktrucks.com/media/files/body-builder/wiring-diagrams/mack-conventional-12volt-includes-us17-version-9-21628497-09-1.pdf (hoja BH "Allison Body Builder Interface", pág. 19 ; hojas DC/DD pág. 44-45)

Conector X06D "Body bldr conn. Allison" → pin del TCM A57: A→1 (inhibición de rango), B→42 (aux hold),
C→2 (freno motor), D→21 (ABS), E→3 (retorno de señal), F→25 (velocímetro), G→62 (freno de servicio),
H→relé Allison B8, J→SPN145NO (relé rango/PTO), K→relé B2, M→relé B3, N→13, P→17 (auto-neutro), R→23,
S→22, T→SPF31A (F31 IGN), U→43, V→5 (velocidad de salida), W→relé A1. L sin uso.
Relés Allison en el arnés: "retarder", "range/pto", "reverse", "PTO enable" y relé de luz de freno del
retardador. Retardador: interruptor S24C ON/OFF, sensor de temperatura B105, módulo A108 "relé retardador"
con presostatos de **4 psi y 7 psi**.
En camiones de riego/aljibe, la bomba accionada por PTO de la Allison se habilita por la salida TCM pin 30
(relé "PTO enable"); si la PTO no engrana, revisar condiciones programadas en el TCM y ese relé.

## [transmision] Aprendizaje adaptativo y autodetección tras reparar/reemplazar TCM
- Aplica: Allison 3000/4000 5ª/6ª Gen
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 8.5-8.6, pág. 142)

- **Autodetección**: el TCM detecta automáticamente la presencia de **retardador de salida** y del **sensor
  de nivel OLS**. Si un retardador presente no es autodetectado, **no funcionará** (y el nivel electrónico no
  estará disponible si el OLS no es detectado).
- **Cambios adaptativos**: el TCM ajusta continuamente cada tipo de cambio (plena carga, carga parcial,
  sin acelerador, subidas, bajadas). Tras reemplazar TCM, recalibrar o reparar embragues se requiere un
  período de manejo variado; la calidad de cada tipo de cambio converge después de **~5 cambios** de ese tipo.
- El reseteo/reaprendizaje forzado y la recalibración se hacen con Allison DOC® (requiere licencia).

## [transmision] Precauciones de soldadura en vehículo con Allison
- Aplica: Allison 3000/4000 (todas)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.kalmarottawa.com/49bee8/globalassets/media/279607/279607_OM8491EN_202109.pdf.pdf (OM8491EN, 11.1, pág. 152)

Antes de soldar (estanques, soportes de carrocería): desconectar los arneses del TCM; desconectar
alimentación y masas del TCM de la batería y las masas de controles electrónicos al chasis; no conectar la
pinza de masa de la soldadora a componentes electrónicos; no soldar sobre ellos; cubrirlos de chispas y calor.
