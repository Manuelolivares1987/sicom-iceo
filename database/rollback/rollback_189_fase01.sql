-- ============================================================================
-- ROLLBACK MIG189 — rollback técnico de EMERGENCIA
-- ⚠️ REABRE la escritura ANÓNIMA no validada (incl. P0 como rpc_cambiar_contrato_activo).
--    Usar solo si un flujo legítimo quedó roto y no se resuelve con GRANT a authenticated.
-- ============================================================================
BEGIN;
GRANT EXECUTE ON FUNCTION public.calcular_iceo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO anon;
GRANT EXECUTE ON FUNCTION public.calcular_todos_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_auto_crear_planes_activo(p_activo_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_calama_aplicar_avance_interno(p_ot_id uuid, p_avance_nuevo numeric, p_fuente text, p_motivo text, p_comentario text, p_uid uuid, p_ejecucion_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_calama_audit_jornada(p_payload jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_consumir_inventario_fifo(p_producto_id uuid, p_bodega_id uuid, p_cantidad numeric, p_salida_bodega_id uuid, p_salida_bodega_item_id uuid, p_movimiento_id uuid, p_ot_id uuid, p_ceco_id uuid, p_consumido_por uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_evaluar_activos_fuera_geocerca() TO anon;
GRANT EXECUTE ON FUNCTION public.fn_generar_nc_desde_checklist_ot(p_ot_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_generar_nc_desde_v3_ot(p_ot_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_gps_generar_alertas_sin_senal() TO anon;
GRANT EXECUTE ON FUNCTION public.fn_guardar_reporte_diario(p_fecha date) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_inicializar_checklist_v2(p_template_id uuid, p_activo_id uuid, p_contrato_id uuid, p_operador_id uuid, p_horometro numeric, p_kilometraje numeric, p_informe_id uuid, p_entrega_ref uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_mantenimiento_diario(p_umbral_mb numeric) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_qr_evaluar_alertas_calidad(p_respuesta_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_recalcular_plazos_diferidos(p_activo_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_reconciliar_comercial_ficha_desde_matriz() TO anon;
GRANT EXECUTE ON FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz() TO anon;
GRANT EXECUTE ON FUNCTION public.fn_taller_log_jornada_evento(p_plan_ot_id uuid, p_tipo character varying, p_motivo text, p_dia_anterior date, p_dia_nuevo date, p_responsable_anterior uuid, p_responsable_nuevo uuid, p_cuadrilla_anterior character varying, p_cuadrilla_nueva character varying, p_campo character varying, p_valor_anterior text, p_valor_nuevo text) TO anon;
GRANT EXECUTE ON FUNCTION public.generar_ots_preventivas() TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_aplicar_diff_a_informe(p_recepcion_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_aprobar_conteo_inventario(p_conteo_id uuid, p_supervisor_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_calcular_iceo_periodo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_calcular_incentivos_periodo(p_contrato_id uuid, p_periodo_inicio date, p_periodo_fin date) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_cerrar_checklist_v2(p_instance_id uuid, p_firma_operador_url text, p_firma_cliente_url text, p_operador_rut character varying, p_operador_nombre character varying, p_cliente_rut character varying, p_cliente_nombre character varying) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_cerrar_periodo_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo date, p_usuario_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_generar_alerta_temprana(p_checklist_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_ingestar_gps_batch(p_proveedor_nombre text, p_eventos jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_portal_marcar_acceso() TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_procesar_recalculos_iceo() TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_programar_ot_recepcion(p_activo_id uuid, p_prioridad prioridad_enum, p_fecha date, p_responsable_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_ajuste_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_motivo text, p_usuario_id uuid, p_ot_id uuid, p_autorizado_por uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_entrada_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_costo_unitario numeric, p_documento_referencia character varying, p_usuario_id uuid, p_lote character varying, p_fecha_vencimiento date) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_transferir_inventario(p_bodega_origen_id uuid, p_bodega_destino_id uuid, p_producto_id uuid, p_cantidad numeric, p_usuario_id uuid, p_motivo text) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text) TO anon;
GRANT EXECUTE ON FUNCTION public.verificar_certificaciones() TO anon;

DO $$ BEGIN RAISE NOTICE 'ROLLBACK189 aplicado (ESCRITURA ANONIMA REABIERTA en 46 funciones).'; END $$;
COMMIT;
