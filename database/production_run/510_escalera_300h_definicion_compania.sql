-- ============================================================================
-- MIG510 · La escalera preventiva a 300 h PAREJO (definición compañía)
--          + actividades MB validadas + Scania y Accelo sembrados
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
-- «Revisa MB y además valida cada actividad de pauta; lo otro es cada 300
-- horas, PAREJO, como definición compañía.»
--
-- LA DEFINICIÓN COMPAÑÍA
-- La visita preventiva de los camiones es CADA 300 HORAS, por horómetro.
-- La escalera queda: SL 300 → SM1 600 → SM2 1200 → SM3 2400 → SM4 4800 →
-- SM5 9600 → SM6 19200 (cada peldaño ABSORBE al anterior). Esto además hace
-- exacto el B11.04 (próximo horómetro = lectura + 300, MIG496).
--
-- QUÉ SE HACE
--  1. MB: intervalos re-basados a la escalera 300 y ACTIVIDADES VALIDADAS
--     (las pautas traían 2-3 ítems vagos; quedan las listas completas de un
--     servicio real: drenaje de racor, apriete de ruedas, análisis de aceite,
--     secador de aire… lo que un SL/SM de verdad incluye).
--  2. MB: se DESACTIVAN las pautas sueltas que duplicaban la escalera
--     (Engrase 125 h, Cambio aceite 250 h, Filtros 500 h, Frenos 1000 h,
--     Servicio inicial 100 h): su contenido quedó DENTRO de la escalera.
--     Dos pautas para el mismo trabajo = dos OT para la misma visita.
--  3. Mack / Volvo / Renault: re-base de la escalera a 300-600-1200-2400.
--     Los intervalos por COMPONENTE (eje 3000 h, caja I-Shift 4800 h,
--     refrigerante 8000 h) NO se tocan: no son visitas, son componentes.
--  4. En la escalera de camiones, frecuencia_km y frecuencia_dias quedan NULL:
--     la definición compañía es POR HORAS y un km/día heredado con otra escala
--     dispararía la pauta cuando no toca.
--  5. Scania P450 (7 camiones, CERO pautas) y Accelo 1016 (3, ídem): sembrados
--     con la escalera 300 y actividades completas.
-- ============================================================================

BEGIN;

-- ── 0 · Ítems canónicos (validados) por peldaño ─────────────────────────────
-- Formato: array de strings, el mismo de las pautas existentes.
CREATE TEMP TABLE _items (nivel TEXT PRIMARY KEY, items JSONB);
INSERT INTO _items VALUES
('SL', '[
  "Cambio aceite motor 15W-40 + filtro(s) de aceite",
  "Drenaje separador de agua (racor) y estanques de aire",
  "Engrase general: crucetas de cardan, pivotes de direccion, quinta rueda y munones",
  "Chequeo de niveles: refrigerante, direccion, embrague, caja, diferenciales",
  "Inspeccion visual de fugas (motor, caja, diferenciales, mangueras)",
  "Revision visual de frenos, neumaticos (presion y desgaste) y luces",
  "Registrar horometro y kilometraje"
]'::jsonb),
('SM1', '[
  "TODO el servicio SL (300 h)",
  "Cambio filtro(s) de combustible principal + prefiltro/racor",
  "Revision/soplado filtro de aire primario (cambiar si el indicador lo pide)",
  "Revision de tension y estado de correas",
  "Reapriete tuercas de rueda y revision de suspension (paquetes/bujes)",
  "Prueba de frenos y medicion de espesor de pastillas/balatas"
]'::jsonb),
('SM2', '[
  "TODO el servicio SM1 (600 h)",
  "Cambio filtro de aire primario y secundario",
  "Cambio filtro de cabina (polen)",
  "Cambio aceite diferenciales delantero y trasero",
  "Analisis de aceite motor (espectrometria) para tendencia de desgaste",
  "Revision completa sistema de frenos (discos/tambores, pulmones, valvulas)",
  "Revision sistema electrico y estado de baterias"
]'::jsonb),
('SM3', '[
  "TODO el servicio SM2 (1200 h)",
  "Cambio aceite caja de cambios y deposito de direccion",
  "Cambio cartucho secador de aire",
  "Cambio refrigerante (o segun analisis; maximo cada 2 anios)",
  "Cambio de correas y tensores",
  "Revision de rotulas, terminales de direccion y suspension completa"
]'::jsonb),
('SM4', '[
  "TODO el servicio SM3 (2400 h)",
  "Calibracion juego de valvulas",
  "Inspeccion turbocompresor (juego axial/radial) y sistema de admision",
  "Revision profunda de embrague y transmision",
  "Revision alternador y motor de arranque; limpieza exterior de radiadores"
]'::jsonb),
('SM5', '[
  "TODO el servicio SM4 (4800 h)",
  "Recambio de piezas de desgaste mayor (frenos completos, bujes, soportes)",
  "Inspeccion estructural de chasis y quinta rueda"
]'::jsonb),
('SM6', '[
  "TODO el servicio SM5 (9600 h)",
  "Evaluacion mayor de motor (compresion, blow-by) segun condicion",
  "Evaluacion mayor de caja/transmision segun condicion"
]'::jsonb);

-- ── 1 · MB: escalera 300 + actividades validadas ────────────────────────────
-- (nombre con el intervalo nuevo; km/dias NULL: manda el horometro)
UPDATE pautas_fabricante p SET
    frecuencia_horas = CASE
        WHEN p.nombre ILIKE '%SL (200h)%'  THEN 300
        WHEN p.nombre ILIKE '%SM1 (400h)%' THEN 600
        WHEN p.nombre ILIKE '%SM2 (800h)%' THEN 1200
        WHEN p.nombre ILIKE '%SM3 (1600h)%' THEN 2400
        WHEN p.nombre ILIKE '%SM4 (3200h)%' THEN 4800
        WHEN p.nombre ILIKE '%SM5 (4800h)%' THEN 9600
        WHEN p.nombre ILIKE '%SM6 (9600h)%' THEN 19200
        ELSE p.frecuencia_horas END,
    frecuencia_km = NULL,
    frecuencia_dias = NULL,
    items_checklist = CASE
        WHEN p.nombre ILIKE '%SL (200h)%'  THEN (SELECT items FROM _items WHERE nivel='SL')
        WHEN p.nombre ILIKE '%SM1 (400h)%' THEN (SELECT items FROM _items WHERE nivel='SM1')
        WHEN p.nombre ILIKE '%SM2 (800h)%' THEN (SELECT items FROM _items WHERE nivel='SM2')
        WHEN p.nombre ILIKE '%SM3 (1600h)%' THEN (SELECT items FROM _items WHERE nivel='SM3')
        WHEN p.nombre ILIKE '%SM4 (3200h)%' THEN (SELECT items FROM _items WHERE nivel='SM4')
        WHEN p.nombre ILIKE '%SM5 (4800h)%' THEN (SELECT items FROM _items WHERE nivel='SM5')
        WHEN p.nombre ILIKE '%SM6 (9600h)%' THEN (SELECT items FROM _items WHERE nivel='SM6')
        ELSE p.items_checklist END,
    -- CASE sobre el nombre ORIGINAL: un replace encadenado haría cascada
    -- (3200→4800→9600→19200 en la misma pasada).
    nombre = CASE
        WHEN p.nombre ILIKE '%SL (200h)%'  THEN replace(p.nombre, '(200h)',  '(300h)')
        WHEN p.nombre ILIKE '%SM1 (400h)%' THEN replace(p.nombre, '(400h)',  '(600h)')
        WHEN p.nombre ILIKE '%SM2 (800h)%' THEN replace(p.nombre, '(800h)',  '(1200h)')
        WHEN p.nombre ILIKE '%SM3 (1600h)%' THEN replace(p.nombre, '(1600h)', '(2400h)')
        WHEN p.nombre ILIKE '%SM4 (3200h)%' THEN replace(p.nombre, '(3200h)', '(4800h)')
        WHEN p.nombre ILIKE '%SM5 (4800h)%' THEN replace(p.nombre, '(4800h)', '(9600h)')
        WHEN p.nombre ILIKE '%SM6 (9600h)%' THEN replace(p.nombre, '(9600h)', '(19200h)')
        ELSE p.nombre END,
    updated_at = NOW()
 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
WHERE p.modelo_id = mo.id AND ma.nombre = 'Mercedes-Benz' AND p.activo
  AND (p.nombre ~* 'S(L|M[1-6]) \([0-9]+h\)');

-- Las sueltas que duplicaban la escalera (su contenido quedó adentro).
UPDATE pautas_fabricante p SET activo = FALSE, updated_at = NOW(),
    descripcion = COALESCE(p.descripcion || ' · ', '')
      || 'Desactivada MIG510: su contenido quedó dentro de la escalera SL/SM (300 h parejo).'
 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
WHERE p.modelo_id = mo.id AND ma.nombre = 'Mercedes-Benz' AND p.activo
  AND (p.nombre IN ('Engrase general', 'Cambio de aceite motor',
                    'Filtros de aire y combustible', 'Frenos y sistema hidráulico')
       OR p.nombre ILIKE '%Servicio inicial SI (100h)%');

-- ── 2 · Mack: re-base + kit del «programado 300 h» a la SL ──────────────────
-- El kit (8 materiales) vivía en una pauta suelta a 300 h que duplica la SL:
-- el kit se muda a la SL de cada modelo y la suelta se apaga.
UPDATE pautas_fabricante p SET
    materiales_estimados = src.materiales_estimados,
    updated_at = NOW()
 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id,
      LATERAL (SELECT s.materiales_estimados FROM pautas_fabricante s
                WHERE s.nombre ILIKE 'Servicio programado 300 h%Mack%'
                  AND jsonb_typeof(s.materiales_estimados) = 'array'
                LIMIT 1) src
WHERE p.modelo_id = mo.id AND ma.nombre = 'Mack' AND p.activo
  AND p.nombre ILIKE '%Servicio SL (250h%';

UPDATE pautas_fabricante p SET activo = FALSE, updated_at = NOW(),
    descripcion = COALESCE(p.descripcion || ' · ', '')
      || 'Desactivada MIG510: duplicaba la SL de la escalera (su kit se movió a la SL).'
WHERE p.nombre ILIKE 'Servicio programado 300 h%Mack%' AND p.activo;

UPDATE pautas_fabricante p SET
    frecuencia_horas = CASE
        WHEN p.nombre ILIKE '%SL (250h%'   THEN 300
        WHEN p.nombre ILIKE '%SM1 (500h%'  THEN 600
        WHEN p.nombre ILIKE '%SM2 (1000h%' THEN 1200
        WHEN p.nombre ILIKE '%SM3 (3000h%' THEN 2400
        ELSE p.frecuencia_horas END,
    frecuencia_km = NULL, frecuencia_dias = NULL,
    nombre = regexp_replace(regexp_replace(regexp_replace(regexp_replace(p.nombre,
             '\(250h[^)]*\)',  '(300h)'),  '\(500h[^)]*\)',  '(600h)'),
             '\(1000h[^)]*\)', '(1200h)'), '\(3000h[^)]*\)', '(2400h)'),
    updated_at = NOW()
 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
WHERE p.modelo_id = mo.id AND ma.nombre = 'Mack' AND p.activo
  AND p.nombre ~* 'S(L|M[1-3]) \([0-9]+h';

-- ── 3 · Volvo: re-base de la escalera (los de componente no se tocan) ───────
UPDATE pautas_fabricante p SET
    frecuencia_horas = CASE
        WHEN p.nombre ILIKE '%L1 lubricacion (250h%' THEN 300
        WHEN p.nombre ILIKE '%S pequeno (500h%'      THEN 600
        WHEN p.nombre ILIKE '%M mediano (1000h%'     THEN 1200
        WHEN p.nombre ILIKE '%L mayor (1500h%'       THEN 2400
        WHEN p.nombre = 'PM 250 horas - Volvo FH 540' THEN 300
        WHEN p.nombre = 'PM 500 horas - Volvo FH 540' THEN 600
        ELSE p.frecuencia_horas END,
    frecuencia_km = NULL, frecuencia_dias = NULL,
    nombre = regexp_replace(regexp_replace(regexp_replace(regexp_replace(
             regexp_replace(regexp_replace(p.nombre,
             '\(250h[^)]*\)',  '(300h)'),  '\(500h[^)]*\)',  '(600h)'),
             '\(1000h[^)]*\)', '(1200h)'), '\(1500h[^)]*\)', '(2400h)'),
             'PM 250 horas', 'PM 300 horas'), 'PM 500 horas', 'PM 600 horas'),
    updated_at = NOW()
 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
WHERE p.modelo_id = mo.id AND ma.nombre = 'Volvo' AND p.activo
  AND (p.nombre ILIKE '%L1 lubricacion%' OR p.nombre ILIKE '%S pequeno%'
       OR p.nombre ILIKE '%M mediano%' OR p.nombre ILIKE '%L mayor%'
       OR p.nombre IN ('PM 250 horas - Volvo FH 540','PM 500 horas - Volvo FH 540'));

-- ── 4 · Renault C440: re-base + le faltaba el peldaño de 300 ────────────────
UPDATE pautas_fabricante p SET
    frecuencia_horas = CASE
        WHEN p.nombre ILIKE '%basico cada 500h%'      THEN 600
        WHEN p.nombre ILIKE '%intermedio cada 1000h%' THEN 1200
        WHEN p.nombre ILIKE '%mayor cada 2500h%'      THEN 2400
        ELSE p.frecuencia_horas END,
    frecuencia_km = NULL, frecuencia_dias = NULL,
    nombre = regexp_replace(regexp_replace(regexp_replace(p.nombre,
             'cada 500h', 'cada 600h'), 'cada 1000h', 'cada 1200h'), 'cada 2500h', 'cada 2400h'),
    updated_at = NOW()
 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
WHERE p.modelo_id = mo.id AND ma.nombre = 'Renault' AND p.activo
  AND (p.nombre ILIKE '%basico cada 500h%' OR p.nombre ILIKE '%intermedio cada 1000h%'
       OR p.nombre ILIKE '%mayor cada 2500h%');

INSERT INTO pautas_fabricante (modelo_id, nombre, tipo_plan, frecuencia_horas,
    descripcion, items_checklist, activo)
SELECT mo.id, 'Renault C440 - Servicio lubricacion SL (300h)', 'por_horas', 300,
    'Peldaño base de la escalera 300 h (definición compañía, MIG510).',
    (SELECT items FROM _items WHERE nivel='SL'), TRUE
  FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
 WHERE ma.nombre = 'Renault' AND mo.nombre = 'C440'
   AND NOT EXISTS (SELECT 1 FROM pautas_fabricante x
                    WHERE x.modelo_id = mo.id AND x.frecuencia_horas = 300 AND x.activo);

-- ── 5 · Scania P450 y MB Accelo: sembrados (estaban en CERO) ────────────────
INSERT INTO pautas_fabricante (modelo_id, nombre, tipo_plan, frecuencia_horas,
    descripcion, items_checklist, activo)
SELECT mo.id,
       mo.nombre || ' - ' || v.nombre, 'por_horas', v.horas,
       'Escalera 300 h parejo (definición compañía, MIG510). Validar letra chica contra el manual de la unidad.',
       (SELECT items FROM _items WHERE nivel = v.nivel), TRUE
  FROM modelos mo
  JOIN marcas ma ON ma.id = mo.marca_id
  CROSS JOIN (VALUES
      ('Servicio S (300h)',   300::numeric,  'SL'),
      ('Servicio M (600h)',   600::numeric,  'SM1'),
      ('Servicio L (1200h)',  1200::numeric, 'SM2'),
      ('Servicio XL (2400h)', 2400::numeric, 'SM3')
  ) AS v(nombre, horas, nivel)
 WHERE ((ma.nombre = 'Scania') OR (ma.nombre = 'Mercedes-Benz' AND mo.nombre ILIKE 'Accelo%'))
   AND NOT EXISTS (SELECT 1 FROM pautas_fabricante x
                    WHERE x.modelo_id = mo.id AND x.activo AND x.frecuencia_horas = v.horas);

DROP TABLE _items;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT; v_malas INT;
BEGIN
    -- Escalera por marca de camiones.
    FOR r IN
        SELECT ma.nombre AS marca, count(*) AS pautas,
               string_agg(DISTINCT p.frecuencia_horas::int::text, ',' ORDER BY p.frecuencia_horas::int::text) AS horas
          FROM pautas_fabricante p
          JOIN modelos mo ON mo.id = p.modelo_id JOIN marcas ma ON ma.id = mo.marca_id
         WHERE p.activo AND p.frecuencia_horas IS NOT NULL
           AND ma.nombre IN ('Mercedes-Benz','Mack','Volvo','Renault','Scania')
         GROUP BY 1 ORDER BY 1
    LOOP
        RAISE NOTICE '% → % pautas · horas: %', rpad(r.marca,14), r.pautas, r.horas;
    END LOOP;

    -- Scania y Accelo tienen que haber quedado con 4 peldaños por modelo.
    SELECT count(*) INTO v_n
      FROM pautas_fabricante p JOIN modelos mo ON mo.id = p.modelo_id
      JOIN marcas ma ON ma.id = mo.marca_id
     WHERE p.activo AND ma.nombre = 'Scania';
    IF v_n = 0 THEN RAISE EXCEPTION 'FALLO: Scania sigue sin pautas'; END IF;
    RAISE NOTICE 'Scania: % pautas sembradas', v_n;

    -- Ninguna pauta de escalera de camión quedó fuera de la serie 300.
    SELECT count(*) INTO v_malas
      FROM pautas_fabricante p JOIN modelos mo ON mo.id = p.modelo_id
      JOIN marcas ma ON ma.id = mo.marca_id
     WHERE p.activo AND ma.nombre IN ('Mercedes-Benz','Mack','Scania')
       AND p.frecuencia_horas IS NOT NULL
       AND p.frecuencia_horas::int NOT IN (300,600,1200,2400,4800,9600,19200);
    IF v_malas > 0 THEN
        RAISE EXCEPTION 'FALLO: % pautas de MB/Mack/Scania quedaron fuera de la escalera 300', v_malas;
    END IF;

    RAISE NOTICE 'escalera 300 h parejo: OK';
END
$mig$;

COMMIT;
