# Ejecución Producción — Guía paso a paso (sin staging)

> **Última actualización:** 2026-05-02 — FASE 5.8
> **Audiencia:** Administrador (Manuel) + Finanzas (validación costos paso 09 y 12).
> **Contexto:** No hay staging disponible. Se ejecuta directamente sobre producción con controles estrictos.

---

## 0. Antes de empezar

### Horario recomendado

| Día | Hora | Razón |
|---|---|---|
| **Sábado o domingo** | **08:00 – 14:00** | Sin actividad operativa, ventana fresca |
| **Buffer** | + 4 horas adicionales | Si el día rebalsa |

Evitar:
- Lunes a viernes en horario laboral.
- Día anterior a cierre de mes.
- Cuando Finanzas no esté disponible (paso 09 y 12 requieren validación).

### Quién debe estar disponible

| Rol | Disponibilidad mínima | Tarea |
|---|---|---|
| Administrador (Manuel) | Toda la ventana (~6 h) | Ejecutar SQL, validar, decidir GO/NO GO |
| Finanzas | 1-2 horas para paso 09 y 12 | Validar costos históricos |
| Bodeguero (Gustavo) | Día lunes mañana | Pruebas funcionales reales (post-deploy) |
| Planificador (Eduardo) | Día lunes mañana | Pruebas funcionales reales (post-deploy) |

### Material previo

- [ ] Carpeta local: `produccion_2026-05-XX/`
- [ ] Acceso a Supabase Dashboard del proyecto producción
- [ ] Acceso a SQL Editor
- [ ] Cliente psql instalado (alternativa)
- [ ] `pg_dump` instalado (para backup)
- [ ] Notebook/cuaderno físico para anotar timestamps
- [ ] Canal de comunicación con Finanzas y usuarios

---

## 1. Backup obligatorio (paso 01)

Seguir las instrucciones de `database/production_run/01_backup_obligatorio.md`.

**Comando rápido (si tienes pg_dump):**

```bash
export DB_URL='postgresql://postgres:<password>@<host>:5432/postgres'
psql "$DB_URL" -c "SELECT current_database(), current_user, NOW();"

pg_dump --schema=public --no-owner --no-privileges \
        --file=backup_pre_mig55_$(date +%Y%m%d_%H%M%S).sql "$DB_URL"

ls -lh backup_pre_mig55_*.sql
gzip backup_pre_mig55_*.sql
```

→ Guardar el archivo `.sql.gz` en `produccion_2026-05-XX/`.

🛑 **Si no tienes backup confirmado, STOP. NO continuar.**

---

## 2. Cómo abrir Supabase SQL Editor

1. https://app.supabase.com
2. Login con tu cuenta admin del proyecto.
3. Seleccionar **proyecto producción**. **Verificar el nombre/ID en la URL.**
4. Sidebar izquierdo → **SQL Editor**.
5. Crear nueva query (`+ New query`).
6. **Verificar siempre antes de ejecutar:**
   ```sql
   SELECT current_database(), current_user, NOW();
   ```

---

## 3. Orden exacto de ejecución

| # | Archivo | Tipo | Tiempo estimado | Pausa después |
|---|---|---|---|---|
| 0 | Ventana sin usuarios | — | — | Confirmar |
| 1 | `01_backup_obligatorio.md` | Manual | 10-30 min | Confirmar archivo `.sql.gz` |
| 2 | `02_prechecks_produccion_safe.sql` | SELECTs | 2 min | Revisar diagnóstico |
| 2A | `02A_hotfix_fn_user_rol.sql` (**solo si paso 2 dice STOP por fn_user_rol**) | DDL función | 30 seg | — |
| 2B | `02B_validate_fn_user_rol.sql` (**si se aplicó 2A**) | SELECTs | 30 seg | Confirmar `OK_FN_USER_ROL` |
| 2C | `02C_debug_fn_user_rol_detection.sql` (**si 2B dice OK pero 02 sigue STOP**) | SELECTs | 30 seg | Confirmar `DETECTED_FN_USER_ROL` |
| 2 v2 | `02_prechecks_produccion_safe_v2.sql` (**si 2C confirmó la función**) | SELECTs | 2 min | Confirmar `PRECHECKS OK` |
| 3 | `03_bitacora_ejecucion.sql` | DDL ligero | 30 seg | — |
| 4 | `04_apply_mig55_produccion.sql` | DDL + funciones | 30-60 seg | Validar logs |
| 5 | `05_validate_mig55_produccion.sql` | SELECTs + ROLLBACK | 30 seg | Confirmar `OK MIG55` |
| 6 | `06_seed_datos_maestros_produccion.sql` | INSERT idempotente | 5 seg | — |
| 7 | `07_apply_mig56_fifo_produccion.sql` | DDL + función FIFO | 30-60 seg | Validar logs |
| 8 | `08_validate_mig56_fifo_produccion.sql` | SELECTs + ROLLBACK | 30 seg | Confirmar `OK MIG56` o `PENDIENTE SEMBRAR CAPAS` |
| 9 | `09_seed_capas_iniciales_fifo_produccion.sql` | **MANUAL con Finanzas** | 30-60 min | Reconciliación = 0 |
| 10 | `10_apply_mig57_combustible_cpp_produccion.sql` | DDL + RPC | 30-60 seg | Validar logs |
| 11 | `11_validate_mig57_combustible_cpp_produccion.sql` | SELECTs + ROLLBACK | 30 seg | Confirmar `OK MIG57` o `PENDIENTE STOCK INICIAL` |
| 12 | `12_seed_stock_inicial_combustible_produccion.sql` | **MANUAL con Finanzas** | 30-60 min | Reconciliación pares coinciden |
| 13 | `13_validate_roles_dashboards_produccion.sql` | SELECTs | 10 seg | Confirmar `OK ROLES` |
| 14 | `14_optional_mig52_blockA_qr_publico_produccion.sql` | **NO EJECUTAR** salvo decisión | — | — |
| 15 | `15_checklist_go_no_go_produccion.md` | Doc final | 15 min | Decidir GO/NO GO |
| 16 | `16_monitoring_post_deploy.sql` | SELECTs | 1 min | Ejecutar a 1h, 24h, 7d |

---

## 4. Detalle por paso

### Paso 2 — Prechecks (CRÍTICO)

```
Copiar contenido de: database/production_run/02_prechecks_produccion_safe.sql
Pegar en SQL Editor → Run
```

**Resultado esperado al final:**
- Query (1) `current_database` muestra el proyecto producción.
- Query (2) `BASE_LEGACY` muestra 25 tablas.
- Query (3) `TABLAS_NUEVAS` muestra 0 (idealmente).
- Query (4) `FUNCIONES_BASE` muestra 6.
- Query (13) `DIAGNOSTICO` muestra `PRECHECKS OK` o `WARNING ...`.

🛑 Si dice `STOP — falta función fn_user_rol`: **NO continuar al paso 03**.
   1. Aplicar **hotfix mínimo**: ejecutar `02A_hotfix_fn_user_rol.sql`.
   2. Validar: ejecutar `02B_validate_fn_user_rol.sql` → debe devolver `OK_FN_USER_ROL`.
   3. **Volver a ejecutar** `02_prechecks_produccion_safe.sql`.
   4. ⚠️ **Si el original SIGUE diciendo STOP a pesar de que 02B devolvió OK** (bug conocido en query 13: busca en `information_schema.tables` lo que es una función):
      - Ejecutar `02C_debug_fn_user_rol_detection.sql` para confirmar — debe devolver `DETECTED_FN_USER_ROL`.
      - Usar `02_prechecks_produccion_safe_v2.sql` (versión corregida) en lugar del original.
      - Re-ejecutar v2 — debe devolver `PRECHECKS OK` (o `WARNING`).
   5. Solo entonces avanzar al paso 03.

⚠️ Si dice `WARNING — productos con stock sin costo`: anotar, decidir en paso 09.
⚠️ Si dice `WARNING — estanques con stock`: anotar, decidir en paso 12.

**Captura:** screenshot del resultado completo. Guardar como `produccion_2026-05-XX/02_prechecks.png`.

---

### Paso 3 — Bitácora

```
Copiar y ejecutar: 03_bitacora_ejecucion.sql
```

Crea `operacion_migraciones_log` y registra `PROD_INICIO`. Sin riesgo.

---

### Paso 4 — Aplicar mig 55

```
Copiar y ejecutar: 04_apply_mig55_produccion.sql
```

**Esperar:** 30-60 segundos. Si Supabase muestra "Query timeout", reintentar.

**Resultado esperado:**
- `TABLAS_CREADAS = 11`
- `FUNCIONES_FOLIO = 5`
- Log `PROD_MIG55_END` con `resultado = ok`.

🛑 Si falla con `ERROR: ... fn_user_rol does not exist`: faltó mig 31. **STOP.**
🛑 Si falla con `relation "X" already exists`: alguien aplicó parcialmente antes. Investigar antes de continuar.

**Captura:** screenshot del resultado.

---

### Paso 5 — Validar mig 55

```
Copiar y ejecutar: 05_validate_mig55_produccion.sql
```

**Resultado esperado:**
- `TABLAS_55 = 11`
- 5 folios distintos generados.
- `RAISE NOTICE Test escritura proveedores: OK` y `Test rollback: OK`.
- Resultado final: `OK MIG55`.

🛑 Si dice `STOP MIG55`: **NO continuar al paso 6**. Investigar.

---

### Paso 6 — Seed maestros

```
Copiar y ejecutar: 06_seed_datos_maestros_produccion.sql
```

**Esperado:** ≥3 proveedores combustible, ≥8 CECOs.

---

### Paso 7 — Aplicar mig 56 FIFO

```
Copiar y ejecutar: 07_apply_mig56_fifo_produccion.sql
```

**Resultado esperado:**
- `TABLAS_FIFO = 2`
- `FN_FIFO = 1`
- Log `PROD_MIG56_END = ok`.

---

### Paso 8 — Validar mig 56

```
Copiar y ejecutar: 08_validate_mig56_fifo_produccion.sql
```

Resultado posible:
- `OK MIG56 — PENDIENTE SEMBRAR CAPAS (paso 09)` → **aceptable** previo a 09. Continuar.
- `OK MIG56` → si ya hubo capas (raro en primera ejecución).
- `STOP MIG56` → **NO continuar**.

---

### Paso 9 — Sembrar capas iniciales (con Finanzas)

🟡 **Pausa obligatoria. Coordinar con Finanzas.**

1. Ejecutar query (1) del archivo `09_seed_capas_iniciales_fifo_produccion.sql` para listar productos.
2. Ejecutar query (2) — si `cantidad > 0` (productos sin costo): **detener antes del INSERT**.
   - Opciones:
     - **Finanzas completa `costo_promedio` en `stock_bodega`** → `UPDATE stock_bodega SET costo_promedio=<X> WHERE producto_id='<UUID>' AND bodega_id='<UUID>';`
     - O excluir esos productos del INSERT (filtrar por `costo_promedio > 0`, ya está en la plantilla).
3. Cuando esté validado: descomentar el INSERT del paso 5 del archivo y ejecutar.
4. Verificar reconciliación (sección 6 del archivo): `productos_desincronizados = 0`.

🛑 Si reconciliación > 0: **investigar antes de continuar**.

---

### Paso 10 — Aplicar mig 57

```
Copiar y ejecutar: 10_apply_mig57_combustible_cpp_produccion.sql
```

**Resultado esperado:**
- `TABLAS_57 = 2`
- `COLUMNAS_ESTANQUES_CPP = 2`
- `RPC_STOCK_INICIAL = 1`
- Log `PROD_MIG57_END = ok`.

---

### Paso 11 — Validar mig 57

```
Copiar y ejecutar: 11_validate_mig57_combustible_cpp_produccion.sql
```

Resultado posible:
- `OK MIG57 — PENDIENTE STOCK INICIAL (paso 12)` → aceptable, continuar a 12.
- `OK MIG57` → si ya había stocks iniciales (raro).
- `STOP MIG57` → **NO continuar**.

---

### Paso 12 — Stock inicial combustible (con Finanzas)

🟡 **Pausa obligatoria. Coordinar con Gustavo (varillaje físico) y Finanzas (costo histórico).**

1. Ejecutar query (1) — listar estanques.
2. Para cada estanque con stock > 0 sin stock_inicial:
   - Confirmar litros físicos (varillaje del día).
   - Confirmar costo histórico ($/lt) con Finanzas.
   - Llamar la RPC adaptando los valores. Ejemplo:
     ```sql
     SELECT rpc_registrar_stock_inicial_combustible(
         '<UUID-ESTANQUE>',
         CURRENT_DATE,
         1000.00,
         900.0000,
         NULL,
         'Apertura prod 2026-05-XX. Stock varillaje fisico verificado por Gustavo. Costo Finanzas (ultima compra ENEX guia 12345).'
     );
     ```
3. Verificar query (4) — todos los estanques con `costo_promedio_lt > 0` y `valor_total_stock` coherente.

🛑 Si algún estanque queda con `costo_promedio_lt = 0` y `stock_teorico_lt > 0`: **investigar antes del paso 13**.

---

### Paso 13 — Validar roles

```
Copiar y ejecutar: 13_validate_roles_dashboards_produccion.sql
```

**Esperado:** `resultado = OK ROLES`. Los 3 usuarios críticos activos.

---

### Paso 14 — Mig 52 Block A (OPCIONAL)

🛑 **NO ejecutar** salvo decisión expresa de habilitar QR público en terreno.

Si se decide ejecutar: ver `database/production_run/14_optional_mig52_blockA_qr_publico_produccion.sql`. Recordar **ajustar el frontend** después.

---

### Paso 15 — Completar checklist

Abrir `database/production_run/15_checklist_go_no_go_produccion.md`. Marcar cada checkbox. **Decidir GO/NO GO**.

---

### Paso 16 — Monitoring post deploy

```
Copiar y ejecutar: 16_monitoring_post_deploy.sql
```

A los siguientes momentos:
- **+1 hora** después del último paso ejecutado.
- **+24 horas** después.
- **+7 días** después.

Cada vez, capturar resultados y guardar en `produccion_2026-05-XX/monitoring_<NhX>.png`.

🛑 Cualquier alerta:
- Stock negativo.
- Productos sin capa con stock.
- Estanques sin CPP.
- Folios o guías duplicadas.
- Errores en bitácora.

→ **Investigar inmediatamente.**

---

## 5. Qué hacer si aparece un error

### Error A — `relation "X" already exists`
Alguien ya aplicó parcialmente. Verificar con paso 02 qué tablas existen. Si están todas, saltar al validate. Si están parciales, **detener** y consultar.

### Error B — `permission denied`
El usuario que ejecuta no tiene permisos. Abrir el SQL Editor con el rol correcto.

### Error C — `relation "fn_user_rol" does not exist`
Mig 31 no aplicada. **STOP.** No avanzar. Aplicar mig 31 primero.

### Error D — `RAISE EXCEPTION` durante apply
Anotar el mensaje completo. Probablemente es un check de role en una RPC. Revisar paso de prechecks.

### Error E — Frontend deja de funcionar
Captura inmediata de:
- Consola navegador (F12 → Console).
- Network tab (errores HTTP).
- Captura del dashboard.
Restaurar `.env.local` si fue cambiado.

### Error F — Reconciliación FIFO o combustible falla
Anotar valores reportados. **NO modificar manualmente** stock_bodega ni combustible_estanques. Consultar.

---

## 6. Cuándo detener (criterios STOP)

🛑 Detener inmediatamente si:

- Cualquier query reporta `STOP` en su resultado final.
- `current_database()` no es producción (te conectaste a otro proyecto).
- Algún paso lanza error no esperado.
- Stock se vuelve negativo.
- Login deja de funcionar para algún rol.
- Reconciliación falla post-seed.
- Finanzas no puede validar costos en paso 09 o 12.
- Cualquier intuición de que algo no anda bien.

→ Detener y consultar antes de continuar.

---

## 7. Comunicación a usuarios

### Antes (24h previas)

> *"Estimado equipo: este sábado/domingo entre 08:00 y 14:00 aplicaremos mejoras importantes en bodega y combustible: orden de compra formal, costo FIFO de repuestos, costo promedio combustible. Durante esa ventana el sistema estará en mantención. Lunes capacitación para Gustavo y Eduardo. Cualquier consulta, conmigo."*

### Al iniciar

> *"Iniciando mantención. Sistema no disponible 08:00 – 14:00. Aviso al terminar."*

### Al terminar (sistema OK)

> *"Sistema disponible. Capacitación lunes 10:00 (Gustavo, Eduardo). Cualquier problema, contactar inmediatamente al administrador."*

### Si se hace rollback

> *"Mantención reagendada por validación pendiente. Sistema sigue funcionando con flujo actual. Avisaré nueva fecha. Disculpas."*

---

## 8. Checklist final antes de iniciar

- [ ] Leí todo este documento completo.
- [ ] Backup confirmado.
- [ ] No hay usuarios activos en el sistema.
- [ ] Finanzas disponible para paso 09 y 12.
- [ ] Tengo 6 horas continuas.
- [ ] Carpeta local creada para evidencia.
- [ ] `current_database()` apunta a producción confirmado.
- [ ] Ventana acordada y comunicada a usuarios.

→ Si **TODOS** marcados, iniciar. Si alguno no, **detener** y resolver primero.
