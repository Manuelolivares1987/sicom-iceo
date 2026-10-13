-- ############################################################################
-- MIG586 · Editar el informe ENEX desde la web (observación general y N° OT)
-- ----------------------------------------------------------------------------
-- QUÉ PASABA
-- La observación general del servicio y el N° OT del mandante solo se podían
-- escribir en el teléfono, dentro de la ejecución en terreno. Desde
-- /dashboard/enex/informes no había forma de corregir una frase mal escrita
-- o completar la observación antes de mandar el informe a firmar.
--
-- Además, al reabrir un servicio en el teléfono la observación general no se
-- cargaba desde el servidor (solo desde el borrador local). Como el guardado
-- reemplaza (MIG267), guardar desde otro teléfono la dejaba en blanco. Eso se
-- corrige en la pantalla de terreno, no aquí.
--
-- LA REGLA (la misma de MIG287)
--   · Se edita mientras el informe esté pendiente de la firma de ESM. Lo que
--     ESM firmó es lo que ESM vio: con la recepción conforme ya firmada, no.
--   · Cualquier cambio deja informe_pdf_url en NULL para que el PDF se rehaga.
-- ############################################################################

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_enex_informe_editar(
    p_ejecucion_id UUID,
    p_observacion  TEXT DEFAULT NULL,
    p_ot_numero    TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_e RECORD;
    v_obs TEXT := NULLIF(btrim(COALESCE(p_observacion, '')), '');
    v_ot  TEXT := NULLIF(btrim(COALESCE(p_ot_numero, '')), '');
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN
        RAISE EXCEPTION 'Sin permiso ENEX' USING ERRCODE = '42501';
    END IF;

    SELECT id, firma_mandante_url, observacion, ot_numero INTO v_e
      FROM enex_ejecuciones WHERE id = p_ejecucion_id
       FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Servicio no encontrado'; END IF;

    IF v_e.firma_mandante_url IS NOT NULL THEN
        RAISE EXCEPTION 'El informe ya fue firmado por ESM: no se puede cambiar lo que firmó';
    END IF;

    IF v_e.observacion IS NOT DISTINCT FROM v_obs AND v_e.ot_numero IS NOT DISTINCT FROM v_ot THEN
        RETURN jsonb_build_object('success', true, 'cambio', false);
    END IF;

    UPDATE enex_ejecuciones
       SET observacion     = v_obs,
           ot_numero       = v_ot,
           informe_pdf_url = NULL,     -- el PDF guardado ya no dice lo mismo
           updated_at      = now()
     WHERE id = p_ejecucion_id;

    RETURN jsonb_build_object('success', true, 'cambio', true, 'ejecucion_id', p_ejecucion_id);
END $function$;

REVOKE ALL ON FUNCTION public.rpc_enex_informe_editar(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_informe_editar(UUID, TEXT, TEXT) TO authenticated;

COMMIT;
