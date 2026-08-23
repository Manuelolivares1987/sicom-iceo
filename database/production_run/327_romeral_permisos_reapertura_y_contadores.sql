-- ============================================================================
-- MIG327 · Lo que faltaba para que esto se pueda usar de verdad
-- ----------------------------------------------------------------------------
-- Cinco cosas que la auditoría del propio sistema dejó al descubierto. Ninguna
-- es una funcionalidad nueva: son las que hacen la diferencia entre "funciona
-- en una demo" y "aguanta un turno con gente real".
--
--   1. QUIÉN FIRMA. Hoy cualquiera con sesión puede firmar un cierre. Un cierre
--      firmado es un documento que va al mandante.
--   2. REAPERTURA. El mensaje decía "pida reapertura" y no existía la
--      reapertura. Alguien va a firmar con un error la primera semana, y ese
--      callejón sin salida cuesta la confianza del turno entero.
--   3. CAMBIO DE CONTADOR. El día que reemplacen un cuentalitros el numeral
--      vuelve a cero y el CHECK `numeral_fin >= numeral_ini` bloquea el cierre.
--      Es un evento normal en faena, no una excepción.
--   4. EL AGUA. Se captura en milímetros y no la mira nadie. En un estanque de
--      combustible el agua de fondo no es un dato de color: arruina inyectores,
--      corroe el estanque y a partir de cierto nivel entra a la succión.
--   5. LA HORA DE CORTE. Configurada y sin usar. Es la causa clásica de que una
--      transacción se corra de día y descuadre dos cierres seguidos.
-- ============================================================================

BEGIN;

-- ── 1. Quién puede firmar un cierre ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_puede_cerrar()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    -- Medir y guardar borrador lo hace quien esté en terreno. FIRMAR el cierre
    -- del día es otra cosa: es declarar ante el mandante cuánto combustible se
    -- movió. Se acota a quien responde por eso.
    SELECT public.fn_tiene_permiso_modulo('inventario', 'approve', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','supervisor','planificador','operador_combustible'
    ]);
$f$;

GRANT EXECUTE ON FUNCTION public.fn_comb_puede_cerrar() TO authenticated;

-- ── 2. Estado del contador, para poder reemplazarlo ────────────────────────
ALTER TABLE public.combustible_faena_medidores
    ADD COLUMN IF NOT EXISTS reemplazado_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reemplaza_a      UUID REFERENCES public.combustible_faena_medidores(id),
    ADD COLUMN IF NOT EXISTS numeral_al_retiro NUMERIC,
    ADD COLUMN IF NOT EXISTS serie            TEXT;

COMMENT ON COLUMN public.combustible_faena_medidores.reemplaza_a IS
  'Contador anterior al que sustituye. Preserva la continuidad del historico cuando el numeral vuelve a cero. MIG327.';

-- El CHECK original impedía registrar el día del cambio. Se reemplaza por uno
-- que permite el reinicio SÓLO si quedó declarado con su motivo.
ALTER TABLE public.combustible_faena_cierre_medidor
    ADD COLUMN IF NOT EXISTS reinicio_contador BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS motivo_reinicio   TEXT;

ALTER TABLE public.combustible_faena_cierre_medidor
    DROP CONSTRAINT IF EXISTS chk_numeral_no_retrocede;

ALTER TABLE public.combustible_faena_cierre_medidor
    ADD CONSTRAINT chk_numeral_no_retrocede
    CHECK (
        numeral_fin IS NULL OR numeral_ini IS NULL
        OR numeral_fin >= numeral_ini
        -- Un contador reemplazado empieza de nuevo. Se acepta, pero hay que
        -- decirlo: sin motivo escrito sigue siendo un error de digitación.
        OR (reinicio_contador AND COALESCE(motivo_reinicio,'') <> '')
    );

COMMENT ON CONSTRAINT chk_numeral_no_retrocede ON public.combustible_faena_cierre_medidor IS
  'Un contador no retrocede, salvo que se haya reemplazado y quede declarado con motivo. MIG327.';

-- Registrar el cambio de un cuentalitros sin perder el histórico.
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_reemplazar_medidor(
    p_medidor_id     uuid,
    p_numeral_retiro numeric,
    p_numeral_inicial numeric DEFAULT 0,
    p_serie_nueva    text DEFAULT NULL,
    p_motivo         text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_viejo RECORD; v_nuevo UUID;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'No autorizado para cambiar un contador.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_viejo FROM combustible_faena_medidores WHERE id = p_medidor_id;
    IF v_viejo.id IS NULL THEN RAISE EXCEPTION 'El contador no existe.'; END IF;
    IF v_viejo.reemplazado_at IS NOT NULL THEN
        RAISE EXCEPTION 'Ese contador ya fue reemplazado el %.', v_viejo.reemplazado_at::date;
    END IF;

    -- El viejo se retira con su última lectura: el histórico queda cerrado y
    -- legible, no se borra ni se sobrescribe.
    UPDATE combustible_faena_medidores
       SET activo = false, reemplazado_at = NOW(), numeral_al_retiro = p_numeral_retiro
     WHERE id = p_medidor_id;

    INSERT INTO combustible_faena_medidores
        (estanque_id, surtidor, numero, etiqueta, orden, ultimo_numeral,
         activo, reemplaza_a, serie)
    VALUES (v_viejo.estanque_id, v_viejo.surtidor, v_viejo.numero,
            COALESCE(v_viejo.etiqueta,'') || ' (nuevo)', v_viejo.orden,
            COALESCE(p_numeral_inicial, 0), true, p_medidor_id, p_serie_nueva)
    RETURNING id INTO v_nuevo;

    RETURN jsonb_build_object(
        'medidor_anterior', p_medidor_id, 'numeral_al_retiro', p_numeral_retiro,
        'medidor_nuevo', v_nuevo, 'numeral_inicial', COALESCE(p_numeral_inicial,0),
        'motivo', p_motivo);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_reemplazar_medidor(uuid, numeric, numeric, text, text) TO authenticated;

-- ── 3. Reabrir un cierre firmado ───────────────────────────────────────────
ALTER TABLE public.combustible_faena_cierre
    ADD COLUMN IF NOT EXISTS reaperturas      INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS reabierto_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reabierto_por    UUID,
    ADD COLUMN IF NOT EXISTS motivo_reapertura TEXT;

CREATE TABLE IF NOT EXISTS public.combustible_faena_cierre_bitacora (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cierre_id   UUID NOT NULL REFERENCES public.combustible_faena_cierre(id) ON DELETE CASCADE,
    accion      TEXT NOT NULL,          -- firmado | reabierto
    motivo      TEXT,
    usuario_id  UUID,
    usuario     TEXT,
    ocurrido_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.combustible_faena_cierre_bitacora IS
  'Cada firma y cada reapertura, con quien y por que. Un cierre que se reabre tres veces es informacion. MIG327.';

ALTER TABLE public.combustible_faena_cierre_bitacora ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_comb_bitacora_lectura ON public.combustible_faena_cierre_bitacora;
CREATE POLICY pol_comb_bitacora_lectura ON public.combustible_faena_cierre_bitacora
    FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.combustible_faena_cierre_bitacora TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_reabrir_cierre(
    p_cierre_id uuid,
    p_motivo    text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_estado TEXT; v_n INT;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'No autorizado para reabrir un cierre.' USING ERRCODE = '42501';
    END IF;
    IF length(trim(COALESCE(p_motivo,''))) < 10 THEN
        RAISE EXCEPTION 'Escriba por qué se reabre. Un cierre firmado ya se informó.'
            USING ERRCODE = '22023';
    END IF;

    SELECT estado, reaperturas INTO v_estado, v_n
      FROM combustible_faena_cierre WHERE id = p_cierre_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'El cierre no existe.'; END IF;
    IF v_estado <> 'firmado' THEN
        RAISE EXCEPTION 'Ese cierre no está firmado, se puede editar directamente.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE combustible_faena_cierre
       SET estado = 'borrador', reaperturas = reaperturas + 1,
           reabierto_at = NOW(), reabierto_por = auth.uid(),
           motivo_reapertura = trim(p_motivo), updated_at = NOW()
     WHERE id = p_cierre_id;

    INSERT INTO combustible_faena_cierre_bitacora (cierre_id, accion, motivo, usuario_id, usuario)
    VALUES (p_cierre_id, 'reabierto', trim(p_motivo), auth.uid(),
            (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = auth.uid()));

    RETURN jsonb_build_object('cierre_id', p_cierre_id, 'reaperturas', v_n + 1);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_reabrir_cierre(uuid, text) TO authenticated;

-- ── 4. Umbrales de agua y hora de corte ────────────────────────────────────
ALTER TABLE public.combustible_faena_config
    ADD COLUMN IF NOT EXISTS agua_alerta_mm  NUMERIC NOT NULL DEFAULT 15,
    ADD COLUMN IF NOT EXISTS agua_critica_mm NUMERIC NOT NULL DEFAULT 25;

COMMENT ON COLUMN public.combustible_faena_config.agua_alerta_mm IS
  'Sobre esto hay que drenar. El agua de fondo corroe el estanque y arruina inyectores; pasado cierto nivel entra a la succion. MIG327.';

-- ── 5. Firmar exige permiso, y queda en bitácora ───────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_guardar_cierre(
    p_faena_id  uuid,
    p_fecha     date,
    p_turno     text,
    p_medido_por text,
    p_puntos    jsonb,
    p_medidores jsonb,
    p_observacion text DEFAULT NULL,
    p_firmar    boolean DEFAULT false,
    p_client_uuid text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id     UUID;
    v_r      JSONB;
    v_ini    NUMERIC;
    v_fin    NUMERIC;
    v_faltan TEXT[];
    v_agua   TEXT[];
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado.' USING ERRCODE = '42501';
    END IF;
    -- Guardar borrador lo hace quien mide. Firmar necesita permiso.
    IF p_firmar AND NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'Puede guardar el turno, pero firmar el cierre le corresponde al encargado o al supervisor.'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO combustible_faena_cierre
        (faena_id, fecha, turno, medido_por, observacion, client_uuid, created_by)
    VALUES (p_faena_id, p_fecha, NULLIF(trim(COALESCE(p_turno,'')),''),
            p_medido_por, p_observacion, p_client_uuid, auth.uid())
    ON CONFLICT (faena_id, fecha, turno) DO UPDATE
        SET medido_por = EXCLUDED.medido_por,
            observacion = EXCLUDED.observacion,
            updated_at = NOW()
    RETURNING id INTO v_id;

    IF (SELECT estado FROM combustible_faena_cierre WHERE id = v_id) = 'firmado'
       AND NOT p_firmar THEN
        RAISE EXCEPTION 'Este cierre ya está firmado. Reábralo si necesita corregirlo.'
            USING ERRCODE = '42501';
    END IF;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_puntos, '[]'::jsonb))
    LOOP
        INSERT INTO combustible_faena_cierre_punto
            (cierre_id, estanque_id, mi, rfp, rt, mf, agua_mm, temperatura_c, densidad_api,
             sin_medicion, motivo_sin_medicion, foto_url, sin_foto_motivo)
        VALUES (v_id, (v_r->>'estanque_id')::uuid,
                (v_r->>'mi')::numeric, (v_r->>'rfp')::numeric, (v_r->>'rt')::numeric,
                (v_r->>'mf')::numeric, (v_r->>'agua_mm')::numeric,
                (v_r->>'temperatura_c')::numeric, (v_r->>'densidad_api')::numeric,
                COALESCE((v_r->>'sin_medicion')::boolean, false),
                NULLIF(v_r->>'motivo_sin_medicion',''), NULLIF(v_r->>'foto_url',''),
                NULLIF(v_r->>'sin_foto_motivo',''))
        ON CONFLICT (cierre_id, estanque_id) DO UPDATE
            SET mi = EXCLUDED.mi, rfp = EXCLUDED.rfp, rt = EXCLUDED.rt, mf = EXCLUDED.mf,
                agua_mm = EXCLUDED.agua_mm, temperatura_c = EXCLUDED.temperatura_c,
                densidad_api = EXCLUDED.densidad_api,
                sin_medicion = EXCLUDED.sin_medicion,
                motivo_sin_medicion = EXCLUDED.motivo_sin_medicion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_punto.foto_url),
                sin_foto_motivo = EXCLUDED.sin_foto_motivo,
                updated_at = NOW();
    END LOOP;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_medidores, '[]'::jsonb))
    LOOP
        v_ini := (v_r->>'numeral_ini')::numeric;
        v_fin := (v_r->>'numeral_fin')::numeric;

        IF v_ini IS NOT NULL AND v_fin IS NOT NULL AND v_fin < v_ini
           AND NOT COALESCE((v_r->>'reinicio_contador')::boolean, false) THEN
            RAISE EXCEPTION 'El contador no puede bajar: anotó % y antes marcaba %. Revise el número, o marque que se cambió el contador.',
                v_fin, v_ini USING ERRCODE = '22023';
        END IF;

        INSERT INTO combustible_faena_cierre_medidor
            (cierre_id, medidor_id, numeral_ini, numeral_fin, calibracion,
             foto_url, sin_foto_motivo, reinicio_contador, motivo_reinicio)
        VALUES (v_id, (v_r->>'medidor_id')::uuid, v_ini, v_fin,
                COALESCE((v_r->>'calibracion')::numeric, 0),
                NULLIF(v_r->>'foto_url',''), NULLIF(v_r->>'sin_foto_motivo',''),
                COALESCE((v_r->>'reinicio_contador')::boolean, false),
                NULLIF(v_r->>'motivo_reinicio',''))
        ON CONFLICT (cierre_id, medidor_id) DO UPDATE
            SET numeral_ini = EXCLUDED.numeral_ini, numeral_fin = EXCLUDED.numeral_fin,
                calibracion = EXCLUDED.calibracion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_medidor.foto_url),
                sin_foto_motivo = EXCLUDED.sin_foto_motivo,
                reinicio_contador = EXCLUDED.reinicio_contador,
                motivo_reinicio = EXCLUDED.motivo_reinicio,
                updated_at = NOW();

        IF v_fin IS NOT NULL THEN
            UPDATE combustible_faena_medidores
               SET ultimo_numeral = v_fin
             WHERE id = (v_r->>'medidor_id')::uuid
               AND (ultimo_numeral IS NULL OR v_fin >= ultimo_numeral
                    OR COALESCE((v_r->>'reinicio_contador')::boolean, false));
        END IF;
    END LOOP;

    IF p_firmar THEN
        SELECT array_agg(e.nombre ORDER BY e.orden_cierre) INTO v_faltan
          FROM combustible_faena_cierre_punto p
          JOIN combustible_estanques e ON e.id = p.estanque_id
         WHERE p.cierre_id = v_id AND NOT p.sin_medicion AND p.mf IS NOT NULL
           AND COALESCE(p.foto_url,'') = '' AND COALESCE(p.sin_foto_motivo,'') = '';
        IF v_faltan IS NOT NULL AND array_length(v_faltan,1) > 0 THEN
            RAISE EXCEPTION 'Falta la foto de la varilla en: %. Sáquela, o escriba por qué no pudo.',
                array_to_string(v_faltan, ', ') USING ERRCODE = '22023';
        END IF;

        SELECT array_agg(COALESCE(md.etiqueta, md.surtidor || ' ' || md.numero) ORDER BY md.orden)
          INTO v_faltan
          FROM combustible_faena_cierre_medidor cm
          JOIN combustible_faena_medidores md ON md.id = cm.medidor_id
         WHERE cm.cierre_id = v_id AND cm.numeral_fin IS NOT NULL
           AND COALESCE(cm.foto_url,'') = '' AND COALESCE(cm.sin_foto_motivo,'') = '';
        IF v_faltan IS NOT NULL AND array_length(v_faltan,1) > 0 THEN
            RAISE EXCEPTION 'Falta la foto del contador en: %. Sáquela, o escriba por qué no pudo.',
                array_to_string(v_faltan, ', ') USING ERRCODE = '22023';
        END IF;

        IF NULLIF(trim(COALESCE(p_medido_por,'')),'') IS NULL THEN
            RAISE EXCEPTION 'Falta el nombre de quien midió.' USING ERRCODE = '22023';
        END IF;

        -- El agua no bloquea el cierre — es un hallazgo operacional, no un
        -- error de registro — pero no puede pasar inadvertida.
        SELECT array_agg(e.nombre || ' (' || p.agua_mm || ' mm)') INTO v_agua
          FROM combustible_faena_cierre_punto p
          JOIN combustible_estanques e ON e.id = p.estanque_id
          LEFT JOIN combustible_faena_config c ON c.faena_id = p_faena_id
         WHERE p.cierre_id = v_id
           AND p.agua_mm > COALESCE(c.agua_critica_mm, 25);
        IF v_agua IS NOT NULL THEN
            RAISE WARNING 'AGUA EN ESTANQUE sobre el nivel critico: %. Drenar antes del proximo despacho.',
                array_to_string(v_agua, ', ');
        END IF;

        UPDATE combustible_faena_cierre
           SET estado = 'firmado', firmado_at = NOW(), updated_at = NOW()
         WHERE id = v_id;

        INSERT INTO combustible_faena_cierre_bitacora (cierre_id, accion, usuario_id, usuario)
        VALUES (v_id, 'firmado', auth.uid(), p_medido_por);
    END IF;

    RETURN jsonb_build_object('cierre_id', v_id, 'firmado', p_firmar);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_guardar_cierre(uuid, date, text, text, jsonb, jsonb, text, boolean, text) TO authenticated;

-- ── 6. El agua entra a las excepciones ─────────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_agua AS
SELECT c.faena_id, c.fecha, c.turno,
       e.id AS estanque_id, e.nombre AS estanque, p.agua_mm,
       CASE
         WHEN p.agua_mm IS NULL THEN 'sin_dato'
         WHEN p.agua_mm > COALESCE(cf.agua_critica_mm, 25) THEN 'critica'
         WHEN p.agua_mm > COALESCE(cf.agua_alerta_mm, 15)  THEN 'alerta'
         ELSE 'normal'
       END AS nivel
FROM combustible_faena_cierre c
JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
JOIN combustible_estanques e ON e.id = p.estanque_id
LEFT JOIN combustible_faena_config cf ON cf.faena_id = c.faena_id
WHERE NOT p.sin_medicion;

GRANT SELECT ON public.v_comb_faena_agua TO authenticated;

COMMIT;
