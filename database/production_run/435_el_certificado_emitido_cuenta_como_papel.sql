-- ============================================================================
-- MIG435 · Un certificado que emite Pillado también es un papel del equipo
-- ----------------------------------------------------------------------------
-- LO QUE AVISÓ MANUEL
-- 27-08-2026: «ojo, hay varios certificados que se podían realizar; en la ficha
-- del equipo salía "Emitir Certificado". Todo esto debe salir en el control
-- documental».
--
-- Tenía razón en más de lo que se veía. Llevar el botón a Control documental es
-- la parte fácil. Al mirarlo apareció que los dos registros no se hablan.
--
-- ── DOS CARPETAS QUE NO SE MIRAN ───────────────────────────────────────────
-- `rpc_emitir_certificado_activo` escribe en `activo_certificados` y nada más.
-- `certificaciones` —de donde salen Control documental, la ficha, el QR del
-- cliente y los avisos— ni se entera.
--
-- O sea: se emite el «Certificado de mantención de aire acondicionado» del
-- camión, queda firmado por el operador y el jefe de taller, y Control
-- documental sigue diciendo que el papel de aire acondicionado está vencido.
-- Los dos tienen razón, porque son dos archivadores distintos.
--
-- Hoy `activo_certificados` está vacío: nadie emitió ninguno todavía. No hay
-- nada que migrar, pero el hueco muerde el primer día que se use.
--
-- ── LA VIGENCIA NO SE INVENTA ──────────────────────────────────────────────
-- Cuánto dura un certificado de mantención no lo sé, y suponerlo es
-- exactamente lo que produjo esta auditoría. Se usa lo que esté declarado en
-- `certificado_vigencia_estandar`; si el tipo no está ahí, el papel se registra
-- SIN VENCIMIENTO, que es la regla que fijó Manuel: si no consta, no se
-- inventa. Cuando se sepa cuánto dura cada uno, se agrega a esa tabla y los
-- siguientes salen con fecha.
--
-- ── CINCO DE SEIS ──────────────────────────────────────────────────────────
-- El mapeo va en una tabla, no en un CASE dentro de la función, porque va a
-- cambiar. Se dejan los cinco que son inequívocos.
--
-- El sexto —«Certificado sistema de carga y descarga de agua»— NO se mapea. Los
-- candidatos son `sist_riego` y `flujo_descarga` y ninguno es claramente el
-- mismo papel. Mapearlo mal haría que un certificado renueve el vencimiento de
-- otro documento distinto, que es peor que no mapearlo. Queda pendiente de que
-- alguien que sepa lo decida.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.certificado_tipo_equivale (
    tipo_codigo TEXT PRIMARY KEY REFERENCES certificado_tipos(codigo),
    tipo_papel  TEXT NOT NULL,
    nota        TEXT
);

COMMENT ON TABLE public.certificado_tipo_equivale IS
  'MIG435: qué papel del equipo renueva cada certificado que emite Pillado. Lo que no esté acá se emite igual, pero no toca certificaciones.';

INSERT INTO certificado_tipo_equivale (tipo_codigo, tipo_papel, nota) VALUES
  ('ultima_mantencion',  'mantencion',         NULL),
  ('sistema_hidraulico', 'mant_hidraulico',    NULL),
  ('aire_acondicionado', 'aire_acondicionado', NULL),
  ('tacografo',          'tacografo',          NULL),
  ('ecm',                'ausencia_falla_ecm', NULL)
ON CONFLICT (tipo_codigo) DO NOTHING;

ALTER TABLE public.certificado_tipo_equivale ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cert_equivale_lectura" ON public.certificado_tipo_equivale;
CREATE POLICY "cert_equivale_lectura" ON public.certificado_tipo_equivale
  FOR SELECT TO authenticated USING (true);

-- ── Emitir el certificado renueva el papel ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_certificado_activo_renueva_papel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_papel TEXT; v_meses INT; v_vence DATE; v_origen TEXT; v_nota TEXT;
BEGIN
    SELECT tipo_papel INTO v_papel
      FROM certificado_tipo_equivale WHERE tipo_codigo = NEW.tipo_codigo;
    IF v_papel IS NULL THEN RETURN NEW; END IF;   -- no equivale a ningún papel

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = v_papel;

    IF v_meses IS NULL THEN
        -- No consta cuánto dura: se registra sin vencimiento en vez de
        -- inventarle uno. Es la regla que fijó Manuel el 26-08.
        v_vence  := '2099-12-31'::date;
        v_origen := 'documento_sin_vencimiento';
        v_nota   := 'MIG435 · emitido por Pillado, certificado Nº '
                 || lpad(NEW.numero::text, 2, '0')
                 || '. No consta cuánto dura este certificado: queda sin vencimiento hasta que se declare.';
    ELSE
        v_vence  := (NEW.fecha_emision + (v_meses || ' months')::INTERVAL)::date;
        v_origen := 'documento';
        v_nota   := 'MIG435 · emitido por Pillado, certificado Nº '
                 || lpad(NEW.numero::text, 2, '0')
                 || ': emitido ' || to_char(NEW.fecha_emision,'DD-MM-YYYY')
                 || ', vence ' || to_char(v_vence,'DD-MM-YYYY')
                 || ' (' || v_meses || ' meses).';
    END IF;

    INSERT INTO certificaciones (
        activo_id, tipo, fecha_emision, fecha_vencimiento, numero_certificado,
        entidad_certificadora, bloqueante, archivo_url,
        fecha_origen, fecha_origen_nota, notas, created_by)
    VALUES (
        NEW.activo_id, v_papel::tipo_certificacion_enum, NEW.fecha_emision, v_vence,
        lpad(NEW.numero::text, 2, '0'), 'PILLADO Y COMPAÑÍA LTDA.', FALSE,
        -- El certificado se ve e imprime en su propia página.
        '/certificado/' || NEW.id,
        v_origen, v_nota,
        'Certificado emitido desde SICOM, firmado por ' || COALESCE(NEW.operador_nombre,'—')
          || ' y ' || COALESCE(NEW.jefe_nombre,'—') || '.',
        NEW.created_by);

    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_cert_activo_renueva_papel ON public.activo_certificados;
CREATE TRIGGER trg_cert_activo_renueva_papel
  AFTER INSERT ON public.activo_certificados
  FOR EACH ROW EXECUTE FUNCTION public.fn_certificado_activo_renueva_papel();

DO $r$
DECLARE r RECORD;
BEGIN
    RAISE NOTICE 'Qué papel renueva cada certificado que emite Pillado:';
    FOR r IN
        SELECT ct.codigo, ct.titulo, e.tipo_papel,
               (SELECT meses FROM certificado_vigencia_estandar v WHERE v.tipo = e.tipo_papel) AS meses
          FROM certificado_tipos ct
          LEFT JOIN certificado_tipo_equivale e ON e.tipo_codigo = ct.codigo
         WHERE ct.activo ORDER BY ct.orden
    LOOP
        RAISE NOTICE '  % -> %  %',
            rpad(r.codigo, 22),
            rpad(COALESCE(r.tipo_papel, '(sin equivalencia: no toca certificaciones)'), 34),
            CASE WHEN r.tipo_papel IS NULL THEN ''
                 WHEN r.meses IS NULL THEN 'sin vencimiento (no consta cuánto dura)'
                 ELSE r.meses || ' meses' END;
    END LOOP;
END
$r$;

COMMIT;
