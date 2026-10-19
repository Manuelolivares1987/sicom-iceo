-- 614 — ESMAX también exige el TC8 del estanque (Manuel 2026-10-19: «el TC8 para
-- los camiones que falta también es un pendiente»). Sólo cambia la lista de la
-- cuenta: portal y correo diario (MIG612-613) lo toman solos.
UPDATE portal_flota_cuentas
   SET documentos_exigidos = ARRAY['revision_tecnica','soap','permiso_circulacion','tc8_sec','programa_mantenimiento'],
       updated_at = NOW()
 WHERE email = 'esmax@pillado.cl';

SELECT json_agg(a.patente||':'||t ORDER BY a.patente, t) AS pendientes
  FROM portal_flota_cuentas c
  JOIN LATERAL fn_portal_flota_activos(c) act(id) ON true
  JOIN activos a ON a.id = act.id
  CROSS JOIN LATERAL unnest(c.documentos_exigidos) t
 WHERE c.email = 'esmax@pillado.cl'
   AND NOT EXISTS (SELECT 1 FROM rpc_documentos_activo_publico(a.id) x WHERE x.tipo = t);
