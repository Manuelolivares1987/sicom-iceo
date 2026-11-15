# Control de combustible en flotas corporativas: Chile y LatAm (benchmark para SICOM)

Contexto: SICOM controla unas 13 camionetas con tarjeta Aramco Fleet y GPS Navixy (Coquimbo/Calama). Investigación del 15-11-2026, con 15 llamadas de herramientas. Muchas fichas de producto de las tarjetas chilenas son folletos PDF antiguos o páginas que hoy dan 404 (el PDF de Shell Card Transporte de Enex y la página Aramco Fleet de Esmax dieron 404, y tarjetaflota.petrobras.cl no resuelve DNS). Algunos datos vienen del resumen del buscador y no de una lectura directa de la página; se marcan así.

## 1. Qué controles ofrecen las tarjetas de combustible chilenas (límites, productos, horario, estaciones, PIN, odómetro, conductor, alertas, bloqueo, API, GPS)

### Takeaway
Las tres grandes redes (Copec, Enex/Shell, Esmax/Aramco) ofrecen lo básico: límites por vehículo en litros o monto y en número de cargas por período, estaciones permitidas, PIN y reportes en portal. Copec TCT es la más completa: alertas por SMS o correo (2 o más cargas en una hora, fuera de horario, sobre el límite), un web service para grandes clientes y, en TCT Premium, verificación física de que el vehículo está presente con un anillo en la boca del estanque. Ninguna fuente muestra que una tarjeta chilena cruce sus transacciones con la posición GPS del vehículo. Eso sí existe en México (Edenred Ticket Car+).

### Cited Findings
**Copec TCT / TCT Premium (flota pesada, diésel)**
- TCT permite fijar "límites de consumo específicos para cada vehículo": litros por carga, frecuencia de uso y estaciones donde puede cargar. Productos: diésel, lubricantes y Bluemax (AdBlue). — [Copec TCT y TCT Premium](https://ww2.copec.cl/empresas/productos-y-servicios/productos/medios-de-pago/tct)
- Seguridad: chip "imposible de clonar" más clave secreta (PIN). Las restricciones quedan grabadas en el chip. — [Copec TCT](https://ww2.copec.cl/empresas/productos-y-servicios/productos/medios-de-pago/tct)
- Alertas por SMS o e-mail, por ejemplo "Alarma por 2 o más cargas dentro de una hora", transacciones fuera de horario y consumos sobre un límite. En la intranet del cliente se eligen qué mensajes recibir. — [Copec TCT](https://ww2.copec.cl/empresas/productos-y-servicios/productos/medios-de-pago/tct)
- Reportes diarios, quincenales y mensuales con rendimiento por vehículo, número de cargas, volumen por estación y ruta. La compra aparece en la web TCT minutos después de hecha. — [Copec TCT](https://ww2.copec.cl/empresas/productos-y-servicios/productos/medios-de-pago/tct); [búsqueda: folleto TCT](https://copec.cdn.modyo.com/uploads/d7af6840-796d-4221-8653-3800610e48fb/original/Folleto_TCT_Premium.pdf)
- Integración: existe un "Sistema Web Service" para grandes clientes que entrega los datos de consumo a sus propios sistemas. Es la única API de tarjeta chilena encontrada. — [Copec TCT](https://ww2.copec.cl/empresas/productos-y-servicios/productos/medios-de-pago/tct)
- TCT Premium agrega "verificación de presencia vehicular": un anillo en la boca del estanque y un lector en la pistola. Si la pistola se aleja del lector, el flujo se corta. Funciona solo en estaciones habilitadas. — [Copec TCT](https://ww2.copec.cl/empresas/productos-y-servicios/productos/medios-de-pago/tct)
- Los límites se definen al pedir la tarjeta o al reponerla, o se cambian en la web TCT (folleto antiguo, resumen del buscador). Los reportes incluyen odómetro y rendimiento. — [Folleto TCT (silo.tips)](https://silo.tips/download/tarjeta-copec-transporte-para-el-control-de-su-flota)
- Copec NeoTAC, otro producto de gestión: el conductor registra el odómetro al cargar y la carga se rechaza si viola las restricciones; también alerta niveles críticos de combustible (resumen del buscador). — [Copec NeoTAC](https://ww2.copec.cl/empresas/productos-y-servicios/servicios/gestion/neotac)
- Copec Pay es una billetera y tarjeta prepago física (2024) orientada a personas. No se encontró una versión para flotas con controles. — [DF](https://www.df.cl/mercados/banca-fintech/copec-lanza-tarjeta-de-prepago-fisica-y-amplia-su-ecosistema-financiero); [The Clinic](https://www.theclinic.cl/2024/05/08/copec-pay-tarjeta-prepagp-fisica-nominacion-ni-banda-magnetica/amp/)

**Esmax / Aramco Fleet (ex Petrobras Flota), la tarjeta que usa SICOM**
- Restricciones del folleto Petrobras Flota 2023: "Límite de Carga", "Cantidad de cargas diarias", "Kilómetros recorridos" y "Restricción de estaciones de servicio" (resumen del buscador; la URL no resolvió al intentar abrirla). — [Tarjetas Petrobras Flota 2023](https://tarjetaflota.petrobras.cl/public/TARJETA%20PETROBRAS%20FLOTA%202023.pdf)
- Administración: se entra a portaltarjetas.cl con el RUT del contratante y una clave enviada por correo; se busca el vehículo o la tarjeta y se ven sus restricciones. Hay app móvil "Tarjeta Flota" (com.esmax.tarjetaflota) para transacciones y restricciones (resumen del buscador; la página dio 404 al abrirla). — [Esmax Aramco Fleet](https://www.esmax.cl/soluciones/aramco-fleet/); [Google Play](https://play.google.com/store/apps/details?id=com.esmax.tarjetaflota&hl=en_NZ); [App Store](https://apps.apple.com/mt/app/tarjeta-flota/id1370928618)
- Prensa describe Aramco Fleet como una plataforma digital para empresas de transporte que controla el consumo en tiempo real. — [Ex-Ante](https://www.ex-ante.cl/?p=293320)
- Riesgo operativo: en reclamos de 2026 hay estaciones que no aceptan Aramco Fleet (San Felipe, feb-2026). — [Reclamos.cl](https://www.reclamos.cl/aramco/reclamo/2026/feb/aramco-bomba-de-san-felipe-no-acepta-aramco-fleet)
- Hay un listado de estaciones que aceptan la tarjeta y de las que tienen tótem de pago. — [Esmax EDS Petrobras Flota](https://www.esmax.cl/wp-content/uploads/EDS_Petrobras_Flota_01_24.pdf)

**Enex / Shell Card (Empresa, Transporte, Institucional, Prepago)**
- Según el manual de Enex: tarjeta asignada a un vehículo y a un tipo de combustible, departamentos o centros de costo, restricciones diarias, semanales y mensuales, y administración en tarjeta-empresa.cl. Shell Card Transporte suma límites de litros y de número de cargas por período, restricción de estaciones y PIN de 4 dígitos. Contacto: tarjeta@enex.cl, 800 104 200 (resumen del buscador; el PDF dio 404 al abrirlo). — [Manual SCT Enex](https://enex.cl/wp-content/uploads/2024/08/230227_SCT_Manual-web-Última-Actualización.pdf); [Manual SCE Prepago](https://enex.cl/wp-content/uploads/2024/08/230227_SCE_Manual-web-Prepago-Última-Actualización.pdf)
- Las alertas pueden ser a nivel de cuenta, vehículo o departamento, de stock mínimo (prepago) y de estado de cuenta (resumen del buscador sobre el manual Shell Card). — [Manual SCI Enex](https://enex.cl/wp-content/uploads/2024/08/230207_SCI_Manual-web-Último-Actualizado.pdf)
- Shell Card Institucional permite restricciones por estación, monto o día, y bloquear tarjetas (tarjeta-institucional.cl, resumen del buscador). Un comparador dice que se puede bloquear el uso fuera de horario y estima la mantención en unas 0,1 UF al mes (dato no verificado). — [tasas.cl](https://tasas.cl/shell-card-empresa)

**LatAm (referencia)**
- Edenred Ticket Car+ (México) certifica cargas con integración GPS y valida el odómetro de forma automática. Ticket Car 3.0 bloquea transacciones que superan la capacidad del estanque. Hay restricciones por día, hora, combustible y estación. — [CarNews MX](https://www.carnews.com.mx/?p=100940); [The Logistics World](https://thelogisticsworld.com/historico/genera-control-de-combustible-ahorros-de-hasta-30/)
- Edenred dice tener más de 12.000 clientes en México; Ticket Car aporta cerca del 90% de sus ingresos allí. Prepara "Edenred One Mobility", que integra combustible, mantención y telemetría. — [DPL News](https://dplnews.com/?p=320690); [Mexico Industry](https://mexicoindustry.com/noticia/edenred-lanza-en-mexico-plataforma-que-integra-combustible-telemetria-y-flotas-electricas)

### Inferences
- Esto se puede reproducir en SICOM: límites, estaciones, número de cargas y PIN ya los da Aramco Fleet. Lo que la tarjeta chilena no hace (salvo TCT Premium con hardware) es probar que el vehículo estaba en la estación. Cruzar cada transacción con la posición Navixy a la hora de la carga es justo el control que Ticket Car+ vende como diferencial en México.
- Las alertas de TCT son un buen punto de partida para las reglas de SICOM: 2 o más cargas en 1 hora, fuera de horario y sobre el límite. A eso se puede sumar la regla de Ticket Car: litros mayores que la capacidad del estanque.
- El campo "Kilómetros recorridos" de Petrobras Flota sugiere que el odómetro se ingresa en la carga, pero no se confirmó.

### Gaps
- No se pudo leer la ficha vigente de Aramco Fleet (404). No se confirmó si tiene API o web service, alertas SMS/correo en tiempo real, restricción horaria ni RUT del conductor.
- No se halló documentación de "Copec Flota" ni de "Copec Pay empresas" como producto con controles distintos de TCT. Copec Mobility/Voy no se investigó por falta de llamadas.
- No hay precios ni comisiones oficiales de ninguna tarjeta chilena. Pluxee: sin resultados en el contexto de flotas en Chile.

## 2. Qué módulos de combustible ofrecen Wialon, Navixy y los proveedores GPS locales, y a qué precio en Chile

### Takeaway
Wialon y Navixy detectan cargas y drenajes con sensor de nivel (FLS) o con datos del CAN bus, y entregan reportes y alertas. Ninguno tiene un importador nativo de tarjetas documentado de forma clara. Wialon lo resuelve vía API o terceros; Navixy tiene un reporte "Fuel Volume NEW" con una tabla de cargas pensada para compararla con el ERP o CRM. En Chile los proveedores locales (Sitrack, DControl, Vikar, GPS Control, Rastreosat) venden sensores de varilla o lectura CAN. No se encontraron precios públicos.

### Cited Findings
- Wialon calcula el consumo de cinco formas: por FLS (nivel del estanque), por sensores de flujo AbsFCS/InsFCS, por cálculo matemático (motor y eficiencia), por tasa (km × l/100 km) y por CAN bus. Integra más de 4.100 modelos de trackers. Reporta fecha, hora, lugar, nivel inicial y final y volumen de cada carga o drenaje. Alerta por email, SMS, push o tablero. En combustible, la API se ofrece para conectar "fuel card solutions" de terceros. No publica precios. — [Wialon fuel management](https://wialon.com/en/fuel-management-system)
- Wialon detecta drenajes con un volumen mínimo configurable, en movimiento o en ralentí. El volumen es Vfinal − Vinit. Los saltos del sensor al partir o detenerse pueden generar drenajes falsos. — [Wialon: Detecting Fuel Drains](https://help.wialon.com/en/wialon-hosting/user-guide/monitoring-system/reports/data-in-reports/fuel/detecting-fuel-drains); [Wialon: false drains](https://help.wialon.com/help/wialon-hosting/en/expert-articles/fuel/how-to-get-rid-of-false-fuel-drains)
- Desde 2014 se pide en el foro de Wialon importar cargas desde XML de proveedores. Se mencionó un "Wialon OIL Service" para integrar tarjetas, sin confirmar que siga vigente. — [Wialon forum](https://forum.wialon.com/viewtopic.php?pid=63859)
- Navixy "Fuel Volume NEW" solo necesita la tabla de calibración y el volumen máximo del estanque. Entrega un gráfico depurado del nivel más una tabla de cargas por estación para "comparar con datos de CRM/ERP". Detecta la hora de carga en minutos, con una desviación de volumen de "unos pocos por ciento" con sensores modernos. Anuncia detección de anomalías con ML (planificada). No describe formato de importación ni lógica de cruce. — [Navixy blog](https://navixy.com/blog/new-report-for-comparing-refueling-data-from-fuel-cards/)
- Navixy usa un índice de calidad del sensor (FSQI) para los drenajes. Advierte que con tarjetas corporativas se drena combustible a bidones propios. La mayoría de los equipos Teltonika reportan nivel y consumo por CAN/OBDII. Hay una extensión "Fuel monitoring" en su marketplace. — [Navixy Fuel Monitoring](https://www.navixy.com/features/fuel-monitoring); [Navixy marketplace](https://marketplace.navixy.com/shop/fuel-monitoring); [Navixy blog sensores](https://navixy.com/blog/remote-fuel-level-monitoring/)
- Precio de Navixy: G2 dice "contactar ventas". SelectHub cita desde USD 250 al mes, sin detalle de qué incluye. — [G2](https://www.g2.com/products/navixy-gps-tracking-platform/pricing); [SelectHub](https://www.selecthub.com/fleet-management-software/navixy/)
- Proveedores locales en Chile:
  - Sitrack (ICAN/VMD) transmite el nivel del estanque y detecta cargas y descargas. — [Sitrack](https://www.sitrack.cl/portal/soluciones/)
  - DControl usa un sensor europeo que registra los litros de cada carga y los drenados. — [DControl](http://www.d-control.cl/)
  - Vikar instala varillas en el estanque. — [Vikar GPS](https://vikargps.cl/)
  - GPS Control y FlotasGPS leen el CAN bus. — [GPS Control](https://www.gpscontrol.cl/); [FlotasGPS](https://flotasgps.cl/)
  - Smartreport ofrece tres vías: sensor, CAN o estimación sin hardware. — [Smartreport](https://www.smartreport.cl/control-gps-para-camiones)
  - Rastreosat (by Redd) combina GPS, periféricos y cámaras con IA para detectar robo y fugas. — [Gpsvision](https://gpsvision.cl/control-de-combustible-en-flotas-con-gps/)
- Geotab (LatAm) promueve integrar tarjeta y telemática para validar cargas. — [Geotab LatAm](https://www.geotab.com/es-latam/blog/integracion-tarjetas-de-combustible-control-flota/)

### Inferences
- Para camionetas (no camiones) el sensor de varilla rara vez se justifica. El CAN/OBD del Teltonika más la posición GPS a la hora de la transacción es el cruce que mejor resulta en relación con su costo. El reporte de Navixy pide sensor de nivel, así que sin FLS su valor para SICOM es limitado.
- Ni Wialon ni Navixy resuelven de fábrica el cruce automático con la tarjeta en Chile. Si SICOM toma las transacciones de Aramco Fleet por API (ya sincroniza cada hora, MIG690) y las cruza con Navixy, eso lo diferencia de lo que ofrece el mercado local.

### Gaps
- Gauss Control, Kauel y Tracklink no aparecieron en los resultados. Tecnotrack, MiX Telematics, Webfleet, Samsara (México/Chile) y Copec Voy no se investigaron por el límite de llamadas.
- No hay precios en CLP del módulo de combustible de ningún proveedor GPS chileno.

## 3. Esquemas típicos de fraude con combustible y estadísticas en Chile/LatAm

### Takeaway
Los casos chilenos documentados son de colusión entre conductor y bombero: facturar más litros que los cargados o vender a terceros. Ocurren sobre todo en el sector público, con montos del orden de $20 millones. Los métodos que más se repiten son cargar a terceros, llenar bidones, inflar litros con el bombero y adulterar el odómetro. La estadística regional que circula (3% a 20% de pérdida) viene de proveedores y no es independiente.

### Cited Findings
- Municipalidad de San Pedro (2023): el CDE se querelló por fraude al fisco por cargas irregulares con tarjetas de vehículos municipales. Participaron un conductor municipal y un bombero de una estación Petrobras, por unos $20 millones. — [Fast Check (dic-2025)](https://www.fastcheck.cl/2025/12/13/uso-irregular-de-tarjetas-de-combustible-habria-permitido-fraude-por-20-millones-en-municipalidad-de-san-pedro/)
- Talcahuano, 2021: se investigó a tres marinos y dos trabajadores de una estación Copec por facturas falsas de combustible que se vendía a terceros. — [BioBioChile](https://www.biobiochile.cl/noticias/nacional/region-del-bio-bio/2021/12/02/lo-vendian-a-terceros-indagan-a-miembros-de-la-armada-y-copec-por-fraude-en-compra-de-combustible.shtml)
- Métodos descritos en guías del sector:
  - facturar más litros que los cargados y repartirse la diferencia con el bombero;
  - cargar con la tarjeta vehículos propios o de terceros;
  - llenar bidones después de la carga legítima o sifonear;
  - alterar el odómetro;
  - cargar muchas veces o con patentes que no calzan.
  — [Vecfleet](https://vecfleet.io/blog/fraude-combustible-flota-senales/); [GTrack](https://gtrack.io/blog/detectar-robo-combustible); [Edenred MX](https://www.edenred.mx/blog/como-prevenir-fraudes-en-el-control-de-gasolina)
- Una estimación logística LatAm dice que entre el 3% y el 20% del combustible comprado por flotas no se convierte en km recorridos (fuente de proveedor, sin metodología). — [GTrack](https://gtrack.io/blog/detectar-robo-combustible)
- Bolivia denunció en marzo de 2026 una red de robo y sabotaje de combustible que operaría en Chile y Bolivia. Es una acusación no verificada y sin detenidos. — [Correo del Sur](https://correodelsur.com/economia/20260331/gobierno-denuncia-red-de-robo-y-sabotaje-de-combustible-que-opera-en-chile-y-bolivia.html)

### Inferences
- Para una flota de camionetas, las señales más útiles son estas:
  - litros por carga mayores que la capacidad del estanque;
  - rendimiento km/l fuera de rango (odómetro GPS contra litros);
  - carga sin el vehículo en la estación según el GPS (carga a terceros);
  - carga en días o horas sin jornada;
  - dos cargas seguidas en poco tiempo.
- La colusión con el bombero (litros inflados) solo la detecta un sensor de nivel o el rendimiento sostenido. La tarjeta por sí sola no la ve.

### Gaps
- No hay estadísticas chilenas independientes (Fiscalía, CChC, gremios de transporte o estudios académicos) sobre pérdidas por fraude de combustible en flotas privadas.

## 4. Normativa y aspectos tributarios relevantes en Chile (impuesto específico al diésel, factura y guía, SII)

### Takeaway
Los contribuyentes de IVA pueden recuperar el impuesto específico al diésel (Ley 18.502 art. 7 y DS 311), salvo el diésel usado en vehículos que transitan por carretera. La minería en faena recuperaba el 100%. El transporte de carga tiene un régimen parcial (Ley 19.764). La Ley 21.811 (DO 26-03-2026) topó la recuperación al 31% entre el 26-03-2026 y el 30-09-2026, con excepción de los transportistas. Para camionetas que circulan por caminos públicos, en general no se recupera. Por eso importa separar en el registro los litros de faena de los litros de carretera.

### Cited Findings
- DS 311: los contribuyentes de IVA recuperan una suma equivalente al impuesto específico soportado, imputándola al débito de IVA o pidiendo la devolución, en la medida que el diésel no se use en vehículos que transitan por carretera. — [SII FAQ](https://www.sii.cl/preguntas_frecuentes/impuestos_mensuales/001_130_6091.htm); [SII FAQ hormigoneros](https://www.sii.cl/preguntas_frecuentes/impuestos_mensuales/001_130_5629.htm)
- Transporte de carga: según el SII no procede la recuperación por la Ley 18.502. Solo procede la recuperación parcial de la Ley 19.764. — [SII jurisprudencia 2015](https://www.sii.cl/pagina/jurisprudencia/adminis/2015/ventas/ja608.htm); [Nubox](https://blog.nubox.com/contadores/recuperacion-impuesto-al-diesel)
- Ley 21.811 art. 4: tope del 31% del impuesto soportado, entre el 26-03-2026 y el 30-09-2026, para facturas emitidas desde la publicación. Los transportistas del art. 14 D) N° 3 y 8 de la LIR quedan exentos del tope. La Circular SII N° 22 del 05-06-2026 instruye su aplicación. — [Circular SII 22/2026](https://www.sii.cl/normativa_legislacion/circulares/2026/circu22.pdf); [CNC](https://cnc.cl/wp-content/uploads/2026/04/1-SII-en-consulta.pdf); [Diario Oficial extracto](https://www.diariooficial.interior.gob.cl/publicaciones/2026/06/13/44474/01/2823461.pdf)
- Las mineras reclamaron que pasaban del 100% al 31% y que asumirían el 74% del costo de la medida. — [DF](https://www.df.cl/empresas/mineria/grandes-mineras-golpean-la-mesa-por-cambio-al-impuesto-al-diesel-y-critican); [Emol](https://www.emol.com/noticias/Economia/2026/03/25/1195301/gremio-minero-impuesto-al-diesel.html)
- El SII tiene una resolución sobre el sistema "Tarjeta Copec Transporte" para emitir documentos tributarios. — [SII Res. 51/2003](https://www.sii.cl/documentos/resoluciones/2003/reso51.doc)

### Inferences
- Para el arriendo de equipos industriales que operan dentro de faena, el diésel consumido fuera de carretera podría ser recuperable. Eso exige un registro trazable por equipo y por uso (faena o carretera), que SICOM ya captura en parte. Debe validarlo un contador.
- El tope transitorio vencía el 30-09-2026. Hay que verificar si se prorrogó.

### Gaps
- No se confirmó si la Ley 21.811 se prorrogó después del 30-09-2026, ni su texto íntegro.
- No se investigó el detalle del formato de factura electrónica o guía de despacho que emiten las tarjetas de flota (factura mensual consolidada o por transacción).
