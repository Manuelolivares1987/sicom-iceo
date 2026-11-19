-- ============================================================================
-- MIG713 — Marco Díaz pasa a mecánico de Franke: puede SACAR de la bodega
-- ----------------------------------------------------------------------------
-- Manuel (18-11-2026): «Marco Díaz y Yohan ahora están de mecánicos». Yohan
-- (yrondon@pillado.cl) ya quedó con «solo sacar» en MIG712. Se agrega Marco
-- Díaz (marco.diaz@sicom-iceo.cl, rol operador_taller) con el mismo permiso.
-- No se toca su faena ni su rol (sigue en el taller/bono de Coquimbo).
-- Rollback: DELETE FROM bodega_responsables WHERE email = 'marco.diaz@sicom-iceo.cl'
--           AND bodega_id = (SELECT id FROM bodegas WHERE codigo = 'BOD-FRK-F01');
-- ============================================================================
INSERT INTO public.bodega_responsables (bodega_id, usuario_id, nombre, email, puede_operar, recibe_alertas, tipo_correo, activo, solo_sacar)
SELECT b.id, u.id, u.nombre_completo || ' (mecánico, solo sacar)', u.email, false, false, 'cc', true, true
  FROM bodegas b, usuarios_perfil u
 WHERE b.codigo = 'BOD-FRK-F01' AND u.email = 'marco.diaz@sicom-iceo.cl'
ON CONFLICT (bodega_id, email) DO UPDATE SET solo_sacar = true, activo = true, usuario_id = EXCLUDED.usuario_id;

DO $$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM bodega_responsables r JOIN bodegas b ON b.id = r.bodega_id
     WHERE b.codigo = 'BOD-FRK-F01' AND r.solo_sacar AND r.activo;
    IF NOT EXISTS (SELECT 1 FROM bodega_responsables r JOIN bodegas b ON b.id = r.bodega_id
                    WHERE b.codigo = 'BOD-FRK-F01' AND r.email = 'marco.diaz@sicom-iceo.cl' AND r.solo_sacar) THEN
        RAISE EXCEPTION 'MIG713: no se agregó a Marco Díaz';
    END IF;
    RAISE NOTICE 'MIG713 OK: % mecánicos con «solo sacar» en Franke', v_n;
END $$;
