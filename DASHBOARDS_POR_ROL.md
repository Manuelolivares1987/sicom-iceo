# DASHBOARDS POR ROL — SICOM-ICEO

> **Última actualización:** 2026-05-02 — FASE 5.6
> **Estado:** Router + 5 dashboards prioritarios + Admin implementados. Resto documentado.

---

## 1. Arquitectura

```
DashboardPage (src/app/dashboard/page.tsx)
   │
   ▼
RoleDashboardRouter (src/components/dashboard/role-dashboard-router.tsx)
   │
   ├── perfil.rol === 'administrador'           →  AdminDashboard
   ├── perfil.rol ∈ {gerencia, subgerente, jefe_operaciones}    →  ExecutiveDashboard (existente)
   ├── perfil.rol ∈ {jefe_mantenimiento, supervisor, planificador} → MantenimientoDashboard
   ├── perfil.rol === 'tecnico_mantenimiento'   →  TecnicoDashboard
   ├── perfil.rol === 'bodeguero'               →  BodegueroDashboard
   ├── perfil.rol === 'operador_abastecimiento' →  AbastecimientoDashboard
   ├── perfil.rol === 'comercial'               →  CommercialDashboard (existente)
   ├── perfil.rol ∈ {auditor, prevencionista, rrhh, colaborador} → OperationsDashboard (provisional)
   └── (sin rol o desconocido)                  →  LegacyDashboard (fallback)
```

---

## 2. Matriz rol → dashboard implementado

| Rol | Dashboard | Estado | Archivo |
|---|---|---|---|
| **administrador** | AdminDashboard | ✅ FASE 5.6 | `roles/admin-dashboard.tsx` |
| **gerencia** | ExecutiveDashboard | ✅ Existente | `executive-dashboard.tsx` |
| **subgerente_operaciones** | ExecutiveDashboard | ✅ Existente | idem |
| **jefe_operaciones** | ExecutiveDashboard | ✅ Existente | idem |
| **jefe_mantenimiento** | MantenimientoDashboard | ✅ FASE 5.6 | `roles/mantenimiento-dashboard.tsx` |
| **supervisor** | MantenimientoDashboard | ✅ FASE 5.6 | idem |
| **planificador** | MantenimientoDashboard | ✅ FASE 5.6 | idem |
| **tecnico_mantenimiento** | TecnicoDashboard | ✅ FASE 5.6 | `roles/tecnico-dashboard.tsx` |
| **bodeguero** | BodegueroDashboard | ✅ FASE 5.6 | `roles/bodeguero-dashboard.tsx` |
| **operador_abastecimiento** | AbastecimientoDashboard | ✅ FASE 5.6 | `roles/abastecimiento-dashboard.tsx` |
| **comercial** | CommercialDashboard | ✅ Existente | `commercial-dashboard.tsx` |
| **auditor** | OperationsDashboard | ⚠️ Provisional | (pendiente AuditorDashboard) |
| **prevencionista** | OperationsDashboard | ⚠️ Provisional | (pendiente PrevencionistaDashboard) |
| **rrhh_incentivos** | OperationsDashboard | ⚠️ Provisional | (pendiente RRHHDashboard) |
| **colaborador** | OperationsDashboard | ⚠️ Provisional | OK por ser rol base |

---

## 3. Datos mostrados por dashboard implementado

### 3.1 AdminDashboard
- 6 KPIs: contratos, faenas, activos, OTs, productos, usuarios
- Alertas activas (top 5)
- Accesos rápidos: admin, auditoría, reportes, ICEO, cumplimiento, plantillas checklist
- Banner "Migraciones pendientes (52-57)" referencia a PLAN_OPERACION_STAGING_MIGRACIONES.md

### 3.2 MantenimientoDashboard (jefe / supervisor / planificador)
- 4 KPIs: OTs activas, OTs por cerrar, OTs vencidas, equipos en taller
- PMs vencidos vs próximos 15 días
- Alertas activas
- Accesos: OT, mantenimiento, flota, activos

### 3.3 TecnicoDashboard
- 3 KPIs: Mis OTs activas, por iniciar, total asignadas
- Lista de Mis OTs activas (top 5)
- Acciones rápidas: Mis OTs, equipos, inventario, scanner QR

### 3.4 BodegueroDashboard
- 4 KPIs: productos en stock, inventario valorizado, stock bajo, movimientos recientes
- Productos bajo mínimo (top 5)
- Movimientos recientes (top 6)
- Acciones: stock general, registrar salida, conteo, scanner

### 3.5 AbastecimientoDashboard
- 4 KPIs: stock total, capacidad, estanques bajo mínimo, consumo mes
- Estanques con barra de % llenado (top 4)
- Movimientos recientes (top 6)
- Acciones: combustible, registrar movimiento, varillaje, abastecimiento

---

## 4. Permisos aplicados

Cada dashboard:
1. **Reutiliza hooks existentes** (`useOTsStats`, `useFlotaVehicular`, `useStockBodega`, `useEstanques`, `useMantenimientosVencidos`, `useAlertasNoLeidas`, etc.).
2. **Sin queries pesadas nuevas** — el router solo cambia la UI; los datos vienen de hooks ya en producción.
3. **Sidebar respeta `usePermissions.canView()`** — los Quick Links solo muestran rutas que el rol puede ver. Si el rol no tiene permiso, el link aparece pero al click la página redirige (defensa adicional vía RLS).

### 4.1 Información sensible — visibilidad por rol

| Dato | administrador | gerencia | subgerente | jefe_mant | supervisor | tecnico | bodeguero | abastec. | prevencionista | comercial | auditor | rrhh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ICEO actual | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Stock valorizado total | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Costos OT | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Combustible valorizado | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Auditoría | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Incentivos | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**Defensa:** se cumple en 3 capas:
1. Sidebar oculta módulos sin permiso (`usePermissions`).
2. Dashboard no muestra KPIs sensibles a rol incorrecto (los hooks específicos no se invocan).
3. RLS Supabase debe filtrar a nivel de datos (FASE 5 audit pendiente).

---

## 5. Pendientes documentados (no implementados en FASE 5.6)

### 5.1 AuditorDashboard
**Datos esperados:**
- Últimos 20 eventos auditoría
- Cambios críticos (DELETE / UPDATE en tablas sensibles)
- Movimientos inventario y combustible del día
- Cambios de roles
- Exportes recientes
- Accesos: auditoría, reportes

**Hooks reutilizables:** `useAuditoria`, `useMovimientos`, `useMovimientosCombustible`.

### 5.2 PrevencionistaDashboard
**Datos esperados:**
- Certificaciones vencidas y por vencer (top 10)
- Equipos bloqueados normativamente
- No conformidades abiertas
- Alertas DS 298 / DS 160 / DS 132
- Accesos: cumplimiento, prevención

**Hooks reutilizables:** `useCertificacionesVencidas`, `useProximosVencimientos`, `usePrevencionResumen`, `useCertificacionesBloqueantes`.

### 5.3 RRHHIncentivosDashboard
**Datos esperados:**
- ICEO del período actual
- Bloqueantes activos
- Incentivos calculados del último período
- Personal con datos incompletos
- Accesos: KPI, ICEO, reportes

**Hooks reutilizables:** `useICEOPeriodo`, `useBloqueantesStatus`, `useIncentivos`, `useCalcularIncentivos`.

### 5.4 ComercialDashboard mejorado
**Mejoras posibles** (existe versión básica):
- Próximos vencimientos contrato
- Disponibilidad comercial real (`v_equipos_disponibles_para_arriendo`)
- Equipos pendientes de verificación ready-to-rent

---

## 6. Patrón seguido por todos los dashboards

```tsx
'use client'

import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useXxxHook } from '@/hooks/...'

export function XxxDashboard() {
  const { data, isLoading } = useXxxHook(...)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Título personalizado</h1>
        <p className="text-sm text-gray-500">Subtítulo del rol</p>
      </div>

      {/* 3-6 KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KPI ... />
      </div>

      {/* Sección "Acciones de hoy" / Alertas */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>...</Card>
        <Card>...</Card>
      </div>

      {/* Accesos rápidos */}
      <Card>
        <CardContent>
          <QuickLink ... />
        </CardContent>
      </Card>
    </div>
  )
}
```

**Reglas:**
- Loading state con `<Spinner />`.
- Empty state con `text-gray-400` y mensaje claro.
- Sin queries que carguen el sistema entero (limit ≤ 10 registros visibles).
- Reutilizar hooks existentes — no crear nuevos servicios.
- Respetar permisos del rol.

---

## 7. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

### Pruebas manuales sugeridas

| Login con | Esperado |
|---|---|
| `admin@pillado.cl` | AdminDashboard con KPIs sistema, banner migraciones |
| `gerencia@pillado.cl` | ExecutiveDashboard (Control Tower) |
| `bodegacoq@pillado.cl` (Gustavo) | BodegueroDashboard con stock, movimientos, accesos inventario |
| `planificador@pillado.cl` (Eduardo) | MantenimientoDashboard con OTs, PMs, flota |
| (cualquier técnico) | TecnicoDashboard con Mis OTs |

---

## 8. Roadmap

| Sprint | Tarea |
|---|---|
| Próximo | Implementar AuditorDashboard, PrevencionistaDashboard, RRHHDashboard |
| Después de aplicar mig 55-57 | Enriquecer BodegueroDashboard con OC pendientes + stock FIFO valorizado |
| Después de aplicar mig 55-57 | Enriquecer AbastecimientoDashboard con valor stock combustible + despachos pendientes |
| Mejora UX | Personalizar saludo: "Buenos días, {nombre}" |
| Mejora UX | Botón "Cambiar a vista clásica" para volver a LegacyDashboard si el usuario prefiere |
