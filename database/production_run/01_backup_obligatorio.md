# 01 — Backup obligatorio antes de cualquier mig

> 🛑 **Si no completas este paso, NO ejecutes nada más.**

---

## Opción A — Backup desde Supabase Dashboard (recomendado)

Plan free **no incluye snapshots automáticos retenidos por más de 1 día**. Por lo tanto, antes de ejecutar las migraciones, exportar manualmente.

### A.1 Backup parcial vía SQL Editor (datos críticos)

En Supabase SQL Editor, ejecutar uno por uno y **copiar el JSON resultado** a un archivo local `backup_<tabla>_<fecha>.json`:

```sql
-- Esperar que cada query termine antes de la siguiente.
-- Copiar el resultado a un archivo .json local.

SELECT json_agg(t) FROM (SELECT * FROM usuarios_perfil) t;
SELECT json_agg(t) FROM (SELECT * FROM activos) t;
SELECT json_agg(t) FROM (SELECT * FROM productos) t;
SELECT json_agg(t) FROM (SELECT * FROM bodegas) t;
SELECT json_agg(t) FROM (SELECT * FROM stock_bodega) t;
SELECT json_agg(t) FROM (SELECT * FROM ordenes_trabajo LIMIT 10000) t;
SELECT json_agg(t) FROM (SELECT * FROM movimientos_inventario LIMIT 10000) t;
SELECT json_agg(t) FROM (SELECT * FROM combustible_estanques) t;
SELECT json_agg(t) FROM (SELECT * FROM combustible_movimientos LIMIT 10000) t;
SELECT json_agg(t) FROM (SELECT * FROM auditoria_eventos
                          WHERE created_at >= NOW() - INTERVAL '90 days') t;
```

**Guardar resultados** en carpeta `backup_pre_mig55_<YYYY-MM-DD>/` local.

### A.2 Backup completo vía pg_dump (ALTERNATIVA mejor)

```bash
# 1. Obtener connection string de Supabase Dashboard:
#    Settings → Database → Connection string → URI

export DB_URL='postgresql://postgres:<password>@<host>:5432/postgres'

# 2. Verificar conexión correcta:
psql "$DB_URL" -c "SELECT current_database(), current_user, NOW();"

# 3. Backup esquema + datos (full):
pg_dump --schema=public --no-owner --no-privileges \
        --file=backup_pre_mig55_$(date +%Y%m%d_%H%M%S).sql \
        "$DB_URL"

# 4. Verificar que el archivo existe y tiene tamaño razonable:
ls -lh backup_pre_mig55_*.sql

# 5. Comprimir para ahorrar espacio:
gzip backup_pre_mig55_*.sql
```

> 🟢 **Mejor:** este método captura schema + datos + funciones + triggers en un solo archivo. Ideal para rollback completo.

### A.3 Tablas críticas que el backup DEBE contener

| Tabla | Importancia |
|---|---|
| `usuarios_perfil` | 🔴 Identidad de usuarios |
| `activos` | 🔴 Maestro de equipos |
| `ordenes_trabajo` | 🔴 Operación core |
| `stock_bodega` | 🔴 Inventario actual |
| `productos` | 🔴 Catálogo |
| `bodegas` | 🔴 Estructura logística |
| `movimientos_inventario` | 🔴 Histórico kardex |
| `combustible_estanques` | 🔴 Stock combustible |
| `movimientos_combustible` | 🔴 Histórico combustible |
| `auditoria_eventos` | 🟡 Trazabilidad (puede limitarse a últimos 90 días) |
| `contratos`, `faenas`, `marcas`, `modelos` | 🟡 Maestros operativos |
| `certificaciones` | 🟡 Cumplimiento normativo |
| `verificaciones_disponibilidad` | 🟡 Ready-to-rent |
| `estado_diario_flota` | 🟡 Histórico flota |
| `checklist_templates` | 🟢 Configuración |

---

## Opción B — Snapshot Supabase (plan pago, no aplica acá)

Si en el futuro se sube de plan, usar:
- Project Settings → Database → Backups → Create snapshot.
- Anotar el ID del snapshot.

---

## Evidencia obligatoria

Después de hacer el backup, **registrar evidencia** y guardar:

```
Carpeta local: backup_pre_mig55_<YYYY-MM-DD>/
├── backup_pre_mig55_<YYYY-MM-DD_HHMMSS>.sql.gz       (full pg_dump)
├── screenshot_supabase_dashboard.png                  (proyecto correcto)
├── tamano_backup.txt                                  (ls -lh)
├── responsable.txt                                    (nombre + firma + fecha)
└── README.txt                                         (cómo restaurar)
```

### Plantilla `README.txt`

```
Backup pre-mig55/56/57 SICOM-ICEO
=================================
Fecha:        2026-05-XX HH:MM:SS UTC-04
Proyecto:     <project-ref de supabase>
Database URL: postgresql://...@<host>:5432/postgres
Responsable:  Manuel Olivares
Tamaño:       XXX MB

Cómo restaurar:
1. gunzip backup_pre_mig55_*.sql.gz
2. psql $DB_URL_PROD < backup_pre_mig55_*.sql
3. Verificar SELECT COUNT(*) FROM tablas críticas.
4. Frontend automaticamente vuelve a estado pre-mig (al estar todo el schema
   restaurado).

Notas:
- Este backup NO incluye Storage (fotos, evidencias). Para Storage usar el
  panel de Supabase → Storage → Backups manuales.
- Auth users no están aquí (están en auth.users gestionado por Supabase).
```

---

## Criterio de avance

✅ **Solo avanzar al paso 02 si:**
- [ ] Archivo `.sql.gz` existe localmente.
- [ ] `tamano_backup.txt` muestra > 1 MB (depende del volumen real).
- [ ] Screenshot del proyecto correcto en Supabase guardado.
- [ ] `README.txt` completado.
- [ ] Responsable identificado.

🛑 **Si NO completaste alguno: STOP.** No ejecutes el paso 02.

---

## Plan de rollback (si todo falla más adelante)

```bash
# Restaurar desde el dump:
gunzip backup_pre_mig55_*.sql.gz
psql "$DB_URL_PROD" < backup_pre_mig55_<fecha>.sql

# Esto destruye datos posteriores al backup. Coordinar con usuarios antes.
```

> ⚠️ **El restore destruye los cambios posteriores al backup.** Si pasaron horas con operación nueva, el rollback pierde esa operación. Por eso la ventana debe ser corta y sin uso.
