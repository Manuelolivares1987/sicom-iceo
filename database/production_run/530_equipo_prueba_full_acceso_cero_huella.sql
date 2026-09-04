-- ============================================================================
-- MIG530 · El equipo de prueba: FULL acceso a los flujos, CERO huella real
-- ============================================================================
--
-- LO QUE ACLARÓ MANUEL (04-09-2026)
-- «Lo que quiero es una patente de prueba donde pueda aplicar TODO para ver
-- cómo resulta — QR, checklist cliente, diferentes OT, etc. — pero que no
-- toque nada.»
--
-- MIG529 lo dejó inocuo APAGÁNDOLE los flujos (QR off, sin contrato): eso
-- impedía probarlos. Se invierte el diseño: el equipo pasa por todo como uno
-- real, y son los CORREOS, PANELES AGREGADOS y REPORTES los que lo ignoran
-- por la marca es_prueba.
--
-- QUÉ SE HACE
--  1. Cliente y contrato DE PRUEBA + el activo queda arrendado con QR
--     encendido → puede probar: QR público (documentos, historial, checklist
--     del cliente), OTs de todo tipo (el contrato lo exige), portal cliente.
--  2. Correo de checklist-cliente pendiente: lo ignora (el PANEL sí lo
--     muestra — para eso está probando).
--  3. Correo de revisión técnica: lo ignora (por si le carga papeles).
--  4. Panel comercial de gerencia (fn_comercial_equipos): lo ignora.
--  5. Estados del planificador: PUEDE cargarlos para probar; una limpieza
--     nocturna (cron 03:30) borra los estados del equipo de prueba de días
--     anteriores — los históricos y reportes quedan intactos. El único
--     efecto posible es el decimal de disponibilidad DEL DÍA en que se está
--     probando, y desaparece solo.
--  (La cobertura de mantenimiento ya lo excluye desde MIG529.)
-- ============================================================================

BEGIN;

-- ── 1 · Cliente + contrato de prueba, activo con todo encendido ─────────────
DO $mig$
DECLARE v_contrato UUID; v_activo UUID;
BEGIN
    SELECT id INTO v_contrato FROM contratos WHERE codigo = 'CONTRATO-PRUEBA';
    IF v_contrato IS NULL THEN
        INSERT INTO contratos (codigo, nombre, cliente, descripcion, fecha_inicio, estado, moneda)
        VALUES ('CONTRATO-PRUEBA', 'Contrato de Prueba (laboratorio)', 'CLIENTE DE PRUEBA',
                'Contrato de laboratorio del equipo PRUEBA-01 (MIG530). No facturable; existe para probar flujos.',
                CURRENT_DATE, 'activo', 'CLP')
        RETURNING id INTO v_contrato;
        RAISE NOTICE 'contrato de prueba creado';
    END IF;

    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';
    IF v_activo IS NULL THEN RAISE EXCEPTION 'FALLO: no existe TEST-01 (MIG529)'; END IF;

    UPDATE activos
       SET qr_publico_habilitado = true,
           estado_comercial = 'arrendado',
           contrato_id = v_contrato,
           updated_at = NOW()
     WHERE id = v_activo;

    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name='activos' AND column_name='cliente_actual') THEN
        EXECUTE 'UPDATE activos SET cliente_actual = ''CLIENTE DE PRUEBA'' WHERE id = $1' USING v_activo;
    END IF;
    RAISE NOTICE 'PRUEBA-01: QR encendido, arrendado a CLIENTE DE PRUEBA';
END $mig$;

-- ── util de parche por línea ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION pg_temp.fn_parchar(p_fn TEXT, p_viejo TEXT, p_nuevo TEXT) RETURNS VOID AS $$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = p_fn;
    IF v_def IS NULL THEN RAISE EXCEPTION 'FALLO: % no existe', p_fn; END IF;
    IF position(p_nuevo IN v_def) > 0 THEN
        RAISE NOTICE '% ya estaba parchada', p_fn; RETURN;
    END IF;
    IF position(p_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré el anclaje en %', p_fn;
    END IF;
    IF position(p_viejo IN substring(v_def FROM position(p_viejo IN v_def) + length(p_viejo))) > 0 THEN
        RAISE EXCEPTION 'FALLO: anclaje repetido en %', p_fn;
    END IF;
    EXECUTE replace(v_def, p_viejo, p_nuevo);
    RAISE NOTICE '% parchada: es_prueba excluido', p_fn;
END $$ LANGUAGE plpgsql;

-- ── 2 · El correo de checklist-cliente lo ignora (el panel NO) ──────────────
SELECT pg_temp.fn_parchar('fn_checklist_cliente_pendientes_cron',
    'WHERE v.estado_cumplimiento <> ''al_dia''',
    'WHERE v.estado_cumplimiento <> ''al_dia''
       -- [MIG530] El equipo de laboratorio no genera correos.
       AND NOT EXISTS (SELECT 1 FROM activos ax WHERE ax.id = v.activo_id AND ax.es_prueba)');

-- ── 3 · El correo de revisión técnica lo ignora ─────────────────────────────
SELECT pg_temp.fn_parchar('fn_rt_por_vencer_cron',
    'JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL',
    'JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL AND NOT COALESCE(a.es_prueba, false)');

-- ── 4 · El panel comercial de gerencia lo ignora ────────────────────────────
SELECT pg_temp.fn_parchar('fn_comercial_equipos',
    'WHERE estado <> ''dado_baja''',
    'WHERE estado <> ''dado_baja'' AND NOT COALESCE(es_prueba, false)');

-- ── 5 · Limpieza nocturna de sus estados del planificador ───────────────────
CREATE OR REPLACE FUNCTION public.fn_limpiar_equipo_prueba()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n INT;
BEGIN
    -- Los estados diarios del equipo de laboratorio no sobreviven al día:
    -- así se puede probar el planificador sin que ningún histórico ni
    -- reporte quede tocado.
    DELETE FROM estado_diario_flota e
     USING activos a
     WHERE a.id = e.activo_id AND a.es_prueba AND e.fecha < CURRENT_DATE;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;

DO $cron$
BEGIN
    PERFORM cron.unschedule('limpieza-equipo-prueba')
     WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'limpieza-equipo-prueba');
    PERFORM cron.schedule('limpieza-equipo-prueba', '30 3 * * *',
                          'SELECT public.fn_limpiar_equipo_prueba()');
    RAISE NOTICE 'cron limpieza-equipo-prueba programado (03:30 diario)';
END $cron$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_activo UUID; v_n INT;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';

    -- Entra al universo del checklist del cliente (para poder probarlo)…
    SELECT count(*) INTO v_n FROM v_checklist_cliente_cumplimiento WHERE activo_id = v_activo;
    IF v_n = 0 THEN RAISE EXCEPTION 'FALLO: PRUEBA-01 no entró al universo del checklist cliente'; END IF;

    -- …y el QR público ya lo entrega.
    SELECT count(*) INTO v_n FROM rpc_historial_mantenimiento_publico(v_activo);
    RAISE NOTICE 'QR público de PRUEBA-01: % filas de historial (puede ser 0, recién nace)', v_n;

    -- Los tres parches quedaron escritos.
    IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('fn_checklist_cliente_pendientes_cron','fn_rt_por_vencer_cron','fn_comercial_equipos')
           AND p.prosrc LIKE '%es_prueba%') <> 3 THEN
        RAISE EXCEPTION 'FALLO: algún parche de exclusión no quedó escrito';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'limpieza-equipo-prueba') THEN
        RAISE EXCEPTION 'FALLO: el cron de limpieza no quedó programado';
    END IF;

    RAISE NOTICE 'MIG530 OK · PRUEBA-01 con full acceso y cero huella (correos, panel comercial y limpieza nocturna)';
END
$mig$;

COMMIT;
