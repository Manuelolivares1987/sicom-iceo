-- 704 — TC8, certificaciones y pluma en el presupuesto (Manuel 17-11-2026).
-- destructivo-ok: los TRUNCATE de fn_ppto_recalcular solo vacían ppto_camion, ppto_visita y ppto_base, resultados propios que la función regenera completos (igual que MIG670).
--   1. El TC8 vence por ley a 5 años: los 2 marcados «no caduca» (SVBJ-57, TRST-57) pasan a emisión + 60 meses
--      (estándar ya verificado en certificado_vigencia_estandar con los TC8 INTECIL de Esmax).
--   2. Línea nueva B4 «Certificaciones por vencimiento»: TC8 a $840.000 (última inspección, Manuel) en el año
--      en que vence cada aljibe, y certificación anual de cada pluma de Calama. Sus compras históricas salen
--      del promedio de B2 para no contarlas dos veces.
--   3. Pluma de Calama: mantención proyectada al ritmo de 2026 cuando supera lo que trae el correctivo.
--   4. Componentes de aljibe de combustible (pistolas, mangueras fuel oil, válvulas): dejan Ferretería y van
--      al equipo (correctivo) o a repuestos sin patente.

-- 1 ─ TC8 por ley
UPDATE certificaciones c
   SET fecha_vencimiento = (c.fecha_emision + interval '60 months')::DATE,
       fecha_origen = 'manual',
       fecha_origen_nota = 'MIG704 · el TC8 vence por ley a 5 años (Manuel 17-11-2026); estaba marcado «no caduca» por venir con la compra.',
       updated_at = now()
 WHERE c.tipo::TEXT = 'tc8_sec' AND c.anulado_at IS NULL AND c.fecha_origen = 'documento_sin_vencimiento'
   AND c.fecha_emision IS NOT NULL;
DELETE FROM certificado_tipo_permanente WHERE tipo::TEXT = 'tc8_sec';

-- 2 ─ Línea, supuestos y productos
INSERT INTO ppto_linea VALUES
('B4','B','Costos fijos de flota','Certificaciones por vencimiento (TC8 y pluma)',75,
 'TC8 de cada aljibe de combustible en el año en que vence (5 años por ley), al costo de la última inspección; certificación anual de cada pluma de Calama.')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO ppto_supuesto (clave, nombre, valor, unidad, nota, orden) VALUES
('costo_tc8', 'Costo de renovar un TC8', 840000, 'clp', 'Última inspección TC8 (Manuel 17-11-2026)', 130),
('costo_cert_pluma', 'Certificación anual de una pluma', 550000, 'clp', 'Softland 2026: inspección de operatividad $0,49 a 0,60 MM', 140)
ON CONFLICT (clave) DO NOTHING;

INSERT INTO ppto_producto_linea (cod_prod, linea_origen) VALUES
('SERSEGCER004','B4'), ('SERSEGICE001','B4'), ('SERSEGSEC001','B4'),
('AFEFERMAN058','L05'), ('AFEFERMAN069','L05'), ('AFEFERMAN076','L05'), ('AFEFERMAN081','L05'),
('AFEFERPIS002','L05'), ('AFEFERPIS013','L05'), ('AFEFERPIW001','L05'), ('AFEFERTAW001','L05'), ('AFEFERVAL010','L05')
ON CONFLICT (cod_prod) DO UPDATE SET linea_origen = EXCLUDED.linea_origen;

CREATE OR REPLACE FUNCTION public.fn_ppto_clasificar(p text, camion boolean, total numeric, lo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN lo = 'B4' THEN 'B4'
        WHEN p LIKE 'REPNEU%' THEN 'A3'
        WHEN p LIKE 'REPMOTFIL%' OR p LIKE 'REPFIL%' OR p LIKE 'CLULUB%' OR p LIKE 'CLUGRA%' THEN 'A1'
        WHEN p LIKE 'CLU%' OR lo IN ('L01','L02') THEN 'D1'
        WHEN lo = 'L07' THEN 'B1'
        WHEN lo = 'L08' THEN 'B2'
        WHEN p = 'SERSEGMEN001' THEN 'B3'
        WHEN p LIKE 'REP%' OR p LIKE 'COM%' OR p LIKE 'REC%' OR p LIKE 'SERREP%'
             OR lo IN ('L03','L04','L05','L06') OR (camion AND p = 'SERSEGSEV002') THEN
            CASE WHEN NOT camion THEN 'A5' WHEN total >= 2500000 THEN 'A4' ELSE 'A2' END
        WHEN lo = 'L09' OR p LIKE 'AFE%' OR p LIKE 'ART%' THEN 'C1'
        WHEN lo = 'L10' OR p LIKE 'ISE%' THEN 'C2'
        WHEN lo = 'L11' THEN 'C3'
        WHEN lo = 'L12' THEN 'C4'
        WHEN lo = 'L13' THEN 'C5'
        WHEN lo = 'L15' THEN 'E1'
        WHEN lo = 'L16' OR p LIKE 'AOF%' OR p LIKE 'IAF%' THEN 'C7'
        WHEN lo IN ('L17','CAPEX') OR p LIKE 'EQU%' THEN 'C8'
        ELSE 'C6'
    END
$function$;

-- 3 y 4 ─ Cálculo
CREATE OR REPLACE FUNCTION public.fn_ppto_recalcular()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::DATE;
    v_fin DATE := date_trunc('month', (now() AT TIME ZONE 'America/Santiago'))::DATE - 1;
    v_i12 DATE; v_i24 DATE; v_i36 DATE;
    v_anios NUMERIC;
    s_hist NUMERIC; s_cont NUMERIC; s_mad NUMERIC; s_neu NUMERIC; s_hedad NUMERIC; s_sind NUMERIC; s_cal NUMERIC;
    f RECORD;
    k INT; d DATE; lv TEXT; n INT; i INT; y INT; c RECORD; v_ritmo NUMERIC; v_rot INT := 0;
    v_seguro NUMERIC; v_pool NUMERIC; v_reserva NUMERIC; v_pct NUMERIC; r JSONB;
    e_t NUMERIC; c_t NUMERIC; c_w NUMERIC; esp NUMERIC; fac NUMERIC; hor_t NUMERIC; v_neu NUMERIC;
BEGIN
    v_i12 := (v_fin + 1 - INTERVAL '12 months')::DATE;
    v_i24 := (v_fin + 1 - INTERVAL '24 months')::DATE;
    v_i36 := (v_fin + 1 - INTERVAL '36 months')::DATE;
    v_anios := (v_fin - DATE '2023-01-01' + 1) / 365.25;
    SELECT valor INTO s_hist FROM ppto_supuesto WHERE clave = 'ipc_historico';
    SELECT valor INTO s_cont FROM ppto_supuesto WHERE clave = 'contingencia';
    SELECT valor INTO s_mad FROM ppto_supuesto WHERE clave = 'correctivo_maduro';
    SELECT valor INTO s_neu FROM ppto_supuesto WHERE clave = 'neumatico_maduro';
    SELECT valor INTO s_hedad FROM ppto_supuesto WHERE clave = 'horas_por_anio_edad';
    SELECT valor INTO s_sind FROM ppto_supuesto WHERE clave = 'ritmo_sin_dato';
    SELECT valor INTO s_cal FROM ppto_supuesto WHERE clave = 'ritmo_anual_calendario';

    DROP TABLE IF EXISTS _idx, _real, _kit;
    CREATE TEMP TABLE _idx ON COMMIT DROP AS
    SELECT 2027 AS anio, 1 + (SELECT valor FROM ppto_supuesto WHERE clave='ipc_2027') AS f;
    INSERT INTO _idx SELECT 2028, x.f * (1 + (SELECT valor FROM ppto_supuesto WHERE clave='ipc_2028')) FROM _idx x WHERE x.anio = 2027;
    INSERT INTO _idx SELECT 2029, x.f * (1 + (SELECT valor FROM ppto_supuesto WHERE clave='ipc_2029')) FROM _idx x WHERE x.anio = 2028;

    -- Real a pesos 2026 hasta el último mes cerrado.
    CREATE TEMP TABLE _real ON COMMIT DROP AS
    SELECT activo_id, linea, fecha, cod_prod, folio, total, origen,
           total * power(1 + s_hist, 2026 - extract(year FROM fecha)::INT) AS t26,
           (total >= 10000000 AND linea IN ('C1','C2','C4','C5','C6','C7','C8')) AS unico
      FROM v_ppto_real WHERE fecha <= v_fin;

    -- Costo de cada kit: precio de la última compra real si es razonable, si no el de referencia.
    CREATE TEMP TABLE _kit ON COMMIT DROP AS
    WITH ventana AS (
        SELECT l.cod_prod, sum(l.total) FILTER (WHERE o.fecha_oc >= v_hoy - 183) AS t6,
               sum(l.cantidad) FILTER (WHERE o.fecha_oc >= v_hoy - 183) AS q6,
               sum(l.total) AS t18, sum(l.cantidad) AS q18
          FROM softland_oc o JOIN softland_oc_linea l USING (num_inter_oc)
         WHERE o.estado = 'AP' AND o.fecha_oc >= v_hoy - 548 AND l.cantidad > 0
           AND l.cod_prod IN (SELECT DISTINCT cod_softland FROM ppto_kit_item WHERE precio_vivo)
         GROUP BY 1
    ), pr AS (
        SELECT k.*, coalesce(v.t6 / nullif(v.q6, 0), v.t18 / nullif(v.q18, 0)) AS vivo
          FROM ppto_kit_item k LEFT JOIN ventana v ON k.precio_vivo AND v.cod_prod = k.cod_softland
    ), pu AS (
        SELECT *, CASE WHEN vivo BETWEEN precio_ref * 0.5 AND precio_ref * 2 THEN vivo ELSE precio_ref END AS precio,
               (vivo BETWEEN precio_ref * 0.5 AND precio_ref * 2) IS TRUE AS es_real FROM pr
    )
    SELECT grupo_kit, nivel, sum(cantidad * precio) AS costo,
           coalesce(sum(cantidad * precio) FILTER (WHERE fil_lub), 0) AS fl,
           coalesce(sum(cantidad * precio) FILTER (WHERE fil_lub AND es_real), 0) AS fl_real
      FROM pu GROUP BY 1, 2;

    -- Flota que entra al presupuesto y su ritmo: promedio del último mes y de la ventana larga.
    TRUNCATE ppto_camion;
    INSERT INTO ppto_camion (patente, activo_id, modelo, anio_fab, estado_comercial, faena, grupo_kit, horometro, ritmo, ritmo_fuente, base_correctivo, base_neumatico, ritmo_18m, ritmo_mejor_mes, mejor_mes)
    WITH mejor AS (
        -- Mejor mes COMPLETO de GPS de los últimos 18 meses (h/día del mes).
        SELECT DISTINCT ON (activo_id) activo_id, mes, horas / extract(day FROM (mes + interval '1 month' - interval '1 day')) AS hd
          FROM v_activo_horas_mes
         WHERE mes < date_trunc('month', v_hoy) AND mes >= date_trunc('month', v_hoy) - interval '18 months' AND horas > 0
           AND horas / extract(day FROM (mes + interval '1 month' - interval '1 day')) <= 14
         ORDER BY activo_id, hd DESC
    ), larga AS (
        SELECT activo_id, horas / nullif(dias, 0) AS hd FROM fn_activo_ventana_horas(v_hoy - 548, v_hoy)
         WHERE dias >= 90 AND horas / nullif(dias, 0) <= 14
    ), b AS (
        SELECT a.patente, a.id, mo.nombre AS modelo, a.anio_fabricacion, a.estado_comercial::TEXT AS ec,
               e.faena, g.grupo_kit, coalesce(e.horometro, a.horas_uso_actual, 0) AS hor,
               aj.ritmo_manual, e.horas_por_dia AS r30, l.hd AS rl, mj.hd AS rm, mj.mes AS mm
          FROM activos a
          LEFT JOIN modelos mo ON mo.id = a.modelo_id
          LEFT JOIN ppto_modelo_grupo g ON g.modelo = mo.nombre
          LEFT JOIN v_equipo_horas e ON e.activo_id = a.id
          LEFT JOIN larga l ON l.activo_id = a.id
          LEFT JOIN mejor mj ON mj.activo_id = a.id
          LEFT JOIN ppto_flota_ajuste aj ON aj.patente = a.patente
         WHERE a.patente IS NOT NULL AND a.estado::TEXT <> 'dado_baja'
           AND coalesce(a.es_prueba, false) = false AND coalesce(a.es_externo, false) = false
           AND coalesce(a.estado_comercial::TEXT, '') <> 'en_venta'
           AND coalesce(aj.incluido, true)
    ), m AS (
        SELECT b.*, greatest(rl, rm) AS medido FROM b
    ), p AS (
        SELECT modelo, avg(medido) AS par FROM m WHERE medido IS NOT NULL GROUP BY 1
    )
    SELECT m.patente, m.id, m.modelo, m.anio_fabricacion, m.ec, m.faena, m.grupo_kit, m.hor,
           coalesce(m.ritmo_manual, m.medido, p.par, m.r30, s_sind),
           CASE WHEN m.ritmo_manual IS NOT NULL THEN 'Manual'
                WHEN m.rm IS NOT NULL AND (m.rl IS NULL OR m.rm > m.rl) THEN 'Mejor mes GPS (' || to_char(m.mm, 'MM-YYYY') || ')'
                WHEN m.rl IS NOT NULL THEN 'Promedio 18 meses'
                WHEN p.par IS NOT NULL THEN 'Sin historial: promedio del modelo'
                WHEN m.r30 IS NOT NULL THEN 'GPS último mes (sin historial ni pares)'
                ELSE 'Sin dato: supuesto' END,
           coalesce((SELECT sum(t26) FROM _real x WHERE x.activo_id = m.id AND x.linea = 'A2' AND x.fecha >= v_i24), 0) / 2,
           coalesce((SELECT sum(t26) FROM _real x WHERE x.activo_id = m.id AND x.linea = 'A3' AND x.fecha >= v_i36), 0) / 3,
           m.rl, m.rm, m.mm
      FROM m LEFT JOIN p ON p.modelo = m.modelo;

    -- Visitas hasta fines de 2029.
    TRUNCATE ppto_visita;
    FOR f IN SELECT * FROM ppto_camion WHERE grupo_kit IS NOT NULL ORDER BY patente LOOP
        v_ritmo := f.ritmo;
        SELECT intervalo_horas INTO i FROM ppto_modelo_grupo WHERE grupo_kit = f.grupo_kit LIMIT 1;
        IF v_ritmo >= 0.1 THEN
            k := floor(f.horometro / i)::INT + 1;
            LOOP
                d := v_hoy + ceil((k * i - f.horometro) / v_ritmo)::INT;
                EXIT WHEN d > DATE '2029-12-31';
                -- Escalera: la visita n toma el nivel según cuántas veces n se divide por 2.
                n := k; y := 0;
                WHILE n % 2 = 0 AND y < 6 LOOP n := n / 2; y := y + 1; END LOOP;
                SELECT kk.nivel INTO lv FROM _kit kk
                 WHERE kk.grupo_kit = f.grupo_kit AND kk.nivel IN ('SL','SM1','SM2','SM3','SM4','SM5','SM6')
                   AND array_position(ARRAY['SL','SM1','SM2','SM3','SM4','SM5','SM6'], kk.nivel) <= y + 1
                 ORDER BY array_position(ARRAY['SL','SM1','SM2','SM3','SM4','SM5','SM6'], kk.nivel) DESC
                 LIMIT 1;
                INSERT INTO ppto_visita (patente, fecha, anio, mes, horas, nivel, tipo, costo, costo_kit)
                SELECT f.patente, d, extract(year FROM d), extract(month FROM d), k * i, lv, 'pauta',
                       kk.fl * coalesce((SELECT x.f FROM _idx x WHERE x.anio = extract(year FROM d)), 1),
                       kk.costo * coalesce((SELECT x.f FROM _idx x WHERE x.anio = extract(year FROM d)), 1)
                  FROM _kit kk WHERE kk.grupo_kit = f.grupo_kit AND kk.nivel = lv;
                k := k + 1;
            END LOOP;
            FOR c IN SELECT * FROM ppto_componente_regla rg WHERE rg.grupo_kit = f.grupo_kit AND rg.cada_horas IS NOT NULL LOOP
                k := floor(f.horometro / c.cada_horas)::INT + 1;
                LOOP
                    d := v_hoy + ceil((k * c.cada_horas - f.horometro) / v_ritmo)::INT;
                    EXIT WHEN d > DATE '2029-12-31';
                    -- Lo que vence antes de 2027 no alcanza a comprarse este año.
                    d := greatest(d, DATE '2027-01-15');
                    INSERT INTO ppto_visita (patente, fecha, anio, mes, horas, nivel, tipo, costo, costo_kit)
                    SELECT f.patente, d, extract(year FROM d), extract(month FROM d), k * c.cada_horas, c.nivel, 'componente',
                           kk.costo * (SELECT x.f FROM _idx x WHERE x.anio = extract(year FROM d)),
                           kk.costo * (SELECT x.f FROM _idx x WHERE x.anio = extract(year FROM d))
                      FROM _kit kk WHERE kk.grupo_kit = f.grupo_kit AND kk.nivel = c.nivel;
                    k := k + 1;
                END LOOP;
            END LOOP;
        END IF;
        FOR y IN 2027..2029 LOOP
            -- Componentes por años y servicio anual: se reparten en el año para no juntarlos en un mes.
            FOR c IN SELECT * FROM ppto_componente_regla rg WHERE rg.grupo_kit = f.grupo_kit AND rg.cada_anios IS NOT NULL
                       AND f.anio_fab IS NOT NULL AND (y - f.anio_fab) > 0 AND (y - f.anio_fab) % rg.cada_anios = 0 LOOP
                INSERT INTO ppto_visita (patente, fecha, anio, mes, horas, nivel, tipo, costo, costo_kit)
                SELECT f.patente, make_date(y, 1 + v_rot % 12, 15), y, 1 + v_rot % 12, NULL, c.nivel, 'componente',
                       kk.costo * (SELECT x.f FROM _idx x WHERE x.anio = y),
                       kk.costo * (SELECT x.f FROM _idx x WHERE x.anio = y)
                  FROM _kit kk WHERE kk.grupo_kit = f.grupo_kit AND kk.nivel = c.nivel;
            END LOOP;
            IF v_ritmo < s_cal THEN
                INSERT INTO ppto_visita (patente, fecha, anio, mes, horas, nivel, tipo, costo, costo_kit)
                SELECT f.patente, make_date(y, 1 + v_rot % 12, 15), y, 1 + v_rot % 12, NULL, 'ANUAL', 'anual',
                       kk.fl * (SELECT x.f FROM _idx x WHERE x.anio = y),
                       kk.costo * (SELECT x.f FROM _idx x WHERE x.anio = y)
                  FROM _kit kk WHERE kk.grupo_kit = f.grupo_kit AND kk.nivel = 'ANUAL';
            END IF;
        END LOOP;
        v_rot := v_rot + 1;
    END LOOP;

    DELETE FROM ppto_resultado WHERE version_id = 1;

    -- A1 por visita.
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, monto)
    SELECT 1, anio, mes, 'A1', patente, sum(costo) FROM ppto_visita WHERE anio >= 2027 AND tipo <> 'componente' GROUP BY anio, mes, patente;
    -- A1 de lo que no tiene kit (camionetas, equipos): su propio gasto.
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, monto)
    SELECT 1, i2.anio, NULL, 'A1', cm.patente, x.base * i2.f
      FROM ppto_camion cm CROSS JOIN _idx i2
      JOIN LATERAL (SELECT sum(t26) / 2 AS base FROM _real rr WHERE rr.activo_id = cm.activo_id AND rr.linea = 'A1' AND rr.fecha >= v_i24) x ON x.base > 0
     WHERE cm.grupo_kit IS NULL;

    -- A2 y A3 por camión y año.
    FOR f IN SELECT * FROM ppto_camion LOOP
        FOR y IN 2027..2029 LOOP
            hor_t := f.horometro + greatest(f.ritmo, 0) * 365.25 * (y - 2026.5);
            e_t := greatest(coalesce(y - f.anio_fab, 99), hor_t / s_hedad);
            SELECT coalesce((SELECT factor FROM ppto_curva_edad WHERE edad = least(floor(greatest(e_t, 0))::INT, 6)), 1) INTO c_t;
            -- Edad equivalente a mitad de la ventana de 24 meses con que se midió su base.
            SELECT coalesce((SELECT factor FROM ppto_curva_edad
                              WHERE edad = least(floor(greatest(coalesce(2025.5 - f.anio_fab, 99), (f.horometro - greatest(f.ritmo, 0) * 365.25) / s_hedad, 0))::INT, 6)), 1) INTO c_w;
            fac := least(c_t / nullif(c_w, 0), 1.5);
            -- La curva se midió en camiones pesados: las camionetas siguen su propio gasto.
            esp := f.base_correctivo * CASE WHEN f.grupo_kit IS NOT NULL THEN coalesce(fac, 1) ELSE 1 END;
            IF f.grupo_kit IS NOT NULL AND e_t < 6 THEN
                esp := greatest(esp, s_mad * c_t * 0.5);
            END IF;
            IF esp > 0 THEN
                INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, monto)
                SELECT 1, y, NULL, 'A2', f.patente, esp * x.f FROM _idx x WHERE x.anio = y;
            END IF;
            v_neu := CASE WHEN f.grupo_kit IS NOT NULL AND f.ritmo >= 1 AND e_t >= 2
                          THEN greatest(f.base_neumatico, s_neu) ELSE f.base_neumatico END;
            IF v_neu > 0 THEN
                INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, monto)
                SELECT 1, y, NULL, 'A3', f.patente, v_neu * x.f FROM _idx x WHERE x.anio = y;
            END IF;
        END LOOP;
    END LOOP;

    -- A4: overhauls de la lista y, si no alcanzan el promedio histórico, una provisión por la diferencia.
    SELECT coalesce(sum(t26), 0) / v_anios INTO v_pool FROM _real WHERE linea = 'A4';
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, descripcion, monto)
    SELECT 1, anio, NULL, 'A4', patente, descripcion, monto FROM ppto_programa WHERE tipo = 'overhaul';
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, descripcion, monto)
    SELECT 1, anio, mes, 'A4', patente, 'Componente ' || nivel || ' por horómetro', costo FROM ppto_visita WHERE tipo = 'componente';
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, descripcion, monto)
    SELECT 1, x.anio, NULL, 'A4', NULL, 'Provisión según historial',
           v_pool * x.f - coalesce((SELECT sum(rr.monto) FROM ppto_resultado rr WHERE rr.version_id = 1 AND rr.linea = 'A4' AND rr.anio = x.anio), 0)
      FROM _idx x
     WHERE v_pool * x.f > coalesce((SELECT sum(rr.monto) FROM ppto_resultado rr WHERE rr.version_id = 1 AND rr.linea = 'A4' AND rr.anio = x.anio), 0);

    -- Pluma (Calama): la mantención de la grúa se proyecta al ritmo de 2026 si supera lo que ya trae el
    -- correctivo de 24 meses. Se reconoce por proveedor: en Softland se compra como «SERVICIOS».
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, descripcion, monto)
    SELECT 1, x.anio, NULL, 'A2', q.patente, 'Mantención de pluma al ritmo 2026', q.ajuste * x.f
      FROM (SELECT cm.patente,
                   coalesce(sum(r.t26) FILTER (WHERE r.fecha >= DATE '2026-01-01'), 0) * 365.0 / greatest(v_fin - DATE '2026-01-01' + 1, 1)
                 - coalesce(sum(r.t26) FILTER (WHERE r.fecha >= v_i24 AND r.linea = 'A2'), 0) / 2 AS ajuste
              FROM ppto_camion cm
              JOIN activos a ON a.id = cm.activo_id
              JOIN _real r ON r.activo_id = cm.activo_id
             WHERE a.tipo_equipamiento::TEXT = 'pluma_grua' AND a.operacion = 'Calama'
               AND r.origen ~* '(PM CHILE|BOLOGNESI|SANDOVAL Y ESPINO)'
             GROUP BY cm.patente) q
      CROSS JOIN _idx x
     WHERE q.ajuste > 0;

    -- B4: certificaciones por vencimiento. TC8 de cada aljibe de combustible en el año en que vence
    -- (5 años por ley); un TC8 ya vencido se presupuesta en 2027. Certificación anual de cada pluma de Calama.
    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, descripcion, monto)
    SELECT 1, greatest(extract(year FROM t.fecha_vencimiento)::INT, 2027), extract(month FROM t.fecha_vencimiento)::INT,
           'B4', cm.patente, 'TC8: vence el ' || to_char(t.fecha_vencimiento, 'DD-MM-YYYY'),
           (SELECT valor FROM ppto_supuesto WHERE clave = 'costo_tc8')
             * (SELECT x.f FROM _idx x WHERE x.anio = greatest(extract(year FROM t.fecha_vencimiento)::INT, 2027))
      FROM ppto_camion cm
      JOIN activos a ON a.id = cm.activo_id
      JOIN LATERAL (SELECT tc.fecha_vencimiento FROM certificaciones tc
                     WHERE tc.activo_id = a.id AND tc.tipo::TEXT = 'tc8_sec' AND tc.anulado_at IS NULL
                     ORDER BY tc.fecha_vencimiento DESC NULLS LAST LIMIT 1) t ON true
     WHERE a.tipo_equipamiento::TEXT = 'aljibe_combustible' AND t.fecha_vencimiento <= DATE '2029-12-31';

    INSERT INTO ppto_resultado (version_id, anio, mes, linea, patente, descripcion, monto)
    SELECT 1, x.anio, NULL, 'B4', cm.patente, 'Certificación anual de pluma',
           (SELECT valor FROM ppto_supuesto WHERE clave = 'costo_cert_pluma') * x.f
      FROM ppto_camion cm JOIN activos a ON a.id = cm.activo_id CROSS JOIN _idx x
     WHERE a.tipo_equipamiento::TEXT = 'pluma_grua' AND a.operacion = 'Calama';

    -- B1: el seguro se paga por cuotas parejas que entran a Softland atrasadas; cuota típica × 12.
    SELECT coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY s), 0) INTO v_seguro
      FROM (SELECT folio, sum(total) AS s FROM _real
             WHERE cod_prod = 'SERSEGSEG002' AND fecha >= v_i12 GROUP BY folio HAVING sum(total) >= 2000000) q;

    -- Líneas sin camión: base anual en pesos 2026.
    TRUNCATE ppto_base;
    INSERT INTO ppto_base (linea, base_anual)
    SELECT l.codigo, CASE
        WHEN l.codigo = 'A1' THEN (SELECT coalesce(sum(t26), 0) FROM _real WHERE linea = 'A1' AND fecha >= v_i12)
        WHEN l.codigo = 'A2' THEN (SELECT coalesce(sum(base_correctivo), 0) FROM ppto_camion)
        WHEN l.codigo = 'A3' THEN (SELECT coalesce(sum(base_neumatico), 0) FROM ppto_camion)
        WHEN l.codigo = 'A4' THEN v_pool
        WHEN l.codigo = 'B1' THEN v_seguro * 12 + (SELECT coalesce(sum(t26), 0) FROM _real WHERE linea = 'B1' AND cod_prod <> 'SERSEGSEG002' AND fecha >= v_i12)
        WHEN l.codigo IN ('B3','C1','C2','C3','C4','C5','C6','C7','C8','D1') THEN (SELECT coalesce(sum(t26), 0) FROM _real x WHERE x.linea = l.codigo AND x.fecha >= v_i12 AND NOT x.unico)
        WHEN l.codigo IN ('A5','B2') THEN (SELECT coalesce(sum(t26), 0) / 2 FROM _real x WHERE x.linea = l.codigo AND x.fecha >= v_i24 AND NOT x.unico)
        ELSE 0 END
      FROM ppto_linea l;

    SELECT coalesce(sum(t26), 0) / v_anios INTO v_reserva FROM _real WHERE linea = 'E1' OR unico;
    UPDATE ppto_base SET base_anual = v_reserva WHERE linea = 'E1';

    INSERT INTO ppto_resultado (version_id, anio, mes, linea, monto)
    SELECT 1, x.anio, NULL, b.linea, b.base_anual * x.f
      FROM ppto_base b CROSS JOIN _idx x
     WHERE b.linea IN ('A5','B1','B2','B3','C1','C2','C3','C4','C5','C6','C7','C8','D1','E1') AND b.base_anual > 0;

    INSERT INTO ppto_resultado (version_id, anio, mes, linea, descripcion, monto)
    SELECT 1, anio, NULL, 'E2', descripcion, monto FROM ppto_programa WHERE tipo = 'opex';

    INSERT INTO ppto_resultado (version_id, anio, mes, linea, monto)
    SELECT 1, anio, NULL, 'E3', sum(monto) * s_cont FROM ppto_resultado
     WHERE version_id = 1 AND linea NOT IN ('D1','E3') GROUP BY anio;

    SELECT round(100 * sum(fl_real) / nullif(sum(fl), 0), 0) INTO v_pct FROM _kit;
    SELECT jsonb_build_object(
        'totales', (SELECT jsonb_object_agg(anio, t) FROM (SELECT anio, round(sum(monto)) t FROM ppto_resultado WHERE version_id = 1 GROUP BY anio) z),
        'kit_pct_precio_real', v_pct,
        'cuota_seguro', round(v_seguro),
        'provision_mayores', round(v_pool),
        'corte', v_fin) INTO r;
    UPDATE ppto_version SET calculado_at = now(), calculado_por = auth.uid(), meta = r WHERE id = 1;
    RETURN r;
END $function$
;

-- Detalle por equipo
CREATE OR REPLACE FUNCTION rpc_ppto_camiones_detalle() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    s_hedad NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'horas_por_anio_edad'), 2500);
    s_mad NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'correctivo_maduro'), 0);
    s_neu NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'neumatico_maduro'), 0);
    r JSONB;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    WITH re AS (
        SELECT activo_id,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2023) AS r23,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2024) AS r24,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2025) AS r25,
               sum(total) FILTER (WHERE extract(year FROM fecha) = 2026) AS r26
          FROM v_ppto_real WHERE linea LIKE 'A%' AND activo_id IS NOT NULL GROUP BY 1
    ), pp AS (
        SELECT patente,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A1') AS prev,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A2') AS corr,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A3') AS neu,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'A4') AS may,
               sum(monto) FILTER (WHERE anio = 2027 AND linea = 'B4') AS cert,
               sum(monto) FILTER (WHERE anio = 2028 AND linea LIKE 'A%') AS t28, sum(monto) FILTER (WHERE anio = 2029 AND linea LIKE 'A%') AS t29
          FROM ppto_resultado WHERE version_id = 1 AND patente IS NOT NULL GROUP BY 1
    ), vi AS (
        SELECT patente, jsonb_agg(jsonb_build_object('tipo', tipo, 'nivel', nivel, 'n', n, 'costo', costo, 'kit', kit) ORDER BY tipo, nivel) AS visitas
          FROM (SELECT patente, tipo, nivel, count(*) AS n, round(sum(costo)) AS costo, round(sum(costo_kit)) AS kit
                  FROM ppto_visita WHERE anio = 2027 GROUP BY 1, 2, 3) x GROUP BY 1
    ), ma AS (
        SELECT patente, jsonb_agg(jsonb_build_object('descripcion', coalesce(descripcion, 'Componente por horómetro'), 'monto', round(monto))) AS mayores
          FROM ppto_resultado WHERE version_id = 1 AND anio = 2027 AND linea = 'A4' AND patente IS NOT NULL GROUP BY 1
    ), ce AS (
        SELECT patente, jsonb_agg(jsonb_build_object('anio', anio, 'descripcion', descripcion, 'monto', round(monto)) ORDER BY anio) AS certs
          FROM ppto_resultado WHERE version_id = 1 AND linea = 'B4' AND patente IS NOT NULL GROUP BY 1
    ), pa AS (
        SELECT patente, jsonb_agg(jsonb_build_object('descripcion', descripcion, 'monto', round(monto))) AS partidas
          FROM ppto_resultado WHERE version_id = 1 AND anio = 2027 AND linea = 'A2' AND descripcion IS NOT NULL AND patente IS NOT NULL GROUP BY 1
    ), ed AS (
        -- Edad equivalente y factor de la curva, igual que fn_ppto_recalcular para 2027.
        SELECT c.patente,
               greatest(coalesce(2027 - c.anio_fab, 99), (c.horometro + greatest(c.ritmo, 0) * 365.25 * 0.5) / s_hedad) AS e27,
               greatest(coalesce(2025.5 - c.anio_fab, 99), (c.horometro - greatest(c.ritmo, 0) * 365.25) / s_hedad, 0) AS ew
          FROM ppto_camion c
    ), fa AS (
        SELECT ed.patente, ed.e27,
               coalesce((SELECT factor FROM ppto_curva_edad WHERE edad = least(floor(greatest(ed.e27, 0))::INT, 6)), 1) AS c27,
               coalesce((SELECT factor FROM ppto_curva_edad WHERE edad = least(floor(ed.ew)::INT, 6)), 1) AS cw
          FROM ed
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'patente', c.patente, 'codigo', a.codigo, 'nombre', a.nombre, 'modelo', c.modelo, 'anio_fab', c.anio_fab,
        'familia', CASE coalesce(a.tipo_equipamiento::TEXT, '')
            WHEN 'aljibe_combustible' THEN 'Aljibe combustible' WHEN 'aljibe_agua' THEN 'Aljibe agua / riego'
            WHEN 'camioneta' THEN 'Camioneta' WHEN 'pluma_grua' THEN 'Camión pluma' WHEN 'grua_horquilla' THEN 'Grúa horquilla'
            WHEN 'ampliroll' THEN 'Polibrazo' WHEN 'generico' THEN 'Carrocería plana' ELSE 'Otros' END,
        'contrato', cs.contrato, 'faena', c.faena, 'estado_comercial', c.estado_comercial,
        'real', jsonb_build_object('2023', coalesce(re.r23, 0), '2024', coalesce(re.r24, 0), '2025', coalesce(re.r25, 0), '2026', coalesce(re.r26, 0)),
        'preventivo', round(coalesce(pp.prev, 0)), 'correctivo', round(coalesce(pp.corr, 0)),
        'neumaticos', round(coalesce(pp.neu, 0)), 'mayores', round(coalesce(pp.may, 0)),
        'certificaciones', round(coalesce(pp.cert, 0)),
        'total_2028', round(coalesce(pp.t28, 0)), 'total_2029', round(coalesce(pp.t29, 0)),
        'base', jsonb_build_object(
            'con_pauta', c.grupo_kit IS NOT NULL, 'grupo_kit', c.grupo_kit,
            'intervalo_horas', (SELECT intervalo_horas FROM ppto_modelo_grupo g WHERE g.modelo = c.modelo),
            'horometro', round(c.horometro), 'ritmo', round(c.ritmo, 2), 'ritmo_fuente', c.ritmo_fuente,
            'ritmo_18m', round(c.ritmo_18m, 2), 'ritmo_mejor_mes', round(c.ritmo_mejor_mes, 2), 'mejor_mes', c.mejor_mes,
            'horas_2027', round(greatest(c.ritmo, 0) * 365.25),
            'visitas', coalesce(vi.visitas, '[]'::jsonb),
            'correctivo_base', round(coalesce(c.base_correctivo, 0)),
            'edad_equivalente', round(fa.e27, 1),
            'factor_edad', CASE WHEN c.grupo_kit IS NOT NULL THEN round(least(fa.c27 / nullif(fa.cw, 0), 1.5), 2) END,
            'piso_correctivo', CASE WHEN c.grupo_kit IS NOT NULL AND fa.e27 < 6 THEN round(s_mad * fa.c27 * 0.5) END,
            'neumatico_base', round(coalesce(c.base_neumatico, 0)),
            'neumatico_piso', CASE WHEN c.grupo_kit IS NOT NULL AND c.ritmo >= 1 AND fa.e27 >= 2 THEN s_neu END,
            'mayores', coalesce(ma.mayores, '[]'::jsonb),
            'certificaciones', coalesce(ce.certs, '[]'::jsonb),
            'partidas_correctivo', coalesce(pa.partidas, '[]'::jsonb))
    ) ORDER BY c.patente), '[]') INTO r
      FROM ppto_camion c
      LEFT JOIN activos a ON a.id = c.activo_id
      LEFT JOIN ppto_contrato_servicio cs ON cs.patente = c.patente
      LEFT JOIN re ON re.activo_id = c.activo_id
      LEFT JOIN pp ON pp.patente = c.patente
      LEFT JOIN vi ON vi.patente = c.patente
      LEFT JOIN ma ON ma.patente = c.patente
      LEFT JOIN ce ON ce.patente = c.patente
      LEFT JOIN pa ON pa.patente = c.patente
      LEFT JOIN fa ON fa.patente = c.patente;
    RETURN r;
END $$;

REVOKE ALL ON FUNCTION rpc_ppto_camiones_detalle() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ppto_camiones_detalle() TO anon, authenticated;

SELECT fn_ppto_recalcular();
