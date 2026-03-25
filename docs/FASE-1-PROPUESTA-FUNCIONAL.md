# FASE 1 — PROPUESTA FUNCIONAL INTEGRAL

## Sistema Integral de Control Operacional, Mantenimiento, Inventario e ICEO (SICOM-ICEO)

---

## 1. RESUMEN EJECUTIVO

SICOM-ICEO es un sistema web de nivel industrial diseñado para operar contratos de servicio en faenas mineras que involucran:

- Administración de combustibles y lubricantes
- Mantenimiento de plataformas fijas (islas de abastecimiento, estanques, surtidores)
- Mantenimiento de plataformas móviles (camiones cisterna, lubrimóviles, equipos de bombeo)
- Control de inventario valorizado con captura por pistola/escáner
- Medición automatizada de KPI e ICEO (Índice Compuesto de Excelencia Operacional)

El sistema resuelve la falta de trazabilidad operacional, la desconexión entre inventario y órdenes de trabajo, la ausencia de control de costos por tarea, y la inexistencia de un índice integrado de desempeño contractual.

**Principio rector:** Toda acción operacional debe ser trazable, auditable y medible. No existe operación válida sin evidencia, sin responsable y sin asociación a una orden de trabajo.

---

## 2. ARQUITECTURA RECOMENDADA

### 2.1 Diagrama de Arquitectura General

```
┌─────────────────────────────────────────────────────────────────────┐
│                        NETLIFY (CDN + Deploy)                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              Next.js 14 (App Router, SSG/SSR)                 │  │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌─────────────────┐  │  │
│  │  │Dashboard│ │  OTs     │ │Inventario│ │  KPI / ICEO     │  │  │
│  │  │Gerencial│ │Terreno   │ │Valorizado│ │  Dashboards     │  │  │
│  │  └─────────┘ └──────────┘ └──────────┘ └─────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │  PWA Shell (Service Worker + Cache + Offline Queue)     │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────────┘
                             │ HTTPS
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         SUPABASE                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │   Auth   │ │PostgreSQL│ │ Storage  │ │Realtime  │ │  Edge    │ │
│  │  + RLS   │ │  + RPC   │ │ Buckets  │ │Subscript.│ │Functions │ │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  PostgreSQL Functions:                                        │   │
│  │  - calcular_kpi(periodo, area)                                │   │
│  │  - calcular_iceo(periodo, contrato)                           │   │
│  │  - valorizar_inventario(bodega)                               │   │
│  │  - validar_cierre_ot(ot_id)                                   │   │
│  │  - registrar_movimiento_inventario(...)                       │   │
│  │  - generar_ots_preventivas()                                  │   │
│  │  - verificar_vencimientos()                                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  pg_cron Jobs:                                                │   │
│  │  - Generación automática OTs preventivas (diario 00:00)      │   │
│  │  - Verificación vencimientos documentales (diario 06:00)     │   │
│  │  - Recálculo KPI diarios (diario 23:00)                      │   │
│  │  - Cierre de período ICEO (mensual día 1, 01:00)             │   │
│  │  - Alertas de stock mínimo (cada 4 horas)                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Supabase Edge Functions:                                     │   │
│  │  - Generación de reportes PDF/Excel                           │   │
│  │  - Procesamiento de lecturas de pistola (batch)               │   │
│  │  - Notificaciones push/email                                  │   │
│  │  - Webhook de sincronización offline                          │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Decisiones Arquitectónicas Clave

| Decisión | Elección | Justificación |
|----------|----------|---------------|
| Framework frontend | **Next.js 14 (App Router)** | SSG para dashboards públicos, SSR para datos en tiempo real, API routes para lógica ligera, excelente soporte PWA |
| UI Library | **Tailwind CSS + shadcn/ui** | Componentes industriales, accesibles, altamente personalizables, sin overhead de runtime |
| Estado global | **Zustand + TanStack Query** | Zustand para estado UI, TanStack Query para cache de servidor con invalidación automática |
| Formularios | **React Hook Form + Zod** | Validación en cliente y servidor con esquemas compartidos, ideal para formularios complejos de OT |
| Gráficos | **Recharts + custom gauges** | Ligero, responsive, ideal para semáforos e indicadores industriales |
| Reportes | **@react-pdf/renderer + ExcelJS** | Generación client-side o edge function para PDFs y Excel |
| Escáner | **html5-qrcode** | Lectura de código de barras/QR desde cámara del dispositivo, sin hardware adicional |
| PWA | **next-pwa + Workbox** | Cache de assets, cola offline para OTs en terreno, sincronización posterior |
| Autenticación | **Supabase Auth** | Email/password para usuarios corporativos, refresh tokens, sesiones persistentes |
| Autorización | **Supabase RLS** | Políticas por rol a nivel de fila, imposible bypassear desde cliente |
| Base de datos | **PostgreSQL en Supabase** | Funciones PL/pgSQL para lógica crítica, triggers, vistas materializadas para KPI |
| Almacenamiento | **Supabase Storage** | Buckets por tipo (evidencias, documentos, certificados), políticas de acceso por rol |
| Deploy | **Netlify** | Build automático desde Git, preview deploys, edge redirects, variables de entorno |

### 2.3 Estrategia PWA y Modo Offline

El sistema debe operar en faenas mineras con conectividad limitada. La estrategia offline es:

```
MODO OFFLINE PARCIAL
│
├── Datos cacheados al iniciar turno:
│   ├── OTs asignadas del día
│   ├── Checklists asociados
│   ├── Catálogo de productos (inventario)
│   ├── Lista de activos de la faena
│   └── Datos del usuario y permisos
│
├── Operaciones permitidas offline:
│   ├── Completar checklists
│   ├── Tomar fotografías (almacenadas en IndexedDB)
│   ├── Registrar observaciones
│   ├── Marcar inicio/fin de tareas
│   └── Lectura de códigos de barra (cola de movimientos)
│
├── Sincronización al recuperar conexión:
│   ├── Cola FIFO con timestamp original
│   ├── Conflictos resueltos por timestamp + prioridad servidor
│   ├── Evidencias fotográficas subidas en background
│   ├── Confirmación visual de sincronización exitosa
│   └── Indicador permanente de estado de conexión
│
└── Operaciones que REQUIEREN conexión:
    ├── Cierre definitivo de OT (requiere validación servidor)
    ├── Movimientos de inventario (requiere validación de stock)
    ├── Creación de nuevas OTs
    └── Consulta de dashboards y reportes
```

---

## 3. MAPA DE MÓDULOS

### 3.1 Mapa Funcional Completo

```
SICOM-ICEO
│
├── M1. CONTRATOS Y GESTIÓN CONTRACTUAL
│   ├── Registro de contratos
│   ├── Faenas asociadas
│   ├── SLA y obligaciones
│   ├── Frecuencia de tareas contractuales
│   ├── Hitos de cumplimiento
│   ├── Matriz de responsabilidades
│   ├── Control de desviaciones
│   └── Alertas de incumplimiento
│
├── M2. ACTIVOS
│   ├── Maestro de activos
│   │   ├── Puntos fijos (islas, estanques, surtidores, bombas, mangueras)
│   │   ├── Puntos móviles (cisterna, lubrimóvil, bombeo)
│   │   ├── Herramientas críticas
│   │   └── Equipos de captura (pistolas/escáneres)
│   ├── Ficha técnica completa
│   ├── Historial de intervenciones
│   ├── Documentación vigente
│   ├── Semáforo operacional
│   └── Árbol de ubicación (contrato > faena > zona > posición)
│
├── M3. ÓRDENES DE TRABAJO (EJE CENTRAL)
│   ├── Creación manual y automática
│   ├── Tipos: inspección, PM, CM, abastecimiento, lubricación, inventario, regularización
│   ├── Flujo de estados completo
│   ├── Asignación de responsables
│   ├── Checklists dinámicos por tipo
│   ├── Captura de evidencia obligatoria
│   ├── Firma digital
│   ├── Asociación de materiales/consumos
│   ├── Costeo por OT
│   ├── Causa de no ejecución
│   └── Cierre con validación supervisor
│
├── M4. MANTENIMIENTO PREVENTIVO
│   ├── Planes por tiempo/km/horas/ciclos
│   ├── Pautas de mantenimiento (checklists maestros)
│   ├── Generación automática de OTs
│   ├── Calendario de vencimientos
│   ├── Alertas por proximidad
│   ├── Semaforización
│   └── Cumplimiento PM por activo/tipo/faena
│
├── M5. MANTENIMIENTO CORRECTIVO
│   ├── Notificación de falla (desde terreno)
│   ├── Clasificación de criticidad
│   ├── MTTR calculado
│   ├── Análisis causa raíz
│   ├── Tiempos muertos
│   ├── Reincidencia por activo
│   ├── Consumo de repuestos
│   ├── Impacto operacional
│   └── Cierre técnico + validación supervisor
│
├── M6. INVENTARIO VALORIZADO
│   ├── Maestro de productos
│   │   ├── Combustibles (diesel, gasolina)
│   │   ├── Lubricantes (aceites motor, hidráulicos, transmisión, grasas)
│   │   ├── Filtros (aceite, aire, combustible, hidráulico)
│   │   ├── Repuestos
│   │   ├── Consumibles
│   │   └── EPP
│   ├── Bodegas y ubicaciones
│   ├── Stock por bodega/faena/unidad móvil
│   ├── Lotes y vencimientos
│   ├── Unidades de medida
│   ├── Valorización
│   │   ├── Costo promedio ponderado (CPP) — método por defecto
│   │   ├── FIFO (configurable)
│   │   └── Valorización total en tiempo real
│   ├── Kardex completo por producto/bodega
│   ├── Stock mínimo/máximo con alertas
│   ├── Ajustes controlados
│   ├── Mermas con trazabilidad
│   ├── Transferencias entre bodegas
│   └── Conciliación físico vs. sistema
│
├── M7. CAPTURA CON PISTOLA / ESCÁNER
│   ├── Lectura código de barras y QR
│   │   ├── Desde pistola industrial (interfaz web)
│   │   └── Desde cámara del dispositivo (fallback)
│   ├── Modos de operación:
│   │   ├── Recepción de productos
│   │   ├── Salida de productos (requiere OT)
│   │   ├── Conteo cíclico
│   │   ├── Conteo general
│   │   └── Transferencia entre ubicaciones
│   ├── Confirmación por usuario
│   ├── Registro automático en Supabase
│   └── Cola offline con sincronización
│
├── M8. ABASTECIMIENTO Y LUBRICACIÓN
│   ├── Programación de abastecimientos
│   ├── Programación de lubricación
│   ├── Ejecución por ruta/faena
│   ├── Control de cumplimiento
│   ├── Registro de volumen despachado
│   ├── Control de diferencias (programado vs. real)
│   ├── Despacho oportuno
│   └── Historial por cliente interno/activo
│
├── M9. DOCUMENTAL Y CUMPLIMIENTO
│   ├── Certificaciones
│   │   ├── SEC (instalaciones eléctricas)
│   │   ├── SEREMI Salud (sanitarias)
│   │   ├── SISS (aguas)
│   │   ├── Revisión técnica vehicular
│   │   ├── SOAP
│   │   ├── Permisos municipales
│   │   ├── Calibraciones de equipos
│   │   └── Licencias de conducir especiales
│   ├── Alertas de vencimiento (30/15/7/1 día)
│   ├── Documentos adjuntos por activo
│   ├── Bloqueo operacional por incumplimiento crítico
│   └── Dashboard de vigencias
│
├── M10. KPI
│   ├── Motor de cálculo automático
│   ├── KPI por área:
│   │   ├── A. Administración combustibles/lubricantes
│   │   ├── B. Mantenimiento puntos fijos
│   │   └── C. Mantenimiento puntos móviles
│   ├── Frecuencias: diario, semanal, mensual
│   ├── Ponderaciones configurables
│   ├── Bloqueantes configurables
│   ├── Tramos de cumplimiento
│   ├── Tendencias
│   └── Drill-down hasta OT/activo/evento
│
├── M11. ICEO
│   ├── Índice compuesto global
│   ├── Consolidación de KPI por área
│   ├── Ponderación por área
│   ├── Reglas de bloqueantes
│   ├── Desglose por faena/contrato/supervisor
│   ├── Visualización: diario/semanal/mensual/anual
│   ├── Tendencia y comparación
│   ├── Top causas de caída
│   └── Drill-down completo
│
├── M12. DASHBOARDS
│   ├── Gerencial
│   ├── Supervisor
│   ├── Técnico
│   └── Bodega/Inventario
│
├── M13. REPORTERÍA
│   ├── Exportación PDF y Excel
│   ├── Reportes estándar (12+ reportes definidos)
│   └── Filtros dinámicos
│
├── M14. AUDITORÍA
│   ├── Log de todas las acciones
│   ├── Usuario, fecha, hora, IP, acción, datos antes/después
│   └── Consulta por rango, usuario, entidad
│
└── M15. ADMINISTRACIÓN
    ├── Usuarios y roles
    ├── Perfiles y permisos (RLS)
    ├── Parámetros del sistema
    ├── Configuración de KPI y ICEO
    └── Configuración de alertas
```

### 3.2 Matriz de Dependencias entre Módulos

```
            M1  M2  M3  M4  M5  M6  M7  M8  M9  M10 M11
M1 Contrat  --  ←   ←               ←       ←   ←   ←
M2 Activos  →   --  ←   ←   ←           ←   ←   ←
M3 OTs      →   →   --  ←   ←   ←   ←   ←       ←   ←
M4 PM       →   →   →   --                       ←
M5 CM       →   →   →       --                   ←
M6 Invent.  →       →               --  ←            ←
M7 Pistola          →           →       --
M8 Abast.  →   →   →                        --   ←
M9 Docum.  →   →                                 --  ←
M10 KPI    →           →   →   →       →   →    --  ←
M11 ICEO   →                                     →   --

→ = depende de    ← = es requerido por
```

**Lectura:** M3 (OTs) es el módulo más interconectado — es el eje central del sistema. Todo fluye hacia y desde las OTs.

---

## 4. FLUJO OPERACIONAL COMPLETO

### 4.1 Flujo Principal: Ciclo de Vida de una Orden de Trabajo

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     CICLO DE VIDA DE UNA OT                              │
└──────────────────────────────────────────────────────────────────────────┘

 ┌─────────┐     ┌─────────┐     ┌──────────┐     ┌──────────────┐
 │ ORIGEN  │────▶│ CREADA  │────▶│ ASIGNADA │────▶│ EN EJECUCIÓN │
 └─────────┘     └─────────┘     └──────────┘     └──────┬───────┘
      │                                                     │
      │  Orígenes:                                         │
      │  ① Plan preventivo (automático)            ┌───────┴────────┐
      │  ② Notificación de falla                   │                │
      │  ③ Programación abastecimiento         ┌───▼───┐      ┌────▼────┐
      │  ④ Solicitud de supervisor              │PAUSADA│      │EJECUTAR │
      │  ⑤ Hallazgo en inspección               └───┬───┘      └────┬────┘
      │  ⑥ Conteo de inventario                     │                │
      │  ⑦ Vencimiento documental                   │    ┌───────────┴──────────┐
      │                                              │    │                      │
      │                                              │  ┌─▼──────────┐   ┌──────▼───────┐
      │                                              │  │EJECUTADA OK│   │EJECUTADA CON │
      │                                              │  │            │   │OBSERVACIONES │
      │                                              │  └─────┬──────┘   └──────┬───────┘
      │                                              │        │                  │
      │                                              │        └────────┬─────────┘
      │  ┌───────────┐    ┌───────────┐              │                 │
      └──│ CANCELADA │    │NO EJECUT. │◀─────────────┘         ┌───────▼───────┐
         └─────┬─────┘    └─────┬─────┘                        │   VALIDACIÓN  │
               │                │                              │  SUPERVISOR   │
               │           ┌────▼──────┐                       └───────┬───────┘
               │           │ REGISTRO  │                               │
               │           │ CAUSA NO  │                       ┌───────▼───────┐
               │           │ EJECUCIÓN │                       │    CERRADA    │
               │           └───────────┘                       └───────┬───────┘
               │                                                       │
               └───────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │  AUDITORÍA +     │
                              │  CÁLCULO KPI +   │
                              │  IMPACTO ICEO    │
                              └─────────────────┘
```

### 4.2 Flujo A: Creación y Ejecución de OT Preventiva

```
PASO 1 — GENERACIÓN AUTOMÁTICA (pg_cron, diario 00:00)
────────────────────────────────────────────────────────
│ El sistema evalúa todos los planes preventivos activos
│ Para cada plan:
│   ├── ¿Cumple condición de disparo?
│   │   ├── Tiempo: fecha_ultima_ejecucion + frecuencia_dias <= hoy
│   │   ├── Km: km_actual - km_ultima_ejecucion >= frecuencia_km
│   │   ├── Horas: hrs_actual - hrs_ultima_ejecucion >= frecuencia_hrs
│   │   └── Ciclos: ciclos_actual - ciclos_ultima >= frecuencia_ciclos
│   │
│   └── SI cumple → Crear OT automática:
│       ├── tipo = 'preventivo'
│       ├── activo_id = plan.activo_id
│       ├── faena_id = activo.faena_id
│       ├── prioridad = plan.prioridad
│       ├── fecha_programada = hoy + plan.anticipacion_dias
│       ├── checklist = plan.pauta_mantenimiento.items
│       ├── materiales_estimados = plan.pauta.materiales
│       └── estado = 'creada'
│
│ → Registro en auditoria_eventos
│ → Notificación a planificador de la faena

PASO 2 — ASIGNACIÓN (Planificador o Supervisor, pantalla web)
──────────────────────────────────────────────────────────────
│ Planificador abre "OTs pendientes de asignar"
│   ├── Filtra por faena, prioridad, tipo
│   ├── Asigna técnico o cuadrilla
│   ├── Confirma fecha programada
│   └── Estado → 'asignada'
│
│ → Notificación push al técnico (PWA)
│ → Registro en auditoria_eventos

PASO 3 — EJECUCIÓN EN TERRENO (Técnico, celular/tablet)
─────────────────────────────────────────────────────────
│ Técnico abre su app (PWA) al iniciar turno
│   ├── Ve lista de OTs asignadas para hoy
│   ├── Selecciona OT a ejecutar
│   ├── Presiona "INICIAR" → Estado = 'en_ejecucion', fecha_inicio = now()
│   │
│   ├── Completa checklist paso a paso:
│   │   ├── Cada ítem: OK / NO OK / N/A
│   │   ├── Observación por ítem (opcional)
│   │   └── Foto por ítem (si requerido)
│   │
│   ├── Registra materiales usados:
│   │   ├── Escanea código de barras del producto
│   │   ├── Ingresa cantidad
│   │   ├── Sistema valida stock disponible
│   │   ├── Sistema asocia movimiento a esta OT
│   │   └── Costo se calcula automáticamente (CPP)
│   │
│   ├── Toma fotografías de evidencia:
│   │   ├── Antes (si aplica)
│   │   ├── Durante
│   │   └── Después
│   │
│   ├── Registra observaciones
│   │
│   ├── Presiona "FINALIZAR":
│   │   ├── Sistema valida:
│   │   │   ├── ¿Checklist completo? (todos los ítems respondidos)
│   │   │   ├── ¿Evidencia mínima cargada? (según configuración)
│   │   │   └── ¿Materiales registrados?
│   │   ├── Si validación OK → firma digital (dibujar con dedo)
│   │   ├── Estado → 'ejecutada_ok' o 'ejecutada_con_observaciones'
│   │   └── fecha_termino = now()
│   │
│   └── Si NO puede ejecutar:
│       ├── Selecciona causa de no ejecución (catálogo):
│       │   ├── Equipo no disponible
│       │   ├── Falta de repuestos
│       │   ├── Condición climática
│       │   ├── Prioridad operacional
│       │   ├── Problema de acceso
│       │   └── Otra (texto libre obligatorio)
│       ├── Toma foto de evidencia de impedimento
│       └── Estado → 'no_ejecutada'
│
│ → Sincronización automática (o cola offline)
│ → Registro en auditoria_eventos

PASO 4 — VALIDACIÓN SUPERVISOR (Supervisor, web/tablet)
─────────────────────────────────────────────────────────
│ Supervisor ve OTs pendientes de validación
│   ├── Revisa:
│   │   ├── Checklist completado
│   │   ├── Evidencia fotográfica
│   │   ├── Materiales consumidos
│   │   ├── Tiempos de ejecución
│   │   └── Observaciones
│   │
│   ├── Opciones:
│   │   ├── APROBAR → Estado = 'cerrada'
│   │   ├── RECHAZAR → Vuelve a 'asignada' con nota
│   │   └── OBSERVAR → Agrega observación, mantiene estado
│   │
│   └── Al cerrar:
│       ├── Se calcula costo total OT (MO + materiales)
│       ├── Se actualizan contadores del activo
│       ├── Se dispara recálculo de KPI afectados
│       └── Se evalúa impacto en ICEO
│
│ → Registro en auditoria_eventos

PASO 5 — IMPACTO EN KPI E ICEO (Automático)
─────────────────────────────────────────────
│ Al cerrar la OT, triggers PostgreSQL:
│   ├── Actualizar cumplimiento PM del activo
│   ├── Actualizar MTTR si es correctivo
│   ├── Actualizar disponibilidad del activo
│   ├── Actualizar consumos del período
│   ├── Recalcular KPI diario del área afectada
│   └── Recalcular ICEO si hay cambio significativo
```

### 4.3 Flujo B: Movimiento de Inventario con Pistola

```
ESCENARIO: Bodeguero entrega filtro de aceite para PM de camión cisterna

PASO 1 — IDENTIFICACIÓN
│ Técnico llega a bodega con OT asignada
│ Bodeguero abre módulo "Salida de Inventario"

PASO 2 — VALIDACIÓN OT
│ Escanea QR de la OT (impreso o desde pantalla del técnico)
│ Sistema valida:
│   ├── ¿OT existe?
│   ├── ¿Estado = 'en_ejecucion' o 'asignada'?
│   ├── ¿El producto solicitado es coherente con el tipo de OT?
│   └── ¿El técnico que solicita es el asignado?

PASO 3 — ESCANEO DE PRODUCTO
│ Bodeguero escanea código de barras del producto
│ Sistema muestra:
│   ├── Nombre del producto
│   ├── Stock disponible en esta bodega
│   ├── Costo unitario (CPP)
│   ├── Lote
│   └── Ubicación en bodega

PASO 4 — REGISTRO DE SALIDA
│ Bodeguero ingresa cantidad
│ Sistema valida:
│   ├── ¿Cantidad <= stock disponible?
│   ├── ¿OT asociada? (OBLIGATORIO)
│   └── ¿Producto identificado? (OBLIGATORIO)
│
│ Al confirmar:
│   ├── Se crea movimiento_inventario:
│   │   ├── tipo = 'salida'
│   │   ├── producto_id
│   │   ├── cantidad
│   │   ├── costo_unitario (CPP al momento)
│   │   ├── costo_total
│   │   ├── bodega_id
│   │   ├── ot_id (OBLIGATORIO)
│   │   ├── activo_id (del activo de la OT)
│   │   ├── usuario_id
│   │   ├── fecha_hora = now()
│   │   └── ubicacion
│   │
│   ├── Se actualiza stock del producto
│   ├── Se actualiza kardex
│   ├── Se recalcula valorización
│   └── Se asocia costo a la OT
│
│ → Registro en auditoria_eventos
│ → Si stock queda bajo mínimo → alerta automática

PASO 5 — CONTEO CÍCLICO (periódico)
│ Bodeguero selecciona "Conteo Cíclico"
│ Sistema presenta productos a contar (por rotación o aleatoriamente)
│ Por cada producto:
│   ├── Escanea código
│   ├── Sistema muestra stock teórico
│   ├── Bodeguero ingresa conteo físico
│   ├── Si hay diferencia:
│   │   ├── Sistema calcula diferencia
│   │   ├── Solicita motivo (catálogo):
│   │   │   ├── Merma operacional
│   │   │   ├── Error de conteo anterior
│   │   │   ├── Producto dañado
│   │   │   ├── Robo/hurto
│   │   │   └── Otro
│   │   ├── Genera ajuste con:
│   │   │   ├── Cantidad ajustada
│   │   │   ├── Impacto valorizado ($)
│   │   │   ├── Responsable
│   │   │   ├── Motivo
│   │   │   └── Autorización supervisor
│   │   └── Impacta KPI de exactitud de inventario (IRA)
```

### 4.4 Flujo C: Cálculo de KPI e ICEO

```
CÁLCULO DE KPI (diario, por área)
─────────────────────────────────
│ Función PostgreSQL: calcular_kpi(periodo, area)
│
│ Para cada KPI del área:
│   ├── Obtener fórmula de kpi_definiciones
│   ├── Obtener datos del período desde tablas operacionales
│   ├── Calcular valor
│   ├── Determinar tramo de cumplimiento:
│   │   ├── 100% = meta cumplida o superada
│   │   ├── Tramo según configuración (ej: >95%=100, 90-95=80, <90=50, <80=0)
│   │   └── 0% si es bloqueante y no cumple umbral mínimo
│   ├── Aplicar ponderación del KPI dentro del área
│   └── Guardar en mediciones_kpi
│
│ → Registrar cálculo en auditoria_eventos

CÁLCULO DE ICEO (al cierre de período o bajo demanda)
──────────────────────────────────────────────────────
│ Función PostgreSQL: calcular_iceo(periodo, contrato)
│
│ PASO 1 — Recopilar KPIs del período
│   ├── Área A: Administración combustibles/lubricantes
│   │   ├── KPI-A1: Diferencia inventario combustibles  (peso: 15%)
│   │   ├── KPI-A2: Diferencia inventario lubricantes    (peso: 10%)
│   │   ├── KPI-A3: Exactitud inventario IRA             (peso: 10%)
│   │   ├── KPI-A4: Cumplimiento normativo               (peso: 15%) [BLOQUEANTE]
│   │   ├── KPI-A5: Cumplimiento abastecimiento prog.    (peso: 15%)
│   │   ├── KPI-A6: Rotación de stock                    (peso: 10%)
│   │   ├── KPI-A7: Despacho oportuno                    (peso: 15%)
│   │   └── KPI-A8: Costo merma sobre ventas             (peso: 10%)
│   │
│   ├── Área B: Mantenimiento puntos fijos
│   │   ├── KPI-B1: Disponibilidad operacional           (peso: 20%) [BLOQUEANTE]
│   │   ├── KPI-B2: MTTR                                 (peso: 15%)
│   │   ├── KPI-B3: Cumplimiento PM                      (peso: 20%)
│   │   ├── KPI-B4: Vigencia certificaciones             (peso: 15%) [BLOQUEANTE]
│   │   ├── KPI-B5: Tasa correctivos / total             (peso: 15%)
│   │   └── KPI-B6: Incidentes ambientales/seguridad     (peso: 15%) [BLOQUEANTE]
│   │
│   └── Área C: Mantenimiento puntos móviles
│       ├── KPI-C1: Disponibilidad flota                 (peso: 20%) [BLOQUEANTE]
│       ├── KPI-C2: Cumplimiento PM flota                (peso: 15%)
│       ├── KPI-C3: Cumplimiento rutas/despachos          (peso: 15%)
│       ├── KPI-C4: MTTR flota                           (peso: 10%)
│       ├── KPI-C5: Rendimiento km/l                     (peso: 10%)
│       ├── KPI-C6: Vigencia documentación legal          (peso: 15%) [BLOQUEANTE]
│       └── KPI-C7: Accidentes/incidentes ruta            (peso: 15%) [BLOQUEANTE]
│
│ PASO 2 — Calcular puntaje por área
│   Para cada área:
│     puntaje_area = Σ (valor_kpi_i × peso_kpi_i)
│
│ PASO 3 — Evaluar bloqueantes
│   Para cada KPI marcado como BLOQUEANTE:
│     SI valor < umbral_minimo_bloqueante:
│       SEGÚN regla configurada:
│         ├── "anular"    → ICEO = 0 para el período
│         ├── "penalizar" → ICEO = ICEO × factor_penalizacion (ej: 0.5)
│         ├── "descontar" → ICEO = ICEO - puntos_descuento
│         └── "bloquear_incentivo" → ICEO se calcula normal pero
│                                     incentivo_habilitado = false
│
│ PASO 4 — Consolidar ICEO
│   ICEO = (puntaje_area_A × peso_A) + (puntaje_area_B × peso_B) + (puntaje_area_C × peso_C)
│
│   Pesos por defecto (configurables):
│     ├── Área A (Administración): 35%
│     ├── Área B (Puntos fijos):   35%
│     └── Área C (Puntos móviles): 30%
│
│   Aplicar efecto de bloqueantes (si corresponde)
│
│ PASO 5 — Clasificar
│   ├── < 70       → DEFICIENTE   (🔴)
│   ├── 70 – 84    → ACEPTABLE    (🟡)
│   ├── 85 – 94    → BUENO        (🟢)
│   └── >= 95      → EXCELENCIA   (⭐)
│
│ PASO 6 — Almacenar
│   INSERT INTO iceo_periodos:
│     ├── contrato_id
│     ├── periodo (mes/año)
│     ├── iceo_valor
│     ├── clasificacion
│     ├── puntaje_area_a, puntaje_area_b, puntaje_area_c
│     ├── bloqueantes_activados (JSON detalle)
│     ├── incentivo_habilitado
│     └── calculado_en = now()
│
│   INSERT INTO iceo_detalle (por cada KPI):
│     ├── iceo_periodo_id
│     ├── kpi_id
│     ├── valor_medido
│     ├── valor_ponderado
│     ├── es_bloqueante
│     ├── bloqueante_activado
│     └── impacto_descripcion
│
│ → Notificación a gerencia
│ → Registro en auditoria_eventos
```

### 4.5 Flujo D: Reportería Gerencial

```
GENERACIÓN DE REPORTE
│
├── Usuario selecciona tipo de reporte
├── Aplica filtros: período, faena, contrato, área
├── Sistema ejecuta consultas optimizadas (vistas materializadas)
├── Renderiza en pantalla con gráficos interactivos
├── Opciones de exportación:
│   ├── PDF → Edge Function genera PDF con layout corporativo
│   └── Excel → ExcelJS genera archivo con múltiples hojas
└── Se registra acceso al reporte en auditoría
```

---

## 5. REGLAS DE NEGOCIO CONSOLIDADAS

### 5.1 Reglas de OT (Eje Central)

| # | Regla | Tipo | Consecuencia |
|---|-------|------|--------------|
| R01 | Toda OT debe tener activo asociado | Validación | Bloquea creación sin activo |
| R02 | Toda OT debe tener responsable asignado antes de ejecutar | Validación | No permite pasar a 'en_ejecucion' |
| R03 | OT no puede cerrarse sin checklist completo | Validación | Bloquea cierre |
| R04 | OT no puede cerrarse sin evidencia mínima | Validación | Bloquea cierre. Mínimo: 1 foto |
| R05 | OT no puede cerrarse sin firma/validación | Validación | Bloquea cierre |
| R06 | OT no ejecutada DEBE tener causa registrada | Validación | Bloquea cambio a 'no_ejecutada' |
| R07 | Solo supervisor puede validar cierre definitivo | Autorización | RLS enforced |
| R08 | Materiales consumidos sin OT = operación denegada | Integridad | Trigger bloquea INSERT sin ot_id |
| R09 | OT cerrada no puede modificarse | Inmutabilidad | RLS + trigger bloquea UPDATE |
| R10 | Toda transición de estado se registra en auditoría | Auditoría | Trigger automático |

### 5.2 Reglas de Inventario

| # | Regla | Tipo | Consecuencia |
|---|-------|------|--------------|
| R11 | Salida de inventario requiere OT válida | Integridad | CHECK constraint + trigger |
| R12 | Salida requiere usuario autenticado | Seguridad | RLS enforced |
| R13 | Salida requiere producto, cantidad, costo, fecha, ubicación | Completitud | NOT NULL constraints |
| R14 | No se permite salida si stock < cantidad solicitada | Stock | Trigger valida antes de INSERT |
| R15 | Todo movimiento actualiza kardex automáticamente | Consistencia | Trigger after INSERT |
| R16 | Diferencia físico vs. sistema genera ajuste controlado | Trazabilidad | Requiere motivo + supervisor |
| R17 | Ajuste de inventario requiere autorización supervisor | Autorización | RLS + campo autorizador |
| R18 | Merma se valora al CPP vigente | Valorización | Función calcula al momento |
| R19 | Stock bajo mínimo genera alerta automática | Operacional | Trigger + notificación |
| R20 | Valorización se recalcula en cada movimiento | Financiero | Trigger recalcula CPP |

### 5.3 Reglas de Activos

| # | Regla | Tipo | Consecuencia |
|---|-------|------|--------------|
| R21 | Activo crítico sin plan PM activo = alerta | Operacional | Job diario verifica |
| R22 | Activo con certificación vencida = bloqueado operacionalmente | Cumplimiento | Flag en ficha, impacta KPI |
| R23 | Todo activo debe tener historial completo de OTs | Trazabilidad | FK en ordenes_trabajo |
| R24 | Cambio de estado de activo requiere motivo | Auditoría | Trigger registra |

### 5.4 Reglas de KPI e ICEO

| # | Regla | Tipo | Consecuencia |
|---|-------|------|--------------|
| R25 | KPI se calcula solo desde datos trazables del sistema | Integridad | No hay entrada manual de KPI |
| R26 | KPI bloqueante bajo umbral impacta ICEO según regla | Negocio | Configurable: anular/penalizar/descontar |
| R27 | ICEO se recalcula al: cerrar OT, registrar incidente, vencer certificación, incumplimiento bloqueante, cierre período | Automatización | Triggers + pg_cron |
| R28 | Cambio de ponderación de KPI requiere perfil administrador | Seguridad | RLS enforced |
| R29 | Histórico de ICEO es inmutable | Auditoría | No UPDATE/DELETE en iceo_periodos |

---

## 6. DETALLE DE KPI POR ÁREA

### 6.1 Área A — Administración de Combustibles y Lubricantes

| ID | KPI | Fórmula | Meta | Bloqueante | Peso | Frecuencia |
|----|-----|---------|------|------------|------|------------|
| A1 | Diferencia inventario combustibles | \|stock_fisico - stock_sistema\| / stock_sistema × 100 | ≤ 0.5% | No | 15% | Mensual |
| A2 | Diferencia inventario lubricantes | \|stock_fisico - stock_sistema\| / stock_sistema × 100 | ≤ 1.0% | No | 10% | Mensual |
| A3 | Exactitud inventario (IRA) | items_sin_diferencia / total_items_contados × 100 | ≥ 97% | No | 10% | Mensual |
| A4 | Cumplimiento normativo | certificaciones_vigentes / certificaciones_requeridas × 100 | 100% | SI | 15% | Mensual |
| A5 | Cumplimiento abastecimiento programado | abastecimientos_ejecutados / abastecimientos_programados × 100 | ≥ 95% | No | 15% | Semanal |
| A6 | Rotación de stock | costo_consumo_periodo / costo_inventario_promedio | > 4x/año | No | 10% | Mensual |
| A7 | Despacho oportuno | despachos_a_tiempo / total_despachos × 100 | ≥ 95% | No | 15% | Semanal |
| A8 | Costo merma sobre ventas | valor_mermas / valor_ventas_periodo × 100 | ≤ 0.3% | No | 10% | Mensual |

### 6.2 Área B — Mantenimiento Puntos Fijos

| ID | KPI | Fórmula | Meta | Bloqueante | Peso | Frecuencia |
|----|-----|---------|------|------------|------|------------|
| B1 | Disponibilidad operacional | (horas_operativas / horas_programadas) × 100 | ≥ 97% | SI | 20% | Mensual |
| B2 | MTTR | Σ tiempo_reparacion / cantidad_correctivos | ≤ 4 hrs | No | 15% | Mensual |
| B3 | Cumplimiento PM | OTs_PM_ejecutadas / OTs_PM_programadas × 100 | ≥ 95% | No | 20% | Mensual |
| B4 | Vigencia certificaciones | certificaciones_vigentes / total_requeridas × 100 | 100% | SI | 15% | Mensual |
| B5 | Tasa de correctivos | OTs_correctivas / (OTs_correctivas + OTs_preventivas) × 100 | ≤ 20% | No | 15% | Mensual |
| B6 | Incidentes ambientales/seguridad | Conteo incidentes del período | 0 | SI | 15% | Mensual |

### 6.3 Área C — Mantenimiento Puntos Móviles

| ID | KPI | Fórmula | Meta | Bloqueante | Peso | Frecuencia |
|----|-----|---------|------|------------|------|------------|
| C1 | Disponibilidad flota | unidades_operativas / total_flota × 100 | ≥ 90% | SI | 20% | Mensual |
| C2 | Cumplimiento PM flota | PM_ejecutados / PM_programados × 100 | ≥ 95% | No | 15% | Mensual |
| C3 | Cumplimiento rutas/despachos | rutas_completadas / rutas_programadas × 100 | ≥ 95% | No | 15% | Semanal |
| C4 | MTTR flota | Σ tiempo_reparacion / cantidad_correctivos | ≤ 8 hrs | No | 10% | Mensual |
| C5 | Rendimiento km/l | km_recorridos / litros_consumidos | ≥ meta_por_tipo | No | 10% | Mensual |
| C6 | Vigencia documentación legal | docs_vigentes / docs_requeridos × 100 | 100% | SI | 15% | Mensual |
| C7 | Accidentes/incidentes ruta | Conteo del período | 0 | SI | 15% | Mensual |

### 6.4 Tramos de Cumplimiento (ejemplo configurable)

| Cumplimiento | Puntaje |
|-------------|---------|
| ≥ 100% de meta | 100 pts |
| 95% – 99% | 90 pts |
| 90% – 94% | 75 pts |
| 85% – 89% | 60 pts |
| 80% – 84% | 40 pts |
| < 80% | 0 pts |

---

## 7. MODELO ICEO — EJEMPLO DE CÁLCULO

### Datos del período (Enero 2026, Faena "Minera Norte"):

```
ÁREA A — Administración (Peso global: 35%)
  A1 Dif. inv. combustibles:  0.3%  → meta 0.5% → cumple 100% → 100 pts × 15% = 15.0
  A2 Dif. inv. lubricantes:   0.8%  → meta 1.0% → cumple 100% → 100 pts × 10% = 10.0
  A3 IRA:                     98%   → meta 97%  → cumple 100% → 100 pts × 10% = 10.0
  A4 Cumpl. normativo:        100%  → BLOQ OK   →              100 pts × 15% = 15.0
  A5 Cumpl. abastecimiento:   92%   → meta 95%  → tramo 90-94 →  75 pts × 15% = 11.25
  A6 Rotación stock:          4.2x  → meta 4x   → cumple 100% → 100 pts × 10% = 10.0
  A7 Despacho oportuno:       96%   → meta 95%  → cumple 100% → 100 pts × 15% = 15.0
  A8 Costo merma/ventas:      0.2%  → meta 0.3% → cumple 100% → 100 pts × 10% = 10.0
  ─────────────────────────────────────────────
  Puntaje Área A = 96.25

ÁREA B — Puntos Fijos (Peso global: 35%)
  B1 Disponibilidad:          98%   → BLOQ OK   →              100 pts × 20% = 20.0
  B2 MTTR:                    3.5h  → meta 4h   → cumple 100% → 100 pts × 15% = 15.0
  B3 Cumplimiento PM:         88%   → meta 95%  → tramo 85-89 →  60 pts × 20% = 12.0
  B4 Vigencia certif:         100%  → BLOQ OK   →              100 pts × 15% = 15.0
  B5 Tasa correctivos:        25%   → meta 20%  → tramo 80-84 →  40 pts × 15% =  6.0
  B6 Incidentes amb/seg:      0     → BLOQ OK   →              100 pts × 15% = 15.0
  ─────────────────────────────────────────────
  Puntaje Área B = 83.0

ÁREA C — Puntos Móviles (Peso global: 30%)
  C1 Disponibilidad flota:    92%   → BLOQ OK   →              100 pts × 20% = 20.0
  C2 Cumplimiento PM flota:   97%   → meta 95%  → cumple 100% → 100 pts × 15% = 15.0
  C3 Cumpl. rutas:            98%   → meta 95%  → cumple 100% → 100 pts × 15% = 15.0
  C4 MTTR flota:              6h    → meta 8h   → cumple 100% → 100 pts × 10% = 10.0
  C5 Rendimiento km/l:        3.8   → meta 3.5  → cumple 100% → 100 pts × 10% = 10.0
  C6 Vigencia doc legal:      100%  → BLOQ OK   →              100 pts × 15% = 15.0
  C7 Accidentes ruta:         0     → BLOQ OK   →              100 pts × 15% = 15.0
  ─────────────────────────────────────────────
  Puntaje Área C = 100.0

ICEO = (96.25 × 0.35) + (83.0 × 0.35) + (100.0 × 0.30)
ICEO = 33.69 + 29.05 + 30.0
ICEO = 92.74 → BUENO 🟢

Bloqueantes: Todos OK → Sin penalización → Incentivo habilitado
```

### Escenario con bloqueante activado:

```
Si B6 (Incidentes amb/seg) = 1 incidente → BLOQUEANTE ACTIVADO

Según configuración:
  - Regla "penalizar": ICEO = 92.74 × 0.5 = 46.37 → DEFICIENTE 🔴
  - Regla "descontar": ICEO = 92.74 - 30 = 62.74 → DEFICIENTE 🔴
  - Regla "bloquear_incentivo": ICEO = 92.74 (se mantiene) pero incentivo = false
  - Regla "anular": ICEO = 0 → DEFICIENTE 🔴
```

---

## 8. ESTRUCTURA DE NAVEGACIÓN

### 8.1 Menú Principal por Perfil

```
ADMINISTRADOR / GERENCIA
├── Dashboard Gerencial
├── Contratos
│   ├── Lista de contratos
│   ├── Detalle contrato
│   ├── SLA y obligaciones
│   └── Desviaciones
├── Operaciones
│   ├── Órdenes de trabajo
│   ├── Calendario mantenimiento
│   ├── Mantenimiento preventivo
│   ├── Mantenimiento correctivo
│   └── Abastecimiento y lubricación
├── Activos
│   ├── Maestro de activos
│   ├── Fichas técnicas
│   ├── Semáforo operacional
│   └── Historial por activo
├── Inventario
│   ├── Dashboard inventario
│   ├── Productos
│   ├── Movimientos
│   ├── Kardex
│   ├── Valorización
│   ├── Conteos
│   └── Ajustes
├── Cumplimiento
│   ├── Certificaciones
│   ├── Documentos
│   ├── Vencimientos
│   └── Bloqueos
├── KPI e ICEO
│   ├── Dashboard KPI
│   ├── ICEO
│   ├── Tendencias
│   └── Drill-down
├── Reportes
├── Auditoría
└── Administración
    ├── Usuarios y roles
    ├── Parámetros
    ├── Configuración KPI
    └── Configuración ICEO

SUPERVISOR
├── Dashboard Supervisor
├── OTs (filtradas por faena)
├── Validar OTs
├── Calendario
├── Mi equipo
├── Activos (faena)
├── KPI de mi área
└── Reportes

TÉCNICO
├── Mis tareas del día
├── OT en ejecución
├── Historial mis OTs
└── Notificaciones

BODEGUERO
├── Dashboard Bodega
├── Recepción
├── Salida (con OT)
├── Conteo
├── Transferencia
├── Kardex
└── Alertas stock
```

---

## 9. INTEGRACIÓN PISTOLA DE INVENTARIO

### 9.1 Enfoque Técnico

La pistola de inventario industrial (Symbol, Honeywell, Zebra) opera de dos formas posibles:

**Opción A — Pistola con navegador integrado (recomendada)**
- La pistola tiene Android/Windows CE con navegador
- Accede directamente a la PWA de SICOM-ICEO
- El módulo de inventario detecta automáticamente lecturas del escáner (keyboard wedge)
- El campo de código de barras recibe el foco y la lectura se procesa como input de teclado

**Opción B — Pistola standalone + sincronización**
- La pistola trabaja desconectada con su software nativo
- Genera archivo de lote (CSV/TXT)
- Se importa al sistema vía interfaz de carga masiva
- El sistema valida y procesa cada línea

**Opción C — Cámara del dispositivo (fallback)**
- Para tablets/celulares sin pistola
- Librería html5-qrcode activa la cámara
- Lee códigos de barras EAN-13, Code 128, QR
- Misma interfaz, mismo flujo, distinto input

### 9.2 Flujo Técnico de Lectura

```javascript
// Interfaz unificada de captura
// El sistema detecta automáticamente si la entrada viene de:
// 1. Pistola (keyboard wedge — input rápido < 50ms entre caracteres)
// 2. Cámara (html5-qrcode — callback onScanSuccess)
// 3. Manual (teclado — input lento)

// En todos los casos, el resultado es un código que se busca en:
// productos.codigo_barras → para movimientos de inventario
// ordenes_trabajo.qr_code → para asociar OT
// activos.qr_code → para identificar activo
```

---

## 10. ESTRATEGIA DE DEPLOY EN NETLIFY + SUPABASE

```
AMBIENTES
├── Desarrollo
│   ├── Supabase: proyecto "sicom-dev"
│   ├── Netlify: branch "develop" → sicom-dev.netlify.app
│   └── Datos: seed de prueba
│
├── Staging
│   ├── Supabase: proyecto "sicom-staging"
│   ├── Netlify: branch "staging" → sicom-staging.netlify.app
│   └── Datos: copia anonimizada de producción
│
└── Producción
    ├── Supabase: proyecto "sicom-prod"
    ├── Netlify: branch "main" → sicom.empresa.cl (dominio custom)
    └── Datos: producción real

Variables de entorno (Netlify):
├── NEXT_PUBLIC_SUPABASE_URL
├── NEXT_PUBLIC_SUPABASE_ANON_KEY
├── SUPABASE_SERVICE_ROLE_KEY (solo edge functions)
└── NEXT_PUBLIC_APP_VERSION
```

---

## 11. ESTIMACIÓN DE COMPLEJIDAD POR MÓDULO

| Módulo | Tablas | Pantallas | Complejidad | Prioridad |
|--------|--------|-----------|-------------|-----------|
| M3. Órdenes de trabajo | 5 | 8 | Alta | P0 — Núcleo |
| M6. Inventario valorizado | 6 | 7 | Alta | P0 — Núcleo |
| M2. Activos | 3 | 5 | Media | P0 — Núcleo |
| M10. KPI | 4 | 4 | Alta | P1 — Crítico |
| M11. ICEO | 2 | 3 | Alta | P1 — Crítico |
| M4. Mantenimiento PM | 3 | 4 | Media | P1 — Crítico |
| M5. Mantenimiento CM | 2 | 3 | Media | P1 — Crítico |
| M7. Captura pistola | 1 | 3 | Media | P1 — Crítico |
| M1. Contratos | 3 | 4 | Media | P2 — Importante |
| M8. Abastecimiento | 3 | 4 | Media | P2 — Importante |
| M9. Documental | 2 | 3 | Media | P2 — Importante |
| M12. Dashboards | 0 | 4 | Media | P2 — Importante |
| M13. Reportería | 0 | 2 | Media | P3 — Complemento |
| M14. Auditoría | 1 | 2 | Baja | P3 — Complemento |
| M15. Administración | 2 | 5 | Baja | P0 — Núcleo |

**Total estimado: ~37 tablas principales, ~61 pantallas**

---

## 12. PRÓXIMOS PASOS (FASE 2)

Una vez aprobada esta Fase 1, la Fase 2 entregará:

1. **Esquema SQL completo** con todas las tablas, relaciones, índices y constraints
2. **Políticas RLS** por rol para cada tabla
3. **Funciones PostgreSQL** para lógica de negocio (cálculo KPI, ICEO, valorización)
4. **Triggers** para auditoría, validaciones y automatización
5. **Estrategia de Storage** (buckets, políticas, límites)
6. **Seed SQL** con datos de ejemplo del rubro minero
7. **Diagrama ER completo**

---

*Documento generado para SICOM-ICEO — Fase 1 — Propuesta Funcional Integral*
*Versión 1.0 — Marzo 2026*
