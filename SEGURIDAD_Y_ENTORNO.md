# SEGURIDAD Y ENTORNO — SICOM-ICEO

> **Última actualización:** 2026-04-28 — FASE 2
> **Resultado:** ✅ Sin secretos versionados. Sin uso de service role key en frontend.

---

## 1. Variables de entorno detectadas en código

> Se documentan **nombres y ubicaciones**. **No se leyeron ni mostraron valores reales.**

| Variable                              | Tipo                       | Ubicación                                                         | Riesgo si se filtra |
| ------------------------------------- | -------------------------- | ----------------------------------------------------------------- | ------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`            | Pública (cliente)          | `frontend/src/lib/supabase.ts:3`                                  | Bajo (URL pública del proyecto Supabase) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY`       | Pública (cliente)          | `frontend/src/lib/supabase.ts:4`                                  | Bajo si **RLS** está activo (la anon key está diseñada para ser pública) |
| `NODE_ENV`                            | Builtin Next.js / Node     | `frontend/next.config.js:4`, `frontend/src/app/dashboard/admin/page.tsx:465` | No aplica |

**Total de variables únicas referenciadas en código frontend: 3.**

---

## 2. Variables esperadas en `.env.local` (mínimo viable)

```
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-public-key>
```

→ `.env.example` creado en `frontend/.env.example` con esa plantilla **sin valores reales**.

### Variables que **NO** deben aparecer en frontend

| Variable                          | Por qué                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| `SUPABASE_SERVICE_ROLE_KEY`       | Bypass de RLS. Solo backend (Edge Functions / scripts seguros). |
| `SUPABASE_JWT_SECRET`             | Permite firmar tokens arbitrarios.                              |
| Cualquier API key sin prefijo `NEXT_PUBLIC_` | Quedaría expuesta si se referencia desde código cliente. |

→ Se buscó `SERVICE_ROLE`, `service_role`, `service-role`, `SUPABASE_SERVICE` en todo el código fuente. **0 referencias en frontend.** Las únicas ocurrencias son:
- `database/schema/05_funciones_triggers_rls.sql` — comentarios y `GRANT` SQL (es el rol Postgres, no la key).
- `docs/FASE-1-PROPUESTA-FUNCIONAL.md:1003` — referencia documental aclarando "solo edge functions".

---

## 3. Riesgos encontrados y resolución

| ID  | Gravedad | Riesgo                                                                                  | Estado    | Acción aplicada |
| --- | -------- | --------------------------------------------------------------------------------------- | --------- | --------------- |
| S01 | Bajo     | `frontend/.gitignore` minimalista: faltaba `.env`, `.env.production`, `.env.development`, `.DS_Store`, `Thumbs.db`, `.vscode/`, `.idea/`, archivos `sw.js`/`workbox-*` generados por PWA. | ✅ Resuelto | `.gitignore` reescrito completo y autosuficiente. |
| S02 | Bajo     | No existía `.env.example` → onboarding y despliegue dependían de conocimiento tribal.  | ✅ Resuelto | `frontend/.env.example` creado. |
| S03 | Medio    | `frontend/src/lib/supabase.ts` silenciaba la falta de env vars con fallback `placeholder.supabase.co` → en navegador, fallos de configuración aparecían como errores 404/network confusos. | ✅ Resuelto | Agregado `console.error` que se dispara solo en `typeof window !== 'undefined'` cuando faltan vars. Mantiene el placeholder para que `next build` no rompa al pre-renderizar páginas estáticas que no usan Supabase. |
| S04 | Bajo     | Carpeta `.next/` huérfana en raíz del repo (`C:\Users\Manuel Olivares\sicom-iceo\.next/`) con 2 archivos `trace`/`trace-build` viejos del 2026-04-11. | ⚠️ Pendiente (acción manual) | NO versionada (gitignore raíz cubre `.next/`). Solo ensucia árbol local. Ver §6. |
| S05 | Bajo     | Carpeta `public/` en raíz del repo (no en `frontend/public`) con `images/` vacía o casi vacía. | ⚠️ Pendiente (acción manual) | NO versionada. Ver §6. |
| S06 | Medio    | 14 vulnerabilidades reportadas por `npm audit` — todas en herramientas de **build-time**, no afectan runtime cliente. | ⚠️ Documentado, sin fix automático | Ver §5. |
| S07 | Alto     | Sin `middleware.ts` → protección de rutas depende 100% de RLS + redirect cliente. (registrado en FASE 0 como R01) | ⏳ Diferido | A resolver en FASE 4. |

---

## 4. Estado del repositorio (qué se está versionando)

`git ls-files | wc -l` → **231 archivos versionados.**

Verificación con `git ls-files | grep -E '\.next|node_modules|tsbuildinfo|\.env'` → **0 resultados.** ✅

| Patrón                    | Versionado | Estado          |
| ------------------------- | ---------- | --------------- |
| `node_modules/`           | ❌ No      | OK (gitignored) |
| `.next/`                  | ❌ No      | OK              |
| `.env`, `.env.local`, etc.| ❌ No      | OK              |
| `*.tsbuildinfo`           | ❌ No      | OK              |
| `.git/`                   | ❌ No      | OK (siempre)    |
| Archivos PWA (`sw.js`, `workbox-*.js`) | ❌ No | OK (frontend gitignore reforzado) |

---

## 5. `npm audit` — Análisis de vulnerabilidades

**Total:** 14 vulnerabilidades (4 moderate, 10 high). **Todas en build-time tooling**, ninguna en el bundle cliente final.

| Paquete                       | Sev    | Origen                            | Riesgo real en SICOM-ICEO                                   |
| ----------------------------- | ------ | --------------------------------- | ----------------------------------------------------------- |
| `@ducanh2912/next-pwa`        | High   | Directa (vía workbox-build/webpack-plugin) | Solo build. No afecta runtime.                          |
| `eslint-config-next`          | High   | Directa (vía `@next/eslint-plugin-next` → glob)            | Solo dev. No afecta runtime.                                |
| `glob` (10.2.0–10.4.5)        | High   | CLI command injection con flag `-c`/`--cmd` | No usamos el CLI de glob; la lib se importa en build.       |
| `@rollup/plugin-terser`       | High   | Vía workbox-build                 | Solo build.                                                 |
| `lodash` (4.0.0–4.17.23)      | High   | `_.template` injection            | Usado por workbox-build internamente. No invocamos `_.template` con input externo. |
| `serialize-javascript`        | High   | Vía workbox-build                 | Solo build.                                                 |
| `brace-expansion` (<1.1.13)   | Med    | Transitivo                        | ReDoS. Solo build.                                          |
| `exceljs` (>=3.5.0)           | Med    | UUID v3 vulnerability             | Genera UUIDs internamente para archivos Excel. No afecta seguridad del usuario. |
| ... (otros transitivos)       | varios | workbox-build, archive utils      | Solo build.                                                 |

### Decisión

**No se ejecuta `npm audit fix --force`.** Los fixes propuestos son todos **semver-major**:
- `@ducanh2912/next-pwa` → 10.2.6 (downgrade major)
- `eslint-config-next` → 16.2.4 (saltar a Next 16)
- `exceljs` → 3.4.0 (downgrade major; perderíamos features)

Riesgo de breaking changes > beneficio de seguridad real (las vulns son explotables solo con input externo controlado en el pipeline de build, escenario que no aplica aquí).

### Acción recomendada

- ⏳ **Mantener `npm audit` como check informativo en cada release.**
- ⏳ **Actualizar manualmente** cuando next-pwa/eslint-config-next saquen patch en línea con Next 14.
- ⏳ **Considerar migración a Next 15/16** como hito mayor (post-MVP), no durante FASE 2.

---

## 6. Acciones manuales recomendadas (NO ejecutadas — requieren tu confirmación)

### Limpieza de artefactos locales huérfanos

> Ninguno está versionado. Solo ensucian el árbol local.

```bash
# 1. Eliminar carpeta .next/ huérfana en raíz (de un build viejo del 2026-04-11)
rm -rf "C:/Users/Manuel Olivares/sicom-iceo/.next"

# 2. Eliminar carpeta public/ huérfana en raíz si está vacía
ls "C:/Users/Manuel Olivares/sicom-iceo/public"   # confirmar contenido
rm -rf "C:/Users/Manuel Olivares/sicom-iceo/public"   # si confirmaste que está vacía/redundante

# 3. (Opcional) Limpiar build local de frontend antes del próximo deploy
rm -rf "C:/Users/Manuel Olivares/sicom-iceo/frontend/.next"
rm -f  "C:/Users/Manuel Olivares/sicom-iceo/frontend/tsconfig.tsbuildinfo"
```

### Rotación de claves (preventivo)

> No se detectó filtración. Pero **conviene rotar** si tienes dudas:

```
Supabase Dashboard → Project Settings → API
  • Reset anon key (se renueva NEXT_PUBLIC_SUPABASE_ANON_KEY)
  • Reset service_role key (jamás en frontend; solo en Edge Functions / scripts seguros)
```

Después actualizar `.env.local` localmente y las env vars en Netlify.

### Verificación periódica

```bash
cd frontend
npm audit                     # informativo, no aplicar fix --force
npm outdated                  # ver desactualización de deps
```

---

## 7. Checklist antes de desplegar a producción

- [ ] `.env.local` **NO** se versionó (`git ls-files | grep -i env` → debe estar vacío).
- [ ] En Netlify: configurar `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY` en Site settings → Environment variables.
- [ ] **Nunca** configurar `SUPABASE_SERVICE_ROLE_KEY` en Netlify para este sitio (el frontend no lo usa).
- [ ] Verificar que las **políticas RLS** de Supabase estén activas en todas las tablas críticas (FASE 5).
- [ ] Ejecutar `npm run build` localmente antes de cada deploy y revisar warnings.
- [ ] Si rotaste keys: verificar que las nuevas estén tanto en `.env.local` (local) como en Netlify (prod).
- [ ] Revisar que el bucket Storage de Supabase (`46_storage_bucket_verificacion.sql`) tenga policies correctas.

---

## 8. Resultado de FASE 2

✅ **Repositorio limpio de secretos. Sin uso de service role key en frontend. Variables de entorno bien tipadas y documentadas.**

- 3 archivos modificados (gitignore, supabase.ts) + 1 creado (`.env.example`).
- 0 archivos sensibles versionados.
- 14 vulnerabilidades npm documentadas — sin fix automático por riesgo de breaking changes.
- 2 acciones manuales recomendadas para el usuario (limpieza de huérfanos `.next/` y `public/` en raíz).
