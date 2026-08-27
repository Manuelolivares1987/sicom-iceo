-- ============================================================================
-- MIG427 · Poder decir «este papel no caduca»
-- ----------------------------------------------------------------------------
-- LO QUE PIDIÓ MANUEL
-- 27-08-2026: «necesito que en Control documental también des la opción de
-- colocar "no caduca". Como por ejemplo el certificado de cabina no caduca».
--
-- Hoy en esa pantalla sólo se puede aceptar una fecha, escribir otra o
-- descartar la propuesta. Para un papel que simplemente no vence, ninguna de
-- las tres sirve: descartar deja el papel igual de sin resolver, y escribir una
-- fecha inventada es justamente lo que se salió a corregir.
--
-- ── DOS COSAS DISTINTAS, Y CONVIENE NO MEZCLARLAS ──────────────────────────
-- «Este documento no declara vencimiento» y «este TIPO de documento no vence
-- nunca» no son la misma afirmación. La primera habla de un papel; la segunda
-- de una categoría, y se aplica también a los que lleguen mañana.
--
-- El certificado de cabina es del segundo tipo: no vence ninguno, ni el de este
-- camión ni el del próximo. Por eso el RPC recibe el alcance y quien marca
-- elige, en vez de que el sistema adivine.
--
-- ── LA LISTA DEJA DE ESTAR ESCRITA EN EL CÓDIGO ────────────────────────────
-- `fn_certificado_tipo_permanente` tenía cinco tipos en un ARRAY dentro de la
-- función: factura, ficha técnica, padrón, inscripción RNVM y homologación.
-- Agregar el certificado de cabina habría significado otra migración, y la
-- siguiente vez otra. Ahora la lista es una tabla y la función la lee: se
-- agrega desde la pantalla y queda registrado quién lo dijo y cuándo.
--
-- La firma de la función no cambia, porque de ella cuelgan la vista de estados
-- y el QR público.
-- ============================================================================

BEGIN;

-- ── 1. La lista, como dato ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.certificado_tipo_permanente (
    tipo         TEXT PRIMARY KEY,
    motivo       TEXT,
    definido_por UUID REFERENCES usuarios_perfil(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.certificado_tipo_permanente IS
  'MIG427: tipos de documento que no vencen nunca. Antes era un ARRAY dentro de fn_certificado_tipo_permanente; ahora se administra desde Control documental.';

INSERT INTO certificado_tipo_permanente (tipo, motivo) VALUES
  ('factura_compra',   'Papel de propiedad del equipo: acompaña al vehículo toda su vida.'),
  ('ficha_tecnica',    'Describe el equipo, no autoriza nada: no caduca.'),
  ('padron',           'Papel de identidad del vehículo.'),
  ('inscripcion_rnvm', 'Inscripción en el Registro Nacional de Vehículos Motorizados.'),
  ('homologacion',     'Homologación del modelo: no se renueva por equipo.')
ON CONFLICT (tipo) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_certificado_tipo_permanente(p_tipo text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  -- [MIG427] La lista vive en `certificado_tipo_permanente`. Todo lo que no
  -- esté ahí vence, aunque nunca se le haya puesto fecha.
  SELECT EXISTS (SELECT 1 FROM certificado_tipo_permanente t WHERE t.tipo = p_tipo);
$function$;

ALTER TABLE public.certificado_tipo_permanente ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tipo_permanente_lectura" ON public.certificado_tipo_permanente;
CREATE POLICY "tipo_permanente_lectura" ON public.certificado_tipo_permanente
  FOR SELECT TO authenticated USING (true);

-- ── 2. Marcar que no caduca ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_certificacion_no_caduca(
    p_certificacion_id uuid,
    p_alcance          text DEFAULT 'este',   -- 'este' | 'tipo'
    p_motivo           text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_rol TEXT; v_tipo TEXT; v_patente TEXT; v_afectados INT;
BEGIN
    SELECT rol INTO v_rol FROM usuarios_perfil WHERE id = auth.uid();
    IF v_rol IS NULL OR v_rol NOT IN ('administrador','subgerente_operaciones',
                                      'jefe_mantenimiento','prevencionista','planificador') THEN
        RAISE EXCEPTION 'No tienes permiso para marcar un documento como que no caduca.';
    END IF;

    IF p_alcance NOT IN ('este','tipo') THEN
        RAISE EXCEPTION 'El alcance tiene que ser «este» o «tipo».';
    END IF;

    SELECT c.tipo::text, COALESCE(a.patente, a.codigo)
      INTO v_tipo, v_patente
      FROM certificaciones c JOIN activos a ON a.id = c.activo_id
     WHERE c.id = p_certificacion_id;
    IF v_tipo IS NULL THEN RAISE EXCEPTION 'No se encontró el documento.'; END IF;

    -- Un certificado bloqueante autoriza a operar. Que «no caduque» es una
    -- afirmación fuerte sobre un papel así: se permite, pero exigiendo el
    -- motivo, para que quede escrito quién lo sostiene.
    IF EXISTS (SELECT 1 FROM certificaciones WHERE id = p_certificacion_id AND bloqueante)
       AND COALESCE(btrim(p_motivo), '') = '' THEN
        RAISE EXCEPTION 'Es un certificado bloqueante: hay que escribir por qué no caduca.';
    END IF;

    IF p_alcance = 'tipo' THEN
        INSERT INTO certificado_tipo_permanente (tipo, motivo, definido_por)
        VALUES (v_tipo, COALESCE(NULLIF(btrim(p_motivo), ''),
                                 'Marcado desde Control documental: este tipo de documento no vence.'),
                auth.uid())
        ON CONFLICT (tipo) DO UPDATE
           SET motivo = EXCLUDED.motivo, definido_por = EXCLUDED.definido_por;
    END IF;

    -- En los dos casos se resuelven los papeles afectados: con alcance «tipo»
    -- son todos los de esa categoría que siguen sin fecha; con «este», sólo él.
    UPDATE certificaciones c
       SET fecha_vencimiento   = '2099-12-31'::date,
           fecha_origen        = 'documento_sin_vencimiento',
           fecha_origen_nota   = 'MIG427 · marcado como que no caduca'
                               || CASE WHEN p_alcance = 'tipo' THEN ' (todo el tipo)' ELSE '' END
                               || COALESCE(': ' || NULLIF(btrim(p_motivo), ''), '.'),
           vigencia_dudosa     = FALSE,
           vigencia_dudosa_nota= NULL,
           updated_at          = NOW()
     WHERE (p_alcance = 'este' AND c.id = p_certificacion_id)
        OR (p_alcance = 'tipo' AND c.tipo::text = v_tipo
            AND (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date
                 OR c.vigencia_dudosa OR c.id = p_certificacion_id));
    GET DIAGNOSTICS v_afectados = ROW_COUNT;

    -- La propuesta del lector deja de tener sentido. El estado es «rechazada»:
    -- `chk_prop_estado` sólo admite pendiente / aceptada / rechazada, y
    -- «descartada» —que se usó por descuido en MIG419— habría reventado ahí.
    UPDATE certificacion_propuestas p
       SET estado = 'rechazada', resuelto_at = NOW(),
           nota_resolucion = 'El documento no caduca.'
      FROM certificaciones c
     WHERE p.certificacion_id = c.id AND p.estado = 'pendiente'
       AND ((p_alcance = 'este' AND c.id = p_certificacion_id)
         OR (p_alcance = 'tipo' AND c.tipo::text = v_tipo));

    RETURN jsonb_build_object('success', true, 'tipo', v_tipo, 'patente', v_patente,
                              'alcance', p_alcance, 'papeles_resueltos', v_afectados);
END $function$;

-- ── 3. Deshacerlo ─────────────────────────────────────────────────────────
-- Marcar mal un tipo deja de pedir un papel que sí hay que renovar. Tiene que
-- poder revertirse desde la misma pantalla, no con una migración.
CREATE OR REPLACE FUNCTION public.rpc_certificacion_vuelve_a_caducar(
    p_certificacion_id uuid,
    p_alcance          text DEFAULT 'este')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_rol TEXT; v_tipo TEXT; v_afectados INT;
BEGIN
    SELECT rol INTO v_rol FROM usuarios_perfil WHERE id = auth.uid();
    IF v_rol IS NULL OR v_rol NOT IN ('administrador','subgerente_operaciones',
                                      'jefe_mantenimiento','prevencionista','planificador') THEN
        RAISE EXCEPTION 'No tienes permiso para cambiar esto.';
    END IF;

    SELECT tipo::text INTO v_tipo FROM certificaciones WHERE id = p_certificacion_id;
    IF v_tipo IS NULL THEN RAISE EXCEPTION 'No se encontró el documento.'; END IF;

    IF p_alcance = 'tipo' THEN
        DELETE FROM certificado_tipo_permanente WHERE tipo = v_tipo;
    END IF;

    UPDATE certificaciones
       SET fecha_origen      = NULL,
           fecha_origen_nota = 'MIG427 · se revirtió la marca de «no caduca»: vuelve a pedir fecha.',
           updated_at        = NOW()
     WHERE fecha_origen = 'documento_sin_vencimiento'
       AND ((p_alcance = 'este' AND id = p_certificacion_id)
         OR (p_alcance = 'tipo' AND tipo::text = v_tipo));
    GET DIAGNOSTICS v_afectados = ROW_COUNT;

    RETURN jsonb_build_object('success', true, 'tipo', v_tipo, 'papeles_afectados', v_afectados);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_certificacion_no_caduca(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_certificacion_vuelve_a_caducar(uuid, text) TO authenticated;

-- ── 4. Que la pantalla sepa qué tipos ya están marcados ───────────────────
-- Se agrega UNA columna sobre la definición que ya existe. Reescribir la vista
-- de memoria habría borrado activo_codigo, activo_nombre, activo_tipo y
-- activo_estado, que la pantalla usa para armar la lista de equipos.
CREATE OR REPLACE VIEW public.v_control_documental AS
 SELECT a.id AS activo_id,
    COALESCE(a.patente, a.codigo) AS patente,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.tipo::text AS activo_tipo,
    a.estado::text AS activo_estado,
    v.id AS certificacion_id,
    v.tipo::text AS tipo,
    v.numero_certificado,
    v.entidad_certificadora,
    v.fecha_emision,
    v.fecha_vencimiento,
    v.estado_real::text AS estado,
    v.dias_restantes,
    v.archivo_url,
    v.bloqueante,
    c.fecha_origen,
    p.id AS propuesta_id,
    p.vencimiento_propuesto,
    p.emision_propuesta,
    p.confianza AS propuesta_confianza,
    p.regla AS propuesta_regla,
    p.evidencia AS propuesta_evidencia,
    p.vencimiento_propuesto IS NOT NULL AND p.vencimiento_propuesto < CURRENT_DATE AS propuesta_vencida,
    -- [MIG427] Si el tipo entero está marcado, el botón de la pantalla tiene
    -- que ofrecer revertirlo en vez de volver a marcarlo.
    fn_certificado_tipo_permanente(v.tipo::text) AS tipo_no_caduca
   FROM v_certificacion_actual v
     JOIN activos a ON a.id = v.activo_id
     JOIN certificaciones c ON c.id = v.id
     LEFT JOIN certificacion_propuestas p ON p.certificacion_id = v.id AND p.estado = 'pendiente'::text
  WHERE a.estado <> 'dado_baja'::estado_activo_enum;

GRANT SELECT ON public.v_control_documental TO authenticated;

DO $r$
DECLARE v_t INT; v_p INT;
BEGIN
    SELECT count(*) INTO v_t FROM certificado_tipo_permanente;
    SELECT count(*) INTO v_p FROM v_control_documental WHERE tipo_no_caduca;
    RAISE NOTICE 'Tipos que no caducan: % | papeles de esos tipos: %', v_t, v_p;
END
$r$;

COMMIT;
