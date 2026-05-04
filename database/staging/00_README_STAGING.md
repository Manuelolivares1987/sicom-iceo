# 00 — README STAGING (SICOM-ICEO)

> **CRÍTICO:** Esta carpeta contiene scripts diseñados para ejecutarse contra
> un proyecto Supabase **STAGING**. **NO ejecutar en producción.**

---

## ⚠️ Antes de tocar nada

1. Confirmar que estás conectado a **staging**, no a producción.
2. URL del proyecto staging debe contener `staging` o `dev` en el nombre, o tener un Project Ref distinto al de producción.
3. Cuando abras Supabase SQL Editor, verifica el dropdown del proyecto.
4. Si tienes la mínima duda, **detente** y verifica con el administrador.

---

## Orden de ejecución

| # | Archivo | Tipo | Reversible | Bloqueante si falla |
|---|---|---|---|---|
| 01 | `01_prechecks_safe.sql` | SOLO LECTURA | sí | sí |
| 02 | `02_seed_datos_maestros.sql` | INSERT idempotente | con DELETE manual | no |
| 03 | `03_apply_mig55_bodega_combustible_base.sql` | DDL + RPCs | requiere DROP | sí |
| 04 | `04_validate_mig55.sql` | SOLO LECTURA + tx ROLLBACK | sí | sí |
| 05 | `05_apply_mig56_fifo.sql` | DDL + RPCs (sobrescribe 03) | requiere DROP | sí |
| 06 | `06_seed_capas_iniciales_fifo.sql` | INSERT controlado | con DELETE | sí |
| 07 | `07_validate_fifo.sql` | SOLO LECTURA + tx ROLLBACK | sí | sí |
| 08 | `08_apply_mig57_combustible_cpp.sql` | DDL + RPCs | requiere DROP | sí |
| 09 | `09_seed_stock_inicial_combustible.sql` | Plantilla manual | con DELETE | no |
| 10 | `10_validate_combustible_cpp.sql` | SOLO LECTURA + tx ROLLBACK | sí | sí |
| 11 | `11_validate_roles_dashboards.sql` | SOLO LECTURA | sí | no |
| 12 | `12_go_no_go_checklist.md` | DOC final | — | — |
| 13 | `13_optional_mig52_blockA_qr_publico.sql` | Opcional | requiere DROP | no |

---

## Cómo conectarse a Supabase staging

### Opción A — SQL Editor del panel
1. https://app.supabase.com → seleccionar **proyecto staging** (NO producción).
2. SQL Editor → New query → pegar contenido de cada archivo en orden.
3. Antes de "Run", **revisar el contenido** y confirmar que aplica.

### Opción B — psql desde local
```bash
# Obtener connection string desde Supabase → Project Settings → Database → URI
export DATABASE_URL='postgresql://postgres:<password>@<host>:5432/postgres'

# Verificar a qué proyecto apunta
psql $DATABASE_URL -c "SELECT current_database(), current_user;"

# Ejecutar script
psql $DATABASE_URL -f database/staging/01_prechecks_safe.sql
```

---

## Cómo validar cada paso

Cada script `0X_validate_*.sql` se diseña para correrse **DESPUÉS** del `0X_apply_*.sql` correspondiente. La validación devuelve filas que deben coincidir con valores esperados documentados en cada archivo.

**Formato sugerido para registrar resultados:**

```
[fecha] [archivo] [resultado] [observación]
2026-05-XX 01_prechecks_safe.sql OK Tablas base presentes
2026-05-XX 03_apply_mig55... OK 9 tablas creadas
2026-05-XX 04_validate_mig55.sql OK Folio formato REC-YYYYMM-XXXXX
...
```

---

## Qué NO ejecutar en producción

- 🚫 Cualquier archivo de `database/staging/` aplicado a un proyecto Supabase de producción **destruirá la coherencia** del costeo si los datos legacy no se migraron previamente.
- 🚫 Para producción usar `PLAN_PASO_PRODUCCION_CONTROLADO.md` que tiene su propio orden + backup obligatorio + ventana de mantención.
- 🚫 Mig 52 Blocks B/C/D **no aplicar** (ni en staging ni en prod) sin auditoría de seguridad adicional. Solo está disponible Block A (vista QR pública).

---

## Si algo falla

1. **STOP.** No continúes con el siguiente script.
2. Capturar el error completo (mensaje + número de línea SQL).
3. Verificar el script de validación inmediatamente anterior — ¿pasó?
4. Si el error es por dato faltante: registrar y consultar antes de ajustar.
5. Si el error es por DDL conflictivo: usar el script de rollback documentado al final de cada `0X_apply_*.sql`.

---

## Responsabilidades

| Rol | Responsabilidad |
|---|---|
| Administrador (Manuel) | Ejecutar scripts, validar GO/NO-GO |
| DBA / desarrollador | Revisar SQL, ajustar si surge error |
| Finanzas | Validar costos históricos antes de seed FIFO y stock inicial combustible |
| Bodeguero (Gustavo) | Probar flujos OC + recepción + salida (cuando staging esté listo) |
| Operador abastecimiento | Probar ingreso/salida combustible (cuando staging esté listo) |

---

## Resultado esperado al terminar staging

- 9 tablas nuevas creadas (proveedores, CECO, OC, recepciones, salidas bodega, ingresos/salidas/despachos combustible, capas FIFO, consumos, stock inicial combustible, kardex valorizado).
- 6+ RPCs nuevas funcionando.
- 7 vistas para Finanzas operativas.
- Stock legacy sembrado como capas iniciales FIFO.
- Stock combustible inicial registrado por estanque.
- Tests funcionales 1-20 pasaron (ver `12_go_no_go_checklist.md`).
- Frontend conectado a staging compila y muestra dashboards por rol.

→ Si todo OK, **se puede planificar deploy a producción** con `PLAN_PASO_PRODUCCION_CONTROLADO.md`.
