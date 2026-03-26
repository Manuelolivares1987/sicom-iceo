# SICOM-ICEO — Sistema Integral de Control Operacional, Mantenimiento, Inventario e ICEO

## Presentación Ejecutiva — Empresas Pillado
### Trayectoria y Compromiso

---

# 1. QUÉ ES SICOM-ICEO

SICOM-ICEO es una plataforma web de nivel industrial diseñada para gestionar la operación completa de contratos de servicio en faenas mineras. Cubre administración de combustibles y lubricantes, mantenimiento de plataformas fijas y móviles, control de inventario valorizado, y medición automática del ICEO (Índice Compuesto de Excelencia Operacional).

El sistema fue construido específicamente para Empresas Pillado y opera sobre tecnología moderna: Next.js 14 como frontend, Supabase (PostgreSQL) como backend, y Netlify como plataforma de despliegue. Es accesible desde celular, tablet y computador.

**URL del sistema:** https://pilladoiceo.netlify.app
**Repositorio:** https://github.com/Manuelolivares1987/sicom-iceo

---

# 2. PROBLEMA QUE RESUELVE

Antes de SICOM-ICEO, la operación enfrentaba estos problemas críticos:

- No existía trazabilidad completa de las tareas de mantenimiento
- Se descubría después si una tarea se ejecutó o no
- Las tareas no ejecutadas por problemas operativos no quedaban formalmente registradas
- El inventario se controlaba parcialmente y no estaba valorizado
- El uso de materiales, combustibles y repuestos no estaba amarrado a una orden de trabajo
- No existía visión integrada del contrato, mantenimiento, inventario y excelencia operacional
- No había sistema auditable para calcular KPI ni incentivos

SICOM-ICEO resuelve cada uno de estos problemas con un sistema donde toda operación es trazable, auditable y medible.

---

# 3. PRINCIPIOS RECTORES

El sistema opera bajo reglas que no se pueden violar:

1. **La Orden de Trabajo (OT) es el eje central** — toda operación gira alrededor de OTs
2. **Tarea sin evidencia = tarea no ejecutada** — no se puede cerrar una OT sin foto
3. **Consumo de inventario sin OT = no permitido** — toda salida de bodega requiere OT asociada
4. **Todo movimiento queda auditado** — quién hizo qué, cuándo y con qué impacto
5. **Todo KPI sale de datos reales** — no hay entrada manual de indicadores
6. **El ICEO se calcula automáticamente** — desde OTs, inventario, certificaciones e incidentes
7. **OT cerrada = inmutable** — después del cierre supervisor, nada puede modificarse

---

# 4. MÓDULOS DEL SISTEMA

## 4.1 Dashboard Gerencial
Panel ejecutivo con ICEO del período, OTs activas, cumplimiento PM, inventario valorizado, tendencias y alertas. Vista diferente según el rol del usuario.

## 4.2 Mis OTs (Vista Operador)
El técnico de terreno ve solo sus OTs asignadas, agrupadas por estado. Puede ejecutar checklist, subir fotos y registrar materiales desde su celular.

## 4.3 Órdenes de Trabajo
Centro de gestión de OTs con 9 estados posibles: creada, asignada, en ejecución, pausada, ejecutada OK, ejecutada con observaciones, no ejecutada, cancelada y cerrada. Cada transición está validada por reglas de negocio en el servidor.

Cada OT incluye: folio automático, tipo, activo asociado, responsable, checklist, evidencias fotográficas, materiales consumidos, costos y firma del supervisor.

## 4.4 Activos y Equipos
Registro completo de cada equipo con marca, modelo, serie, faena, estado operacional, criticidad, kilometraje, horas de uso y ciclos. Cada equipo tiene un código QR único que puede imprimirse y pegarse en el equipo físico. Al escanearlo, muestra la ficha digital del equipo.

La ficha del equipo muestra: datos generales, historial completo de mantenciones, planes PM, certificaciones, costos acumulados, MTTR, MTBF, disponibilidad y health score.

## 4.5 Mantenimiento Preventivo
Planes de mantenimiento basados en pautas del fabricante, con frecuencias por tiempo, kilometraje, horas de uso o ciclos. El sistema genera OTs preventivas automáticamente cuando se cumple la condición de disparo. Cada OT preventiva viene con su checklist pre-cargado desde la pauta del fabricante.

## 4.6 Inventario Valorizado
Control completo de combustibles, lubricantes, filtros, repuestos y consumibles. Cada producto tiene costo promedio ponderado (CPP) calculado automáticamente. El sistema maneja entradas, salidas, ajustes, transferencias entre bodegas, mermas y conteos con pistola de inventario.

Regla crítica: toda salida de inventario requiere OT válida. El sistema valida que la bodega pertenezca a la misma faena de la OT.

## 4.7 Conteo con Pistola/Escáner
Flujo completo de conteo físico de inventario con soporte para pistola industrial y cámara del celular. El sistema compara automáticamente stock físico vs. sistema y calcula diferencias valorizadas. El supervisor puede aprobar el conteo y generar ajustes automáticos.

## 4.8 Abastecimiento y Lubricación
Gestión de rutas de despacho, control de cumplimiento, registro de volumen despachado y control de diferencias programado vs. real.

## 4.9 Cumplimiento Documental
Seguimiento de certificaciones SEC, SEREMI, SISS, revisión técnica, SOAP, calibraciones y licencias. Alertas automáticas por vencimiento a 30, 15, 7 y 1 día. Bloqueo operacional si una certificación crítica está vencida.

## 4.10 KPI (Indicadores Clave)
21 KPIs distribuidos en 3 áreas, calculados automáticamente desde datos operacionales del sistema. Cada KPI tiene fórmula, meta, peso, umbrales y drill-down a los datos fuente.

## 4.11 ICEO
Índice Compuesto de Excelencia Operacional. Consolida los 21 KPIs en un score único de 0 a 100. Clasificación: Deficiente (<70), Aceptable (70-84), Bueno (85-94), Excelencia (≥95). Los bloqueantes pueden anular el ICEO o bloquear incentivos.

## 4.12 Incentivos
Cálculo automático de incentivos variables por trabajador basado en el ICEO del período. Tramos de pago configurables. Aprobación por supervisor antes de pago.

## 4.13 Reportes
8 tipos de reportes exportables a CSV y Excel: OTs, inventario valorizado, movimientos, cumplimiento PM, certificaciones, KPI mensual, ICEO e historial por activo.

## 4.14 Auditoría
Log completo de todas las acciones del sistema con diff JSON de cambios. Filtrable por tabla, acción, fecha y usuario.

## 4.15 Administración
Gestión de usuarios y roles, configuración de KPI/ICEO, editor de plantillas de checklist por tipo de OT.

---

# 5. PERFILES DE USUARIO

El sistema tiene 10 roles con permisos diferenciados. Cada rol ve solo los módulos que le corresponden:

| Rol | Qué puede hacer |
|-----|----------------|
| **Administrador** | Acceso total: crear, editar, eliminar, configurar |
| **Gerencia** | Ver todo en solo lectura: dashboards, KPI, ICEO, reportes |
| **Subgerente de Operaciones** | Ver todo, aprobar OTs |
| **Supervisor** | Ver OTs de su faena, cerrar OTs, registrar incidentes |
| **Planificador** | Crear y asignar OTs, gestionar planes PM |
| **Técnico de Mantenimiento** | Ver y ejecutar sus OTs asignadas, completar checklist, subir evidencia |
| **Bodeguero** | Gestionar inventario, realizar conteos, registrar salidas |
| **Operador de Abastecimiento** | Registrar abastecimientos y rutas de despacho |
| **Auditor** | Ver todo sin modificar |
| **RRHH / Incentivos** | Ver KPI, ICEO e incentivos |

---

# 6. KPIs DEL SISTEMA

## Área A — Administración de Lubricantes y Combustibles (8 KPIs)

| Código | KPI | Meta | Bloqueante |
|--------|-----|------|-----------|
| A1 | Disponibilidad de Puntos de Abastecimiento | ≥98% | Sí — bloquea incentivo si <90% |
| A2 | Precisión de Despacho de Combustible | ≥99% | No |
| A3 | Cumplimiento de Rutas Programadas | ≥97% | No |
| A4 | Exactitud de Inventario Combustibles | ≥99.5% | Sí — penaliza ICEO si <95% |
| A5 | Tiempo de Respuesta Abastecimiento | ≥95% | No |
| A6 | Merma Operacional Combustible | ≤0.3% | Sí — descuenta 30 pts si >1% |
| A7 | Cumplimiento Documental | 100% | Sí — bloquea incentivo si <90% |
| A8 | Incidentes Ambientales | 0 | Sí — ANULA ICEO si ≥1 incidente |

## Área B — Mantenimiento de Puntos Fijos (6 KPIs)

| Código | KPI | Meta | Bloqueante |
|--------|-----|------|-----------|
| B1 | Cumplimiento Plan Preventivo Fijos | ≥98% | Sí — bloquea incentivo si <85% |
| B2 | Disponibilidad de Activos Fijos | ≥97% | Sí — penaliza ICEO si <90% |
| B3 | MTTR Activos Fijos | ≤4 horas | No |
| B4 | Cumplimiento de Calibraciones | 100% | Sí — bloquea incentivo si <90% |
| B5 | Exactitud Inventario Repuestos Fijos | ≥98% | No |
| B6 | Backlog Correctivas Fijos | ≤5% | No |

## Área C — Mantenimiento de Puntos Móviles (7 KPIs)

| Código | KPI | Meta | Bloqueante |
|--------|-----|------|-----------|
| C1 | Cumplimiento PM Móviles | ≥97% | Sí — bloquea incentivo si <85% |
| C2 | Disponibilidad Flota Móvil | ≥95% | Sí — penaliza ICEO si <85% |
| C3 | MTTR Flota Móvil | ≤8 horas | No |
| C4 | Certificaciones Vehiculares | 100% | Sí — bloquea incentivo si <95% |
| C5 | Eficiencia Combustible Flota | ≥95% | No |
| C6 | Exactitud Inventario Repuestos Móviles | ≥98% | No |
| C7 | Backlog Correctivas Móviles | ≤8% | No |

---

# 7. CÁLCULO DEL ICEO

El ICEO se calcula así:

1. Se mide cada KPI desde datos reales del sistema
2. Se calcula el porcentaje de cumplimiento respecto a la meta
3. Se asigna un puntaje según tramos (0 a 100 puntos)
4. Se pondera por el peso del KPI dentro de su área
5. Se suman los puntajes por área
6. Se aplican los pesos por área: A (35%), B (35%), C (30%)
7. Se evalúan los bloqueantes
8. Se clasifica el resultado

Clasificación del ICEO:
- 95-100: Excelencia → 100% del incentivo
- 90-94: Muy Bueno → 90% del incentivo
- 85-89: Bueno → 75% del incentivo
- 80-84: Aceptable → 50% del incentivo
- 70-79: Regular → 25% del incentivo
- Menor a 70: Deficiente → 0% del incentivo

Si hay un bloqueante activo (por ejemplo, un incidente ambiental), el ICEO puede reducirse a 0 y el incentivo se suspende completamente.

---

# 8. INCENTIVOS VARIABLES

El sistema calcula automáticamente el incentivo mensual de cada trabajador:

1. Se obtiene el ICEO del período
2. Se busca el tramo correspondiente (qué porcentaje del incentivo máximo se paga)
3. Se multiplica por el sueldo base y el porcentaje máximo de incentivo del cargo
4. Si hay bloqueante activo, el monto es $0

Ejemplo: Un técnico con sueldo base $1.200.000 y 12% de incentivo máximo. Si el ICEO es 92 (tramo 90%), su incentivo sería: $1.200.000 × 12% × 90% = $129.600.

El sistema también contempla un bono anual de excelencia sostenida para quienes mantengan ICEO ≥95 durante 12 meses consecutivos.

---

# 9. TRAZABILIDAD POR EQUIPO (QR)

Cada equipo del contrato tiene un código QR único. Al escanearlo desde un celular o tablet, se abre la ficha digital del equipo que muestra:

- Código, nombre, marca, modelo, serie
- Estado operacional (operativo, en mantención, fuera de servicio)
- Última mantención y próxima mantención programada
- OTs abiertas
- Certificaciones vigentes, por vencer y vencidas
- Costo acumulado de mantención
- MTTR (tiempo medio de reparación)

El QR puede descargarse como imagen PNG e imprimirse para pegar en el equipo físico. La ficha pública es accesible sin login. Para ver el detalle completo (historial, costos, checklist), se requiere acceso al sistema.

---

# 10. KPIs POR ACTIVO INDIVIDUAL

Además de los 21 KPIs operacionales, cada equipo individual tiene sus propios indicadores:

| KPI | Descripción |
|-----|-------------|
| MTTR | Tiempo promedio de reparación (horas) |
| MTBF | Tiempo promedio entre fallas (horas) |
| Disponibilidad | Porcentaje de horas operativas vs. horas del período |
| Cumplimiento PM | Porcentaje de mantenciones preventivas ejecutadas |
| Tasa de Correctivos | Porcentaje de OTs correctivas vs. total |
| Cumplimiento Documental | Porcentaje de certificaciones vigentes |
| Health Score | Índice compuesto de salud del equipo (0-100) |

El Health Score se calcula: 30% disponibilidad + 25% cumplimiento PM + 20% cumplimiento documental + 15% tasa correctivos + 10% MTTR.

Un ranking ordena todos los equipos del peor al mejor health score para priorizar intervenciones.

---

# 11. AUTOMATIZACIÓN

El sistema ejecuta tareas automáticas sin intervención humana:

| Tarea | Frecuencia | Qué hace |
|-------|-----------|----------|
| Generar OTs preventivas | Diario (01:00) | Evalúa planes PM y crea OTs automáticas |
| Verificar certificaciones | Diario (06:00) | Actualiza estados, genera alertas, bloquea activos |
| Alertas stock mínimo | Cada 6 horas | Detecta productos bajo nivel mínimo |
| Detectar OTs vencidas | Diario (07:00) | Alerta sobre OTs con fecha pasada |
| Recálculo KPI | Diario (23:00) | Recalcula KPIs e ICEO para contratos activos |
| Procesar recálculos ICEO | Cada 2 horas | Procesa recálculos pendientes por eventos (cierre OT, incidentes) |

Cada ejecución queda registrada en un log con resultado, duración y errores.

---

# 12. SEGURIDAD Y AUDITORÍA

- **Autenticación:** Login con email y contraseña vía Supabase Auth
- **Autorización:** Row Level Security (RLS) en PostgreSQL — cada usuario ve solo lo que corresponde a su rol
- **Permisos en UI:** El sidebar muestra solo los módulos permitidos para cada rol
- **Auditoría:** Toda acción crítica queda registrada con JSON antes/después, usuario, fecha y hora
- **Inmutabilidad:** OTs cerradas no pueden modificarse (trigger en PostgreSQL bloquea cambios)
- **Transacciones atómicas:** Operaciones críticas usan RPCs con locks exclusivos para prevenir inconsistencias

---

# 13. TECNOLOGÍA

| Componente | Tecnología |
|-----------|------------|
| Frontend | Next.js 14, React 18, TypeScript, Tailwind CSS |
| Backend | Supabase (PostgreSQL 15) |
| Base de datos | 24 archivos SQL, 50+ tablas, 22 RPCs, 36 triggers |
| Autenticación | Supabase Auth con JWT |
| Almacenamiento | Supabase Storage (fotos, documentos) |
| Deploy | Netlify con CI/CD desde GitHub |
| Escáner | html5-qrcode (cámara + pistola industrial) |
| QR | Librería qrcode para generación de imágenes |
| Gráficos | Recharts |

---

# 14. INVENTARIO DEL SISTEMA

| Métrica | Cantidad |
|---------|----------|
| Archivos SQL | 24 |
| Líneas SQL | 12.000+ |
| Archivos frontend | 90+ |
| Líneas frontend | 18.000+ |
| Rutas/páginas | 23 |
| RPCs transaccionales | 22 |
| Triggers PostgreSQL | 36 |
| Vistas SQL | 11 |
| Hooks React Query | 15 |
| Services (capa datos) | 14 |
| Componentes UI | 20+ |
| Módulos domain | 4 |
| Jobs automáticos pg_cron | 7 |
| Roles de usuario | 10 |
| KPIs | 21 + 7 por activo |
| Reportes exportables | 8 |
| Documentos de arquitectura | 9 |

---

# 15. FLUJO OPERACIONAL TÍPICO

```
PLANIFICADOR crea OT → asigna técnico → OT queda "Asignada"
     ↓
TÉCNICO abre "Mis OTs" desde celular → inicia ejecución
     ↓
TÉCNICO completa checklist (OK/NO OK/N/A) → sube fotos de evidencia
     ↓
BODEGUERO registra salida de materiales con escáner → asocia a la OT
     ↓
TÉCNICO finaliza OT (sistema valida checklist + evidencia)
     ↓
SUPERVISOR revisa: costos, evidencia, checklist → cierra definitivamente
     ↓
SISTEMA recalcula KPIs → actualiza ICEO → calcula incentivos
     ↓
GERENCIA ve dashboard ejecutivo con ICEO, KPIs y tendencias
```

---

# 16. PRÓXIMOS PASOS

| Mejora | Descripción |
|--------|-------------|
| PWA Offline | Operación en terreno sin conexión a internet |
| Firma Digital | Firma con dedo en pantalla para técnicos |
| PDF Corporativo | Reportes con logo y formato Pillado Empresas |
| Notificaciones Push | Alertas en tiempo real al celular |
| Testing Automatizado | Suite de tests para prevenir regresiones |
| Multi-tenancy | Preparación para operar múltiples contratos como SaaS |

---

*SICOM-ICEO — Empresas Pillado — Trayectoria y Compromiso*
*Versión 1.0 — Marzo 2026*
