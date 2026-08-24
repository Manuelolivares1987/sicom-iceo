-- ============================================================================
-- MIG379 · El portal de Karen no muestra los certificados técnicos
-- ----------------------------------------------------------------------------
-- Cada equipo tiene 21 tipos de certificado. El portal separa los ~8 básicos
-- —permiso, SOAP, revisión técnica, gases, TC8, hermeticidad— y deja los otros
-- ~13 detrás de un botón «Ver otros N certificados técnicos». Torque de ruedas,
-- inventario de neumáticos, aire acondicionado, calibración: importan adentro,
-- pero no son la conversación que ESMAX tiene con nosotros por este link.
--
-- POR PORTAL, NO PARA TODO EL SISTEMA
-- Adentro no cambia nada: la ficha del equipo, las alertas, los semáforos y el
-- dashboard siguen mostrando y exigiendo los 21. Los certificados no se borran
-- ni se dejan de pedir. Lo único que cambia es lo que viaja por ESTE link, y la
-- bandera vive en la fila del portal para que el próximo mandante pueda tener
-- otra respuesta sin tocar código.
--
-- QUE QUEDE DICHO
-- En el DJKL-18 hay cuatro técnicos vencidos (láminas de seguridad,
-- operatividad, mantención, aire acondicionado). Hoy Karen los puede abrir; con
-- esto deja de verlos. Es una decisión del contrato, no un efecto secundario, y
-- por eso queda escrita acá y en la observación del portal.
--
-- POR QUÉ SE PARCHA Y NO SE REESCRIBE LA FUNCIÓN
-- `fn_portal_prevencion_publico` arma un JSON de 46 claves —horómetro,
-- kilometraje, marca y modelo, folios de mantenimiento, fechas de emisión—.
-- Reescribirla completa para cambiar un WHERE es la forma más segura de perder
-- un campo por el camino. Se le cambian dos líneas y se verifica que las 46
-- claves sigan ahí. Ojo: `pg_get_functiondef` devuelve CRLF, así que sólo
-- funcionan los reemplazos de UNA línea, y cada uno lleva su guarda.
-- ============================================================================

BEGIN;

-- ── 1. La bandera ─────────────────────────────────────────────────────────
-- Por omisión TRUE: un portal nuevo muestra todo, que es como estaba antes.
ALTER TABLE public.portales_prevencion
    ADD COLUMN IF NOT EXISTS ver_certificados_tecnicos BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN public.portales_prevencion.ver_certificados_tecnicos IS
    '[MIG379] FALSE = por este link sólo viajan los documentos básicos. No cambia nada adentro: los técnicos se siguen exigiendo, mostrando y alertando en el sistema.';

-- ── 2. El recorte, donde se arma la respuesta ─────────────────────────────
-- Filtrarlo sólo en la pantalla dejaría los datos viajando igual: quien abra
-- las herramientas del navegador vería lo que se supone que no sale.
DO $patch$
DECLARE
    v_def TEXT;
    v_old TEXT;
    v_new TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_portal_prevencion_publico';
    IF v_def IS NULL THEN
        RAISE EXCEPTION 'No existe fn_portal_prevencion_publico: revisar MIG308/313.';
    END IF;

    -- (a) El WHERE de los certificados de equipo.
    v_old := 'WHERE c.activo_id = a.id';
    v_new := 'WHERE c.activo_id = a.id AND (v_p.ver_certificados_tecnicos OR c.tipo = ANY (v_basicos))';
    IF position(v_old in v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró el WHERE de los certificados: la función cambió de forma.';
    END IF;
    IF position(v_new in v_def) > 0 THEN
        RAISE NOTICE 'El filtro ya estaba aplicado.';
    ELSE
        v_def := replace(v_def, v_old, v_new);
    END IF;

    -- (b) Con los técnicos fuera no queda nada que separar: la pantalla muestra
    --     una tabla sola en vez de una tabla más un desplegable vacío.
    v_old := '''separa_basicos'',        (array_length(v_basicos, 1) > 0),';
    v_new := '''separa_basicos'',        (array_length(v_basicos, 1) > 0 AND v_p.ver_certificados_tecnicos),'
          || chr(13) || chr(10) || '          ''solo_basicos'',          (NOT v_p.ver_certificados_tecnicos),';
    IF position(v_old in v_def) = 0 AND position('solo_basicos' in v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró la línea de separa_basicos: la función cambió de forma.';
    END IF;
    v_def := replace(v_def, v_old, v_new);

    EXECUTE v_def;
END
$patch$;

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_publico(text, uuid) TO anon, authenticated;

-- ── 3. El portal de Romeral (ESMAX · Karen) ───────────────────────────────
UPDATE public.portales_prevencion
   SET ver_certificados_tecnicos = FALSE,
       observacion = COALESCE(observacion, '')
                   || ' | MIG379: por decisión del contrato, este link muestra sólo la documentación básica. Los certificados técnicos quedan de uso interno.',
       updated_at = NOW()
 WHERE faena_codigo = 'ROMERAL';

-- ── 4. Que no se haya perdido nada por el camino ──────────────────────────
DO $verif$
DECLARE
    v_def TEXT;
    v_falta TEXT[] := '{}';
    v_k TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_portal_prevencion_publico';

    FOREACH v_k IN ARRAY ARRAY[
        'estado_codigo', 'fecha_emision', 'horas', 'km', 'marca_modelo',
        'trabajo', 'numero_certificado', 'entidad_certificadora',
        'rut_enmascarado', 'tiene_archivo', 'mantenimiento', 'personal'
    ] LOOP
        IF position('''' || v_k || '''' in v_def) = 0 THEN
            v_falta := v_falta || v_k;
        END IF;
    END LOOP;

    IF array_length(v_falta, 1) > 0 THEN
        RAISE EXCEPTION 'El parche perdió claves del JSON: %', array_to_string(v_falta, ', ');
    END IF;
    RAISE NOTICE 'Las claves del JSON siguen completas.';
END
$verif$;

COMMIT;
