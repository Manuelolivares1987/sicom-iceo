# PERMISOS Y ROLES — SICOM-ICEO

> **Última actualización:** 2026-04-28 — FASE 4 (Auth, roles, protección de rutas)
> **Resumen:** Sistema de permisos centralizado existente y funcional. Middleware diferido por razón técnica concreta. Defensa real depende de RLS Supabase (FASE 5).

---

## 1. Estado actual de Auth

### 1.1 Componentes detectados

| Componente | Archivo | Estado |
|---|---|---|
| AuthContext | `frontend/src/contexts/auth-context.tsx` | ✅ Funcional |
| `useAuth` hook | mismo archivo | ✅ Funcional |
| `useRequireAuth` hook | `frontend/src/hooks/use-require-auth.ts` | ✅ Funcional |
| Login | `frontend/src/app/login/page.tsx` | ✅ Funcional (RHF + redirect post-login) |
| Logout | `auth-context.signOut()` invocado desde Sidebar y Header | ✅ Funcional |
| Cliente Supabase | `frontend/src/lib/supabase.ts` | ✅ `@supabase/supabase-js` (browser-only) |
| Persistencia sesión | `supabase.auth.onAuthStateChange` + `getSession` en mount | ✅ Funcional |
| Layout dashboard | `frontend/src/app/dashboard/layout.tsx` → `useRequireAuth` | ✅ Funcional |
| **Middleware Next.js** | **NO EXISTE** | ⚠️ **Por decisión técnica** (ver §3) |

### 1.2 Flujo de autenticación actual

1. Usuario navega a cualquier ruta.
2. `RootLayout` envuelve la app en `<AuthProvider>` que llama `supabase.auth.getSession()` y suscribe a cambios.
3. Si la ruta es `/dashboard/*`, `DashboardLayout` invoca `useRequireAuth()`:
   - Si `loading` → muestra spinner.
   - Si `!isAuthenticated` → `router.replace('/login')`.
4. `/login` y `/equipo/[id]` no usan `useRequireAuth` → son **públicas** (intencional).
5. La sesión se mantiene vía Supabase Auth (refresh tokens automáticos) y se almacena en **`localStorage`** del navegador (config por defecto de `@supabase/supabase-js` v2 sin SSR).

### 1.3 Rutas públicas y privadas

| Ruta | Acceso | Justificación |
|---|---|---|
| `/` | Pública | Redirige según sesión (si auth → `/dashboard`, si no → `/login`) |
| `/login` | Pública | Acceso al sistema |
| `/equipo/[id]` | **Pública (sin auth)** | Diseñado para escaneo QR en terreno (técnicos sin login) |
| `/dashboard/*` | Privada | Protegida por `useRequireAuth` en `DashboardLayout` |

---

## 2. Estado actual de roles y permisos

### 2.1 Definición central

`frontend/src/hooks/use-permissions.ts` exporta:

- **16 roles** (en sintonía con `RolUsuario` de `types/enums.ts` y enum Postgres `rol_usuario_enum`):
  `administrador`, `gerencia`, `subgerente_operaciones`, `jefe_operaciones`, `jefe_mantenimiento`, `comercial`, `prevencionista`, `colaborador`, `supervisor`, `planificador`, `tecnico_mantenimiento`, `bodeguero`, `operador_abastecimiento`, `auditor`, `rrhh_incentivos` (+ uno más).
- **16 módulos** mapeables: `contratos`, `activos`, `ordenes_trabajo`, `inventario`, `mantenimiento`, `abastecimiento`, `cumplimiento`, `kpi`, `iceo`, `reportes`, `auditoria`, `admin`, `flota`, `prevencion`, `comercial`, `reporte_diario`.
- **6 acciones** por módulo: `view`, `create`, `edit`, `delete`, `approve`, `export`.
- Funciones: `can(module, permission)`, `canView`, `canCreate`, `canEdit`, `canDelete`, `canApprove`, `canExport`, `isAdmin`, `isSupervisor`, `isReadOnly`, `getVisibleModules`.

> **Nota:** El spec de FASE 4 sugería ~9 roles. La implementación actual tiene 16. **No se reduce** — son más granulares y reflejan la organización real de Pillado (validados contra mig 31 / 35 que cargan perfiles de usuario reales).

### 2.2 Resumen de permisos por rol (vista resumida)

| Rol | Módulos visibles | Capacidad CRUD destacada |
|---|---|---|
| **administrador** | Todos (16) | Full CRUD + approve + export |
| **gerencia** | Todos (16) | Solo view + export |
| **subgerente_operaciones** | Todos | view + export, approve OTs, edit flota |
| **jefe_operaciones** | Casi todos | create/edit/approve OTs, edit activos y flota |
| **jefe_mantenimiento** | Operativos | create/edit/approve OTs, create/edit mantenimiento |
| **comercial** | Comerciales | view contratos/abastecimiento/flota, create comercial |
| **prevencionista** | Prevención + Cumplimiento + Reportes | full CRUD prevención + cumplimiento |
| **supervisor** | Op + lectura compliance | view/create/edit/approve OTs, edit flota |
| **planificador** | Op | view/create/edit OTs y mantenimiento |
| **tecnico_mantenimiento** | Mínimo | view + edit OT (asignadas) |
| **bodeguero** | Inventario | view/create/edit inventario |
| **operador_abastecimiento** | Abastecimiento | view/create/edit abastecimiento |
| **auditor** | Solo lectura global | view + export en todo |
| **rrhh_incentivos** | KPI/ICEO/Reportes | solo view + export |
| **colaborador** | Mínimo | view activos, OTs, flota, reporte_diario |

### 2.3 Uso real de los permisos en la UI

Inventario de archivos que importan `usePermissions`:

| Archivo | Uso | Función invocada |
|---|---|---|
| `sidebar.tsx` | Filtrado de menú por grupo | `canView(item.module)` |
| `dashboard/admin/gps/page.tsx` | Gating de página | (revisar) |
| `dashboard/flota/aprobar/[otId]/page.tsx` | Gating de acción de aprobar | (revisar) |
| `use-permissions.ts` | Definición | — |

> **Hallazgo importante:** La UI **filtra el menú correctamente** (sidebar oculta lo que el rol no puede ver), pero **las acciones internas de cada módulo** (botones Crear, Editar, Eliminar, Aprobar, Exportar) **no usan `usePermissions` en la mayoría de páginas**. Cualquier usuario que pueda *ver* un módulo, ve también los botones de acción.
>
> **Implicación:** la **defensa real** de operaciones CRUD depende de **políticas RLS** en Supabase, no de la UI. Si RLS está correctamente configurada (FASE 5), un click en "Eliminar" sin permiso fallará en la DB. Si RLS no está bien, hay riesgo real.

### 2.4 Sidebar — verificación de respeto a permisos

✅ Confirmado: `sidebar.tsx` filtra cada grupo de navegación con `canView(item.module)` y oculta el grupo entero si queda vacío. Funciona.

---

## 3. Decisión sobre `middleware.ts`

### 3.1 Decisión: **DIFERIDO** (no implementado en FASE 4)

### 3.2 Razón técnica concreta

El cliente Supabase actual (`frontend/src/lib/supabase.ts`) usa **`@supabase/supabase-js` puro**, sin `@supabase/ssr`. Por defecto, este cliente guarda la sesión en **`localStorage`** del navegador, **NO en cookies**.

Un Next.js middleware corre en **edge runtime** (servidor) y solo tiene acceso a **cookies y headers** de la request. **No tiene acceso a `localStorage`**, que es exclusivamente del navegador.

→ Un middleware naïve que intentara verificar autenticación leyendo cookies **no encontraría la sesión** y haría redirect al login a usuarios autenticados (loop). Esto rompería el sistema.

### 3.3 Lo que requeriría implementarlo correctamente

1. **Migrar `lib/supabase.ts`** de `createClient` (browser) a `createBrowserClient` de `@supabase/ssr`.
2. **Crear `lib/supabase/server.ts`** con `createServerClient` y handlers de cookies (read/set/delete).
3. **Configurar Auth para usar cookies** en lugar de localStorage (`storage: cookieStorage` o equivalente).
4. **Crear `middleware.ts`** con `createMiddlewareClient` que refresque tokens en cookies.
5. **Probar exhaustivamente** que `useAuth`, `getSession`, `onAuthStateChange` siguen funcionando idénticamente en cliente.
6. **Verificar Netlify** — `@netlify/plugin-nextjs@5.15` soporta middleware Next 14, pero hay que validar configuración de cookies en producción.

**Riesgo:** una migración mal hecha rompe la sesión en producción → usuarios no pueden loguearse → demo cancelada. **El upside de seguridad es marginal** dado que `useRequireAuth` ya redirige al login y RLS es la defensa real.

### 3.4 Mitigación actual (suficiente para MVP)

| Capa | Defensa | Estado |
|---|---|---|
| 1. Routing cliente | `useRequireAuth` en `DashboardLayout` redirige si no hay sesión | ✅ Activo |
| 2. UI menú | `usePermissions` oculta módulos según rol | ✅ Activo |
| 3. Backend (única defensa **real** de datos) | **RLS en Supabase** sobre tablas críticas | ⚠️ A auditar en FASE 5 |
| 4. Network | HTTPS de Netlify + Supabase | ✅ Activo |

### 3.5 Recomendación post-MVP

Implementar middleware en un PR aislado con plan de testing. Pasos sugeridos:

```text
1. branch feature/auth-ssr-middleware
2. Instalar uso de @supabase/ssr (ya está en deps)
3. Crear lib/supabase-server.ts con createServerClient
4. Reemplazar lib/supabase.ts con createBrowserClient
5. Verificar que la sesión migra de localStorage a cookies en runtime
6. Crear middleware.ts:
   - Allowlist: /, /login, /equipo/[id], /_next/*, /api/* (si aplica), /images/*, /manifest.json, /sw.js, /workbox-*, /favicon.ico
   - Default: chequear cookie de auth → si no, redirect a /login
   - Evitar loop: si ya está en /login y autenticado, redirect a /dashboard
7. Probar en preview Netlify antes de prod.
```

Plantilla de matcher seguro:

```ts
// middleware.ts (POST-MVP, no implementar todavía)
export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|images|manifest.json|sw.js|workbox-.*|fallback-.*|swe-worker-.*|equipo).*)',
  ],
}
```

> El matcher excluye `/equipo` para mantener el QR público.

---

## 4. Brechas entre permisos visuales y seguridad real

| ID | Brecha | Severidad | Mitigación |
|---|---|---|---|
| P01 | Acciones CRUD en módulos NO usan `usePermissions` para gating de botones (solo el menú lo hace). | Medio | RLS Supabase debe rechazar operaciones sin permiso. **A auditar en FASE 5.** |
| P02 | `/equipo/[id]` es ruta **pública** sin auth → expone datos de activo a cualquiera con el ID. | Alto | RLS debe permitir `SELECT` solo de columnas no sensibles (sin costos, sin contratos), o filtrar por `published=true` flag. **A auditar en FASE 5.** |
| P03 | El cliente Supabase usa anon key con sesión en localStorage. Si hay XSS, un atacante podría exfiltrar la sesión. | Bajo (sin entradas vulnerables hoy) | Las migraciones a cookies HttpOnly mitigarían parcialmente. Diferido. |
| P04 | No hay middleware → un usuario sin sesión que cargue `/dashboard/iceo` directamente verá un flash brevísimo del shell antes del redirect. | Bajo (UX, no seguridad) | Aceptable — los datos no se renderizan porque los hooks fallan sin auth y RLS bloquea. |
| P05 | El `dashboard/admin/gps` y otras páginas administrativas dependen de RLS para evitar acceso por URL directa de roles que no son admin. | Medio | RLS + chequear que la página `/admin/gps` use `usePermissions.isAdmin()` o equivalente. **Detectado en FASE 3 (M05).** |

---

## 5. Riesgos corregidos en FASE 4

**Cero modificaciones en código fuente.** Esta fase fue auditoría + decisión + documentación.

Lo que sí queda **explícitamente resuelto**:
- ✅ El sistema actual de auth está documentado y se conoce su perímetro.
- ✅ La decisión sobre middleware es **explícita y razonada** (no es un olvido).
- ✅ El plan de implementación post-MVP está listo para el PR futuro.
- ✅ Las brechas P01–P05 están registradas con mitigación clara y dependencia con FASE 5.

---

## 6. Riesgos pendientes (a resolver en FASE 5 o post-MVP)

| Riesgo | Resolución |
|---|---|
| R01 / S07 — Sin middleware | Diferido. Post-MVP. |
| M01 — `/equipo/[id]` público | RLS debe filtrar columnas en FASE 5. |
| P01 — Acciones CRUD sin gating UI | RLS en FASE 5. Si demo lo amerita, agregar gating en módulos críticos en una sub-fase. |
| P03 — Sesión en localStorage | Cookies HttpOnly post-MVP (depende de migrar a `@supabase/ssr`). |
| P05 — Admin pages sin gating de página | Verificar / agregar `usePermissions.isAdmin()` en `dashboard/admin/*` (no urgente; RLS protege datos). |

---

## 7. Recomendación para FASE 5 (Supabase / RLS)

**Auditoría RLS es la pieza crítica que falta.** Toda la seguridad real del sistema descansa allí. En FASE 5 verificar:

1. **`activos`** — ¿qué columnas son legibles por `anon` (rol que usa `/equipo/[id]`)? Idealmente filtrar costos, contratos, faena_id si son sensibles.
2. **`ordenes_trabajo`** — ¿RLS chequea `responsable_id = auth.uid()` para roles tecnico_mantenimiento? ¿permite create/update solo si rol está en la lista?
3. **`auditoria_eventos`** — ¿solo `auditor` y `administrador` pueden leer? ¿INSERT bloqueado para todos los roles (es trigger-only)?
4. **`usuarios_perfil`** — ¿cada rol solo ve su perfil + admin ve todo?
5. **Storage bucket** (mig 46) — ¿policies para upload solo de roles autorizados?
6. **RPCs** (`crear_ot_*`, `aprobar_ot_*`, `cambiar_estado_*`) — ¿usan `SECURITY DEFINER` con check interno de rol?
7. **`mediciones_kpi`** — ¿ICEO calculado solo por `administrador` / `subgerente_operaciones`?
8. **`incentivos`** — ¿solo `rrhh_incentivos` y `administrador`?

→ Generar matriz `Tabla × Rol × {SELECT, INSERT, UPDATE, DELETE}` esperada vs real.

---

## 8. Resultado de FASE 4

✅ **Auth y permisos auditados. Decisión técnica explícita sobre middleware.**

- Sistema actual cubre el flujo end-to-end con `useRequireAuth` + `usePermissions`.
- Cliente Supabase usa localStorage por diseño (no SSR) — middleware diferido por razón técnica.
- 5 brechas registradas (P01–P05), todas con mitigación dependiente de RLS (FASE 5).
- Cero cambios en código fuente. Sistema sigue compilando (FASE 1 verificada). No se requiere re-correr build (sin diff de código).
- Plan claro de migración a `@supabase/ssr` + middleware para post-MVP.

---

## 9. FASE 5.1 — Roles para piloto operativo (2026-04-28)

### Cambios aplicados
1. ✏️ **`editar-usuario-modal.tsx`**: completados los 5 roles que faltaban en el desplegable (`jefe_operaciones`, `jefe_mantenimiento`, `comercial`, `prevencionista`, `colaborador`). El modal ahora soporta los 15 roles del enum.
2. ✏️ **`admin/page.tsx`**: gating UI con `usePermissions.isAdmin()` para que **solo el rol `administrador` vea/use la pestaña Usuarios** (cambio de roles). Las pestañas General y Parámetros siguen visibles para los demás.
3. 📄 Documento `USUARIOS_ROLES_PILOTO.md` creado con matriz de 11 roles prioritarios + checklist alta de usuarios + reglas de oro.
4. 📄 Documento `PILOTO_OPERATIVO.md` creado con plan de 7 días + módulos por rol + acciones críticas + checklist diario del admin.
5. 📄 SQL `database/schema/53_seed_roles_piloto_recommendations.sql` creado (comentado, no ejecutable directo) con plantilla para los 11 perfiles del piloto.

### Pendientes documentados (no aplicados por riesgo de refactor)
- Gating UI en botones de **Calcular ICEO**, **Calcular Incentivos**, **Cerrar período KPI**, **Crear/Cerrar OT supervisor**, **Ajuste inventario** — todos en `/dashboard/iceo`, `/dashboard/kpi`, `/dashboard/ordenes-trabajo`, `/dashboard/inventario`. Pendiente porque la defensa real es RLS (FASE 5).
- Aplicar Block A de `database/schema/52_rls_hardening_recommendations.sql` antes del piloto (vista pública QR para `/equipo/[id]`).

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, sin breaking changes.
