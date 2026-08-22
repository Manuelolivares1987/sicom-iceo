-- ============================================================================
-- MIG309 · Sugerencias manda el estado del equipo en TODO el sistema
-- ----------------------------------------------------------------------------
-- MIG307 hizo que confirmar el día sincronizara activos.estado (el operativo),
-- pero dejó estado_comercial fuera por miedo a los gates. Ese miedo ya no
-- corresponde: desde el 2026-07-22 los gates de checklist de entrega y de
-- ready-to-rent ADVIERTEN, no bloquean. Los únicos que bloquean son el DS 298
-- (antigüedad > 15 años en transporte de sustancias peligrosas) y el de
-- calidad (pendientes críticos no diferibles) — y esos DEBEN bloquear.
--
-- Resultado de dejarlo a medias: hoy hay 8 equipos donde la ficha comercial
-- contradice al planificador. HKSR-81 y JGBY-10 figuran "disponible" mientras
-- el planificador los tiene arrendados; GCHT-12 figura disponible y está en
-- venta. Eso ensucia el tablero comercial, la disponibilidad y el informe.
--
-- QUÉ HACE
--   a) El mapeo código -> ficha queda en TRES funciones y en ningún otro lado.
--      Estaba escrito dos veces (el modal y MIG307) y ya habían empezado a
--      separarse: MIG307 no conocía 'S'.
--   b) rpc_confirmar_estado_dia sincroniza estado + estado_comercial +
--      categoria_uso. Si un gate legítimo bloquea, NO se pierde el cierre del
--      día: el bloqueo queda anotado en la fila para que el planificador lo
--      vea y lo resuelva.
--   c) rpc_actualizar_estado_diario_manual usa las mismas funciones. Ahí los
--      bloqueos SÍ explotan hacia el usuario: es una acción deliberada de una
--      persona sobre un equipo, tiene que enterarse en el momento.
--   d) Se alinean los 8 equipos que ya estaban torcidos.
-- ============================================================================

BEGIN;

-- ── a) El mapeo, en un solo lugar ──────────────────────────────────────────

-- Estado OPERATIVO de la ficha. Qué le pasa al fierro.
CREATE OR REPLACE FUNCTION public.fn_estado_ficha_desde_codigo(p_codigo character)
RETURNS estado_activo_enum
LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE p_codigo
             WHEN 'M' THEN 'en_mantenimiento'
             WHEN 'T' THEN 'en_mantenimiento'
             WHEN 'H' THEN 'en_mantenimiento'
             WHEN 'F' THEN 'fuera_servicio'
             WHEN 'S' THEN 'fuera_servicio'   -- robo / siniestro (MIG306)
             ELSE        'operativo'
           END::estado_activo_enum;
$f$;

-- Estado COMERCIAL. Bajo qué título lo tiene el cliente.
-- Los transitorios (M/T/F/S) no lo tocan: un camión en taller sigue arrendado.
CREATE OR REPLACE FUNCTION public.fn_estado_comercial_desde_codigo(
    p_codigo character,
    p_actual estado_comercial_enum
)
RETURNS estado_comercial_enum
LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE p_codigo
             WHEN 'A' THEN 'arrendado'::estado_comercial_enum
             WHEN 'C' THEN 'arrendado'::estado_comercial_enum
             WHEN 'D' THEN 'disponible'::estado_comercial_enum
             WHEN 'U' THEN 'uso_interno'::estado_comercial_enum
             WHEN 'L' THEN 'leasing'::estado_comercial_enum
             WHEN 'R' THEN 'en_recepcion'::estado_comercial_enum
             WHEN 'V' THEN 'en_venta'::estado_comercial_enum
             WHEN 'H' THEN NULL                -- en habilitación no tiene título
             ELSE p_actual
           END;
$f$;

-- Categoría de uso, la que agrupa el informe de Fiabilidad.
-- NULL = el código no la define y se conserva la que tenía.
CREATE OR REPLACE FUNCTION public.fn_categoria_uso_desde_codigo(p_codigo character)
RETURNS categoria_uso_enum
LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE p_codigo
             WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
             WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
             WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
             WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
             WHEN 'V' THEN 'venta'::categoria_uso_enum
             ELSE NULL
           END;
$f$;

GRANT EXECUTE ON FUNCTION public.fn_estado_ficha_desde_codigo(character) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_estado_comercial_desde_codigo(character, estado_comercial_enum) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_categoria_uso_desde_codigo(character) TO authenticated;

-- ── b) Dónde se anota un bloqueo, para que no se pierda en silencio ────────
ALTER TABLE public.estado_diario_flota
    ADD COLUMN IF NOT EXISTS ficha_sync_error TEXT;

COMMENT ON COLUMN public.estado_diario_flota.ficha_sync_error IS
  'Por qué la ficha del equipo no pudo seguir al estado confirmado (gate DS 298, calidad). NULL = sincronizó bien. MIG309.';

-- ── c) Confirmar el día sincroniza la ficha completa ───────────────────────
CREATE OR REPLACE FUNCTION public.rpc_confirmar_estado_dia(
    p_activo_id uuid,
    p_fecha     date,
    p_estado    character
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_ultima_fecha DATE;
    v_a            RECORD;
    v_error        TEXT := NULL;
BEGIN
    -- [MIG189] Autorización fail-closed (flota/approve). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'flota', 'flota', 'approve' USING ERRCODE = '42501';
    END IF;

    INSERT INTO estado_diario_flota
      (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override, actualizado_por, actualizado_at)
    VALUES
      (p_activo_id, p_fecha, p_estado, true, false, 'Confirmado por planificador (sugerencia GPS)', auth.uid(), now())
    ON CONFLICT (activo_id, fecha) DO UPDATE
      SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
          motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
          actualizado_at = now(), updated_at = now();

    -- La ficha sigue al planificador SOLO si esta es la última fecha registrada
    -- del equipo. Corregir un día pasado no puede reescribir el estado de hoy.
    SELECT MAX(fecha) INTO v_ultima_fecha
      FROM estado_diario_flota WHERE activo_id = p_activo_id;

    IF v_ultima_fecha IS NULL OR p_fecha < v_ultima_fecha THEN
        RETURN;
    END IF;

    SELECT id, estado, estado_comercial, categoria_uso INTO v_a
      FROM activos WHERE id = p_activo_id;

    IF NOT FOUND OR v_a.estado = 'dado_baja' THEN
        RETURN;   -- una baja no vuelve sola desde un cierre de día
    END IF;

    -- Un gate puede negarse con razón (DS 298 por antigüedad, calidad por
    -- pendientes críticos). Cuando eso pasa, el cierre del día IGUAL vale:
    -- estado_diario_flota es la fuente de verdad y el planificador está
    -- registrando la realidad, no pidiendo permiso. Lo que se hace es dejar
    -- anotado el motivo para que alguien lo resuelva.
    BEGIN
        UPDATE activos a
           SET estado           = fn_estado_ficha_desde_codigo(p_estado),
               estado_comercial = fn_estado_comercial_desde_codigo(p_estado, a.estado_comercial),
               categoria_uso    = COALESCE(fn_categoria_uso_desde_codigo(p_estado), a.categoria_uso),
               updated_at       = now()
         WHERE a.id = p_activo_id
           AND (a.estado           IS DISTINCT FROM fn_estado_ficha_desde_codigo(p_estado)
             OR a.estado_comercial IS DISTINCT FROM fn_estado_comercial_desde_codigo(p_estado, a.estado_comercial)
             OR a.categoria_uso    IS DISTINCT FROM COALESCE(fn_categoria_uso_desde_codigo(p_estado), a.categoria_uso));
    EXCEPTION WHEN OTHERS THEN
        v_error := SQLERRM;
    END;

    UPDATE estado_diario_flota
       SET ficha_sync_error = v_error
     WHERE activo_id = p_activo_id AND fecha = p_fecha
       AND ficha_sync_error IS DISTINCT FROM v_error;
END $function$;

-- ── d) El modal usa el mismo mapeo, pero ahí los bloqueos SÍ explotan ──────
-- Se reemplazan sólo los CASE inline por las funciones. El resto del cuerpo
-- (creación de OT, no conformidad F+arrendado, respuesta) queda igual.
CREATE OR REPLACE FUNCTION public.rpc_actualizar_estado_diario_manual(
    p_activo_id uuid, p_fecha date, p_nuevo_estado character, p_motivo text,
    p_crear_ot boolean DEFAULT false, p_ot_tipo tipo_ot_enum DEFAULT NULL::tipo_ot_enum,
    p_ot_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_ot_responsable_id uuid DEFAULT NULL::uuid, p_ot_descripcion text DEFAULT NULL::text,
    p_ubicacion character varying DEFAULT NULL::character varying)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_user_id            UUID;
    v_activo             RECORD;
    v_ot_id              UUID;
    v_ot_folio           VARCHAR(20);
    v_ot_estado_inicial  estado_ot_enum;
    v_ot_contrato_id     UUID;
    v_ot_faena_id        UUID;
    v_ot_error           TEXT;
    v_periodo            VARCHAR(6);
    v_secuencia          INTEGER;
    v_existente          UUID;
    v_nuevo_estado_act   estado_activo_enum;
    v_nuevo_estado_com   estado_comercial_enum;
    v_nueva_categoria    categoria_uso_enum;
BEGIN
    -- 1. AUTH
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    -- 2. VALIDAR CÓDIGO
    IF p_nuevo_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L','S') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- 2b. LUGAR FÍSICO (texto libre) ANTES del cambio de estado.
    IF p_ubicacion IS NOT NULL AND length(trim(p_ubicacion)) > 0 THEN
        UPDATE activos SET ubicacion_actual = trim(p_ubicacion), updated_at = NOW()
         WHERE id = p_activo_id;
        v_activo.ubicacion_actual := trim(p_ubicacion);
    END IF;

    -- 3. CREAR OT AUTOMÁTICA (M, T, F)
    IF p_crear_ot AND p_nuevo_estado IN ('M','T','F') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE
                WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                WHEN p_nuevo_estado = 'F' THEN 'correctivo'
                ELSE 'preventivo'
            END;
        END IF;

        v_ot_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
        v_ot_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

        v_ot_estado_inicial := CASE
            WHEN p_ot_responsable_id IS NOT NULL THEN 'asignada'::estado_ot_enum
            ELSE 'creada'::estado_ot_enum
        END;

        PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(
            CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
        ), 0) + 1
        INTO v_secuencia
        FROM ordenes_trabajo
        WHERE folio LIKE 'OT-' || v_periodo || '-%';

        v_ot_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

        BEGIN
            INSERT INTO ordenes_trabajo (
                folio, tipo, contrato_id, faena_id, activo_id,
                prioridad, estado, responsable_id,
                fecha_programada, observaciones,
                generada_automaticamente, created_by
            ) VALUES (
                v_ot_folio, p_ot_tipo,
                v_ot_contrato_id, v_ot_faena_id, p_activo_id,
                p_ot_prioridad, v_ot_estado_inicial, p_ot_responsable_id,
                p_fecha, COALESCE(p_ot_descripcion, p_motivo),
                true, v_user_id
            )
            RETURNING id INTO v_ot_id;
        EXCEPTION WHEN OTHERS THEN
            v_ot_error := SQLERRM;
            v_ot_id := NULL;
            v_ot_folio := NULL;
        END;
    END IF;

    -- 4. UPSERT estado_diario_flota
    SELECT id INTO v_existente
    FROM estado_diario_flota
    WHERE activo_id = p_activo_id AND fecha = p_fecha;

    IF v_existente IS NULL THEN
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo,
            cliente, ubicacion, operacion,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at,
            ot_relacionada_id, observacion, registrado_por
        ) VALUES (
            p_activo_id, p_fecha, v_activo.contrato_id, p_nuevo_estado,
            v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
            true, p_motivo, false,
            v_user_id, NOW(),
            v_ot_id, p_motivo, v_user_id
        );
    ELSE
        UPDATE estado_diario_flota
        SET estado_codigo     = p_nuevo_estado,
            ubicacion         = COALESCE(v_activo.ubicacion_actual, ubicacion),
            override_manual   = true,
            motivo_override   = p_motivo,
            actualizado_por   = v_user_id,
            actualizado_at    = NOW(),
            ot_relacionada_id = COALESCE(v_ot_id, ot_relacionada_id),
            observacion       = p_motivo,
            updated_at        = NOW()
        WHERE id = v_existente;
    END IF;

    -- 5. SINCRONIZAR LA FICHA. [MIG309] El mapeo ya no se escribe aquí: es el
    -- mismo que usa el cierre del día. Los gates que bloqueen se propagan al
    -- usuario a propósito — esto es una persona actuando sobre un equipo.
    v_nuevo_estado_act := fn_estado_ficha_desde_codigo(p_nuevo_estado);
    v_nuevo_estado_com := fn_estado_comercial_desde_codigo(p_nuevo_estado, v_activo.estado_comercial);
    v_nueva_categoria  := fn_categoria_uso_desde_codigo(p_nuevo_estado);

    UPDATE activos
    SET estado           = v_nuevo_estado_act,
        estado_comercial = v_nuevo_estado_com,
        categoria_uso    = COALESCE(v_nueva_categoria, categoria_uso),
        updated_at       = NOW()
    WHERE id = p_activo_id;

    -- 6. NO CONFORMIDAD F+arrendado (protegida)
    IF p_nuevo_estado = 'F' AND v_activo.estado_comercial = 'arrendado' THEN
        BEGIN
            INSERT INTO no_conformidades (
                activo_id, fecha_evento, tipo, severidad, descripcion, created_by
            ) VALUES (
                p_activo_id, p_fecha, 'falla_en_terreno', 'alta',
                'Equipo arrendado pasa a fuera de servicio: ' || COALESCE(p_motivo,'sin motivo'),
                v_user_id
            )
            ON CONFLICT DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 7. RESULTADO
    RETURN jsonb_build_object(
        'success',           true,
        'estado_aplicado',   p_nuevo_estado,
        'activo_estado',     v_nuevo_estado_act,
        'activo_comercial',  v_nuevo_estado_com,
        'activo_categoria',  COALESCE(v_nueva_categoria, v_activo.categoria_uso),
        'ot_creada',         v_ot_id IS NOT NULL,
        'ot_id',             v_ot_id,
        'ot_folio',          v_ot_folio,
        'ot_estado_inicial', v_ot_estado_inicial,
        'ot_error',          v_ot_error
    );
END;
$function$;

-- ── e) El reconciliador también alinea lo comercial ────────────────────────
-- Cambia la firma (agrega 'bloqueados'), asi que hay que soltarla primero.
DROP FUNCTION IF EXISTS public.fn_reconciliar_estado_ficha_desde_matriz();

CREATE OR REPLACE FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz()
RETURNS TABLE(revisados integer, actualizados integer, bloqueados integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    r     RECORD;
    v_rev INTEGER := 0;
    v_upd INTEGER := 0;
    v_blk INTEGER := 0;
BEGIN
    FOR r IN
        SELECT a.id, a.estado, a.estado_comercial, a.categoria_uso, u.cod
        FROM activos a
        JOIN LATERAL (
            SELECT estado_codigo AS cod
            FROM estado_diario_flota e
            WHERE e.activo_id = a.id AND e.fecha <= CURRENT_DATE
            ORDER BY e.fecha DESC LIMIT 1
        ) u ON TRUE
        WHERE a.estado <> 'dado_baja'
    LOOP
        v_rev := v_rev + 1;
        IF r.estado           IS DISTINCT FROM fn_estado_ficha_desde_codigo(r.cod)
        OR r.estado_comercial IS DISTINCT FROM fn_estado_comercial_desde_codigo(r.cod, r.estado_comercial)
        OR r.categoria_uso    IS DISTINCT FROM COALESCE(fn_categoria_uso_desde_codigo(r.cod), r.categoria_uso)
        THEN
            BEGIN
                UPDATE activos
                   SET estado           = fn_estado_ficha_desde_codigo(r.cod),
                       estado_comercial = fn_estado_comercial_desde_codigo(r.cod, estado_comercial),
                       categoria_uso    = COALESCE(fn_categoria_uso_desde_codigo(r.cod), categoria_uso),
                       updated_at       = NOW()
                 WHERE id = r.id;
                v_upd := v_upd + 1;
            EXCEPTION WHEN OTHERS THEN
                v_blk := v_blk + 1;
                RAISE WARNING 'No se pudo alinear %: %', r.id, SQLERRM;
            END;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_rev, v_upd, v_blk;
END;
$function$;

-- ── f) Alinear lo que ya estaba torcido ────────────────────────────────────
SELECT * FROM public.fn_reconciliar_estado_ficha_desde_matriz();

COMMIT;
