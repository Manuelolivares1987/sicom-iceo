-- ============================================================================
-- SICOM-ICEO | 189 — Fase 0.1: cerrar escritura ANÓNIMA no validada
-- ----------------------------------------------------------------------------
-- La auditoría encontró funciones SECURITY DEFINER en public, ejecutables por
-- 'anon' (por el EXECUTE default de PUBLIC nunca revocado), que ESCRIBEN sin
-- validar sesión/rol. Verificado explotable, p.ej. rpc_cambiar_contrato_activo
-- (cambia el contrato de cualquier activo por su ID, sin login).
--
-- Estrategia SEGURA y quirúrgica (sin tocar la lógica de cada función):
--   REVOKE EXECUTE FROM anon, PUBLIC  +  GRANT EXECUTE TO authenticated.
-- Así 'anon' pierde el acceso y los flujos autenticados del frontend siguen
-- funcionando. Los jobs de pg_cron/triggers ejecutan como 'postgres' y NO se
-- ven afectados (no dependen del grant de anon).
--
-- Allowlist (siguen siendo anónimas, son escrituras públicas por QR;
-- su rate-limit es un pendiente P1 aparte):
--   rpc_guardar_checklist_publico, rpc_checklist_cliente_guardar
--
-- Esta migración NO reemplaza la validación por-función (defensa en profundidad),
-- que queda como endurecimiento posterior. Cierra la exposición anónima YA.
-- IDEMPOTENTE. Rollback: GRANT EXECUTE ... TO anon en las funciones listadas
-- (reabre el agujero; ver database/rollback/rollback_189_*.sql).
-- ============================================================================
SET client_min_messages = warning;

REVOKE EXECUTE ON FUNCTION public.calcular_iceo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.calcular_iceo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.calcular_todos_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.calcular_todos_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_auto_crear_planes_activo(p_activo_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_auto_crear_planes_activo(p_activo_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_calama_aplicar_avance_interno(p_ot_id uuid, p_avance_nuevo numeric, p_fuente text, p_motivo text, p_comentario text, p_uid uuid, p_ejecucion_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_calama_aplicar_avance_interno(p_ot_id uuid, p_avance_nuevo numeric, p_fuente text, p_motivo text, p_comentario text, p_uid uuid, p_ejecucion_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_calama_audit_jornada(p_payload jsonb) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_calama_audit_jornada(p_payload jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_consumir_inventario_fifo(p_producto_id uuid, p_bodega_id uuid, p_cantidad numeric, p_salida_bodega_id uuid, p_salida_bodega_item_id uuid, p_movimiento_id uuid, p_ot_id uuid, p_ceco_id uuid, p_consumido_por uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_consumir_inventario_fifo(p_producto_id uuid, p_bodega_id uuid, p_cantidad numeric, p_salida_bodega_id uuid, p_salida_bodega_item_id uuid, p_movimiento_id uuid, p_ot_id uuid, p_ceco_id uuid, p_consumido_por uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_evaluar_activos_fuera_geocerca() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_evaluar_activos_fuera_geocerca() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_generar_nc_desde_checklist_ot(p_ot_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_generar_nc_desde_checklist_ot(p_ot_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_generar_nc_desde_v3_ot(p_ot_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_generar_nc_desde_v3_ot(p_ot_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_gps_generar_alertas_sin_senal() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_gps_generar_alertas_sin_senal() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_guardar_reporte_diario(p_fecha date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_guardar_reporte_diario(p_fecha date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_inicializar_checklist_v2(p_template_id uuid, p_activo_id uuid, p_contrato_id uuid, p_operador_id uuid, p_horometro numeric, p_kilometraje numeric, p_informe_id uuid, p_entrega_ref uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_inicializar_checklist_v2(p_template_id uuid, p_activo_id uuid, p_contrato_id uuid, p_operador_id uuid, p_horometro numeric, p_kilometraje numeric, p_informe_id uuid, p_entrega_ref uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_mantenimiento_diario(p_umbral_mb numeric) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_mantenimiento_diario(p_umbral_mb numeric) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_qr_evaluar_alertas_calidad(p_respuesta_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_qr_evaluar_alertas_calidad(p_respuesta_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_plazos_diferidos(p_activo_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_recalcular_plazos_diferidos(p_activo_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_reconciliar_comercial_ficha_desde_matriz() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_reconciliar_comercial_ficha_desde_matriz() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_taller_log_jornada_evento(p_plan_ot_id uuid, p_tipo character varying, p_motivo text, p_dia_anterior date, p_dia_nuevo date, p_responsable_anterior uuid, p_responsable_nuevo uuid, p_cuadrilla_anterior character varying, p_cuadrilla_nueva character varying, p_campo character varying, p_valor_anterior text, p_valor_nuevo text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_taller_log_jornada_evento(p_plan_ot_id uuid, p_tipo character varying, p_motivo text, p_dia_anterior date, p_dia_nuevo date, p_responsable_anterior uuid, p_responsable_nuevo uuid, p_cuadrilla_anterior character varying, p_cuadrilla_nueva character varying, p_campo character varying, p_valor_anterior text, p_valor_nuevo text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.generar_ots_preventivas() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.generar_ots_preventivas() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_aplicar_diff_a_informe(p_recepcion_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_aplicar_diff_a_informe(p_recepcion_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_aprobar_conteo_inventario(p_conteo_id uuid, p_supervisor_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_aprobar_conteo_inventario(p_conteo_id uuid, p_supervisor_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_calcular_iceo_periodo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_calcular_iceo_periodo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_calcular_incentivos_periodo(p_contrato_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_calcular_incentivos_periodo(p_contrato_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_cerrar_checklist_v2(p_instance_id uuid, p_firma_operador_url text, p_firma_cliente_url text, p_operador_rut character varying, p_operador_nombre character varying, p_cliente_rut character varying, p_cliente_nombre character varying) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cerrar_checklist_v2(p_instance_id uuid, p_firma_operador_url text, p_firma_cliente_url text, p_operador_rut character varying, p_operador_nombre character varying, p_cliente_rut character varying, p_cliente_nombre character varying) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_cerrar_periodo_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo date, p_usuario_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cerrar_periodo_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo date, p_usuario_id uuid) TO authenticated;
-- (allowlist, se mantiene anon) rpc_checklist_cliente_guardar
REVOKE EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_generar_alerta_temprana(p_checklist_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_generar_alerta_temprana(p_checklist_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text) TO authenticated;
-- (allowlist, se mantiene anon) rpc_guardar_checklist_publico
REVOKE EXECUTE ON FUNCTION public.rpc_ingestar_gps_batch(p_proveedor_nombre text, p_eventos jsonb) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_ingestar_gps_batch(p_proveedor_nombre text, p_eventos jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_portal_marcar_acceso() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_portal_marcar_acceso() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_procesar_recalculos_iceo() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_procesar_recalculos_iceo() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_programar_ot_recepcion(p_activo_id uuid, p_prioridad prioridad_enum, p_fecha date, p_responsable_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_programar_ot_recepcion(p_activo_id uuid, p_prioridad prioridad_enum, p_fecha date, p_responsable_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_registrar_ajuste_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_motivo text, p_usuario_id uuid, p_ot_id uuid, p_autorizado_por uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_registrar_ajuste_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_motivo text, p_usuario_id uuid, p_ot_id uuid, p_autorizado_por uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_registrar_entrada_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_costo_unitario numeric, p_documento_referencia character varying, p_usuario_id uuid, p_lote character varying, p_fecha_vencimiento date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_registrar_entrada_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_costo_unitario numeric, p_documento_referencia character varying, p_usuario_id uuid, p_lote character varying, p_fecha_vencimiento date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_transferir_inventario(p_bodega_origen_id uuid, p_bodega_destino_id uuid, p_producto_id uuid, p_cantidad numeric, p_usuario_id uuid, p_motivo text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_transferir_inventario(p_bodega_origen_id uuid, p_bodega_destino_id uuid, p_producto_id uuid, p_cantidad numeric, p_usuario_id uuid, p_motivo text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.verificar_certificaciones() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.verificar_certificaciones() TO authenticated;

-- Verificación: 0 de las funciones cerradas debe quedar ejecutable por anon.
DO $$
DECLARE v_abiertas INT;
BEGIN
    SELECT count(*) INTO v_abiertas
      FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace AND nsp.nspname='public'
     WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
       AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
       AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
       AND p.proname NOT IN ('rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar');
    IF v_abiertas > 0 THEN
        RAISE EXCEPTION 'MIG189 incompleta: % funciones de escritura siguen anónimas', v_abiertas;
    END IF;
    RAISE NOTICE 'MIG189 OK: escritura anónima no validada cerrada (allowlist QR intacta).';
END $$;

SELECT '46 funciones cerradas a anon' AS resultado;
