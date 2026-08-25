-- ============================================================================
-- MIG391 · Primero el estándar, después lo que el camión debe
-- ----------------------------------------------------------------------------
-- MIG390 dejó «Documentación» con el mismo bloque_orden que «No conformidades
-- abiertas» (2), así que el empate lo resolvía el motor y las NC aparecían
-- después de los papeles.
--
-- El orden no es decorativo: es el orden en que se camina alrededor del camión.
-- Primero se mira el equipo contra su estándar, después se revisa lo que ya
-- estaba anotado como pendiente, y al final los papeles — que se revisan en la
-- oficina, no con el camión al lado.
-- ============================================================================

BEGIN;

UPDATE public.auditoria_calidad_plantilla_items
   SET bloque_orden = CASE WHEN categoria = 'documentacion' THEN 3 ELSE 4 END
 WHERE estandar IS NULL;

-- Y las auditorías que sigan abiertas se reordenan igual, para que nadie vea
-- una mitad con el orden viejo.
UPDATE public.auditoria_calidad_items i
   SET bloque_orden = CASE
        WHEN i.bloque = 'Estándar del camión'        THEN 1
        WHEN i.bloque = 'No conformidades abiertas'  THEN 2
        WHEN i.bloque = 'Documentación'              THEN 3
        ELSE 4 END
  FROM public.auditorias_calidad a
 WHERE a.id = i.auditoria_id
   AND a.resultado = 'pendiente' AND a.anulada = FALSE;

DO $r$
DECLARE v_row RECORD;
BEGIN
    FOR v_row IN
        SELECT bloque, min(bloque_orden) AS ord, count(*) AS n
          FROM public.auditoria_calidad_plantilla_items
         WHERE activo GROUP BY bloque ORDER BY 2
    LOOP
        RAISE NOTICE '% · orden % · % items', COALESCE(v_row.bloque,'(sin bloque)'), v_row.ord, v_row.n;
    END LOOP;
END
$r$;

COMMIT;
