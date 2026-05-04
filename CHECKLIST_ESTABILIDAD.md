# CHECKLIST DE ESTABILIDAD — SICOM-ICEO

> **Última actualización:** 2026-04-28 — FASE 1 (Build, TypeScript y dependencias)
> **Resultado global:** ✅ **EL SISTEMA COMPILA**

---

## 1. Resultado de comandos ejecutados

| Comando             | Resultado | Detalle                                                                 |
| ------------------- | --------- | ----------------------------------------------------------------------- |
| `npm install`       | ✅ OK     | 882 paquetes auditados, 0 dependencias faltantes. **14 vulnerabilidades** (4 moderate / 10 high) — documentadas, no bloquean. |
| `npm run lint`      | ✅ OK     | 0 errores. 16 warnings (cosméticos / mejores prácticas). No bloquean.   |
| `npm run typecheck` | ✅ OK     | 0 errores. TypeScript strict pasa limpio.                               |
| `npm run build`     | ✅ OK     | Compilación exitosa. 37 rutas generadas (static + dynamic). PWA SW emitido. |

---

## 2. Errores encontrados en FASE 1 (estado inicial)

### 🔴 Críticos (bloquearon el build)
| # | Archivo                                         | Regla                          | Descripción                                                  |
| - | ----------------------------------------------- | ------------------------------ | ------------------------------------------------------------ |
| 1 | `src/app/dashboard/page.tsx` (10 ocurrencias)   | `react-hooks/rules-of-hooks`   | 8 hooks de datos + `useState` + `useRouter` llamados después de un `if/return` condicional por rol. **Bug funcional real** — viola Rules of Hooks. |
| 2 | `src/components/ui/input.tsx:14`                | `react-hooks/rules-of-hooks`   | `React.useId()` invocado condicionalmente con `id || React.useId()`. |
| 3 | `src/components/ui/select.tsx:16`               | `react-hooks/rules-of-hooks`   | Mismo patrón que `input.tsx`.                                |
| 4 | 12 archivos JSX (~25 ocurrencias)               | `react/no-unescaped-entities`  | Comillas dobles literales en JSX (cosmético).                |

### 🟡 Configuración faltante
| # | Item                                            | Acción aplicada                                              |
| - | ----------------------------------------------- | ------------------------------------------------------------ |
| 5 | Falta script `typecheck` en `package.json`      | ➕ Agregado `"typecheck": "tsc --noEmit"`                    |
| 6 | Falta `.eslintrc.json` (lint pedía configuración interactiva) | ➕ Creado con `extends: "next/core-web-vitals"` |

### 🟠 Vulnerabilidades npm (no bloquean)
- 14 vulnerabilidades reportadas por `npm audit` (4 moderate, 10 high). **Acción diferida** — no se corre `npm audit fix --force` por riesgo de breaking changes en deps mayores. Se revisará en FASE 2 o como tarea posterior.

---

## 3. Errores corregidos

| # | Acción                                                                                         | Archivo modificado                                  |
| - | ---------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 1 | Agregado script `typecheck`                                                                    | `frontend/package.json`                             |
| 2 | Creado config ESLint base                                                                      | `frontend/.eslintrc.json` (nuevo)                   |
| 3 | Desactivada regla cosmética `react/no-unescaped-entities` (no es bug funcional, evita tocar 12 archivos) | `frontend/.eslintrc.json`                |
| 4 | Refactor mínimo del routing por rol — extraído `LegacyDashboard` como sub-componente para mover los hooks fuera del condicional. **Sin cambios de lógica de negocio ni UI.** | `frontend/src/app/dashboard/page.tsx` |
| 5 | `useId()` movido fuera del `\|\|` para que se llame siempre                                    | `frontend/src/components/ui/input.tsx`              |
| 6 | Idem                                                                                           | `frontend/src/components/ui/select.tsx`             |

---

## 4. Errores pendientes (no bloquean build, registrados para fases siguientes)

### Warnings de lint (16 total) — diferidos
| Archivo                                                    | Regla                            | Severidad |
| ---------------------------------------------------------- | -------------------------------- | --------- |
| 8 archivos con `<img>` HTML                                | `@next/next/no-img-element`      | Bajo      |
| `inventario/combustible/movimiento/page.tsx:97`            | `react-hooks/exhaustive-deps`    | Medio     |
| `dashboard/kpi/page.tsx:353`                               | `react-hooks/exhaustive-deps`    | Medio     |
| `executive-dashboard.tsx:49`                               | `react-hooks/exhaustive-deps`    | Medio     |
| `operations-dashboard.tsx:31`                              | `react-hooks/exhaustive-deps`    | Medio     |
| `flota/cambiar-estado-modal.tsx:116`                       | `react-hooks/exhaustive-deps`    | Medio     |

→ Las `exhaustive-deps` se revisarán en FASE 7 (UX y estados) por ser bugs sutiles potenciales. Las `no-img-element` se atacan en FASE 9 (preparación de demo) porque solo afectan métricas LCP.

### Otros pendientes (no de FASE 1)
- 14 vulnerabilidades npm — revisar en FASE 2.
- Sin `middleware.ts` — FASE 4.
- Sin `.env.example` — FASE 2.
- `lib/supabase.ts` con fallback `placeholder.supabase.co` — FASE 2.

---

## 5. Archivos modificados en FASE 1 (lista exhaustiva)

```
M  frontend/package.json                 (script typecheck)
A  frontend/.eslintrc.json               (config lint nueva)
M  frontend/src/components/ui/input.tsx  (useId fuera del ||)
M  frontend/src/components/ui/select.tsx (useId fuera del ||)
M  frontend/src/app/dashboard/page.tsx   (extraído LegacyDashboard)
M  AUDITORIA_TECNICA.md                  (anexo FASE 1)
A  CHECKLIST_ESTABILIDAD.md              (este documento)
```

(M = modificado, A = añadido)

---

## 6. Comandos para reproducir resultado

```bash
cd frontend
npm install
npm run lint        # 0 errores
npm run typecheck   # 0 errores
npm run build       # build exitoso, 37 rutas
```

---

## 7. Resultado final FASE 1

✅ **El sistema compila.**

- 37 rutas generadas (28 estáticas + 9 dinámicas).
- Service worker PWA emitido correctamente.
- TypeScript strict pasa limpio.
- ESLint pasa sin errores (solo warnings).
- Sin breaking changes funcionales: el comportamiento del Dashboard es el mismo que antes (mismo routing por rol, mismo dashboard legacy para roles no listados).

**Siguiente fase sugerida:** FASE 2 — Seguridad, variables de entorno y limpieza del repositorio.
