-- 684 — Presupuesto sin alza por edad en el correctivo (Manuel 09-11-2026: «me la van a cuestionar»).
-- destructivo-ok: fn_ppto_recalcular vacía y regenera solo sus tablas de resultado (ppto_camion, ppto_visita, ppto_base, ppto_resultado versión 1).
-- El correctivo (A2) queda en el gasto real de los últimos 24 meses de cada camión, a IPC: sin curva de edad
-- ni piso por camión maduro. Se puede volver a activar con el supuesto «Alza por edad en correctivo».
-- Recalcula con los datos de hoy, que ya incluyen los litros verificados de MIG683.

INSERT INTO ppto_supuesto (clave, nombre, valor, unidad, nota, orden)
VALUES ('aplicar_curva_edad', 'Alza por edad en correctivo (100 % = aplicar, 0 % = no)', 0, 'pct',
        'Apagada: el correctivo sigue el gasto real de cada camión. Era criterio, no gasto observado.', 65);

UPDATE ppto_linea SET metodo = 'Gasto real de los últimos 24 meses de cada camión, a IPC. Sin alza por edad (supuesto «Alza por edad en correctivo»). Incluye lo que no es filtro ni lubricante de las pautas.'
 WHERE codigo = 'A2';

CREATE OR REPLACE FUNCTION fn_ppto_recalcular() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::DATE;
    v_fin DATE := date_trunc('month', (now() AT TIME ZONE 'America/Santiago'))::DATE - 1;
    v_i12 DATE; v_i24 DATE; v_i36 DATE;
    v_anios NUMERIC;
    s_hist NUMERIC; s_cont NUMERIC; s_mad NUMERIC; s_neu NUMERIC; s_hedad NUMERIC; s_sind NUMERIC; s_cal NUMERIC; s_curva NUMERIC;
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
    SELECT coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'aplicar_curva_edad'), 1) INTO s_curva;

    DROP TABLE IF EXISTS _idx, _real, _kit;
    CREATE TEMP TABLE _idx ON COMMIT DROP AS
    SELECT 2027 AS anio, 1 + (SELECT valor FROM ppto_supuesto WHERE clave='ipc_2027') AS f;
    INSERT INTO _idx SELECT 2028, x.f * (1 + (SELECT valor FROM ppto_supuesto WHERE clave='ipc_2028')) FROM _idx x WHERE x.anio = 2027;
    INSERT INTO _idx SELECT 2029, x.f * (1 + (SELECT valor FROM ppto_supuesto WHERE clave='ipc_2029')) FROM _idx x WHERE x.anio = 2028;

    -- Real a pesos 2026 hasta el último mes cerrado.
    CREATE TEMP TABLE _real ON COMMIT DROP AS
    SELECT activo_id, linea, fecha, cod_prod, folio, total,
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
    INSERT INTO ppto_camion (patente, activo_id, modelo, anio_fab, estado_comercial, faena, grupo_kit, horometro, ritmo, ritmo_fuente, base_correctivo, base_neumatico)
    WITH larga AS (
        SELECT activo_id, horas / nullif(dias, 0) AS hd FROM fn_activo_ventana_horas(v_hoy - 548, v_hoy)
         WHERE dias >= 90 AND horas / nullif(dias, 0) <= 14
    ), b AS (
        SELECT a.patente, a.id, mo.nombre AS modelo, a.anio_fabricacion, a.estado_comercial::TEXT AS ec,
               e.faena, g.grupo_kit, coalesce(e.horometro, a.horas_uso_actual, 0) AS hor,
               aj.ritmo_manual, e.horas_por_dia AS r30, l.hd AS rl
          FROM activos a
          LEFT JOIN modelos mo ON mo.id = a.modelo_id
          LEFT JOIN ppto_modelo_grupo g ON g.modelo = mo.nombre
          LEFT JOIN v_equipo_horas e ON e.activo_id = a.id
          LEFT JOIN larga l ON l.activo_id = a.id
          LEFT JOIN ppto_flota_ajuste aj ON aj.patente = a.patente
         WHERE a.patente IS NOT NULL AND a.estado::TEXT <> 'dado_baja'
           AND coalesce(a.es_prueba, false) = false AND coalesce(a.es_externo, false) = false
           AND coalesce(a.estado_comercial::TEXT, '') <> 'en_venta'
           AND coalesce(aj.incluido, true)
    ), m AS (
        SELECT b.*, CASE WHEN r30 IS NOT NULL AND rl IS NOT NULL THEN (r30 + rl) / 2 ELSE coalesce(r30, rl) END AS medido FROM b
    ), p AS (
        SELECT modelo, avg(medido) AS par FROM m WHERE medido IS NOT NULL GROUP BY 1
    )
    SELECT m.patente, m.id, m.modelo, m.anio_fabricacion, m.ec, m.faena, m.grupo_kit, m.hor,
           coalesce(m.ritmo_manual, m.medido, p.par, s_sind),
           CASE WHEN m.ritmo_manual IS NOT NULL THEN 'Manual'
                WHEN m.r30 IS NOT NULL AND m.rl IS NOT NULL THEN 'GPS último mes y 18 meses'
                WHEN m.r30 IS NOT NULL THEN 'GPS último mes'
                WHEN m.rl IS NOT NULL THEN 'Lecturas 18 meses'
                WHEN p.par IS NOT NULL THEN 'Sin dato: promedio del modelo'
                ELSE 'Sin dato: supuesto' END,
           coalesce((SELECT sum(t26) FROM _real x WHERE x.activo_id = m.id AND x.linea = 'A2' AND x.fecha >= v_i24), 0) / 2,
           coalesce((SELECT sum(t26) FROM _real x WHERE x.activo_id = m.id AND x.linea = 'A3' AND x.fecha >= v_i36), 0) / 3
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
            esp := f.base_correctivo * CASE WHEN f.grupo_kit IS NOT NULL AND s_curva > 0 THEN coalesce(fac, 1) ELSE 1 END;
            IF f.grupo_kit IS NOT NULL AND e_t < 6 AND s_curva > 0 THEN
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
END $$;

SELECT fn_ppto_recalcular() IS NOT NULL AS recalculado;
SELECT anio, round(sum(monto) / 1e6, 1) AS total_mm, round(sum(monto) FILTER (WHERE linea = 'A2') / 1e6, 1) AS a2_mm
  FROM ppto_resultado WHERE version_id = 1 GROUP BY anio ORDER BY anio;
