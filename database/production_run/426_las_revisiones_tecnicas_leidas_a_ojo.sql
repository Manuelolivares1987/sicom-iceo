-- ============================================================================
-- MIG426 · Las revisiones técnicas, leídas una por una
-- ----------------------------------------------------------------------------
-- Segunda tanda de la auditoría forense: los 19 certificados de revisión
-- técnica bloqueantes que el sistema no podía leer (escaneos, o archivos PNG y
-- JPEG guardados como si fueran PDF). Se abrieron todos.
--
-- ── EL RESULTADO ───────────────────────────────────────────────────────────
--   13 estaban bien cargados en el sistema
--    4 no tenían fecha y ahora la tienen
--    2 aparecían VIGENTES estando vencidos
--
-- Los dos últimos son el hallazgo:
--
--   JDKH-31   el papel dice ABRIL 2026     el sistema decía 31-12-2026
--   SVBJ-55   el papel dice 30-06-2026     el sistema decía 26-12-2026
--
-- Ninguno de los dos aparecía en la lista de vencidos. Llevan 118 y 57 días
-- circulando con la revisión técnica caducada y el sistema en verde.
--
-- ── LO QUE ENSEÑÓ LEERLAS ──────────────────────────────────────────────────
-- La revisión técnica chilena declara su vigencia como MES y AÑO —«VÁLIDO
-- HASTA SEPTIEMBRE 2026»— y en la misma línea imprime el sello de la firma
-- electrónica con su hora. Un lector que busque «una fecha cerca de la palabra
-- hasta» se lleva el sello. Por eso estos certificados hay que leerlos con la
-- regla de que una fecha seguida de hora es una firma, no una vigencia; ya
-- quedó en los tests de lib/leer-papel.mjs.
--
-- Cuando el papel dice sólo el mes, la vigencia cubre el mes completo: se
-- registra el último día. No es una suposición, es cómo funciona el permiso.
--
-- ── DE PASO ────────────────────────────────────────────────────────────────
-- Varios de estos camiones figuran a nombre de bancos —Santander, BBVA, BCI— y
-- de terceros como B K SpA. Son leasings; no es un problema documental, pero
-- explica por qué el papel no siempre llega solo a la carpeta.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _rt(patente TEXT, insp DATE, vence DATE, nota TEXT) ON COMMIT DROP;
INSERT INTO _rt VALUES
  -- Aparecían vigentes y están vencidos
  ('JDKH-31','2025-04-30','2026-04-30','El certificado dice VALIDO HASTA ABRIL 2026. El sistema lo daba vigente hasta el 31-12-2026.'),
  ('SVBJ-55','2025-12-30','2026-06-30','El certificado dice 30 JUNIO 2026. El sistema lo daba vigente hasta el 26-12-2026.'),
  -- No tenían fecha
  ('GCSY-66','2025-05-29','2029-05-29','Grúa Toyota: la revisión técnica de este equipo rige hasta 2029.'),
  ('KVDK-20','2026-03-03','2027-02-28','VÁLIDO HASTA FEBRERO 2027: cubre el mes completo.'),
  ('RZPC-83','2025-06-30','2027-06-30','VÁLIDO HASTA JUNIO 2027.'),
  ('SBPG-12','2025-06-02','2027-05-31','VÁLIDO HASTA MAYO 2027: cubre el mes completo.'),
  -- Confirmados correctos: se les deja la fecha de inspección y el origen
  ('DCHD-83','2026-05-28','2026-11-28', NULL),
  ('FJTJ-60','2026-08-03','2027-02-03', NULL),
  ('FJTJ-61','2026-07-09','2027-01-09', NULL),
  ('FSLZ-67','2026-06-26','2026-12-26', NULL),
  ('HHWB-44','2026-06-08','2026-12-05', NULL),
  ('HKSR-81','2025-12-05','2026-06-04', NULL),
  ('JTYK-88','2026-07-09','2027-01-08', NULL),
  ('KCBY-31','2026-06-17','2026-12-16', NULL),
  ('LKPY-18','2026-02-18','2026-08-18', NULL),
  ('LLBP-96','2025-09-26','2026-09-30', NULL),
  ('RSCY-85','2026-07-30','2027-01-30', NULL),
  ('TGGF-58','2026-08-12','2027-02-12', NULL),
  ('TTPC-47','2026-07-10','2027-01-10', NULL);

UPDATE certificaciones c
   SET fecha_emision     = r.insp,
       fecha_vencimiento = r.vence,
       fecha_origen      = 'documento',
       fecha_origen_nota = 'MIG426 · leído a ojo del escaneo: revisión ' || to_char(r.insp,'DD-MM-YYYY')
                         || ', válida hasta ' || to_char(r.vence,'DD-MM-YYYY')
                         || COALESCE(' · ' || r.nota, ''),
       vigencia_dudosa   = FALSE,
       vigencia_dudosa_nota = NULL,
       updated_at        = NOW()
  FROM _rt r, activos a
 WHERE c.activo_id = a.id AND COALESCE(a.patente,a.codigo) = r.patente
   AND c.tipo::text = 'revision_tecnica'
   AND c.id IN (SELECT id FROM v_certificacion_actual);

-- ── Lo que se leyó por texto en la misma auditoría ────────────────────────
-- Tres documentos con texto cuyo dictamen no coincidía con el sistema y que se
-- verificaron frase por frase.
CREATE TEMP TABLE _texto(patente TEXT, tipo TEXT, insp DATE, vence DATE, nota TEXT) ON COMMIT DROP;
INSERT INTO _texto VALUES
  ('TGGF-59','revision_tecnica','2026-03-19','2026-09-19',
   'El certificado dice VALIDA HASTA 19 SEPTIEMBRE 2026. El sistema decía 31-12-2026.'),
  ('KVWD-27','analisis_gases','2025-11-14','2026-05-14',
   'El certificado dice VALIDA HASTA 14 MAYO 2026. El sistema decía 20-11-2025.'),
  ('GCSY-66','seguro_rc','2023-01-09','2024-01-09',
   'La póliza rige del 09-01-2023 al 09-01-2024, 365 días. El sistema no tenía fecha: lleva vencida más de dos años.');

UPDATE certificaciones c
   SET fecha_emision     = t.insp,
       fecha_vencimiento = t.vence,
       fecha_origen      = 'documento',
       fecha_origen_nota = 'MIG426 · leído del texto del documento: ' || t.nota,
       vigencia_dudosa   = FALSE,
       vigencia_dudosa_nota = NULL,
       updated_at        = NOW()
  FROM _texto t, activos a
 WHERE c.activo_id = a.id AND COALESCE(a.patente,a.codigo) = t.patente
   AND c.tipo::text = t.tipo
   AND c.id IN (SELECT id FROM v_certificacion_actual);

DO $r$
DECLARE v_v INT; v_t INT; v_b INT;
BEGIN
    SELECT count(*) FILTER (WHERE v.estado_real::text = 'vencido'), count(*)
      INTO v_v, v_t
      FROM v_certificacion_actual v JOIN certificaciones c ON c.id = v.id
      JOIN activos a ON a.id = v.activo_id
     WHERE c.tipo::text = 'revision_tecnica' AND a.estado <> 'dado_baja'::estado_activo_enum;
    SELECT count(*) INTO v_b
      FROM v_certificacion_actual v JOIN certificaciones c ON c.id = v.id
      JOIN activos a ON a.id = v.activo_id
     WHERE c.bloqueante AND v.estado_real::text = 'vencido' AND a.estado <> 'dado_baja'::estado_activo_enum;
    RAISE NOTICE 'Revisiones técnicas vencidas: % de % | bloqueantes vencidos en toda la flota: %', v_v, v_t, v_b;
END
$r$;

COMMIT;
