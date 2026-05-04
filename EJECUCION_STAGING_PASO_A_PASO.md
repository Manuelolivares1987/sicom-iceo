# Ejecución Staging — Guía paso a paso

> **Última actualización:** 2026-05-02 — FASE 5.7
> **Audiencia:** administrador (Manuel) + DBA (si aplica) + Finanzas (validación costos).
> **Tiempo estimado total:** 15-20 horas distribuidas en 2-3 días.

---

## Pre-requisito: tener un Supabase staging

### Si NO existe

1. **Crear proyecto nuevo en Supabase:**
   - https://app.supabase.com → New project.
   - Nombre: `sicom-iceo-staging`.
   - Database password: anotar en lugar seguro.
   - Region: misma que producción (latencia consistente).
   - Plan: Free tier suficiente.

2. **Obtener credenciales:**
   - Settings → API → URL del proyecto.
   - Settings → API → `anon public` key.
   - Settings → Database → Connection string (modo `URI`) — para psql.

3. **Aplicar mig 01-51 (legacy):**
   - SQL Editor → ejecutar cada migración en orden numérico.
   - Esperar que termine cada una antes de la siguiente.
   - Estimación: 30-45 minutos.

4. **Importar datos críticos desde producción:**
   ```bash
   # Desde producción
   pg_dump --data-only --schema=public \
     -t contratos -t faenas -t marcas -t modelos -t activos \
     -t bodegas -t productos -t combustible_estanques \
     -t usuarios_perfil \
     $DB_PROD > /tmp/datos_base_prod.sql

   # A staging
   psql $DB_STAGING < /tmp/datos_base_prod.sql
   ```

   **Alternativa más simple:** crear datos sintéticos manualmente (5-10 activos, 1-2 contratos, 5 productos, 1 bodega, 1 estanque). Suficiente para tests funcionales.

---

## Configurar frontend para apuntar a staging

```bash
cd frontend

# Backup de configuración actual
cp .env.local .env.local.production-backup

# Editar .env.local con credenciales de staging
# NEXT_PUBLIC_SUPABASE_URL=<URL-staging>
# NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key-staging>

# Reiniciar dev server
npm run dev
```

> ⚠️ **Crítico:** si por error el `.env.local` queda apuntando a producción durante los scripts de staging, **modificarás producción**. Verifica con un `SELECT current_database()` antes de cada ejecución.

---

## Ejecución de scripts

Todos los archivos están en `database/staging/`. Ejecutar **en orden**:

### Paso 0 — README

Leer `database/staging/00_README_STAGING.md` antes de tocar nada.

### Paso 1 — Prechecks SAFE

```bash
# Vía SQL Editor: copiar contenido de 01_prechecks_safe.sql, pegar, Run.
# Vía psql:
psql $DB_STAGING -f database/staging/01_prechecks_safe.sql
```

**Captura recomendada:** screenshot de los resultados de las 10 queries para registro.

**Si falla algo aquí:** detenerse. La base no tiene la estructura legacy esperada.

### Paso 2 — Aplicar mig 55 (Bodega + Combustible base)

```bash
psql $DB_STAGING -f database/staging/03_apply_mig55_bodega_combustible_base.sql
```

**Verificar al final:** sale `TABLAS_NUEVAS_CREADAS = 11` y `FUNCIONES_FOLIO = 5`.

### Paso 3 — Seed datos maestros

```bash
psql $DB_STAGING -f database/staging/02_seed_datos_maestros.sql
```

**Verificar:** `PROVEEDORES_ACTIVOS` muestra al menos 4 combustible. `CECO_ACTIVOS` muestra al menos 8.

### Paso 4 — Validar mig 55

```bash
psql $DB_STAGING -f database/staging/04_validate_mig55.sql
```

**Verificar logs:** debe imprimir `TEST OK` y `TEST COMPLETADO`. Si dice `TEST OMITIDO`, faltan datos maestros (volver al Paso 3).

### Paso 5 — Aplicar mig 56 (FIFO)

```bash
psql $DB_STAGING -f database/staging/05_apply_mig56_fifo.sql
```

**Verificar:** `TABLAS_FIFO = 2`, `COLUMNAS_OT_MAT_FIFO = 5`, `FN_FIFO = 1`, `VISTA_STOCK_FIFO = 1`.

### Paso 6 — Sembrar capas iniciales FIFO

**Importante:** este paso es manual e iterativo.

1. Ejecutar prechecks del archivo:
   ```bash
   psql $DB_STAGING -c "$(sed -n '1,/-- ── 4./p' database/staging/06_seed_capas_iniciales_fifo.sql)"
   ```

2. Si `PRODUCTOS_SIN_COSTO > 0`:
   - Listar y coordinar con Finanzas.
   - Actualizar `stock_bodega.costo_promedio` o filtrar en el INSERT.

3. **Descomentar el INSERT del archivo** (líneas entre `/*` y `*/`).

4. Ejecutar el archivo completo:
   ```bash
   psql $DB_STAGING -f database/staging/06_seed_capas_iniciales_fifo.sql
   ```

5. Verificar reconciliación: `RECONCILIACION_FIFO = 0`.

### Paso 7 — Validar FIFO

```bash
psql $DB_STAGING -f database/staging/07_validate_fifo.sql
```

**Verificar logs:**
- `TEST 1 OK` (1 unidad → $10.000)
- `TEST 2 OK` (1 unidad → $14.000)
- `TEST 3 OK` (2 unidades → $24.000)
- `TEST 4 OK` (stock insuficiente)
- `RECONCILIACION_POST_TEST = 0`

### Paso 8 — Aplicar mig 57 (Combustible CPP)

```bash
psql $DB_STAGING -f database/staging/08_apply_mig57_combustible_cpp.sql
```

**Verificar:** `TABLAS_57 = 2`, `COLUMNAS_ESTANQUES_CPP = 2`, `RPC_STOCK_INICIAL = 1`.

### Paso 9 — Stock inicial combustible

**Iterativo y crítico**:

1. Listar estanques con `09_seed_stock_inicial_combustible.sql` query (1).

2. **Coordinar con Finanzas**:
   - Litros físicos por estanque (varillaje del día).
   - Costo histórico $/lt validado.

3. **Editar el archivo** descomentando las llamadas y ajustando valores reales para cada estanque.

4. Ejecutar.

5. Verificar con `v_combustible_stock_valorizado_actual`.

### Paso 10 — Validar combustible CPP

```bash
psql $DB_STAGING -f database/staging/10_validate_combustible_cpp.sql
```

**Verificar logs:**
- `TEST 1 OK` (stock 1.000 lt @ $900)
- `TEST 2 OK` (ingreso → CPP $966,67)
- `TEST 3 OK` (salida 500 lt)
- Reconciliación: pares coinciden

### Paso 11 — Validar roles

```bash
psql $DB_STAGING -f database/staging/11_validate_roles_dashboards.sql
```

**Verificar:** los 3 usuarios piloto aparecen, faenas asignadas, eventos auditoría > 0.

### Paso 12 — GO/NO GO

Abrir `database/staging/12_go_no_go_checklist.md`. Marcar cada checkbox. Decidir.

---

## Cómo registrar resultados

Para cada paso:

1. **Screenshot** del resultado de las queries de verificación.
2. **Anotar en bitácora** del archivo `12_go_no_go_checklist.md` (sección "Bitácora de ejecución"):
   - Fecha
   - Script
   - Resultado (OK / FALLA)
   - Observaciones
   - Responsable

3. **Si falla un paso:** capturar error completo (mensaje + número línea SQL) y crear archivo `staging_error_<paso>_<fecha>.txt` en local.

---

## Qué hacer si falla un paso

### Error A — "relation does not exist"
Falta una migración previa. Volver a `01_prechecks_safe.sql` y validar.

### Error B — "duplicate key value"
La tabla ya existe con datos. Verificar si ya se aplicó este script. Si sí, no es error (idempotente).

### Error C — "foreign key violation"
Faltan datos maestros (proveedor, CECO, bodega). Ejecutar `02_seed_datos_maestros.sql`.

### Error D — RPC falla con "Rol % no autorizado"
El usuario que ejecuta no tiene rol `administrador` en `usuarios_perfil`. Loguearse con admin o usar service_role temporalmente para staging.

### Error E — TEST FALLO en validación
Capturar el valor reportado vs esperado. Si la diferencia es decimal (centavos), revisar redondeo. Si es magnitud, hay un bug que debe investigarse antes de continuar.

---

## Cómo volver atrás en staging

Cada `0X_apply_*.sql` tiene una sección **ROLLBACK MANUAL** comentada al final.

Para un rollback completo:

```sql
-- ATENCION: destructivo. Usar solo en staging.
-- En orden inverso:

-- 13. Si aplicaste mig 52 Block A:
DROP FUNCTION IF EXISTS rpc_ficha_activo_publica CASCADE;
DROP VIEW IF EXISTS public_activos_qr;
ALTER TABLE activos DROP COLUMN IF EXISTS qr_publico_habilitado;

-- 8-10. Mig 57:
DROP VIEW IF EXISTS v_combustible_stock_valorizado_actual;
DROP FUNCTION IF EXISTS rpc_registrar_stock_inicial_combustible CASCADE;
DROP TABLE IF EXISTS combustible_kardex_valorizado CASCADE;
DROP TABLE IF EXISTS combustible_stock_inicial CASCADE;
ALTER TABLE combustible_estanques
    DROP COLUMN IF EXISTS costo_promedio_lt,
    DROP COLUMN IF EXISTS valor_total_stock;

-- 5-7. Mig 56:
DROP VIEW IF EXISTS v_stock_valorizado_fifo;
DROP FUNCTION IF EXISTS fn_consumir_inventario_fifo CASCADE;
DROP TABLE IF EXISTS inventario_consumos_capas CASCADE;
DROP TABLE IF EXISTS inventario_capas CASCADE;
ALTER TABLE ot_materiales_planeados
    DROP COLUMN IF EXISTS costo_unitario_real,
    DROP COLUMN IF EXISTS costo_total_real,
    DROP COLUMN IF EXISTS metodo_costeo,
    DROP COLUMN IF EXISTS salida_bodega_id,
    DROP COLUMN IF EXISTS ceco_id;

-- 3-4. Mig 55:
DROP TABLE IF EXISTS despachos_combustible CASCADE;
DROP TABLE IF EXISTS salidas_combustible CASCADE;
DROP TABLE IF EXISTS ingresos_combustible CASCADE;
DROP TABLE IF EXISTS salidas_bodega_items CASCADE;
DROP TABLE IF EXISTS salidas_bodega CASCADE;
DROP TABLE IF EXISTS recepciones_bodega_items CASCADE;
DROP TABLE IF EXISTS recepciones_bodega CASCADE;
DROP TABLE IF EXISTS ordenes_compra_items CASCADE;
DROP TABLE IF EXISTS ordenes_compra CASCADE;
DROP TABLE IF EXISTS centros_costo CASCADE;
DROP TABLE IF EXISTS proveedores CASCADE;

-- Funciones folio
DROP FUNCTION IF EXISTS fn_generar_folio_recepcion_bodega();
DROP FUNCTION IF EXISTS fn_generar_folio_salida_bodega();
DROP FUNCTION IF EXISTS fn_generar_folio_ingreso_combustible();
DROP FUNCTION IF EXISTS fn_generar_folio_salida_combustible();
DROP FUNCTION IF EXISTS fn_generar_folio_despacho_combustible();

-- Sequences
DROP SEQUENCE IF EXISTS seq_folio_recepcion_bodega;
DROP SEQUENCE IF EXISTS seq_folio_salida_bodega;
DROP SEQUENCE IF EXISTS seq_folio_ingreso_combustible;
DROP SEQUENCE IF EXISTS seq_folio_salida_combustible;
DROP SEQUENCE IF EXISTS seq_folio_despacho_combustible;

-- Enums
DROP TYPE IF EXISTS estado_oc_enum CASCADE;
DROP TYPE IF EXISTS estado_oc_item_enum CASCADE;
DROP TYPE IF EXISTS tipo_salida_bodega_enum CASCADE;
DROP TYPE IF EXISTS tipo_proveedor_enum CASCADE;
DROP TYPE IF EXISTS tipo_documento_proveedor_enum CASCADE;
DROP TYPE IF EXISTS tipo_salida_combustible_enum CASCADE;
DROP TYPE IF EXISTS estado_despacho_combustible_enum CASCADE;
```

---

## Cuando staging esté GO → preparar producción

1. **Restaurar `.env.local`** apuntando a producción:
   ```bash
   cd frontend
   cp .env.local.production-backup .env.local
   ```

2. **Backup completo de producción** (snapshot Supabase + dump SQL).

3. **Seguir `PLAN_PASO_PRODUCCION_CONTROLADO.md`** estrictamente.

4. **NO usar los scripts de staging directamente** en producción. Adaptar bloques específicos según el plan.

---

## Checklist final antes de ir a producción

- [ ] Staging GO (todos los checkboxes de `12_go_no_go_checklist.md`).
- [ ] Frontend probado contra staging (login con 5 roles).
- [ ] Reconciliaciones FIFO + combustible: ambas en 0 desincronizaciones.
- [ ] Backup snapshot Supabase confirmado.
- [ ] Dump SQL local guardado.
- [ ] Comunicación pre-deploy enviada a usuarios.
- [ ] Ventana acordada con stakeholders.
- [ ] Plan de rollback claro.
- [ ] Costos validados por Finanzas.
- [ ] Disponibilidad confirmada del responsable durante la ventana.

→ Si **TODOS** marcados, **GO a producción**. Si alguno no, **detener**.
