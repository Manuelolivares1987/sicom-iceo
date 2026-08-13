-- ============================================================================
-- SICOM-ICEO | 285 — Si el cliente reporta un problema, el jefe se entera
-- ============================================================================
-- Hasta ahora, cuando el cliente marcaba un ítem NO OK en su checklist del QR,
-- el sistema anotaba una alerta temprana en un radar interno. Nadie la miraba,
-- y al jefe de taller no le llegaba nada: el cliente reportaba un freno malo y
-- el taller se enteraba cuando el equipo llegaba solo.
--
-- Ahora la novedad del cliente entra por la misma puerta que todo lo demás:
-- se convierte en NO CONFORMIDAD y aparece en la bandeja del jefe, con la foto
-- que sacó el cliente y lo que escribió. Además queda contada en el número que
-- el jefe ve en el menú.
--
-- Lo que el cliente reporta sobre FRENOS, FUGAS o el TABLERO entra como
-- severidad alta: son las tres cosas que dejan un equipo fuera de operación.
--
-- No se duplica: si el cliente vuelve a marcar lo mismo la semana siguiente y
-- la NC anterior sigue abierta, se suma la fecha del nuevo reporte a esa NC en
-- vez de crear otra. Un problema que se repite es el mismo problema.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='checklist_cliente_semanal_items') THEN
        RAISE EXCEPTION 'STOP — falta el checklist del cliente'; END IF;
END $$;


-- ── La bandeja del jefe tiene que mostrar este origen ───────────────────────
-- La vista filtra por una lista de orígenes. En vez de transcribir sus ~100
-- líneas (y arriesgar perder una columna al copiarla), se le agrega el origen
-- nuevo a esa lista sobre su propia definición.
DO $$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_viewdef('v_nc_recepcion'::regclass, true) INTO v_def;

    IF v_def LIKE '%checklist_cliente%' THEN
        RAISE NOTICE 'MIG285: v_nc_recepcion ya incluye checklist_cliente';
        RETURN;
    END IF;

    IF position('''manual''::text' IN v_def) = 0 THEN
        RAISE EXCEPTION 'STOP — v_nc_recepcion no tiene la lista de orígenes esperada';
    END IF;

    v_def := replace(v_def, '''manual''::text', '''manual''::text, ''checklist_cliente''::text');
    EXECUTE 'CREATE OR REPLACE VIEW v_nc_recepcion AS ' || rtrim(v_def, ';' || E'\n' || ' ');
    RAISE NOTICE 'MIG285: v_nc_recepcion ahora incluye las novedades del cliente';
END $$;


-- ── El hallazgo del cliente se vuelve no conformidad ────────────────────────
CREATE OR REPLACE FUNCTION fn_nc_desde_checklist_cliente(p_checklist_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_activo   UUID;
    v_fecha    DATE;
    v_quien    TEXT;
    r          RECORD;
    v_creadas  INT := 0;
    v_sumadas  INT := 0;
    v_sev      TEXT;
    v_nc       UUID;
    v_desc     TEXT;
BEGIN
    SELECT c.activo_id, COALESCE(c.fecha::date, CURRENT_DATE),
           COALESCE(NULLIF(TRIM(c.operador_nombre), ''), 'el cliente')
      INTO v_activo, v_fecha, v_quien
      FROM checklist_cliente_semanal c WHERE c.id = p_checklist_id;

    IF v_activo IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'motivo', 'checklist sin equipo');
    END IF;

    FOR r IN
        SELECT i.id, i.categoria, i.descripcion, i.observacion, i.foto_url
          FROM checklist_cliente_semanal_items i
         WHERE i.checklist_id = p_checklist_id AND i.resultado = 'no_ok'
    LOOP
        -- Frenos, fugas y tablero dejan el equipo fuera de operación.
        v_sev := CASE WHEN r.categoria IN ('frenos', 'fugas', 'tablero') THEN 'alta' ELSE 'media' END;

        v_desc := COALESCE(NULLIF(TRIM(r.descripcion), ''), 'Novedad reportada por el cliente');

        -- ¿Ya hay una NC abierta del cliente por lo mismo en este equipo?
        SELECT n.id INTO v_nc
          FROM no_conformidades n
         WHERE n.activo_id = v_activo
           AND n.origen = 'checklist_cliente'
           AND n.descripcion LIKE v_desc || '%'
           AND NOT COALESCE(n.resuelto, false)
           AND n.estado_planificacion NOT IN ('resuelta', 'descartada')
         LIMIT 1;

        IF v_nc IS NOT NULL THEN
            -- Se repite: se deja constancia en la misma NC, no se abre otra.
            -- Que se repita sube la severidad: el cliente ya lo dijo una vez.
            UPDATE no_conformidades
               SET descripcion = descripcion
                                 || E'\n· Reportado de nuevo el ' || to_char(v_fecha, 'DD-MM-YYYY')
                                 || ' por ' || v_quien
                                 || COALESCE(': ' || NULLIF(TRIM(r.observacion), ''), ''),
                   severidad  = CASE WHEN severidad = 'media' THEN 'alta' ELSE severidad END,
                   updated_at = NOW()
             WHERE id = v_nc;
            v_sumadas := v_sumadas + 1;
            CONTINUE;
        END IF;

        INSERT INTO no_conformidades (
            activo_id, tipo, descripcion, fecha_evento, severidad,
            origen, estado_planificacion, foto_url
        ) VALUES (
            v_activo, 'otra',
            v_desc || COALESCE(' — «' || NULLIF(TRIM(r.observacion), '') || '»', '')
                   || ' (reportado por ' || v_quien || ')',
            v_fecha, v_sev, 'checklist_cliente', 'registrada',
            NULLIF(TRIM(r.foto_url), '')
        );
        v_creadas := v_creadas + 1;
    END LOOP;

    -- ── Avisar al jefe de taller ────────────────────────────────────────────
    -- Va como alerta que REQUIERE ACCIÓN (MIG283): entra en "Por decidir" y
    -- suma al número que el jefe ve en el menú, no al ruido informativo.
    IF v_creadas > 0 THEN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id)
        SELECT 'no_conformidad',
               'El cliente reportó ' || v_creadas || ' problema' || CASE WHEN v_creadas > 1 THEN 's' ELSE '' END
                 || ' en ' || COALESCE(a.patente, a.codigo),
               v_quien || ' marcó ' || v_creadas || ' ítem(s) con problema en el checklist del equipo.',
               CASE WHEN EXISTS (SELECT 1 FROM no_conformidades n
                                  WHERE n.activo_id = v_activo AND n.origen = 'checklist_cliente'
                                    AND n.severidad = 'alta' AND n.fecha_evento = v_fecha)
                    THEN 'critical' ELSE 'warning' END,
               'no_conformidad', v_activo, u.id
          FROM activos a
          CROSS JOIN usuarios_perfil u
         WHERE a.id = v_activo
           AND u.rol::text IN ('jefe_mantenimiento', 'planificador')
           AND u.activo;
    END IF;

    RETURN jsonb_build_object('ok', true, 'nc_creadas', v_creadas, 'nc_actualizadas', v_sumadas);
END $$;

COMMENT ON FUNCTION fn_nc_desde_checklist_cliente(UUID) IS
    'Convierte en no conformidad lo que el cliente marcó NO OK en su checklist del QR '
    'y avisa al jefe de taller. No duplica si el problema se repite. MIG285.';


-- ── Se dispara al guardar el checklist del cliente ──────────────────────────
CREATE OR REPLACE FUNCTION fn_trg_nc_desde_checklist_cliente()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.tiene_novedad AND COALESCE(OLD.tiene_novedad, false) IS DISTINCT FROM true THEN
        -- Si algo falla acá, el checklist del cliente igual se guarda: perder
        -- su inspección por un problema nuestro sería peor.
        BEGIN
            PERFORM fn_nc_desde_checklist_cliente(NEW.id);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nc_desde_checklist_cliente ON checklist_cliente_semanal;
CREATE TRIGGER trg_nc_desde_checklist_cliente
    AFTER INSERT OR UPDATE OF tiene_novedad ON checklist_cliente_semanal
    FOR EACH ROW EXECUTE FUNCTION fn_trg_nc_desde_checklist_cliente();


SELECT 'MIG285 OK' AS resultado;
