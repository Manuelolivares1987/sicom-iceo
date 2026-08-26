-- ============================================================================
-- MIG424 · Una póliza siempre tiene vigencia
-- ----------------------------------------------------------------------------
-- MIG419 dejó 86 papeles en «sin vencimiento» siguiendo la regla de Manuel: si
-- el documento no lo dice, no se inventa. Revisando qué tipos quedaron ahí, la
-- mayoría son certificados de taller —tacógrafo, ECM, mantención hidráulica,
-- torque de ruedas— donde «este papel no declara vencimiento» es perfectamente
-- normal.
--
-- Pero hay 7 pólizas de seguro. Una póliza SIEMPRE tiene período de vigencia:
-- es lo que se está comprando. Que el lector no lo haya encontrado significa
-- que no lo supo leer, no que el papel no lo diga.
--
-- ── POR QUÉ SE SABE QUE EL LECTOR FALLA ────────────────────────────────────
-- Se comprobó con un SOAP. El lector lo declaró «no menciona vencimiento», y
-- el documento lo dice en una tabla:
--
--     MODELO  AÑO   RUT          RIGE DESDE   HASTA
--     Canter  2011  77316540-8   01/10/2025   30/09/2026
--
-- La etiqueta va en la fila de títulos y la fecha en la de valores, sin la
-- palabra «vencimiento» en ninguna parte. El lector busca la palabra; el papel
-- usa una tabla. Por eso «no declara» no es una conclusión confiable todavía, y
-- por eso estas 7 no se dejan como resueltas.
--
-- Se revisó lo importante primero: entre los 86 NO hay ningún SOAP, ninguna
-- revisión técnica y ningún permiso de circulación. Esos tres vencen por ley y
-- haberlos dejado sin vencimiento habría sido grave. No pasó.
--
-- Las 7 pólizas vuelven a «falta la fecha»: alguien las abre y anota el período
-- que dicen. Es trabajo real y corto, sobre documentos que se sabe que lo traen.
-- ============================================================================

BEGIN;

UPDATE certificaciones c
   SET vigencia_dudosa = TRUE,
       vigencia_dudosa_nota =
         'MIG424 · quedó como «sin vencimiento» porque el lector no encontró la '
         || 'fecha, pero una póliza siempre trae período de vigencia. Hay que abrir '
         || 'el PDF y anotar hasta cuándo rige.',
       fecha_origen = NULL,
       fecha_origen_nota = 'MIG424 · revierte la conclusión de MIG419 para este tipo de documento.',
       updated_at = NOW()
 WHERE c.fecha_origen = 'documento_sin_vencimiento'
   AND c.tipo::text IN ('seguro_rc', 'soap', 'revision_tecnica', 'permiso_circulacion');

DO $r$
DECLARE v_p INT; v_sv INT; v_soap INT;
BEGIN
    SELECT count(*) INTO v_p FROM certificaciones WHERE vigencia_dudosa_nota LIKE 'MIG424%';
    SELECT count(*) INTO v_sv FROM certificaciones WHERE fecha_origen = 'documento_sin_vencimiento';
    SELECT count(*) INTO v_soap FROM certificaciones
     WHERE fecha_origen = 'documento_sin_vencimiento'
       AND tipo::text IN ('soap','revision_tecnica','permiso_circulacion');
    RAISE NOTICE 'Devueltas a revisar: % | quedan sin vencimiento: % | de esos, tipos que vencen por ley: %',
        v_p, v_sv, v_soap;
END
$r$;

COMMIT;
