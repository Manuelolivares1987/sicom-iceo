# Preguntas Primer Día — Pillado

> **Cómo usar esta plantilla en Notion:**
> 1. En Notion, crea una página nueva en blanco.
> 2. Copia TODO el contenido de abajo (desde el título hasta el final).
> 3. Pégalo en Notion con Ctrl+V. Los checkboxes `[ ]`, los títulos `##` y las citas `>` se convierten automáticamente.
> 4. Cuando obtengas una respuesta, marca el checkbox `[x]` y escríbela como cita debajo (línea que empieza con `>`).

---

## 1. Negocio y operación

- [ ] ¿Cuáles son los 3 contratos más rentables y cuáles están más complicados?
- [ ] ¿Qué clientes tienen penalizaciones por incumplimiento? ¿De cuánto es cada una?
- [ ] ¿Cuál es el ciclo típico de un arriendo (propuesta → contrato → entrega → facturación)?
- [ ] ¿Qué equipos están próximos a fin de contrato y hay que renegociar?
- [ ] ¿Quién es la contraparte (usuario líder) en cada cliente?
- [ ] ¿Tarifas por día, por mes, por kilómetro? ¿Hay bonus por utilización?
- [ ] ¿Qué equipos están en estado "en venta" y por qué?
- [ ] ¿Tenemos algún contrato con cláusula de exclusividad?

## 2. Flota

- [ ] ¿Cuál es la meta de disponibilidad mensual por tipo de equipo?
- [ ] ¿Qué vehículos de los 55 están cerca de los 15 años (bloqueo DS 298)?
- [ ] ¿Quién autoriza un override manual de estado diario?
- [ ] ¿Cómo se prioriza cuándo entra un equipo a mantención si está arrendado?
- [ ] ¿Hay plan de renovación de flota? ¿Presupuesto 2026?
- [ ] ¿Operación Calama/Atacama: qué tan independiente es de Coquimbo?
- [ ] ¿Qué marcas predominan y con qué proveedor de servicio técnico?

## 3. Mantenimiento

- [ ] ¿La pauta preventiva estándar por tipo de equipo está toda cargada?
- [ ] ¿MTTR y MTBF están calculándose hoy? ¿Cuál es la meta?
- [ ] ¿Quién es el jefe de taller en Coquimbo? ¿Y en Calama?
- [ ] ¿Stock crítico de repuestos — quién autoriza compras urgentes?
- [ ] ¿Proveedor preferido de neumáticos, lubricantes, filtros?
- [ ] ¿Tenemos contrato de mantención con servicio técnico externo (Scania, Volvo, etc.)?
- [ ] ¿Hay histórico de fallas recurrentes por modelo?

## 4. Prevención y normativa

- [ ] ¿Quién es el prevencionista titular?
- [ ] ¿Está el SEMEP de cada conductor actualizado?
- [ ] ¿Hay calendario de capacitaciones y refrescamientos para 2026?
- [ ] ¿Últimos incidentes reportables (Ley 16.744)? ¿Cómo se cerraron?
- [ ] ¿Auditorías externas próximas? (Mutualidad, SEC, cliente minero)
- [ ] ¿Tenemos PTS documentado para cada actividad crítica (DS 132)?
- [ ] ¿Cómo se controla la fatiga del conductor (Ley 21.561) hoy?
- [ ] ¿Quién firma las no conformidades?

## 5. Sistema SICOM-ICEO

- [ ] ¿Quién administra el sistema además de mí? (para evitar pisar configs)
- [ ] ¿Hay un backup recurrente y quién lo monitorea?
- [ ] ¿Integración GPS: qué proveedor (ARM, OHP, otro)?
- [ ] ¿Hay módulos o pantallas que no se están usando y por qué?
- [ ] ¿El reporte diario al cliente se envía automático o manual?
- [ ] ¿Quién tiene rol administrador además de mí?
- [ ] ¿Hay entornos separados (staging / producción) o solo uno?

## 6. KPIs y metas

- [ ] Meta OEE flota global 2026: ____ %
- [ ] Meta disponibilidad mecánica: ____ %
- [ ] Meta cumplimiento PM: ____ %
- [ ] Meta ICEO (score global): ____
- [ ] ¿A quién se reporta el dashboard ejecutivo y con qué frecuencia?
- [ ] ¿Hay bono a la empresa por cumplir cierto ICEO?

## 7. Equipo humano

- [ ] Pedir organigrama actualizado (gerencia → subgerente → jefes → supervisores → técnicos)
- [ ] ¿Hay incentivos por KPI al personal? ¿Cómo se calculan hoy?
- [ ] ¿Qué rotación tenemos de conductores y técnicos?
- [ ] ¿Horario/turnos base en Calama vs Coquimbo?
- [ ] ¿Quién conoce bien el Excel V30 antes de digitalizarlo?

## 8. Datos que faltan cargar al sistema

- [ ] Fechas SEMEP reales de cada conductor (hoy hay 8 alertas pendientes)
- [ ] RUT y teléfono de cada usuario creado (demo queda con campos NULL)
- [ ] Horómetros y kilometraje inicial por equipo para planes PM
- [ ] Tarifas vigentes de cada contrato
- [ ] Contactos de emergencia del cliente en cada faena

---

## Meta primera semana

- [ ] Navegar los 22 módulos del sistema con datos reales
- [ ] Entender el flujo de una OT extremo a extremo (crear → ejecutar → cerrar)
- [ ] Leer la matriz de permisos por rol (tabla `_roles_matriz_permisos`)
- [ ] Visitar Taller Coquimbo y conocer a los 8 técnicos del seed
- [ ] Revisar las 25 alertas abiertas y categorizarlas por urgencia
- [ ] Crear los 14 usuarios demo en Supabase y ejecutar migración 35
- [ ] Proponer 2 mejoras al gerente general basándome en lo observado
