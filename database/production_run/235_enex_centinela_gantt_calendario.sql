-- ============================================================================
-- SICOM-ICEO | 235 — ENEX Centinela: calendario EXACTO de la Gantt trimestral
-- ============================================================================
-- Afinamiento pedido por Manuel (2026-07-21): el plan cargado en MIG234 dejaba
-- todo en julio sin fecha. Aquí se reconstruye el calendario EXACTO de la carta
-- Gantt "Planificacion Trimestral Mantenimiento Intermedio" de Centinela
-- (2do trimestre May-Jun-Jul 2026), leyendo la posición real de cada celda del
-- PDF (semana + día de la columna v/s/d/l/m/m/j). La SEMANA ACTUAL (Semana 29,
-- Lun 20 – Vie 24-jul) se toma de la "Programación Semanal Mantenimiento
-- Intermedio Centinela" y MANDA sobre la Gantt para esa semana:
--   Lun 20: EESS Muelle (mant+calib) · Mar 21: SM Esperanza Sur (calib)
--   Mié 22: Petrolera Óxido (calib) + camiones · Mié/Jue/Vie: calibración camiones
-- Camiones: la Gantt/semanal programan por DÍA/cantidad, no por patente; los 21
-- camiones se distribuyen en las fechas de calibración de camiones de julio de la
-- Gantt (9 en la semana actual 22/23/24-jul, resto en 3/7/8/14-jul).
-- ADITIVA, IDEMPOTENTE (borra y recarga el plan de Centinela sin ejecución).
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM enex_faenas WHERE codigo='CENTINELA') THEN
        RAISE EXCEPTION 'STOP — falta faena CENTINELA (MIG206)'; END IF;
END $$;

-- 1. Limpiar el plan cargado por scripts (MIG234/235) que aún NO tenga ejecución.
--    (Respeta las programaciones creadas a mano por Manuel y las ya ejecutadas.)
DELETE FROM enex_programaciones pr
 USING enex_instalaciones i, enex_faenas f
 WHERE pr.instalacion_id = i.id AND i.faena_id = f.id AND f.codigo='CENTINELA'
   AND pr.observacion IN ('Plan trimestral Centinela (carga MIG234)',
                          'Plan trimestral Centinela (Gantt MIG235)')
   AND i.tipo <> 'truck_shop'
   AND NOT EXISTS (SELECT 1 FROM enex_ejecuciones e WHERE e.programacion_id = pr.id);

-- 2. Instalaciones — calendario exacto de la Gantt (+ Semana 29 en la semana actual).
WITH plan(nombre, svc, f) AS (VALUES
  ('Semimóvil Esperanza Sur','calibracion',DATE '2026-05-03'),
  ('Semimóvil Esperanza Sur','mantencion',DATE '2026-05-03'),
  ('EESS Muelle','calibracion',DATE '2026-05-04'),
  ('EESS Muelle','mantencion',DATE '2026-05-04'),
  ('Semimóvil 1','calibracion',DATE '2026-05-10'),
  ('Semimóvil 1','mantencion',DATE '2026-05-10'),
  ('Semimóvil 2','calibracion',DATE '2026-05-10'),
  ('Semimóvil 2','mantencion',DATE '2026-05-10'),
  ('EESS Sulfuro','calibracion',DATE '2026-05-11'),
  ('EESS Sulfuro','mantencion',DATE '2026-05-11'),
  ('Semimóvil Sulfuros 3','calibracion',DATE '2026-05-11'),
  ('Semimóvil Sulfuros 3','mantencion',DATE '2026-05-11'),
  ('EESS Óxido','calibracion',DATE '2026-05-17'),
  ('EESS Óxido','mantencion',DATE '2026-05-17'),
  ('Petrolera Óxido','calibracion',DATE '2026-05-17'),
  ('Petrolera Óxido','mantencion',DATE '2026-05-17'),
  ('EESS Sulfuro','mantencion',DATE '2026-05-19'),
  ('Semimóvil Encuentro','calibracion',DATE '2026-05-24'),
  ('Semimóvil Encuentro','mantencion',DATE '2026-05-24'),
  ('EESS Encuentro','calibracion',DATE '2026-05-25'),
  ('EESS Encuentro','mantencion',DATE '2026-05-25'),
  ('Semimóvil Esperanza Sur','mantencion',DATE '2026-05-31'),
  ('Semimóvil 1','mantencion',DATE '2026-06-01'),
  ('EESS Encuentro','calibracion',DATE '2026-06-07'),
  ('EESS Óxido','calibracion',DATE '2026-06-07'),
  ('EESS Óxido','mantencion',DATE '2026-06-07'),
  ('Petrolera Óxido','calibracion',DATE '2026-06-08'),
  ('Semimóvil Sulfuros 3','calibracion',DATE '2026-06-08'),
  ('Semimóvil Sulfuros 3','mantencion',DATE '2026-06-08'),
  ('EESS Óxido','calibracion',DATE '2026-06-14'),
  ('EESS Óxido','mantencion',DATE '2026-06-14'),
  ('Petrolera Óxido','calibracion',DATE '2026-06-15'),
  ('Semimóvil 1','calibracion',DATE '2026-06-29'),
  ('Semimóvil 2','calibracion',DATE '2026-06-30'),
  ('Semimóvil Sulfuros 3','calibracion',DATE '2026-07-05'),
  ('Semimóvil Sulfuros 3','mantencion',DATE '2026-07-05'),
  ('EESS Sulfuro','calibracion',DATE '2026-07-07'),
  ('Semimóvil 2','mantencion',DATE '2026-07-07'),
  ('EESS Muelle','calibracion',DATE '2026-07-20'),
  ('EESS Muelle','mantencion',DATE '2026-07-20'),
  ('Semimóvil Esperanza Sur','calibracion',DATE '2026-07-21'),
  ('Petrolera Óxido','calibracion',DATE '2026-07-22')
)
INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
SELECT i.id, plan.svc, EXTRACT(YEAR FROM plan.f)::int, EXTRACT(MONTH FROM plan.f)::int, plan.f,
       'Plan trimestral Centinela (Gantt MIG235)', (SELECT id FROM usuarios_perfil ORDER BY created_at LIMIT 1)
  FROM plan
  JOIN enex_faenas f ON f.codigo='CENTINELA'
  JOIN enex_instalaciones i ON i.faena_id=f.id AND i.nombre=plan.nombre AND i.activo;

-- 3. Camiones — calibración por patente en las fechas de julio de la Gantt.
WITH plan(patente, f) AS (VALUES
  ('TBGJ71',DATE '2026-07-22'),
  ('SXCF77',DATE '2026-07-22'),
  ('RKSV49',DATE '2026-07-22'),
  ('TBGJ73',DATE '2026-07-23'),
  ('RKSV46',DATE '2026-07-23'),
  ('TBGJ70',DATE '2026-07-23'),
  ('TBGJ67',DATE '2026-07-24'),
  ('SKPJ32',DATE '2026-07-24'),
  ('SKPL78',DATE '2026-07-24'),
  ('TBGJ69',DATE '2026-07-03'),
  ('SXCF76',DATE '2026-07-03'),
  ('SXGG83',DATE '2026-07-03'),
  ('VFZK21',DATE '2026-07-07'),
  ('SKPL79',DATE '2026-07-07'),
  ('TBGJ68',DATE '2026-07-07'),
  ('VFZK22',DATE '2026-07-08'),
  ('SKPL80',DATE '2026-07-08'),
  ('TBGJ72',DATE '2026-07-08'),
  ('SXGH41',DATE '2026-07-14'),
  ('SKPJ31',DATE '2026-07-14'),
  ('SXGH43',DATE '2026-07-14')
)
INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
SELECT i.id, 'calibracion', EXTRACT(YEAR FROM plan.f)::int, EXTRACT(MONTH FROM plan.f)::int, plan.f,
       'Plan trimestral Centinela (Gantt MIG235)', (SELECT id FROM usuarios_perfil ORDER BY created_at LIMIT 1)
  FROM plan
  JOIN enex_faenas f ON f.codigo='CENTINELA'
  JOIN enex_instalaciones i ON i.faena_id=f.id AND UPPER(i.patente)=UPPER(plan.patente) AND i.tipo='camion';

-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
  'total_centinela', (SELECT COUNT(*) FROM enex_programaciones pr JOIN enex_instalaciones i ON i.id=pr.instalacion_id
                        JOIN enex_faenas f ON f.id=i.faena_id WHERE f.codigo='CENTINELA'),
  'por_mes', (SELECT jsonb_object_agg(m, n) FROM (
        SELECT pr.periodo_mes m, COUNT(*) n FROM enex_programaciones pr JOIN enex_instalaciones i ON i.id=pr.instalacion_id
        JOIN enex_faenas f ON f.id=i.faena_id WHERE f.codigo='CENTINELA' AND pr.observacion LIKE '%Gantt MIG235%'
        GROUP BY pr.periodo_mes ORDER BY pr.periodo_mes) s),
  'semana_actual', (SELECT jsonb_agg(x ORDER BY x) FROM (
        SELECT (i.nombre||' '||pr.tipo_servicio||' '||pr.fecha_programada) x
        FROM enex_programaciones pr JOIN enex_instalaciones i ON i.id=pr.instalacion_id
        JOIN enex_faenas f ON f.id=i.faena_id
        WHERE f.codigo='CENTINELA' AND pr.fecha_programada BETWEEN '2026-07-20' AND '2026-07-24' AND i.tipo<>'camion') s),
  'camiones_jul', (SELECT COUNT(*) FROM enex_programaciones pr JOIN enex_instalaciones i ON i.id=pr.instalacion_id
                     WHERE i.tipo='camion' AND pr.tipo_servicio='calibracion' AND pr.periodo_mes=7)
) AS resultado;

NOTIFY pgrst, 'reload schema';
