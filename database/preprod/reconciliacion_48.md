# Reconciliación de las 48 funciones de escritura anónima (catálogo prod)

Conteo real: **P0=19, P1=24, P2=5, total=48**.
MIG185 cierra 1 P0; MIG189 cierra 45 (11 GrupoA + 7 GrupoB + 27 P1/P2); allowlist QR=2. Cerradas a anon: **46 de 48**.

| Función | Firma | Prio | Corrección | anon antes | anon después | auth después | Guard interno |
|---|---|---|---|---|---|---|---|
| `calcular_iceo` | p_contrato_id uuid, p_faena_id uuid, p_p | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `calcular_todos_kpi` | p_contrato_id uuid, p_faena_id uuid, p_p | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_auto_crear_planes_activo` | p_activo_id uuid | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
| `fn_calama_aplicar_avance_interno` | p_ot_id uuid, p_avance_nuevo numeric, p_ | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_calama_audit_jornada` | p_payload jsonb | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_consumir_inventario_fifo` | p_producto_id uuid, p_bodega_id uuid, p_ | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_evaluar_activos_fuera_geocerca` | () | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_generar_nc_desde_checklist_ot` | p_ot_id uuid | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
| `fn_generar_nc_desde_v3_ot` | p_ot_id uuid | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
| `fn_gps_generar_alertas_sin_senal` | () | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_guardar_reporte_diario` | p_fecha date | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_inicializar_checklist_v2` | p_template_id uuid, p_activo_id uuid, p_ | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_mantenimiento_diario` | p_umbral_mb numeric | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_qr_evaluar_alertas_calidad` | p_respuesta_id uuid | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_recalcular_plazos_diferidos` | p_activo_id uuid | P2 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `fn_reconciliar_comercial_ficha_desde_matriz` | () | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
| `fn_reconciliar_estado_ficha_desde_matriz` | () | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
| `fn_taller_log_jornada_evento` | p_plan_ot_id uuid, p_tipo character vary | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `generar_ots_preventivas` | () | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
| `rpc_actualizar_metricas_activo` | p_activo_id uuid, p_kilometraje numeric, | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_aplicar_diff_a_informe` | p_recepcion_id uuid | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_aprobar_conteo_inventario` | p_conteo_id uuid, p_supervisor_id uuid | P2 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_asignar_pauta` | p_activo_id uuid, p_pauta_id uuid | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_calcular_iceo_periodo` | p_contrato_id uuid, p_faena_id uuid, p_p | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_calcular_incentivos_periodo` | p_contrato_id uuid, p_periodo_inicio dat | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_cambiar_contrato_activo` | p_activo_id uuid, p_nuevo_contrato_id uu | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_cerrar_checklist_v2` | p_instance_id uuid, p_firma_operador_url | P2 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_cerrar_ot_supervisor` | p_ot_id uuid, p_supervisor_id uuid, p_ob | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_cerrar_periodo_kpi` | p_contrato_id uuid, p_faena_id uuid, p_p | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_checklist_cliente_guardar` | p_payload jsonb | P1 | allowlist QR | sí | **sí** | sí | no (público QR) |
| `rpc_confirmar_cierre_diario` | p_fecha date, p_items jsonb | P0 | MIG185 | sí | no | sí | sí (MIG185) |
| `rpc_confirmar_estado_dia` | p_activo_id uuid, p_fecha date, p_estado | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_crear_auxiliar` | p_padre_id uuid, p_nombre text, p_tipo t | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_crear_ot` | p_tipo tipo_ot_enum, p_contrato_id uuid, | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_generar_alerta_temprana` | p_checklist_id uuid | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_generar_qr_activo` | p_activo_id uuid, p_base_url text | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_guardar_checklist_publico` | p_payload jsonb | P1 | allowlist QR | sí | **sí** | sí | no (público QR) |
| `rpc_ingestar_gps_batch` | p_proveedor_nombre text, p_eventos jsonb | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_portal_marcar_acceso` | () | P2 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_procesar_recalculos_iceo` | () | P2 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_programar_ot_recepcion` | p_activo_id uuid, p_prioridad prioridad_ | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_registrar_ajuste_inventario` | p_bodega_id uuid, p_producto_id uuid, p_ | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_registrar_entrada_inventario` | p_bodega_id uuid, p_producto_id uuid, p_ | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_registrar_salida_inventario` | p_bodega_id uuid, p_producto_id uuid, p_ | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_transferir_inventario` | p_bodega_origen_id uuid, p_bodega_destin | P1 | MIG189 P1/P2 | sí | no | sí | no (Fase 1) |
| `rpc_transicion_ot` | p_ot_id uuid, p_nuevo_estado estado_ot_e | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `rpc_validar_sugerencia` | p_sugerencia_id uuid, p_accion character | P0 | MIG189 GrupoA | sí | no | sí | sí (fail-closed) |
| `verificar_certificaciones` | () | P0 | MIG189 GrupoB | sí | no | no | no (interno: sin PostgREST) |
