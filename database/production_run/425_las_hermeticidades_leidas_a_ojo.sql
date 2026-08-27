-- ============================================================================
-- MIG425 · Las hermeticidades que hubo que leer a ojo
-- ----------------------------------------------------------------------------
-- Manuel pidió una auditoría forense de cada papel. Para los certificados que
-- son escaneos sin texto eso significa abrir la imagen y leerla, uno por uno.
-- Se hizo con los nueve certificados de hermeticidad bloqueantes que estaban
-- en esa situación. Ocho se pudieron leer.
--
--   PATENTE   INSPECCIÓN   VENCE (papel)   TENÍA EL SISTEMA   ESTADO REAL
--   FJTJ-60   01-10-2025   01-04-2026      hasta 01-04-2027   vencido 147 d
--   FSLZ-67   26-03-2026   25-09-2026      hasta 11-11-2027   vigente 30 d
--   HKSR-81   08-09-2021   08-03-2022      hasta 28-11-2024   vencido 1.632 d
--   JGBY-10   05-12-2025   05-06-2026      hasta 05-06-2027   vencido 82 d
--   LCSX-78   01-10-2025   01-04-2026      hasta 01-04-2027   vencido 147 d
--   SVBJ-56   15-10-2025   15-04-2026      sin fecha          vencido 133 d
--   TRST-57   05-05-2026   05-11-2026      hasta 05-11-2027   vigente 71 d
--
-- Seis de nueve están vencidos, y el sistema sólo sabía de uno.
--
-- ── TRES COSAS QUE APARECIERON AL MIRAR LOS PAPELES ────────────────────────
--
-- 1. El HKSR-81 tiene en carpeta un certificado de 2021 que venció en marzo de
--    2022. No es que la fecha esté mal cargada: es que no hay un papel más
--    nuevo. Ese camión lleva cuatro años y medio sin certificar el estanque.
--
-- 2. El certificado del LCSX-78 dice «Fecha de vencimiento: martes, 1 de abril
--    de 2025», anterior a su propia fecha de inspección (1 de octubre de 2025).
--    Es un error del emisor: 1 de abril de 2025 fue martes y el de 2026 fue
--    miércoles, así que se tipeó el año anterior. Se registra el 01-04-2026,
--    que es lo que corresponde a la prueba, y queda anotado que el papel está
--    mal emitido: hay que pedir la corrección.
--
-- 3. Tres camiones distintos —FJTJ-60, LCSX-78 y SVBJ-56— llevan el mismo
--    «CERTIFICADO Nº 10/2025» con fechas de prueba distintas. La numeración no
--    identifica nada. No se corrige acá porque no es un dato del sistema, pero
--    es un problema de control documental del emisor.
--
-- El RSCY-85 no se pudo leer: su PDF viene partido en tiras de 140 píxeles.
-- Queda marcado para reescanear, no se le inventa fecha.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _leidos(patente TEXT, insp DATE, vence DATE, cert TEXT, nota TEXT) ON COMMIT DROP;
INSERT INTO _leidos VALUES
  ('FJTJ-60','2025-10-01','2026-04-01','10/2025', NULL),
  ('FSLZ-67','2026-03-26','2026-09-25','02/2026', NULL),
  ('HKSR-81','2021-09-08','2022-03-08','09/2021',
   'El papel en carpeta es de 2021. No hay certificado más nuevo: el estanque lleva más de 4 años sin certificar.'),
  ('JGBY-10','2025-12-05','2026-06-05','12/2025', NULL),
  ('LCSX-78','2025-10-01','2026-04-01','10/2025',
   'El certificado dice vencimiento 01-04-2025, anterior a su propia inspección. Error de tipeo del emisor: hay que pedir la corrección.'),
  ('SVBJ-56','2025-10-15','2026-04-15','10/2025', NULL),
  ('TRST-57','2026-05-05','2026-11-05','01/2026', NULL);

UPDATE certificaciones c
   SET fecha_emision     = l.insp,
       fecha_vencimiento = l.vence,
       fecha_origen      = 'documento',
       fecha_origen_nota = 'MIG425 · leído a ojo del escaneo, certificado Nº ' || l.cert
                         || ': inspección ' || to_char(l.insp,'DD-MM-YYYY')
                         || ', vencimiento ' || to_char(l.vence,'DD-MM-YYYY')
                         || COALESCE(' · ' || l.nota, ''),
       vigencia_dudosa   = FALSE,
       vigencia_dudosa_nota = NULL,
       updated_at        = NOW()
  FROM _leidos l, activos a
 WHERE c.activo_id = a.id AND COALESCE(a.patente,a.codigo) = l.patente
   AND c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual);

-- El que no se pudo leer no se toca: se deja pidiendo un escaneo nuevo.
UPDATE certificaciones c
   SET vigencia_dudosa = TRUE,
       vigencia_dudosa_nota = 'MIG425 · el PDF viene partido en tiras de 140 píxeles y no se puede leer '
                            || 'ni a ojo. Hay que volver a escanear el certificado.',
       updated_at = NOW()
  FROM activos a
 WHERE c.activo_id = a.id AND COALESCE(a.patente,a.codigo) = 'RSCY-85'
   AND c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual);

DO $r$
DECLARE r RECORD; v_v INT := 0; v_t INT := 0;
BEGIN
    FOR r IN
        SELECT COALESCE(a.patente,a.codigo) AS patente, v.estado_real::text AS estado,
               c.fecha_vencimiento::date AS vence, (CURRENT_DATE - c.fecha_vencimiento::date) AS dias
          FROM v_certificacion_actual v JOIN certificaciones c ON c.id = v.id
          JOIN activos a ON a.id = v.activo_id
         WHERE c.tipo::text = 'hermeticidad' AND a.estado <> 'dado_baja'::estado_activo_enum
         ORDER BY c.fecha_vencimiento
    LOOP
        v_t := v_t + 1;
        IF r.estado = 'vencido' THEN v_v := v_v + 1; END IF;
        RAISE NOTICE '  % % % %', rpad(r.patente,10), rpad(r.estado,11),
            COALESCE(to_char(r.vence,'DD-MM-YYYY'),'—'),
            CASE WHEN r.dias > 0 THEN 'hace ' || r.dias || ' días' ELSE '' END;
    END LOOP;
    RAISE NOTICE 'Hermeticidad: % vencidas de %', v_v, v_t;
END
$r$;

COMMIT;
