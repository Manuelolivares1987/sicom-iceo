-- MIG606: el cierre del sync Softland volvió a caber en el límite del rol anon.
--
-- MIG602 agregó al cierre el refresco de mv_activo_gps_dia y mv_activo_faena_dia
-- (~30 s). El agente llama con la anon key y anon tiene statement_timeout=3s, así
-- que desde el 15-10 cada corrida terminaba en 500: se subían los documentos pero
-- se deshacía el cierre (borrados, refresco de mv_softland_costo_mes y log) y el
-- panel de costos quedaba congelado.
--
-- El cierre ahora refresca solo mv_softland_costo_mes (~0,6 s). Las dos vistas
-- GPS las refresca el cron 'refrescar-faena-dia' (15:00 UTC, después del sync).

CREATE OR REPLACE FUNCTION rpc_softland_cerrar_corrida(
    p_secreto TEXT, p_run UUID, p_inicio TIMESTAMPTZ, p_desde DATE, p_stats JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_borrados INTEGER := 0;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;

    IF p_desde IS NOT NULL THEN
        DELETE FROM softland_doc
         WHERE fecha >= p_desde AND run_id IS DISTINCT FROM p_run;
        GET DIAGNOSTICS v_borrados = ROW_COUNT;
    END IF;

    INSERT INTO softland_cc (codigo, area, zona)
    SELECT DISTINCT d.codi_cc, k.area, k.zona
      FROM softland_doc d
      CROSS JOIN LATERAL fn_softland_cc_clasificar(d.codi_cc, NULL) k
     WHERE d.codi_cc IS NOT NULL
    ON CONFLICT (codigo) DO NOTHING;

    REFRESH MATERIALIZED VIEW mv_softland_costo_mes;

    INSERT INTO softland_sync_log (run_id, inicio, desde, docs, docs_cambiados, lineas,
                                   borrados, equipo, detalle)
    VALUES (p_run, p_inicio, p_desde,
            (p_stats->>'docs')::INTEGER, (p_stats->>'cambiados')::INTEGER,
            (p_stats->>'lineas')::INTEGER, v_borrados, p_stats->>'equipo', p_stats)
    ON CONFLICT (run_id) DO NOTHING;

    RETURN jsonb_build_object('borrados', v_borrados);
END $$;
