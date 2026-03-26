# ARQUITECTURA OBJETIVO — Plan de Refactor Concreto

## Estado actual vs. objetivo

```
ACTUAL (54 archivos)                    OBJETIVO (~95 archivos)
src/                                    src/
├── app/        (19 pages)              ├── app/         (19 pages, más delgadas)
├── components/ (13 componentes)        ├── components/  (18+ componentes)
├── contexts/   (2 contextos)           ├── contexts/    (3 contextos)
├── hooks/      (8 hooks)               ├── hooks/       (10 hooks)
├── lib/                                ├── lib/
│   ├── services/ (9 servicios)         │   ├── repositories/ (9 repos, solo Supabase)
│   ├── supabase.ts                     │   ├── supabase.ts
│   └── utils.ts                        │   └── utils.ts
└── types/      (1 archivo)             ├── domain/      (NUEVO: reglas de negocio)
                                        │   ├── ot/
                                        │   ├── inventario/
                                        │   ├── kpi/
                                        │   └── activos/
                                        ├── validations/ (NUEVO: schemas Zod)
                                        └── types/       (3+ archivos, tipado fuerte)
```

---

## CAMBIOS CONCRETOS POR ARCHIVO

### ═══════════════════════════════════════════
### CAPA 1: TYPES (tipar bien todo primero)
### ═══════════════════════════════════════════

#### `src/types/database.ts` → MANTENER + PARTIR EN 3

El archivo actual (332 líneas) mezcla tipos de Supabase con tipos de dominio.

**CREAR:**

| Archivo nuevo | Qué contiene | De dónde sale |
|--------------|-------------|---------------|
| `src/types/enums.ts` | Todos los enums (TipoOT, EstadoOT, etc.) | Extraer de database.ts líneas 89-105 |
| `src/types/entities.ts` | Interfaces de negocio (OrdenTrabajo, Activo, etc.) | Extraer de database.ts líneas 107-332 |
| `src/types/database.ts` | Solo el type Database de Supabase | Mantener líneas 1-87, limpiar |

**Motivo:** Los enums se usan en validaciones, UI y domain logic. Las entidades se usan en todo el sistema. Tenerlos separados elimina imports circulares y facilita testing.

---

### ═══════════════════════════════════════════
### CAPA 2: DOMAIN (lógica de negocio pura)
### ═══════════════════════════════════════════

**Problema actual:** La lógica de negocio está dispersa entre services (ordenes-trabajo.ts líneas 96-148) y pages (OT detail 935 líneas). No hay un lugar canónico para las reglas.

**CREAR** el directorio `src/domain/` con estos archivos:

#### `src/domain/ot/transitions.ts` — NUEVO
```
Contenido:
- VALID_TRANSITIONS: Record<EstadoOT, EstadoOT[]>
  Ejemplo: { creada: ['asignada','cancelada'], asignada: ['en_ejecucion','cancelada'], ... }
- canTransition(from: EstadoOT, to: EstadoOT): boolean
- getAvailableTransitions(estado: EstadoOT): EstadoOT[]
- requiresCausa(estado: EstadoOT): boolean  → true si es 'no_ejecutada'
- requiresEvidencia(estado: EstadoOT): boolean → true si es 'ejecutada_ok'

Fuente: Extraer lógica implícita de services/ordenes-trabajo.ts (iniciarOT, pausarOT, etc.)
         y de app/dashboard/ordenes-trabajo/[id]/page.tsx (botones condicionales)
```

#### `src/domain/ot/validation.ts` — NUEVO
```
Contenido:
- validateCierreOT(ot, checklist[], evidencias[]): { valid: boolean, errors: string[] }
  Reglas: checklist completo, evidencia mínima, firma, timestamps
- validateNoEjecucion(causa, detalle): { valid, errors }
- validateCrearOT(data): { valid, errors }

Fuente: Reglas que hoy están en triggers SQL pero NO se validan en frontend
```

#### `src/domain/inventario/rules.ts` — NUEVO
```
Contenido:
- TIPOS_REQUIEREN_OT: TipoMovimiento[] = ['salida', 'merma']
- TIPOS_REQUIEREN_AUTORIZACION: TipoMovimiento[] = ['ajuste_negativo', 'merma']
- validateSalida(data): { valid, errors }
  → OT obligatoria, cantidad > 0, stock suficiente, usuario autenticado
- validateEntrada(data): { valid, errors }
  → documento referencia, cantidad > 0
- validateAjuste(data): { valid, errors }
  → motivo obligatorio, autorización para negativos
- canRetirarMaterial(estadoOT: EstadoOT): boolean
  → Solo 'en_ejecucion' o 'asignada'

Fuente: Extraer de services/inventario.ts líneas 148-193 (validaciones inline)
```

#### `src/domain/kpi/calculator.ts` — NUEVO
```
Contenido:
- getICEOClassification(valor: number): ClasificacionICEO
- getICEOColor(valor: number): string
- getICEOLabel(valor: number): string
- calculateAreaScore(mediciones: MedicionKPI[]): number
- evaluateBloqueante(kpi: KPIDefinicion, medicion: MedicionKPI): BloqueanteResult

Fuente: Extraer de lib/utils.ts (getICEOColor, getICEOLabel, getICEOBgColor)
         + nueva lógica de evaluación que hoy no existe en frontend
```

#### `src/domain/activos/status.ts` — NUEVO
```
Contenido:
- isOperativo(activo: Activo): boolean
- requiresMantenimiento(activo: Activo, planes: PlanMantenimiento[]): boolean
- getCertificacionesVencidas(certs: Certificacion[]): Certificacion[]
- getSemaforoOperacional(activo: Activo, certs: Certificacion[]): 'verde'|'amarillo'|'rojo'

Fuente: Lógica que hoy está dispersa en pages y utils
```

---

### ═══════════════════════════════════════════
### CAPA 3: SERVICES → REPOSITORIES (renombrar + limpiar)
### ═══════════════════════════════════════════

**Cambio clave:** Renombrar `lib/services/` a `lib/repositories/`. Los "services" actuales son realmente repositorios de datos (solo hacen queries a Supabase). La lógica de negocio se mueve a `domain/`.

#### `src/lib/services/` → `src/lib/repositories/` — RENOMBRAR

| Archivo actual | Archivo nuevo | Cambios |
|---------------|--------------|---------|
| `services/ordenes-trabajo.ts` (306 líneas) | `repositories/ordenes-trabajo.ts` (~200 líneas) | **Eliminar** validaciones de negocio (mover a domain/ot/). Dejar solo CRUD + queries Supabase. Eliminar iniciarOT/pausarOT/etc (se reescriben como operaciones en domain). |
| `services/inventario.ts` (388 líneas) | `repositories/inventario.ts` (~250 líneas) | **Eliminar** validación de stock y OT (mover a domain/inventario/). Dejar solo queries. |
| `services/kpi-iceo.ts` | `repositories/kpi-iceo.ts` | Sin cambios mayores. Corregir alias de query bloqueantes. |
| `services/activos.ts` | `repositories/activos.ts` | Sin cambios. Remover `as any`. |
| `services/contratos.ts` | `repositories/contratos.ts` | Sin cambios. |
| `services/faenas.ts` | `repositories/faenas.ts` | Sin cambios. |
| `services/certificaciones.ts` | `repositories/certificaciones.ts` | Sin cambios. |
| `services/alertas.ts` | `repositories/alertas.ts` | Sin cambios. |
| `services/auditoria.ts` | `repositories/auditoria.ts` | Sin cambios. |

**CREAR** services que orquestan domain + repository:

#### `src/lib/services/ot-service.ts` — NUEVO
```
Contenido:
- iniciarOT(id): valida transición (domain) → actualiza (repo) → invalida cache
- pausarOT(id): valida transición → actualiza → invalida
- finalizarOT(id, obs?): valida cierre (domain) → actualiza → invalida
- noEjecutarOT(id, causa, detalle): valida causa → actualiza → invalida
- cerrarSupervisor(id, obs?): valida → actualiza → invalida

Cada función:
1. Consulta estado actual via repo
2. Valida transición via domain/ot/transitions
3. Valida reglas via domain/ot/validation
4. Ejecuta update via repo
5. Retorna resultado tipado

Fuente: Refactor de services/ordenes-trabajo.ts (funciones de transición)
         + domain/ot/ (validaciones)
```

#### `src/lib/services/inventario-service.ts` — NUEVO
```
Contenido:
- registrarSalida(data): valida reglas (domain) → verifica stock → inserta → retorna
- registrarEntrada(data): valida → inserta → retorna
- registrarAjuste(data): valida autorización → inserta → retorna

Cada función:
1. Valida via domain/inventario/rules
2. Consulta stock via repo
3. Ejecuta insert via repo
4. Retorna resultado

Fuente: Refactor de services/inventario.ts (funciones de movimiento)
```

---

### ═══════════════════════════════════════════
### CAPA 4: VALIDATIONS (schemas Zod)
### ═══════════════════════════════════════════

**CREAR** `src/validations/` para schemas de formularios:

#### `src/validations/ot.ts` — NUEVO
```
- crearOTSchema: z.object({ tipo, contrato_id, faena_id, activo_id, prioridad, ... })
- noEjecucionSchema: z.object({ causa: z.enum([...]).required, detalle: z.string().optional })
- finalizarOTSchema: z.object({ observaciones: z.string().optional })
```

#### `src/validations/inventario.ts` — NUEVO
```
- salidaSchema: z.object({ bodega_id, producto_id, cantidad: z.number().positive(), ot_id: z.string().uuid(), ... })
- entradaSchema: z.object({ ..., documento_referencia: z.string().min(1), ... })
- ajusteSchema: z.object({ ..., motivo: z.string().min(1), ... })
```

#### `src/validations/activo.ts` — NUEVO
```
- crearActivoSchema
- actualizarActivoSchema
```

**Motivo:** Hoy los formularios validan inline con `if (!campo)`. Con Zod + react-hook-form se centraliza y se comparte entre frontend y service.

---

### ═══════════════════════════════════════════
### CAPA 5: HOOKS (ajustes menores)
### ═══════════════════════════════════════════

| Archivo actual | Cambio | Detalle |
|---------------|--------|---------|
| `hooks/use-ordenes-trabajo.ts` | **MODIFICAR** | Mutations deben llamar a `ot-service.ts` en vez de `repositories/` directo. Remover `as any` en useCreateOT. |
| `hooks/use-inventario.ts` | **MODIFICAR** | Mutations llaman a `inventario-service.ts`. Corregir tipo de useRegistrarSalida (agregar usuario_id desde auth). |
| `hooks/use-kpi-iceo.ts` | **MODIFICAR** | Corregir parámetros opcionales. |
| `hooks/use-activos.ts` | SIN CAMBIOS | OK |
| `hooks/use-alertas.ts` | SIN CAMBIOS | OK (ya corregido) |
| `hooks/use-certificaciones.ts` | SIN CAMBIOS | OK |
| `hooks/use-require-auth.ts` | SIN CAMBIOS | OK |
| `hooks/use-scanner.ts` | **MODIFICAR** | Limpiar wedgeTimerRef en cleanup. |

**CREAR:**

#### `hooks/use-toast.ts` — NUEVO
```
Sistema de notificaciones tipo toast.
- useToast(): { toast(msg, type), dismiss(id) }
- Reemplaza todos los setTimeout para feedback en pages
```

#### `hooks/use-permissions.ts` — NUEVO
```
- usePermissions(): { canCreate(module), canEdit(module), canDelete(module), canApprove() }
- Lee rol desde useAuth().perfil.rol
- Determina permisos por módulo
- Se usa en pages para mostrar/ocultar botones
```

---

### ═══════════════════════════════════════════
### CAPA 6: COMPONENTS (nuevos componentes)
### ═══════════════════════════════════════════

**Los 13 componentes actuales se mantienen.** Agregar:

| Componente nuevo | Ruta | Propósito |
|-----------------|------|-----------|
| `components/ui/toast.tsx` | NUEVO | Toasts de feedback (éxito, error, warning) |
| `components/ui/confirm-dialog.tsx` | NUEVO | Diálogo de confirmación reutilizable (reemplaza confirms inline en OT detail) |
| `components/ui/empty-state.tsx` | NUEVO | Estado vacío reutilizable ("No hay datos", "Sin resultados") |
| `components/ui/stat-card.tsx` | NUEVO | Tarjeta de estadística (extraer del dashboard, se repite 4 veces) |
| `components/ui/data-table.tsx` | NUEVO | Tabla con filtros, paginación y sort integrados |

**MODIFICAR:**

| Componente | Cambio |
|-----------|--------|
| `components/layout/header.tsx` | Reemplazar "Juan Pérez" con `useAuth().perfil`. Implementar logout. Conectar notificaciones a `useConteoNoLeidas`. |
| `components/layout/sidebar.tsx` | Corregir href `/dashboard/ordenes` → `/dashboard/ordenes-trabajo`. Reemplazar usuario hardcodeado. |

---

### ═══════════════════════════════════════════
### CAPA 7: PAGES (adelgazar, extraer lógica)
### ═══════════════════════════════════════════

**Principio:** Las pages solo deben orquestar componentes y hooks. No deben tener lógica de negocio.

#### `app/dashboard/ordenes-trabajo/[id]/page.tsx` (935 líneas) — PARTIR

Este archivo es el más problemático. 935 líneas con UI, lógica de transiciones, modals, tabs todo junto.

**CREAR componentes extraídos:**

| Componente nuevo | Líneas que absorbe | Descripción |
|-----------------|-------------------|-------------|
| `components/ot/ot-header.tsx` | ~50 líneas | Folio, badges de estado/tipo/prioridad, info grid |
| `components/ot/ot-checklist-tab.tsx` | ~80 líneas | Tab de checklist con ítems, OK/NO OK, fotos |
| `components/ot/ot-evidencias-tab.tsx` | ~100 líneas | Tab de evidencias con upload y grid |
| `components/ot/ot-materiales-tab.tsx` | ~80 líneas | Tab de materiales con tabla y totales |
| `components/ot/ot-historial-tab.tsx` | ~50 líneas | Tab de historial/timeline |
| `components/ot/ot-actions.tsx` | ~150 líneas | Barra de acciones + modals de confirmación |

**Resultado:** `[id]/page.tsx` baja de 935 → ~150 líneas (solo compose + hooks).

#### `app/dashboard/page.tsx` (659 líneas) — PARTIR

**CREAR componentes extraídos:**

| Componente nuevo | Descripción |
|-----------------|-------------|
| `components/dashboard/iceo-summary.tsx` | Gauge ICEO + delta + clasificación |
| `components/dashboard/ots-stats.tsx` | Card OTs activas + pie chart |
| `components/dashboard/kpi-areas.tsx` | 3 cards de áreas KPI |
| `components/dashboard/alertas-panel.tsx` | Lista de alertas/vencimientos |

**Resultado:** `page.tsx` baja de 659 → ~120 líneas.

#### `app/dashboard/inventario/salida/page.tsx` (521 líneas) — PARTIR

**CREAR:**

| Componente nuevo | Descripción |
|-----------------|-------------|
| `components/inventario/ot-selector.tsx` | Buscador de OT con validación obligatoria |
| `components/inventario/producto-selector.tsx` | Buscador por código/barcode con info de stock |
| `components/inventario/salida-form.tsx` | Formulario completo de salida |

**Resultado:** `salida/page.tsx` baja de 521 → ~80 líneas.

---

### ═══════════════════════════════════════════
### CAPA 8: CONTEXTS (1 nuevo)
### ═══════════════════════════════════════════

#### `src/contexts/toast-context.tsx` — NUEVO
```
Proveedor global de toasts.
Agrega al layout.tsx como wrapper.
Todos los componentes pueden llamar useToast().
```

Los 2 contextos existentes (`auth-context.tsx`, `query-provider.tsx`) se **mantienen sin cambios**.

---

### ═══════════════════════════════════════════
### CAPA 9: LIB/UTILS (limpiar)
### ═══════════════════════════════════════════

#### `src/lib/utils.ts` — MODIFICAR

**Mover a domain:**
- `getICEOColor()`, `getICEOBgColor()`, `getICEOLabel()` → `domain/kpi/calculator.ts`

**Mantener en utils** (son helpers de presentación genéricos):
- `cn()`, `formatCLP()`, `formatPercent()`, `formatDate()`, `formatDateTime()`
- `getEstadoOTColor()`, `getEstadoOTLabel()`, `getSemaforoColor()`, `getCriticidadColor()`

---

## RESUMEN DE CAMBIOS

### Archivos a CREAR: 22

```
src/types/enums.ts
src/types/entities.ts
src/domain/ot/transitions.ts
src/domain/ot/validation.ts
src/domain/inventario/rules.ts
src/domain/kpi/calculator.ts
src/domain/activos/status.ts
src/lib/services/ot-service.ts
src/lib/services/inventario-service.ts
src/validations/ot.ts
src/validations/inventario.ts
src/validations/activo.ts
src/hooks/use-toast.ts
src/hooks/use-permissions.ts
src/contexts/toast-context.tsx
src/components/ui/toast.tsx
src/components/ui/confirm-dialog.tsx
src/components/ui/empty-state.tsx
src/components/ui/stat-card.tsx
src/components/ui/data-table.tsx
src/components/ot/ot-header.tsx
src/components/ot/ot-checklist-tab.tsx
src/components/ot/ot-evidencias-tab.tsx
src/components/ot/ot-materiales-tab.tsx
src/components/ot/ot-historial-tab.tsx
src/components/ot/ot-actions.tsx
src/components/dashboard/iceo-summary.tsx
src/components/dashboard/ots-stats.tsx
src/components/dashboard/kpi-areas.tsx
src/components/dashboard/alertas-panel.tsx
src/components/inventario/ot-selector.tsx
src/components/inventario/producto-selector.tsx
src/components/inventario/salida-form.tsx
```

### Archivos a RENOMBRAR: 9

```
src/lib/services/ordenes-trabajo.ts  → src/lib/repositories/ordenes-trabajo.ts
src/lib/services/inventario.ts       → src/lib/repositories/inventario.ts
src/lib/services/kpi-iceo.ts         → src/lib/repositories/kpi-iceo.ts
src/lib/services/activos.ts          → src/lib/repositories/activos.ts
src/lib/services/contratos.ts        → src/lib/repositories/contratos.ts
src/lib/services/faenas.ts           → src/lib/repositories/faenas.ts
src/lib/services/certificaciones.ts  → src/lib/repositories/certificaciones.ts
src/lib/services/alertas.ts          → src/lib/repositories/alertas.ts
src/lib/services/auditoria.ts        → src/lib/repositories/auditoria.ts
```

### Archivos a MODIFICAR: 12

```
src/types/database.ts          (reducir a solo tipo Database)
src/lib/utils.ts               (mover funciones ICEO a domain)
src/hooks/use-ordenes-trabajo.ts  (usar ot-service en vez de repo directo)
src/hooks/use-inventario.ts       (usar inventario-service)
src/hooks/use-kpi-iceo.ts         (corregir params)
src/hooks/use-scanner.ts          (limpiar timer)
src/components/layout/header.tsx   (usuario real, logout, notificaciones)
src/components/layout/sidebar.tsx  (corregir link, usuario real)
src/app/dashboard/page.tsx         (extraer componentes, adelgazar)
src/app/dashboard/ordenes-trabajo/[id]/page.tsx  (extraer tabs y acciones)
src/app/dashboard/inventario/salida/page.tsx     (extraer selectores)
src/app/layout.tsx                 (agregar ToastProvider)
```

### Archivos a ELIMINAR: 0

No se elimina ningún archivo. Todo se refactoriza o se extrae.

---

## ORDEN DE EJECUCIÓN

```
Sprint 1 (Foundation):
  1. Crear types/enums.ts y types/entities.ts
  2. Crear domain/ot/transitions.ts
  3. Crear domain/ot/validation.ts
  4. Crear domain/inventario/rules.ts
  5. Corregir header.tsx y sidebar.tsx (usuario real, logout, link)
  → Resultado: reglas de negocio centralizadas, layout funcional

Sprint 2 (Repository Pattern):
  6. Renombrar services/ → repositories/
  7. Crear services/ot-service.ts
  8. Crear services/inventario-service.ts
  9. Actualizar hooks para usar services
  → Resultado: separación limpia de capas

Sprint 3 (UI Components):
  10. Crear toast system (context + hook + component)
  11. Crear confirm-dialog, empty-state, stat-card
  12. Extraer componentes de OT detail (6 componentes)
  13. Extraer componentes de dashboard (4 componentes)
  → Resultado: pages adelgazadas, componentes reutilizables

Sprint 4 (Validations + Polish):
  14. Crear validations/ con schemas Zod
  15. Integrar Zod en formularios existentes
  16. Crear hooks/use-permissions.ts
  17. Aplicar permisos en UI
  → Resultado: validación robusta, permisos visibles
```

---

*Arquitectura objetivo para SICOM-ICEO*
*Basada en auditoría del repositorio actual — Marzo 2026*
