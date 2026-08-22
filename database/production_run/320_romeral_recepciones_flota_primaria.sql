-- ============================================================================
-- MIG320 · Recepción de flota primaria con la guía capturada en la descarga
-- ----------------------------------------------------------------------------
-- QUÉ RESUELVE
--   El hallazgo 7: hoy la recepción se valida "contra la guía de despacho",
--   que en la práctica es alguien comparando dos papeles línea por línea, días
--   después, cuando el camión ya se fue y el sello ya no está.
--
--   Una recepción mal registrada mueve el inventario durante días sin que nadie
--   sepa por qué: entra como diferencia de estanque y se persigue como si fuera
--   una pérdida. El propio instructivo lo dice en el Anexo A.5.
--
-- EL MODELO
--   Sale del que ya funciona en la app Orpak: una guía trae un total y ese
--   total se reparte entre estanques (bimodal / mina1 / mina2 / casaf). Acá el
--   reparto es una tabla hija en vez de columnas fijas, porque los puntos de
--   Romeral ya cambiaron una vez —Casa Fuerza dejó de llenarse en agosto— y
--   volverán a cambiar.
--
--   Dos números distintos a propósito: LITROS DE LA GUÍA (lo que dice el
--   documento del proveedor) y LITROS RECIBIDOS (lo que efectivamente entró al
--   estanque). Si se guarda uno solo, la diferencia entre ambos desaparece — y
--   esa diferencia es justamente el control.
--
--   Foto de la guía obligatoria al confirmar, por lo mismo que las mediciones:
--   la guía se va con el camión.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.combustible_faena_recepcion (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id        UUID NOT NULL REFERENCES public.faenas(id),
    fecha           DATE NOT NULL,
    hora            TIME,
    -- Documento del proveedor
    guia            TEXT,
    viaje           TEXT,
    camion          TEXT,
    proveedor       TEXT,
    litros_guia     NUMERIC,
    -- Evidencia
    foto_guia_url   TEXT,
    sin_foto_motivo TEXT,
    -- Quién recibió y bajo qué sello
    recibido_por    TEXT,
    sello           TEXT,
    observacion     TEXT,
    estado          TEXT NOT NULL DEFAULT 'borrador',   -- borrador | confirmada
    confirmada_at   TIMESTAMPTZ,
    anulada         BOOLEAN NOT NULL DEFAULT false,
    anulada_motivo  TEXT,
    client_uuid     TEXT UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.combustible_faena_recepcion IS
  'Recepcion de flota primaria capturada en la descarga, con la guia fotografiada. La guia se va con el camion. MIG320.';
COMMENT ON COLUMN public.combustible_faena_recepcion.litros_guia IS
  'Lo que dice el documento del proveedor. Distinto de lo recibido a proposito: la diferencia entre ambos ES el control. MIG320.';

CREATE TABLE IF NOT EXISTS public.combustible_faena_recepcion_destino (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recepcion_id  UUID NOT NULL REFERENCES public.combustible_faena_recepcion(id) ON DELETE CASCADE,
    estanque_id   UUID NOT NULL REFERENCES public.combustible_estanques(id),
    litros        NUMERIC NOT NULL,
    UNIQUE (recepcion_id, estanque_id),
    CONSTRAINT chk_recepcion_litros_positivos CHECK (litros > 0)
);

CREATE INDEX IF NOT EXISTS idx_comb_recepcion_faena_fecha
    ON public.combustible_faena_recepcion (faena_id, fecha DESC);

-- ── Registrar una recepción ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_recepcion(
    p_faena_id    uuid,
    p_fecha       date,
    p_destinos    jsonb,                       -- [{estanque_id, litros}]
    p_guia        text DEFAULT NULL,
    p_viaje       text DEFAULT NULL,
    p_camion      text DEFAULT NULL,
    p_proveedor   text DEFAULT NULL,
    p_litros_guia numeric DEFAULT NULL,
    p_hora        time DEFAULT NULL,
    p_recibido_por text DEFAULT NULL,
    p_sello       text DEFAULT NULL,
    p_observacion text DEFAULT NULL,
    p_foto_guia   text DEFAULT NULL,
    p_sin_foto_motivo text DEFAULT NULL,
    p_confirmar   boolean DEFAULT false,
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
    v_total  NUMERIC := 0;
    v_dif    NUMERIC;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado.' USING ERRCODE = '42501';
    END IF;

    -- Reintento del teléfono sin señal: no se duplica el ingreso de litros.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM combustible_faena_recepcion WHERE client_uuid = p_client_uuid;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO combustible_faena_recepcion
            (faena_id, fecha, hora, guia, viaje, camion, proveedor, litros_guia,
             foto_guia_url, sin_foto_motivo, recibido_por, sello, observacion,
             client_uuid, created_by)
        VALUES (p_faena_id, COALESCE(p_fecha, CURRENT_DATE), p_hora,
                NULLIF(trim(COALESCE(p_guia,'')),''), NULLIF(trim(COALESCE(p_viaje,'')),''),
                NULLIF(upper(trim(COALESCE(p_camion,''))),''), NULLIF(trim(COALESCE(p_proveedor,'')),''),
                p_litros_guia, NULLIF(trim(COALESCE(p_foto_guia,'')),''),
                NULLIF(trim(COALESCE(p_sin_foto_motivo,'')),''),
                NULLIF(trim(COALESCE(p_recibido_por,'')),''), NULLIF(trim(COALESCE(p_sello,'')),''),
                NULLIF(trim(COALESCE(p_observacion,'')),''),
                p_client_uuid, auth.uid())
        RETURNING id INTO v_id;
    ELSE
        IF (SELECT estado FROM combustible_faena_recepcion WHERE id = v_id) = 'confirmada'
           AND NOT p_confirmar THEN
            RAISE EXCEPTION 'Esta recepción ya está confirmada.' USING ERRCODE = '42501';
        END IF;
        UPDATE combustible_faena_recepcion
           SET fecha = COALESCE(p_fecha, fecha), hora = COALESCE(p_hora, hora),
               guia = COALESCE(NULLIF(trim(COALESCE(p_guia,'')),''), guia),
               viaje = COALESCE(NULLIF(trim(COALESCE(p_viaje,'')),''), viaje),
               camion = COALESCE(NULLIF(upper(trim(COALESCE(p_camion,''))),''), camion),
               proveedor = COALESCE(NULLIF(trim(COALESCE(p_proveedor,'')),''), proveedor),
               litros_guia = COALESCE(p_litros_guia, litros_guia),
               -- La foto puede llegar después que el dato, si la señal se cortó.
               foto_guia_url = COALESCE(NULLIF(trim(COALESCE(p_foto_guia,'')),''), foto_guia_url),
               sin_foto_motivo = NULLIF(trim(COALESCE(p_sin_foto_motivo,'')),''),
               recibido_por = COALESCE(NULLIF(trim(COALESCE(p_recibido_por,'')),''), recibido_por),
               sello = COALESCE(NULLIF(trim(COALESCE(p_sello,'')),''), sello),
               observacion = NULLIF(trim(COALESCE(p_observacion,'')),''),
               updated_at = NOW()
         WHERE id = v_id;
    END IF;

    -- El reparto se reescribe entero: es más simple y más seguro que parchear.
    DELETE FROM combustible_faena_recepcion_destino WHERE recepcion_id = v_id;
    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_destinos, '[]'::jsonb))
    LOOP
        IF COALESCE((v_r->>'litros')::numeric, 0) <= 0 THEN CONTINUE; END IF;
        INSERT INTO combustible_faena_recepcion_destino (recepcion_id, estanque_id, litros)
        VALUES (v_id, (v_r->>'estanque_id')::uuid, (v_r->>'litros')::numeric);
        v_total := v_total + (v_r->>'litros')::numeric;
    END LOOP;

    IF p_confirmar THEN
        IF v_total <= 0 THEN
            RAISE EXCEPTION 'Indique en qué estanque quedó el combustible.' USING ERRCODE = '22023';
        END IF;
        IF COALESCE(NULLIF(trim(COALESCE(p_foto_guia,'')),''),
                    NULLIF(trim(COALESCE(p_sin_foto_motivo,'')),'')) IS NULL
           AND (SELECT COALESCE(foto_guia_url, sin_foto_motivo)
                  FROM combustible_faena_recepcion WHERE id = v_id) IS NULL THEN
            RAISE EXCEPTION 'Falta la foto de la guía. Sáquela, o escriba por qué no pudo.'
                USING ERRCODE = '22023';
        END IF;
        UPDATE combustible_faena_recepcion
           SET estado = 'confirmada', confirmada_at = NOW(), updated_at = NOW()
         WHERE id = v_id;
    END IF;

    v_dif := CASE WHEN p_litros_guia IS NOT NULL THEN v_total - p_litros_guia END;

    RETURN jsonb_build_object(
        'recepcion_id', v_id,
        'litros_recibidos', v_total,
        'diferencia_vs_guia', v_dif,
        'confirmada', p_confirmar);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_recepcion(
    uuid, date, jsonb, text, text, text, text, numeric, time, text, text, text,
    text, text, boolean, text) TO authenticated;

-- ── La recepción con su cruce contra la guía ───────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_recepcion AS
SELECT
    r.id, r.faena_id, r.fecha, r.hora, r.guia, r.viaje, r.camion, r.proveedor,
    r.litros_guia, r.foto_guia_url, r.sin_foto_motivo,
    r.recibido_por, r.sello, r.observacion, r.estado, r.anulada, r.created_at,
    COALESCE(d.litros_recibidos, 0)                    AS litros_recibidos,
    d.destinos,
    -- El control: lo que dice el papel contra lo que entró al estanque.
    CASE WHEN r.litros_guia IS NOT NULL
         THEN COALESCE(d.litros_recibidos, 0) - r.litros_guia END AS diferencia_vs_guia,
    CASE WHEN r.litros_guia IS NULL OR r.litros_guia = 0 THEN NULL
         ELSE ROUND((COALESCE(d.litros_recibidos,0) - r.litros_guia) / r.litros_guia, 4)
    END                                                AS diferencia_pct
FROM combustible_faena_recepcion r
LEFT JOIN LATERAL (
    SELECT SUM(rd.litros) AS litros_recibidos,
           jsonb_agg(jsonb_build_object(
               'estanque_id', rd.estanque_id,
               'estanque', e.nombre,
               'clave', e.clave_cierre,
               'litros', rd.litros) ORDER BY e.orden_cierre) AS destinos
      FROM combustible_faena_recepcion_destino rd
      JOIN combustible_estanques e ON e.id = rd.estanque_id
     WHERE rd.recepcion_id = r.id
) d ON TRUE
WHERE NOT r.anulada;

GRANT SELECT ON public.v_comb_faena_recepcion TO authenticated;

-- ── Lo recibido por estanque y día, para proponer el `rfp` del cierre ──────
-- Hoy quien varilla escribe a mano cuánto recibió. Si la recepción ya se
-- capturó en la descarga, el número está: proponerlo evita una transcripción y,
-- sobre todo, evita que los dos números no coincidan.
CREATE OR REPLACE VIEW public.v_comb_faena_recibido_dia AS
SELECT r.faena_id, r.fecha, rd.estanque_id,
       SUM(rd.litros)::numeric AS litros,
       COUNT(*)::int           AS recepciones
FROM combustible_faena_recepcion r
JOIN combustible_faena_recepcion_destino rd ON rd.recepcion_id = r.id
WHERE NOT r.anulada
GROUP BY r.faena_id, r.fecha, rd.estanque_id;

GRANT SELECT ON public.v_comb_faena_recibido_dia TO authenticated;

COMMIT;
