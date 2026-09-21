# Benchmark de producto — herramientas de diagnóstico y asistencia al técnico (camiones pesados)

> Documento para el DESARROLLADOR (no se indexa en el RAG). Investigación 2026-09-19.
> Objetivo: identificar qué hace "clase mundial" a una herramienta de diagnóstico y traducirlo a funcionalidades
> concretas para el Copiloto Técnico de SICOM-ICEO (Next.js + Supabase, móvil, RAG de manuales + historial OT + casos resueltos).

---

## 1. Resumen ejecutivo

Las herramientas líderes convergen en 5 patrones:
1. **Del código a la acción en un toque**: código → descripción clara → severidad → causas probables ORDENADAS → prueba guiada → reparación → repuestos → tiempo estándar (Jaltest Info, JPRO Fault Guidance + NextStep, Mitchell 1, Cummins Guidanz).
2. **Datos de reparaciones reales** como señal de ranking ("qué arregló esto en N casos similares"): Snap-on SureTrack (Real Fixes, Top Repairs / Common Replaced Parts sobre >1.000 millones de registros), Bosch Experience-Based Repair.
3. **Contexto del vehículo específico** (VIN/configuración, motor, historial, telemetría) para filtrar ruido: Samsara Enhanced Fault Code Insights, Uptake (reduce miles de códigos a 5-10 accionables por vehículo/año), Volvo/Mercedes Uptime.
4. **Esquemas interactivos**: clic en componente → ubicación física, conector, pinout, prueba guiada (Jaltest, Mitchell 1 TruckSeries, JPRO).
5. **IA generativa 2025-2026** montada SOBRE datos propios verificados (no chatbot genérico): Bosch ESI[tronic] AI (sobre su base EBR), Samsara AI (sobre manuales de servicio), ServiceMax AI (sobre historial del activo), Tractian (procedimientos prescriptivos).

Nuestra ventaja diferencial posible: historial real de OT de NUESTRA flota + condiciones de operación (altura, polvo, PTO) + regla dura de citar fuente. Ninguna herramienta comercial conoce la faena del cliente.

---

## 2. Fichas por herramienta

### 2.1 Jaltest (Cojali) — Jaltest Diagnostics + Jaltest Info
Fuentes: https://www.jaltest.co.uk/diagnostics/additional-modules/jaltest-info ; https://sadlerpowertrain.com/content/pdf-update/jaltest-catalogue_EN_411.pdf ; https://www.eclipse-tech.co.uk/jaltest-software/
Funciones clave:
- Solución de problemas por código de error Y por síntoma (dos puertas de entrada).
- Esquemas eléctricos, neumáticos y de combustible interactivos: al pasar sobre un componente se resalta; al hacer clic abre datos técnicos, documentos relacionados y ubicación física en el vehículo.
- Datos técnicos del vehículo (torques de ajuste, medidas de referencia, parámetros), datos de mantenimiento, liberaciones y procedimientos (TSB), guías de reemplazo de componentes.
- Tiempos de reparación (estimación para presupuestar y planificar taller).
- Diagnóstico manual con valores de referencia; actualización ≥3 veces al año. Multimarca (camión europeo + americano) — ya existe en la flota (carpeta "Videos Jaltest").
Ideas UX para el mecánico con teléfono:
1. Doble entrada en la pantalla inicial: "Tengo un código" / "Tengo un síntoma".
2. Ficha de componente única (foto, ubicación, conector, valores de prueba) enlazada desde cualquier respuesta.
3. Mostrar el tiempo estándar de reparación junto a la solución para que el jefe de taller planifique.
4. Pictogramas simples (lámparas, herramientas) en vez de texto largo.

### 2.2 Noregon JPRO Professional (Fault Guidance, Repair Mentor, NextStep, Fleet)
Fuentes: https://www.noregon.com/jpro/fault-guidance/ ; https://www.noregon.com/noregon-releases-jpro-professional-2025-v3-software-update/ ; https://www.fleetmaintenance.com/in-the-bay/diagnostic-and-repair/article/55379175/noregon-systems-inc-noregon-expands-jpro-diagnostics-and-guided-troubleshooting
Funciones clave:
- Fault Guidance: al leer un código entrega automáticamente pasos de prueba, procedimientos, diagramas interactivos, datos en vivo y descripciones OEM + SAE mejoradas. Cobertura basada en COMPONENTES (motor Cummins, caja Eaton…) y no en vehículos, por eso cubre camiones nuevos sin esperar actualización.
- Integración con NextStep Repair: pasar de la prueba a la reparación sin abrir otro navegador ni otro dispositivo.
- Afirmación de marketing: reduce el uso de aplicaciones OEM en 35 %.
- 2025-2026: diagnóstico ampliado de bus CAN y troubleshooting guiado de fallas de comunicación con menos pruebas manuales.
Ideas UX:
1. "Siguiente paso" siempre visible: la respuesta termina en una acción concreta (medir X entre pin A y B, esperar Y).
2. Cobertura por componente: indexar manuales por componente (Allison, Bendix, Cummins, WABCO) y reutilizar en cualquier camión que lo tenga.
3. Asistente específico de red CAN (árbol 60/120/40 Ω) — es el problema eléctrico más caro de diagnosticar.
4. Sin cambiar de app: procedimiento, diagrama y OT en la misma vista.

### 2.3 Diesel Laptops — Diesel Repair (web + app 2025), TruckFaultCodes, integración IA con Pitstop
Fuentes: https://www.prnewswire.com/news-releases/diesel-laptops-announces-the-diesel-repair-mobile-app-repair-information-anytime-anywhere-302451201.html ; https://repair.diesellaptops.com/ ; https://www.fleetmaintenance.com/in-the-bay/diagnostic-and-repair/press-release/55016628/pitstop-partners-with-diesel-laptops-on-ai-predictive-analytics ; https://www.diesellaptops.com/community/forums/forums/3355-free-stuff/topics/11112-free-diagnostic-fault-code-information
Funciones clave:
- App Diesel Repair (iOS/Android, mayo 2025): decodificador de VIN diésel (componentes, filtros, correas), búsqueda de códigos OEM y genéricos, diagramas de cableado a color, referencia cruzada de repuestos OEM/aftermarket, misma cuenta en móvil y escritorio.
- TruckFaultCodes: >70.000 DTC categorizados; versión gratuita con info rápida y paga con reparación paso a paso, diagramas y localizador de componentes.
- Con Pitstop (IA predictiva) declaran ahorrar hasta 10 h/semana de diagnóstico por técnico al entender la falla antes de que el camión llegue.
- (DieselTech.AI, https://www.dieseltech.ai/, es un producto distinto de IA de diagnóstico diésel.)
Ideas UX:
1. Decodificar la ficha del camión (patente → motor, caja, ABS, filtros, correas) y mostrarla arriba de cada respuesta.
2. Referencia cruzada de repuestos con stock del inventario SICOM.
3. Búsqueda de código que tolere formatos: "SPN 3251 FMI 0", "3251-0", "P2463", "MID 128 PID 100".
4. Modo sin conexión para las fichas descargadas de los camiones asignados al técnico.

### 2.4 Cummins Guidanz + QuickServe Online (QSOL)
Fuentes: https://www.cummins.com/en-na/parts-and-service/digital-products-and-services/guidanz ; https://play.google.com/store/apps/details?id=com.cummins.guidanz ; https://quickserve.cummins.com/info/qsol/news/cds_reinvention.print
Funciones clave:
- App gratuita: datos de placa del equipo, códigos Cummins PRIORIZADOS con descripción, lectura de códigos J1939 de todos los módulos conectados, compartir por email, idiomas inglés/español/francés.
- "Immediate Assessment" (proveedores certificados): leer el código, evaluar severidad, estimar tiempo de reparación, identificar repuestos probables y abrir la orden de trabajo ANTES de que el equipo llegue al taller.
- Estandarización del contenido de troubleshooting: el mismo árbol en QSOL, Guidanz, Fault Code Analyzer y EDS (una sola verdad).
Ideas UX:
1. "Evaluación inmediata" en el teléfono del supervisor: código → severidad (¿puede seguir operando?) → repuestos → pre-OT.
2. Semáforo de severidad basado en lámpara (RSL/AWL/MIL/PL) + reglas propias de la flota.
3. Botón "Compartir diagnóstico" (WhatsApp/email) con resumen y fuentes.
4. Una sola fuente de verdad: el árbol de diagnóstico se edita en un lugar y se usa en chat, OT y checklist.

### 2.5 Volvo Premium Tech Tool (PTT) + Remote Diagnostics (Volvo/Mack/Renault)
Fuentes: https://www.volvotrucks.us/our-difference/uptime-and-connectivity/remote-diagnostics/ ; https://www.volvotrucks.us/parts-and-services/services/premium-tech-tool/
Funciones clave:
- PTT: diagnóstico, pruebas, programación de ECUs, parametrización (requiere licencia).
- Remote Diagnostics: monitoreo 24/7 de motor, I-Shift y postratamiento; especialistas del Uptime Center analizan el código Y los datos de antes y después del evento; declaran reducir el tiempo de diagnóstico >70 %.
- ASIST: portal para presupuestos electrónicos, aprobar reparaciones y comunicarse con el concesionario; programación remota OTA.
Ideas UX:
1. Mostrar el contexto temporal del código (qué pasaba antes/después: carga, temperatura, altura) si hay telemetría.
2. Plan de acción por código en 3 niveles: "sigue operando" / "programa taller" / "detén el camión".
3. Aprobación de reparación desde el teléfono del jefe (flujo OT existente).
4. Botón "escalar a especialista" que empaqueta códigos, fotos y mediciones.

### 2.6 Mercedes-Benz Trucks — XENTRY + Mercedes-Benz Trucks Uptime
Fuentes: https://www.uptime-info.mercedes-benz.com/ ; https://www.mercedes-benz-trucks.com/gb/en/business-and-services/digital-services/mercedes-benz-trucks-uptime.html ; https://service-info.mercedes-benz-trucks.com/eu/en/workshop-solutions.html
Funciones clave:
- Telediagnóstico automático continuo; ante condición crítica envía datos al back-end; recomendación de acción al cliente en 240 segundos.
- La causa de la falla se conoce antes de llegar al taller: diagnóstico, recomendación clara e identificación de repuestos según instrucciones de reparación; el taller se prepara aunque la visita no esté programada.
- Portal Fleetboard: estado de la flota, desgaste de piezas y fluidos, pronóstico de mantenimientos.
- XENTRY/WIS: diagnóstico y documentación de taller (licencia).
Ideas UX:
1. "Kit de preparación" antes de que el camión llegue: repuestos y herramientas probables para el código.
2. Mensaje de acción en lenguaje simple para el operador/conductor.
3. Integrar desgaste de fluidos/filtros (pauta de mantención SICOM) en la vista de diagnóstico.

### 2.7 Scania SDP3 / SWS (Scania Workshop Solution)
Fuentes: https://www.scania.com/group/en/home/products-and-services/services/rmi/diagnostics.html
Funciones clave:
- SDP3: lectura de códigos, troubleshooting asistido, parametrización, programación; conexión vía VCI (Scania o compatible ISO 22900-2).
- SWS reemplaza gradualmente a SDP3 y cubre hasta los modelos más nuevos.
Ideas UX:
1. Guardar en el Copiloto la "receta" de conexión por marca (qué VCI, qué software, qué licencia) — evita horas perdidas en terreno.
2. Señalar explícitamente "requiere licencia SDP3/SWS" cuando el paso no es realizable con herramienta genérica.

### 2.8 Bosch ESI[tronic] + asistente IA (2026/4)
Fuentes: https://www.bosch-presse.de/pressportal/de/en/efficiently-find-the-right-repair-solution-ai-assistant-optimizes-esitronic-diagnostic-software-from-bosch-283840.html ; https://www.garagewireeurope.com/news/bosch-integrates-ai-assistant-into-esitronic-diagnostic-platform/
Funciones clave:
- El técnico ingresa un código o unas palabras; el asistente analiza datos de diagnóstico, instrucciones de reparación e información del fabricante y entrega sugerencias estructuradas, opciones de reparación y documentos relevantes; permite diálogo continuo y pedir alternativas.
- Anclado en la base Experience-Based Repair (EBR) de Bosch (no chatbot genérico). Llega con la actualización 2026/4 sin costo para paquetes Advanced/Master; premio de innovación Automechanika 2026.
Ideas UX:
1. Respuesta ESTRUCTURADA (no párrafos): causas ordenadas, pruebas, documentos, alternativas.
2. Botón "dame otra alternativa" que excluya lo ya descartado por el técnico.
3. Diálogo que recuerda qué pruebas ya hizo el técnico en esta OT.

### 2.9 Snap-on SureTrack (Real Fixes, Top Repairs / Common Replaced Parts, Smart Data)
Fuentes: https://www.snapon.com/EN/US/Diagnostics/News-Center/Press-Release-Archive/What_Is_SureTrack ; https://www.brakeandfrontend.com/real-fixes-available-on-new-snap-on-suretrack-blog/ ; https://www.snapon.com/DiagnosticsManuals/SureTrack%20Help/Content/Common/SureTrack/Using%20SureTrack%20with%20your%20Diagnostic%20Tool.htm
Funciones clave:
- Real Fixes: casos resueltos en formato queja-causa-corrección, validados por técnicos expertos.
- Top Repairs / Common Replaced Parts: al elegir un DTC muestra un gráfico con el porcentaje de reparaciones verificadas por pieza reemplazada (por kilometraje), derivado de millones de órdenes de trabajo.
- Smart Data: configura automáticamente los parámetros en vivo relevantes para el código, oculta los no relacionados y resalta los que están fuera de rango.
Ideas UX:
1. Gráfico "en nuestra flota, este código se resolvió con…" (% por pieza/causa, N casos) — nuestro equivalente a Top Repairs usando historial OT.
2. Tarjeta Real Fix de 3 líneas (queja/causa/corrección) con link a la OT original.
3. Lista de "parámetros a mirar" por código (Smart Data manual): p. ej. SPN 3251 → ΔP, % hollín, temp. entrada DOC.
4. Validación: un caso sólo se usa como "resuelto" si tiene causa raíz confirmada y el código no volvió.

### 2.10 Mitchell 1 TruckSeries
Fuentes: https://mitchell1.com/truckseries/ ; https://mitchell1.com/truckseries/repair-information/ ; https://www.fleetequipmentmag.com/truck-repair-interactive-wiring-diagrams/
Funciones clave:
- Información de reparación multimarca Clase 4-8; estimación de mano de obra; procedimientos DTC.
- Diagramas interactivos: navegación directa al diagrama del componente con trazas resaltadas; clic en componente → especificaciones, ubicación, vista del conector, pruebas guiadas del componente.
- Búsqueda 1Search Plus; guía de estimación con tiempos, precios OEM y diagramas de piezas en una página; conocimiento SureTrack (>1.000 millones de registros).
Ideas UX:
1. Búsqueda única (código, síntoma, componente, N° de parte) con resultados agrupados.
2. Vista de conector (cara del conector con número de pin) generada desde el manual cuando exista, con cita de página.
3. Presupuesto rápido: tiempo + repuestos + stock.

### 2.11 ServiceMax AI / Copilot (PTC)
Fuentes: https://www.ptc.com/en/news/2025/ptc-launches-servicemax-ai ; https://www.ptc.com/en/products/servicemax/ai-service
Funciones clave: IA generativa (feb-2025) sobre el historial documentado del activo (datos del equipo, historial de servicio, resoluciones conocidas); chat por trabajo/activo; automatiza documentación y agenda; recomendaciones predictivas; Copilot con troubleshooting asistido, captura de conocimiento e insights previos al trabajo; soporte remoto con video/AR.
(No se encontró información pública reciente de "Tweddle" como producto de diagnóstico; se omite.)
Ideas UX:
1. "Resumen previo al trabajo" (pre-job brief): últimas 5 OT del camión, códigos recientes, piezas cambiadas, pauta pendiente.
2. Dictado por voz → el asistente redacta la OT (causa, corrección, tiempo) para que el técnico sólo confirme.
3. Captura de conocimiento: al cerrar OT, preguntar "¿qué fue lo que realmente lo arregló?".

### 2.12 Tractian (CMMS con IA)
Fuentes: https://tractian.com/en/solutions/cmms/mobile-app ; https://tractian.com/en/blog/preserve-maintenance-tribal-knowledge-ai-powered-cmms ; https://tractian.com/en/solutions/integrations/samsara
Funciones clave: app móvil que funciona 100 % sin conexión y sincroniza al reconectar; OT con historial del activo, repuestos y procedimientos paso a paso en el punto de trabajo; IA que identifica patrones de falla y genera procedimientos prescriptivos; fotos, tiempos y cierre desde el teléfono; integración con Samsara/Geotab/Motive para PM por odómetro/horas reales; preservación del conocimiento "tribal".
Ideas UX:
1. Offline-first real (faena sin señal): cola de preguntas y fichas precargadas.
2. Cierre de OT con fotos y mediciones obligatorias según tipo de falla.
3. Preservar conocimiento de técnicos senior como casos citables.

### 2.13 Samsara (Connected Maintenance, Enhanced Fault Code Insights, AI agents)
Fuentes: https://www.ccjdigital.com/technology/artificial-intelligence/article/15749298/samsaras-latest-asset-maintenance-features-utilize-ai ; https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55386202/samsara-samsara-unleashes-agentic-ai-to-free-maintenance-teams-from-monotony ; https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance ; https://kb.samsara.com/hc/en-us/articles/36064344215693-Samsara-Assistant
Funciones clave:
- Fault code intelligence: descifra códigos OEM, explica cómo diagnosticar y reparar, qué herramientas se necesitan; crea órdenes de trabajo con IA.
- Enhanced Fault Code Insights (jun-2026): agrega contexto marca/modelo/año/motor, identifica códigos que suelen preceder fallas mayores, severidad y priorización.
- Agente de mantenimiento: interpreta códigos con manuales de servicio, estima costos, predice fallas con datos de la red, revisa garantía y redacta OT (de 2 horas a 2 minutos según Samsara). Agent Studio para agentes propios (garantías, compras, planificación).
Ideas UX:
1. "Códigos precursores": marcar códigos que en nuestra flota anteceden fallas caras (p. ej. SPN 3719 repetido → DPF retirado).
2. Borrador automático de OT desde el código con repuestos sugeridos.
3. Chequeo de garantía/recall (NHTSA/SERNAC) al abrir la OT.

### 2.14 Fleetio
Fuentes: https://www.fleetio.com/blog/whats-new-fleetio-q1-2025-product-updates ; https://www.fleetio.com/blog/q2-2025-product-updates ; https://www.recyclingtoday.com/news/fleetio-launches-ai-capability-simplify-accelerate-fleet-maintenance-approvals/
Funciones clave: evaluación de OT con IA (qué trabajos están listos, cuáles podrían incluir servicios adicionales); Service Advisor que automatiza aprobaciones rutinarias, marca excepciones, eleva urgencias y resume el historial de servicio y aprobaciones en una narrativa; automatizaciones configurables; soporte en español (Q2-2025).
Ideas UX:
1. Resumen narrativo del historial del camión en 5 líneas.
2. Sugerencia de "aprovechar la parada": servicios de pauta pendientes al abrir una OT correctiva.

### 2.15 Uptake (Fleet)
Fuentes: https://uptake.com/subject-matter/fleet-maintenance/ ; https://marketplace.geotab.com/solutions/uptake/
Funciones clave: reduce miles de códigos a 5-10 problemas accionables por vehículo al año; reconoce qué combinaciones de datos indican falla y cuáles no; integra Samsara/Trimble/Geotab; detecta anomalías de motor, postratamiento y ABS; alerta cuando se disparan códigos potencialmente críticos.
Ideas UX:
1. Filtro de ruido: agrupar códigos por evento y ocultar los "consecuencia" (p. ej. SPN 1569 detrás del código causa).
2. Lista "top 5 problemas de la flota esta semana" para el jefe de mantenimiento.

### 2.16 Otros asistentes IA 2025-2026 para técnicos
Fuentes: https://www.fleetmaintenance.com/shop-operations/article/53096073/ai-the-bodyless-shop-assistant ; https://www.heavyparts.ai/ ; https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance
- Uso más valioso reportado: IA generativa que busca en miles de páginas de manuales PDF para ayudar a técnicos nuevos (Fleet Maintenance).
- Heavy Parts AI: asistente conversacional anclado en catálogos OEM y referencias de servicio para piezas y especificaciones.
- Penske: combina registros de reparación, telemática y contenido de capacitación (Trucking Info).
- Riesgo común: alucinación de valores críticos → nuestra regla de "solo valores con fuente citada" es un diferenciador de confianza.

---

## 3. Patrones de UX para un mecánico con teléfono en terreno (síntesis)

- Pantalla de inicio con 3 botones grandes: **Código**, **Síntoma**, **Camión** (patente/QR en la puerta).
- Entrada por **foto** (tablero con lámparas/códigos, pantalla del escáner, placa del componente) y por **voz** (manos sucias, guantes).
- Respuesta en tarjetas: 1) Qué es (1 línea) 2) Severidad y si puede seguir operando 3) Causas ordenadas con % de la flota 4) Siguiente prueba con valor esperado y fuente 5) Repuestos y stock 6) Casos resueltos similares.
- Cada valor numérico con chip de fuente (manual, página) y nivel de confiabilidad (oficial / técnica / experiencia de campo).
- Checklist interactivo de la prueba guiada donde el técnico ingresa lo medido; el asistente decide el siguiente paso.
- Modo offline, alto contraste para sol, botones de 48 px mínimo, uso con una mano.
- Cierre asistido de OT (voz → causa/corrección/tiempo) que alimenta automáticamente los casos resueltos.

---

## 4. TOP 15 funcionalidades priorizadas para el Copiloto "clase mundial"

Esfuerzo: S = días (≤1 semana), M = 1-3 semanas, L = > 3 semanas. Orden = impacto en tiempo de diagnóstico / esfuerzo, considerando lo que ya existe (RAG de manuales, historial OT, casos resueltos, Next.js/Supabase).

| # | Funcionalidad | Qué hace | Referente | Esfuerzo |
|---|---|---|---|---|
| 1 | Búsqueda de código tolerante + ficha de código | Acepta "SPN 3251 FMI 0", "3251/0", "MID 128 PID 100", "FR/MR", Allison P-codes; muestra descripción, significado del FMI, lámpara, severidad y fuente (usa `codigos/*.json`) | JPRO, Diesel Repair, Guidanz | S |
| 2 | Respuesta estructurada en tarjetas con cita obligatoria por valor | Qué es / severidad / causas / siguiente prueba / fuente; chip de confiabilidad; bloquea valores sin fuente | Bosch ESI AI, regla dura propia | S |
| 3 | Contexto del camión automático | Al elegir patente: marca, modelo, motor, caja, ABS, Euro, faena/altura, últimas OT y códigos; filtra la búsqueda RAG por esa configuración | Diesel Repair VIN decoder, ServiceMax pre-job | S |
| 4 | "En nuestra flota esto se resolvió con…" | Ranking de causas/piezas por código+modelo desde historial OT (N casos, % y link a la OT) | Snap-on Top Repairs, Real Fixes | M |
| 5 | Pruebas guiadas interactivas con valores esperados | Checklist paso a paso (p. ej. red CAN 60/120/40 Ω; arranque Delco Remy); el técnico ingresa la medición y el sistema elige el siguiente paso | JPRO Fault Guidance, Jaltest | M |
| 6 | Semáforo de severidad / "¿puede seguir operando?" | Regla por lámpara (RSL/AWL/MIL/PL), FMI y reglas de flota; mensaje simple para operador y supervisor | Guidanz Immediate Assessment, Volvo Remote Dx | S |
| 7 | Entrada por foto y voz | OCR de pantalla del escáner/tablero y placas; dictado en español con jerga local | Samsara Assistant, Tractian | M |
| 8 | Cierre de OT asistido y captura de caso resuelto | Voz → queja/causa/corrección/tiempo/mediciones; exige causa raíz y verificación para publicarlo como caso | SureTrack Real Fixes, ServiceMax | M |
| 9 | Filtro de ruido de códigos | Agrupa códigos por evento, oculta "consecuencia" (SPN 1569, 5246) detrás de la causa, detecta FMI 9/19 múltiples → sugiere revisar red | Uptake, Samsara Insights | M |
| 10 | Parámetros a mirar por código (Smart Data manual) | Lista de datos en vivo relevantes y rango esperado por código (p. ej. SPN 3251 → ΔP, % hollín, T° DOC) | Snap-on Smart Data | S |
| 11 | Repuestos probables + stock + pre-OT | Desde el código sugiere repuestos (historial) y consulta inventario SICOM; crea borrador de OT | Mercedes Uptime, Samsara agent, Guidanz | M |
| 12 | Modo offline-first | Fichas y manuales de los camiones asignados precargados; cola de preguntas sin señal; sincroniza al volver | Tractian | L |
| 13 | Ficha de componente/conector con ubicación y pinout citado | Página del manual (imagen recortada) con ubicación, vista del conector y pines; enlazable desde cualquier respuesta | Jaltest, Mitchell 1 | L |
| 14 | Alertas de códigos precursores y recurrentes | Detecta códigos que en la flota anteceden fallas caras o que reaparecen tras reparación (retrabajo) | Samsara Enhanced Insights, Uptake | M |
| 15 | Escalar a especialista con paquete completo | Botón que envía códigos, freeze frame, mediciones, fotos y pasos ya hechos a supervisor/concesionario (WhatsApp/email) | Volvo ASIST, Guidanz compartir | S |

Notas de implementación:
- #1, #2, #6, #10 aprovechan directamente `codigos/j1939-generico.json` y las fichas de `metodologia-diagnostico.md`.
- #4 y #14 requieren normalizar en Supabase el campo "código" de las OT (SPN, FMI, MID, formato) y un campo "causa raíz confirmada" (boolean) para no contaminar el ranking.
- #5 conviene modelarlo como árboles JSON versionados (nodo = prueba, valor esperado, fuente, siguiente nodo) en lugar de texto libre, para que sean auditables.
- Evaluación continua: medir tiempo de diagnóstico por OT, tasa de "primera reparación correcta" y retrabajos dentro de 30 días, antes/después del Copiloto.
