# Control de combustible: metodología de detección y presentación al directorio como control interno

Alcance: flota industrial chica en Chile (~13 livianos con tarjeta de combustible + camiones pesados que cargan en faenas mineras). Fuentes 2020-2026 donde fue posible. Aviso general: casi todo el material sobre "fuel fraud" en la web es de proveedores (WEX, Shell, Motive, Geotab, Oxmaint, FleetRabbit, HVI). Lo trato como marketing. Las fuentes más sólidas que encontré son las auditorías internas de gobiernos (Fort Worth, Orange County, Houston, San Diego, TIGTA), el NIST Engineering Statistics Handbook y el resumen secundario del ACFE 2024. No encontré ningún paper académico revisado por pares sobre detección de fraude con tarjeta de combustible + GPS.

## P1. Metodología: rendimiento lleno a lleno, conciliación por ventana, detección estadística, cargas parciales, ruido del odómetro, falsos positivos, tolerancias

### Conclusión
El estándar práctico tiene dos capas. (1) Reglas deterministas por transacción: litros sobre la capacidad del estanque, ubicación de la tarjeta distinta de la posición GPS, cargas fuera de horario o en fin de semana, varias cargas en poco tiempo, vehículo inactivo o dado de baja, producto equivocado. (2) Conciliación por vehículo sobre una ventana móvil: litros contra km GPS, comparados con la línea base propia del vehículo y marcados con estadística robusta (z modificado con mediana/MAD, |M| > 3,5). Las tolerancias publicadas son reglas de la industria, no estándares. Hay que calibrarlas con los datos propios.

### Hallazgos citados
**Reglas por transacción (la base que usan los auditores)**
- La auditoría interna de Fort Worth (informe 2025.003.2, datos FY2024) probó las transacciones de combustible con cuatro análisis: cargas entre 22:00 y 06:00, en fin de semana y en feriados; galones cargados contra capacidad del estanque (en toda la población de vehículos); y uso de la tarjeta contra el estado activo o rematado del vehículo — [Fort Worth Internal Audit FY2025 Q2 Data Analysis](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- En el mismo informe, las capacidades de estanque guardadas en el sistema de flota superaban las del fabricante en 1,5 a 22 galones. Flota las había inflado "hasta 5 galones" para que se pudieran contabilizar las cargas en que el operador sigue cargando después del corte automático de la pistola. En una muestra de 15 tipos de vehículo (861 vehículos) hubo 69 cargas que superaban la capacidad del fabricante. Un caso tenía 12,7 galones de exceso sobre el fabricante y solo 0,3 galones sobre la capacidad del sistema, así que el reporte de excepciones no lo habría marcado. La auditoría concluyó que inflar la capacidad "anula los controles" contra fraude, despilfarro y abuso — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- **Tolerancia sobre la capacidad del estanque:** después de la auditoría, Flota de Fort Worth bajó su margen a 3 galones (≈11 L) sobre la capacidad del fabricante. Citó un estándar de la industria según el cual un vehículo admite 0,5 a 3 galones después del corte automático, según tamaño y diseño del estanque y la dilatación térmica. Los auditores concluyeron que, sin retrofit, es improbable que un vehículo admita 5 galones sobre lo especificado — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- Un proveedor sugiere un tope de capacidad del estanque + 5%. Una plantilla de conciliación para petroleras deja un margen pequeño por la variación del corte de la pistola — vía [Oxmaint fuel card reconciliation checklist](https://oxmaint.com/industries/fleet-management/fleet-fuel-card-reconciliation-management-checklist); [FleetRabbit oilfield reconciliation template](https://fleetrabbit.com/industry/oil-and-gas/oilfield-fleet-fuel-reconciliation-template) (proveedores)
- La política de Minnesota DOT lista las compras sobre la capacidad del estanque entre las excepciones típicas de tarjeta de combustible — [MnDOT policy FM021](https://www.dot.state.mn.us/policy/financial/fm021.html)
- Cada transacción debe cruzarse con un vehículo, una fecha, una lectura de kilometraje y un volumen plausible para el estanque y el consumo. Una diferencia persistente de más de 2% entre el odómetro digitado por el conductor y el odómetro GPS se marca como posible manipulación — [Oxmaint checklist](https://oxmaint.com/industries/fleet-management/fleet-fuel-card-reconciliation-management-checklist) (proveedor)
- Una ubicación distinta entre la estación de la transacción y la posición GPS del vehículo se describe como el indicador de fraude más fuerte — [FleetRabbit trucking reconciliation](https://fleetrabbit.com/industry/transportation-and-logistics/trucking-fleet-fuel-reconciliation-across-cards-bulk-and-trucks-2026) (proveedor)
- Señales de alerta según Shell Fleet Solutions: una tarjeta cargando varios vehículos, tarjeta equivocada para el vehículo, volumen sobre la capacidad del estanque, transacciones lejos del área de operación, producto equivocado o premium frecuente, varias transacciones en poco tiempo. Controles digitales: restringir por producto, lugar y horario, monitoreo en tiempo real, bloqueo inmediato, analítica para atípicos y cargas fuera de horario — [MWS Magazine sobre el whitepaper 2025 de Shell](https://www.mwsmag.com/shells-2025-fraud-and-misuse-whitepaper/)
- No hay umbrales universales. Cada flota define sus reglas de horario, lugar, volumen, producto y frecuencia — [AUTOSIST, What fuel card exceptions reveal](https://autosist.com/blog/what-fuel-card-exceptions-reveal-about-your-fleet/) (proveedor)

**Conciliación por ventana y línea base**
- La detección de anomalías se describe como comparar las transacciones, la telemetría GPS y los datos de motor contra la línea base histórica de cada vehículo. El robo pequeño por carga (ej. 20 galones por parada) no gatilla alertas por transacción, pero aparece como patrón en varias transacciones. Eso justifica la ventana móvil — [Oxmaint anomaly patterns](https://oxmaint.com/industries/fleet-management/how-to-detect-fleet-fuel-theft-anomaly-patterns) (proveedor)
- Umbral de alerta propuesto: desviación de 15% o más sobre la línea base del vehículo (mantención o robo). HVI también usa un alza de 15% sin explicación como señal — [búsqueda: guías de dashboard / HVI](https://heavyvehicleinspection.com/blog/post/fleet-fuel-theft-detection) (proveedor)
- Una patente describe comparar la carga actual (volumen, duración, caudal en el tiempo) con cargas históricas de vehículos comparables y advertir fraude si no calzan — [patente "Monitoring refueling operations"](https://ipiq.io/patents/6084428)

**Estadística robusta**
- NIST: z modificado de Iglewicz y Hoaglin, M_i = 0,6745·(x_i − mediana)/MAD. Los valores con |M_i| > 3,5 se etiquetan como atípicos potenciales — [NIST/SEMATECH e-Handbook, Detection of Outliers](https://itl.nist.gov/div898/handbook/eda/section3/eda35h.htm)
- El z modificado no se ve arrastrado hacia cero por los mismos atípicos (evita el enmascaramiento), a diferencia del z clásico — [MetricGate, Z vs modified Z](https://metricgate.com/blogs/zscore-vs-modified-zscore/) (secundaria, coincide con NIST)

**Cargas parciales en el cálculo lleno a lleno**
- Las cargas parciales rompen el cálculo lleno a lleno si no se tratan. La solución práctica es acumular km y litros hasta la siguiente carga a estanque lleno — [Fuelly forums](https://fuelly.com/forums/f8/inaccurate-mpg-427.html)
- El punto de corte de la pistola varía entre estaciones. Temperatura y pendiente cambian el nivel. Se recomienda llenar a un nivel conocido y sumar el volumen de las parciales — [Fuelly, filling from halfway](https://fuelly.com/forums/f8/filling-from-halfway-459.html); [EcoModder](https://ecomodder.com/forum/showthread.php/how-many-gallon-fillup-accurate-mpg-readings-13794-2.html)
- El manual Ford F-150 recomienda llenar completo al inicio, registrar cada carga, calcular después de varias cargas, mantener el mismo método de llenado e ignorar los primeros ~1.600 km (rodaje) — [manual Ford F-150 vía ManualsLib](https://www.manualslib.com/manual/573212/Ford-F-150.html?page=199)
- No encontré ningún estudio riguroso que cuantifique el error de las cargas parciales. La cifra de "1-2% en ciclos largos" viene de un sitio de baja calidad — ver Vacíos.

**Ruido del odómetro y del GPS**
- El odómetro calcula por rotación de rueda. Un cambio de 5 mm en el radio de la rueda mueve la lectura ~2%. El error típico de un odómetro mecánico es hasta 5% y puede llegar a 12-15% con desgaste o repuestos no originales — [Mapon, odometer vs GPS](https://www.mapon.com/en/blog/difference-in-odometer-and-gps-data) (proveedor)
- Navixy (la plataforma GPS que usa Radicom): los fabricantes admiten hasta 10% de error de odómetro, normalmente cerca de 5% y hacia arriba. Si el equipo transmite con poca frecuencia, el GPS "corta las curvas" y pierde distancia. Túneles y subterráneos cortan la señal — [Navixy docs, mileage and odometer](https://www.navixy.com/docs/expert-center/faq-and-troubleshooting/sensors/mileage-and-odometer)
- Motus: la guía SAE admite un error de odómetro de ±4% — [Motus blog](https://www.motus.com/blog/variations-in-odometer-readings/)
- Los proveedores reportan diferencias típicas odómetro/GPS de 3-7%, con el odómetro por encima del GPS — [Ikonn](https://www.ikonn.com.br/en/support/odometer-errors-gps-vs-dashboard-discrepancy) (proveedor)

**Fuentes conocidas de falsos positivos (documentadas)**
- Operación legítima 24/7: en Fort Worth, las cargas nocturnas, de fin de semana y de feriado eran casi todas de departamentos con turnos 24/7. Resultado: "sin excepción" — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- Datos maestros malos: capacidades de estanque erradas en el sistema (falsos negativos) y operadores que digitan el número de una unidad antigua o rematada en la pistola (falsos positivos) — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- Un KPI puede verse perfecto y estar equivocado por un ping duplicado o un ID de vehículo cruzado. Se recomienda publicar indicadores de calidad de datos (% de lecturas marcadas como atípicas) junto con los KPI — [Oxmaint telematics data cleanup](https://oxmaint.com/industries/fleet-management/what-fleet-managers-should-track-in-a-telematics-data-cleanup-dashboard-comparison-guide) (proveedor)
- Los sensores de nivel se pueden burlar (bolsas de aire en el estanque, alcohol mezclado con el combustible) — [Mapon, preventing fuel theft](https://www.mapon.com/en/blog/preventing-fuel-theft-fleet) (proveedor)

### Inferencias
- Diseño recomendado para esta flota (síntesis propia):
  - (a) Reglas duras por transacción: litros > capacidad del fabricante + ~10 L (equivale a los 3 gal de Fort Worth; usar la capacidad de la ficha técnica, nunca un valor inflado); distancia estación-GPS > X km a la hora de la carga; varias cargas en < N horas; carga con vehículo en taller, inactivo o vendido; producto distinto del diésel.
  - (b) Conciliación por ventana móvil (ej. 30 días o las últimas 3-5 cargas a estanque lleno) de L/100 km GPS contra la mediana propia del vehículo, marcando |z modificado| > 3,5, o una banda de ±15% como regla de negocio más simple.
  - (c) Ignorar la ventana cuando la cobertura GPS del período sea mala (huecos de telemetría).
- Con ~13 livianos, la mediana/MAD por vehículo necesita historia (≥ 8-10 cargas) para ser estable. Con poca historia conviene usar la mediana del grupo de modelos iguales y no la del vehículo solo.
- Como el GPS suele subestimar distancia y el odómetro sobrestimarla, conviene fijar una sola fuente de distancia (GPS) para el KPI y usar la diferencia odómetro/GPS solo como control de calidad del dato.
- Camiones pesados en faena minera: buena parte del consumo es en ralentí o con PTO, sin km. Ahí el km/L engaña. Lo correcto es L/hora de motor (horómetro o rFMS/CAN) y conciliar contra el despacho del surtidor de faena, no contra la tarjeta. Es una inferencia: no encontré una fuente específica de minería.

### Vacíos
- No encontré ningún paper académico revisado por pares (2020-2026) que valide umbrales para detectar fraude con tarjeta + GPS. Todo el material metodológico es de proveedores, auditorías o NIST (genérico).
- No hay estándar (ISO, SAE ni asociación de flotas) para las tolerancias. Los valores de 2% (odómetro), 5% o 3 gal (estanque) y 15% (línea base) son práctica de la industria.
- No encontré fuentes de NAFA, AFLA o ICFM de acceso público con tolerancias específicas.
- No encontré cifras de cartas de control (Shewhart/EWMA/CUSUM) aplicadas a combustible. El z modificado sí tiene respaldo de NIST.

## P2. Benchmarks: peso del combustible en el costo operativo, pérdida por fraude o mal uso, ahorros realistas

### Conclusión
En camiones (EE.UU., ATRI) el combustible es ~21% del costo operativo por milla. Las estimaciones de pérdida por mal uso o fraude van de 1% a 19% del gasto en combustible según el proveedor, sin metodología publicada. La cifra más citable es la de Shell: 2-5% del gasto anual, con el mal uso como ~80% de los incidentes. Los ahorros de 8-20% después de integrar tarjeta y telemetría son afirmaciones de proveedores sin caso auditado.

### Hallazgos citados
- ATRI (Operational Costs of Trucking, edición 2026 con datos de 2025): costo total US$2,336/milla, récord. Combustible US$0,482/milla. Fuera de combustible, US$1,854/milla. Combustible ≈ 21% del total (cálculo derivado, no cifra publicada por ATRI). Fuentes: [Truckers News](https://www.truckersnews.com/news/article/15830055/truckings-operational-costs-reached-new-high-of-2336-per-mile-in-2025); [TT News](https://www.ttnews.com/articles/atri-truck-costs-2025); [FleetOwner](https://www.fleetowner.com/operations/article/55392569/atri-report-breaks-down-class-8-truck-operating-costs-by-region-and-expense-category). Ojo: un artículo de FleetMaintenance habla de un alza fuerte del precio del combustible en 2025, contradiciendo al resto. Lo trato con cautela.
- Shell Fleet Solutions (whitepaper 2025): las flotas pierden 2-5% del gasto anual en combustible por mal uso. El mal uso explica ~80% de los incidentes relacionados con combustible. Un incidente de fraude puede costar US$60.000-80.000. No publica muestra ni método — [MWS Magazine](https://www.mwsmag.com/shells-2025-fraud-and-misuse-whitepaper/)
- Otras estimaciones de proveedores, muy dispersas: 5-15% del presupuesto de combustible (19% en flotas grandes, 16% en chicas); 3-5%; 1-3%; 6-10% del combustible que pasa por un sitio (ejecutivo citado en Fleet Maintenance) — [búsqueda agregada: HVI](https://heavyvehicleinspection.com/blog/post/fleet-fuel-card-fraud-detection-guide-2026); [FleetRabbit](https://fleetrabbit.com/industry/transportation-and-logistics/reducing-trucking-fuel-theft-and-card-fraud-across-the-fleet-2026); [Fleet Maintenance, How to prevent fuel fraud](https://www.fleetmaintenance.com/equipment/emissions-and-efficiency/article/55134795/how-to-prevent-fuel-fraud)
- ACFE 2024 Report to the Nations (vía resumen secundario): pérdida mediana por fraude ocupacional US$145.000. El fraude afecta ~5% de los ingresos — [WEX, citando ACFE 2024](https://www.wexinc.com/resource/fuel-card-fraud-is-on-the-rise-how-two-factor-authentication-and-telematics-help-protect-your-trucking-fleet)
- ACFE 2024 (vía Wipfli): con monitoreo proactivo de datos, la duración mediana del fraude baja 58% (24 a 10 meses) y la pérdida mediana 52% (US$200.000 a US$96.000). Según ASCPA, los controles en general se asocian a 23-63% menos pérdida y 14-50% menos duración. Según Forvis Mazars, solo 53% de las organizaciones con más de 100 empleados tiene analítica proactiva — [Wipfli](https://www.wipfli.com/insights/articles/ra-identifying-the-risks-of-occupational-fraud); [ASCPA](https://www.ascpa.com/fraudprevention); [Forvis Mazars](https://forvismazars.us/forsights/2024/08/be-proactive-limit-asset-misappropriation-schemes). Sin verificar contra el PDF original de la ACFE.
- Ahorros declarados después de controles: 8-15% (tarjeta + telemetría, que incluye ralentí y mecánica, no solo fraude); 10-20% (Transpoco); 6% por hábitos de conducción (Geotab). Ninguno trazable a un caso auditado — [Transpoco](https://www.transpoco.com/blog/fuel-card-management-system-maximize-your-fleet-roi); [Geotab](https://www.geotab.com/blog/fleet-fuel-telematics/); [Oxmaint public fleets](https://oxmaint.com/industries/government/fleet-fuel-management-public-sector-cost-control) (todos proveedores)

### Inferencias
- Para el directorio, lo honesto es presentar un rango de exposición (ej. 2-5% del gasto en combustible de la flota con tarjeta, según Shell) como hipótesis, y reemplazarlo lo antes posible por la tasa medida propia: litros en excepciones confirmadas / litros totales.
- Separar "ahorro por control de fraude" de "ahorro por eficiencia" (ralentí, conducción, mantención). Las cifras de 8-20% las mezclan.
- El hallazgo de la ACFE sobre monitoreo proactivo (−52% de pérdida mediana) es el argumento de control interno más citable para justificar el control ante el directorio, aunque es de fraude ocupacional en general y no específico de combustible.

### Vacíos
- No hay benchmark chileno ni latinoamericano del peso del combustible en costos de flota industrial o minera. Tampoco del % de pérdida por mal uso.
- No encontré un informe de la ACFE con una cifra específica de fraude con tarjeta de combustible.
- No encontré ningún caso independiente (auditado) de ahorro antes/después.

## P3. Reportabilidad al directorio: KPI, formato de una página, tendencias, mapa de calor

### Conclusión
Las fuentes coinciden en que el directorio quiere tendencias y la jefatura quiere excepciones. El costo por km es el KPI ancla y el combustible por km la capa de diagnóstico. Hay que publicar indicadores de calidad de datos junto a los KPI. No encontré una fuente de autoridad (IIA o asociación de flotas) con un formato específico de "control de combustible para el directorio". El formato recomendado abajo es síntesis propia.

### Hallazgos citados
- El costo por milla o km es el KPI más importante en reportes de flota. El costo de combustible por milla es el diagnóstico debajo de ese KPI — [Simply Fleet, fleet reporting metrics](https://www.simplyfleet.app/blog/fleet-reporting-metrics) (proveedor)
- Los reportes se adaptan por rol: un ejecutivo quiere tendencias, un jefe de flota necesita excepciones. Para el directorio el tablero debe "partir desde la sala del directorio y no desde el despacho", con medidas como costo de transporte sobre ingresos — [FleetRabbit, trucking KPI dashboard 2026](https://fleetrabbit.com/industry/transportation-and-logistics/trucking-fleet-kpi-dashboard-every-operations-director-should-track-2026); [AUTOSIST, types of fleet reports](https://autosist.com/blog/types-of-fleet-management-reports/) (proveedores)
- Un experto citado en Government Fleet dice que es importante monitorear las excepciones de combustible, porque cargar sobre la capacidad del estanque puede indicar robo — [Government Fleet, top KPIs](https://www.government-fleet.com/articles/top-kpis-to-track-to-improve-fleet-performance)
- Publicar indicadores de calidad de datos (% de lecturas atípicas o marcadas) junto a los KPI operativos — [Oxmaint](https://oxmaint.com/industries/fleet-management/what-fleet-managers-should-track-in-a-telematics-data-cleanup-dashboard-comparison-guide)
- Formato de referencia de un auditor: el informe de Fort Worth presenta cada prueba con "Objetivo / Metodología / Qué encontramos / Alcance (período)", tablas de excepciones por tramo de exceso (1-3, 3,1-5, … >20 galones) y conclusiones del tipo "sin excepción" o "excepción". Es un formato reutilizable para presentar evidencia de un control al directorio — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- Una métrica clave para la empresa es la tasa de transacciones marcadas o confirmadas como fraudulentas sobre el gasto total, revisada mensualmente — [Oxmaint fraud controls guide](https://oxmaint.com/industries/fleet-management/fleet-fuel-card-fraud-and-misuse-controls-guide) (proveedor)

### Inferencias (formato propuesto, síntesis propia)
- **Una página, cuatro bloques:**
  1. **Resultado económico:** gasto en combustible real vs presupuesto (mes y acumulado del año), $/km y L/100 km (o km/L) vs meta, separando livianos con tarjeta y pesados en faena (L/hora).
  2. **Cobertura del control:** % de vehículos y % del gasto bajo control automático, % de transacciones conciliadas con GPS, y lo que queda fuera con su motivo.
  3. **Excepciones:** abiertas, cerradas y nuevas en el período; antigüedad (0-7, 8-30, >30 días); resultado del cierre (justificada / error de dato / descuento o recupero / sanción); litros y $ recuperados.
  4. **Calidad de datos y limitaciones:** % de transacciones sin odómetro, huecos de GPS, vehículos sin capacidad de estanque cargada.
- **Gráficos:** tendencia de 12 meses de L/100 km por grupo de vehículos con banda de tolerancia (estilo carta de control), barras de excepciones por mes apiladas por resultado, y una tabla top 5 de vehículos por desviación.
- **Mapa de calor de riesgo:** matriz probabilidad × impacto con 4-6 riesgos (tarjeta usada en otro vehículo, carga a bidón, carga fuera de horario, dato de odómetro falso, robo en faena sin tarjeta, pérdida de señal GPS). Marcar el riesgo residual después del control para mostrar el efecto del control.
- Excluir los KPI de vanidad (n° de alertas generadas) y preferir los de resultado (excepciones confirmadas, $ recuperado, tiempo de cierre).

### Vacíos
- No encontré guía de IIA, NAFA, AFLA ni ICFM con un formato estándar de reporte de combustible para directorio. Tampoco umbrales de antigüedad de excepciones (ej. cerrar en < 30 días). Las propuestas de arriba son síntesis.
- No encontré ejemplos públicos de mapas de calor aplicados a riesgo de combustible.

## P4. Encuadre como control interno: diseño COSO, dueño, frecuencia, evidencia, segregación de funciones, excepciones, pista de auditoría y limitaciones

### Conclusión
Un control bien descrito dice quién lo ejecuta, qué hace, cuándo y con qué frecuencia, cómo (manual o automático, con qué precisión o umbral) y qué evidencia deja. También nombra un responsable único y quién aprueba las excepciones y quién remedia. Las auditorías públicas de programas de tarjetas de combustible se caen siempre en los mismos puntos: monitoreo de tarjetas emitidas, gestión de PIN, verificar que la transacción sea del negocio, política escrita y datos maestros. Las limitaciones (cobertura, calidad de datos) se informan con la conclusión tipo auditor: "sin excepción / excepción / no fue posible concluir".

### Hallazgos citados
- Descripción de un control: quién, qué, cuándo, cómo y con qué evidencia. "El contralor revisa la conciliación mensualmente" es una deficiencia de diseño porque omite la precisión y la evidencia. Para controles de revisión de la gerencia importa la precisión de la revisión (detectar a un nivel de agregación relevante), no la seniority de quien revisa. Una firma por sí sola da poca evidencia — [SmartSuite, risk control matrix](https://www.smartsuite.com/guides/internal-controls-risk-control-matrix-control-testing); [FinRep, MRC documentation under SOX (cita Grant Thornton Snapshot 2025-11)](https://www.finrep.ai/blog/mrc-documentation-under-sox-what-auditors-need) (secundarias; referencias primarias PCAOB AS 2201 y COSO no consultadas)
- La documentación de la prueba registra ID del control, descripción (qué, quién, frecuencia), tipo (manual, automático, manual dependiente de TI) y frecuencia — [SmartSuite](https://www.smartsuite.com/guides/internal-controls-risk-control-matrix-control-testing)
- Responsabilidad: definir quién ejecuta, quién revisa, quién guarda la evidencia, quién aprueba las excepciones y quién remedia, con un responsable único por control — [NHI Mgmt Group, SOX control ownership](https://nhimg.org/faq/why-do-sox-controls-fail-when-ownership-is-unclear/) (secundaria)
- Hallazgos recurrentes en auditorías de tarjetas de combustible:
  - Orange County CA: el monitoreo de las tarjetas emitidas a empleados y vehículos fue calificado como debilidad de control significativa — [OC Auditor, audit 1029](https://ocauditor.gov/wp-content/uploads/2017/08/1029-Internal-Control-Audit-of-OC-Public-Works-Fuel-Card-Administration.pdf) (2017, anterior al rango pedido)
  - Houston (2026): 11 hallazgos que indican "debilidad de control sistémica" en administración, supervisión y cumplimiento de la política — [Houston Controller, audit 2026-03](https://preflight.houstontx.gov/controller/audit/reports/2026-03.pdf)
  - San Antonio Fire Dept.: no había controles adecuados para verificar que solo ocurrieran transacciones del negocio — [Government Fleet](https://www.government-fleet.com/news/audit-scrutinizes-san-antonio-fire-department-fuel-card-management)
  - TIGTA (IRS): el programa de tarjetas de flota carecía de supervisión y controles internos suficientes — [TIGTA](https://www.tigta.gov/articles/press-releases/improved-oversight-irs-fuel-cards-needed-tigta-says)
  - USPS OIG: problemas con las compras de combustible y con la gestión de PIN de las tarjetas Voyager — [USPS OIG](https://www.uspsoig.gov/es/node/2891)
  - San Diego County (FY2025-26): el diseño y la efectividad operativa de los controles de tarjetas y fobs de combustible requieren mejora — [San Diego County Auditor](https://www.sandiegocounty.gov/content/dam/sdc/auditor/audit/fy2526/Fuel_Card_and_Fob_Management_Controls.pdf) (no pude abrir el PDF; timeout)
  - Fort Lauderdale: hallazgos clasificados como deficiencias de control interno y deficiencias significativas, pero no debilidades materiales. Es la escala de severidad que se usa al informar — [Fort Lauderdale audit](https://www.fortlauderdale.gov/home/showpublisheddocument/85425/638659703909270000)
- Ejemplo de limitación declarada con honestidad: Fort Worth escribió que "no pudo concluir" si el exceso de carga correspondía a varios vehículos cargados en una sola transacción o a abuso/fraude. También dijo explícitamente que, con la práctica vigente, los reportes de excepción no detectarían las sobrecargas — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)
- Datos maestros como control: Fort Worth comparó la capacidad de estanque del sistema con la del fabricante y encontró que el cambio manual de capacidades anulaba el control. El script que desactiva los vehículos rematados en el sistema de combustible no funcionaba — [Fort Worth](https://www.fortworthtexas.gov/files/assets/public/v/1/internal-audit/documents/fy2025/fy2025-q2-data-analysis-report.pdf)

### Inferencias (ficha de control propuesta, síntesis propia sobre lo anterior)
- **Objetivo / riesgo:** que el combustible pagado con tarjeta o despachado en faena se consuma en vehículos de la empresa y en actividades del negocio.
- **Tipo:** detectivo, automático (reglas + conciliación diaria) con revisión manual de excepciones (manual dependiente de TI).
- **Frecuencia:** reglas por transacción a diario (o cada hora si la API de la tarjeta lo permite), conciliación por ventana semanal o mensual, reporte mensual a gerencia y trimestral al directorio.
- **Dueño:** jefatura de operaciones o flota. Quien revisa la excepción no debe ser el conductor ni su supervisor directo. El cierre con descuento o recupero lo aprueba otro rol (administración o finanzas).
- **Precisión:** umbrales explícitos (capacidad del fabricante + ~10 L; |z modificado| > 3,5 o ±15% contra la mediana propia; distancia estación-GPS > X km).
- **Evidencia:** registro inmutable de excepción → justificación → aprobación, con fecha, usuario y adjuntos.
- **Segregación de funciones:** quien mantiene los datos maestros (capacidad de estanque, asignación tarjeta-vehículo) no cierra excepciones. Los cambios de datos maestros quedan en bitácora. Esta es la lección central de Fort Worth.
- **Limitaciones a declarar:** cobertura (camiones que cargan en faena sin tarjeta y fuera del control de transacciones); huecos de GPS; dependencia del odómetro digitado; la tarjeta prueba compra, no consumo (no detecta trasvasije después de cargar si no hay sensor de nivel); período de calibración con falsos positivos.
- **Conclusión del período** en la escala del auditor: "sin excepción / excepciones explicadas / excepciones confirmadas (n, L, $) / no fue posible concluir (n, motivo)".
- **Mapeo COSO (inferencia; no verifiqué el texto de COSO 2013):** control environment (política de tarjetas, firma del conductor); risk assessment (mapa de calor); control activities (bloqueos y reglas en la tarjeta, conciliación); information & communication (tablero, calidad de datos); monitoring activities (revisión trimestral del directorio, prueba independiente anual).

### Vacíos
- No consulté directamente COSO 2013 (componentes y principios), IIA IPPF/GIAS 2024 ni PCAOB AS 2201. Las citas de diseño de controles son secundarias (proveedores o consultoras).
- No encontré una auditoría de tarjetas de combustible que mapee explícitamente sus hallazgos a componentes COSO.
- No hay guía chilena específica (CMF, Contraloría) para control de combustible en empresas privadas. No la busqué en profundidad.
