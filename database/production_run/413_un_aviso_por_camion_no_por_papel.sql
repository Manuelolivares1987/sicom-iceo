-- ============================================================================
-- MIG413 · Un aviso por camión, no uno por papel
-- ----------------------------------------------------------------------------
-- MIG412 dejó el escalamiento avisando por CADA certificado sin fecha, a cada
-- persona de cuatro roles. Haciendo la cuenta antes de que corriera:
--
--     195 papeles sin fecha × 4 destinatarios = 780 avisos
--
-- Esta misma mañana la campanita marcaba tope con 2.531 avisos sin leer y hubo
-- que ponerle caducidad justamente por esto. Soltar 780 más habría deshecho ese
-- arreglo el primer día, y con avisos que además dicen todos lo mismo.
--
-- ── EL CAMIÓN ES LA UNIDAD ─────────────────────────────────────────────────
-- A nadie le sirve saber que «el certificado de cabina del TGGF-57 no tiene
-- fecha». Lo que sirve es: «el TGGF-57 tiene 8 papeles sin vigencia conocida».
-- Se va a Control documental una vez y se resuelven los ocho.
--
-- Con eso el número baja de 780 a lo sumo a un aviso por equipo con pendientes,
-- y el texto pasa a ser accionable en vez de repetitivo.
--
-- ── Y SE ACTUALIZA EN VEZ DE APILARSE ──────────────────────────────────────
-- Si el aviso del equipo sigue sin leer y la semana siguiente le faltan 6 en
-- vez de 8, se reescribe el mismo aviso. Nunca hay dos avisos abiertos del
-- mismo camión.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_certificados_escalar_sin_fecha()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    r RECORD; u RECORD; v_nuevos INT := 0; v_actualizados INT := 0; v_upd INT;
    v_msg TEXT; v_sev TEXT;
BEGIN
    FOR r IN
        SELECT a.id AS activo_id,
               COALESCE(a.patente, a.codigo) AS patente,
               count(*) AS n,
               max(CURRENT_DATE - c.created_at::date) AS dias_max,
               string_agg(DISTINCT replace(v.tipo::text, '_', ' '), ', '
                          ORDER BY replace(v.tipo::text, '_', ' ')) AS tipos
          FROM v_certificacion_actual v
          JOIN certificaciones c ON c.id = v.id
          JOIN activos a ON a.id = v.activo_id
         WHERE v.estado_real::text = 'sin_fecha'
           AND a.estado <> 'dado_baja'::estado_activo_enum
           AND (CURRENT_DATE - c.created_at::date) >= 30
         GROUP BY 1, 2
    LOOP
        v_sev := CASE WHEN r.dias_max >= 60 THEN 'critical' ELSE 'warning' END;
        v_msg := r.n || ' papel' || CASE WHEN r.n <> 1 THEN 'es' ELSE '' END
              || ' del ' || r.patente || ' están cargados sin fecha de vencimiento: '
              || left(r.tipos, 180)
              || '. Nadie sabe si están vigentes. Se resuelven de una vez en '
              || 'Flota → Control documental.';

        FOR u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true
               AND rol IN ('administrador','subgerente_operaciones','jefe_mantenimiento','prevencionista')
        LOOP
            -- Un solo aviso abierto por camión y persona: si sigue sin leer, se
            -- reescribe con el conteo de hoy en vez de apilar otro.
            UPDATE alertas
               SET mensaje = v_msg, severidad = v_sev, created_at = NOW()
             WHERE tipo = 'doc_sin_fecha' AND entidad_tipo = 'activo'
               AND entidad_id = r.activo_id AND destinatario_id = u.id AND NOT leida;
            GET DIAGNOSTICS v_upd = ROW_COUNT;

            IF v_upd > 0 THEN
                v_actualizados := v_actualizados + 1;
            ELSE
                INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                     destinatario_id, requiere_accion, leida, created_at)
                VALUES ('doc_sin_fecha',
                        'Papeles sin vigencia: ' || r.patente,
                        v_msg, v_sev, 'activo', r.activo_id, u.id, true, false, NOW());
                v_nuevos := v_nuevos + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object('avisos_nuevos', v_nuevos, 'avisos_actualizados', v_actualizados);
END $function$;

COMMENT ON FUNCTION public.fn_certificados_escalar_sin_fecha() IS
  'MIG413: un aviso por camión con papeles sin vigencia, no uno por papel. Se reescribe mientras siga sin leer.';

-- La alerta apunta al equipo: el enlace tiene que llevar a su ficha.
-- (rutaAlerta en el header ya manda entidad_tipo=activo a la flota.)

DO $r$
DECLARE v_eq INT; v_papeles INT;
BEGIN
    SELECT count(DISTINCT v.activo_id), count(*)
      INTO v_eq, v_papeles
      FROM v_certificacion_actual v
      JOIN certificaciones c ON c.id = v.id
      JOIN activos a ON a.id = v.activo_id
     WHERE v.estado_real::text = 'sin_fecha' AND a.estado <> 'dado_baja'::estado_activo_enum
       AND (CURRENT_DATE - c.created_at::date) >= 30;
    RAISE NOTICE 'Escalamiento: % equipos con % papeles sin fecha → hasta % avisos (antes habrían sido %)',
        v_eq, v_papeles, v_eq * 4, v_papeles * 4;
END
$r$;

COMMIT;
