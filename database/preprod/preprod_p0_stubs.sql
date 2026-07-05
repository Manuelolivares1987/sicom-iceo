-- STUBS de las 18 funciones P0 que toca MIG189 (firma exacta). SOLO preprod.
SET client_min_messages=warning;

DO $$ BEGIN CREATE TYPE accion_sugerencia_enum AS ENUM ('pendiente','aprobada','rechazada','expirada','auto_revertida'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE actividad_conductor_enum AS ENUM ('conduccion','espera','carga_descarga','descanso','mantencion','pernocte','traslado_interno','disponible'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE area_kpi_enum AS ENUM ('administracion_combustibles','mantenimiento_fijos','mantenimiento_moviles'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE bloque_checklist_enum AS ENUM ('b1_documentacion','b2_estado_exterior','b3_motor_niveles','b4_sistema_equipo','b5_seguridad_activa','b6_diagnostico_electronico','b7_cierre_recepcion','a_trabajos_ot','b_pruebas_funcionales','c_estado_entrega','d_cierre_entrega','b_sistema_electrico','b_fugas','b_inventario_seguridad','b_kit_invierno','b_pruebas_operativas'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE categoria_tarea_taller AS ENUM ('preventiva','calibracion','equipo_flota','asistencia_terreno','equipo_externo','soldadura'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE categoria_uso_enum AS ENUM ('arriendo_comercial','leasing_operativo','uso_interno','venta'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE causa_no_ejecucion_enum AS ENUM ('equipo_no_disponible','falta_repuestos','condicion_climatica','prioridad_operacional','problema_acceso','personal_no_disponible','otra'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE clase_un_sp_enum AS ENUM ('clase_1','clase_2','clase_3','clase_4','clase_5','clase_6','clase_7','clase_8','clase_9'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE clasificacion_iceo_enum AS ENUM ('deficiente','aceptable','bueno','excelencia'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE criticidad_enum AS ENUM ('critica','alta','media','baja'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE default_cobrable_enum AS ENUM ('cliente','empresa','compartido','evaluar','na'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE destino_despacho_combustible_enum AS ENUM ('vehiculo_flota','equipo_externo','bidon','otro'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE efecto_bloqueante_enum AS ENUM ('anular','penalizar','descontar','bloquear_incentivo'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_activo_enum AS ENUM ('operativo','en_mantenimiento','fuera_servicio','dado_baja','en_transito'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_comercial_enum AS ENUM ('arrendado','disponible','uso_interno','leasing','en_recepcion','en_venta','comprometido','en_transito'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_despacho_combustible_enum AS ENUM ('programado','en_ruta','entregado','observado','anulado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_documento_enum AS ENUM ('vigente','por_vencer','vencido','no_aplica'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_documento_respel_enum AS ENUM ('vigente','por_vencer','vencido','en_tramite','no_aplica'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_informe_recepcion_enum AS ENUM ('en_inspeccion','borrador','emitido','cancelado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_instance_enum AS ENUM ('en_progreso','cerrado','anulado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_material_ot_enum AS ENUM ('faltante','suficiente','despachado','cancelado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_oc_enum AS ENUM ('abierta','parcial','cerrada','anulada'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_oc_item_enum AS ENUM ('pendiente','parcial','completo'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE estado_ot_enum AS ENUM ('creada','asignada','en_ejecucion','pausada','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE frecuencia_enum AS ENUM ('diario','semanal','quincenal','mensual','bimestral','trimestral','semestral','anual'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE fuente_registro_enum AS ENUM ('app_manual','gps_automatico','supervisor','api_externa','sistema'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE gravedad_hallazgo_enum AS ENUM ('menor','mayor','critica'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE instrumento_medicion_enum AS ENUM ('check','visual','numerico','manometro','caudalimetro','profundimetro','termometro','multimetro','scanner_obd','muestra_lab','foto','firma'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE metodo_valorizacion_enum AS ENUM ('cpp','fifo','ultimo_costo'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE momento_checklist_enum AS ENUM ('entrega_arriendo','recepcion_devolucion','ready_to_rent','preventiva'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE origen_cambio_estado_enum AS ENUM ('manual','sugerencia','sistema','importado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE prioridad_enum AS ENUM ('emergencia','urgente','alta','normal','baja'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE prueba_operativa_enum AS ENUM ('ruta','recirculacion','regadio'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE resultado_item_enum AS ENUM ('ok','no_ok','na','pendiente'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE resultado_verificacion_enum AS ENUM ('aprobado','rechazado','aprobado_con_observaciones','pendiente'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE rol_usuario_enum AS ENUM ('administrador','gerencia','subgerente_operaciones','supervisor','planificador','tecnico_mantenimiento','bodeguero','operador_abastecimiento','auditor','rrhh_incentivos','jefe_operaciones','jefe_mantenimiento','comercial','prevencionista','colaborador','encargado_cobros','auditor_calidad'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_activo_enum AS ENUM ('punto_fijo','punto_movil','surtidor','dispensador','estanque','bomba','manguera','camion_cisterna','lubrimovil','equipo_bombeo','herramienta_critica','pistola_captura','camioneta','camion','equipo_menor'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_bodega_sp_enum AS ENUM ('bodega_sp_general','estanque_combustible','aljibe_movil','deposito_lubricantes','bodega_respel'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_certificacion_enum AS ENUM ('sec','seremi','siss','revision_tecnica','soap','permiso_municipal','calibracion','licencia_especial','otra','permiso_circulacion','hermeticidad','tc8_sec','inscripcion_sec','seguro_rc','fops_rops','cert_gancho'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_conteo_enum AS ENUM ('ciclico','general','selectivo'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_costo_recepcion_enum AS ENUM ('repuesto','mano_obra','servicio_externo','otro'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_documento_proveedor_enum AS ENUM ('guia','factura','vale','boleta','otro'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_equipamiento_enum AS ENUM ('aljibe_agua','aljibe_combustible','pluma_grua','ampliroll','grua_horquilla','camioneta','tracto','generico'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_geocerca_enum AS ENUM ('base_pillado','faena_cliente','bodega','taller_externo','zona_restringida','punto_interes'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_geocerca_evento_enum AS ENUM ('entrada','salida'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_incidente_enum AS ENUM ('ambiental','seguridad','operacional','vehicular'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_licencia_enum AS ENUM ('A1','A2','A3','A4','A5','B','C','D','E','F'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_medidor_combustible_enum AS ENUM ('ingreso','despacho','bidireccional'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_movimiento_combustible_enum AS ENUM ('ingreso','despacho','ajuste','merma'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_movimiento_enum AS ENUM ('entrada','salida','ajuste_positivo','ajuste_negativo','transferencia_entrada','transferencia_salida','merma','devolucion'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_no_conformidad_enum AS ENUM ('entrega_fuera_tiempo','entrega_incompleta','incumplimiento_norma','incidente_seguridad','contaminacion','documentacion_incompleta','no_conformidad_ambiental','repeticion_servicio','falla_en_terreno','otra'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_ot_enum AS ENUM ('inspeccion','preventivo','correctivo','abastecimiento','lubricacion','inventario','regularizacion','verificacion_disponibilidad','inspeccion_recepcion'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_plan_pm_enum AS ENUM ('por_tiempo','por_kilometraje','por_horas','por_ciclos','mixto'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_proveedor_enum AS ENUM ('combustible','repuestos','servicios','lubricantes','filtros','otros'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_salida_bodega_enum AS ENUM ('ot','persona','ceco','venta','ajuste_autorizado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_salida_combustible_enum AS ENUM ('venta_externa','carga_equipo_propio','despacho_cliente','ajuste'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.fn_auto_crear_planes_activo(p_activo_id uuid)
 RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.fn_auto_crear_planes_activo(p_activo_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.fn_generar_nc_desde_checklist_ot(p_ot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.fn_generar_nc_desde_checklist_ot(p_ot_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.fn_generar_nc_desde_v3_ot(p_ot_id uuid)
 RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.fn_generar_nc_desde_v3_ot(p_ot_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.fn_reconciliar_comercial_ficha_desde_matriz()
 RETURNS TABLE(revisados integer, actualizados integer, bloqueados integer, detalle_bloqueados text)
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.fn_reconciliar_comercial_ficha_desde_matriz() TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz()
 RETURNS TABLE(revisados integer, actualizados integer)
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz() TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.generar_ots_preventivas()
 RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.generar_ots_preventivas() TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character)
 RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.verificar_certificaciones()
 RETURNS TABLE(certificacion_id uuid, estado_anterior text, estado_nuevo text)
 LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;
GRANT EXECUTE ON FUNCTION public.verificar_certificaciones() TO anon, authenticated;
