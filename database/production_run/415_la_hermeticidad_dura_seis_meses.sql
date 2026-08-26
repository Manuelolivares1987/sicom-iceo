-- ============================================================================
-- MIG415 · La hermeticidad dura seis meses, no un año
-- ----------------------------------------------------------------------------
-- LO QUE AVISÓ MANUEL
-- 26-08-2026: «Hermeticidad del estanque del camión DJKL 18, está mal, el
-- vencimiento es 29/06/2026».
--
-- Tenía razón, y al tirar del hilo apareció algo bastante peor que un dato malo.
--
-- ── LO QUE DICE EL PAPEL ───────────────────────────────────────────────────
-- Certificado Nº 12/2025 del DJKL-18, firmado por el Jefe de Operaciones:
--     Fecha de inspección  : 29 de diciembre de 2025
--     Fecha de vencimiento : 29 de junio de 2026
--
-- Seis meses. La base tenía 29/06/2026 como EMISIÓN y 29/06/2027 como
-- vencimiento: alguien leyó el vencimiento como si fuera la fecha de la prueba
-- y le sumó un año. El camión lleva 58 días vencido con un certificado
-- bloqueante en verde.
--
-- ── NO ERA UNO ─────────────────────────────────────────────────────────────
-- De los 25 certificados de hermeticidad de la flota, 24 estaban cargados con
-- 365 días de vigencia. Sólo el TCJV-15 tenía 183. Se leyeron los documentos
-- que tienen texto, más el escaneo del DJKL-18 a ojo:
--
--   PATENTE    DICE EL PAPEL              TENÍA LA BASE      REAL
--   DJKL-18    29-12-2025 → 29-06-2026    hasta 29-06-2027   vencido hace 58 d
--   DCHD-83    27-01-2026 → 27-07-2026    hasta 31-12-2027   vencido hace 30 d
--   KVWD-27    13-01-2026 → 13-07-2026    hasta 11-10-2025   vencido hace 44 d
--   SVBJ-57    05-01-2026 → 05-07-2026    hasta 05-07-2027   vencido hace 52 d
--   TCJV-15    12-06-2026 → 12-12-2026    hasta 12-12-2026   correcto
--
-- Cinco documentos leídos, cinco dicen seis meses. Y el error no es un
-- corrimiento parejo que se pueda deshacer con una resta: el DCHD-83 tenía
-- 31-12-2026 de emisión, que no es ni la inspección ni el vencimiento. Son
-- datos inventados en la carga de abril.
--
-- ── LO QUE SE CORRIGE Y LO QUE NO ──────────────────────────────────────────
-- Se corrigen los cuatro que se leyeron. Los otros 21 son escaneos sin texto:
-- no se les inventa una fecha, pero TAMPOCO se les sigue diciendo «vigente».
-- Un certificado bloqueante que el sistema no puede sostener tiene que decir
-- que no lo puede sostener. Quedan marcados para revisión con su propuesta y
-- un aviso por camión.
--
-- Por qué importa: la hermeticidad del estanque es lo que autoriza a ese camión
-- a mover combustible. No es un papel de archivo.
-- ============================================================================

BEGIN;

-- ── 1. Los cuatro que dicen su fecha ──────────────────────────────────────
CREATE TEMP TABLE _herm(patente TEXT, insp DATE, vence DATE, cert TEXT) ON COMMIT DROP;
INSERT INTO _herm VALUES
  ('DJKL-18','2025-12-29','2026-06-29','12/2025'),
  ('DCHD-83','2026-01-27','2026-07-27','01/2026'),
  ('KVWD-27','2026-01-13','2026-07-13',NULL),
  ('SVBJ-57','2026-01-05','2026-07-05',NULL);

UPDATE certificaciones c
   SET fecha_emision     = h.insp,
       fecha_vencimiento = h.vence,
       fecha_origen      = 'documento',
       fecha_origen_nota = 'MIG415 · leído del certificado'
                         || COALESCE(' Nº ' || h.cert, '')
                         || ': inspección ' || to_char(h.insp,'DD-MM-YYYY')
                         || ', vencimiento ' || to_char(h.vence,'DD-MM-YYYY')
                         || ' (vigencia 6 meses)',
       updated_at        = NOW()
  FROM _herm h, activos a
 WHERE c.activo_id = a.id AND COALESCE(a.patente,a.codigo) = h.patente
   AND c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual);

-- ── 2. Los 21 escaneos: no se inventan, pero dejan de decir «vigente» ─────
-- Se les deja una propuesta pendiente para que Control documental los muestre
-- arriba, con la evidencia de por qué se desconfía de la fecha que tienen.
INSERT INTO certificacion_propuestas
    (certificacion_id, vencimiento_propuesto, emision_propuesta, confianza, regla, evidencia, estado)
SELECT c.id, NULL, NULL, 'sin_fecha',
       'vigencia_sospechosa',
       'Cargado con ' || (c.fecha_vencimiento::date - c.fecha_emision::date) || ' días de vigencia. '
       || 'Los certificados de hermeticidad que sí se pudieron leer (DJKL-18, DCHD-83, KVWD-27, '
       || 'SVBJ-57, TCJV-15) dicen todos 6 meses. Este es un escaneo sin texto: hay que abrirlo '
       || 'y anotar la fecha que dice el papel.',
       'pendiente'
  FROM certificaciones c
  JOIN activos a ON a.id = c.activo_id
 WHERE c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual)
   AND a.estado <> 'dado_baja'::estado_activo_enum
   AND c.fecha_origen IS DISTINCT FROM 'documento'
   AND c.fecha_emision < '2099-01-01'::date
   AND (c.fecha_vencimiento::date - c.fecha_emision::date) > 200
   AND NOT EXISTS (SELECT 1 FROM certificacion_propuestas p
                    WHERE p.certificacion_id = c.id AND p.estado = 'pendiente');

-- ── 3. Un aviso por camión, crítico: es un papel que autoriza a operar ────
INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                     destinatario_id, requiere_accion, leida, created_at)
SELECT 'doc_sin_fecha',
       'Hermeticidad por verificar: ' || COALESCE(a.patente,a.codigo),
       'El certificado de hermeticidad del ' || COALESCE(a.patente,a.codigo) ||
       ' está cargado con ' || (c.fecha_vencimiento::date - c.fecha_emision::date) ||
       ' días de vigencia, pero todos los certificados de hermeticidad que se pudieron ' ||
       'leer dicen 6 meses. Es un escaneo: hay que abrir el archivo y anotar la fecha real. ' ||
       'Es un certificado bloqueante: mientras no se verifique, no hay respaldo de que el ' ||
       'estanque esté autorizado.',
       'critical', 'activo', a.id, u.id, true, false, NOW()
  FROM certificaciones c
  JOIN activos a ON a.id = c.activo_id
 CROSS JOIN (SELECT id FROM usuarios_perfil
              WHERE activo = true
                AND rol IN ('administrador','subgerente_operaciones','jefe_mantenimiento','prevencionista')) u
 WHERE c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual)
   AND a.estado <> 'dado_baja'::estado_activo_enum
   AND c.fecha_origen IS DISTINCT FROM 'documento'
   AND c.fecha_emision < '2099-01-01'::date
   AND (c.fecha_vencimiento::date - c.fecha_emision::date) > 200
   AND NOT EXISTS (SELECT 1 FROM alertas al
                    WHERE al.tipo = 'doc_sin_fecha' AND al.entidad_id = a.id
                      AND al.destinatario_id = u.id AND NOT al.leida
                      AND al.titulo LIKE 'Hermeticidad%');

-- ── 4. Que el lector sepa cuánto dura ─────────────────────────────────────
-- La regla de 2 años fue un acuerdo razonable para papeles que no declaran
-- vigencia. La hermeticidad SÍ la declara, y son 6 meses: aplicarle 2 años es
-- exactamente cómo se llegó a esto. Queda escrito en la base para que el lector
-- y quien cargue a mano usen el mismo número.
CREATE TABLE IF NOT EXISTS public.certificado_vigencia_estandar (
    tipo            TEXT PRIMARY KEY,
    meses           INT  NOT NULL CHECK (meses > 0),
    fuente          TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.certificado_vigencia_estandar IS
  'MIG415: cuánto dura cada tipo de certificado según sus propios documentos. La regla de 2 años sólo aplica donde no hay un estándar acá.';

INSERT INTO certificado_vigencia_estandar (tipo, meses, fuente) VALUES
  ('hermeticidad', 6, 'Certificados Nº 12/2025 (DJKL-18) y 01/2026 (DCHD-83): inspección mas 6 meses exactos. Verificado en 5 documentos.')
ON CONFLICT (tipo) DO UPDATE SET meses = EXCLUDED.meses, fuente = EXCLUDED.fuente;

ALTER TABLE public.certificado_vigencia_estandar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "vigencia_estandar_lectura" ON public.certificado_vigencia_estandar;
CREATE POLICY "vigencia_estandar_lectura" ON public.certificado_vigencia_estandar
  FOR SELECT TO authenticated USING (true);

DO $r$
DECLARE v_corr INT; v_marc INT; v_venc INT; v_avisos INT;
BEGIN
    SELECT count(*) INTO v_corr FROM certificaciones WHERE fecha_origen_nota LIKE 'MIG415%';
    SELECT count(*) INTO v_marc FROM certificacion_propuestas WHERE regla='vigencia_sospechosa' AND estado='pendiente';
    SELECT count(*) INTO v_avisos FROM alertas WHERE titulo LIKE 'Hermeticidad por verificar%' AND NOT leida;
    SELECT count(*) INTO v_venc FROM v_certificacion_actual v JOIN certificaciones c ON c.id=v.id
     WHERE c.tipo::text='hermeticidad' AND c.fecha_vencimiento::date < CURRENT_DATE;
    RAISE NOTICE 'Corregidos con el documento: % | marcados para abrir: % | avisos: % | hermeticidades vencidas ahora: %',
        v_corr, v_marc, v_avisos, v_venc;
END
$r$;

COMMIT;
