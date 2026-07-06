-- ============================================================================
-- 191_informes_intervencion.sql  ·  Incremento 1 — Informe técnico de intervención
-- ----------------------------------------------------------------------------
-- Migración ADITIVA e IDEMPOTENTE. No modifica tablas de negocio existentes.
-- Crea el informe técnico como entidad nueva que CONSOLIDA y CONGELA snapshots
-- desde las fuentes oficiales (taller_ot_ejecuciones, inventario_consumos_capas,
-- checklist_v2_instance, no_conformidades) SIN duplicarlas ni recalcular FIFO ni
-- recalcular tiempos efectivos.
--
-- Alcance Incremento 1: informe + trabajos + materiales (entregado/consumido) +
-- mano de obra + pruebas + folio/versiones + RPCs + inmutabilidad + bitácora.
-- FUERA de alcance (NO implementado aquí): gate obligatorio de cierre de OT,
-- conciliación/devoluciones de materiales, cambios a informe de recobro,
-- facturación, QR B1, MIG188.
--
-- Permisos: módulo 'informes' vía fn_tiene_permiso_modulo (fail-closed). No se
-- modifica MIG185/189. El cierre de OT (rpc_cerrar_ot_supervisor) NO se toca.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1) CORRELATIVO DE FOLIO  (IT-YYYYMM-#####), seguro por advisory lock
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.informe_intervencion_correlativo (
    periodo   CHAR(6) PRIMARY KEY,       -- YYYYMM
    ultimo    INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.fn_next_folio_informe_intervencion()
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_periodo CHAR(6) := to_char(now(), 'YYYYMM');
    v_num     INTEGER;
BEGIN
    -- Lock por periodo: serializa la generación del correlativo sin MAX()+1 suelto.
    PERFORM pg_advisory_xact_lock(hashtext('folio_informe_intervencion:' || v_periodo));
    INSERT INTO public.informe_intervencion_correlativo(periodo, ultimo)
         VALUES (v_periodo, 1)
    ON CONFLICT (periodo) DO UPDATE
            SET ultimo = public.informe_intervencion_correlativo.ultimo + 1,
                updated_at = now()
      RETURNING ultimo INTO v_num;
    RETURN 'IT-' || v_periodo || '-' || lpad(v_num::text, 5, '0');
END;
$fn$;

-- ----------------------------------------------------------------------------
-- 2) TABLA CABECERA  informes_intervencion
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.informes_intervencion (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio                  VARCHAR NOT NULL UNIQUE,
    ot_id                  UUID NOT NULL REFERENCES public.ordenes_trabajo(id) ON DELETE RESTRICT,
    activo_id              UUID NOT NULL REFERENCES public.activos(id) ON DELETE RESTRICT,
    checklist_instance_id  UUID REFERENCES public.checklist_v2_instance(id) ON DELETE SET NULL,
    plan_semanal_id        UUID,
    version                INTEGER NOT NULL DEFAULT 1,
    informe_anterior_id    UUID REFERENCES public.informes_intervencion(id) ON DELETE SET NULL,
    es_version_vigente     BOOLEAN NOT NULL DEFAULT true,
    estado                 VARCHAR NOT NULL DEFAULT 'borrador',
    tipo_intervencion      VARCHAR,
    motivo_ingreso         TEXT,
    condicion_ingreso      TEXT,
    diagnostico_resumen        TEXT,
    trabajo_planificado_resumen TEXT,
    trabajo_realizado_resumen   TEXT,
    trabajos_pendientes_resumen TEXT,
    pruebas_resumen        TEXT,
    resultado_pruebas      VARCHAR,
    estado_salida          VARCHAR,
    restricciones_operacionales TEXT,
    recomendaciones        TEXT,
    kilometraje_ingreso    NUMERIC,
    kilometraje_salida     NUMERIC,
    horometro_ingreso      NUMERIC,
    horometro_salida       NUMERIC,
    fecha_ingreso          TIMESTAMPTZ,
    fecha_inicio           TIMESTAMPTZ,
    fecha_termino          TIMESTAMPTZ,
    ejecutor_principal_id  UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    elaborado_por          UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    revisado_por           UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    aprobado_por           UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    firma_ejecutor_url     TEXT,
    firma_jefe_url         TEXT,
    pdf_url                TEXT,
    pdf_sha256             TEXT,
    snapshot               JSONB,
    motivo_correccion      TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    aprobado_at            TIMESTAMPTZ,
    cerrado_at             TIMESTAMPTZ,
    anulado_at             TIMESTAMPTZ,
    -- Restricciones de negocio
    CONSTRAINT chk_ii_estado CHECK (estado IN ('borrador','pendiente_revision','observado','aprobado','cerrado','anulado')),
    CONSTRAINT chk_ii_version_pos CHECK (version > 0),
    CONSTRAINT chk_ii_anterior_si_v_gt1 CHECK (version = 1 OR informe_anterior_id IS NOT NULL),
    CONSTRAINT chk_ii_correccion_motivo CHECK (version = 1 OR motivo_correccion IS NOT NULL),
    CONSTRAINT chk_ii_segregacion CHECK (aprobado_por IS NULL OR ejecutor_principal_id IS NULL OR aprobado_por <> ejecutor_principal_id),
    CONSTRAINT uq_ii_ot_version UNIQUE (ot_id, version)
);

-- Una sola versión vigente por OT (índice parcial)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ii_ot_vigente
    ON public.informes_intervencion(ot_id) WHERE es_version_vigente;
CREATE INDEX IF NOT EXISTS idx_ii_activo   ON public.informes_intervencion(activo_id);
CREATE INDEX IF NOT EXISTS idx_ii_ot       ON public.informes_intervencion(ot_id);
CREATE INDEX IF NOT EXISTS idx_ii_estado   ON public.informes_intervencion(estado);

-- ----------------------------------------------------------------------------
-- 3) DETALLE DE TRABAJOS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.informe_intervencion_trabajos (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id         UUID NOT NULL REFERENCES public.informes_intervencion(id) ON DELETE CASCADE,
    checklist_item_id  UUID,     -- ref a checklist_v2_instance_item / checklist_ot (no FK dura: fuentes múltiples)
    nc_id              UUID REFERENCES public.no_conformidades(id) ON DELETE SET NULL,
    sistema            VARCHAR,
    componente         VARCHAR,
    sintoma            TEXT,
    diagnostico        TEXT,
    trabajo_planificado TEXT,
    trabajo_realizado  TEXT,
    estado             VARCHAR NOT NULL DEFAULT 'pendiente',
    resultado          VARCHAR,
    responsable_id     UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    fecha_inicio       TIMESTAMPTZ,
    fecha_termino      TIMESTAMPTZ,
    horas_hombre       NUMERIC,
    es_adicional       BOOLEAN NOT NULL DEFAULT false,
    motivo_adicional   TEXT,
    evidencia_antes_url   TEXT,
    evidencia_durante_url TEXT,
    evidencia_despues_url TEXT,
    observacion        TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_iit_estado CHECK (estado IN ('pendiente','en_ejecucion','realizado','realizado_parcial','no_realizado','no_aplica'))
);
CREATE INDEX IF NOT EXISTS idx_iit_informe ON public.informe_intervencion_trabajos(informe_id);

-- ----------------------------------------------------------------------------
-- 4) MATERIALES CONSOLIDADOS  (snapshot referencial; NO kardex paralelo)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.informe_intervencion_materiales (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id             UUID NOT NULL REFERENCES public.informes_intervencion(id) ON DELETE CASCADE,
    producto_id            UUID,
    nc_id                  UUID,
    bodega_ticket_id       UUID,
    bodega_ticket_item_id  UUID,
    salida_bodega_id       UUID,
    salida_bodega_item_id  UUID,
    movimiento_inventario_id UUID,
    -- Snapshots congelados
    producto_codigo        VARCHAR,
    producto_descripcion   TEXT,
    unidad                 VARCHAR,
    cantidad_entregada     NUMERIC,
    cantidad_consumida     NUMERIC,
    costo_unitario         NUMERIC,
    costo_total            NUMERIC,
    metodo_costeo          VARCHAR,          -- 'FIFO' (fuente: inventario_consumos_capas)
    capas_resumen          JSONB,            -- detalle de capas FIFO consolidadas
    fecha_movimiento       TIMESTAMPTZ,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_iim_informe ON public.informe_intervencion_materiales(informe_id);

-- ----------------------------------------------------------------------------
-- 5) MANO DE OBRA  (consume taller_ot_ejecuciones; NO recalcula tiempo efectivo)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.informe_intervencion_manoobra (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id               UUID NOT NULL REFERENCES public.informes_intervencion(id) ON DELETE CASCADE,
    ejecucion_id             UUID,            -- ref a taller_ot_ejecuciones(id)
    tecnico_id               UUID,
    tecnico_nombre_snapshot  VARCHAR,
    started_at               TIMESTAMPTZ,
    finished_at              TIMESTAMPTZ,
    tiempo_total_segundos    INTEGER,
    tiempo_pausado_segundos  INTEGER,
    tiempo_colacion_segundos INTEGER,
    tiempo_efectivo_segundos INTEGER,         -- copiado de taller_ot_ejecuciones (NO recalculado)
    costo_hora_snapshot      NUMERIC,
    costo_total_snapshot     NUMERIC,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_iimo_informe ON public.informe_intervencion_manoobra(informe_id);

-- ----------------------------------------------------------------------------
-- 6) PRUEBAS DE SALIDA  (registrables; NO bloquean cierre de OT en Inc.1)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.informe_intervencion_pruebas (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    informe_id     UUID NOT NULL REFERENCES public.informes_intervencion(id) ON DELETE CASCADE,
    tipo_prueba    VARCHAR NOT NULL,
    descripcion    TEXT,
    resultado      VARCHAR,          -- ok | no_ok | na
    valor_medido   NUMERIC,
    unidad         VARCHAR,
    rango_min      NUMERIC,
    rango_max      NUMERIC,
    responsable_id UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    evidencia_url  TEXT,
    observacion    TEXT,
    fecha_prueba   TIMESTAMPTZ DEFAULT now(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_iip_informe ON public.informe_intervencion_pruebas(informe_id);

-- ----------------------------------------------------------------------------
-- 7) INMUTABILIDAD + AUDITORÍA
-- ----------------------------------------------------------------------------
-- Trigger que rechaza modificaciones SUSTANTIVAS a informes aprobados/cerrados/
-- anulados. Solo permite cambios técnicos controlados (pdf, transición a cerrado,
-- marcación de versión sustituida, anulación). Las transiciones legítimas pasan
-- por RPCs SECURITY DEFINER.
CREATE OR REPLACE FUNCTION public.fn_ii_guard_inmutabilidad()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
BEGIN
    IF OLD.estado IN ('aprobado','cerrado','anulado') THEN
        -- Columnas cuyo cambio SÍ está permitido tras aprobar:
        IF ( NEW.pdf_url               IS DISTINCT FROM OLD.pdf_url
          OR NEW.pdf_sha256            IS DISTINCT FROM OLD.pdf_sha256
          OR NEW.estado               IS DISTINCT FROM OLD.estado
          OR NEW.es_version_vigente   IS DISTINCT FROM OLD.es_version_vigente
          OR NEW.updated_at           IS DISTINCT FROM OLD.updated_at
          OR NEW.cerrado_at           IS DISTINCT FROM OLD.cerrado_at
          OR NEW.anulado_at           IS DISTINCT FROM OLD.anulado_at )
        AND NOT (  -- ninguna columna sustantiva cambió
              NEW.folio IS DISTINCT FROM OLD.folio OR NEW.ot_id IS DISTINCT FROM OLD.ot_id
           OR NEW.activo_id IS DISTINCT FROM OLD.activo_id OR NEW.version IS DISTINCT FROM OLD.version
           OR NEW.motivo_ingreso IS DISTINCT FROM OLD.motivo_ingreso
           OR NEW.diagnostico_resumen IS DISTINCT FROM OLD.diagnostico_resumen
           OR NEW.trabajo_realizado_resumen IS DISTINCT FROM OLD.trabajo_realizado_resumen
           OR NEW.trabajos_pendientes_resumen IS DISTINCT FROM OLD.trabajos_pendientes_resumen
           OR NEW.estado_salida IS DISTINCT FROM OLD.estado_salida
           OR NEW.recomendaciones IS DISTINCT FROM OLD.recomendaciones
           OR NEW.ejecutor_principal_id IS DISTINCT FROM OLD.ejecutor_principal_id
           OR NEW.aprobado_por IS DISTINCT FROM OLD.aprobado_por
           OR NEW.snapshot IS DISTINCT FROM OLD.snapshot
        ) THEN
            -- Transición de estado válida solo aprobado->cerrado o *->anulado
            IF NEW.estado IS DISTINCT FROM OLD.estado
               AND NOT ( (OLD.estado='aprobado' AND NEW.estado='cerrado')
                      OR NEW.estado='anulado' ) THEN
                RAISE EXCEPTION 'Transición de estado no permitida sobre informe % (% -> %)', OLD.folio, OLD.estado, NEW.estado
                    USING ERRCODE='42501';
            END IF;
            -- Un informe anulado no puede volver a aprobarse
            IF OLD.estado='anulado' AND NEW.estado IN ('aprobado','cerrado') THEN
                RAISE EXCEPTION 'Informe anulado % no puede reactivarse', OLD.folio USING ERRCODE='42501';
            END IF;
            RETURN NEW;  -- cambio técnico permitido
        ELSE
            RAISE EXCEPTION 'Informe % está % y no admite cambios sustantivos directos (use nueva versión)', OLD.folio, OLD.estado
                USING ERRCODE='42501';
        END IF;
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_ii_inmutabilidad ON public.informes_intervencion;
CREATE TRIGGER trg_ii_inmutabilidad
    BEFORE UPDATE ON public.informes_intervencion
    FOR EACH ROW EXECUTE FUNCTION public.fn_ii_guard_inmutabilidad();

-- Auditoría a auditoria_eventos (tabla, registro_id, accion, datos_*, usuario_id)
CREATE OR REPLACE FUNCTION public.fn_ii_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
    INSERT INTO public.auditoria_eventos(tabla, registro_id, accion, datos_anteriores, datos_nuevos, usuario_id)
    VALUES ('informes_intervencion',
            COALESCE(NEW.id, OLD.id),
            TG_OP,
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
            auth.uid());
    RETURN COALESCE(NEW, OLD);
END;
$fn$;

DROP TRIGGER IF EXISTS trg_ii_auditoria ON public.informes_intervencion;
CREATE TRIGGER trg_ii_auditoria
    AFTER INSERT OR UPDATE OR DELETE ON public.informes_intervencion
    FOR EACH ROW EXECUTE FUNCTION public.fn_ii_auditoria();

-- ----------------------------------------------------------------------------
-- 8) RLS  (lectura interna; escritura solo vía RPCs SECURITY DEFINER)
-- ----------------------------------------------------------------------------
ALTER TABLE public.informes_intervencion            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.informe_intervencion_trabajos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.informe_intervencion_materiales  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.informe_intervencion_manoobra    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.informe_intervencion_pruebas     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.informe_intervencion_correlativo ENABLE ROW LEVEL SECURITY;

-- SELECT: usuario interno con permiso informes/view (fail-closed). Portal cliente,
-- perfil dual, anon y sin-perfil quedan denegados por el guard.
DROP POLICY IF EXISTS pol_ii_select ON public.informes_intervencion;
CREATE POLICY pol_ii_select ON public.informes_intervencion FOR SELECT TO authenticated
  USING (public.fn_tiene_permiso_modulo('informes','view',
         ARRAY['administrador','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento','supervisor','planificador','tecnico_mantenimiento','auditor_calidad','bodeguero']));

DROP POLICY IF EXISTS pol_iit_select ON public.informe_intervencion_trabajos;
CREATE POLICY pol_iit_select ON public.informe_intervencion_trabajos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.informes_intervencion i WHERE i.id = informe_id));
DROP POLICY IF EXISTS pol_iim_select ON public.informe_intervencion_materiales;
CREATE POLICY pol_iim_select ON public.informe_intervencion_materiales FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.informes_intervencion i WHERE i.id = informe_id));
DROP POLICY IF EXISTS pol_iimo_select ON public.informe_intervencion_manoobra;
CREATE POLICY pol_iimo_select ON public.informe_intervencion_manoobra FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.informes_intervencion i WHERE i.id = informe_id));
DROP POLICY IF EXISTS pol_iip_select ON public.informe_intervencion_pruebas;
CREATE POLICY pol_iip_select ON public.informe_intervencion_pruebas FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.informes_intervencion i WHERE i.id = informe_id));

-- (Sin políticas de INSERT/UPDATE/DELETE: escritura denegada para authenticated;
--  las RPCs SECURITY DEFINER son las únicas que escriben.)

-- ----------------------------------------------------------------------------
-- 9) HELPER de autorización interno
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ii_puede(p_accion TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT CASE p_accion
    WHEN 'view'    THEN public.fn_tiene_permiso_modulo('informes','view',
                        ARRAY['administrador','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento','supervisor','planificador','tecnico_mantenimiento','auditor_calidad','bodeguero'])
    WHEN 'edit'    THEN public.fn_tiene_permiso_modulo('informes','edit',
                        ARRAY['administrador','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento','supervisor','tecnico_mantenimiento'])
    WHEN 'approve' THEN public.fn_tiene_permiso_modulo('informes','approve',
                        ARRAY['administrador','subgerente_operaciones','jefe_mantenimiento'])
    WHEN 'delete'  THEN public.fn_tiene_permiso_modulo('informes','delete',
                        ARRAY['administrador','subgerente_operaciones'])
    ELSE false END;
$fn$;

-- ----------------------------------------------------------------------------
-- 10) RPC — CREAR desde OT (idempotente, precarga snapshots)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_crear_informe_intervencion_desde_ot(p_ot_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_id       UUID;
    v_ot       RECORD;
    v_ci       UUID;
    v_tarifa   NUMERIC;
BEGIN
    IF NOT public.fn_ii_puede('edit') THEN
        RAISE EXCEPTION 'No autorizado para crear informe técnico' USING ERRCODE='42501';
    END IF;
    -- Serializa por OT: evita duplicados por doble clic / concurrencia
    PERFORM pg_advisory_xact_lock(hashtext('informe_ot:' || p_ot_id::text));

    SELECT * INTO v_ot FROM public.ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT % no existe', p_ot_id USING ERRCODE='P0002';
    END IF;

    -- Idempotencia: si ya hay una versión vigente NO terminal, devolverla
    SELECT id INTO v_id FROM public.informes_intervencion
     WHERE ot_id = p_ot_id AND es_version_vigente
       AND estado IN ('borrador','pendiente_revision','observado','aprobado')
     LIMIT 1;
    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;

    SELECT id INTO v_ci FROM public.checklist_v2_instance
     WHERE ot_id = p_ot_id ORDER BY created_at DESC LIMIT 1;
    v_tarifa := COALESCE(v_ot.tarifa_hora, 0);

    INSERT INTO public.informes_intervencion(
        folio, ot_id, activo_id, checklist_instance_id, version, es_version_vigente,
        estado, tipo_intervencion, fecha_ingreso, fecha_inicio, fecha_termino,
        ejecutor_principal_id, elaborado_por)
    VALUES (
        public.fn_next_folio_informe_intervencion(), p_ot_id, v_ot.activo_id, v_ci, 1, true,
        'borrador', v_ot.tipo::text, v_ot.created_at, v_ot.fecha_inicio, v_ot.fecha_termino,
        v_ot.responsable_id, auth.uid())
    RETURNING id INTO v_id;

    -- Precarga TRABAJOS: ítems de la OT (checklist_ot) + NC + ítems V03 relevantes
    -- (no_ok / con observación). NO se copian los ítems 'ok' del checklist.
    INSERT INTO public.informe_intervencion_trabajos(informe_id, checklist_item_id, sistema, componente, trabajo_planificado, estado, observacion)
    SELECT v_id, co.id, co.seccion, NULL, co.descripcion, 'pendiente', co.observacion
      FROM public.checklist_ot co WHERE co.ot_id = p_ot_id;

    INSERT INTO public.informe_intervencion_trabajos(informe_id, nc_id, sistema, sintoma, diagnostico, estado, observacion)
    SELECT v_id, nc.id, nc.tipo::text, nc.descripcion, nc.accion_correctiva, 'pendiente', nc.descripcion
      FROM public.no_conformidades nc WHERE nc.ot_id = p_ot_id;

    INSERT INTO public.informe_intervencion_trabajos(informe_id, checklist_item_id, trabajo_planificado, resultado, estado, observacion)
    SELECT v_id, cii.id, cii.descripcion_custom, cii.resultado, 'pendiente', cii.observacion
      FROM public.checklist_v2_instance_item cii
     WHERE cii.instance_id = v_ci AND cii.resultado IS DISTINCT FROM 'ok' AND COALESCE(cii.excluido,false) = false;

    -- Precarga MANO DE OBRA desde taller_ot_ejecuciones (tiempo efectivo NO recalculado)
    INSERT INTO public.informe_intervencion_manoobra(
        informe_id, ejecucion_id, tecnico_id, tecnico_nombre_snapshot, started_at, finished_at,
        tiempo_total_segundos, tiempo_pausado_segundos, tiempo_colacion_segundos, tiempo_efectivo_segundos,
        costo_hora_snapshot, costo_total_snapshot)
    SELECT v_id, e.id, e.ejecutor_id, up.nombre_completo, e.started_at, e.finished_at,
           e.tiempo_total_segundos, e.tiempo_pausado_segundos, e.tiempo_colacion_segundos, e.tiempo_efectivo_segundos,
           v_tarifa, ROUND(v_tarifa * COALESCE(e.tiempo_efectivo_segundos,0) / 3600.0)
      FROM public.taller_ot_ejecuciones e
      LEFT JOIN public.usuarios_perfil up ON up.id = e.ejecutor_id
     WHERE e.ot_id = p_ot_id;

    -- Precarga MATERIALES consolidando inventario_consumos_capas (FIFO) por producto,
    -- conservando el detalle de capas en el snapshot. NO se recalcula FIFO.
    INSERT INTO public.informe_intervencion_materiales(
        informe_id, producto_id, metodo_costeo, cantidad_consumida, costo_total, costo_unitario,
        capas_resumen, fecha_movimiento)
    SELECT v_id, c.producto_id, 'FIFO',
           SUM(c.cantidad_consumida),
           SUM(c.costo_total_consumido),
           CASE WHEN SUM(c.cantidad_consumida) > 0 THEN SUM(c.costo_total_consumido)/SUM(c.cantidad_consumida) END,
           jsonb_agg(jsonb_build_object('capa_id', c.capa_id, 'cantidad', c.cantidad_consumida,
                     'costo_unitario_capa', c.costo_unitario_capa, 'costo_total', c.costo_total_consumido)
                     ORDER BY c.fecha_consumo),
           MAX(c.fecha_consumo)
      FROM public.inventario_consumos_capas c
     WHERE c.ot_id = p_ot_id
     GROUP BY c.producto_id;

    -- Completa código/descripcion/unidad del producto (snapshot) si existe catálogo
    UPDATE public.informe_intervencion_materiales m
       SET producto_codigo = p.codigo, producto_descripcion = p.nombre, unidad = p.unidad_medida
      FROM public.productos p
     WHERE m.informe_id = v_id AND m.producto_id = p.id;

    RETURN v_id;
END;
$fn$;

-- ----------------------------------------------------------------------------
-- 11) RPC — ACTUALIZAR BORRADOR (ownership: técnico solo el propio; jefe/admin todo)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_actualizar_borrador_informe(p_informe_id UUID, p_campos JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('edit') THEN
        RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id = p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe % no existe', p_informe_id USING ERRCODE='P0002'; END IF;
    IF v_row.estado NOT IN ('borrador','observado') THEN
        RAISE EXCEPTION 'Solo editable en borrador/observado (estado actual %)', v_row.estado USING ERRCODE='42501';
    END IF;
    -- Ownership: si no es aprobador (jefe/admin), solo el creador puede editar
    IF NOT public.fn_ii_puede('approve') AND v_row.elaborado_por IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Solo el creador puede editar este borrador' USING ERRCODE='42501';
    END IF;
    UPDATE public.informes_intervencion SET
        tipo_intervencion      = COALESCE(p_campos->>'tipo_intervencion', tipo_intervencion),
        motivo_ingreso         = COALESCE(p_campos->>'motivo_ingreso', motivo_ingreso),
        condicion_ingreso      = COALESCE(p_campos->>'condicion_ingreso', condicion_ingreso),
        diagnostico_resumen    = COALESCE(p_campos->>'diagnostico_resumen', diagnostico_resumen),
        trabajo_planificado_resumen = COALESCE(p_campos->>'trabajo_planificado_resumen', trabajo_planificado_resumen),
        trabajo_realizado_resumen   = COALESCE(p_campos->>'trabajo_realizado_resumen', trabajo_realizado_resumen),
        trabajos_pendientes_resumen = COALESCE(p_campos->>'trabajos_pendientes_resumen', trabajos_pendientes_resumen),
        pruebas_resumen        = COALESCE(p_campos->>'pruebas_resumen', pruebas_resumen),
        resultado_pruebas      = COALESCE(p_campos->>'resultado_pruebas', resultado_pruebas),
        estado_salida          = COALESCE(p_campos->>'estado_salida', estado_salida),
        restricciones_operacionales = COALESCE(p_campos->>'restricciones_operacionales', restricciones_operacionales),
        recomendaciones        = COALESCE(p_campos->>'recomendaciones', recomendaciones),
        kilometraje_ingreso    = COALESCE((p_campos->>'kilometraje_ingreso')::numeric, kilometraje_ingreso),
        kilometraje_salida     = COALESCE((p_campos->>'kilometraje_salida')::numeric, kilometraje_salida),
        horometro_ingreso      = COALESCE((p_campos->>'horometro_ingreso')::numeric, horometro_ingreso),
        horometro_salida       = COALESCE((p_campos->>'horometro_salida')::numeric, horometro_salida),
        firma_ejecutor_url     = COALESCE(p_campos->>'firma_ejecutor_url', firma_ejecutor_url)
    WHERE id = p_informe_id;
END;
$fn$;

-- ----------------------------------------------------------------------------
-- 12) RPCs de transición de estado
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_enviar_informe_revision(p_informe_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('edit') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado NOT IN ('borrador','observado') THEN RAISE EXCEPTION 'Estado % no permite envío a revisión', v_row.estado USING ERRCODE='42501'; END IF;
    UPDATE public.informes_intervencion SET estado='pendiente_revision', updated_at=now() WHERE id=p_informe_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.rpc_observar_informe(p_informe_id UUID, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('approve') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado <> 'pendiente_revision' THEN RAISE EXCEPTION 'Solo observable en pendiente_revision' USING ERRCODE='42501'; END IF;
    UPDATE public.informes_intervencion
       SET estado='observado', revisado_por=auth.uid(), motivo_correccion=COALESCE(p_motivo,motivo_correccion), updated_at=now()
     WHERE id=p_informe_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.rpc_aprobar_informe_intervencion(p_informe_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion; v_snap JSONB;
BEGIN
    IF NOT public.fn_ii_puede('approve') THEN RAISE EXCEPTION 'No autorizado para aprobar' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado <> 'pendiente_revision' THEN RAISE EXCEPTION 'Solo aprobable en pendiente_revision (estado %)', v_row.estado USING ERRCODE='42501'; END IF;
    -- Segregación: el aprobador no puede ser el ejecutor principal ni el creador
    IF auth.uid() = v_row.ejecutor_principal_id OR auth.uid() = v_row.elaborado_por THEN
        RAISE EXCEPTION 'El aprobador no puede ser el ejecutor/creador del informe' USING ERRCODE='42501';
    END IF;
    -- Campos mínimos
    IF COALESCE(v_row.trabajo_realizado_resumen,'')='' OR COALESCE(v_row.estado_salida,'')='' THEN
        RAISE EXCEPTION 'Faltan campos mínimos (trabajo_realizado_resumen, estado_salida)' USING ERRCODE='P0001';
    END IF;
    -- Congela snapshot desde fuentes oficiales (equipo, contrato, lecturas, costos, responsables)
    SELECT jsonb_build_object(
        'congelado_at', now(),
        'activo', (SELECT to_jsonb(a) FROM public.activos a WHERE a.id=v_row.activo_id),
        'ot', (SELECT jsonb_build_object('folio',o.folio,'tipo',o.tipo,'estado',o.estado,'contrato_id',o.contrato_id) FROM public.ordenes_trabajo o WHERE o.id=v_row.ot_id),
        'materiales_total', (SELECT COALESCE(SUM(costo_total),0) FROM public.informe_intervencion_materiales WHERE informe_id=p_informe_id),
        'manoobra_total', (SELECT COALESCE(SUM(costo_total_snapshot),0) FROM public.informe_intervencion_manoobra WHERE informe_id=p_informe_id),
        'trabajos', (SELECT jsonb_agg(to_jsonb(t)) FROM public.informe_intervencion_trabajos t WHERE t.informe_id=p_informe_id),
        'pruebas', (SELECT jsonb_agg(to_jsonb(pr)) FROM public.informe_intervencion_pruebas pr WHERE pr.informe_id=p_informe_id)
    ) INTO v_snap;
    UPDATE public.informes_intervencion
       SET estado='aprobado', aprobado_por=auth.uid(), aprobado_at=now(), snapshot=v_snap, updated_at=now()
     WHERE id=p_informe_id;
END; $fn$;

-- PDF: permitido tras aprobar (cambio técnico controlado)
CREATE OR REPLACE FUNCTION public.rpc_registrar_pdf_informe(p_informe_id UUID, p_pdf_url TEXT, p_sha256 TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('approve') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado NOT IN ('aprobado','cerrado') THEN RAISE EXCEPTION 'PDF solo tras aprobar' USING ERRCODE='42501'; END IF;
    UPDATE public.informes_intervencion SET pdf_url=p_pdf_url, pdf_sha256=p_sha256, updated_at=now() WHERE id=p_informe_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.rpc_cerrar_informe_intervencion(p_informe_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('approve') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado <> 'aprobado' THEN RAISE EXCEPTION 'Solo cerrable en aprobado' USING ERRCODE='42501'; END IF;
    IF COALESCE(v_row.pdf_url,'')='' THEN RAISE EXCEPTION 'PDF obligatorio antes de cerrar' USING ERRCODE='P0001'; END IF;
    UPDATE public.informes_intervencion SET estado='cerrado', cerrado_at=now(), updated_at=now() WHERE id=p_informe_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.rpc_anular_informe_intervencion(p_informe_id UUID, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('delete') THEN RAISE EXCEPTION 'No autorizado para anular' USING ERRCODE='42501'; END IF;
    IF COALESCE(p_motivo,'')='' THEN RAISE EXCEPTION 'Motivo de anulación obligatorio' USING ERRCODE='P0001'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado='anulado' THEN RAISE EXCEPTION 'Ya anulado' USING ERRCODE='P0001'; END IF;
    UPDATE public.informes_intervencion
       SET estado='anulado', anulado_at=now(), es_version_vigente=false,
           motivo_correccion=COALESCE(motivo_correccion,'') || ' [ANULADO: ' || p_motivo || ']', updated_at=now()
     WHERE id=p_informe_id;
    -- Si se anula una corrección, la versión anterior no anulada vuelve a ser vigente
    -- (evita que la OT quede sin informe efectivo en la bitácora).
    IF v_row.informe_anterior_id IS NOT NULL THEN
        UPDATE public.informes_intervencion
           SET es_version_vigente = true, updated_at = now()
         WHERE id = v_row.informe_anterior_id AND estado <> 'anulado';
    END IF;
END; $fn$;

-- Nueva versión (corrección sustantiva): clona, versión+1, anterior no vigente, motivo obligatorio
CREATE OR REPLACE FUNCTION public.rpc_crear_nueva_version_informe(p_informe_id UUID, p_motivo TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_old public.informes_intervencion; v_new UUID;
BEGIN
    IF NOT public.fn_ii_puede('edit') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
    IF COALESCE(p_motivo,'')='' THEN RAISE EXCEPTION 'Motivo de corrección obligatorio' USING ERRCODE='P0001'; END IF;
    SELECT * INTO v_old FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF NOT v_old.es_version_vigente THEN RAISE EXCEPTION 'Solo se versiona la vigente' USING ERRCODE='42501'; END IF;
    IF v_old.estado = 'anulado' THEN RAISE EXCEPTION 'No se versiona un informe anulado' USING ERRCODE='42501'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('informe_ot:' || v_old.ot_id::text));
    -- Marca la anterior como NO vigente (permitido por el guard de inmutabilidad)
    UPDATE public.informes_intervencion SET es_version_vigente=false, updated_at=now() WHERE id=p_informe_id;

    INSERT INTO public.informes_intervencion(
        folio, ot_id, activo_id, checklist_instance_id, plan_semanal_id, version, informe_anterior_id,
        es_version_vigente, estado, tipo_intervencion, motivo_ingreso, condicion_ingreso, diagnostico_resumen,
        trabajo_planificado_resumen, trabajo_realizado_resumen, trabajos_pendientes_resumen, pruebas_resumen,
        resultado_pruebas, estado_salida, restricciones_operacionales, recomendaciones,
        kilometraje_ingreso, kilometraje_salida, horometro_ingreso, horometro_salida,
        fecha_ingreso, fecha_inicio, fecha_termino, ejecutor_principal_id, elaborado_por, motivo_correccion)
    SELECT v_old.folio || '-v' || (v_old.version+1), v_old.ot_id, v_old.activo_id, v_old.checklist_instance_id,
           v_old.plan_semanal_id, v_old.version+1, v_old.id, true, 'borrador', v_old.tipo_intervencion,
           v_old.motivo_ingreso, v_old.condicion_ingreso, v_old.diagnostico_resumen,
           v_old.trabajo_planificado_resumen, v_old.trabajo_realizado_resumen, v_old.trabajos_pendientes_resumen,
           v_old.pruebas_resumen, v_old.resultado_pruebas, v_old.estado_salida, v_old.restricciones_operacionales,
           v_old.recomendaciones, v_old.kilometraje_ingreso, v_old.kilometraje_salida, v_old.horometro_ingreso,
           v_old.horometro_salida, v_old.fecha_ingreso, v_old.fecha_inicio, v_old.fecha_termino,
           v_old.ejecutor_principal_id, auth.uid(), p_motivo
    RETURNING id INTO v_new;

    -- Copia los detalles a la nueva versión
    INSERT INTO public.informe_intervencion_trabajos(informe_id, checklist_item_id, nc_id, sistema, componente, sintoma, diagnostico, trabajo_planificado, trabajo_realizado, estado, resultado, responsable_id, fecha_inicio, fecha_termino, horas_hombre, es_adicional, motivo_adicional, evidencia_antes_url, evidencia_durante_url, evidencia_despues_url, observacion)
    SELECT v_new, checklist_item_id, nc_id, sistema, componente, sintoma, diagnostico, trabajo_planificado, trabajo_realizado, estado, resultado, responsable_id, fecha_inicio, fecha_termino, horas_hombre, es_adicional, motivo_adicional, evidencia_antes_url, evidencia_durante_url, evidencia_despues_url, observacion
      FROM public.informe_intervencion_trabajos WHERE informe_id=p_informe_id;
    INSERT INTO public.informe_intervencion_materiales(informe_id, producto_id, nc_id, bodega_ticket_id, bodega_ticket_item_id, salida_bodega_id, salida_bodega_item_id, movimiento_inventario_id, producto_codigo, producto_descripcion, unidad, cantidad_entregada, cantidad_consumida, costo_unitario, costo_total, metodo_costeo, capas_resumen, fecha_movimiento)
    SELECT v_new, producto_id, nc_id, bodega_ticket_id, bodega_ticket_item_id, salida_bodega_id, salida_bodega_item_id, movimiento_inventario_id, producto_codigo, producto_descripcion, unidad, cantidad_entregada, cantidad_consumida, costo_unitario, costo_total, metodo_costeo, capas_resumen, fecha_movimiento
      FROM public.informe_intervencion_materiales WHERE informe_id=p_informe_id;
    INSERT INTO public.informe_intervencion_manoobra(informe_id, ejecucion_id, tecnico_id, tecnico_nombre_snapshot, started_at, finished_at, tiempo_total_segundos, tiempo_pausado_segundos, tiempo_colacion_segundos, tiempo_efectivo_segundos, costo_hora_snapshot, costo_total_snapshot)
    SELECT v_new, ejecucion_id, tecnico_id, tecnico_nombre_snapshot, started_at, finished_at, tiempo_total_segundos, tiempo_pausado_segundos, tiempo_colacion_segundos, tiempo_efectivo_segundos, costo_hora_snapshot, costo_total_snapshot
      FROM public.informe_intervencion_manoobra WHERE informe_id=p_informe_id;
    INSERT INTO public.informe_intervencion_pruebas(informe_id, tipo_prueba, descripcion, resultado, valor_medido, unidad, rango_min, rango_max, responsable_id, evidencia_url, observacion, fecha_prueba)
    SELECT v_new, tipo_prueba, descripcion, resultado, valor_medido, unidad, rango_min, rango_max, responsable_id, evidencia_url, observacion, fecha_prueba
      FROM public.informe_intervencion_pruebas WHERE informe_id=p_informe_id;

    RETURN v_new;
END; $fn$;

-- ----------------------------------------------------------------------------
-- 13) BITÁCORA — extiende v_bitacora_equipo con 'informe_tecnico' (7ª fuente)
--     Se conservan intactas las 6 fuentes existentes (riesgo cero de regresión).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_bitacora_equipo AS
 SELECT o.activo_id, 'ot'::text AS tipo_registro, o.id AS ref_id,
        COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio, o.fecha_programada::timestamptz, o.created_at) AS fecha,
        o.folio AS titulo, (o.tipo::text || ' · '::text) || o.estado::text AS subtitulo,
        NULLIF(o.observaciones, ''::text) AS detalle, o.costo_total AS costo, up.nombre_completo AS responsable
   FROM ordenes_trabajo o LEFT JOIN usuarios_perfil up ON up.id = o.responsable_id
 UNION ALL
 SELECT h.activo_id, 'os_legacy'::text, h.id, h.fecha_recepcion::timestamptz,
        'OS '::text || COALESCE(h.os_cqbo, h.os_numero, h.id::text::varchar)::text AS titulo,
        CASE WHEN h.flag_correctivo THEN 'correctivo '::text WHEN h.flag_mant_prev THEN 'preventivo '::text ELSE ''::text END
        || COALESCE('· '::text || h.faena::text, ''::text),
        ((COALESCE(('Cliente '::text || h.cliente::text) || '. '::text, ''::text) || COALESCE(('Horómetro '::text || h.horometro) || '. '::text, ''::text)) || COALESCE(h.num_trabajos::text || ' trabajos. '::text, ''::text)) || COALESCE(('Cumpl. '::text || h.cumplimiento_pct) || '%'::text, ''::text),
        NULL::numeric, h.responsable
   FROM historial_os_legacy h WHERE h.activo_id IS NOT NULL
 UNION ALL
 SELECT ac.activo_id, 'auditoria'::text, ac.id, COALESCE(ac.fecha_auditoria, ac.created_at),
        'Auditoría de calidad'::varchar, ac.resultado::text, NULLIF(COALESCE(ac.motivo_rechazo, ac.observaciones), ''::text), NULL::numeric, NULL::text
   FROM auditorias_calidad ac
 UNION ALL
 SELECT ir.activo_id, 'recepcion'::text, ir.id, COALESCE(ir.fecha_recepcion::timestamptz, ir.created_at),
        'Recepción '::text || COALESCE(ir.folio, ''::varchar)::text, ir.estado::text, NULLIF(ir.cliente_nombre::text, ''::text), ir.total, NULL::text
   FROM informes_recepcion ir
 UNION ALL
 SELECT d.activo_id, 'diferido'::text, d.id, d.fecha_diferimiento,
        'Pendiente: '::text || d.descripcion, (d.estado::text || ' · '::text) || d.severidad::text,
        CASE WHEN d.diferible THEN ((('Plazo '::text || COALESCE(d.plazo_fecha_limite::text, 's/d'::text)) || ' ('::text) || COALESCE(d.plazo_origen, 's/d'::varchar)::text) || ')'::text ELSE 'No diferible (bloquea operativo)'::text END,
        NULL::numeric, NULL::text
   FROM items_diferidos d
 UNION ALL
 SELECT cc.activo_id, 'checklist_cliente'::text, cc.id, cc.fecha::timestamptz,
        'Checklist del cliente'::varchar,
        CASE WHEN cc.tiene_novedad THEN cc.items_no_ok::text || ' novedad(es)'::text ELSE 'sin novedad'::text END,
        NULLIF(COALESCE('Operador '::text || cc.operador_nombre::text, cc.observaciones), ''::text), NULL::numeric, cc.operador_nombre
   FROM checklist_cliente_semanal cc
 UNION ALL
 -- 7ª fuente: informe técnico de intervención (solo versión vigente; detalle on-demand por ref_id)
 SELECT ii.activo_id, 'informe_tecnico'::text, ii.id,
        COALESCE(ii.cerrado_at, ii.aprobado_at, ii.created_at) AS fecha,
        ('Informe técnico '::text || ii.folio) || ' v'::text || ii.version::text AS titulo,
        (ii.estado::text || COALESCE(' · '::text || ii.estado_salida, ''::text)) AS subtitulo,
        NULLIF(ii.trabajo_realizado_resumen, ''::text) AS detalle,
        ( (SELECT COALESCE(SUM(costo_total),0) FROM informe_intervencion_materiales m WHERE m.informe_id=ii.id)
        + (SELECT COALESCE(SUM(costo_total_snapshot),0) FROM informe_intervencion_manoobra mo WHERE mo.informe_id=ii.id) ) AS costo,
        upe.nombre_completo AS responsable
   FROM informes_intervencion ii
   LEFT JOIN usuarios_perfil upe ON upe.id = ii.ejecutor_principal_id
  WHERE ii.es_version_vigente AND ii.estado <> 'anulado';

-- ----------------------------------------------------------------------------
-- 14) STORAGE — bucket PRIVADO informes-tecnicos + policies (sin acceso público)
-- ----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('informes-tecnicos', 'informes-tecnicos', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "ii_storage_read" ON storage.objects;
CREATE POLICY "ii_storage_read" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'informes-tecnicos'
         AND public.fn_tiene_permiso_modulo('informes','view',
             ARRAY['administrador','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento','supervisor','planificador','tecnico_mantenimiento','auditor_calidad','bodeguero']));
DROP POLICY IF EXISTS "ii_storage_write" ON storage.objects;
CREATE POLICY "ii_storage_write" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'informes-tecnicos'
         AND public.fn_tiene_permiso_modulo('informes','approve',
             ARRAY['administrador','subgerente_operaciones','jefe_mantenimiento']));

-- ----------------------------------------------------------------------------
-- 15) GRANTS mínimos
-- ----------------------------------------------------------------------------
GRANT SELECT ON public.informes_intervencion, public.informe_intervencion_trabajos,
                public.informe_intervencion_materiales, public.informe_intervencion_manoobra,
                public.informe_intervencion_pruebas TO authenticated;
GRANT SELECT ON public.v_bitacora_equipo TO authenticated;
REVOKE ALL ON public.informe_intervencion_correlativo FROM anon, authenticated;

DO $g$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT unnest(ARRAY[
    'rpc_crear_informe_intervencion_desde_ot(uuid)','rpc_actualizar_borrador_informe(uuid,jsonb)',
    'rpc_enviar_informe_revision(uuid)','rpc_observar_informe(uuid,text)',
    'rpc_aprobar_informe_intervencion(uuid)','rpc_registrar_pdf_informe(uuid,text,text)',
    'rpc_cerrar_informe_intervencion(uuid)','rpc_anular_informe_intervencion(uuid,text)',
    'rpc_crear_nueva_version_informe(uuid,text)']) AS sig
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', r.sig);
  END LOOP;
END $g$;

-- ----------------------------------------------------------------------------
-- 16) POSTVALIDACIÓN
-- ----------------------------------------------------------------------------
DO $post$
DECLARE v_tablas INT; v_rpcs INT; v_rls INT;
BEGIN
  SELECT count(*) INTO v_tablas FROM pg_tables WHERE schemaname='public'
    AND tablename IN ('informes_intervencion','informe_intervencion_trabajos','informe_intervencion_materiales','informe_intervencion_manoobra','informe_intervencion_pruebas');
  IF v_tablas <> 5 THEN RAISE EXCEPTION 'POSTVAL: faltan tablas (%/5)', v_tablas; END IF;

  SELECT count(*) INTO v_rpcs FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
   WHERE p.proname IN ('rpc_crear_informe_intervencion_desde_ot','rpc_actualizar_borrador_informe','rpc_enviar_informe_revision','rpc_observar_informe','rpc_aprobar_informe_intervencion','rpc_registrar_pdf_informe','rpc_cerrar_informe_intervencion','rpc_anular_informe_intervencion','rpc_crear_nueva_version_informe');
  IF v_rpcs <> 9 THEN RAISE EXCEPTION 'POSTVAL: faltan RPCs (%/9)', v_rpcs; END IF;

  SELECT count(*) INTO v_rls FROM pg_class WHERE relname IN ('informes_intervencion','informe_intervencion_trabajos','informe_intervencion_materiales','informe_intervencion_manoobra','informe_intervencion_pruebas') AND relrowsecurity;
  IF v_rls <> 5 THEN RAISE EXCEPTION 'POSTVAL: RLS no activa en las 5 tablas (%/5)', v_rls; END IF;

  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id='informes-tecnicos' AND public=false) THEN
    RAISE EXCEPTION 'POSTVAL: bucket informes-tecnicos no es privado';
  END IF;
  RAISE NOTICE 'POSTVAL OK: 5 tablas, 9 RPCs, RLS activa, bucket privado, vista extendida.';
END $post$;

COMMIT;

-- ============================================================================
-- ROLLBACK DE DESARROLLO (NO ejecutar en producción):
-- ----------------------------------------------------------------------------
-- BEGIN;
--   DROP VIEW IF EXISTS public.v_bitacora_equipo;   -- recrear desde 128 tras drop
--   DROP FUNCTION IF EXISTS public.rpc_crear_informe_intervencion_desde_ot(uuid),
--     public.rpc_actualizar_borrador_informe(uuid,jsonb), public.rpc_enviar_informe_revision(uuid),
--     public.rpc_observar_informe(uuid,text), public.rpc_aprobar_informe_intervencion(uuid),
--     public.rpc_registrar_pdf_informe(uuid,text,text), public.rpc_cerrar_informe_intervencion(uuid),
--     public.rpc_anular_informe_intervencion(uuid,text), public.rpc_crear_nueva_version_informe(uuid,text),
--     public.fn_ii_puede(text), public.fn_next_folio_informe_intervencion(),
--     public.fn_ii_guard_inmutabilidad(), public.fn_ii_auditoria() CASCADE;
--   DROP TABLE IF EXISTS public.informe_intervencion_pruebas, public.informe_intervencion_manoobra,
--     public.informe_intervencion_materiales, public.informe_intervencion_trabajos,
--     public.informes_intervencion, public.informe_intervencion_correlativo CASCADE;
--   DELETE FROM storage.buckets WHERE id='informes-tecnicos';
-- COMMIT;
-- ============================================================================
