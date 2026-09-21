# Componentes comunes e implementos — fichas de diagnóstico (flota Pillado)

Alcance: frenos ABS/EBS y aire comprimido, retardadores, tomas de fuerza (PTO), hidráulica de grúa pluma y polibrazo, bombas de agua y combustible de aljibes, sobrellenado óptico, sistema de arranque y carga de 24 V, y normativa DS 160 para camiones tanque.
Investigación: 2026-09-19. Los PDF descargados están en `Manuales/_Investigacion web 2026-09-19/Componentes/<Fabricante>/`, y cada carpeta tiene su `_descargas.json` con la URL de origen.
IMPORTANTE: antes de aplicar una ficha, confirme en terreno la marca, el modelo y el voltaje (12 V o 24 V) del componente instalado. Varias fuentes son norteamericanas y usan sistemas de 12 V; cuando existe el valor para 24 V, la ficha lo indica.

---

## [frenos] WABCO ABS versión E (Meritor WABCO): cómo leer los códigos de parpadeo (blink codes)
- Aplica: camiones con ECU ABS Meritor WABCO versión D/E (norma NA, p. ej. Mack GU813 si trae ABS WABCO; verificar la etiqueta de la ECU). No aplica a los EBS europeos de Mercedes, Volvo, Scania y Renault.
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (Meritor WABCO MM-0112 ABS/ESC E Version, sección 5, págs. 31-35)

Modo diagnóstico (la lámpara ABS entrega el código):
1. Ponga la ignición en ON. Si la lámpara ABS se enciende un momento y luego se apaga, el sistema está OK. Si no se enciende, revise la ampolleta y el cableado. Si queda encendida, hay una falla, una falla de sensor en el último ciclo, códigos borrados sin haber circulado todavía, la ECU desconectada o un problema de alimentación o masa.
2. Mantenga presionado el interruptor de blink code **1 segundo** y suéltelo.
3. Cuente los destellos: primer dígito de 1 a 8, pausa de 1,5 s, segundo dígito de 1 a 6, y pausa de 4 s antes de repetir.
   - Falla **activa**: repite el mismo código hasta que se apaga la ignición. Hay que repararla antes de poder ver otras.
   - Fallas **almacenadas**: muestra cada código una sola vez. La última falla guardada sale primero.
4. El código 1-1 significa que el sistema está OK.

Modo borrado: con la ignición en ON, mantenga el interruptor presionado **al menos 3 segundos**. Si aparecen 8 destellos rápidos seguidos del código de configuración, el borrado se hizo. Si no aparecen los 8 destellos, todavía hay fallas activas. El modo borrado también desactiva el ATC. Después de borrar, la lámpara queda encendida hasta que el camión supera 6 km/h (4 mph).

Si no hay interruptor, se puede usar un puente a masa (back-probe) durante 1 s para leer o 3 s para borrar:
- ECU en cabina: pin 15 del conector X1.
- ECU en chasis con conectores de 12 pines: pin 10 de X1.
- ECU en chasis con conectores de 18 pines: pin 15 de X1.
Los blink codes no son compatibles con el software E8.

## [frenos] WABCO ABS versión E: significado del primer y segundo dígito del blink code
- Aplica: ECU ABS Meritor WABCO versión D/E (verificar en el vehículo)
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (MM-0112, "Blink Code Identification", pág. 36) y https://wabco-mel.s3.amazonaws.com/tp0186_web.pdf (TP-0186)

| 1er dígito (tipo de falla) | 2do dígito (ubicación, para los dígitos 2 a 6) |
|---|---|
| 1 Sin fallas | 1 Delantero derecho (lado vereda) |
| 2 Válvula moduladora ABS | 2 Delantero izquierdo (lado conductor) |
| 3 Entrehierro del sensor excesivo | 3 Trasero derecho, eje motriz |
| 4 Sensor en corto o abierto | 4 Trasero izquierdo, eje motriz |
| 5 Señal de sensor errática o diferencia de neumáticos | 5 Trasero derecho, eje adicional |
| 6 Rueda dentada (tone ring) | 6 Trasero izquierdo, eje adicional |

Primer dígito 7 (función del sistema): 7-1 CAN J1939 o ESC; 7-2 válvula ATC 3/2; 7-3 relé del retardador o del freno motor; 7-4 lámpara ABS; 7-5 configuración ATC; 7-6 válvula de frenado activo de remolque o del eje delantero; 7-7 sensor de presión de freno; 7-8 monitoreo de presión de neumáticos.
Primer dígito 8 (ECU): 8-1 alimentación baja; 8-2 alimentación alta; 8-3 falla interna; 8-4 error de configuración; 8-5 masa; 8-6 acelerómetro RSC o módulo ESC.
Qué revisar según TP-0186: 2-x revisar la válvula moduladora, su cable y conectores. 3-x ajustar el sensor hasta que toque la rueda dentada y revisar el juego de rodamiento y el descentramiento (runout) del cubo. 4-x revisar el sensor, el cable y la resistencia. 5-x revisar diferencias de neumático o de rueda dentada y contactos intermitentes. 6-x rueda dentada dañada. 8-1/8-2 revisar el voltaje del vehículo y la alimentación de la ECU.

## [frenos] WABCO ABS versión E: prueba eléctrica del sensor de rueda
- Aplica: sensores de velocidad de rueda de ABS Meritor WABCO (versión D/E)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (MM-0112, 5.2.1.1 Wheel Speed Sensor Testing, págs. 36-38)

1. Ajuste: empuje el sensor hasta que toque la rueda dentada. No use objetos con filo para empujarlo ni hacer palanca, porque se autoajusta al girar la rueda.
2. Mida la resistencia del sensor solo: debe dar **900-2000 Ω**.
3. Mida el sensor junto con el arnés desde los pines de la ECU: debe dar el mismo valor, con una diferencia de no más de 1 Ω. Si cambia la lectura o está abierto, el problema está en el arnés.
4. Revise el arnés solo: no debe haber continuidad a batería ni a masa.
5. Salida del sensor: al menos **0,2 V AC a 30 rpm**. La tabla de fallas indica girar la rueda a media vuelta por segundo y verificar 0,2 V AC.
6. La resistencia varía con la temperatura. Mida todos los sensores al mismo tiempo y antes de mover el camión.
Pines de la ECU en cabina (Universal/Basic): LF X2-18 pines 12 y 15; RF X2-18 pines 10 y 13; LR X2-18 pines 11 y 14; RR X2-18 pines 17 y 18; LR del tercer eje X3-15 pines 2 y 5; RR del tercer eje X3-15 pines 11 y 14.
ECU en chasis sin ESC: LF X2-negro 7-8; RF X2-negro 5-6; LR X3-verde 1-2; RR X3-verde 3-4.

## [frenos] WABCO ABS versión E: prueba de la válvula moduladora (y diferencia entre 12 V y 24 V)
- Aplica: moduladores ABS Meritor WABCO (versión D/E), 12 V y 24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (MM-0112, 5.2.1.2 Modulator Valve Testing, págs. 38-41)

| Medición | Sistema de 12 V | Sistema de 24 V |
|---|---|---|
| Pin de entrada (inlet, cable café) a masa | 4,0-9,0 Ω | 11,0-21,0 Ω |
| Pin de salida o escape (outlet, cable azul) a masa | 4,0-9,0 Ω | 11,0-21,0 Ω |
| Medido en los pines de la ECU con la válvula conectada | igual, con ±1 Ω de diferencia | igual, con ±1 Ω de diferencia |
| Arnés solo | sin continuidad a batería ni a masa | igual |
Si la lectura supera 9 Ω (o 21 Ω en 24 V), confirme que no midió entre inlet y outlet. Si los pines son los correctos, limpie los contactos del modulador y vuelva a medir.

## [frenos] WABCO ABS versión E: válvula de frenado activo (ABV) y válvula ATC
- Aplica: ECU ABS Meritor WABCO versión E con ATC, RSC o ESC
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (MM-0112, 5.2.1.4, pág. 44) y https://wabco-mel.s3.amazonaws.com/tp0186_web.pdf

- Solenoide ABV 3/2 (entre la alimentación y el común de la ABV): **7,0-14,0 Ω en 12 V** y **26,3-49,0 Ω en 24 V**. Con el arnés conectado debe dar el mismo valor, con una diferencia de no más de 1 Ω. El arnés solo no debe tener continuidad a batería ni a masa.
- Válvula ATC (TP-0186, 12 V): 7,0-14,0 Ω.
- Sensor de presión de freno (código 7-7): debe recibir 8,0-16,0 V de alimentación (TP-0186). Revise también el interruptor de luz de freno.

## [frenos] WABCO ABS: la lámpara no responde al blink code (condiciones de voltaje)
- Aplica: ECU ABS Meritor WABCO versión D/E, 12 V y 24 V
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (MM-0112, Tabla B "Blink Code Conditions", pág. 35)

- Si la lámpara ABS no se apaga al activar el blink code, el voltaje está fuera del rango **9,5-14,0 V (12 V) o 18-32 V (24 V)**. Mida el voltaje y revise las conexiones.
- Si no aparecen los 8 destellos después de mantener 3 s, el interruptor no se sostuvo el tiempo correcto (1 s lee, 3 s borra), hay cableado defectuoso o quedan fallas activas.
- TP-0186 indica que la alimentación de la ECU debe estar entre 9,0 y 16,0 V en sistemas de 12 V.

## [frenos] Bendix EC-60: modos del interruptor de blink code y cómo leer los códigos
- Aplica: ECU ABS Bendix EC-60 (camiones de norma NA, p. ej. Mack GU813 si trae Bendix; verificar la etiqueta de la ECU)
- Tipo: lectura_codigos_tablero
- Confiabilidad: oficial
- Fuente: https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (Bendix SD-13-4869, págs. 21-26)

Cuántas veces presionar el interruptor, con el vehículo detenido:
- 1 vez: códigos activos.
- 2 veces: códigos inactivos.
- 3 veces: borrar códigos activos. También sale del modo dinamómetro.
- 4 veces: chequeo de configuración.
- 5 veces: modo dinamómetro (desactiva ATC y ESP).
- 7 veces: reconfigurar la ECU. Para esto hay que mantener el interruptor presionado antes de dar ignición.
Pausa entre dígitos: 1,5 s. Pausa entre mensajes: 2,5 s. Si la ECU detecta movimiento del vehículo, sale del modo blink code.
Índice del primer dígito:
- 1: sin DTC.
- 2 a 5, 14 y 15: sensores de rueda. 2 dirección izquierdo, 3 dirección derecho, 4 motriz izquierdo, 5 motriz derecho, 14 y 15 eje adicional.
- 6: alimentación eléctrica.
- 7 a 10, 16 y 17: moduladores (PMV).
- 11: J1939.
- 12: misceláneos.
- 13: ECU.
- 18: válvula de control de tracción (TCV) del eje motriz.
- 19: TCV del eje de dirección.
- 20: PMV del remolque.
- 21: sensor de ángulo de dirección.
- 22: sensor de guiñada.
- 23: sensor de aceleración lateral.
- 24: sensores de demanda de freno o de carga.

## [frenos] Bendix EC-60: valores de prueba del sensor de rueda, modulador PMV y alimentación
- Aplica: ECU ABS Bendix EC-60 (sistema de 12 V según la hoja de datos)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://n0c357rmy1njbuit2friqwu.blob.core.windows.net/documents/VcCA4sr2I0EBhB_SD-13-4869_US_004.pdf (SD-13-4869, págs. 27-31)

- Sensor de rueda: **1500-2500 Ω**, sin continuidad a masa ni a voltaje, y salida **>0,25 V AC** girando la rueda a unas 0,5 rev/s. El DTC del sensor se mantiene hasta ciclar la alimentación de la ECU y circular a más de 15 mph (24 km/h), o hasta borrarlo con el interruptor o la herramienta.
- Modulador PMV Bendix: **4,9-5,5 Ω** entre REL y CMN, y también entre HLD y CMN. **9,8-11 Ω** entre REL y HLD. Sin continuidad a masa ni a voltaje.
- Alimentación: ponga una carga, por ejemplo una ampolleta 1157, y mida en el conector de la ECU. Ignición a masa y batería a masa deben dar **9-17 V DC**. En la ECU de cabina, conector X1 de 18 vías: pin 1 masa, pin 3 ignición, pin 16 batería.
- Nota: los valores de Bendix son distintos de los de WABCO (900-2000 Ω). Use siempre los de la marca de la ECU instalada.

## [frenos] Prueba "chuff" de moduladores ABS (sin scanner)
- Aplica: ABS Bendix EC-60/EC-80. Como referencia general, también sirve para cualquier ABS con autotest de moduladores al dar contacto.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.bendixvrc.com/itemDisplay.asp?documentID=7270 (Bendix Air Brake System Troubleshooting BW7270, Test 3)

Con el sistema de aire a plena presión, el motor detenido y el freno de estacionamiento liberado, mantenga pisado el pedal de freno y dé ignición. Cada solenoide de modulador se energiza un instante y debe escucharse un "chuff" corto y seco. El orden en EC-60/EC-80 es: 1 dirección derecho, 2 dirección izquierdo, 3 motriz derecho, 4 motriz izquierdo, 5 adicional derecho, 6 adicional izquierdo y 7 TCV del eje motriz. Luego el patrón se repite. La prueba solo se hace con el vehículo detenido. Si un modulador no suena, revise su conector, mida la resistencia (ver la ficha de EC-60) y revise la línea de aire.

## [frenos] Prueba del sistema de aire: gobernador, advertencia de baja presión y tiempo de carga
- Aplica: toda la flota (frenos neumáticos). Los valores son los de Bendix para vehículos norteamericanos. En los camiones europeos, use la presión de corte del APU/secador del fabricante (ver ficha WABCO APU).
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.bendixvrc.com/itemDisplay.asp?documentID=7270 (Bendix BW7270, Test 1 y Checklist 1)

1. Vacíe todos los estanques a 0 psi. Arranque el motor y déjelo en ralentí acelerado. La advertencia de baja presión debe estar encendida.
2. La advertencia debe apagarse **sobre 60 psi (4,1 bar)**.
3. Tiempo de carga: de **85 a 100 psi en 40 s o menos**.
4. Corte del gobernador (cut-out): normalmente **125-135 psi**, o el valor que indique el manual del vehículo.
5. Baje la presión hasta el reenganche (cut-in). La diferencia entre cut-in y cut-out **no debe superar 30 psi**.
Si falla:
- Si la advertencia se activa bajo 60 psi, verifique el manómetro con uno patrón y cambie el interruptor de baja presión.
- Si la carga demora más de 40 s: filtro o línea de admisión del compresor restringidos, carbón en la descarga (busque la causa del exceso de temperatura) o fuga en el descargador (unloader). Con el sistema cargado, se escucha en la admisión.
- Si el corte está fuera de rango, verifique con un manómetro patrón y revise el descargador antes de ajustar o cambiar el gobernador.

## [frenos] Prueba de fugas del sistema de aire (estático y con freno aplicado)
- Aplica: toda la flota (frenos neumáticos)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.bendixvrc.com/itemDisplay.asp?documentID=7270 (Bendix BW7270, Test 2, Test 4, Checklists 2 y 4)

Prueba estática (Test 2): con las ruedas calzadas, a plena presión y con los frenos de estacionamiento liberados, espere 1 min para que se estabilice y observe 2 min.
Prueba con freno aplicado (Test 4): con el motor detenido, aplique y mantenga 80-90 psi en el pedal. Espere 1 min y observe 2 min.
Caída de presión permitida en cualquiera de los estanques de servicio:
| Configuración | Máximo en 2 min |
|---|---|
| Camión solo | 4 psi |
| Tracto + 1 remolque | 6 psi |
| Tracto + 2 remolques | 8 psi |
Dónde buscar la fuga (use detector o agua jabonosa):
- Lado de suministro: líneas y fittings, purgas, interruptores de baja presión, válvulas relé de servicio y de freno de resorte, válvula de pie doble, válvula de mano del remolque, válvula de estacionamiento, válvula de seguridad del estanque o del secador, gobernador y línea de descarga del compresor.
- Lado de servicio: fittings, interruptor de luz de freno, válvula de control de remolque, válvula de pie, válvula de protección del tracto, válvula doble retención, relés de servicio y diafragmas de cámaras.

## [frenos] Carrera de vástago de cámaras de freno: límites CVSA
- Aplica: toda la flota con cámaras de freno tipo 12 a 36 y ajustadores (slack) automáticos
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.bendixvrc.com/itemDisplay.asp?documentID=7270 (Bendix BW7270, Test 4, tabla CVSA)

Mida con el freno de estacionamiento liberado y 80-90 psi aplicados en las cámaras. El ángulo entre el vástago y el slack debe ser de 90° o algo menos, e igual en ambos lados del eje.
| Cámara | 12 | 12L | 16 | 16L | 20 | 20L | 20L3 | 24 | 24L | 24L3 | 30 | 30L | 36 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Carrera nominal | 1-3/4" | 2-1/4" | 2-1/4" | 2-1/2" | 2-1/4" | 2-1/2" | 3" | 2-1/4" | 2-1/2" | 3" | 2-1/2" | 3" | 3" |
| Límite CVSA | 1-3/8" | 1-3/4" | 1-3/4" | 2" | 1-3/4" | 2" | 2-1/2" | 1-3/4" | 2" | 2-1/2" | 2" | 2-1/2" | 2-1/4" |
(Tabla reconstruida desde el texto del PDF. Si hay dudas, compárela con la tabla impresa del BW7270.) Si la carrera excede el límite, busque la causa raíz. Bendix advierte que no se debe ajustar a mano un slack automático que dejó de ajustar, porque eso no corrige la falla de fondo.

## [frenos] Secador de aire WABCO System Saver 1200/1800: ciclo normal y prueba operacional
- Aplica: secadores WABCO System Saver 1200/1800 (cartucho simple). Revise en terreno qué secador tiene cada camión.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm34_web.pdf (Meritor WABCO MM-34, rev. 03.2020, págs. 3 y 31-32)

- El gobernador enciende el compresor (cut-in) entre **100 y 110 psi** y lo apaga (cut-out) entre **120 y 130 psi**, según su ajuste. En la prueba operacional el corte queda en unos **120-140 psi**.
- Al descargar el compresor, el secador purga con un soplido fuerte seguido de un flujo suave de **10-45 s**.
- En los modelos de regeneración, el estanque de suministro y el secundario bajan **cerca de 10 psi** durante la regeneración (10-35 s). Eso es normal.
- Si el secundario cae **25 psi o más** durante la regeneración sin otros consumos, hay fugas o la válvula de retención controlada por presión (PCCV) falla. Limpie las válvulas de regeneración y de retención de salida, y revise el compresor y el gobernador.
- Si no hay caída de presión: la PCCV no está instalada o está en el estanque equivocado, hay otra válvula de retención entre el secador y el secundario, o el manómetro secundario no está conectado al circuito secundario.
- No confíe en los manómetros de la cabina: instale un manómetro calibrado de ±1 psi en el estanque secundario.
- Mantención: verifique cada semana que purgue y drene los estanques. Cambie el desecante cada 2-3 años o antes, según el uso y el estado del compresor, y siempre que se reconstruya el compresor.

## [frenos] Secador WABCO System Saver: fuga por la válvula de purga y regeneración demasiado larga
- Aplica: secadores WABCO System Saver 1200/1800
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm34_web.pdf (MM-34, Tabla D, págs. 25-26)

- **Fuga por la válvula de purga con el compresor cargando** (el compresor cicla en exceso o no sube la presión): válvula de purga congelada abierta, suciedad bajo el asiento (partículas de fittings o de la línea de entrada), arandela de purga invertida, línea equivocada conectada a la puerta 4 (unloader), anillo seguro de la purga mal asentado o válvula de retención de salida que no sella.
- **Regeneración de más de 30 s con pérdida de presión en el estanque de suministro**: la válvula de regeneración no corta el flujo.
- En calor extremo, la línea de descarga del compresor debe ser lo bastante larga para que el aire entre al secador bajo **80 °C (175 °F)**. En frío, mantenga limpia de aceite y agua la línea del gobernador a la puerta 4.

## [frenos] Secador WABCO System Saver: prueba del calefactor (12 V y 24 V)
- Aplica: secadores WABCO System Saver con calefactor
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm34_web.pdf (MM-34, "Heater Resistance", pág. 30)

1. Desconecte el arnés del calefactor y mida entre los dos pines del lado del secador: **1,0-2,0 Ω si es de 12 V** y **5,0-7,0 Ω si es de 24 V**.
2. Si mide menos de 1,0 Ω (12 V) o menos de 5,0 Ω (24 V), cambie el calefactor.
3. El termostato solo cierra en frío, bajo 35 °F (1,7 °C). Sobre esa temperatura el calefactor puede leer abierto sin estar malo.
4. Con el multímetro en voltios, mida en el conector del arnés. Si la lectura es anormal, revise el arnés y el fusible.
Prueba de fugas del secador: cargue hasta el corte y aplique agua jabonosa en todas las conexiones. Si hay fuga, drene, desarme, revise hilos y grietas, aplique sellador y repita.

## [frenos] WABCO APU (unidad de preparación de aire europea): presiones de corte, válvula de seguridad y válvula de protección de 4 circuitos
- Aplica: WABCO Air Processing Unit 932 500 xxx 0 (camiones europeos, típico de Mercedes Actros/Axor; verifique el número de parte en la placa del APU)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/8150004983.pdf (WABCO 815 000 498 3 Test and Adjustment Instructions APU, 2005, págs. 6-8 y 21)

Según la tabla de variantes de APU del documento (el valor depende del número de parte):
- Presión de corte del regulador (pCUT-OFF): **12,5 bar o 10 bar**, según la variante.
- Válvula de seguridad del secador: se abre a **14,5 +2,5 bar**. Algunas variantes tienen la válvula de seguridad a 10 bar y un corte de 8,5 bar.
- Válvula de protección multicircuito (MKSV): apertura de circuitos 1+2 a **9,0 bar** y de circuitos 3+4 a **7,5 bar**. Cierre de circuitos 1+2 a **>7,0 bar** y de circuitos 3+4 a **>4,5 bar**.
- Calefactor del cartucho: controlado por un bimetal que se conecta a unos **+7 °C** y se desconecta a unos **+30 °C**. Al energizarlo con 24 V DC debe consumir **3,9-4,2 A** al inicio y luego cortar solo (0 A).
- Torque de unión entre el secador y la válvula multicircuito: 20+4 N·m.
Nota: son pruebas de banco. En el camión, compare el corte y los cierres con un manómetro patrón en las tomas de prueba. Para parámetros específicos del vehículo se requiere licencia de XENTRY/WIS (Mercedes).

## [frenos] WABCO APU: prueba de los sensores de presión de los circuitos de freno
- Aplica: WABCO APU 932 500 xxx 0 con sensores de presión (pantalla de presiones de los circuitos 1 y 2)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/8150004983.pdf (815 000 498 3, cap. 7, págs. 36-38)

- Pines: 6.2 señal del circuito 1; 6.3 alimentación del circuito 1 (5 V o 24 V); 6.4 masa del circuito 1. 6.5 señal del circuito 2; 6.6 alimentación del circuito 2; 6.7 masa del circuito 2.
- Sin presión, la señal debe ser de unos **1 V**.
- Con presión, la señal sigue la fórmula **U = p/4 + 1 V** (p en bar). Ejemplo: 11 bar dan 11/4 + 1 = **3,75 V**.
- Los sensores sirven para mostrar la presión en el tablero y activar los testigos. No afectan el funcionamiento neumático del APU.

## [frenos] WABCO EBS3 (camiones europeos): autodiagnóstico, cuándo medir y modo banco de rodillos
- Aplica: camiones con WABCO EBS3 (típico de Mercedes Actros/Axor y otros europeos; verificar). El diagnóstico con DTC requiere XENTRY (Mercedes), Tech Tool (Volvo/Renault), SDP3 (Scania) o WABCO TOOLBOX/W-EASY.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.wabco-customercentre.com/catalog/docs/8150102083.pdf (WABCO EBS3 System Description 815 010 208 3, cap. 8 y 9, págs. 31-38)

- El EBS vigila los sensores del transmisor de freno (señales PWM y switches), los sensores de presión de los moduladores de eje y de la válvula de remolque, los sensores de desgaste de balatas, los solenoides y el CAN (bus de sistema y bus del vehículo). También compara la presión izquierda contra la derecha de cada eje y la presión del eje trasero contra la del delantero en el respaldo neumático.
- El cableado de los sensores de presión y de los solenoides internos de los moduladores **no es accesible**. Los componentes EBS no se reparan: se reemplaza el componente completo.
- **Solo mida resistencias o voltajes en el arnés cuando el sistema indique una falla y el software de diagnóstico lo pida.**
- Masa: la resistencia entre las partes metálicas de los componentes y el chasis debe ser **menor a 10 Ω**.
- Modo banco de rodillos: con la ignición apagada, pise el pedal de freno para activar el sistema y luego dé ignición y arranque el motor. Se sale del modo al superar 3 km/h en ambos ejes o 12 km/h en un eje. Si el voltaje de a bordo está bajo, la ECU puede resetearse al arrancar y salir del modo.
- Si se cambia el tamaño de neumático o la carga por eje, hay que reparametrizar con el fabricante.

## [frenos] WABCO EBS 3.1 (norma NA): lectura de DTC por J1939 con TOOLBOX
- Aplica: WABCO EBS 3.1 en camiones de norma NA (si alguna unidad Mack o Volvo NA lo trae)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.zf.com/products/media/automotive/cv/literature_downloads_wna/truck_solutions/abs__ebs___habs_technical_publications/TP15143_web.pdf (WABCO TP-15143 EBS 3.1 Repair Guide, págs. 4-5)

El EBS 3.1 **solo se comunica por J1939**. En TOOLBOX, verifique el protocolo en "Utilities". La pantalla de DTC entrega la descripción, el número de ocurrencias, el SPN y el FMI, junto con instrucciones básicas de reparación. Con "Clear Faults" solo se borran los códigos almacenados. Las tablas SPN/FMI con sus reparaciones están en el mismo documento, desde la página 12.

## [frenos] Retardador electromagnético Telma: controles periódicos y cuidados
- Aplica: retardadores Telma (Axial/Focal), si alguna unidad los tiene (levantar en terreno)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.telma.com/documents/gestion/operation_manual_telma.pdf (Telma retarder operations manual, págs. 13-15)

- Palanca manual: 0 = sin retardo; 1 = 25 %; 2 = 50 %; 3 = 75 %; 4 = 100 %. Hay que devolverla a 0 al detenerse.
- Controles: primero a los **5.000 km**, luego **cada 50.000 km o una vez al año**, lo que ocurra primero.
  - Mecánicos: juego axial del eje del retardador, de la salida de la caja y del puente; torques de fijación; suspensión auxiliar y soportes de goma; fugas de grasa por los retenes; entrehierros (air-gaps), ajustándolos si hace falta.
  - Eléctricos: prueba funcional completa del mando; estado de cables y tapas de terminales.
- Antes de intervenir, corte la alimentación del sistema. Antes de reconectarla, deje todos los mandos en OFF.
- Lavado: mantenga al menos 1 m de distancia, no dirija el chorro a las bobinas, use **≤25 bar y ≤50 °C** y no use químicos. Mantenga limpios los ductos de ventilación del rotor y el espacio entre bobinas, porque el barro y el polvo son críticos en faena.

## [frenos] Retardador hidráulico Voith 115 HV: qué se sabe públicamente
- Aplica: Mercedes-Benz Actros/Axor con retardador Voith (VR 115 HV). Confirmar en terreno qué unidades lo tienen.
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.driventic.com/products/truck/retarder (la línea de retardadores de camión de Voith ahora es Driventic; la página de voith.com redirige ahí)

- Es un retardador secundario multiplicador con suministro de aceite propio, independiente de la caja. Disipa la energía de frenado en el circuito de refrigeración del motor. Se integra al vehículo con el control VERA (limitador y cruise control).
- El manual de servicio (Aftersales Service Manual) y la lectura de códigos de destello **no están publicados por el fabricante**. Las copias que circulan en sitios de terceros no están autorizadas. El diagnóstico se hace con XENTRY (Mercedes) o con el servicio Voith/Driventic, lo que **requiere licencia o servicio autorizado**.
- Práctica de campo sin valores: si el retardador reduce su potencia por temperatura, revise el nivel y estado del refrigerante del motor, el radiador (polvo) y el nivel de aceite del retardador.

## [transmision] PTO eléctrica sobre aire o hidráulica: "no engancha" (guía de solenoide Muncie)
- Aplica: PTO Muncie serie FA/FR/CS/GA/GM con solenoide de 12 V. En camiones de 24 V, confirme el voltaje del solenoide instalado y use los datos de su fabricante.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.munciepower.com/cms/files/Products/Literature/Documents/Troubleshooting/TRG08-04.pdf (Muncie TRG08-04 Power Take-Off Solenoid Troubleshooting Guide)

| Síntoma | Causa probable | Corrección |
|---|---|---|
| No engancha (eléctrico sobre aire) | Presión de aire insuficiente | Medir la presión de aire en la PTO y revisar el circuito contra el diagrama de instalación |
| No engancha (eléctrico sobre hidráulico) | Presión hidráulica insuficiente | Medir la presión en la PTO y compararla con el manual de instalación |
| No engancha | Cartucho del solenoide doblado (la PTO quedó muy cerca de un objeto sólido) | Cambiar el solenoide y dar holgura |
| No engancha | Voltaje insuficiente en el solenoide (mínimo **10,2 V**, máximo **14 V** DC) | Medir con multímetro y confirmar la masa |
| No engancha | Bobina abierta o en corto | La bobina debe medir **8,5-10 Ω** y consumir **1,2-1,4 A** |
| Fusible de 10 A quemado | Bobina en corto | Medir la resistencia y cambiar |
| Lectra-Shift (fusible de 40 A) | Bobina ENGAGE o HOLD | ENGAGE (cable blanco a masa) **0,3-0,5 Ω**; HOLD (cable rojo a masa) **4,7-5,9 Ω**; entre rojo y blanco, la suma de ambas |
| No desengancha | Suciedad en el solenoide o en el filtro, o las causas anteriores | Limpiar y lavar las mangueras |

## [transmision] PTO Chelsea (Parker) accionada por aire: válvula de protección, holgura y mantención
- Aplica: PTO Parker Chelsea de 6 y 8 pernos (serie 100, 221, 260, 442, 489, 660, 680, 812, etc.)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://assets.wellertruck.com/reference-materials/owners-manuals/chelsea-owners-manual-power-take-offs.pdf (Parker Chelsea HY25-1135-M1/US Owner's Manual, págs. 26-27, 44 y 51)

- El kit de cambio por aire lleva una **válvula de protección de presión que abre a 60-70 psi** (kit 378414; en otro esquema, a 70 psi). Si el circuito de frenos está bajo esa presión, la PTO **no recibe aire y no engancha**. Esto es normal y protege los frenos.
- En transmisiones automáticas, detenga el mando de la PTO antes de cambiar de marcha.
- Holgura (backlash) al montar: **0,006"-0,012" (0,15-0,30 mm)**, ajustada con empaquetaduras. Una empaquetadura de 0,010" cambia la holgura unos 0,006", y una de 0,020" la cambia unos 0,012".
- Mantención: cada día, revise los mecanismos de aire, hidráulicos y de trabajo antes de operar. Cada mes, revise fugas, reapriete el anclaje y lubrique las estrías.
- Bombas de montaje directo: use grasa antifretting (tubo 379688 o cartucho 379831). Las estrías oxidadas o desgastadas del eje de la bomba indican fretting por vibración torsional. Si la PTO trabaja muchas horas, hay que re-engrasar con más frecuencia.

## [transmision] Procedimiento de conexión de la PTO en un aljibe de agua (fabricante nacional Tremac)
- Aplica: aljibes de agua con PTO y bomba de engranajes que mueve un motor hidráulico acoplado a la bomba centrífuga (Tremac 20/25/30 m³). Sirve como referencia para aljibes de configuración similar.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://asesor.kaufmann.cl/uploads/multimedium/name/13813/MANUAL_DE_INSTRUCCION_Y_MANTENIMIENTO_TANQUE_ALJIBE_SOBRE_CAMION_20_25_Y_30_M3.pdf (Tremac, Manual de instrucción y mantenimiento tanque aljibe, págs. 9-11)

1. Arranque con el embrague a fondo (caja mecánica) o con el freno pisado (automática). La caja debe estar en neutro (mecánica) o en P (automática).
2. Suelte el embrague y verifique que la **presión neumática esté sobre 8 bar**.
3. Con el motor en ralentí, pise el embrague, **espere 5 s** y active la PTO. Luego suelte el embrague suavemente.
4. Suba las rpm hasta un **máximo de 1500 rpm**.
5. Para regar en movimiento, conecte la PTO primero y después la marcha. Para cambiar de marcha con la PTO conectada, active la válvula derivadora (V.D.) para quitar la carga.
6. Las PTO para cajas automáticas son de multidisco y la presión de conexión **siempre debe estar sobre 8 bar** para que no se desgasten antes de tiempo.
7. La válvula de bola VB5, que alimenta la bomba, debe estar abierta, porque la bomba centrífuga nunca debe trabajar sin agua.

## [transmision] Mack (VECU): por qué la PTO o el acelerador de trabajo no se activan (condiciones programables)
- Aplica: Mack GU813 (VECU, mDrive). Revise los parámetros con Premium Tech Tool.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: Mack Body Builder Instructions, Section 9 Power Take-off (PTO), USA190535581, 9.2025, págs. 3-4 y 91-100. Portal: https://www.macktrucks.com/parts-and-service/body-builders/ (copia local en `_Descargados oficiales 2026-09/Mack/Mack GU Granite Body Builder Seccion 9 - PTO y parametros VECU4.pdf`)

- EHT/PTO 0 (acelerador electrónico de mano): se opera con los botones del cruise control (ON/OFF, SET/Decel, RESUME/Accel). La VECU entra al modo PTO **solo si se cumplen las condiciones programadas**: velocidad máxima del vehículo, freno de estacionamiento aplicado o no, rango de rpm, etc.
- Salida de habilitación de la PTO: la VECU puede **bloquear el enganche** del equipo auxiliar hasta que se cumplan las condiciones (freno de estacionamiento, rpm dentro de rango). Con mDrive, la VECU recibe la entrada PTO 1 y habilita la PTO de la caja por J1939 a través de la TECU. Si el interruptor está bien pero la PTO no engancha, revise el estado del freno de estacionamiento, la velocidad y las rpm, y compárelos con los parámetros.
- Hay "dropouts" temporales, que vuelven a la velocidad fijada, y estándar, que exigen reiniciar el interruptor.
- Con mDrive, detenido, **no se permiten las marchas crawler** para operar la PTO. Si la PTO supera **100 hp (75 kW) durante 15 min**, necesita enfriador de aceite.

## [hidraulica] Régimen de motor recomendado según la potencia de la PTO y cálculo de caudal
- Aplica: toda la flota con bomba hidráulica en la PTO (grúa, polibrazo, aljibes con motor hidráulico)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: Mack Body Builder Instructions Section 9 PTO USA190535581 (9.2025), págs. 56-70. Portal: https://www.macktrucks.com/parts-and-service/body-builders/ (copia local en `_Descargados oficiales 2026-09/Mack/`)

| Potencia de la PTO | < 40 hp (30 kW) | 42-67 hp (31-50 kW) | 68-94 hp (51-70 kW) | > 95 hp (71 kW) |
|---|---|---|---|---|
| Rpm de motor recomendadas | 700-800 | 800-900 | 900-1000 | > 1000 |
- Velocidad de la bomba: n = rpm del motor × razón de la PTO (Z). Ejemplo del documento: 800 × 1,53 = 1200 rpm. No exceda la velocidad máxima de la bomba que indica su fabricante.
- Potencia: P = Q × p / (1680 × η), con Q en L/min, p en bar y η cerca de 0,95.
- Una línea de presión de diámetro insuficiente genera calor. Ejemplo del documento: 113,5 L/min (30 gpm) con 9,65 bar (140 psi) de caída producen cerca de 1,7 kW (5800 BTU).
- Una bomba de pistones rinde cerca del 97 % a unas 1000 rpm y calienta menos que una de engranajes.

## [hidraulica] Cavitación de la bomba hidráulica: requisitos de succión, estanque, filtros y aceite
- Aplica: toda la flota con bomba hidráulica en la PTO (grúa, polibrazo, aljibes con motor hidráulico)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: Mack Body Builder Instructions Section 9 PTO USA190535581 (9.2025), págs. 55-57. Portal: https://www.macktrucks.com/parts-and-service/body-builders/

- Las velocidades máximas de autosucción del catálogo valen con **1,0 bar absoluto** en la entrada. Para cumplirlas se necesita el aceite unos **0,5 m sobre la entrada de la bomba**, línea de succión bien dimensionada, el niple de succión original y un estanque correcto.
- La velocidad en la línea de succión debe ser **< 1 m/s**. Una mala alimentación produce **cavitación**, ruido, vida corta y, en el peor caso, la falla de la bomba.
- Estanque de **1,5 veces el caudal nominal de la bomba** (L/min), con suficiente superficie de desaireación. El nivel de aceite siempre debe estar sobre la puerta de succión.
- Filtro de retorno dimensionado para unas 2 veces el caudal de la bomba: **28 µm** para 0-200 bar y **10 µm** para 200-300 bar. Cámbielo al menos una vez al año. El filtro de aire del estanque debe tener la misma finura que el filtro de retorno.
- Aceite: HLP (DIN 51524), ATF Dexron II o aceite de motor API CD, con viscosidad de **20-30 cSt**. No mezcle calidades. Al llenar, purgue el aire de la carcasa de la bomba por la puerta de purga superior.
- La bomba nunca debe girar sin flujo de aceite en el sistema.

## [implemento] Polibrazo Palfinger (hooklift): bomba, rpm de trabajo, estanque y mando neumático
- Aplica: hook loaders Palfinger T8-T30 (polibrazo 20 t). Referencia general para otros polibrazos.
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://media.adtorqueedge.com/palfinger-nz/brochures/installation-information/palfinger-nz-hookloader-installation-manual-2024.pdf (Palfinger NZ Hook Loader Installation Manual 2024, cap. 5 y 6, págs. 44-56)

- Bombas: de engranajes, **por regla general hasta 230 bar como máximo**; de pistones, para presiones mayores.
- Rpm de trabajo del motor: normalmente **800-1200 rpm**. Con una PTO de razón 1:1 se recomiendan **1000 rpm**, y el régimen debe ser **constante**. Nunca supere las rpm permitidas de la bomba.
- Caudal recomendado a 1000 rpm del motor: T8-T10 (válvula SD8) **41 L/min**. T15-T22A **63 L/min**. T20-T30 con válvula SDS150 **80 L/min** y con SDS180 **108 L/min**. Estanques de referencia: 50 L, 100 L, 100 L y 140 L.
- Volumen del estanque: **1,15 a 1,5 veces el caudal de la bomba** (L/min).
- Mando neumático de pilotaje: presión máxima de **15 bar**, regulada a **8 bar** con el regulador que viene con el equipo. **Nunca conecte la alimentación neumática al circuito de frenos.** Ajuste los reguladores de velocidad del bloqueo de contenedor para que la palanca se mantenga 3 s.
- Las válvulas de control se pilotean por aire. Las palancas manuales son solo de emergencia y, al usarlas, el sistema de seguridad del equipo normalmente queda anulado.

## [implemento] Polibrazo Hyva Titan: requisitos de presión de la bomba
- Aplica: hook loaders Hyva Titan (polibrazo)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.hyva.com/globalassets/hkl-0002titan-hookloader-installation-manual_ml.pdf (Hyva HKL-0002 Titan Hookloader Installation Manual, rev. AD 10-02-2025, sección 5.2, pág. 23)

La bomba del polibrazo Hyva Titan atornillable debe cumplir:
| Parámetro | Valor |
|---|---|
| Presión peak máxima | 400 bar |
| Presión intermitente máxima | 350 bar |
| Presión continua máxima | 280 bar |
- El caudal exacto sale de la razón de la PTO, las rpm del motor y el desplazamiento de la bomba (ver la hoja de especificaciones del modelo).
- Verifique que la PTO tenga torque suficiente para el polibrazo.
- Ponga el estanque lo más cerca posible de la bomba para que la succión sea corta.

## [implemento] Grúa telescópica IMT: tabla de fallas de operación
- Aplica: grúas IMT telescópicas (camión pluma; IMT JPZV-22 u otros)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514 Telescopic Crane Vol. 1, 1-11-1 Troubleshooting, pág. 1-15)

| Problema | Causa | Solución |
|---|---|---|
| Los estabilizadores no funcionan | La grúa no tiene potencia hidráulica | Enganchar la PTO |
| El control remoto de radio no funciona | Paro de emergencia presionado o batería del control descargada | Tirar el botón de paro o cambiar por una batería cargada |
| El control con cable no funciona | Selector "Power" no está en "Crane", cable desconectado o control roto | Poner el selector en Crane, conectar el cable o usar los botones del banco de válvulas para plegar |
| No bajan la pluma, no sale la extensión y no sube el winche | La grúa está en two-block (gancho contra la punta) o en sobrecarga | Bajar el winche; o subir la pluma, retraer la extensión o bajar el winche para salir de la sobrecarga |
| Falla el control remoto (golpe, batería) | — | Usar el respaldo del control remoto |

## [hidraulica] Grúa IMT: válvula de alivio, vacío en la succión y cambio de filtros
- Aplica: grúas IMT (camión pluma)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514, 2-5-7 y 2-5-9, pág. 2-8)

- La presión de la válvula de alivio viene fijada y **sellada de fábrica**. No debe manipularse. Solo un representante IMT puede ajustarla y resellarla, y si el sello se rompe se pierde la garantía. Ajustarla por sobre lo especificado es inseguro.
- Vacuómetro del filtro de succión: si marca **más de 8 in Hg**, hay riesgo de **cavitación** y daño a la bomba. Cambie el elemento.
- Filtros: primer cambio a las **50 h** en un equipo nuevo y luego **cada 200 h**. También a las 50 h después de reparar un componente hidráulico mayor.
- Para cambiar el filtro de succión, cierre primero la válvula de compuerta del estanque. Después ábrala, enganche la PTO y revise fugas.

## [hidraulica] Grúa IMT: síntomas por viscosidad incorrecta y temperatura del aceite
- Aplica: grúas IMT. Criterio general para la hidráulica de implementos.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514, 2-5-10 Hydraulic System Troubleshooting, págs. 2-8 y 2-9)

- **Aceite demasiado liviano**: fugas excesivas, menor rendimiento volumétrico de la bomba, más desgaste, **pérdida de presión**, falta de control positivo y menor eficiencia.
- **Aceite demasiado pesado**: más presión, **más temperatura**, operación lenta, baja eficiencia mecánica y más consumo de potencia.
- En ambos casos hay que cambiar el aceite.
- Mantenga la temperatura del sistema **bajo 130 °F (54 °C)**. Use enfriadores o intercambiadores si hace falta, y mantenga el estanque lleno para evitar oleaje y calentamiento.
- Use filtros de **10 µm o mejores**, analice el aceite en laboratorio y reemplace los componentes antes de que contaminen el sistema.

## [hidraulica] Grúa IMT: prueba de las válvulas de retención de carga (holding valves) en los cilindros
- Aplica: grúas IMT (cilindros de pluma y extensión)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514, 2-5-8, pág. 2-8)

Las holding valves no son ajustables y evitan que el cilindro se mueva de golpe si se rompe una manguera.
1. Con la carga nominal completa, extienda el cilindro y apague el motor.
2. Accione la válvula de control para retraer. Para el cilindro principal, deje la pluma horizontal con la carga máxima. Para el cilindro de extensión, lleve la grúa a su máxima articulación.
3. Si el cilindro **"se arrastra" (creep)**, cambie la holding valve. Si no se mueve, la válvula está bien.

## [hidraulica] Grúa IMT: banco de válvulas, alivio, válvula proporcional y direccionales
- Aplica: grúas IMT con banco de válvulas eléctrico y control remoto proporcional
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514, sección 3, pág. 3-12) y https://www.imt.com/wp-content/uploads/2018/05/Operations-Maintenance-Repair-Volume-1_20140915.pdf (IMT 99900037, 2-19, págs. 2-15 y 2-16)

- **Válvula de alivio**: limita la presión máxima. En el modelo del manual telescópico viene fijada a **3000 psi con 10 gpm**; para otros modelos, vea el manual específico. Si falla, suele quedar **pegada abierta**: no se forma presión y falta fuerza en todas las funciones. Se cambia desenroscándola.
- **Válvula proporcional**: regula la velocidad de las funciones con una corriente de **0,2 a 2,2 A** según el gatillo. Si la bobina se quemó o el carrete se pegó, no hay control de velocidad. Verifique que llegue corriente a la bobina. Para probar, el vástago se puede atornillar a mano.
- **Direccionales** (4): si una función no opera, pruebe con el **override manual** (el pasador al centro del solenoide). Si con el override funciona, el problema es eléctrico: bobina o cableado. Las bobinas son intercambiables, así que puede cambiarlas de lugar para aislar la falla. Si no funciona ni a mano ni eléctricamente, cambie la sección. PRECAUCIÓN: el override manda aceite de inmediato y el actuador se mueve de golpe.
- LED del amplificador (AMP driver, banco Fauver): el LED **Power** rojo indica que hay alimentación. El LED **PWM%** va de rojo (corriente mínima) a amarillo y verde (máxima). **Si queda en rojo al apretar el gatillo, hay un corto** en el cableado o en la bobina proporcional.
- Ajuste MIN: con el motor en alta, presione Rotation y gire el potenciómetro Min hasta que la grúa apenas empiece a girar.

## [hidraulica] Grúa IMT: sistema ELLS o de corte por capacidad (no opera "subir", "winche arriba" o "extender")
- Aplica: grúas IMT con ELLS o sistema de corte por sobrecarga (capacity shut-down)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514, 2-15 ELLS Troubleshooting, pág. 2-21) y https://www.imt.com/wp-content/uploads/2018/05/Operations-Maintenance-Repair-Volume-1_20140915.pdf (99900037, pág. 1-12)

- Para salir de la sobrecarga, invierta la función que la causa. La válvula sensora se ajusta normalmente a **10 % sobre la presión del sistema**. Revise con regularidad el cableado (flojo, corroído o cortado), las fugas en el sello O-ring del manifold y el interruptor de presión.
Prueba ELLS con multímetro:
1. Con ignición y freno de estacionamiento aplicados y la grúa energizada (no hace falta la PTO), use un trozo de acero para detectar qué solenoide se magnetiza al activar "LOWER UP" y luego "WINCH UP".
2. Desenchufe esos solenoides y el interruptor de presión. Entre la masa del conector de "LOWER UP" y la de "WINCH UP" **no debe haber continuidad**. Si la hay, el arnés está malo.
3. Entre la masa del conector del interruptor de presión y la masa de cada función cortada por el ELLS **debe haber continuidad**. Si no la hay, el arnés está malo.
4. Si el arnés está bien, cambie el interruptor de presión.

## [implemento] Grúa IMT: fallas del winche y presión de calado
- Aplica: grúas IMT con winche de tornillo sinfín o planetario
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (IMT 99903514, 2-16 Winch Troubleshooting, pág. 2-22)

| Problema | Revisión o solución |
|---|---|
| No levanta cargas pesadas | Exceso de carga (reaparejar), falta de aceite en la caja del winche, o presión de entrada al motor bajo lo especificado con la carga calada: **modelo 1015: 2250 psi; 2020: 2350 psi; 3020/3820/5020/5525/6025/6625: 3000 psi; 7020/7025: 2500 psi**. Pruebe la bomba y el alivio principal. Revise el juego axial del sinfín; si supera **0,030"**, revise los rodamientos |
| No sostiene la carga | Ajuste el freno 1/4 de vuelta a la vez, en sentido horario; discos de freno gastados; embrague de levas mal montado; muñón del sinfín desgastado |
| Gira lento | Poco caudal (mida con caudalímetro bajo carga) o motor gastado |
| No gira con carga y abre el alivio | Motor agarrotado o corona y sinfín dañados |

## [hidraulica] Grúa IMT: calentamiento en frío, ruido de la bomba y velocidad de la bomba
- Aplica: grúas IMT (camión pluma). Criterio aplicable a implementos hidráulicos en invierno de altura.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.imt.com/wp-content/uploads/2018/05/Operations-Maintenance-Repair-Volume-1_20140915.pdf (IMT 99900037, 1-5 y 1-12, págs. 1-8 y 1-12) y https://www.imt.com/wp-content/uploads/2018/03/TELE_CRANE_VOL1.pdf (1-14-4)

- Bajo **-25 °F (-32 °C)**: caliente el camión unos **45 min** y luego enganche la PTO en ralentí para que circule el aceite. **No acelere el motor**, porque la bomba se sobrerrevoluciona y la **cavitación puede dañarla de forma permanente**.
- Si oye metal raspando o "popping" en la bomba, detenga el equipo. Revise que la línea de succión no esté tapada y que el aceite no esté gelificado.
- Si la grúa está lenta, **primero verifique la velocidad de la bomba** con un tacómetro calibrado. Rpm del motor necesarias = rpm requeridas de la bomba ÷ razón de la PTO (la razón se expresa como % de las rpm del motor).
- En zonas de polvo o arena: tapas del estanque apretadas, filtros más seguidos y limpieza antes de abrir mangueras.

## [implemento] Control remoto Scanreco G2: códigos de error en el display RCL 5300 (170-192)
- Aplica: grúas con radio control Scanreco G2 conectado a un RCL 5300 (HMF, IMT y otros). Levantar en terreno qué marca de radio tiene cada grúa: Scanreco, HBC u otra.
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: http://www.hmf-tech.com/admin/pdf/file/Scanreco%20G2%20radio%20remote%20control%20system,%2020-13.pdf (HMF Technical Service, Scanreco G2, rev. 20-13, pág. 47)

| Código | Descripción |
|---|---|
| 170 | Falla interna del radio controlador |
| 171 | Error en los terminales de salida del radio controlador |
| 172 | Falla del botón de paro de la caja de control remoto |
| 173 | Palanca de control activada al encender |
| 174 | Error en la señal de una palanca |
| 175 | Falta la codificación de ID entre el radio controlador y la caja remota |
| 176 | Alimentación del radio controlador demasiado baja |
| 177 | Alimentación del radio controlador demasiado alta |
| 180 | Sin enlace de radio entre el radio controlador y la caja remota |
| 184 | El RCL 5300 no recibe la señal de seguridad por cable (DV) |
| 185 | Error en la señal DV del radio controlador |
| 186 | Selector del radio controlador en "Manual" |
| 192 | El RCL 5300 no se comunica con el radio controlador en la red |
Al detectar un error, el sistema corta todas las salidas y el diodo rojo "Status" parpadea rápido. La secuencia de monitoreo dura unos 6 s. Si el error es temporal, el sistema se resetea solo. Si no, reinicie el radio controlador llevando el selector a OFF y de vuelta a Remote.

## [implemento] Control remoto Scanreco G2: códigos "Er" del display LED interno del receptor
- Aplica: receptores (radio controladores) Scanreco G2
- Tipo: codigo_falla
- Confiabilidad: oficial
- Fuente: http://www.hmf-tech.com/admin/pdf/file/Scanreco%20G2%20radio%20remote%20control%20system,%2020-13.pdf (HMF Scanreco G2, págs. 48-50)

El display interno muestra "Er" y luego dos grupos de dos dígitos. Si el error es menor, repite la secuencia 3 veces y reinicia. Si es importante, la repite hasta que se corta la alimentación.
| Display 2 | Display 3 | Significado |
|---|---|---|
| 01 | 01-07 | Error de checksum (EEPROM/FLASH), inestabilidad de software o hardware. Reiniciar y, si sigue, llamar al servicio técnico |
| 02 | 02 | Cortocircuito en la salida DV (seguridad por cable) |
| 04 | 01-14 | Cortocircuito en una salida digital |
| 07 | 1A-8B | Error en una salida analógica |
| 15 | 1A-8B | Cortocircuito en una salida analógica |
| 16 | 1A-8B | Circuito abierto en una salida analógica |
| 17 | 01 | Alimentación demasiado baja |
| 17 | 02 | Alimentación demasiado alta |
Si la salida está en corto (02.02, 04.xx, 15.xx), revise la salida, el cable y el enchufe. Desconecte el enchufe y reinicie. Con el terminal de servicio CGW 5355 se lee el registro (black box) del RCL, con hasta 50 tipos de error, sin abrir el receptor.

## [hidraulica] Aljibe de agua Tremac: descripción del circuito y datos de la bomba centrífuga
- Aplica: aljibes de agua Tremac 20/25/30 m³ (bomba centrífuga movida por un motor hidráulico). Verifique en terreno si la bomba de cada aljibe es Rovatti, Eifel EA, Silea o ETKF.
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://asesor.kaufmann.cl/uploads/multimedium/name/13813/MANUAL_DE_INSTRUCCION_Y_MANTENIMIENTO_TANQUE_ALJIBE_SOBRE_CAMION_20_25_Y_30_M3.pdf (Tremac, págs. 5-9)

- Cadena de mando: PTO → bomba de engranajes → motor hidráulico → bomba centrífuga. Tiene un estanque de aceite propio.
- Bomba de fábrica: **Rovatti S2P85**, 1200 L/min, altura de 56 m, **tiempo máximo sin carga: 2 min**.
- Válvulas de membrana neumáticas de 3" con unión Victaulic, normalmente cerradas y comandadas desde la cabina. VM1 es el aspersor del lado piloto, VM3 el aspersor del lado copiloto y VM2 la barra nebulizadora.
- Cañería de 3" ASTM A53/A106, Sch 40 y 80, con abrazaderas ranuradas flexibles UL-FM.
- Barra nebulizadora de 2,6 m. Puede funcionar por gravedad (válvula de bola VB4) o presurizada (VM2).

## [hidraulica] Aljibe de agua Tremac: mantención del sistema hidráulico (filtros, aceite, estanque)
- Aplica: aljibes de agua Tremac con mando hidráulico de la bomba centrífuga
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://asesor.kaufmann.cl/uploads/multimedium/name/13813/MANUAL_DE_INSTRUCCION_Y_MANTENIMIENTO_TANQUE_ALJIBE_SOBRE_CAMION_20_25_Y_30_M3.pdf (Tremac, 2.1, págs. 5-7)

- Inspección mensual: nivel y estado del aceite, fugas, presión de trabajo, aprietes, flexibles y roces, filtros e indicador de saturación. Reapriete todas las conexiones a las 2 semanas de uso.
- Filtros: primer cambio a las **50 h** o al mes, y luego **cada 500 h o 6 meses**.
- Aceite: primer cambio a las **200 h** o a los 2 meses, y luego **cada 1500 h o 1 vez al año**. Diálisis (flushing) **cada 750 h con filtro de 8-10 µm**. Análisis de aceite cada 6 meses. Aceite recomendado: **NUTO H 46 o equivalente**.
- Zunchos del estanque: **20 N·m (15 lb·ft)** a los primeros 1000 km y luego cada 5000 km. Cambie el filtro de aire del estanque al menos 2 veces al año. Limpie el interior 1 vez al año.
- **En ambientes corrosivos, con polvo o en condiciones severas (faena minera), reduzca todos los intervalos a la mitad.**

## [hidraulica] Aljibe de agua Tremac: detección de fallas del riego
- Aplica: aljibes de agua Tremac. Lógica aplicable a otros aljibes con bomba centrífuga.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://asesor.kaufmann.cl/uploads/multimedium/name/13813/MANUAL_DE_INSTRUCCION_Y_MANTENIMIENTO_TANQUE_ALJIBE_SOBRE_CAMION_20_25_Y_30_M3.pdf (Tremac, sección 9 y 10, págs. 16-17)

| Falla | Solución |
|---|---|
| El equipo no funciona en general | Revisar que la presión de aire esté en rango, que la válvula de bola del estanque hidráulico esté totalmente abierta y que haya aceite en el estanque hidráulico |
| Funciona la hidráulica pero no hay caudal de agua presurizada | Revisar que VB5 (alimentación de la bomba) esté totalmente abierta, que VB3 (carga presurizada) esté totalmente cerrada y que haya agua suficiente en el aljibe |
| El caudal cae durante el riego | Revisar el nivel de agua, que VB5 esté totalmente abierta y que la admisión de la bomba dentro del tanque no esté obstruida |
| Ruido en la hidráulica (PTO o bomba) | Pedir un técnico |
Con frío extremo, drene la bomba al terminar la jornada para que no se congele. Esto es relevante en faenas de altura.

## [hidraulica] Bomba centrífuga de agua (serie ETKF de Erduro): fallas típicas y causas
- Aplica: bombas centrífugas de succión axial para agua (ETKF de Erduro, la bomba "Volvos ETKF" del taller). Criterio aplicable a Eifel EA y Silea, cuyos manuales locales están escaneados y no se pudieron extraer.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.erduro.com/upload/downloads/etkf-user-manual-en_c93017.pdf (Erduro ETKF-EMKF Single Stage User Manual, "Reasons for failures and trouble shooting", Tablas 3 y 4; copia local "Manual bomba Volvos etkf-user-manual-en_c93017.pdf")

Síntomas: no descarga al arrancar; baja el caudal o no hay caudal; motor sobrecargado; rodamientos calientes; vibración; ruido.
Causas principales según el manual:
1. **Aire en el líquido**: la succión no está bien sumergida y se forman remolinos. Suba el nivel o baje la succión.
2. **Bolsón de aire en la línea de succión**: revise la pendiente. Si el tanque está sobre la bomba, la línea debe bajar hacia la bomba; si está bajo la bomba, debe subir hacia ella.
3. **Bomba o succión sin cebar**: llénelas de líquido y arranque de nuevo.
4. **Entra aire por el sello, la cañería o las uniones**: revise todas las uniones de succión.
5. **Cavitación por NPSH bajo**: nivel bajo, pérdidas por fricción en la succión, válvula de succión no totalmente abierta. La válvula de succión nunca se usa para regular caudal.
6. Altura de succión excesiva: use una cañería de mayor diámetro o baje la bomba.
7. Más altura de descarga de la esperada: válvulas no totalmente abiertas u obstrucción en la descarga.
Operar mucho tiempo con la descarga cerrada o casi cerrada convierte toda la potencia en calor y **sobrecalienta la bomba**. Si ocurre, instale un bypass después de la bomba. Nunca haga girar la bomba en sentido inverso.

## [combustible] Bomba de paletas Blackmer (camión aljibe de combustible): puesta en marcha y ajuste de la válvula de alivio
- Aplica: bombas Blackmer para camión (TX/TXD, montadas en la PTO o con mando hidráulico). Levantar en terreno el modelo de bomba de cada aljibe de combustible.
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: http://www.pancos.co.kr/blackmer/mdb2/pdf/201-a00.pdf (Blackmer Truck Pumps, Instructions 201-A00, págs. 4-5)

- Al arrancar, la bomba debe **cebar en 1 minuto o menos**. Instale temporalmente un vacuómetro y un manómetro en las puertas de 1/4" NPT del cilindro y registre las lecturas iniciales como referencia.
- Válvula de alivio interna: su ajuste está en una placa en la tapa. Debe quedar **15-20 psi (1,0-1,4 bar) sobre la presión máxima de operación** o sobre el ajuste del bypass externo. Se prueba cerrando un momento una válvula de descarga y leyendo el manómetro. Girar en sentido horario aumenta la presión y antihorario la disminuye.
- **No opere contra la descarga cerrada por más de 15 s.** Si se trabaja más de 1 minuto con la descarga cerrada, hay que instalar un bypass externo al estanque. Cerrar parcialmente la descarga hace "castañetear" (chatter) la válvula de alivio y no se debe hacer.
- Con mando por PTO o hidráulico, **debe haber control de velocidad** para no superar las rpm máximas de la bomba, independiente de las rpm del motor.
- La válvula de alivio interna protege la bomba. **No es una válvula de control de presión del sistema.**

## [combustible] Bomba Blackmer: tabla de síntomas y causas
- Aplica: bombas de paletas Blackmer de camión (TX/TXD)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: http://www.pancos.co.kr/blackmer/mdb2/pdf/201-a00.pdf (Blackmer 201-A00, General Pump Troubleshooting, págs. 9-10)

- **No ceba**: bomba seca, paletas gastadas, válvula de succión cerrada, fuga en la succión, filtro (strainer) tapado, succión restringida, transmisión cortada, bomba con vapor atrapado (vapor lock), velocidad demasiado baja para cebar, o alivio parcialmente abierto o que no asienta.
- **Capacidad reducida**: velocidad baja, válvulas de succión no totalmente abiertas, fuga en la succión, restricción en la succión (cañería chica, muchos codos, filtro tapado), piezas gastadas, restricción en la descarga que hace pasar flujo por el alivio, alivio gastado o bajo, o paletas mal instaladas.
- **Ruido**: vacío excesivo (succión restringida, velocidad alta para la viscosidad o volatilidad, bomba lejos del estanque), descarga cerrada, bomba suelta, cardán mal instalado, rodamientos gastados, cañerías sin anclar, eje doblado o desalineado, rotor gastado, válvula del sistema defectuosa o alivio bajo.
- **Paletas dañadas**: cuerpos extraños, operación en seco, cavitación, viscosidad alta, incompatibilidad con el líquido, calor, varillas de empuje gastadas, material solidificado al arrancar, golpe de ariete o instalación incorrecta.
- **Eje cortado**: cuerpos extraños, viscosidad alta, alivio que no abre, golpe de ariete, desalineación o paletas y ranuras gastadas.
- **Fuga por el sello**: O-rings incompatibles o dañados, eje dañado en la zona del sello, rodamientos con exceso de grasa, cavitación, sello de labio mal asentado, corrosión, o caras del sello mecánico dañadas.

## [combustible] Medidor Liquid Controls serie M (M-5 a M-80): tabla de fallas
- Aplica: medidores de desplazamiento positivo Liquid Controls M-5, M-7, M-10, M-15, M-25, M-30, M-40, M-60 y M-80 de aljibes de combustible
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://lcmeter.com/wp-content/uploads/2022/03/M100-10-M-MA-Meters_V4_09202021-compressed-4.pdf (Liquid Controls M100-10 M/MA Meters Installation & Parts, Troubleshooting, págs. 22-23)

| Problema | Causa probable y solución |
|---|---|
| Fuga por el prensaestopas (packing gland) | Sello interno gastado: cambiar el packing gland y su O-ring. Causas típicas: dilatación térmica y golpe de ariete (ver ficha siguiente) |
| Fuga por la empaquetadura de la tapa | Golpe de presión o pernos flojos: cambiar la empaquetadura y apretar |
| Pasa producto pero el registro no avanza | Revisar el packing gland y el tren de engranajes. Si todo gira, el problema es el registro. Si gira el medidor pero no el eje del ajustador (adjuster), cambiar el ajustador. Si avanzan los números chicos y no los grandes, reparar el registro. Si el engranaje del packing gland no gira, cambiarlo (puede ser por partir el flujo demasiado rápido). En M-60 y M-80, la paleta de arrastre puede estar cortada |
| Dientes rotos en los engranajes de sincronización | Partir o parar el flujo demasiado rápido, o bypass de la bomba mal ajustado |
| El registro no marca bien | Ajustador descalibrado, placa o razón de engranajes incorrecta, **aire en el sistema** (revisar el eliminador de aire) |
| No pasa flujo | Bomba sin funcionar, válvula cerrada o defectuosa, o medidor "congelado" por sales o suciedad: limpiar e inspeccionar |
| El medidor gira lento | Válvula que no abre del todo, rotores con sales, restricción aguas abajo o **canasto del filtro tapado** |
| Cuenta hacia atrás | Invertir el engranaje motriz del ajustador (pág. 10) |

## [combustible] Medidor Liquid Controls: daño por dilatación térmica y golpe de ariete
- Aplica: medidores Liquid Controls en aljibes de combustible (toda la línea de trasvasije)
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://lcmeter.com/wp-content/uploads/2022/03/M100-10-M-MA-Meters_V4_09202021-compressed-4.pdf (M100-10, Operating Note, pág. 22)

- **Dilatación térmica**: si se cierran las válvulas a ambos lados del medidor y el producto se calienta (camión al sol), basta que suba **1 °F** para superar la presión máxima de trabajo del medidor. Debe haber una válvula de alivio en el sistema.
- **Golpe de ariete**: al cerrar de golpe una válvula con mucho caudal, toda la masa de líquido golpea el medidor, el packing gland y los internos. Mientras más larga la línea y mayor la velocidad, peor el golpe. Use una **válvula de cierre lento de dos etapas**, y si no basta, un amortiguador de aire.
- Síntomas: fugas por el packing gland y por la tapa, y dientes rotos en los engranajes de sincronización.

## [combustible] Eliminador de aire mecánico Liquid Controls M300: cómo funciona y mantención
- Aplica: eliminadores de aire y vapor mecánicos Liquid Controls (M300) montados sobre el filtro, antes del medidor
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://lcmeter.com/wp-content/uploads/2022/03/M300-10_Mechanical-Eliminators.pdf (Liquid Controls M300-10 Mechanical Air & Vapor Eliminators, págs. 5-6 y 18-20; copia local "Manual Eliminador Mecánico de Aire M300-10_(Liquid Control).pdf")

- Funcionamiento: el aire sube a la cámara del eliminador. Cuando el nivel de líquido sube, el flotador aprieta las láminas (reed strips) contra la placa de válvula y sella las puertas de venteo. Cuando entra aire, el flotador baja y el aire se ventila hacia el estanque. La **válvula de retención de aire (air check) o diferencial**, a la salida del medidor, se mantiene cerrada con el aire expulsado más la fuerza del resorte, de modo que **no pasa producto por el medidor hasta que se elimina el aire**. El orificio de purga limitada (bleed) la abre lentamente para evitar golpes.
- Síntomas de falla: el medidor registra de más (pasa aire) o sale producto por el venteo hacia el estanque (flotador inundado o láminas rotas). Si la válvula de aire no abre, revise el orificio de purga y las líneas de venteo.
- Mantención: cambie la placa de válvula y el sello de la tapa después de revisar el reborde de la puerta de venteo. Torque de los pernos de la tapa: **17,5-20,5 ft·lb**. Si el flotador pesa porque tiene producto dentro, **cambie el conjunto del flotador**. Cambie las láminas rotas y **sujételas al sacar el tornillo**, porque se disparan de golpe.
- Antes de desarmar: presión en **0 psi**, líquido drenado y líneas cerradas.

## [combustible] Sobrellenado óptico API de 5 hilos: cómo lo ve la isla de carga (rack monitor Civacon)
- Aplica: aljibes de combustible con sensores ópticos de 5 hilos y enchufe API (norma API RP 1004; compatibles con Scully y Civacon)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.opwglobal.com/docs/libraries/opw-engineered-systems/manuals/h52496pa-iom.pdf?sfvrsn=f952dec4_8 (Civacon 8130 Optic Rack Monitor IOM H52496PA, págs. 3 y 11-12)

- El monitor de la isla intercambia pulsos digitales con cada sensor. Si cualquier componente falla (sensor, cable o enchufe), queda en **NO PERMISIVO**. Los sensores **no se pueden puentear**.
- El monitor usa **4 de los 5 hilos**. El quinto (diagnóstico) solo lo usan los monitores a bordo. Soporta hasta 12 sensores ópticos.
- **Verificación de masa (GV)**: la fuente principal es la masa del sensor en el enchufe API, normalmente el **pin 10**. También puede venir por los acoples de carga, la línea de recuperación de vapores o la pinza de tierra.
- Luces del monitor de la isla: **VERDE = permisivo**; **ROJO fijo = no permisivo** (sensor mojado o falla de sensor o cable); **ROJO parpadeando = no hay verificación de masa**; ROJO y VERDE juntos = bypass activo.
- Voltaje de la salida intrínsecamente segura del monitor (dato de la isla, no del camión): 12-14 V DC entre los terminales 3 y 2 sin nada conectado.
- Complemento local: los procedimientos internos "Manual de Prueba Básico Sistema Sobrellenado Óptico (Multitester)" y "Manual de Pruebas Sistema Sobrellenado Óptico" (carpeta Manuales) traen el pinout que usa Pillado: rojo al pin 8, negro al 10, naranja al 6, amarillo al 4, verde al 5 y perno inteligente al 9.

## [combustible] Tester de camión Civacon 1376TT: cómo interpretar la pantalla
- Aplica: aljibes de combustible con sobrellenado óptico o de termistor API (prueba en taller con el tester Civacon 1376TT o un equivalente)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.opwglobal.com/docs/libraries/civacon/iom/1376tt-truck-tester.pdf?sfvrsn=616588c4_2 (Civacon 1376TT Truck Tester H52795PA, págs. 4-11)

- El tester detecta solo si la señal es óptica o de termistor. En modo óptico entrega señal a los pines **4, 5, 6 y 7** del enchufe óptico. Mira el pin 8 para detectar termistor. **No conecte a la vez un enchufe óptico y uno de termistor.**
- **Primero exige una verificación de masa (GV)** válida (pines 9 y 10 de J1). Sin GV no da permiso.
- Pantalla:
  - Banco verde completo encendido o parpadeando: **PERMISO**.
  - "g" roja: **falla de masa** (el camión no tiene buena conexión a tierra; revise el perno de masa y el pin 10).
  - "g" verde: masa verificada y buscando la señal de sobrellenado.
  - Número rojo: **compartimento con falla o sensor mojado**. En óptico se muestra un solo canal, determinado por la impedancia del **hilo verde de diagnóstico**.
  - Sin comunicación: falla interna del tester.
- Lógica de campo: si aparece "g" roja, busque masa o pin 10. Si aparece un número rojo, revise ese compartimento: sensor mojado o producto sobre el sensor, sensor dañado, o continuidad de sus hilos hasta el enchufe (usar el procedimiento local con multitester).

## [combustible] Monitor a bordo Scully IntelliCheck: sin luces o sin luz de permiso
- Aplica: aljibes de combustible con monitor a bordo Scully IntelliCheck o IntelliCheck2 (solo si lo tiene; los sistemas pasivos de sensor más enchufe API no lo usan)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://scully.com/wp-content/uploads/61460B_IntelliCheck.pdf (Scully 61460B IntelliCheck Diagnostic Troubleshooting Procedures, Procedimientos 1 y 2, págs. 3-4)

**Sin luces indicadoras:**
1. Mida en TB1. Si hay **11-14,0 V DC**, el módulo está malo.
2. Si no, mida de TB1 (+) al chasis. Si ahí hay voltaje, repare la masa entre el enchufe (nose plug) o la batería y TB1.
3. Desconecte los cables de TB1 y mida entre ellos. Si hay voltaje, cambie el módulo.
4. Revise el fusible en línea.
5. Mida en el enchufe o la batería. Si hay voltaje, repare la alimentación hacia TB1.
**Sin luz de permiso:** si hay luces de sobrellenado encendidas, vaya al Procedimiento 3. Si hay luces de retención (retain), al 5. Si está encendida la luz AUX, al 7. Si no hay ninguna de esas, pruebe con un tester universal o mida continuidad entre TB5-2 y TB5-3 (contactos del relé). Si hay continuidad, está quemada la luz de permiso. Si no la hay, cambie el módulo.

## [combustible] Monitor Scully IntelliCheck con sensores de 5 hilos (SP-FU): luz de sobrellenado encendida o parpadeando
- Aplica: aljibes de combustible con Scully IntelliCheck y sensores ópticos de 5 hilos SP-FU
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://scully.com/wp-content/uploads/61460B_IntelliCheck.pdf (Scully 61460B, Procedimientos 8 y 9, págs. 17-25)

**Luz fija** (Procedimiento 8):
1. ¿El sensor indicado está en producto? Si es así, baje el nivel.
2. Desconecte TB3-1 (o el terminal indicado). Si la luz no pasa a parpadear más lento que Dynacheck, cambie el módulo.
3. Conecte un SP-FU conocido bueno a TB3 (sensor, power, pulse out y GND). Si la luz no se apaga, cambie el módulo.
4. Conecte al módulo el SP-FU del compartimento. Si no se apaga, cambie el sensor. Si se apaga, revise el cable entre el módulo y los sensores.
5. Reinstale el sensor y puentee sus hilos naranjo, rojo, amarillo y negro con cables nuevos directo a TB3. Si así funciona, cambie el cableado.
**Luz parpadeando** (Procedimiento 9): compare con la luz Dynacheck.
- Más rápido: desconecte en el sensor el hilo naranjo. Si la luz pasa a más lenta, cambie el sensor. Si no, cambie el cableado.
- Más lento: procedimiento 9A/9B, por hilo abierto.
- Igual: procedimiento 9C/9D.

## [combustible] DS 160 (Chile): exigencias para el camión tanque que afectan la mantención
- Aplica: aljibes de combustible (camiones tanque de combustibles líquidos) de toda la flota
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.sec.cl/sitioweb/transparencia_activa/julio2010/Decreto_160.pdf (DS 160/2008 Reglamento de Seguridad de Combustibles Líquidos, arts. 181-203)

- Art. 181: el diseño y la construcción siguen DOT 406 (178.345). Art. 182: el sistema de recuperación de vapores y la carga por fondo siguen **API RP 1004** (8.ª ed., 2003).
- Art. 184: los pasahombres y escotillas deben ser herméticos y resistir una presión hidrostática de **62 kPa (0,65 kgf/cm²)** sin filtrar ni deformarse. Art. 185: cada compartimento lleva válvulas de presión y vacío con un paso mínimo de **3 cm²**. Art. 186: válvula de emergencia en cada salida, cerrada salvo durante la carga y descarga.
- Arts. 187-189: los circuitos de iluminación llevan protección de sobrecorriente, hay un **interruptor general** inmediatamente después de la batería y los circuitos se cablean por ambos polos, **sin usar el chasis como retorno**. Art. 190: terminal de puesta a tierra.
- Art. 197: el escape va separado del sistema de combustible y protegido de salpicaduras; parachoques trasero al menos 15 cm de las válvulas; despeje mínimo de 30 cm.
- **Art. 200**: el circuito de la bomba de trasvasije debe tener un **sistema automático contra sobrepresión** (válvula de alivio o bypass). Las mangueras deben ser compatibles, eléctricamente continuas y con su presión máxima marcada. Los acoples deben ser rápidos, herméticos y antichispa, y todo se inspecciona con la frecuencia que declare el operador en su Programa de Seguridad.
- **Art. 203 c)**: **inspección semestral de la hermeticidad** de los tanques y de las empaquetaduras de las tapas y escotillas. Art. 203 d): inspección mensual del vehículo según el DS 298/94.
- Art. 198: 2 extintores de polvo químico seco (PQS) de al menos 40 BC, revisados cada 6 meses como mínimo.

## [electrico] Prueba de baterías de 12 V (en bancos de 24 V): ojo hidrométrico y prueba de carga
- Aplica: toda la flota (baterías de plomo-ácido, bancos de 24 V con 2 baterías de 12 V en serie)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy Diagnostic Procedures Manual, 3-1 a 3-6, págs. 10-11)

Pruebe cada batería de 12 V por separado:
1. Ojo hidrométrico: verde, continúe; oscuro, recargue y continúe; **amarillo, cambie la batería**. Sin ojo, mida el voltaje: si es **≥12,4 V** continúe, y si no, recargue.
2. Con baterías con tapones, mida la densidad a 80 °F: ninguna celda bajo **1,230** y una diferencia máxima de **0,050** entre celdas. Si la diferencia es mayor, cambie la batería.
3. Aplique 300 A por 15 s para quitar la carga superficial y espere 1 min. En baterías con tapones, si aparece una neblina azul en una celda, cámbiela.
4. Aplique una carga de **la mitad del CCA** por **15 s** y lea el voltaje con la carga aplicada. Mínimo según la temperatura de la batería: 70 °F (21 °C) 9,6 V; 50 °F (10 °C) 9,4 V; 30 °F (-1 °C) 9,1 V; 15 °F 8,8 V; 0 °F (-18 °C) 8,5 V. Si queda bajo ese valor, cambie la batería.
Con bornes de espárrago, mida en las placas de plomo o use adaptadores, porque medir en el espárrago da una falsa lectura de batería mala.

## [electrico] Caída de voltaje en los cables de batería y de arranque (24 V)
- Aplica: toda la flota (arranque de 24 V; motores de arranque Delco Remy y otros)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy, 3-7 a 3-12, págs. 12-13)

1. Use un carbon pile de 24 V, o arme un sistema temporal de 12 V con una sola batería conectada y use los amperes indicados para 24 V.
2. Conecte el carbon pile entre el terminal BAT del solenoide y la masa del motor de arranque. Ajuste a **250 A (sistema de 24 V)**; en 12 V son 500 A.
3. Con un voltímetro digital en escala baja, mida la caída del positivo (BAT del arranque al positivo de la batería) y luego la del negativo (masa del arranque al negativo de la batería). Mida en los terminales, no en las pinzas.
4. **Pérdida total (positivo + negativo) máxima en 24 V: 1,0 V** con arranques 37MT, 40MT, 41MT, 42MT y 50MT. En 12 V el máximo es 0,5 V (0,4 V con 50MT).
5. Con dos ubicaciones de baterías, pruebe cada juego con **125 A (24 V)**.
Si la caída es excesiva, cambie cables o repare conexiones. Reconecte el sistema a 24 V antes de arrancar.

## [electrico] Arranque lento o que no gira: circuito del relé magnético y voltaje disponible al girar
- Aplica: toda la flota (arranque de 24 V con relé o switch magnético)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy, 3-13 a 3-25, págs. 14-17)

- Pérdida en el circuito del switch magnético: máximo **2,0 V en 24 V** (1,0 V en 12 V).
- Pérdida total en el cableado del circuito del solenoide, con carga de 60 A en 24 V: máximo **1,8 V** (0,8 V en 12 V).
- Pérdida en los contactos del switch magnético con carga: máximo **0,2 V** en 12 V y en 24 V.
- Circuito de control del solenoide a voltaje pleno: cada punto debe quedar a **no más de 2,0 V (24 V)** del voltaje de la batería. Si el switch no cierra pero tiene voltaje, cámbielo. Si no llega voltaje, revise la masa del switch y el cableado.
- **Voltaje disponible al girar**: mida entre BAT del solenoide y la masa del arranque mientras gira. Si da **18 V o menos (24 V)** (9 V en 12 V), mida cada batería mientras gira. Si hay **más de 0,5 V de diferencia entre dos baterías** o un cable está tibio, revise los cables entre baterías.
- Por último, revise la corona del volante y el piñón. Si los dos están bien y el arranque sigue lento, cambie el arranque. Si con uno nuevo no mejora, busque una causa mecánica en el motor.

## [electrico] Alternador de 24 V: caída en el cableado, voltaje de salida, amperaje y remagnetización
- Aplica: toda la flota (alternadores de 24 V; procedimiento Delco Remy para cualquier alternador con regulador interno)
- Tipo: procedimiento_diagnostico
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy, 3-26 a 3-32, págs. 17-19)

1. **Cableado** (motor apagado, sistema temporal de 12 V): ponga el carbon pile entre la salida del alternador y masa, con los amperes nominales del alternador. Mida la caída de la salida al positivo de la batería y de la masa del alternador al negativo. **Suma máxima en 24 V: 1,0 V** (0,5 V en 12 V).
2. **Voltaje de salida** (a temperatura de taller, sin consumos y en ralentí acelerado hasta que se estabilice por 2 min): **no debe superar 31 V (24 V)** (15,5 V en 12 V). Si lo supera, cambie el alternador o el regulador.
3. **Amperaje**: con una pinza amperimétrica en todos los cables de salida y el carbon pile en las baterías, a unas 5000 rpm del alternador (la mayoría de los alternadores pesados se clasifican a 5000 rpm), el máximo debe quedar **dentro del 10 % del valor nominal** grabado en la carcasa.
4. Si la salida es cero, remagnetice el rotor: con el alternador conectado normalmente, puentee un instante el positivo de la batería al terminal R o I. Repita la prueba y, si sigue en cero, cambie el alternador.
Requisito previo: baterías probadas y con más de 12,4 V cada una, y correa y soportes en buen estado.

## [electrico] Alternador Delco Remy 24SI/28SI: terminales, cable de sensado y caída admisible
- Aplica: alternadores Delco Remy 24SI y 28SI (24 V de 70 A y 100 A según el modelo; verificar la placa)
- Tipo: pinout_conector
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/documents/alternator-instruction-sheets/installation-instructions-24si-28si.aspx (Delco Remy 24SI/28SI Installation Instructions 10524210, págs. 1-2)

- **B+**: salida al positivo de la batería. La caída en el cable de carga, a salida plena, **no debe superar 1,0 V en 24 V** (0,5 V en 12 V).
- **S (Remote Sense)**: al voltaje del sistema en la batería o en un punto de distribución común, con cable 16 AWG y **fusible de 5 A**. **No lo conecte a R ni a I.** El alternador funciona sin este cable, pero regula mejor con él.
- **R o P (relay/phase)**: entrega **la mitad del voltaje del sistema** (unos 12-14 V en un sistema de 24 V). La frecuencia es igual a las **rpm del alternador ÷ 10** y el consumo máximo es de **4 A**. Sirve para relés, testigos y tacómetros. **No es el sensado; no lo conecte a B+.**
- **I**: terminal de lámpara o ignición, 1,0 A en cualquier sentido.
- En el conector de 4 pines, **L** es la lámpara y **F** es el dato de campo hacia la ECU o ECM.
- Tornillo de masa: muy recomendado. Torques: B+ 9,0-13,0 N·m; masa 5,6-6,8 N·m; terminales M5 3,0-5,0 N·m; terminales #10 1,7-2,8 N·m.
Diagnóstico rápido: si hay tacómetro por R y la aguja cae a cero, revise el alternador o el terminal R. Si el voltaje es alto (>31 V en 24 V), revise primero el cable S.

## [electrico] Motor de arranque Delco Remy 38MT/39MT (24 V): CCA máximo, relé y conexiones
- Aplica: arranques Delco Remy 38MT y 39MT (24 V)
- Tipo: especificacion
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/documents/starter-instruction-sheets/installing-38mt-39mt-gear-reduction-heavy-duty-s.aspx (Delco Remy 10511649, rev. 6)

- **CCA máximo de las baterías** (un CCA excesivo daña el arranque): 38MT **900 CCA en 24 V** (1875 en 12 V); 39MT **1250 CCA en 24 V** (2500 en 12 V).
- Un relé o switch magnético montado aparte y su cableado deben soportar al menos **200 A en 24 V** (300 A en 12 V).
- El IMS (switch magnético integrado) puede ser de 3 cables (va al interruptor de partida) o de 2 cables (va al ECM). **No son intercambiables.**
- Arranque aislado: requiere un cable de masa, de la misma sección que el positivo, desde su terminal "Insulated/Ground" hasta el negativo de la batería. Sin ese cable no funciona.
- Torques: BAT (+) y masa (-) 24,5-27,5 N·m; terminal del solenoide S 2,0-2,5 N·m; terminal del switch magnético 1,9-2,4 N·m.
- Los drenajes deben quedar bajo la horizontal. Si el arranque anterior tenía suplementos (shims) o espaciador, reinstálelos igual. Si la corona está dañada, cámbiela.

## [electrico] Arranque "inteligente" Delco Remy (SIMS/IOCP): por qué se niega a girar
- Aplica: arranques Delco Remy con relé SIMS y protección de sobre-giro integrada (IOCP). El documento da los valores para 12 V. En 24 V, confirme los umbrales con Delco Remy.
- Tipo: falla_conocida
- Confiabilidad: oficial
- Fuente: https://www.delcoremy.com/getmedia/30ff0e99-7084-451b-8f2a-6745dd18a3b5/DelcoRemy_DiagnosticManual_Updated_Digital.pdf.aspx (Delco Remy, sección V, 5-1 y 5-2, págs. 21-22)

El relé SIMS bloquea el arranque para protegerlo:
- **Reintento automático**: intenta enganchar el piñón 3 veces en menos de 1 s. Si no logra, hay que ciclar la ignición.
- **Bloqueo por bajo voltaje** (12 V): no permite el arranque si el voltaje en vacío es menor a 12 V (unos 25 % de carga).
- **Bloqueo por alto voltaje** (12 V): no permite el arranque sobre 14 V. Por eso bloquea las partidas con booster de alto voltaje.
- **Protección de sobre-giro (OCP)**: si el arranque supera **150 °C** por giro continuo, el termostato se abre. Deje enfriar antes de desmontar.
- **Bloqueo con motor en marcha** y desenganche automático al partir.
Revise el termostato OCP en frío: con el conector desconectado, entre sus dos terminales debe medir **cero ohm**. Si está abierto en frío, cambie el arranque. No lo pruebe en caliente, porque abre por diseño.
Antes de desmontar un arranque que "no hace nada", verifique el voltaje en el terminal S, el estado de carga y la temperatura.

## [general] Datos que el taller debe levantar de cada implemento para usar estas fichas
- Aplica: toda la flota (37 camiones)
- Tipo: procedimiento_diagnostico
- Confiabilidad: experiencia_campo
- Fuente: https://www.wabco-customercentre.com/catalog/docs/mm0112_web_en.pdf (las fichas de este archivo muestran que los valores cambian por marca, versión y voltaje: WABCO 900-2000 Ω contra Bendix 1500-2500 Ω; moduladores de 12 V a 4-9 Ω contra 24 V a 11-21 Ω)

Registre en cada ficha de equipo:
1. **ECU de ABS o EBS**: marca (WABCO, Bendix o Knorr), número de parte y versión (D/E, EBS3), y si es de 12 V o 24 V. Indique si tiene interruptor de blink code.
2. **Secador o APU**: marca, modelo y número de parte (WABCO 432 410..., 932 500..., System Saver o Bendix AD-IP), presión de corte en la placa y calefactor de 12 V o 24 V.
3. **Retardador**: Voith (VR115HV o 115E), Telma (modelo) o ninguno.
4. **PTO**: marca y modelo (Mercedes NMV/NA, ZF, Chelsea, Muncie, Hyva, Allison), accionamiento (aire, eléctrico o hidráulico), voltaje del solenoide, razón de la PTO y ubicación del interruptor de seguridad y de su presóstato.
5. **Bomba hidráulica**: marca, modelo, desplazamiento en cc/rev y tipo (engranajes o pistones), presión de alivio de placa y sello.
6. **Grúa**: marca, modelo y serie (IMT, Palfinger, Hiab, PM o Fassi), limitador de momento de carga (modelo) y radio control (Scanreco G2, HBC u otro, con modelo y serie).
7. **Polibrazo**: marca, modelo y serie (Hyva Titan, Marrel Ampliroll, Palfinger o Guima), válvula principal (SD8, SDS150 o SDS180) y presión de trabajo.
8. **Aljibe de agua**: fabricante del tanque, bomba centrífuga (Eifel EA, Silea, Rovatti o ETKF, con modelo), accionamiento (directo por PTO o con motor hidráulico) y válvulas (neumáticas o eléctricas).
9. **Aljibe de combustible**: bomba (Blackmer o Corken, con modelo y ajuste del alivio), medidor LC (modelo M-xx y serie), eliminador de aire (M300), registrador, filtros o separador, sistema de sobrellenado (Civacon, Scully o Dixon, con modelo del sensor de 2 o 5 hilos y si tiene monitor a bordo), y la fecha y el organismo de la última certificación de hermeticidad (DS 160, art. 203).
10. **Arranque y alternador**: marca y modelo (Bosch, Delco Remy 39MT, 28SI, etc.) y el CCA de las baterías.
