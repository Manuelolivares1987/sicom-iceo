-- 706 — Correctivo y overhaul explicados por equipo; sin doble conteo de la preventiva (Manuel 17-11-2026).
-- destructivo-ok: los TRUNCATE de fn_ppto_recalcular solo vacían ppto_camion, ppto_visita, ppto_base y ppto_kit_costo, resultados propios que la función regenera completos (igual que MIG670).
-- En los equipos con pauta, el correctivo de 24 meses traía mantenciones preventivas hechas en taller o
-- concesionario («KIT MANTENCION», «SERVICIO MANTENCION CAMION»): ~$12,9 MM en 24 meses que el preventivo
-- por pauta ya cuenta. Manuel: sacar solo las de descripción clara; los servicios de concesionario sin
-- detalle se quedan, pero se muestran aparte. Nueva consulta con la composición de cada equipo.

CREATE OR REPLACE FUNCTION fn_ppto_categoria_correctivo(p_des TEXT, p_prov TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_des ~* '(mantenci[oó]n (camion|preventiv|de \d|\d)|kit mant|servicio \d+ ?(hrs|horas|km)|pauta|preventiv|servicio (de )?lubricaci)'
            THEN 'Mantención preventiva (ya va en el preventivo)'
        WHEN p_prov ~* '(PM CHILE|BOLOGNESI|SANDOVAL Y ESPINO)' THEN 'Pluma'
        WHEN p_prov ~* '(VOLVO CHILE|SCANIA CHILE|KAUFMANN|SALINAS Y FABRES|DERCO)' AND p_des ~* '^\s*(servicios?|servicios repuestos)\s*$'
            THEN 'Servicio de concesionario sin detalle'
        WHEN p_des ~* '(siniestr|deducible|choque|colisi)' THEN 'Siniestro'
        WHEN p_des ~* '^\s*(servicios?|servicios de reparaciones varias|servicio de reparaciones menores|reparacion camion|traslado|evaluacion y diagnostico)\s*$'
            THEN 'Servicio genérico sin detalle'
        ELSE 'Repuestos y reparaciones' END
$$;

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
    SELECT activo_id, linea, fecha, cod_prod, folio, total, origen, des_prod,
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
    TRUNCATE ppto_kit_costo;
    INSERT INTO ppto_kit_costo (grupo_kit, nivel, costo, fl) SELECT grupo_kit, nivel, costo, fl FROM _kit;

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
           coalesce((SELECT sum(t26) FROM _real x WHERE x.activo_id = m.id AND x.linea = 'A2' AND x.fecha >= v_i24
                       AND NOT (m.grupo_kit IS NOT NULL AND fn_ppto_categoria_correctivo(x.des_prod, x.origen) = 'Mantención preventiva (ya va en el preventivo)')), 0) / 2,
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

-- Composición de un equipo: real por componente y año, la base del correctivo y lo que forma el overhaul.
CREATE OR REPLACE FUNCTION rpc_ppto_equipo_composicion(p_patente TEXT) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_corte DATE := coalesce((SELECT (meta->>'corte')::DATE FROM ppto_version WHERE id = 1), (date_trunc('month', now()) - interval '1 day')::DATE);
    v_i24 DATE;
    v_i36 DATE;
    v_hist NUMERIC := coalesce((SELECT valor FROM ppto_supuesto WHERE clave = 'ipc_historico'), 0);
    v_activo UUID;
    v_kit BOOLEAN;
BEGIN
    IF NOT fn_costos_operacion_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver costos de operación.' USING ERRCODE = '42501';
    END IF;
    v_i24 := (v_corte + 1 - interval '24 months')::DATE;
    v_i36 := (v_corte + 1 - interval '36 months')::DATE;
    SELECT activo_id, grupo_kit IS NOT NULL INTO v_activo, v_kit FROM ppto_camion WHERE patente = p_patente;
    IF v_activo IS NULL THEN RETURN NULL; END IF;
    RETURN (
    WITH r AS (
        SELECT fecha, linea, des_prod, origen, total, folio,
               total * power(1 + v_hist, 2026 - extract(year FROM fecha)::INT) AS t26,
               fn_ppto_categoria_correctivo(des_prod, origen) AS cat
          FROM v_ppto_real WHERE activo_id = v_activo
    ), base AS (
        SELECT *, (v_kit AND cat = 'Mantención preventiva (ya va en el preventivo)') AS excluida
          FROM r WHERE linea = 'A2' AND fecha BETWEEN v_i24 AND v_corte
    )
    SELECT jsonb_build_object(
        'corte', v_corte, 'ventana_desde', v_i24, 'ipc_historico', v_hist,
        'real', (SELECT jsonb_object_agg(l, a) FROM (
                   SELECT l, jsonb_object_agg(y::TEXT, coalesce(m, 0)) AS a
                     FROM unnest(ARRAY['A1','A2','A3','A4','B4']) l
                     CROSS JOIN generate_series(2023, 2026) y
                     LEFT JOIN LATERAL (SELECT round(sum(total)) AS m FROM r WHERE r.linea = l AND extract(year FROM r.fecha) = y) x ON true
                    GROUP BY l) z),
        'ppto', (SELECT jsonb_object_agg(linea, jsonb_build_object('2027', a27, '2028', a28, '2029', a29)) FROM (
                   SELECT linea, round(sum(monto) FILTER (WHERE anio = 2027)) a27, round(sum(monto) FILTER (WHERE anio = 2028)) a28, round(sum(monto) FILTER (WHERE anio = 2029)) a29
                     FROM ppto_resultado WHERE version_id = 1 AND patente = p_patente GROUP BY linea) q),
        'correctivo_categorias', (SELECT coalesce(jsonb_agg(jsonb_build_object('categoria', cat, 'excluida', excluida, 'monto', round(sum_t), 'monto_2026', round(sum_t26), 'n', n) ORDER BY excluida, sum_t DESC), '[]') FROM (
                   SELECT cat, excluida, sum(total) sum_t, sum(t26) sum_t26, count(*) n FROM base GROUP BY 1, 2) c),
        'correctivo_compras', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', fecha, 'categoria', cat, 'excluida', excluida, 'proveedor', origen,
                                       'descripcion', des_prod, 'folio', folio, 'monto', round(total)) ORDER BY total DESC), '[]') FROM base),
        'overhaul_2027', (SELECT coalesce(jsonb_agg(jsonb_build_object('anio', rr.anio, 'descripcion', coalesce(rr.descripcion, 'Componente por horómetro'), 'monto', round(rr.monto),
                                       'gatillo', (SELECT pg.gatillo FROM ppto_programa pg WHERE pg.tipo = 'overhaul' AND pg.patente = p_patente AND pg.anio = rr.anio AND pg.descripcion = rr.descripcion LIMIT 1)) ORDER BY rr.anio, rr.monto DESC), '[]')
                            FROM ppto_resultado rr WHERE rr.version_id = 1 AND rr.linea = 'A4' AND rr.patente = p_patente),
        'overhaul_historia', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', fecha, 'proveedor', origen, 'descripcion', des_prod, 'monto', round(total)) ORDER BY fecha DESC), '[]')
                              FROM r WHERE linea = 'A4'),
        'neumaticos_compras', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', fecha, 'proveedor', origen, 'descripcion', des_prod, 'monto', round(total)) ORDER BY fecha DESC), '[]')
                               FROM r WHERE linea = 'A3' AND fecha BETWEEN v_i36 AND v_corte)
    ));
END $$;
REVOKE ALL ON FUNCTION rpc_ppto_equipo_composicion(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_ppto_equipo_composicion(TEXT) TO anon, authenticated;

SELECT fn_ppto_recalcular();
