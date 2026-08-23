-- ============================================================================
-- MIG333 · Los tres entregables dejan de tipearse a mano
-- ----------------------------------------------------------------------------
-- El cierre termina en tres documentos que hoy se llenan a mano, celda por
-- celda, desde datos que el sistema ya tiene:
--
--   CIERRE ROMERAL   una hoja por día con las mediciones físicas y los
--                    numerales, más una hoja por estación con el movimiento
--                    del mes
--   FORM AC 066      el stock de cada estanque día por día, con el KPI de
--                    llenado y las recepciones
--   BBDD             la lista plana de transacciones con la Semana ENAP
--
-- Esa doble digitación no es sólo lenta: es el origen de la mitad de los
-- hallazgos. La hoja de Casa Fuerza se abandonó el día 2 porque nadie alcanza
-- a tipear cuatro veces lo mismo. Lo que no se tipea, no existe; y lo que se
-- tipea dos veces, se contradice.
--
-- LA SEMANA ENAP
-- No es la semana ISO. Va de jueves a miércoles y se recorta en los bordes del
-- mes: la semana que cruza el 31 se parte en dos, porque la facturación es
-- mensual. Una venta con la semana equivocada se factura en el período
-- equivocado. La regla estaba dentro de la aplicación del mundo Orpak; acá
-- queda escrita y verificable.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_semana_enap(p_fecha date)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    -- De jueves a miercoles. EXTRACT(DOW) da domingo=0 ... jueves=4, asi que
    -- (dow + 3) % 7 son los dias transcurridos desde el jueves anterior.
    WITH d AS (
        SELECT p_fecha AS f,
               ((EXTRACT(DOW FROM p_fecha)::int + 3) % 7) AS desde_jueves,
               date_trunc('month', p_fecha)::date AS primero,
               (date_trunc('month', p_fecha) + INTERVAL '1 month - 1 day')::date AS ultimo
    ), r AS (
        -- El recorte por el borde del mes: la semana nunca cruza el cambio de
        -- mes porque la facturacion es mensual.
        SELECT GREATEST(d.f - d.desde_jueves, d.primero) AS inicio,
               LEAST(d.f - d.desde_jueves + 6, d.ultimo)  AS fin
          FROM d
    )
    SELECT to_char(r.inicio, 'DD/MM') || ' AL ' || to_char(r.fin, 'DD/MM') FROM r;
$f$;

COMMENT ON FUNCTION public.fn_semana_enap(date) IS
  'Semana ENAP: jueves a miercoles, recortada en los bordes del mes. No es la semana ISO. MIG333.';

-- ── BBDD: la lista plana que se copia al final del cierre ──────────────────
CREATE OR REPLACE VIEW public.v_comb_bbdd AS
SELECT t.faena_id,
       row_number() OVER (PARTITION BY t.faena_id ORDER BY t.dia_cierre, t.hora, t.id) AS id,
       t.fecha, t.hora, t.flota, t.vehiculo AS equipo, t.producto,
       t.litros AS volumen, t.estacion_texto AS estacion, t.departamento,
       t.tarjeta, t.autorizado_por, t.bomba,
       t.clasificacion AS registro_manual,
       t.ceco_codigo,
       t.dia_cierre,
       public.fn_semana_enap(t.dia_cierre) AS semana_enap,
       'orpak'::text AS origen
FROM combustible_orpak_transaccion t
UNION ALL
-- Los camiones aljibe no pasan por Orpak: los registra la app de terreno.
-- Van a la misma BBDD, en el mismo formato, para que el entregable salga
-- completo en un solo paso.
SELECT d.faena_id,
       row_number() OVER (PARTITION BY d.faena_id ORDER BY d.fecha, d.hora, d.id) AS id,
       d.fecha, d.hora::text, d.flota, COALESCE(d.equipo_texto, q.nombre), 'Diesel',
       d.litros, e.nombre, COALESCE(c.codigo, d.ceco_texto),
       NULL, d.operador_nombre, NULL,
       CASE d.tipo_movimiento WHEN 'trasvasije' THEN 'TRASVASIJE'
                              WHEN 'recirculacion' THEN 'RECIRCULACION'
                              ELSE 'CMP' END,
       COALESCE(c.codigo, d.ceco_texto),
       d.fecha,
       public.fn_semana_enap(d.fecha),
       'terreno'
FROM combustible_faena_despachos d
JOIN combustible_estanques e ON e.id = d.estanque_id
LEFT JOIN combustible_faena_equipos q ON q.id = d.equipo_id
LEFT JOIN combustible_faena_cecos   c ON c.id = d.ceco_id
WHERE NOT d.anulado;

GRANT SELECT ON public.v_comb_bbdd TO authenticated;

-- ── FORM AC 066: el stock de cada estanque, día por día ────────────────────
CREATE OR REPLACE VIEW public.v_comb_form_ac066 AS
SELECT c.faena_id, c.fecha,
       e.id AS estanque_id, e.nombre AS estanque, e.orden_cierre, e.grupo_cuadre,
       e.capacidad_lt      AS capacidad_nominal,
       e.capacidad_llenado_lt AS capacidad_llenado,
       p.mf AS stock,
       CASE WHEN e.capacidad_llenado_lt > 0
            THEN round(p.mf / e.capacidad_llenado_lt, 6) END AS kpi_llenado,
       COALESCE(p.rfp, 0) AS recibido_flota_primaria,
       COALESCE(p.rt, 0)  AS recibido_trasvasije,
       p.agua_mm,
       p.sin_medicion
FROM combustible_faena_cierre c
JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
JOIN combustible_estanques e ON e.id = p.estanque_id;

GRANT SELECT ON public.v_comb_form_ac066 TO authenticated;

CREATE OR REPLACE VIEW public.v_comb_form_ac066_dia AS
SELECT f.faena_id, f.fecha,
       sum(f.stock)                     AS stock_total,
       sum(f.capacidad_llenado)         AS capacidad_total,
       CASE WHEN sum(f.capacidad_llenado) > 0
            THEN round(sum(f.stock) / sum(f.capacidad_llenado), 6) END AS kpi_diario,
       sum(f.recibido_flota_primaria)   AS recibido_total,
       (SELECT count(*) FROM v_comb_faena_recepcion r
         WHERE r.faena_id = f.faena_id AND r.fecha = f.fecha AND NOT r.anulada) AS camiones_recepcionados
FROM v_comb_form_ac066 f
WHERE NOT f.sin_medicion
GROUP BY f.faena_id, f.fecha;

GRANT SELECT ON public.v_comb_form_ac066_dia TO authenticated;

-- ── Cierre Romeral: la hoja mensual por estación ───────────────────────────
CREATE OR REPLACE VIEW public.v_comb_cierre_romeral_mes AS
SELECT p.faena_id, p.fecha, p.estanque_id, p.estanque_nombre,
       e.orden_cierre, e.grupo_cuadre,
       p.mi  AS saldo_inicial,
       p.rfp AS recepcion_camion,
       p.rt  AS trasvasije_recibido,
       p.mf  AS saldo_final,
       p.v_fis AS salida_por_varilla,
       p.v_mec AS salida_por_contador,
       p.agua_mm,
       -- Lo que este punto le entregó a cada camión aljibe, que en la planilla
       -- va en una columna por camión.
       (SELECT COALESCE(sum(d.litros), 0)
          FROM combustible_faena_despachos d
         WHERE d.faena_id = p.faena_id AND d.fecha = p.fecha
           AND d.estanque_id = p.estanque_id AND NOT d.anulado
           AND d.tipo_movimiento = 'trasvasije') AS trasvasije_entregado,
       (SELECT COALESCE(sum(t.litros), 0)
          FROM combustible_orpak_transaccion t
         WHERE t.faena_id = p.faena_id AND t.dia_cierre = p.fecha
           AND t.estanque_id = p.estanque_id
           AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION')) AS despacho_orpak,
       p.sin_medicion, p.motivo_sin_medicion, p.medido_por, p.estado
FROM v_comb_faena_cierre_punto p
JOIN combustible_estanques e ON e.id = p.estanque_id;

GRANT SELECT ON public.v_comb_cierre_romeral_mes TO authenticated;

-- ── Cierre Romeral: la hoja del día, con numerales ─────────────────────────
CREATE OR REPLACE VIEW public.v_comb_cierre_romeral_numerales AS
SELECT c.faena_id, c.fecha, e.nombre AS estanque, e.orden_cierre,
       md.surtidor, md.numero AS cuentalitros, md.etiqueta,
       cm.numeral_ini, cm.numeral_fin, cm.calibracion,
       CASE WHEN cm.numeral_fin IS NULL OR cm.numeral_ini IS NULL THEN NULL
            WHEN cm.reinicio_contador THEN NULL
            ELSE cm.numeral_fin - cm.numeral_ini + COALESCE(cm.calibracion, 0) END AS despachado,
       cm.reinicio_contador, cm.motivo_reinicio,
       cm.foto_url IS NOT NULL AS con_foto
FROM combustible_faena_cierre c
JOIN combustible_faena_cierre_medidor cm ON cm.cierre_id = c.id
JOIN combustible_faena_medidores md ON md.id = cm.medidor_id
JOIN combustible_estanques e ON e.id = md.estanque_id;

GRANT SELECT ON public.v_comb_cierre_romeral_numerales TO authenticated;

COMMIT;
