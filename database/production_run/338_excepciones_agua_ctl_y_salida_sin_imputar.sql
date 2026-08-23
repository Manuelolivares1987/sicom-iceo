-- ============================================================================
-- MIG338 · Tres controles que existían y no llegaban a nadie
-- ----------------------------------------------------------------------------
-- El agua de fondo, la corrección por temperatura y la salida sin imputar se
-- calculaban bien y no aparecían en la única pantalla que alguien abre todos
-- los días. Un control que hay que ir a buscar no es un control: es un dato.
--
-- 1. AGUA EN EL FONDO DEL ESTANQUE
--    Sobre 15 mm hay que drenar; sobre 25 mm hay que hacerlo antes del próximo
--    despacho. El agua corroe el estanque desde abajo, arruina inyectores y,
--    pasado cierto nivel, entra a la succión y se va a los equipos. Se medía
--    en cada cierre y no la miraba nadie.
--
-- 2. LA DIFERENCIA POR TEMPERATURA CONTRA LA GUÍA
--    ENAP factura a 15 °C. El estanque recibe a la temperatura a la que viene
--    el camión. 30.000 litros facturados a 15 °C recibidos a 25 °C ocupan unos
--    260 litros más — y esos 260 litros, mirados sin corregir, parecen una
--    diferencia de medición que nadie sabe explicar. Corregidos, dejan de ser
--    un misterio y pasan a ser física.
--
--    Se avisa sólo cuando la corrección explica una parte apreciable de la
--    diferencia: si la guía cuadra al litro, la temperatura es irrelevante y no
--    hay nada que decir.
--
-- 3. SALIÓ COMBUSTIBLE Y NO HAY A QUIÉN IMPUTARLO
--    Cuando la varilla y el cuentalitros coinciden en que salieron litros y el
--    sistema no tiene ninguna transacción. Es el hallazgo más grave que puede
--    dar un control de inventario y estaba sólo en una vista aparte.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_comb_faena_excepciones AS
 SELECT c.faena_id, NULL::date AS fecha, 'ceco_por_confirmar'::text AS tipo,
        c.codigo AS referencia,
        'CECO ' || c.codigo || ' anotado por ' || COALESCE(c.anotado_por, 'terreno') AS detalle,
        c.litros, c.despachos AS cantidad
   FROM v_comb_faena_ceco_por_confirmar c
UNION ALL
 SELECT d.faena_id, d.fecha, 'despacho_sin_ceco'::text,
        COALESCE(e.nombre, d.equipo_texto, 'equipo sin identificar'),
        'Carga sin CECO' || COALESCE(' a ' || COALESCE(e.nombre, d.equipo_texto), ''),
        d.litros, 1
   FROM combustible_faena_despachos d
   LEFT JOIN combustible_faena_equipos e ON e.id = d.equipo_id
  WHERE NOT d.anulado AND d.ceco_id IS NULL AND d.tipo_movimiento = 'venta'
UNION ALL
 SELECT g.faena_id, g.fecha, 'fuera_de_tolerancia'::text, g.puntos,
        'Varilla ' || round(g.v_fis) || ' L contra contador ' || round(g.v_mec)
          || ' L · diferencia ' || round(g.var1) || ' L',
        abs(g.var1), g.tanques
   FROM v_comb_faena_cuadre_grupo g
  WHERE g.resultado = 'investigar'
UNION ALL
 SELECT g.faena_id, g.fecha, 'contador_sin_leer'::text, g.puntos,
        'Se midió la varilla pero faltan ' || (g.medidores_total - g.medidores_leidos)
          || ' de ' || g.medidores_total || ' contadores. Sin eso no hay control cruzado.',
        NULL::numeric, (g.medidores_total - g.medidores_leidos)::integer
   FROM v_comb_faena_cuadre_grupo g
  WHERE g.resultado = 'incompleto'
UNION ALL
 SELECT c.faena_id, c.fecha, 'medicion_sin_foto'::text, e.nombre,
        'Medición sin foto ni motivo escrito', NULL::numeric, 1
   FROM combustible_faena_cierre_punto p
   JOIN combustible_faena_cierre c ON c.id = p.cierre_id
   JOIN combustible_estanques e ON e.id = p.estanque_id
  WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
    AND COALESCE(p.foto_url, '') = '' AND COALESCE(p.sin_foto_motivo, '') = ''
UNION ALL
 SELECT r.faena_id, r.fecha, 'recepcion_con_diferencia'::text,
        COALESCE(r.guia, r.camion, 'sin guía'),
        'Guía ' || round(r.litros_guia) || ' L, recibidos ' || round(r.litros_recibidos) || ' L',
        abs(r.diferencia_vs_guia), 1
   FROM v_comb_faena_recepcion r
  WHERE r.diferencia_vs_guia IS NOT NULL AND abs(r.diferencia_vs_guia) > 0

-- ── Lo nuevo ───────────────────────────────────────────────────────────────
UNION ALL
 SELECT s.faena_id, s.fecha, 'salida_sin_imputar'::text, s.puntos,
        'Salieron ' || round(s.litros_sin_imputar) || ' L confirmados por varilla y contador,'
          || ' y el sistema no tiene ninguna transacción. No se sabe a quién cargarlos.',
        s.litros_sin_imputar, 1
   FROM v_comb_faena_salida_sin_imputar s
UNION ALL
 SELECT a.faena_id, a.fecha, 'agua_en_estanque'::text, a.estanque,
        CASE a.nivel
          WHEN 'critica' THEN 'Agua a ' || a.agua_mm || ' mm. Drenar antes del próximo despacho:'
                              || ' a este nivel entra a la succión.'
          ELSE 'Agua a ' || a.agua_mm || ' mm. Programar drenaje.'
        END,
        NULL::numeric, a.agua_mm::integer
   FROM v_comb_faena_agua a
  WHERE a.nivel IN ('alerta', 'critica')
UNION ALL
 SELECT t.faena_id, t.fecha, 'diferencia_por_temperatura'::text,
        COALESCE(t.guia, t.camion, 'sin guía'),
        'A ' || t.temperatura_c || ' °C la guía de ' || round(t.litros_guia)
          || ' L equivale a ' || round(t.recibido_a_15c) || ' L a 15 °C:'
          || ' la temperatura explica ' || round(t.litros_recibidos - t.recibido_a_15c) || ' L.',
        abs(t.litros_recibidos - t.recibido_a_15c), 1
   FROM v_comb_faena_recepcion_ctl t
  WHERE t.ctl IS NOT NULL AND t.litros_guia IS NOT NULL
    -- Si la guia cuadra al litro, la temperatura es irrelevante y no hay nada
    -- que decir. Sólo se avisa cuando explica algo de una diferencia real.
    AND abs(COALESCE(t.diferencia_vs_guia, 0)) > 50
    AND abs(t.litros_recibidos - t.recibido_a_15c) > 30;

COMMENT ON VIEW public.v_comb_faena_excepciones IS
  'Todo lo que se sale del patron, en un solo lugar. Control por excepcion: revisar el 100% es no revisar nada. MIG321, ampliada en MIG338 con agua, correccion por temperatura y salida sin imputar.';

COMMIT;
