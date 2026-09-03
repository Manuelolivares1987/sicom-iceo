-- Diag (solo lectura): ¿por qué el operador no ve la OS que se planificó?
DO $d$
DECLARE r RECORD;
BEGIN
    -- Las OS creadas los últimos 3 días, con su asignación y el vínculo de cuenta.
    FOR r IN
        SELECT o.folio, o.titulo, o.estado, o.created_at::date AS creada,
               ot.folio AS ot_folio, ot.estado::text AS ot_estado,
               t.nombre AS tecnico, t.usuario_perfil_id IS NOT NULL AS cuenta_vinculada,
               a.hasta IS NULL AS asignacion_vigente
          FROM taller_os o
          JOIN ordenes_trabajo ot ON ot.id = o.ot_id
          LEFT JOIN taller_os_asignacion a ON a.os_id = o.id
          LEFT JOIN taller_tecnicos t ON t.id = a.tecnico_id
         WHERE o.created_at > NOW() - INTERVAL '3 days'
         ORDER BY o.created_at DESC
    LOOP
        RAISE NOTICE 'OS % «%» estado=% · OT % (%) · tecnico=% vinculado=% vigente=%',
            r.folio, r.titulo, r.estado, r.ot_folio, r.ot_estado,
            COALESCE(r.tecnico,'(nadie)'), r.cuenta_vinculada, r.asignacion_vigente;
    END LOOP;

    -- Técnicos activos y si tienen cuenta vinculada (MIG478).
    FOR r IN SELECT nombre, usuario_perfil_id IS NOT NULL AS vinculado
               FROM taller_tecnicos WHERE COALESCE(activo,true) ORDER BY nombre LOOP
        RAISE NOTICE 'tecnico % · cuenta vinculada=%', r.nombre, r.vinculado;
    END LOOP;
END $d$;
