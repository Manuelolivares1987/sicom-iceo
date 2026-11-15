# Telemática internacional: cómo Samsara, Geotab, Motive y Verizon Connect cruzan la tarjeta de combustible con el GPS (benchmark 2025-2026)

Fecha de investigación: 2026-11-15. Fuentes: páginas del proveedor, centros de ayuda, comunicados de prensa, prensa especializada (CCJ, Overdrive, HDT) y agregadores de precios. Algunos centros de ayuda (kb.samsara.com, fleet-help.verizonconnect.com, helpcenter.gomotive.com/Fuel-Reports-and-Alerts) devolvieron HTTP 403 al descargarlos directamente. En esos casos el contenido viene de los fragmentos del buscador y va marcado como tal.

## P1. ¿Qué controles de fraude y desperdicio aplica cada uno?

### Conclusión
Los cuatro hacen el control básico: comparan la posición del vehículo con la de la estación a la hora de la transacción. Lo que cambia entre ellos son los umbrales: Samsara usa 100 m/±10 min, Geotab 1 km/±3 h y Verizon 0,5 mi/60 min. Motive y Samsara (y Geotab a través de su Fleet Card) también comparan el **alza del nivel del estanque medida por sensor/CAN con los litros facturados**. Geotab y Verizon documentan los controles de **capacidad del estanque** y de **tipo de combustible**. En ningún proveedor encontré documentado un control nativo de km/L esperado por transacción. Tampoco encontré uno de «varias cargas el mismo día» como regla con nombre: se aproxima con límites de gasto por frecuencia o período.

### Hallazgos con fuente

**Samsara**
- El informe Fuel Purchases (Fuel & Energy > Fuel Purchases) cruza las compras con el seguimiento del vehículo. Estado **Verified**: algún vehículo de la flota estuvo dentro de **100 m** de la estación y **±10 min** de la transacción. Estado **Unverified**: no hubo ninguno. Estado **Processing**: la compra aún no se analiza. El administrador puede reasignar el vehículo y cambiar el estado a mano. Fuente: fragmento del buscador de [kb.samsara.com 360043272731](https://kb.samsara.com/hc/en-us/articles/360043272731) (403 al descargar).
- Para las transacciones que llegan por integración, otro artículo de ayuda indica 100 m y **20 min**. Contradice los 10 min anteriores y el artículo estaba truncado, así que hay que verificarlo. Fuente: [Samsara help (zendesk) 26052857105805](https://samsara1678209876.zendesk.com/hc/articles/26052857105805).
- Las compras sin verificar **igual cuentan** en los galones con impuesto pagado del informe IFTA. Fuente: fragmento de [kb.samsara.com](https://kb.samsara.com/hc/en-us/articles/360043272731).
- «Advanced Fuel Insights» (22-05-2025) incluye tres funciones. (a) Alertas en tiempo real por **caída brusca del nivel ≥5 %**, con hora y lugar (robo/sifonaje). (b) Detección de fraude en compras: un umbral configurable de **alza del nivel del estanque** se combina con la proximidad del vehículo, y las transacciones sin verificar se muestran en un mapa. Requiere integrar la tarjeta o subir la boleta. (c) Captura de boletas con IA para flotas sin tarjeta. Fuente: [Samsara blog: Announcing Advanced Fuel Insights](https://www.samsara.com/blog/announcing-advanced-fuel-insights).
- Los umbrales de la alerta por caída de nivel no coinciden entre páginas. La página de producto dice 5 %, una página de soluciones dice 10 % y la ayuda recomienda ≥20 % en una ventana corta, por ejemplo 6-10 min. Las alertas se configuran en el panel o por API y pueden disparar un webhook. Fuentes: [Página de producto Samsara Fuel](https://www.samsara.com/products/telematics/fleet-fuel-management-system); [Samsara solutions](https://samsara.com/solutions/fleet-fuel-management-system); [Integración de tarjetas de combustible (developers)](https://developers.samsara.com/docs/fuel-card-integration).
- Limitación reportada por un cliente (Egertons, Reino Unido, junio 2025): la alerta de caída llega «solo cuando el camión se vuelve a encender». Fuente: [Samsara UK blog: Egertons](https://www.samsara.com/uk/blog/egertons-targets-fuel-theft-and-operational-waste-with-samsara).
- La app de marketplace **Fleevo Fuel Analytics** marca transacciones sospechosas según ubicación, tipo de combustible, **nivel de combustible** y tipo de producto. También detecta **tarjetas compartidas** entre vehículos o conductores. Fuente: [Samsara Marketplace: Fleevo](https://samsara.com/resources/marketplace/fleevo-fuel-analytics).
- Según CCJ, **Comdata** usa el GPS en tiempo real de Samsara para comparar la ubicación del vehículo con la estación «en el milisegundo exacto» en que se pasa la tarjeta. Con la integración **Coast** se puede bloquear la transacción si el vehículo asignado no está presente. Fuente: [CCJ: Transaction data and analytics spot inefficiencies](https://www.ccjdigital.com/technology/asset-tracking-management/article/15829375/transaction-data-reveals-hidden-fuel-savings).
- Con **RoadFlex** (25-08-2025), Samsara entrega la ubicación y el odómetro para validar cada transacción. Hay alertas instantáneas por infracción de la política, y las compras que no cumplen se marcan o bloquean. Fuente: [Samsara blog: fuel fraud in public fleets](https://www.samsara.com/blog/the-high-cost-of-fuel-fraud-and-how-public-fleets-can-prevent-it).
- El marketplace de Samsara incluye integraciones con WEX/EFS, Shell, Petro-Pass, Allstar (Reino Unido) y AtoB, entre otras. Fuentes: [WEX/EFS](https://www.samsara.com/resources/marketplace/efs-fuel-card); [Shell](https://www.samsara.com/resources/marketplace/shell-fuel-card); [AtoB](https://atob.com/samsara).

**Geotab (MyGeotab + Marketplace + Geotab Fleet Card)**
- La página **Fuel Transactions** marca tres discrepancias:
  - **Location mismatch**: la posición registrada del activo está a más de ~**1 km (0,6 mi)** de la estación. Para la posición más cercana revisa una ventana de **±3 h** alrededor de la transacción.
  - **Tank size mismatch**: el volumen comprado supera en más de **110 %** la capacidad registrada del estanque.
  - **Fuel type mismatch**: el producto de la transacción no coincide con el combustible del activo.

  Fuente: [Geotab Support: Fuel Transactions](https://support.geotab.com/help/mygeotab/energy-and-sustainability/fuel/fuel-transactions).
- **Identidad del conductor**: la asignación puede ser por activo o por conductor. En el modo por conductor se exige que el nombre del titular de la tarjeta coincida exactamente con el conductor en MyGeotab, y se usa el activo asignado a ese conductor en el momento de la carga. Si después se cambia el tipo de combustible, el estanque o el conductor, las transacciones pasadas **no se reprocesan**. Fuente: [Geotab Support: Fuel Transactions](https://support.geotab.com/help/mygeotab/energy-and-sustainability/fuel/fuel-transactions).
- Ese artículo **no** cubre la comparación del alza del nivel del estanque con lo facturado. Fuente: el mismo artículo.
- Las transacciones entran por cuatro vías: importación automática con el Add-In Fuel Transaction Provider (WEX, Corpay y Voyager en EE. UU.), registro del conductor con el Add-In Fuel Tracker en la app Drive, carga masiva con el Add-In Fuel Transaction Import, o archivo CSV/XLSX. Fuente: [Geotab Support: Fuel Transactions](https://support.geotab.com/help/mygeotab/energy-and-sustainability/fuel/fuel-transactions).
- **Geotab Fleet Card**, lanzada el 01-10-2026 y emitida y operada por **AtoB**:
  - La tarjeta queda **bloqueada** hasta que el conductor la desbloquea en Geotab Drive con el vehículo estacionado en el comercio.
  - La compra se rechaza si el vehículo no está en la bomba o si el estanque **no tiene espacio** para el volumen.
  - También verifica las coordenadas GPS del comercio.
  - Permite reglas por monto, período, ubicación y categoría de comercio.

  Fuente: [Comunicado de prensa de Geotab: Geotab Fleet Card](https://www.geotab.com/press-release/geotab-fleet-card/).

**Motive (Motive Card)**
- Controles anunciados el 05-12-2024:
  1. **Discrepancia entre ubicación del vehículo y del gasto**, con alerta por IA y **rechazo automático**.
  2. **Discrepancia de tipo de combustible**: alerta y opción de congelar la tarjeta o bloquear el comercio.
  3. **Discrepancia entre nivel de combustible y gasto**.
  4. **Límites de gasto por categoría**: tipo de comercio, **hora del día**, **día de la semana**, ciclo de facturación y ubicación de la transacción.

  Fuente: [Comunicado de prensa de Motive, 05-12-2024](https://gomotive.com/motive-adds-the-industrys-most-comprehensive-fuel-fraud-controls-to-motive-card-to-stop-fraud-on-the-spot-2024-12-5/).
- **Discrepancia entre nivel de combustible y gasto**: marca la transacción cuando el estanque no sube en proporción a lo comprado. Distingue tres escenarios: se excede la capacidad total, el volumen no cuadra con el alza, o el nivel no sube nada. El detalle muestra combustible comprado, nivel esperado, nivel real, lugar, vehículo y hora. La capacidad del estanque se **estima a partir de cargas anteriores** y se puede corregir en el perfil del vehículo. Fuente: [Motive Help: Fuel Level and Spend Mismatch](https://helpcenter.gomotive.com/hc/en-us/articles/18269694656669-Fuel-Level-and-Spend-Mismatch).
- Existe un artículo de ayuda aparte para **Fuel Type Mismatch**: [Motive Help: Fuel Type Mismatch](https://helpcenter.gomotive.com/hc/en-us/articles/21982941719965-Fuel-Type-Mismatch).
- Otro artículo, «Fuel Theft Prevention When Vehicle Gateway Data is Unreliable», explica qué hacer cuando no hay datos del gateway. Solo vi el título, no el contenido. Fuente: [Motive Help](https://helpcenter.gomotive.com/hc/en-us/articles/28704525446941-Fuel-Theft-Prevention-When-Vehicle-Gateway-Data-is-Unreliable).
- Según la prensa especializada, el sistema analiza la ubicación del vehículo y de la compra en el momento de la transacción, y también el monto. Puede rechazar y alertar en tiempo real. Ejemplo de alerta: se compraron X galones y el nivel del estanque no cambió. Fuentes: [CCJ](https://www.ccjdigital.com/technology/article/15709325/motive-rolls-out-new-aipowered-tools-to-detect-fraudulent-transactions-and-reduce-costs); [Overdrive](https://www.overdriveonline.com/gear/article/15709850/fuel-purchase-fraud-in-eye-of-motive-card-system-updates).

**Verizon Connect**
- Informe **Fuel Card Match Detail**: hay *match* si el vehículo estuvo a **≤0,5 mi (~800 m)** de la estación dentro de **60 min** de la compra. Si no, queda *unmatched* «y normalmente debe revisarse». En los casos sin coincidencia el informe muestra la ubicación real del vehículo y **qué vehículo y conductor sí estaban en la estación**. Columnas: Match, Driver, Teams, Vehicle, Fleets, Most Recent Vehicle Report, Vehicle Location, Vehicle and Driver at Location, Account Number, los últimos 5 dígitos de la tarjeta, Purchase Date y Purchase Address. Requiere el **Fuel Module**. Fuente: [Verizon Connect Platform Help: Fuel Card Match Detail Reports](https://platform-help.verizonconnect.com/fleet_fuel_card_match_detail_reports.htm).
- Excepciones relacionadas en los ajustes del informe: exceso de velocidad (Max Speed), **ralentí excesivo (Max Idle)** y detención larga (Max Stop Time). Fuente: la misma página.
- **Compras que exceden la capacidad del estanque**, alerta de que el vehículo «no estaba en la bomba» y control del gasto con tarjeta contra el **presupuesto**. Fuente: [Verizon Connect: fleet fuel management software](https://www.verizonconnect.com/features/fleet-fuel-management-software/).
- Informe **Lost Fuel**: cruza la transacción con el vehículo asignado según dónde estaba el vehículo, el sitio de la compra y si se compró combustible en exceso. Fuente: solo el fragmento del buscador de [fleet-help.verizonconnect.com](https://fleet-help.verizonconnect.com/hc/en-us/articles/360010682640) (403). La página de producto no lo menciona.
- Las compras de FLEETCOR se importan **cada noche**. Las integraciones incluyen WEX, Comdata, Fuelman, Corpay/FLEETCOR, AmeriFuel y, en Reino Unido, Allstar y The Fuel Card Company. Fuentes: [Verizon Marketplace: FLEETCOR](https://www.verizonconnect.com/solutions/marketplace/fleetcor); [WEX](https://www.verizonconnect.com/solutions/marketplace/wex-inc/); [Comdata](https://www.verizonconnect.com/solutions/marketplace/comdata).

### Matriz resumen (D = documentado, P = solo partner/marketplace, — = no encontrado)
| Control | Samsara | Geotab | Motive | Verizon |
|---|---|---|---|---|
| Ubicación del vehículo vs estación | D (100 m/±10 min) | D (1 km/±3 h); rechazo con Fleet Card | D + rechazo automático | D (0,5 mi/60 min) |
| Litros vs capacidad del estanque | P (Fleevo) / implícito en el control de alza | D (>110 %); rechazo con Fleet Card | D (capacidad estimada por cargas anteriores) | D |
| Alza del nivel del sensor vs litros facturados | D (Advanced Fuel Insights) | — en Fuel Transactions; la Fleet Card usa el espacio libre del estanque | D (3 escenarios) | — |
| Tipo de combustible | P (Fleevo) | D | D | — |
| Hora del día / fuera de horario | P (reglas del emisor de la tarjeta) | Reglas de período (Fleet Card) | D (límites por hora/día) | — |
| Identidad del conductor | Reasignación manual | D (match de nombre) + desbloqueo en la app | Desbloqueo de la tarjeta | Muestra el conductor que estaba en la estación |
| Varias cargas el mismo día | — (P: tarjeta compartida con Fleevo) | — | Límites por período | — |
| km/L esperado por transacción | — | — | — | — |
| Robo por caída de nivel | D (≥5-20 %) | — | — | — |
| Costo del ralentí | Informes de ralentí | — (prensa: herramientas de ralentí) | — | Excepción Max Idle |

### Inferencias
- La ventana más estricta es la de Samsara (100 m/10 min) y la más laxa la de Geotab (±3 h). Geotab tolera huecos de GPS, pero a cambio deja pasar fraudes cerca de la estación.
- Comparar el alza del nivel del estanque con los litros facturados es lo que separa a Motive y Samsara del resto. Funciona solo si hay sensor o CAN de nivel confiable, y Motive excluye explícitamente de su garantía los casos sin datos del sensor.
- El rendimiento (km/L o MPG) se usa como **indicador de tendencia** por vehículo, no como regla que marque una transacción concreta.

### Pendientes
- Contenido completo de kb.samsara.com y de los artículos de Verizon y de Motive «Fuel Reports and Alerts»: el servidor bloqueó la descarga (403).
- No encontré documentación de una regla nativa de «varias cargas en el día» ni de km/L esperado por carga en ninguno de los cuatro.

## P2. ¿Alertas en tiempo real o por lote? ¿Bloqueo en la bomba? ¿Cómo se revisan las transacciones marcadas?

### Conclusión
Solo los proveedores que **emiten su propia tarjeta** pueden bloquear en la bomba: Motive Card (desde dic-2024) y Geotab Fleet Card (desde oct-2026, vía AtoB). Samsara bloquea a través de partners (Coast, RoadFlex, Comdata). Verizon y el modo «integración» de Samsara y Geotab trabajan **por lote**: importan después de la carga, a menudo cada noche, y marcan la transacción a posteriori. El flujo de revisión más explícito es el de Motive: marcar como Reviewed, notas para otros administradores y congelar la tarjeta.

### Hallazgos con fuente
- **Motive**: rechazo automático por discrepancia de ubicación y por «Fuel Level Exceeds Threshold», más desbloqueo de la tarjeta, Spend Controls y Merchant Controls. Para tener la garantía antifraude al menos uno debe estar activo. Fuente: [Motive Fraud Protection Guarantee](https://gomotive.com/legal/fraud-protection-guarantee/).
- **Motive**, flujo de revisión: «Mark a flagged transaction as Reviewed», agregar notas para otros administradores y congelar la tarjeta. Las alertas llegan al Notification Center, y si se marcan como «Important» la notificación es inmediata. Fuente: [Motive Help: Fuel Level and Spend Mismatch](https://helpcenter.gomotive.com/hc/en-us/articles/18269694656669-Fuel-Level-and-Spend-Mismatch).
- **Motive**: alertas instantáneas y «Control Spend in Real Time». Fuente: [Comunicado de prensa de Motive](https://gomotive.com/motive-adds-the-industrys-most-comprehensive-fuel-fraud-controls-to-motive-card-to-stop-fraud-on-the-spot-2024-12-5/).
- **Geotab Fleet Card**: autorización dinámica en tiempo real que bloquea **antes** de la carga, a diferencia de las tarjetas que alertan después. En MyGeotab se revisan transacciones, aprobaciones y rechazos. Fuente: [Comunicado de prensa de Geotab](https://www.geotab.com/press-release/geotab-fleet-card/).
- **Geotab Fuel Transactions** (integración): es una revisión por lote. La columna Potential issues muestra la discrepancia principal más «+N» adicionales. Las tarjetas de conteo filtran la tabla y el botón «Not assigned» asigna a mano las transacciones sin activo. **No** se describe un estado de descartar o justificar. Aviso explícito: las discrepancias «indican anomalías de datos, no son prueba de fraude», no deben ser la única base para decisiones laborales y todo debe investigarse. Fuente: [Geotab Support: Fuel Transactions](https://support.geotab.com/help/mygeotab/energy-and-sustainability/fuel/fuel-transactions).
- **Samsara**: cambio manual de estado y vehículo en Fuel Purchases. Fuente: fragmento de [kb.samsara.com](https://kb.samsara.com/hc/en-us/articles/360043272731). La alerta por caída de nivel es en tiempo real, pero un cliente reporta que llega recién al encender el camión. Fuentes: [Advanced Fuel Insights](https://www.samsara.com/blog/announcing-advanced-fuel-insights); [Egertons](https://www.samsara.com/uk/blog/egertons-targets-fuel-theft-and-operational-waste-with-samsara). El bloqueo en la bomba solo existe vía Coast, RoadFlex o Comdata. Fuentes: [CCJ](https://www.ccjdigital.com/technology/asset-tracking-management/article/15829375/transaction-data-reveals-hidden-fuel-savings); [Samsara blog: RoadFlex](https://www.samsara.com/blog/the-high-cost-of-fuel-fraud-and-how-public-fleets-can-prevent-it).
- **Verizon**: alertas «casi en tiempo real» por SMS o app según su página de producto. Fuente: [Verizon Connect: fuel management](https://www.verizonconnect.com/features/fleet-fuel-management-software/). En la práctica, la importación de FLEETCOR es **nocturna**, lo que da un desfase de hasta un día. Fuente: [Verizon Marketplace: FLEETCOR](https://www.verizonconnect.com/solutions/marketplace/fleetcor). El informe solo dice «unmatched → follow up», sin un flujo formal de cierre. Fuente: [Platform Help](https://platform-help.verizonconnect.com/fleet_fuel_card_match_detail_reports.htm).

### Inferencias
- El patrón de mercado distingue dos niveles. El **nivel 1** es la integración: importación con desfase, marca a posteriori y revisión manual. El **nivel 2** es la tarjeta propia: autorización en línea con GPS y nivel del estanque y rechazo en la bomba. Para una herramienta interna sin emisor propio, el nivel 1 con buena trazabilidad es lo que se puede replicar.
- Ninguno documenta con claridad una justificación obligatoria con causal tipificada ni un log de auditoría inmutable. Motive (Reviewed + notas) es lo más cercano.

### Pendientes
- No encontré documentación de flujos de aprobación por niveles ni de exportación de la bitácora de auditoría en ninguno de los cuatro.

## P3. KPIs y paneles de combustible para la gerencia

### Conclusión
Los paneles se centran en el rendimiento por vehículo y conductor, el ralentí, el IFTA, las compras y el conteo de discrepancias. Verizon es el único que menciona explícitamente el **gasto contra presupuesto**. Samsara agrega precios de combustible cercanos y benchmarks. Ninguno publica un KPI estándar de «ahorro logrado» en el producto.

### Hallazgos con fuente
- **Geotab**: tarjetas con el conteo por tipo de discrepancia (ubicación, estanque, tipo, sin asignar), un gráfico «Trend: Fuel Purchased» comparado con el período anterior y el informe descargable Fuel Transaction Report. Las antiguas páginas Fill-ups y Fuel Mismatch ya no muestran transacciones. Fuente: [Geotab Support: Fuel Transactions](https://support.geotab.com/help/mygeotab/energy-and-sustainability/fuel/fuel-transactions); [Nueva página de transacciones de combustible (product update)](https://support.geotab.com/product-updates/new-fuel-transactions-page-general-availability).
- **Geotab** publica una checklist de auditoría del gasto en combustible: [Geotab fuel spending audit checklist (PDF)](https://www.geotab.com/CMS-GeneralFiles-production/NA/Checklist/fleet-fuel-spending-audit-checklist-MPROD-1721-EN-NA-checklist-final-aoda.pdf). No la revisé en detalle.
- **Samsara**: Driver Efficiency Report, informes de ralentí (reglas personalizadas, alerta de audio en cabina según el clima, ralentí incorporado al coaching), Fuel Purchase Reports, Fuel Price Insights (precios cercanos frente a dónde cargan los conductores), benchmarks contra pares e IFTA. Fuente: [Advanced Fuel Insights](https://www.samsara.com/blog/announcing-advanced-fuel-insights).
- **Verizon**: historial de transacciones por vehículo con comparación de compras y MPG entre vehículos, eficiencia por vehículo (ralentí, velocidad, mantención), CO2, IFTA por estado, benchmarks históricos y **gasto de tarjeta contra presupuesto**. Fuente: [Verizon Connect: fuel management](https://www.verizonconnect.com/features/fleet-fuel-management-software/).
- **Motive**: un panel único que reúne telemática y gasto. Fuente: [Comunicado de prensa de Motive](https://gomotive.com/motive-adds-the-industrys-most-comprehensive-fuel-fraud-controls-to-motive-card-to-stop-fraud-on-the-spot-2024-12-5/); [Motive spend management](https://gomotive.com/spend-management). El artículo «Fuel Reports and Alerts» no se pudo leer (403).

### Inferencias
- El costo por km y la tendencia de km/L se derivan de los datos de distancia y combustible, pero ninguna fuente pública los muestra como KPI con nombre en un panel ejecutivo de combustible.

### Pendientes
- No pude ver capturas ni listas completas de los informes de Motive (403).

## P4. Ahorros y reducción de fraude publicados, con sus advertencias

### Conclusión
Todas las cifras vienen del propio proveedor: pruebas internas, estimaciones con supuestos o casos de clientes elegidos por él. No encontré validación independiente.

### Hallazgos con fuente
- **Motive**: en una prueba de 30 días con clientes identificó más de **US$250.000** en más de **1.200 transacciones no autorizadas**. Cita investigación según la cual el **19 %** del gasto de flota se pierde por fraude o robo, y estima que integrar combustible y gestión de flota ahorra **6,6 %** del gasto en combustible. Advertencia: son cifras del proveedor, sin verificación independiente. Fuente: [Comunicado de prensa de Motive](https://gomotive.com/motive-adds-the-industrys-most-comprehensive-fuel-fraud-controls-to-motive-card-to-stop-fraud-on-the-spot-2024-12-5/); [Work Truck Online](https://www.worktruckonline.com/news/motive-launches-ai-powered-fuel-fraud-controls).
- **Geotab**: para una flota hipotética de 500 camiones Clase 8 con US$31,3 M de gasto anual en combustible, estima ~**US$2,19 M** evitables suponiendo una tasa de fraude del **7 %**. Advertencia: es un supuesto, no una medición. Su análisis de 419.000 cargas diésel encontró hasta **77 ¢/gal** de diferencia entre estaciones del mismo pueblo, ~US$58 en una carga de 75 gal. Fuente: [Comunicado de prensa de Geotab](https://www.geotab.com/press-release/geotab-fleet-card/).
- **Samsara**: Gordon Food Service bajó el ralentí de hasta 17 % a menos de 5 % y ahorró **US$2,5 M** en combustible en un año. Liberty Energy ahorra **US$10 M/año en impuestos** a los combustibles, lo que no es fraude. Cita que entre el 5 y el 10 % del consumo anual se pierde por robo o mala asignación (fuente de terceros). Fuente: [Advanced Fuel Insights](https://www.samsara.com/blog/announcing-advanced-fuel-insights).
- **Samsara + RoadFlex**: un conductor que carga su vehículo personal dos veces por semana puede costar más de US$4.000 al año. Si el 10 % de la flota usa mal la tarjeta, una agencia mediana podría perder más de US$50.000 al año. Advertencia: viene de una encuesta «próxima a publicarse» de RoadFlex. Fuente: [Samsara blog](https://www.samsara.com/blog/the-high-cost-of-fuel-fraud-and-how-public-fleets-can-prevent-it).
- **Verizon**: su página de combustible no trae cifras de ahorro en combustible. El único caso con dólares es de seguros: US$200.000 de B.A.M. Trucking. Fuente: [Verizon Connect: fuel management](https://www.verizonconnect.com/features/fleet-fuel-management-software/).

### Inferencias
- Para un caso de negocio interno, lo prudente es usar el rango de 5 a 10 % de pérdida por robo o mala asignación que cita Samsara (de terceros) como hipótesis y medirlo con datos propios. Las cifras del 19 % de Motive y del 7 % de Geotab son supuestos de marketing.

### Pendientes
- No encontré estudios independientes (FleetOwner, ATRI o académicos) que midan la reducción de fraude atribuible a estos productos.

## P5. Precios públicos

### Conclusión
Ninguno publica una lista de precios completa. Los agregadores estiman entre **US$20 y 50 por vehículo al mes** solo en software. Las tarjetas propias (Motive Card y Geotab Fleet Card) no cobran mensualidad y se financian con el intercambio y la red de descuentos.

### Hallazgos con fuente
- Estimaciones de agregadores, con fuentes que no siempre coinciden. **Samsara**: ~US$27-33/veh/mes (CostBench dice 27-50), y US$40-60 con cámaras. **Motive**: US$25-33/veh/mes más ~US$150 por el hardware ELD. **Geotab**: Base US$30, Pro US$35, ProPlus US$40 por vehículo al mes, o US$15 en modalidad de compra (lo vende un revendedor, así que varía). **Verizon Connect**: Core US$20 y Advanced US$28, o US$20-23,50 con contrato de 3 años. Fuentes: [CostBench 2026](https://costbench.com/stats/fleet-management-pricing-2026/); [CostBench Geotab vs Verizon](https://costbench.com/compare/geotab-vs-verizon-connect/); [AuthenCIO: precios Motive](https://www.authencio.com/blog/motive-pricing-compare-plans-fees-top-alternatives); [Expert Market](https://www.expertmarket.com/fleet-management/best-cheap-gps-tracking).
- **Geotab Fleet Card**: sin costo de activación ni de uso, sin cuota mensual. Descuentos mayoristas en más de 34.000 estaciones de EE. UU. (no publica el porcentaje). Garantía antifraude de hasta US$250.000 para cuentas elegibles en transacciones verificadas por telemática. Solo para EE. UU. Fuente: [Comunicado de prensa de Geotab](https://www.geotab.com/press-release/geotab-fleet-card/).
- **Motive Card**: descuentos en más de 26.000 ubicaciones. Fuente: [Comunicado de prensa de Motive](https://gomotive.com/motive-adds-the-industrys-most-comprehensive-fuel-fraud-controls-to-motive-card-to-stop-fraud-on-the-spot-2024-12-5/). La garantía antifraude (vigente desde el 22-04-2025) cubre hasta US$25.000/año si el límite de crédito anualizado es menor a US$1 M, y hasta US$250.000/año si es de US$1 M o más. El tope es US$15.000 por tarjeta. Hay que reportar dentro de **72 h**. Excluye el fraude «amistoso» (de empleados), las transacciones aprobadas a mano y las que no tienen datos del gateway o del sensor de nivel. No es un seguro. Fuente: [Motive Fraud Protection Guarantee](https://gomotive.com/legal/fraud-protection-guarantee/).
- **Verizon**: el módulo de combustible es un complemento de pago (Fuel Module) sin precio público. Fuente: [Platform Help](https://platform-help.verizonconnect.com/fleet_fuel_card_match_detail_reports.htm).

### Inferencias
- Las garantías de Motive y Geotab **excluyen el fraude interno de empleados**, que es justamente el riesgo principal de una flota propia con choferes. El valor de la herramienta interna está en detectar ese fraude interno, que las garantías no cubren.

### Pendientes
- No encontré el precio del Fuel Module de Verizon ni el de las apps de marketplace (Fleevo y otras). Todos los productos de tarjeta son de EE. UU. o Canadá. No hay equivalente para Chile en estas fuentes.
