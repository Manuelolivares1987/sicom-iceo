# FASE 2 — DISEÑO DE BASE DE DATOS SUPABASE/POSTGRESQL

## Sistema Integral de Control Operacional, Mantenimiento, Inventario e ICEO (SICOM-ICEO)

---

## 1. ESTRUCTURA DE ARCHIVOS SQL

Los scripts se ejecutan en orden secuencial:

| # | Archivo | Contenido | Tamaño |
|---|---------|-----------|--------|
| 1 | `01_tipos_y_enums.sql` | Extensiones + 19 tipos ENUM | 6 KB |
| 2 | `02_tablas_core.sql` | 11 tablas maestras + triggers updated_at | 18 KB |
| 3 | `03_tablas_ot_inventario.sql` | 9 tablas OT + inventario + triggers folio/estado | 19 KB |
| 4 | `04_tablas_kpi_iceo_compliance.sql` | 13 tablas KPI, ICEO, compliance, auditoría | 22 KB |
| 5 | `05_funciones_triggers_rls.sql` | Funciones de negocio, triggers, políticas RLS | 64 KB |
| 6 | `06_funciones_kpi_iceo.sql` | 21 funciones KPI + calculador ICEO + CPP | 54 KB |
| 7 | `07_seed_data.sql` | Datos semilla realistas minería chilena | 33 KB |

**Total: ~216 KB de SQL, 33 tablas, 19 enums, 21+ funciones, 29 políticas RLS**

---

## 2. DIAGRAMA ENTIDAD-RELACIÓN

### 2.1 Vista General (Agrupado por Dominio)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              DOMINIO CONTRACTUAL                                 │
│                                                                                  │
│  ┌─────────────┐       ┌─────────────┐       ┌──────────────────┐               │
│  │  contratos   │──1:N──│   faenas     │──1:N──│    bodegas       │               │
│  │             │       │             │       │                  │               │
│  │ codigo      │       │ codigo      │       │ codigo           │               │
│  │ cliente     │       │ ubicacion   │       │ tipo (fija/movil)│               │
│  │ SLA (JSON)  │       │ region      │       │ responsable_id───┼──┐            │
│  │ obligaciones│       │ coordenadas │       └──────────────────┘  │            │
│  └──────┬──────┘       └──────┬──────┘                              │            │
│         │                     │                                      │            │
│         │              ┌──────┴──────┐                               │            │
│         └──────────────│configuracion│                               │            │
│                        │   _iceo     │                               │            │
│                        │ pesos_area  │                               │            │
│                        │ umbrales    │                               │            │
│                        └─────────────┘                               │            │
└──────────────────────────────────────────────────────────────────────┼────────────┘
                                                                       │
┌──────────────────────────────────────────────────────────────────────┼────────────┐
│                            DOMINIO USUARIOS                          │            │
│                                                                      ▼            │
│  ┌──────────────────┐      ┌──────────────────┐                                  │
│  │   auth.users      │──1:1──│ usuarios_perfil  │                                  │
│  │   (Supabase)      │      │                  │                                  │
│  │                   │      │ nombre_completo  │                                  │
│  │                   │      │ rut              │                                  │
│  │                   │      │ rol (ENUM)       │                                  │
│  │                   │      │ faena_id ────────┼──→ faenas                        │
│  │                   │      │ firma_url        │                                  │
│  └───────────────────┘      └──────────────────┘                                  │
└───────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────────┐
│                            DOMINIO ACTIVOS                                        │
│                                                                                   │
│  ┌──────────┐     ┌──────────┐     ┌─────────────────┐                           │
│  │  marcas   │─1:N─│ modelos  │─1:N─│     activos      │                           │
│  │          │     │          │     │                 │                           │
│  │ nombre   │     │ nombre   │     │ codigo (UNIQUE) │                           │
│  └──────────┘     │ tipo_act.│     │ tipo            │                           │
│                   │ espec.   │     │ criticidad      │                           │
│                   └──────────┘     │ estado          │                           │
│                        │           │ km_actual       │                           │
│                        │           │ horas_uso       │                           │
│                        ▼           │ contrato_id ────┼──→ contratos              │
│              ┌─────────────────┐   │ faena_id ───────┼──→ faenas                 │
│              │pautas_fabricante│   │ modelo_id ──────┼──→ modelos                │
│              │                 │   └────────┬────────┘                           │
│              │ items_checklist │            │                                     │
│              │ materiales_est. │            │1:N                                  │
│              │ frecuencia_*   │            │                                     │
│              └────────┬────────┘   ┌───────┴─────────┐                           │
│                       │            │planes_mantenim.  │                           │
│                       └──1:N──────▶│                 │                           │
│                                    │ pauta_fab_id    │                           │
│                                    │ activo_id       │                           │
│                                    │ frecuencia_*    │                           │
│                                    │ prox_ejecucion  │                           │
│                                    └────────┬────────┘                           │
│                                             │                                     │
│              ┌──────────────────┐           │                                     │
│              │ certificaciones   │◀──N:1─────┤                                    │
│              │                  │           │                                     │
│              │ tipo (SEC,SEREMI)│           │                                     │
│              │ fecha_vencim.    │           │                                     │
│              │ bloqueante       │           │                                     │
│              │ estado           │           │                                     │
│              └──────────────────┘           │                                     │
└─────────────────────────────────────────────┼─────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────┼─────────────────────────────────────┐
│                    DOMINIO ÓRDENES DE TRABAJO (EJE CENTRAL)                       │
│                                              │                                     │
│                                    ┌─────────▼──────────┐                         │
│                                    │  ordenes_trabajo    │                         │
│                                    │                    │                         │
│                                    │ folio (OT-YYYYMM-X)│                         │
│         ┌──────────────────────────│ tipo               │──────────────┐          │
│         │                          │ estado             │              │          │
│         │                          │ prioridad          │              │          │
│         │                          │ activo_id ─────────┼──→ activos   │          │
│         │                          │ faena_id           │              │          │
│         │                          │ responsable_id     │              │          │
│         │                          │ plan_mant_id       │              │          │
│         │                          │ costo_total (GEN)  │              │          │
│         │                          │ qr_code (auto)     │              │          │
│         │                          └──┬──────┬──────┬───┘              │          │
│         │                             │      │      │                  │          │
│   ┌─────┴──────────┐   ┌─────────────┴┐  ┌──┴──────┴───┐  ┌──────────┴────┐     │
│   │historial_estado │   │checklist_ot  │  │evidencias_ot│  │movimientos_   │     │
│   │      _ot        │   │              │  │             │  │ inventario    │     │
│   │                 │   │ orden        │  │ tipo        │  │              │     │
│   │ estado_anterior │   │ descripcion  │  │ archivo_url │  │ (ver dominio │     │
│   │ estado_nuevo    │   │ resultado    │  │ metadata    │  │  inventario) │     │
│   │ motivo          │   │ observacion  │  │ (GPS, etc)  │  │              │     │
│   └─────────────────┘   │ foto_url     │  └─────────────┘  └──────────────┘     │
│                          └──────────────┘                                         │
│                                                                                   │
│   ┌─────────────────┐   ┌─────────────────┐                                      │
│   │   incidentes     │   │ rutas_despacho   │                                      │
│   │                 │   │                 │                                      │
│   │ tipo            │   │ fecha_programada│                                      │
│   │ gravedad        │   │ puntos_prog.    │                                      │
│   │ causa_raiz      │   │ km_programados  │                                      │
│   │ ot_id ──────────┼──→│ ot_id           │                                      │
│   └─────────────────┘   └────────┬────────┘                                      │
│                                  │1:N                                             │
│                          ┌───────┴────────┐                                      │
│                          │ abastecimientos │                                      │
│                          │               │                                      │
│                          │ cant_program.  │                                      │
│                          │ cant_real      │                                      │
│                          │ diferencia(GEN)│                                      │
│                          │ mov_inv_id ────┼──→ movimientos_inventario             │
│                          └────────────────┘                                      │
└───────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────────┐
│                       DOMINIO INVENTARIO VALORIZADO                               │
│                                                                                   │
│  ┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐              │
│  │  productos    │     │  stock_bodega     │     │  movimientos_    │              │
│  │              │     │                  │     │  inventario      │              │
│  │ codigo       │─1:N─│ bodega_id        │     │                  │              │
│  │ codigo_barras│     │ producto_id      │     │ tipo (ENUM)      │              │
│  │ categoria    │     │ cantidad         │◀─── │ cantidad         │              │
│  │ unidad_medida│     │ costo_promedio   │ UPD │ costo_unitario   │              │
│  │ costo_actual │     │ valor_total (GEN)│     │ costo_total (GEN)│              │
│  │ stock_min/max│     └──────────────────┘     │ ot_id ───────────┼──→ OT       │
│  │ metodo_valor.│                               │ activo_id        │              │
│  └──────┬───────┘                               │ bodega_id ───────┼──→ bodegas  │
│         │                                       │ lote             │              │
│         │                                       │ usuario_id       │              │
│         │         ┌──────────────────┐          └────────┬─────────┘              │
│         │         │     kardex       │                   │                        │
│         │         │                  │◀── TRIGGER ───────┘                        │
│         │         │ cant_anterior    │                                            │
│         │         │ cant_posterior   │     ┌──────────────────┐                   │
│         │         │ cpp_anterior     │     │conteos_inventario│                   │
│         │         │ cpp_posterior    │     │                  │                   │
│         │         │ valor_stock      │     │ tipo (ciclico/   │                   │
│         │         └──────────────────┘     │  general/select.)│                   │
│         │                                  │ estado           │                   │
│         │                                  └────────┬─────────┘                   │
│         │                                           │1:N                          │
│         │                                  ┌────────┴─────────┐                   │
│         └──────────────────────────────────│ conteo_detalle   │                   │
│                                            │                  │                   │
│                                            │ stock_sistema    │                   │
│  ┌──────────────────┐                      │ stock_fisico     │                   │
│  │ lecturas_pistola │                      │ diferencia (GEN) │                   │
│  │                  │                      │ dif_valorizada   │                   │
│  │ codigo_leido     │                      │ ajuste_aplicado  │                   │
│  │ tipo_lectura     │                      └──────────────────┘                   │
│  │ dispositivo      │                                                             │
│  └──────────────────┘                                                             │
└───────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────────┐
│                          DOMINIO KPI E ICEO                                       │
│                                                                                   │
│  ┌──────────────────┐     ┌──────────────┐     ┌──────────────────┐              │
│  │kpi_definiciones   │─1:N─│ kpi_tramos   │     │  mediciones_kpi  │              │
│  │                  │     │              │     │                  │              │
│  │ codigo (A1..C7)  │     │ rango_min    │     │ kpi_id           │              │
│  │ nombre           │─1:N─│ rango_max    │     │ contrato_id      │              │
│  │ area (ENUM)      │     │ puntaje      │     │ faena_id         │              │
│  │ formula          │     └──────────────┘     │ periodo          │              │
│  │ funcion_calculo  │                          │ valor_medido     │              │
│  │ meta_valor       │──────────────────────────│ puntaje          │              │
│  │ peso             │                          │ valor_ponderado  │              │
│  │ es_bloqueante    │                          │ bloq_activado    │              │
│  │ efecto_bloqueante│                          │ datos_calculo(J) │              │
│  └──────────────────┘                          └────────┬─────────┘              │
│                                                          │                        │
│                                                          │ N:1                    │
│                                                          ▼                        │
│  ┌──────────────────┐                          ┌──────────────────┐              │
│  │  iceo_periodos    │──────────────────────────│  iceo_detalle    │              │
│  │                  │            1:N            │                  │              │
│  │ contrato_id      │                          │ iceo_periodo_id  │              │
│  │ faena_id         │                          │ medicion_kpi_id  │              │
│  │ periodo          │                          │ kpi_codigo       │              │
│  │ puntaje_area_a   │                          │ valor_ponderado  │              │
│  │ puntaje_area_b   │                          │ bloq_activado    │              │
│  │ puntaje_area_c   │                          │ impacto_descrip. │              │
│  │ iceo_bruto       │                          └──────────────────┘              │
│  │ iceo_final       │                                                            │
│  │ clasificacion    │                                                            │
│  │ bloqueantes (J)  │                                                            │
│  │ incentivo_hab.   │                                                            │
│  └──────────────────┘                                                            │
└───────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────────┐
│                       DOMINIO TRANSVERSAL                                         │
│                                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐                │
│  │auditoria_eventos │  │    documentos     │  │     alertas      │                │
│  │                  │  │                  │  │                  │                │
│  │ tabla            │  │ entidad_tipo     │  │ tipo             │                │
│  │ registro_id      │  │ entidad_id       │  │ titulo           │                │
│  │ accion           │  │ nombre           │  │ severidad        │                │
│  │ datos_anteriores │  │ archivo_url      │  │ destinatario_id  │                │
│  │ datos_nuevos     │  │ fecha_vencimiento│  │ leida            │                │
│  │ usuario_id       │  └──────────────────┘  └──────────────────┘                │
│  │ ip_address       │                                                             │
│  └──────────────────┘                                                             │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Relaciones Clave (Resumen)

| Relación | Cardinalidad | Descripción |
|----------|-------------|-------------|
| contrato → faenas | 1:N | Un contrato tiene múltiples faenas |
| faena → bodegas | 1:N | Cada faena tiene bodegas fijas y móviles |
| faena → activos | 1:N | Activos asignados a una faena |
| marca → modelos | 1:N | Catálogo de marcas con sus modelos |
| modelo → activos | 1:N | Cada activo es de un modelo específico |
| modelo → pautas_fabricante | 1:N | **Pauta del fabricante por modelo** |
| pauta_fab → planes_mantenimiento | 1:N | Plan PM de un activo basado en la pauta |
| activo → planes_mantenimiento | 1:N | Planes PM asignados a un activo |
| activo → ordenes_trabajo | 1:N | OTs asociadas a un activo |
| activo → certificaciones | 1:N | Certificaciones por activo |
| plan_mant → ordenes_trabajo | 1:N | OTs generadas desde un plan PM |
| OT → checklist_ot | 1:N | Items de checklist por OT |
| OT → evidencias_ot | 1:N | Fotos y documentos por OT |
| OT → historial_estado_ot | 1:N | Log de transiciones de estado |
| OT → movimientos_inventario | 1:N | Consumos asociados a la OT |
| bodega + producto → stock_bodega | N:M | Stock por bodega y producto |
| movimiento_inv → kardex | 1:1 | Cada movimiento genera un registro kardex |
| conteo_inventario → conteo_detalle | 1:N | Detalle del conteo físico |
| kpi_definicion → kpi_tramos | 1:N | Tramos de puntaje por KPI |
| kpi_definicion → mediciones_kpi | 1:N | Mediciones por período |
| iceo_periodo → iceo_detalle | 1:N | Desglose del ICEO por KPI |

---

## 3. JERARQUÍA DE MANTENIMIENTO (POR FABRICANTE)

```
MARCA (ej: Caterpillar, Volvo, Gilbarco)
  └── MODELO (ej: Volvo FH 540, Gilbarco Veeder-Root)
       ├── tipo_activo: camion_cisterna, surtidor, etc.
       ├── especificaciones (JSON): potencia, capacidad, etc.
       │
       └── PAUTAS DEL FABRICANTE (1 o más por modelo)
            ├── "PM 250 horas - Volvo FH 540"
            │    ├── tipo_plan: por_horas
            │    ├── frecuencia_horas: 250
            │    ├── items_checklist: [cambio aceite, filtro aceite, revisión niveles...]
            │    └── materiales_estimados: [Shell Rimula R4 x 40L, Filtro 1R-0751 x 1...]
            │
            ├── "PM 500 horas - Volvo FH 540"
            │    ├── tipo_plan: por_horas
            │    ├── frecuencia_horas: 500
            │    └── items_checklist: [todo lo de 250h + filtro combustible + calibración...]
            │
            └── "PM 10.000 km - Volvo FH 540"
                 ├── tipo_plan: por_kilometraje
                 ├── frecuencia_km: 10000
                 └── items_checklist: [...]

            ▼ Se instancia como:

PLAN DE MANTENIMIENTO (por activo específico)
  ├── activo: "Cisterna-001" (Volvo FH 540, serie XXX)
  ├── pauta_fabricante_id → "PM 250 horas - Volvo FH 540"
  ├── frecuencia heredada o ajustada
  ├── última ejecución: 2026-03-10 a 12.450 hrs
  ├── próxima ejecución: 2026-04-xx o a 12.700 hrs
  │
  └── GENERA AUTOMÁTICAMENTE → OT preventiva
       ├── tipo: preventivo
       ├── checklist: copiado de la pauta del fabricante
       ├── materiales: estimados de la pauta
       └── estado: creada → asignada → ejecutada
```

---

## 4. POLÍTICAS RLS (RESUMEN POR ROL)

| Rol | SELECT | INSERT | UPDATE | DELETE | Restricción |
|-----|--------|--------|--------|--------|-------------|
| administrador | Todo | Todo | Todo | Todo | Sin restricción |
| gerencia | Todo | - | - | - | Solo lectura |
| subgerente_ops | Todo | - | - | - | Solo lectura |
| supervisor | Su faena | incidentes | OTs de su faena | - | Filtro por faena_id |
| planificador | Su faena | OTs, planes_mant | OTs, planes_mant | - | Filtro por faena_id |
| tecnico_mant | Sus OTs | evidencias, checklist | Sus OTs asignadas | - | responsable_id = uid |
| bodeguero | Inventario faena | Movimientos, conteos | Stock faena | - | Filtro por faena_id |
| operador_abast | Su faena | Abastecimientos, mov. salida | Abastecimientos | - | Filtro por faena_id |
| auditor | Todo | - | - | - | Solo lectura total |
| rrhh_incentivos | ICEO, KPI, usuarios | - | - | - | Solo tablas específicas |

---

## 5. FUNCIONES POSTGRESQL IMPLEMENTADAS

### 5.1 Triggers Automáticos

| Trigger | Tabla | Evento | Función |
|---------|-------|--------|---------|
| auto_updated_at | Todas con updated_at | BEFORE UPDATE | Actualiza timestamp |
| generar_folio_ot | ordenes_trabajo | BEFORE INSERT | Genera OT-YYYYMM-XXXXX |
| generar_qr_ot | ordenes_trabajo | BEFORE INSERT | Genera código QR único |
| validar_cierre_ot | ordenes_trabajo | BEFORE UPDATE | Valida evidencia, checklist, firma |
| validar_no_ejecucion | ordenes_trabajo | BEFORE UPDATE | Exige causa si no ejecutada |
| registrar_transicion | ordenes_trabajo | AFTER UPDATE | Log en historial_estado_ot |
| validar_salida_inv | movimientos_inventario | BEFORE INSERT | Exige OT + valida stock |
| actualizar_stock | movimientos_inventario | AFTER INSERT | Recalcula stock + CPP |
| registrar_kardex | movimientos_inventario | AFTER INSERT | Inserta en kardex |
| actualizar_costo_ot | movimientos_inventario | AFTER INSERT | Suma costos a la OT |
| audit_trigger | Tablas críticas | AFTER ALL | Log en auditoria_eventos |

### 5.2 Funciones de Negocio

| Función | Propósito | Invocación |
|---------|-----------|------------|
| verificar_certificaciones() | Actualiza estados, genera alertas, bloquea activos | pg_cron diario |
| generar_ots_preventivas() | Evalúa planes PM, crea OTs automáticas | pg_cron diario |
| calcular_cpp() | Calcula costo promedio ponderado | Llamada desde trigger |

### 5.3 Funciones KPI (21 funciones)

| Función | KPI | Área |
|---------|-----|------|
| calcular_kpi_a1 | Diferencia inventario combustibles | A |
| calcular_kpi_a2 | Diferencia inventario lubricantes | A |
| calcular_kpi_a3 | Exactitud inventario IRA | A |
| calcular_kpi_a4 | Cumplimiento normativo | A |
| calcular_kpi_a5 | Cumplimiento abastecimiento | A |
| calcular_kpi_a6 | Rotación de stock | A |
| calcular_kpi_a7 | Despacho oportuno | A |
| calcular_kpi_a8 | Costo merma sobre ventas | A |
| calcular_kpi_b1 | Disponibilidad operacional fijos | B |
| calcular_kpi_b2 | MTTR puntos fijos | B |
| calcular_kpi_b3 | Cumplimiento PM fijos | B |
| calcular_kpi_b4 | Vigencia certificaciones fijos | B |
| calcular_kpi_b5 | Tasa correctivos fijos | B |
| calcular_kpi_b6 | Incidentes amb/seg fijos | B |
| calcular_kpi_c1 | Disponibilidad flota | C |
| calcular_kpi_c2 | Cumplimiento PM flota | C |
| calcular_kpi_c3 | Cumplimiento rutas/despachos | C |
| calcular_kpi_c4 | MTTR flota | C |
| calcular_kpi_c5 | Rendimiento km/l | C |
| calcular_kpi_c6 | Vigencia doc legal móviles | C |
| calcular_kpi_c7 | Accidentes/incidentes ruta | C |

### 5.4 Funciones Maestras

| Función | Propósito |
|---------|-----------|
| calcular_todos_kpi(contrato, faena, inicio, fin) | Ejecuta los 21 KPIs, calcula puntajes y pondera |
| calcular_iceo(contrato, faena, inicio, fin) | Consolida KPIs, aplica bloqueantes, clasifica ICEO |

---

## 6. SUPABASE STORAGE STRATEGY

### Buckets

| Bucket | Contenido | Acceso | Límite archivo |
|--------|-----------|--------|----------------|
| `evidencias-ot` | Fotos de OTs (antes/durante/después) | Técnico sube, supervisor ve | 10 MB |
| `firmas` | Firmas digitales de técnicos y supervisores | Técnico sube, supervisor ve | 2 MB |
| `certificaciones` | PDFs de certificados (SEC, SEREMI, etc.) | Admin sube, todos ven | 20 MB |
| `documentos` | Documentos generales del contrato | Admin sube, roles con acceso | 50 MB |
| `reportes` | PDFs y Excel generados | Sistema genera, roles con acceso | 50 MB |

### Estructura de paths

```
evidencias-ot/
  └── {contrato_id}/
      └── {faena_id}/
          └── {ot_folio}/
              ├── foto_antes_001.jpg
              ├── foto_durante_001.jpg
              └── foto_despues_001.jpg

certificaciones/
  └── {activo_codigo}/
      └── {tipo_certificacion}/
          └── {fecha_emision}_{nombre}.pdf

firmas/
  └── {usuario_id}/
      └── firma_{timestamp}.png
```

### Políticas de Storage

```sql
-- Técnicos pueden subir evidencias solo a OTs donde son responsables
CREATE POLICY "tecnico_upload_evidencias" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'evidencias-ot'
    AND (storage.foldername(name))[3] IN (
      SELECT folio FROM ordenes_trabajo WHERE responsable_id = auth.uid()
    )
  );

-- Todos los autenticados pueden ver evidencias de su faena
CREATE POLICY "read_evidencias_faena" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'evidencias-ot');
```

---

## 7. DATOS SEMILLA INCLUIDOS

El archivo `07_seed_data.sql` incluye datos realistas de minería chilena:

- **1 contrato**: "Minera Los Andes" — 3 años, CLP $18.500M
- **3 faenas**: Mina Principal, Planta Concentradora, Puerto Embarque (Antofagasta)
- **6 bodegas**: 1 fija + 1 móvil por faena
- **10 marcas**: Caterpillar, Komatsu, Volvo, Mercedes-Benz, Scania, Lincoln, Wayne, Gilbarco, Tokheim, Atlas Copco
- **22 modelos**: Con tipo_activo y especificaciones técnicas reales
- **12 productos**: 3 combustibles, 5 lubricantes, 4 filtros CAT — con códigos de barras y precios CLP
- **21 definiciones KPI**: Con fórmulas, metas, pesos, bloqueantes y funciones de cálculo
- **126 tramos KPI**: 6 tramos por cada KPI
- **1 configuración ICEO**: Pesos por defecto (35%/35%/30%)

---

## 8. RECOMENDACIONES DE PERFORMANCE

1. **Vistas materializadas** para dashboards KPI (refrescar cada hora)
2. **Índices parciales** en OTs por estado (WHERE estado NOT IN ('cerrada','cancelada'))
3. **Particionamiento** de auditoria_eventos por mes (tabla más grande)
4. **Connection pooling** vía Supabase (PgBouncer incluido)
5. **Índices GIN** en campos JSONB (sla_json, items_checklist, datos_calculo)
6. **Vacuum y analyze** automáticos (configurados en Supabase)

---

## 9. ORDEN DE EJECUCIÓN EN SUPABASE

```bash
# En Supabase SQL Editor, ejecutar en este orden:
1. 01_tipos_y_enums.sql          # Extensiones y tipos
2. 02_tablas_core.sql            # Tablas maestras
3. 03_tablas_ot_inventario.sql   # OTs e inventario
4. 04_tablas_kpi_iceo_compliance.sql  # KPI, ICEO, compliance
5. 05_funciones_triggers_rls.sql # Lógica de negocio + RLS
6. 06_funciones_kpi_iceo.sql     # Cálculo KPI e ICEO
7. 07_seed_data.sql              # Datos de prueba
```

**Nota:** Habilitar `pg_cron` desde el dashboard de Supabase antes de ejecutar los scripts.

---

*Documento generado para SICOM-ICEO — Fase 2 — Diseño de Base de Datos*
*Versión 1.0 — Marzo 2026*
