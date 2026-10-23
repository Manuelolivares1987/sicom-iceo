-- MIG643 · Portal de flota: equipos adicionales fuera del contrato
-- ============================================================================
-- El portal (MIG609) muestra los equipos de los contratos de la cuenta. El
-- SVBJ-56 (aljibe 15 kL, CC-15-14) debe verse en el portal de ESMAX, pero
-- está «disponible» y sin contrato: asignarlo a CTR-ESMAX-2025 cambiaría su
-- estado comercial y la disponibilidad de la flota.
--
-- portal_flota_cuentas.activos_extra: equipos que la cuenta ve además de los
-- de sus contratos. fn_portal_flota_activos es el único punto de alcance
-- (lista, ficha, descargas, pendientes del correo y conteo del admin).
-- ============================================================================

BEGIN;

ALTER TABLE portal_flota_cuentas
    ADD COLUMN IF NOT EXISTS activos_extra UUID[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION public.fn_portal_flota_activos(p_cuenta portal_flota_cuentas)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT a.id
      FROM activos a
     WHERE (a.contrato_id = ANY(p_cuenta.contratos_ids)
            OR a.id = ANY(COALESCE(p_cuenta.activos_extra, '{}')))
       AND a.fecha_baja IS NULL
       AND NOT COALESCE(a.es_prueba, false);
$function$;

UPDATE portal_flota_cuentas
   SET activos_extra = array_append(activos_extra, '284cc50a-d04c-402f-9a40-4d68663e9b6e'::uuid),
       updated_at = NOW()
 WHERE empresa = 'ESMAX'
   AND NOT ('284cc50a-d04c-402f-9a40-4d68663e9b6e'::uuid = ANY(activos_extra));

COMMIT;

SELECT c.nombre, (SELECT string_agg(coalesce(a.patente, a.codigo), ', ' ORDER BY a.patente)
                    FROM activos a WHERE a.id IN (SELECT fn_portal_flota_activos(c))) equipos
  FROM portal_flota_cuentas c WHERE c.empresa = 'ESMAX';
