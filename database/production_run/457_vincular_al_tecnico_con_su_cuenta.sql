-- ============================================================================
-- MIG457 · Vincular al técnico con su cuenta, o la cartola no la ve nadie
-- ============================================================================
--
-- LO QUE APARECIÓ AL APLICAR MIG456
-- La cartola identifica al trabajador por `taller_tecnicos.usuario_perfil_id`.
-- La verificación del cierre dejó el número a la vista:
--
--     técnicos con cuenta vinculada (verán su cartola): 0
--     técnicos SIN cuenta vinculada (no podrán entrar): 9
--
-- Los nueve mecánicos del taller. La pantalla está construida y no la puede
-- abrir ninguno de ellos.
--
-- QUÉ SE PUEDE ARREGLAR ACÁ Y QUÉ NO
-- Buscando por nombre en `usuarios_perfil`, sólo DOS de los nueve tienen cuenta:
--
--     Juan Valenzuela  → cuenta «Juan Valenzuela» [tecnico_mantenimiento]
--     Felipe López     → cuenta «Felipe López»    [auditor_calidad]
--
-- Esos dos se vinculan. Los otros SIETE —Brian Alday, Danny Guerra, Joel Coo,
-- Jorge Castro, Marco Díaz, Yeran Sanhueza, Yusdel Sarduy— NO TIENEN CUENTA EN
-- EL SISTEMA. Crear cuentas necesita correo y clave de cada persona; no es algo
-- que se deduzca de una liquidación ni que deba inventar una migración.
--
-- Es el bloqueo real de la puesta en marcha de septiembre: sin cuenta, el
-- mecánico no ve su bono, y sin verlo no puede revisarlo, que es todo el punto.
--
-- OJO CON FELIPE LÓPEZ
-- Hay dos cuentas parecidas: «Felipe López» (auditor_calidad, Coquimbo) y
-- «Felipe López Franke» (operador_combustible, otra operación). Se vincula la
-- primera, que es la que calza con el técnico de Taller Coquimbo. Si en la
-- práctica resulta ser otra persona, se corrige con un UPDATE de una fila.
-- Recordar además que Felipe sigue SIN CARGO de bono (MIG453): su cartola va a
-- decir «falta el cargo del técnico» hasta que RRHH responda.
-- ============================================================================

BEGIN;

UPDATE taller_tecnicos t
   SET usuario_perfil_id = up.id, updated_at = NOW()
  FROM usuarios_perfil up
 WHERE t.nombre = 'Juan Valenzuela'
   AND up.nombre_completo = 'Juan Valenzuela'
   AND t.usuario_perfil_id IS NULL;

UPDATE taller_tecnicos t
   SET usuario_perfil_id = up.id, updated_at = NOW()
  FROM usuarios_perfil up
 WHERE t.nombre = 'Felipe López'
   AND up.nombre_completo = 'Felipe López'
   AND t.usuario_perfil_id IS NULL;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_con INT; v_sin INT; v_lista TEXT; v_dup INT;
BEGIN
    -- Una cuenta no puede ser dos técnicos: la cartola no sabría cuál devolver.
    SELECT count(*) INTO v_dup
      FROM (SELECT usuario_perfil_id FROM taller_tecnicos
             WHERE usuario_perfil_id IS NOT NULL AND COALESCE(activo, TRUE)
             GROUP BY usuario_perfil_id HAVING count(*) > 1) x;
    IF v_dup > 0 THEN
        RAISE EXCEPTION 'FALLO: % cuentas vinculadas a más de un técnico', v_dup;
    END IF;

    SELECT count(*) FILTER (WHERE usuario_perfil_id IS NOT NULL),
           count(*) FILTER (WHERE usuario_perfil_id IS NULL)
      INTO v_con, v_sin
      FROM taller_tecnicos WHERE COALESCE(activo, TRUE);

    RAISE NOTICE 'técnicos que ya pueden abrir su cartola: %', v_con;
    RAISE NOTICE 'técnicos que todavía NO tienen cuenta:   %', v_sin;

    SELECT string_agg(nombre, ', ' ORDER BY nombre) INTO v_lista
      FROM taller_tecnicos
     WHERE COALESCE(activo, TRUE) AND usuario_perfil_id IS NULL;
    IF v_lista IS NOT NULL THEN
        RAISE NOTICE 'hay que crearles cuenta a: %', v_lista;
    END IF;
END
$mig$;

COMMIT;
