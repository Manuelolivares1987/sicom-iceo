# FASE 5 — DEPLOY EN NETLIFY DESDE GITHUB

## Repositorio GitHub

**URL:** https://github.com/Manuelolivares1987/sicom-iceo
**Visibilidad:** Pública (para revisión por otra IA)

---

## 1. CONECTAR NETLIFY CON GITHUB

### Paso a paso:

1. Ve a [app.netlify.com](https://app.netlify.com)
2. Click **"Add new site"** > **"Import an existing project"**
3. Selecciona **GitHub**
4. Autoriza Netlify si es la primera vez
5. Busca y selecciona el repo **`sicom-iceo`**
6. Configura el build:

| Campo | Valor |
|-------|-------|
| Branch to deploy | `main` |
| Base directory | `frontend` |
| Build command | `npm run build` |
| Publish directory | `frontend/.next` |

7. Click **"Deploy site"**

### Variables de entorno en Netlify:

Ve a **Site settings** > **Environment variables** > **Add variable**:

| Variable | Valor |
|----------|-------|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://gvmaucxgjnrxvgleyklf.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` (tu key completa) |

---

## 2. PLUGIN NEXT.JS PARA NETLIFY

El archivo `frontend/netlify.toml` ya está configurado:

```toml
[build]
  command = "npm run build"
  publish = ".next"

[[plugins]]
  package = "@netlify/plugin-nextjs"
```

Este plugin permite:
- Rutas dinámicas (`/dashboard/ordenes-trabajo/[id]`)
- API routes (si se necesitan en el futuro)
- ISR (Incremental Static Regeneration)
- Image optimization

---

## 3. DOMINIO PERSONALIZADO (Opcional)

1. En Netlify: **Domain management** > **Add custom domain**
2. Ingresa: `sicom.pilladoempresas.cl` (o el que prefieras)
3. Configura DNS en tu proveedor:
   - CNAME: `sicom` → `tu-sitio.netlify.app`
   - O: A record → IP de Netlify
4. Netlify genera certificado SSL automáticamente

---

## 4. ESTRATEGIA DE AMBIENTES

| Ambiente | Branch | URL | Supabase |
|----------|--------|-----|----------|
| Producción | `main` | sicom.pilladoempresas.cl | proyecto prod |
| Staging | `staging` | staging--sicom.netlify.app | proyecto staging |
| Preview | PR branches | deploy-preview-N.netlify.app | proyecto dev |

Para habilitar:
- Netlify genera automáticamente **deploy previews** para cada Pull Request
- Crear branch `staging` para ambiente de pruebas

---

## 5. SEGURIDAD

### Ya implementado:
- `.env.local` en `.gitignore` (no se sube a GitHub)
- Variables de entorno solo en Netlify (no en código)
- RLS en Supabase (Row Level Security por rol)
- Auth con Supabase (tokens JWT)

### Recomendaciones adicionales:
- Habilitar **MFA** en Supabase dashboard
- Configurar **allowed redirect URLs** en Supabase Auth settings
- Agregar el dominio de Netlify a **Site URL** en Supabase Auth
- Revisar **CORS** en Supabase si hay problemas de acceso
- Considerar **rate limiting** en Supabase Edge Functions

---

## 6. CI/CD AUTOMÁTICO

Con la conexión GitHub → Netlify:
- Cada `push` a `main` → deploy automático a producción
- Cada Pull Request → deploy preview con URL única
- Build logs visibles en Netlify dashboard
- Rollback instantáneo a cualquier deploy anterior

---

*Documento generado para SICOM-ICEO — Fase 5 — Deploy*
*Versión 1.0 — Marzo 2026*
