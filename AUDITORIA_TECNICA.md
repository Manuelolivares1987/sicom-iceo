# AUDITORÍA TÉCNICA — SICOM-ICEO (Empresas Pillado)

> **Última actualización:** 2026-05-02 — FASE 5.8 (Ejecución productiva sin staging) — ✅ 17 archivos en database/production_run/ + 2 docs maestros, build limpio
> **Autor:** Auditoría asistida por Claude Code
> **Repositorio:** `C:\Users\Manuel Olivares\sicom-iceo`
> **Rama:** `main` (estado: limpio al inicio de la auditoría)

---

## 1. Resumen ejecutivo

El proyecto **SICOM-ICEO** es una plataforma operacional para arriendo de flota industrial minera (Empresas Pillado), construida sobre **Next.js 14.2 (App Router) + React 18 + TypeScript estricto + Supabase + Tailwind**, desplegada en **Netlify**, con soporte **PWA** ya activo.

**Estado general detectado: BASE FUNCIONAL SÓLIDA, CON PUNTOS DE ESTABILIZACIÓN MENORES.** No es un esqueleto vacío: hay 51 migraciones SQL aplicadas, 24 servicios de dominio, 23 hooks de datos, módulos productivos avanzados (flota, OEE, ICEO, fiabilidad, combustible) ya desplegados según commits recientes y memoria del proyecto (despliegue 2026-04-11).

**Principales hallazgos preliminares:**

- ✅ Stack moderno y coherente (Next 14, RHF + Zod, React Query, Zustand).
- ✅ Sistema de permisos centralizado existente en `src/hooks/use-permissions.ts` con 16 roles.
- ✅ AuthContext bien estructurado con sesión persistente vía Supabase.
- ⚠️ **Sin middleware de protección de rutas** (todo lo hace el cliente vía `useRequireAuth`). Aceptable si RLS está bien configurada, pero es un riesgo a documentar.
- ⚠️ **No existe `.env.example`** ni script `typecheck` en `package.json`.
- ⚠️ **Carpeta `.next/` en la raíz del repo** además de en `frontend/` — artefacto huérfano.
- ⚠️ Cliente Supabase con **fallbacks `placeholder.supabase.co`** que podrían enmascarar errores de configuración en runtime.
- ⚠️ `frontend/.gitignore` muy minimalista (cubierto parcialmente por raíz, pero conviene reforzar).

No se detectaron secretos hardcodeados en código fuente (`SERVICE_ROLE`, JWTs, URLs Supabase explícitas) — la única ocurrencia es la URL placeholder en `lib/supabase.ts`.

---

## 2. Estructura del repositorio detectada

```
sicom-iceo/
├── .git/
├── .gitignore                    ← raíz, completo
├── .next/                        ⚠ artefacto huérfano en raíz
├── .transcripciones/             ← gitignored
├── .claude/                      ← gitignored
├── public/                       ← raíz (revisar si redundante con frontend/public)
├── database/
│   └── schema/                   ← 51 migraciones SQL (01 → 51)
├── docs/                         ← documentación funcional y técnica
└── frontend/                     ← APP Next.js
    ├── .env.local                ← gitignored, NO leído
    ├── .gitignore                ← minimalista
    ├── netlify.toml
    ├── next.config.js            ← con next-pwa
    ├── tsconfig.json             ← strict: true
    ├── tailwind.config.ts        ← con tema corporativo Pillado
    ├── package.json
    ├── package-lock.json
    ├── tsconfig.tsbuildinfo      ← gitignored
    ├── public/
    └── src/
        ├── app/                  ← App Router (login, dashboard/*, equipo/[id])
        ├── components/           ← ui/, layout/, ot/, flota/, dashboard/, admin/, recepcion/
        ├── contexts/             ← auth-context, query-provider, toast-context
        ├── domain/               ← activos/status, inventario/rules, kpi/calculator, ot/transitions
        ├── hooks/                ← 23 hooks (use-*)
        ├── lib/                  ← supabase, utils, export, services/ (24 servicios)
        ├── types/                ← entities, database, enums
        └── validations/          ← ot, inventario, combustible, index
```

---

## 3. Stack tecnológico

| Categoría             | Tecnología                                                | Versión   |
| --------------------- | --------------------------------------------------------- | --------- |
| Framework             | Next.js (App Router)                                      | ^14.2.0   |
| UI                    | React + React DOM                                         | ^18.3.0   |
| Lenguaje              | TypeScript (strict)                                       | ^5.5.0    |
| Estilos               | Tailwind CSS + tema corporativo Pillado                   | ^3.4.0    |
| BaaS                  | Supabase (`@supabase/supabase-js`, `@supabase/ssr`)       | ^2.45 / ^0.5 |
| Estado servidor       | TanStack React Query                                      | ^5.50     |
| Estado cliente        | Zustand                                                   | ^4.5      |
| Formularios           | React Hook Form + @hookform/resolvers + Zod               | ^7.52 / ^3.9 / ^3.23 |
| Gráficos              | Recharts                                                  | ^2.12     |
| PDF / Excel           | @react-pdf/renderer + exceljs                             | ^3.4 / ^4.4 |
| QR / Scanner          | qrcode + html5-qrcode                                     | ^1.5 / ^2.3 |
| Fechas                | date-fns + date-fns-tz                                    | ^3.6 / ^3.1 |
| Iconos                | lucide-react                                              | ^0.400    |
| PWA                   | @ducanh2912/next-pwa                                      | ^10.2.9   |
| Despliegue            | Netlify (`@netlify/plugin-nextjs`)                        | ^5.15.9   |
| Lint                  | ESLint + eslint-config-next                               | ^8.57 / ^14.2 |

**Scripts disponibles (`frontend/package.json`):**
- `dev` → `next dev`
- `build` → `next build`
- `start` → `next start`
- `lint` → `next lint`
- ❌ **No hay `typecheck`** (se agregará en FASE 1).

---

## 4. Módulos detectados (rutas reales en `src/app`)

| Módulo                  | Ruta                                                       | Listado en spec |
| ----------------------- | ---------------------------------------------------------- | --------------- |
| Login                   | `/login`                                                   | ✅              |
| Home (redirige)         | `/`                                                        | —               |
| Dashboard               | `/dashboard`                                               | ✅              |
| Activos                 | `/dashboard/activos`, `/dashboard/activos/[id]`            | ✅              |
| Flota                   | `/dashboard/flota`, `/jornada`, `/recepcion`, `/verificar/[otId]`, `/aprobar/[otId]`, `/inspeccion-recepcion/[informeId]`, `/recepcion/[informeId]/emitir` | ✅ |
| Mantenimiento           | `/dashboard/mantenimiento`                                 | ✅              |
| Órdenes de Trabajo      | `/dashboard/ordenes-trabajo`, `/[id]`, `/dashboard/mis-ots`| ✅              |
| Inventario              | `/dashboard/inventario`, `/salida`, `/conteo`, `/scanner`, `/cargar-maestro`, `/combustible`, `/combustible/medidores`, `/combustible/movimiento`, `/combustible/varillaje` | ✅ |
| Prevención              | `/dashboard/prevencion`                                    | ✅              |
| Cumplimiento            | `/dashboard/cumplimiento`                                  | ✅              |
| Fiabilidad              | `/dashboard/fiabilidad`                                    | ✅              |
| Reportes                | `/dashboard/reportes`                                      | ✅              |
| Reporte Diario          | `/dashboard/reporte-diario`                                | ✅              |
| KPI                     | `/dashboard/kpi`                                           | ✅              |
| ICEO                    | `/dashboard/iceo`                                          | ✅              |
| Contratos               | `/dashboard/contratos`                                     | ✅              |
| Abastecimiento          | `/dashboard/abastecimiento`, `/despachos`                  | ✅              |
| Comercial               | `/dashboard/comercial`                                     | ✅              |
| Auditoría               | `/dashboard/auditoria`                                     | ✅              |
| Administración          | `/dashboard/admin`, `/admin/checklist-templates`, `/admin/gps` | ✅          |
| Equipo                  | `/equipo/[id]`                                             | ✅              |

**Cobertura: 20/20 módulos del spec presentes en código.** Estado funcional individual se evaluará en FASE 3.

---

## 5. Capa de datos / dominio

- **Servicios (`src/lib/services/`):** 24 archivos — uno por dominio (activos, flota, contratos, faenas, alertas, kpi-iceo, auditoría, admin, inventario, incentivos, mantenimiento, abastecimiento, ordenes-trabajo, certificaciones, prevención, reporte-diario, jornada-conductor, fiabilidad, verificación, ot-materiales, informe-recepcion, combustible). **Capa de servicios YA EXISTE** — la FASE 8 será de mejora, no creación.
- **Hooks (`src/hooks/`):** 23 hooks `use-*` consumiendo los servicios.
- **Dominio (`src/domain/`):** lógica de negocio aislada (transiciones de OT, reglas de inventario, cálculo KPI, status de activos).
- **Validaciones (`src/validations/`):** parcial — solo `ot.ts`, `inventario.ts`, `combustible.ts`, `index.ts`. Faltan validaciones para varios módulos (FASE 6).
- **Migraciones SQL (`database/schema/`):** 51 archivos numerados secuencialmente. Cubren tipos/enums, tablas core, OT, KPI/ICEO, RLS, triggers, cron, flota OEE, jornada, normativa, fiabilidad, combustible, etc. **Backend muy maduro.**

---

## 6. Autenticación y permisos

- **Login:** `src/app/login/page.tsx` + `signIn()` en AuthContext via `supabase.auth.signInWithPassword`.
- **Sesión persistente:** sí (`onAuthStateChange` + `getSession` en mount).
- **Protección de rutas:** **solo cliente** vía `useRequireAuth` en `dashboard/layout.tsx` → `router.replace('/login')` si no hay sesión. **No hay `middleware.ts`** (ni en `src/` ni en raíz de frontend).
- **Permisos:** matriz centralizada en `src/hooks/use-permissions.ts` con 16 roles y permisos `view/create/edit/delete/approve/export` por módulo. `getVisibleModules()` para sidebar. **Más completo que el spec** (el spec sugiere 9, hay 16).

**Riesgo de seguridad medio:** sin middleware, las rutas privadas se renderizan brevemente antes del redirect. La defensa real depende de **Supabase RLS** (verificar en FASE 5). Los datos no se filtran por backend a nivel de Next, sólo a nivel de Postgres.

---

## 7. Estado general — Riesgos iniciales (clasificados)

| ID  | Gravedad   | Riesgo                                                                                                    | Fase resolución |
| --- | ---------- | --------------------------------------------------------------------------------------------------------- | --------------- |
| R01 | **Alto**   | No existe `middleware.ts`: rutas privadas dependen 100% de RLS + redirect cliente.                        | FASE 4 / 5      |
| R02 | **Medio**  | No existe `.env.example` — onboarding y despliegue dependen de conocimiento tribal.                       | FASE 2          |
| R03 | **Medio**  | `lib/supabase.ts` usa fallback `placeholder.supabase.co` que silencia errores de config faltante.         | FASE 1 / 2      |
| R04 | **Medio**  | `package.json` no tiene script `typecheck` — TS strict no se valida fuera de build.                       | FASE 1          |
| R05 | **Bajo**   | Carpeta `.next/` en raíz del repo (debería estar solo en `frontend/`).                                    | FASE 2          |
| R06 | **Bajo**   | `frontend/.gitignore` minimalista (5 líneas). Cubierto por gitignore raíz, pero conviene normalizar.      | FASE 2          |
| R07 | **Bajo**   | Carpeta `public/` también en raíz del repo (revisar si está vacía o redundante).                          | FASE 2          |
| R08 | **Medio**  | Validaciones Zod incompletas: faltan para activos, mantenimiento, prevención, contratos, abastecimiento.  | FASE 6          |
| R09 | **Medio**  | Pendiente verificar si existen mocks/demo data en componentes (82 ocurrencias de `placeholder/mock/demo` en 32 archivos — la mayoría parecen ser `placeholder` HTML, pero hay que confirmar). | FASE 3 |
| R10 | **Bajo**   | Servicio worker PWA generado en build podría versionarse — ya cubierto en `.gitignore` raíz.              | OK              |
| R11 | **Crítico (potencial)** | Sin ejecutar build aún: hasta no correr `npm run build` y `tsc --noEmit` no sabemos si compila. | FASE 1 |

**Crítico: R11** — el primer paso de FASE 1 es confirmar que el sistema compila tal cual está hoy.

---

## 8. Primeras recomendaciones (no aplicadas en FASE 0)

1. **No tocar arquitectura todavía.** La base es sólida; el riesgo de refactor masivo en MVP supera el beneficio.
2. **FASE 1 inmediata:** correr `npm install`, `npm run lint`, agregar `typecheck`, `npm run build`. Estabilizar antes de cualquier otra cosa.
3. **No eliminar nada en FASE 0.** Las carpetas `.next/` y `public/` en raíz se documentan, no se borran sin confirmación.
4. **No leer `.env.local`.** Cumplido — el archivo se detectó pero no se abrió.
5. **Respetar `usePermissions` existente.** No reescribir desde cero en FASE 4.
6. **Respetar capa de servicios existente.** FASE 8 será revisión y mejora puntual, no rediseño.

---

## 9. Siguiente fase sugerida

~~**FASE 1 — Build, TypeScript y dependencias.**~~ ✅ Completada (ver sección 10).

**Próxima:** FASE 2 — Seguridad, variables de entorno y limpieza del repositorio.

> **Esperando confirmación del usuario para continuar.**

---

## 10. FASE 1 — Resultado (2026-04-28)

✅ **EL SISTEMA COMPILA.** Detalles completos en `CHECKLIST_ESTABILIDAD.md`.

### Acciones aplicadas
1. Agregado script `"typecheck": "tsc --noEmit"` a `frontend/package.json`.
2. Creado `frontend/.eslintrc.json` con `extends: "next/core-web-vitals"` (faltaba la config base; lint pedía setup interactivo).
3. Desactivada regla `react/no-unescaped-entities` (cosmética, evita tocar 12 archivos).
4. Corregido bug crítico **`react-hooks/rules-of-hooks`** en `src/app/dashboard/page.tsx`: 10 hooks llamados después de un `if/return` por rol. Solución mínima: extraído sub-componente `LegacyDashboard` para que los hooks no queden detrás de un condicional. Sin cambios funcionales ni de UI.
5. Corregido `useId()` condicional en `src/components/ui/input.tsx` y `src/components/ui/select.tsx` (movido fuera del `||`).

### Métricas
- Lint: **0 errores**, 16 warnings (no bloquean).
- Typecheck: **0 errores**.
- Build: **37 rutas generadas** (28 estáticas + 9 dinámicas), service worker PWA emitido OK.

### Pendientes registrados
- 16 warnings de lint (`<img>`, `exhaustive-deps`) — diferidos a FASE 7/9.
- 14 vulnerabilidades npm (`npm audit`) — revisar en FASE 2 sin `--force`.
- Riesgos R01–R09 de la sección 7 siguen vigentes (FASE 2+).

---

## 11. FASE 2 — Resultado (2026-04-28)

✅ **Repositorio limpio de secretos.** Detalles en `SEGURIDAD_Y_ENTORNO.md`.

### Acciones aplicadas
1. ➕ Creado `frontend/.env.example` con plantilla de variables esperadas (sin valores reales).
2. 🔧 Reescrito `frontend/.gitignore` para que sea autosuficiente: incluye ahora `.env`, `.env.production`, `.env.development`, `.DS_Store`, `Thumbs.db`, IDE folders y archivos PWA generados (`sw.js`, `workbox-*.js`, etc.).
3. 🔧 Mejorado `frontend/src/lib/supabase.ts`: agregado `console.error` que se dispara solo en navegador cuando faltan `NEXT_PUBLIC_SUPABASE_URL` o `NEXT_PUBLIC_SUPABASE_ANON_KEY`. El placeholder se mantiene **solo** para no romper `next build` en pre-render estático. (Riesgo S03 — Medio → Resuelto.)
4. ✅ Verificado: cero referencias a `SUPABASE_SERVICE_ROLE_KEY` o secretos no-públicos en frontend.
5. ✅ Verificado: `git ls-files` → 231 archivos versionados, ninguno sensible (sin `.env*`, sin `.next/`, sin `node_modules/`, sin `tsbuildinfo`).

### Pendientes manuales (informados al usuario, no ejecutados)
- 🟡 Eliminar carpeta `.next/` huérfana en raíz del repo (no versionada, solo basura local).
- 🟡 Eliminar carpeta `public/` huérfana en raíz si está vacía/redundante (no versionada).
- 🟡 Considerar rotación preventiva de Supabase anon key (no se detectó filtración; es buena práctica si hay dudas).
- 🟡 14 vulnerabilidades npm: diferidas. Todas en build-time tooling. `npm audit fix --force` no aplicado (saltos semver-major).

### Riesgos resueltos en FASE 2
- S01 (gitignore minimalista) ✅
- S02 (sin `.env.example`) ✅
- S03 (fallback Supabase silencioso) ✅

### Riesgos persistentes
- S04, S05 (huérfanos locales) — acción manual del usuario.
- S06 (vulns build-time) — diferido / informativo.
- S07 = R01 (sin middleware) — FASE 4.

---

## 12. FASE 3 — Resultado (2026-04-28)

✅ **Mapa real construido.** Detalles completos en `MAPA_MODULOS.md`.

### Hallazgos
- **22 módulos** detectados (login + 21 bajo dashboard + ficha pública `/equipo/[id]`).
- **162 llamadas `supabase.from(...)`** distribuidas en 22 servicios → **todos los módulos consumen Supabase real**.
- **Cero módulos con mock/demo data hardcoded** ni "solo maqueta".
- Capa de servicios YA EXISTE y es correcta (uno por dominio). FASE 8 será refinamiento, no creación.

### Distribución de readiness
| Estado demo | Cant |
|---|---|
| 🟢 Listo | 16 |
| 🟡 Parcial (depende de datos/permisos) | 4 |
| 🛠️ Solo herramienta operativa | 3 |
| 🔴 No mostrar (depende de hardware) | 1 |
| 🔧 Corrección urgente | 0 |

### Top 5 sugerido para demo ejecutiva
1. Login → /dashboard
2. Flota (módulo bandera, 55 vehículos reales)
3. OT + Mantenimiento (motor de estados, Zod)
4. KPI + ICEO (ventaja competitiva)
5. Reporte Diario (automatización + tendencia)

### Riesgos detectados en FASE 3
- M01 (Alto) — `/equipo/[id]` ruta pública sin auth → revisar RLS en FASE 5.
- M02–M04 (Medio) — bundles pesados en `recepcion/emitir` (597 KB), `cargar-maestro` (414 KB), `scanner` (cámara).
- M05–M07 (Bajo) — Admin/GPS sin hardware, Storage bucket en FASE 5, Zod incompleto en FASE 6.

### Cero modificaciones en código fuente en esta fase.

---

## 13. FASE 4 — Resultado (2026-04-28)

✅ **Auth y permisos auditados. Decisión sobre middleware explícita y razonada.** Detalles en `PERMISOS_Y_ROLES.md`.

### Hallazgos clave
- **AuthContext + `useRequireAuth` cubren protección cliente** de todo `/dashboard/*`. Login y `/equipo/[id]` son **públicas por diseño** (QR en terreno).
- **`usePermissions` con 16 roles × 16 módulos × 6 acciones** ya existe y funciona. **Sidebar lo respeta** (oculta grupos según `canView`).
- **Brecha P01:** las acciones internas (botones Crear/Editar/etc) **no están filtradas por `usePermissions` en la mayoría de módulos**. Solo el menú lo está. → defensa real depende de RLS Supabase.

### Decisión: `middleware.ts` DIFERIDO post-MVP

**Razón técnica:** el cliente Supabase usa `@supabase/supabase-js` puro → la sesión se guarda en `localStorage`, no en cookies. Un middleware edge no puede leer localStorage. Implementarlo requiere migrar a `@supabase/ssr` con cookie storage (refactor con riesgo alto para el MVP). El upside de seguridad es marginal porque RLS es la defensa real.

### Brechas registradas (P01–P05)
- P01: acciones CRUD en módulos sin gating UI por permisos → mitigado por RLS (FASE 5).
- P02: `/equipo/[id]` público → RLS debe filtrar columnas sensibles (FASE 5).
- P03: sesión en localStorage (XSS surface) → cookies HttpOnly post-MVP.
- P04: sin middleware = flash de UI antes del redirect (UX, no seguridad).
- P05: páginas admin sin gating de página → RLS protege datos.

### Cero modificaciones en código fuente en esta fase.

### Verificación
- `npm run typecheck` → ✅ 0 errores (re-ejecutado).
- Build no requiere re-ejecución (sin diff de código).

---

## 14. FASE 5 — Resultado (2026-04-28)

⚠️ **Auditoría completa con brechas reales detectadas.** Detalles en `SUPABASE_AUDIT.md`. SQL recomendado (no destructivo) en `database/schema/52_rls_hardening_recommendations.sql`.

### Hallazgos clave
- **51 migraciones SQL revisadas**, **47 RPCs frontend mapeadas**, **4 buckets Storage** detectados (solo 1 versionado en mig 46).
- Patrón sistémico: la mayoría de tablas usan `pol_authenticated_select_* USING (true)` → cualquier autenticado lee todo.
- Defensa por rol depende de RPCs `SECURITY DEFINER`, pero **muchas no validan rol al iniciar** → un usuario `colaborador` podría llamar `rpc_cerrar_ot_supervisor` directamente desde el browser.

### Brechas (resumen)
- **🔴 RLS-01 Crítica:** 12+ RPCs SECURITY DEFINER sin role-check inicial (cierre OT, ajuste inv, cálculo ICEO).
- **🔴 RLS-02 Crítica:** `/equipo/[id]` invoca `rpc_ficha_activo` (probable SECURITY DEFINER) que expondría `costo_acumulado`, `faena_nombre` sin login.
- **🔴 RLS-03 Crítica:** Tabla `incentivos` con SELECT abierto a authenticated.
- **🟠 RLS-04 a RLS-07 Altas:** lecturas abiertas de `usuarios_perfil`, `auditoria_eventos`, `mediciones_kpi`, `certificaciones`, `contratos`; 24 funciones `calcular_kpi_*` sin role-check; buckets no versionados.
- **🟡 RLS-08, RLS-09 Medias:** bucket `evidencias-verificacion` con `public=true` (decisión de producto), naming `suspel_*/respel_*` por verificar.

### Cero ejecuciones destructivas, cero cambios en código frontend
- Archivo `52_rls_hardening_recommendations.sql` creado **comentado bloque por bloque** con 5 secciones: A (vista pública QR), B (plantilla role-check), C (restricción SELECTs), D (versionar buckets), E (verificaciones SAFE).
- **Acción mínima recomendada antes de demo:** aplicar **solo Block A** (vista pública `public_activos_qr` + flag `qr_publico_habilitado`). Reduce el blast radius más visible (ruta pública sin login).

### Verificación
- `npm run typecheck` → ✅ sigue limpio (sin diff TS).

---

## 15. FASE 5.1 — Roles y permisos para piloto operativo (2026-04-28)

✅ **Sistema apto para piloto controlado.** Detalles en `USUARIOS_ROLES_PILOTO.md` y `PILOTO_OPERATIVO.md`.

### Hallazgos
- Frontend (`use-permissions.ts`), enum (`types/enums.ts`) y DB (`rol_usuario_enum`) **coinciden 100%** con 15 roles.
- **Brecha cerrada:** `EditarUsuarioModal` solo listaba 10 roles → **5 faltaban** (`jefe_operaciones`, `jefe_mantenimiento`, `comercial`, `prevencionista`, `colaborador`). Ahora cubre los 15.
- **Brecha cerrada:** la pestaña **Usuarios** en `/dashboard/admin` ahora está gated con `usePermissions.isAdmin()` → solo el rol `administrador` puede cambiar roles.

### Cambios de código aplicados
1. `frontend/src/components/admin/editar-usuario-modal.tsx` — completar 15 roles.
2. `frontend/src/app/dashboard/admin/page.tsx` — gating UI con `usePermissions`.

### Documentos creados/actualizados
- `USUARIOS_ROLES_PILOTO.md` (nuevo) — 11 roles prioritarios + matriz + checklist alta usuarios.
- `PILOTO_OPERATIVO.md` (nuevo) — plan 7 días + módulos por rol + acciones críticas.
- `database/schema/53_seed_roles_piloto_recommendations.sql` (nuevo, comentado) — plantilla para 11 perfiles.
- `PERMISOS_Y_ROLES.md` (sección 9 — FASE 5.1).

### Acciones críticas con gating UI **pendiente** (por riesgo de refactor)
- Calcular ICEO, Calcular Incentivos, Cerrar período KPI (`/dashboard/iceo`, `/dashboard/kpi`).
- Cerrar OT supervisor, Aprobar OT (`/dashboard/ordenes-trabajo`).
- Ajustes inventario, salidas, conteos (`/dashboard/inventario`).
- Defensa real: RLS Supabase (FASE 5 detectó brechas, hardening en `52_*.sql`).

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 16. FASE 5.2 — Estado diario/futuro de flota + checklists configurables (2026-04-29)

✅ **Mejora aplicada con cambios mínimos.** Detalles completos en `FLOTA_ESTADO_DIARIO_CHECKLISTS.md` y `CHECKLISTS_FLOTA_IMPORTACION.md`.

### Hallazgo clave
La infraestructura de "estado diario / programado + checklists configurables" **ya existía** completa en migraciones previas (22, 25, 30, 37, 44, 45). Solo faltaba exponer la fecha en la UI (estaba hardcodeada como `today`) y agregar UI para crear plantillas nuevas. **Cero migraciones nuevas necesarias.**

### Cambios aplicados
1. ✏️ `frontend/src/components/flota/cambiar-estado-modal.tsx`:
   - Agregado selector de fecha (default hoy, permite futuro, bloquea pasado salvo admin).
   - Mensaje contextual según fecha (futuro = "Programar cambio", hoy = "Guardar cambio", pasado = "Está corrigiendo el historial").
   - Validación con `usePermissions().isAdmin()` antes de submit.
2. ✏️ `frontend/src/app/dashboard/admin/checklist-templates/page.tsx`:
   - Bloque "Crear nueva plantilla" con tipo + nombre. Botón "Crear plantilla vacía".
3. 📄 `database/schema/54_flota_estado_programado_checklists.sql` — **no destructivo, todo comentado.** Bloques A (índices opcionales), B (comments docs), C (plantilla SQL para import), D (versionado formal post-piloto), 0/E (verificaciones SAFE).
4. 📄 `FLOTA_ESTADO_DIARIO_CHECKLISTS.md` (nuevo) — flujo, reglas, riesgos, pruebas manuales, pendientes.
5. 📄 `CHECKLISTS_FLOTA_IMPORTACION.md` (nuevo) — formato CSV/Excel, procedimiento paso a paso, versionado, errores frecuentes.

### Cambios NO aplicados (documentados)
- BLOCK D de `54_*.sql` (versionado formal con `version`, `template_padre_id`, `valido_desde/hasta`) — diferido post-piloto.
- Sección UI con cambios programados próximos 7 días — FASE 7.
- Import CSV masivo de plantillas — post-piloto.
- BLOCK B de `52_*.sql` (role-check en RPCs sensibles) — pendiente FASE 5.x.

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 17. FASE 6 — Validaciones y formularios críticos (2026-04-30)

✅ **Biblioteca Zod completa creada para 12 dominios. Cero formularios tocados durante el piloto.** Detalles en `VALIDACIONES_FORMULARIOS.md`.

### Hallazgo principal
Solo **2 archivos** del frontend usan React Hook Form (`crear-ot-modal` con Zod, `login` sin Zod). El resto del sistema usa validación manual con `useState`. Aplicar zodResolver masivamente sería refactor mayor con riesgo alto durante piloto operativo.

### Decisión
**No refactorizar formularios.** Construir biblioteca Zod completa lista para uso incremental cada vez que se toque un formulario por bug, mejora o feature nueva.

### Archivos creados (9 nuevos schemas)
- `validations/activos.ts` — alta/edición de equipos + actualización de métricas
- `validations/mantenimiento.ts` — planes PM + generación OT desde plan + pautas
- `validations/certificaciones.ts` — con regla `fecha_vencimiento >= fecha_emision`
- `validations/abastecimiento.ts` — rutas + transiciones + abastecimientos
- `validations/contratos.ts` — con regla `fecha_fin > fecha_inicio`
- `validations/prevencion.ts` — SUSPEL/RESPEL
- `validations/flota.ts` — cambio estado (regla "OT auto solo M/T/F") + verificación ready-to-rent
- `validations/checklists.ts` — `checklistTemplateOperativoSchema` exige ≥1 ítem
- `validations/admin.ts` — edición usuario + RUT chileno regex

### Archivo modificado
- `validations/index.ts` — re-export de los 12 dominios

### Riesgos pendientes (V01–V10)
Ver `VALIDACIONES_FORMULARIOS.md §7`. Priorización para próximo sprint:
1. Cambio Estado Flota
2. Salida/Ajuste inventario
3. Movimiento combustible
4. Crear certificación
5. Editar usuario admin

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 18. FASE 5.3 — Bodega, OC, CECO y combustible clase mundial (2026-04-30)

✅ **Modelo de datos completo + biblioteca Zod creada. SQL NO ejecutado** (todo comentado en `55_*.sql`). Detalles en `BODEGA_OC_CECO_TRAZABILIDAD.md` y `COMBUSTIBLE_TRAZABILIDAD_CLASE_MUNDIAL.md`.

### Diagnóstico del flujo actual (gap detectado)
- ❌ No existían: OC con estado, recepción parcial contra OC, tabla proveedores, CECO obligatorio en salidas, persona "entregado a", folios internos REC/SAL/ICB/SCB/DCB, ingreso combustible con guía formal UNIQUE, tipos venta/carga propio/despacho, despacho con 3 sellos.
- ✅ Ya existían: stock automático (mig 50), audit_trigger, RPCs `rpc_registrar_entrada/salida_inventario`, `fn_registrar_movimiento_combustible`.

### SQL creado (no ejecutado)
`database/schema/55_bodega_combustible_oc_ceco_trazabilidad.sql` — 17 bloques comentados:
- A: 8 enums nuevos
- B: tabla `proveedores` (con seed sugerido ENEX/ESMAX/COPEC)
- C: tabla `centros_costo`
- D: `ordenes_compra` + items con `cantidad_pendiente` generada
- E: `recepciones_bodega` + items con UNIQUE proveedor+doc
- F: `salidas_bodega` + items con CHECK CECO obligatorio
- G: `ingresos_combustible` con UNIQUE proveedor+guía
- H: `salidas_combustible` con CHECK según tipo
- I: `despachos_combustible` con CHECK 3 sellos + fotos
- J: 5 funciones de folio
- K: RPC `rpc_registrar_recepcion_bodega` (role-check + sobrecantidad solo admin)
- L: RPC `rpc_registrar_salida_bodega` (role-check + CECO + reglas)
- M: RPC `rpc_registrar_ingreso_combustible` (reusa fn existente)
- N-O: RPCs de salida y despacho con sellos (firma propuesta)
- P: notas Storage
- Q: 5 verificaciones SAFE

### Validaciones Zod nuevas
- `validations/bodega.ts` (nuevo, 6 schemas): proveedor, CECO, OC, OC item, recepción, salida.
- `validations/combustible.ts` (extendido, 4 schemas): ingreso formal, salida formal, despacho salida sellos, despacho entrega.
- `validations/index.ts` actualizado con `export * from './bodega'`.

### Frontend
**No tocado.** Implementación incremental documentada en B06–B11 y C07–C11.

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 19. FASE 5.4-A — Inventario FIFO para repuestos/materiales (2026-05-02)

✅ **Modelo FIFO completo + función transaccional + 4 vistas para finanzas. SQL NO ejecutado** (`56_*.sql` todo comentado). Detalles en `INVENTARIO_FIFO_COSTEO_OT.md`.

### Decisión técnica
FIFO para repuestos/materiales/insumos (físicamente individuales, con lotes y vencimientos). Combustible mantiene su modelo CPP existente (mig 50) — fungible mezclado físicamente.

### Tablas nuevas (mig 56)
- `inventario_capas` — capas valorizadas creadas por cada recepción contra OC. Campos clave: `cantidad_inicial`, `cantidad_disponible`, `costo_unitario`, `costo_total_disponible` (generated), trazabilidad completa hacia OC/recepción/proveedor.
- `inventario_consumos_capas` — detalle de cada consumo (1 a N filas por salida). Apunta a `salida_bodega_item_id`, `ot_id`, `ceco_id`, `capa_id`.

### Extensión a tablas existentes
- `ot_materiales_planeados` (mig 48) recibe 5 columnas nuevas: `costo_unitario_real`, `costo_total_real`, `metodo_costeo`, `salida_bodega_id`, `ceco_id`.

### Función core
`fn_consumir_inventario_fifo(producto, bodega, cantidad, salida_id, item_id, ot_id, ceco_id, ...)`:
- `SELECT ... FOR UPDATE` ordenado por `(fecha_recepcion, created_at, id)` ASC.
- Pre-check de stock total + RAISE EXCEPTION claro si insuficiente.
- Loop consumiendo capas; marca `agotada` cuando llega a 0.
- Retorna JSONB con totales + detalle de capas.

### RPCs reescritas (versiones FIFO)
- `rpc_registrar_recepcion_bodega` — crea capa por cada item; valida sobrecantidad y precio distinto con override admin + justificación ≥10 caracteres.
- `rpc_registrar_salida_bodega` — consume FIFO; actualiza `salidas_bodega_items.costo_unitario_clp`; inserta en `ot_materiales_planeados` con costo real si tipo=ot.

### 4 vistas para finanzas
- `v_trazabilidad_producto_fifo` — capa → recepción → OC → proveedor → consumos.
- `v_costo_ot_materiales_fifo` — costo real por OT con drill-down a capas.
- `v_stock_valorizado_fifo` — valor de inventario actual a costo real.
- `v_kardex_valorizado_materiales` — kardex unificado entradas/salidas con saldos acumulados.

### Validaciones Zod nuevas
- `recepcionFifoSchema` — extiende recepción con override + justificación.
- `salidaFifoSchema` — bloquea costo manual salvo `manual_autorizado` con autorización + justificación.
- `capaInventarioReadSchema` — tipo de lectura para UI.
- Refactor: `salidaBodegaSchema` se separa en `salidaBodegaBaseSchema` (extensible) + refines aplicados aparte.

### Frontend
**No tocado.** Plan de implementación incremental en `INVENTARIO_FIFO_COSTEO_OT.md §13.1`.

### Riesgos
- F01 🔴 mig 55 debe aplicarse PRIMERO (FK de mig 56 dependen de tablas de mig 55).
- F02 🟠 Reconciliación capas vs stock_bodega debe ser semanal.
- F03 🟠 Concurrencia mitigada con `FOR UPDATE`.
- F04 🟡 Productos legacy sin capas requieren script ad-hoc de seed.

### Verificación
- `npm run typecheck` → ✅ 0 errores (refactor de Zod corregido).
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 20. FASE 5.4-B — Combustible con CPP móvil + trazabilidad valorizada (2026-05-02)

✅ **Modelo CPP móvil + 3 RPCs valorizadas + 3 vistas + ejemplo numérico documentado. SQL NO ejecutado** (`57_*.sql` todo comentado). Detalles en `COMBUSTIBLE_COSTEO_PROMEDIO_TRAZABILIDAD.md`.

### Decisión técnica
**Combustible = Promedio Ponderado Móvil por estanque** (físicamente mezclado). Repuestos/materiales mantienen FIFO (mig 56, NO se modifica).

### Tablas nuevas (mig 57)
- `combustible_stock_inicial` — partida controlada con UNIQUE activa por estanque, justificación obligatoria.
- `combustible_kardex_valorizado` — snapshot inmutable post-movimiento con stock + CPP + valor + cliente/equipo/CECO + evidencia.

### Extensiones a tablas mig 55
- `combustible_estanques` += `costo_promedio_lt`, `valor_total_stock`.
- `ingresos_combustible` += 9 campos CPP (`costo_unitario_lt`, `valor_total_ingreso`, `costo_promedio_anterior/nuevo`, `stock_anterior/nuevo`, `valor_stock_anterior/nuevo`, `kardex_valorizado_id`).
- `salidas_combustible` += 8 campos (`costo_unitario_aplicado`, `valor_total_salida`, `costo_promedio_al_momento`, `stock_anterior/nuevo`, `valor_stock_anterior/nuevo`, `kardex_valorizado_id`).
- `despachos_combustible` += `kardex_valorizado_id`.

### RPCs nuevas
- `rpc_registrar_stock_inicial_combustible` — solo admin/subgerente, una activa por estanque, observación obligatoria ≥5.
- `rpc_registrar_ingreso_combustible_valorizado` — recalcula CPP móvil con fórmula clásica, valida proveedor activo, guía única, evidencia, capacidad estanque, diferencia meter/litros.
- `rpc_registrar_salida_combustible_valorizada` — aplica CPP vigente, NO modifica CPP, valida CECO, motivo, evidencia, reglas según tipo (venta_externa/carga_propio/despacho/ajuste).

### 3 vistas para finanzas
- `v_combustible_kardex_valorizado` — kardex con joins enriquecidos.
- `v_combustible_trazabilidad_salida` — detalle de cada salida + ingresos previos que formaron CPP (informativo).
- `v_combustible_stock_valorizado_actual` — tablero ejecutivo: stock, CPP, valor, % llenado, último ingreso/salida/varillaje.

### Validaciones Zod nuevas (3 schemas)
- `stockInicialCombustibleSchema` — observación obligatoria ≥5.
- `ingresoCombustibleValorizadoSchema` — guía + evidencia + meter coherente + diferencia con observación.
- `salidaCombustibleValorizadaSchema` — CECO + vale + reglas según tipo. **NO acepta costo manual** (sistema lo asigna).

### Ejemplo numérico documentado
Stock inicial 1.000 lt a $900 → Compra 2.000 lt a $1.000 → CPP nuevo $966,67 → Salida 500 lt: costo $483.333, stock final 2.500 lt valor $2.416.667.

### Frontend
**No tocado.** Servicios/pantallas documentadas en `COMBUSTIBLE_COSTEO_PROMEDIO_TRAZABILIDAD.md §12`.

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 21. FASE 5.6 — Operacionalización: migraciones pendientes + dashboards por rol (2026-05-02)

✅ **Inventario migraciones + 2 planes operativos + Router de dashboards + 5 dashboards por rol implementados.** Detalles en `DASHBOARDS_POR_ROL.md`, `PLAN_OPERACION_STAGING_MIGRACIONES.md`, `PLAN_PASO_PRODUCCION_CONTROLADO.md`.

### Migraciones pendientes auditadas
| Mig | Estado | Aplicar staging | Aplicar prod |
|---|---|---|---|
| 52 | Comentado | ⚠️ Solo Block A | Solo Block A |
| 53 | Comentado | Tras crear users Auth | Tras pruebas |
| 54 | Solo Block 0 SAFE | ✅ | ✅ |
| 55 | Comentado | ✅ Bloques A-O | ✅ Tras staging |
| 56 | Comentado (depende 55) | ✅ Tras 55+tests | ✅ |
| 57 | Comentado (depende 55) | ✅ Tras 55+tests | ✅ |

### Frontend implementado
- **Router:** `src/components/dashboard/role-dashboard-router.tsx` — switch por `perfil.rol`.
- **Dashboards nuevos:** admin, mantenimiento (jefe/supervisor/planificador), tecnico, bodeguero, abastecimiento.
- **Hook nuevo:** `hooks/use-admin-stats.ts`.
- **Modificado:** `dashboard/page.tsx` simplificado para usar el router; LegacyDashboard como fallback.
- **Reusados:** ExecutiveDashboard (gerencia), CommercialDashboard, OperationsDashboard (provisional para auditor/prevencionista/rrhh).

### Dashboards pendientes documentados
- AuditorDashboard, PrevencionistaDashboard, RRHHIncentivosDashboard — datos y hooks reutilizables documentados en `DASHBOARDS_POR_ROL.md §5`.

### Verificación FASE 5.6
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

---

## 22. FASE 5.7 — Preparación staging operativo (2026-05-02)

✅ **14 archivos en `database/staging/` listos para ejecutar paso a paso. Build frontend limpio. Cero ejecuciones SQL automáticas.**

### Scripts creados (`database/staging/`)
| # | Archivo | Tipo | Líneas aprox |
|---|---|---|---|
| 00 | `00_README_STAGING.md` | Doc | 140 |
| 01 | `01_prechecks_safe.sql` | Solo lectura | 110 |
| 02 | `02_seed_datos_maestros.sql` | INSERT idempotente | 60 |
| 03 | `03_apply_mig55_bodega_combustible_base.sql` | DDL + funciones folio (ejecutable) | 380 |
| 04 | `04_validate_mig55.sql` | Lectura + DO con ROLLBACK | 120 |
| 05 | `05_apply_mig56_fifo.sql` | DDL + función FIFO + vista | 220 |
| 06 | `06_seed_capas_iniciales_fifo.sql` | Plantilla con prechecks | 90 |
| 07 | `07_validate_fifo.sql` | DO con tests $10K/$14K + ROLLBACK | 130 |
| 08 | `08_apply_mig57_combustible_cpp.sql` | DDL + RPC stock_inicial + vista | 190 |
| 09 | `09_seed_stock_inicial_combustible.sql` | Plantilla manual por estanque | 100 |
| 10 | `10_validate_combustible_cpp.sql` | DO con test ejemplo $900/$966,67 + ROLLBACK | 130 |
| 11 | `11_validate_roles_dashboards.sql` | Solo lectura roles/perfiles | 80 |
| 12 | `12_go_no_go_checklist.md` | Checklist final + bitácora | 130 |
| 13 | `13_optional_mig52_blockA_qr_publico.sql` | Opcional QR público | 80 |

### Documento operativo

**`EJECUCION_STAGING_PASO_A_PASO.md`** — guía completa con: cómo crear Supabase staging, copiar variables `.env`, apuntar frontend, ejecutar cada script, registrar resultados, qué hacer si falla un paso, cómo volver atrás, criterios para pasar a producción.

### Características clave de los scripts

- **Idempotentes** donde es posible (`CREATE TABLE/INDEX IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, `ALTER TABLE ADD COLUMN IF NOT EXISTS`).
- **Tests con ROLLBACK explícito** en `04`, `07`, `10` — no contaminan la BD aunque pasen.
- **Verificaciones SAFE** al final de cada `apply` — confirman que se creó lo esperado.
- **Rollback manual documentado** comentado al final de cada `apply_*`.
- **Pre-checks de datos** (productos sin costo, cantidades negativas) antes de seed.

### Estado dashboards FASE 5.6
Validado: `RoleDashboardRouter` + 5 dashboards prioritarios + ExecutiveDashboard/CommercialDashboard/OperationsDashboard reusados. Sin cambios en FASE 5.7.

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

### NO ejecutado en este sprint
- ❌ Ningún SQL aplicado.
- ❌ Frontend no apunta a staging todavía (espera decisión operativa del administrador).
- ❌ Mig 52 Blocks B/C/D no incluidos (solo Block A opcional en archivo 13).

---

## 23. FASE 5.8 — Ejecución productiva sin staging (2026-05-02)

✅ **17 archivos en `database/production_run/` + 2 documentos maestros + bitácora SQL.** No hay staging disponible (plan free); se trabaja directamente sobre producción con controles estrictos. Build limpio.

### Archivos creados en `database/production_run/`
| # | Archivo | Tipo |
|---|---|---|
| 00 | `00_LEER_ANTES_PRODUCCION.md` | Doc obligatorio |
| 01 | `01_backup_obligatorio.md` | Procedimiento backup |
| 02 | `02_prechecks_produccion_safe.sql` | Solo lectura + diagnóstico |
| 03 | `03_bitacora_ejecucion.sql` | Tabla `operacion_migraciones_log` + helper |
| 04 | `04_apply_mig55_produccion.sql` | DDL mig 55 idempotente con log |
| 05 | `05_validate_mig55_produccion.sql` | Solo lectura + ROLLBACK |
| 06 | `06_seed_datos_maestros_produccion.sql` | INSERT idempotente |
| 07 | `07_apply_mig56_fifo_produccion.sql` | DDL FIFO con verificación dependencia |
| 08 | `08_validate_mig56_fifo_produccion.sql` | Solo lectura + ROLLBACK |
| 09 | `09_seed_capas_iniciales_fifo_produccion.sql` | **MANUAL con Finanzas** |
| 10 | `10_apply_mig57_combustible_cpp_produccion.sql` | DDL CPP con verificación dependencia |
| 11 | `11_validate_mig57_combustible_cpp_produccion.sql` | Solo lectura + ROLLBACK |
| 12 | `12_seed_stock_inicial_combustible_produccion.sql` | **MANUAL con Finanzas** |
| 13 | `13_validate_roles_dashboards_produccion.sql` | Solo lectura |
| 14 | `14_optional_mig52_blockA_qr_publico_produccion.sql` | **OPCIONAL — no ejecutar salvo decisión** |
| 15 | `15_checklist_go_no_go_produccion.md` | Checklist final |
| 16 | `16_monitoring_post_deploy.sql` | Monitoreo a 1h, 24h, 7d |

### Documentos en raíz
- `EJECUCION_PRODUCCION_PASO_A_PASO.md` — guía operativa completa.
- `COMO_IDENTIFICAR_PROBLEMAS_POST_MIGRACION.md` — diagnóstico ante 7 categorías de síntomas.

### Bitácora obligatoria
Tabla `operacion_migraciones_log` + función `fn_log_operacion_migracion()` registran cada paso ejecutado con responsable y resultado.

### Características clave
- **Idempotentes** (`CREATE TABLE IF NOT EXISTS`, `ON CONFLICT DO NOTHING`).
- **Verificación de dependencias** al inicio (apply_mig56 verifica mig 55).
- **Tests con ROLLBACK explícito** en validaciones — no contaminan datos.
- **Resultado final** con `OK MIG55/56/57` o `STOP` o `PENDIENTE`.
- **Rollback manual documentado** al final de cada apply.
- **Pausas obligatorias** en pasos 09 y 12 (validación Finanzas).

### Verificación
- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.

### NO ejecutado en FASE 5.8
- ❌ Ningún SQL aplicado en producción.
- ❌ Backup no generado (lo hace el operador antes de ejecutar).
- ❌ Mig 52 Blocks B/C/D no incluidos (solo Block A opcional).
- ❌ Mig 56 RPCs reescritas FIFO completas no incluidas — solo tabla + función `fn_consumir_inventario_fifo`. Reescritura de `rpc_registrar_*_bodega` con FIFO queda para sprint UI.
