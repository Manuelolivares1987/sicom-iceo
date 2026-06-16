-- ============================================================================
-- SICOM-ICEO | 143 — Checklist de Inspeccion Unificado (seed + quality gates)
-- ----------------------------------------------------------------------------
-- Parte 2 de 2. Requiere 142 ya aplicado (enum + columnas + template V03).
--
-- 1) Siembra los items EXACTOS de la pestana "Recepcion" del Excel oficial
--    (Camion Aljibe Agua Industrial - Revisado): 11 bloques, ~190 items, con el
--    TIEMPO EN MINUTOS de cada uno (total recepcion = 550 min) + un bloque NUEVO
--    "Pruebas operativas" (ruta / recirculacion / regadio) segun el equipo.
-- 2) Activa CL-INSPECCION-V03 y desactiva CL-RECEPCION-V02 (queda como historico;
--    las instancias viejas siguen apuntando a sus items).
-- 3) Cablea los dos quality gates para que lean de ESTA plantilla (una sola
--    fuente de verdad): la auditoria de calidad (Gate 2) y el chequeo cruzado
--    (Gate 1). De los items no_ok nacen las No Conformidades (ya cableado MIG141).
--
-- Enriquecimiento sobre el Excel (decision del usuario): a cada item se le mapea
--   instrumento de captura, default de recobro (cliente/empresa/compartido),
--   categoria de calidad (documentacion/tecnica) y si es critico.
--
-- IDEMPOTENTE: re-siembra borrando los items del template V03 y reinsertando.
-- ============================================================================

-- ── 0. Precheck (142 aplicado) ───────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='checklist_template_v2_item' AND column_name='tiempo_min') THEN
        RAISE EXCEPTION 'STOP - aplicar 142 primero (falta columna tiempo_min).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM checklist_template_v2 WHERE codigo='CL-INSPECCION-V03') THEN
        RAISE EXCEPTION 'STOP - aplicar 142 primero (falta template CL-INSPECCION-V03).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                   WHERE t.typname='bloque_checklist_enum' AND e.enumlabel='b_pruebas_operativas') THEN
        RAISE EXCEPTION 'STOP - el enum no tiene b_pruebas_operativas. Aplicar 142 y reconectar.';
    END IF;
END $$;


-- ============================================================================
-- 1. SEED items del Excel oficial
-- ============================================================================
DO $body$
DECLARE
    v_tpl UUID;
    v_all          tipo_equipamiento_enum[] := ARRAY['aljibe_agua','aljibe_combustible','pluma_grua','ampliroll','grua_horquilla','camioneta','tracto','generico']::tipo_equipamiento_enum[];
    v_agua         tipo_equipamiento_enum[] := ARRAY['aljibe_agua']::tipo_equipamiento_enum[];
    v_recirc       tipo_equipamiento_enum[] := ARRAY['aljibe_agua','aljibe_combustible']::tipo_equipamiento_enum[];
    v_ruta         tipo_equipamiento_enum[] := ARRAY['aljibe_agua','aljibe_combustible','pluma_grua','ampliroll','tracto','camioneta']::tipo_equipamiento_enum[];
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2 WHERE codigo='CL-INSPECCION-V03';

    -- Re-seed limpio (idempotente)
    DELETE FROM checklist_template_v2_item WHERE template_id = v_tpl;

    -- ── BLOQUE 1 — DOCUMENTACION Y CERTIFICACIONES (orden 1, documentacion) ────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, cert_tipo, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b1_documentacion',1, 1,'B01.01','Permiso de Circulacion vigente',                          v_all,'check',true,true ,'empresa','documentacion',true ,'permiso_circulacion',2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 2,'B01.02','SOAP vigente',                                            v_all,'check',true,true ,'empresa','documentacion',true ,'soap',2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 3,'B01.03','Revision Tecnica vigente',                                v_all,'check',true,true ,'empresa','documentacion',true ,'revision_tecnica',2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 4,'B01.04','Tarjeta GPS / Tacografo operativa',                       v_all,'check',true,false,'empresa','documentacion',false,NULL,2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 5,'B01.05','Emision de gases contaminantes (vigente)',                v_all,'check',true,true ,'empresa','documentacion',true ,'emision_gases',2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 6,'B01.06','Padron del vehiculo',                                     v_all,'check',true,false,'empresa','documentacion',false,NULL,1,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 7,'B01.07','Certificado de laminas de vidrios',                       v_all,'check',true,false,'empresa','documentacion',false,NULL,2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 8,'B01.08','Certificado de cabina',                                   v_all,'check',true,false,'empresa','documentacion',false,NULL,2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1, 9,'B01.09','Certificado de fabricacion del estanque',                 v_all,'check',true,false,'empresa','documentacion',false,NULL,2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1,10,'B01.10','Certificado de fabricacion del sistema hidraulico',       v_all,'check',true,false,'empresa','documentacion',false,NULL,2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1,11,'B01.11','Certificado de mantencion al dia',                        v_all,'check',true,false,'empresa','documentacion',false,NULL,2,'Excel Recepcion'),
        (v_tpl,'b1_documentacion',1,12,'B01.12','Documentacion cliente final (estandares Boart / Codelco)',v_all,'check',false,false,'cliente','documentacion',false,NULL,3,'Excel Recepcion');

    -- ── BLOQUE 2 — ESTADO EXTERIOR Y CABINA (orden 2, tecnica) ────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b2_estado_exterior',2, 1,'B02.01','Carroceria / pintura / corrosion (registro fotografico antes)', v_all,'visual',NULL,true,true ,'cliente','tecnica',false,15,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 2,'B02.02','Panel de instrumentos',                                v_all,'visual',NULL,true,false,'empresa','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 3,'B02.03','Estado del volante',                                    v_all,'visual',NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 4,'B02.04','Radio musical',                                         v_all,'check', NULL,false,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 5,'B02.05','Tacografo',                                             v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 6,'B02.06','Espejos retrovisores',                                  v_all,'visual',NULL,true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 7,'B02.07','Estado de los asientos',                                v_all,'visual',NULL,true,false,'cliente','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 8,'B02.08','Funcionamiento de los asientos',                        v_all,'check', NULL,true,false,'empresa','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2, 9,'B02.09','Chapa de las puertas',                                  v_all,'check', NULL,true,false,'cliente','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,10,'B02.10','Revision de los pernos del tablero',                    v_all,'check', NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,11,'B02.11','Funcionamiento de las bocinas',                         v_all,'check', NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,12,'B02.12','Limpia parabrisas',                                     v_all,'check', NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,13,'B02.13','Correcto funcionamiento de la palanca de cambio/Joystick',v_all,'check',NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,14,'B02.14','Accionamiento del freno de servicio',                   v_all,'check', NULL,true,false,'empresa','tecnica',true , 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,15,'B02.15','Accionamiento del freno de parqueo',                    v_all,'check', NULL,true,false,'empresa','tecnica',true , 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,16,'B02.16','Funcionamiento del freno de motor',                     v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,17,'B02.17','Funcionamiento del retardador',                         v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,18,'B02.18','Gravado de patentes en los vidrios y espejos',          v_all,'visual',NULL,true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,19,'B02.19','Estado de los vidrios laterales y para brisas',         v_all,'visual',NULL,true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,20,'B02.20','Funcionamiento de los alza vidrios',                    v_all,'check', NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,21,'B02.21','Estructura de la cabina',                               v_all,'visual',NULL,true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,22,'B02.22','Parabrisas / vidrios laterales / espejos',              v_all,'visual',NULL,true,true ,'cliente','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,23,'B02.23','Estado faros, focos y luces (todas operativas)',        v_all,'check', NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,24,'B02.24','Estado laminas de seguridad (parabrisa y laterales)',   v_all,'visual',NULL,true,false,'cliente','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,25,'B02.25','Logos de cliente correctamente instalados',             v_all,'visual',NULL,true,false,'cliente','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,26,'B02.26','Stiker de patente y CECO visibles',                     v_all,'visual',NULL,true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,27,'B02.27','Neumatico Pos.1 delantero izq. - presion / banda (mm) / torque',v_all,'profundimetro','mm',true,false,'compartido','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,28,'B02.28','Neumatico Pos.2 delantero der. - presion / banda / torque',     v_all,'profundimetro','mm',true,false,'compartido','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,29,'B02.29','Neumaticos Pos.3-4 medio izq./der. - presion / banda / torque', v_all,'profundimetro','mm',true,false,'compartido','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,30,'B02.30','Neumaticos Pos.5-6 medio izq./der. - presion / banda / torque', v_all,'profundimetro','mm',true,false,'compartido','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,31,'B02.31','Neumaticos Pos.7-8 medio izq./der. - presion / banda / torque', v_all,'profundimetro','mm',true,false,'compartido','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,32,'B02.32','Neumaticos Pos.9-10 medio izq./der. - presion / banda / torque',v_all,'profundimetro','mm',true,false,'compartido','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,33,'B02.33','Rueda de repuesto 1 / barra anti empotramiento',        v_all,'visual',NULL,true,false,'cliente','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,34,'B02.34','Rueda de repuesto 2 / barra anti empotramiento',        v_all,'visual',NULL,true,false,'cliente','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,35,'B02.35','Revisar todos los Check Point',                         v_all,'check', NULL,true,false,'empresa','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,36,'B02.36','Sin filtraciones visibles (aceite, agua, combustible, hidraulico)',v_all,'visual',NULL,true,true,'evaluar','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,37,'B02.37','Tele comando',                                          v_all,'check', NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,38,'B02.38','Eslingas / lingas de puertas',                          v_all,'visual',NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,39,'B02.39','Seguros de anclaje de cabina / seguros de capot',       v_all,'check', NULL,true,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,40,'B02.40','Corta corriente',                                       v_all,'check', NULL,true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,41,'B02.41','Escaleras, pasamanos y barandas',                       v_all,'visual',NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,42,'B02.42','Paquetes de resorte',                                   v_all,'visual',NULL,true,false,'empresa','tecnica',false, 8,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,43,'B02.43','Pernos de sujecion TK (estanque/equipo) y chasis',      v_all,'check', NULL,true,false,'empresa','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b2_estado_exterior',2,44,'B02.44','Acumulador de aire',                                    v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion');

    -- ── BLOQUE 3 — MOTOR Y NIVELES (orden 3, tecnica) ─────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b3_motor_niveles',3, 1,'B03.01','Nivel aceite motor (varilla)',                           v_all,'visual',NULL,true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 2,'B03.02','Nivel refrigerante',                                     v_all,'visual',NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 3,'B03.03','Nivel liquido de frenos',                                v_all,'visual',NULL,true,false,'empresa','tecnica',true , 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 4,'B03.04','Nivel liquido direccion hidraulica',                     v_all,'visual',NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 5,'B03.05','Nivel AdBlue (camiones Euro V/VI)',                       v_all,'visual',NULL,true,false,'cliente','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 6,'B03.06','Nivel de aceite de la transmision',                      v_all,'visual',NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 7,'B03.07','Nivel de aceite del retardador',                         v_all,'visual',NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 8,'B03.08','Nivel de aceite del primer diferencial',                 v_all,'visual',NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3, 9,'B03.09','Nivel de aceite de segundo diferencial',                 v_all,'visual',NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,10,'B03.10','Estado del Aspa',                                         v_all,'visual',NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,11,'B03.11','Estado de los radiadores (Refrigerante, transmision y aire acondicionado)',v_all,'visual',NULL,true,false,'empresa','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,12,'B03.12','Sistema de accionamiento del aire acondicionado',        v_all,'check', NULL,true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,13,'B03.13','Revision del accionamiento del embrague',                v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,14,'B03.14','Funcionamiento de la caja de direccion',                 v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,15,'B03.15','Funcionamiento del tren delantero',                      v_all,'check', NULL,true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,16,'B03.16','Revision de los bujes de las bielas',                    v_all,'visual',NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,17,'B03.17','Revision de los bujes de los paquetes de resortes',      v_all,'visual',NULL,true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,18,'B03.18','Estado del parachoques delantero',                       v_all,'visual',NULL,true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,19,'B03.19','Estado del parachoques trasero',                         v_all,'visual',NULL,true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,20,'B03.20','Funcionamiento del corta corriente',                     v_all,'check', NULL,true,false,'empresa','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,21,'B03.21','Estado correas (tension, fisuras, deshilachado)',        v_all,'visual',NULL,true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,22,'B03.22','Estado mangueras (sin fisuras ni filtraciones)',         v_all,'visual',NULL,true,false,'empresa','tecnica',false,20,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,23,'B03.23','Estado filtros (saturacion filtro de aire - visual)',    v_all,'visual',NULL,true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,24,'B03.24','Estado bateria (terminales limpios, voltaje >12V)',      v_all,'multimetro','V',true,false,'compartido','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,25,'B03.25','Rearranque: 5 segundos antes de encender (avisar al operador)',v_all,'check',NULL,true,false,'empresa','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,26,'B03.26','Humo de escape: color / persistencia (registrar)',       v_all,'visual',NULL,true,true ,'evaluar','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b3_motor_niveles',3,27,'B03.27','Ruido de motor: anormal (vibracion / golpes) - describir',v_all,'visual',NULL,true,false,'evaluar','tecnica',false, 3,'Excel Recepcion');

    -- ── BLOQUE 4 — SISTEMA ELECTRICO (orden 4, tecnica) ───────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b_sistema_electrico',4, 1,'B04.01','Luces bajas',                                          v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 2,'B04.02','Luces altas',                                          v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 3,'B04.03','Luces de posicion',                                    v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 4,'B04.04','Intermitentes derecho, izquierdo trasero y delanteros',v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 5,'B04.05','Luces de estacionamiento',                             v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 6,'B04.06','Luz de patente',                                       v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 7,'B04.07','Focos neblineros',                                     v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 8,'B04.08','Iluminacion panel control',                            v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4, 9,'B04.09','Iluminacion interior cabina',                          v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,10,'B04.10','Focos faeneros traseros y laterales',                  v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,11,'B04.11','Estado de las micas',                                  v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,12,'B04.12','Correcto ruteado de los cables',                       v_all,'check',true,false,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,13,'B04.13','Funcionamiento de todos los controles del panel de control',v_all,'check',true,false,'empresa','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,14,'B04.14','Funcionamiento correcto de las paradas de emergencia', v_all,'check',true,false,'empresa','tecnica',true , 5,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,15,'B04.15','Funcionamiento del aire acondicionado',                v_all,'check',true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,16,'B04.16','Funcionamiento de la calefaccion',                     v_all,'check',true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,17,'B04.17','Luces de trocha',                                      v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,18,'B04.18','Luces de freno',                                       v_all,'check',true,false,'empresa','tecnica',true , 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,19,'B04.19','Luces de retroceso',                                   v_all,'check',true,false,'empresa','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b_sistema_electrico',4,20,'B04.20','Alarma sonora de retroceso',                           v_all,'check',true,false,'empresa','tecnica',true , 1,'Excel Recepcion');

    -- ── BLOQUE 5 — REVISION DE FUGAS POR COMPONENTE (orden 5, tecnica) ────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b_fugas',5,1,'B05.01','Motor - sin fugas de aceite / refrigerante',                v_all,'visual',true,false,'empresa','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b_fugas',5,2,'B05.02','Caja de cambios - sin fugas',                                v_all,'visual',true,false,'empresa','tecnica',false,4,'Excel Recepcion'),
        (v_tpl,'b_fugas',5,3,'B05.03','Diferencial (delantero / trasero) - sin fugas',             v_all,'visual',true,false,'empresa','tecnica',false,4,'Excel Recepcion'),
        (v_tpl,'b_fugas',5,4,'B05.04','Sistema de direccion - sin fugas',                          v_all,'visual',true,false,'empresa','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b_fugas',5,5,'B05.05','Estanque de combustible del camion - sin fugas',            v_all,'visual',true,true ,'empresa','tecnica',true ,2,'Excel Recepcion'),
        (v_tpl,'b_fugas',5,6,'B05.06','Sistema neumatico / acumulador de aire - sin fugas',        v_all,'visual',true,false,'empresa','tecnica',false,2,'Excel Recepcion');

    -- ── BLOQUE 6 — SISTEMAS ESPECIFICOS DEL EQUIPAMIENTO (orden 6, aljibe agua) ─
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo',6, 1,'B06.01','ALJIBE - Revisar estanque por filtraciones',            v_agua,'visual',NULL,true,false,'empresa','tecnica',false, 5,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 2,'B06.02','ALJIBE - Revisar estanque por fisuras (ext. e int.)',    v_agua,'visual',NULL,true,true ,'empresa','tecnica',false,10,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 3,'B06.03','ALJIBE - Bomba centrifuga (chequeo de operacion, ruidos)',v_agua,'check',NULL,true,false,'empresa','tecnica',false, 6,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 4,'B06.04','ALJIBE - Accionamiento de toma de fuerza (PTO)',         v_agua,'check',NULL,true,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 5,'B06.05','ALJIBE - Apertura y cierre de valvulas (llaves)',        v_agua,'check',NULL,true,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 6,'B06.06','ALJIBE - Funcionamiento del regulador de flujo',         v_agua,'check',NULL,true,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 7,'B06.07','ALJIBE - Funcionamiento de aspersores',                  v_agua,'check',NULL,true,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 8,'B06.08','ALJIBE - Funcionamiento de barra de riego (flautin)',    v_agua,'check',NULL,true,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6, 9,'B06.09','ALJIBE - Funcionamiento de canon de agua (si tiene)',    v_agua,'check',NULL,false,false,'empresa','tecnica',false, 4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6,10,'B06.10','ALJIBE - Funcionamiento de valvulas de aire / tecalanes de aire',v_agua,'check',NULL,true,false,'empresa','tecnica',false,4,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6,11,'B06.11','ALJIBE - Carrete, manguera y pistola',                   v_agua,'visual',NULL,true,false,'cliente','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6,12,'B06.12','ALJIBE - Escotilla y valvula de alivio',                 v_agua,'check',NULL,true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b4_sistema_equipo',6,13,'B06.13','ALJIBE - Prueba de caudal (L/min) y fugas en sistema general',v_agua,'caudalimetro','L/min',true,false,'empresa','tecnica',false,30,'Excel Recepcion');

    -- ── BLOQUE 7 — SEGURIDAD ACTIVA (orden 7, tecnica) ────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b5_seguridad_activa',7, 1,'B07.01','Sistema somnolencia (Driveri / Smart Eye) - operativo',  v_all,'check',true,true ,'empresa','tecnica',true , 4,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 2,'B07.02','Sistema Mobileye / ADAS - operativo + actualizacion vigente',v_all,'check',true,true,'empresa','tecnica',true ,4,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 3,'B07.03','Camara de retroceso - calidad imagen + nocturno',         v_all,'check',true,false,'empresa','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 4,'B07.04','Camara punto ciego - operativa',                          v_all,'check',true,false,'empresa','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 5,'B07.05','Frenos EBS / ABS - sin codigos de falla',                 v_all,'check',true,false,'empresa','tecnica',true , 4,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 6,'B07.06','Pertiga retractil - altura y luminosidad',               v_all,'check',true,false,'cliente','tecnica',false, 3,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 7,'B07.07','Balizas - todas operativas (ambar / rojo)',              v_all,'check',true,false,'cliente','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 8,'B07.08','Cunas',                                                  v_all,'check',true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7, 9,'B07.09','Radio comunicacion',                                     v_all,'check',true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7,10,'B07.10','Extintor - vigente + presion + accesible',              v_all,'check',true,true ,'cliente','tecnica',true , 2,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7,11,'B07.11','Calzos de seguridad - presentes y en buen estado',      v_all,'check',true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7,12,'B07.12','Triangulos de emergencia + chaleco reflectante',        v_all,'check',true,false,'cliente','tecnica',false, 1,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7,13,'B07.13','Botiquin de primeros auxilios - completo y vigente',    v_all,'check',true,false,'cliente','tecnica',false, 2,'Excel Recepcion'),
        (v_tpl,'b5_seguridad_activa',7,14,'B07.14','Cinturones de seguridad - todos operativos',            v_all,'check',true,false,'cliente','tecnica',true , 2,'Excel Recepcion');

    -- ── BLOQUE 8 — DIAGNOSTICO ELECTRONICO (orden 8, tecnica) ─────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b6_diagnostico_electronico',8,1,'B08.01','Escaneo OBD / Jaltest - sin codigos de falla activos',          v_all,'scanner_obd',NULL,true,true ,'evaluar','tecnica',false,8,'Excel Recepcion'),
        (v_tpl,'b6_diagnostico_electronico',8,2,'B08.02','Escaneo de marca (Volvo Connect / Telligent / Optidriver) - sin advertencias',v_all,'scanner_obd',NULL,true,false,'empresa','tecnica',false,6,'Excel Recepcion'),
        (v_tpl,'b6_diagnostico_electronico',8,3,'B08.03','Lectura del ultimo error / advertencia registrada',            v_all,'scanner_obd',NULL,true,false,'evaluar','tecnica',false,3,'Excel Recepcion'),
        (v_tpl,'b6_diagnostico_electronico',8,4,'B08.04','Estado regeneracion DPF (Euro V/VI) - porcentaje',             v_all,'numerico','%',true,false,'evaluar','tecnica',false,3,'Excel Recepcion'),
        (v_tpl,'b6_diagnostico_electronico',8,5,'B08.05','Proxima pauta del sistema (horometro del proximo servicio)',   v_all,'numerico',NULL,true,false,'na','tecnica',false,2,'Excel Recepcion');

    -- ── BLOQUE 9 — INVENTARIO Y ELEMENTOS DE SEGURIDAD (orden 9, tecnica) ─────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b_inventario_seguridad',9, 1,'B09.01','Indicadores de tuerca / traba tuercas (check point)', v_all,'check',true,false,'empresa','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 2,'B09.02','Extintor de cabina (vigente)',                        v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 3,'B09.03','Estado de las patentes',                              v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 4,'B09.04','Extintores exteriores y gabinetes (vigentes)',        v_all,'check',true,false,'cliente','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 5,'B09.05','Gata',                                                v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 6,'B09.06','Llave de ruedas y barrote',                           v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 7,'B09.07','Triangulos de seguridad',                             v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 8,'B09.08','Chaleco reflectante amarillo',                        v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9, 9,'B09.09','Botiquin',                                            v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9,10,'B09.10','Conos',                                               v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9,11,'B09.11','Cunas de seguridad',                                  v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9,12,'B09.12','Radio de comunicacion',                               v_all,'check',true,false,'cliente','tecnica',false,1,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9,13,'B09.13','Rueda de repuesto',                                   v_all,'check',true,false,'cliente','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b_inventario_seguridad',9,14,'B09.14','Sistema de somnolencia',                              v_all,'check',true,false,'empresa','tecnica',false,2,'Excel Recepcion');

    -- ── BLOQUE 10 — KIT DE INVIERNO (orden 10, opcional faena cordillera) ─────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b_kit_invierno',10, 1,'B10.01','Pala para nieve',                          v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 2,'B10.02','Cadena para nieve + tensores de cadena',   v_all,'check',false,false,'cliente','tecnica',false,2,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 3,'B10.03','1 par de cunas de seguridad',              v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 4,'B10.04','Saco de yute',                             v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 5,'B10.05','Lanza de arrastre o estrobo',              v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 6,'B10.06','1 kg de sal gruesa',                       v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 7,'B10.07','Chuzo y/o picota',                         v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 8,'B10.08','Botella plastica 1 L de alcohol',          v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10, 9,'B10.09','Par de plumillas extra',                   v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10,10,'B10.10','Linterna con 2 pilas de repuesto',         v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)'),
        (v_tpl,'b_kit_invierno',10,11,'B10.11','2 frazadas',                               v_all,'check',false,false,'cliente','tecnica',false,1,'Excel Recepcion (opcional)');

    -- ── BLOQUE NUEVO — PRUEBAS OPERATIVAS (orden 11): ruta / recirculacion / regadio ─
    -- "Segun corresponda": ruta -> equipos rodantes; recirculacion -> aljibes;
    -- regadio -> aljibe agua.
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, prueba_tipo, tiempo_min, fuente_fabricante)
    VALUES
        -- Prueba de ruta
        (v_tpl,'b_pruebas_operativas',11, 1,'PRU.R01','Prueba de ruta - arranque, marcha y cambios sin saltos en carga',     v_ruta,'check',NULL,true,false,'empresa','tecnica',false,'ruta',10,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 2,'PRU.R02','Prueba de ruta - frenos de servicio frenan recto, sin tirones',       v_ruta,'check',NULL,true,false,'empresa','tecnica',true ,'ruta', 5,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 3,'PRU.R03','Prueba de ruta - freno motor y retardador efectivos en bajada',       v_ruta,'check',NULL,true,false,'empresa','tecnica',false,'ruta', 5,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 4,'PRU.R04','Prueba de ruta - direccion estable, sin vibracion ni holgura',        v_ruta,'check',NULL,true,false,'empresa','tecnica',false,'ruta', 5,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 5,'PRU.R05','Prueba de ruta - temperatura motor/refrigeracion estable en operacion',v_ruta,'visual',NULL,true,false,'empresa','tecnica',false,'ruta', 5,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 6,'PRU.R06','Prueba de ruta - sin ruidos anomalos en suspension/tren motriz',      v_ruta,'visual',NULL,true,false,'evaluar','tecnica',false,'ruta', 5,'Pruebas operativas'),
        -- Recirculacion
        (v_tpl,'b_pruebas_operativas',11, 7,'PRU.C01','Recirculacion - bomba opera en circuito cerrado sin cavitacion',      v_recirc,'check',NULL,true,false,'empresa','tecnica',false,'recirculacion',6,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 8,'PRU.C02','Recirculacion - presion y caudal estables durante recirculacion',     v_recirc,'manometro','kPa',true,false,'empresa','tecnica',false,'recirculacion',6,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11, 9,'PRU.C03','Recirculacion - sin fugas en lineas, valvulas y uniones',             v_recirc,'visual',NULL,true,true ,'empresa','tecnica',true ,'recirculacion',5,'Pruebas operativas'),
        -- Regadio (aljibe agua)
        (v_tpl,'b_pruebas_operativas',11,10,'PRU.G01','Regadio - aspersores delanteros: patron y alcance uniforme',          v_agua,'check',NULL,true,false,'empresa','tecnica',false,'regadio',5,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11,11,'PRU.G02','Regadio - aspersores laterales y traseros operativos',                v_agua,'check',NULL,true,false,'empresa','tecnica',false,'regadio',4,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11,12,'PRU.G03','Regadio - barra de riego (flautin): distribucion pareja sin obstruccion',v_agua,'check',NULL,true,false,'empresa','tecnica',false,'regadio',5,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11,13,'PRU.G04','Regadio - canon de agua: alcance y giro (si tiene)',                  v_agua,'check',NULL,false,false,'empresa','tecnica',false,'regadio',4,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11,14,'PRU.G05','Regadio - regulador de flujo responde correctamente',                 v_agua,'check',NULL,true,false,'empresa','tecnica',false,'regadio',4,'Pruebas operativas'),
        (v_tpl,'b_pruebas_operativas',11,15,'PRU.G06','Regadio - prueba de caudal en regadio (L/min)',                       v_agua,'caudalimetro','L/min',true,false,'empresa','tecnica',false,'regadio',10,'Pruebas operativas');

    -- ── BLOQUE 11 — CIERRE Y RESPONSABILIDADES (orden 12, tecnica) ────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, bloque_orden, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, categoria_calidad, critico, tiempo_min, fuente_fabricante)
    VALUES
        (v_tpl,'b7_cierre_recepcion',12,1,'B11.01','Danos no reportados detectados al recibir (texto + fotos)',  v_all,'visual',true ,true ,'cliente','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b7_cierre_recepcion',12,2,'B11.02','Observaciones del operador que entrega (texto libre)',        v_all,'visual',false,false,'na','tecnica',false,3,'Excel Recepcion'),
        (v_tpl,'b7_cierre_recepcion',12,3,'B11.03','Trabajos solicitados (descripcion inicial)',                  v_all,'visual',false,false,'evaluar','tecnica',false,5,'Excel Recepcion'),
        (v_tpl,'b7_cierre_recepcion',12,4,'B11.04','Proximo horometro de pauta (planificado) - OBLIGATORIO',      v_all,'numerico',true,false,'na','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b7_cierre_recepcion',12,5,'B11.05','Tipo de OT a generar (taxonomia OT-XX-XX)',                   v_all,'visual',false,false,'na','tecnica',false,2,'Excel Recepcion'),
        (v_tpl,'b7_cierre_recepcion',12,6,'B11.06','Tiempo estimado de la OT (HH) y fecha de entrega comprometida',v_all,'numerico',false,false,'na','tecnica',false,3,'Excel Recepcion'),
        (v_tpl,'b7_cierre_recepcion',12,7,'B11.07','Firma operador entrega + RUT / Firma responsable taller + RUT',v_all,'firma',true,false,'na','tecnica',false,3,'Excel Recepcion');

END $body$;


-- ── 2. Activar V03 y desactivar V02 (orden importa por uq_cl_v2_momento_activo) ─
UPDATE checklist_template_v2 SET activo=false, updated_at=NOW()
 WHERE codigo='CL-RECEPCION-V02' AND activo=true;
UPDATE checklist_template_v2 SET activo=true, updated_at=NOW()
 WHERE codigo='CL-INSPECCION-V03';


-- ============================================================================
-- 3. CABLEAR QUALITY GATES A LA MISMA PLANTILLA (una sola fuente de verdad)
-- ============================================================================

-- 3.1 GATE 2 — Auditoria de calidad: copiar items del template activo de
--     recepcion/inspeccion, filtrados por el tipo de equipamiento del activo.
--     Mapea bloque->categoria (documentacion/tecnica), critico y cert_tipo.
--     Fallback a la plantilla legacy si el template no tuviera items.
CREATE OR REPLACE FUNCTION fn_iniciar_auditoria_calidad(
    p_activo_id UUID,
    p_ot_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_aud  UUID;
    v_tot  INT;
    v_tipo tipo_equipamiento_enum;
    v_tpl  UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id; END IF;

    SELECT COALESCE(tipo_equipamiento,'generico') INTO v_tipo FROM activos WHERE id = p_activo_id;
    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true
     ORDER BY version DESC LIMIT 1;

    INSERT INTO auditorias_calidad (activo_id, ot_id, iniciada_por, created_by)
    VALUES (p_activo_id, p_ot_id, v_user, v_user)
    RETURNING id INTO v_aud;

    -- Items desde el template unificado (filtrado por equipo)
    IF v_tpl IS NOT NULL THEN
        INSERT INTO auditoria_calidad_items
            (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
             referencia_cert_id, resultado)
        SELECT
            v_aud,
            ti.categoria_calidad,
            ti.bloque_orden * 1000 + ti.orden,
            ti.descripcion, ti.obligatorio, ti.critico,
            c.cert_id,
            CASE
                WHEN ti.categoria_calidad = 'documentacion' AND ti.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente'
            END
        FROM checklist_template_v2_item ti
        LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
            FROM certificaciones cc
            WHERE cc.activo_id = p_activo_id
              AND ti.cert_tipo IS NOT NULL
              AND cc.tipo::TEXT = ti.cert_tipo
            ORDER BY cc.fecha_vencimiento DESC NULLS LAST
            LIMIT 1
        ) c ON true
        WHERE ti.template_id = v_tpl
          AND v_tipo = ANY(ti.tipos_equipamiento)
        ORDER BY ti.bloque_orden, ti.orden;

        GET DIAGNOSTICS v_tot = ROW_COUNT;
    ELSE
        v_tot := 0;
    END IF;

    -- Fallback: plantilla legacy si el template no aporto items
    IF v_tot = 0 THEN
        INSERT INTO auditoria_calidad_items
            (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
             referencia_cert_id, resultado)
        SELECT
            v_aud, p.categoria, p.orden, p.descripcion, p.obligatorio, p.critico,
            c.cert_id,
            CASE
                WHEN p.categoria = 'documentacion' AND p.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente'
            END
        FROM auditoria_calidad_plantilla_items p
        LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
            FROM certificaciones cc
            WHERE cc.activo_id = p_activo_id
              AND p.cert_tipo IS NOT NULL
              AND cc.tipo::TEXT = p.cert_tipo
            ORDER BY cc.fecha_vencimiento DESC NULLS LAST
            LIMIT 1
        ) c ON true
        WHERE p.activo = true
        ORDER BY p.categoria, p.orden;
        GET DIAGNOSTICS v_tot = ROW_COUNT;
    END IF;

    UPDATE auditorias_calidad SET items_total = v_tot WHERE id = v_aud;
    RETURN jsonb_build_object('auditoria_id', v_aud, 'items_total', v_tot, 'fuente',
                              CASE WHEN v_tpl IS NOT NULL THEN 'CL-INSPECCION-V03' ELSE 'plantilla_legacy' END);
END $$;


-- 3.2 GATE 1 — Chequeo cruzado: tomar los items TECNICOS del mismo template
--     (la documentacion no aplica a la verificacion de trabajo en curso),
--     filtrados por el equipo de la OT. Fallback a la plantilla legacy.
CREATE OR REPLACE FUNCTION fn_crear_chequeo_cruzado(
    p_ot_id            UUID,
    p_ejecucion_id     UUID DEFAULT NULL,
    p_avance_evento_id UUID DEFAULT NULL,
    p_avance_declarado NUMERIC DEFAULT NULL,
    p_turno            VARCHAR DEFAULT 'dia'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_ot        RECORD;
    v_ejecutor  UUID;
    v_cheq_id   UUID;
    v_total     INT;
    v_tipo      tipo_equipamiento_enum;
    v_tpl       UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT id, activo_id, responsable_id INTO v_ot
    FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT % no existe', p_ot_id; END IF;

    v_ejecutor := NULL;
    IF p_ejecucion_id IS NOT NULL THEN
        SELECT ejecutor_id INTO v_ejecutor FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id;
    END IF;
    v_ejecutor := COALESCE(v_ejecutor, v_ot.responsable_id, v_user);

    INSERT INTO taller_chequeos_cruzados (
        ot_id, activo_id, ejecucion_id, avance_evento_id, turno,
        ejecutor_id, avance_declarado, created_by
    ) VALUES (
        p_ot_id, v_ot.activo_id, p_ejecucion_id, p_avance_evento_id,
        COALESCE(p_turno,'dia'), v_ejecutor, p_avance_declarado, v_user
    ) RETURNING id INTO v_cheq_id;

    SELECT COALESCE(tipo_equipamiento,'generico') INTO v_tipo FROM activos WHERE id = v_ot.activo_id;
    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true
     ORDER BY version DESC LIMIT 1;

    -- Items tecnicos del template (filtrados por equipo)
    IF v_tpl IS NOT NULL THEN
        INSERT INTO taller_chequeo_cruzado_items
            (chequeo_id, orden, categoria, descripcion, obligatorio, requiere_foto)
        SELECT v_cheq_id, ti.bloque_orden * 1000 + ti.orden, 'general',
               ti.descripcion, ti.obligatorio, ti.requiere_foto
        FROM checklist_template_v2_item ti
        WHERE ti.template_id = v_tpl
          AND ti.categoria_calidad = 'tecnica'
          AND v_tipo = ANY(ti.tipos_equipamiento)
        ORDER BY ti.bloque_orden, ti.orden;
        GET DIAGNOSTICS v_total = ROW_COUNT;
    ELSE
        v_total := 0;
    END IF;

    -- Fallback: plantilla legacy
    IF v_total = 0 THEN
        INSERT INTO taller_chequeo_cruzado_items
            (chequeo_id, orden, categoria, descripcion, obligatorio, requiere_foto)
        SELECT v_cheq_id, orden, categoria, descripcion, obligatorio, requiere_foto
        FROM taller_chequeo_cruzado_plantilla_items
        WHERE activo = true
        ORDER BY orden;
        GET DIAGNOSTICS v_total = ROW_COUNT;
    END IF;

    UPDATE taller_chequeos_cruzados SET items_total = v_total WHERE id = v_cheq_id;
    RETURN jsonb_build_object('chequeo_id', v_cheq_id, 'ejecutor_id', v_ejecutor,
                              'items_total', v_total);
END $$;


-- ============================================================================
-- 4. VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'items_v03',     (SELECT COUNT(*) FROM checklist_template_v2_item i
                      JOIN checklist_template_v2 t ON t.id=i.template_id WHERE t.codigo='CL-INSPECCION-V03'),
    'minutos_total', (SELECT COALESCE(SUM(tiempo_min),0) FROM checklist_template_v2_item i
                      JOIN checklist_template_v2 t ON t.id=i.template_id WHERE t.codigo='CL-INSPECCION-V03'),
    'minutos_sin_pruebas', (SELECT COALESCE(SUM(tiempo_min),0) FROM checklist_template_v2_item i
                      JOIN checklist_template_v2 t ON t.id=i.template_id
                      WHERE t.codigo='CL-INSPECCION-V03' AND i.bloque <> 'b_pruebas_operativas'),
    'bloques',       (SELECT COUNT(DISTINCT bloque_orden) FROM checklist_template_v2_item i
                      JOIN checklist_template_v2 t ON t.id=i.template_id WHERE t.codigo='CL-INSPECCION-V03'),
    'activo_v03',    (SELECT activo FROM checklist_template_v2 WHERE codigo='CL-INSPECCION-V03'),
    'activo_v02',    (SELECT activo FROM checklist_template_v2 WHERE codigo='CL-RECEPCION-V02'),
    'subtotales_por_bloque', (SELECT jsonb_object_agg(bloque_orden::text, suma) FROM (
                      SELECT bloque_orden, SUM(tiempo_min) AS suma FROM checklist_template_v2_item i
                      JOIN checklist_template_v2 t ON t.id=i.template_id
                      WHERE t.codigo='CL-INSPECCION-V03' GROUP BY bloque_orden ORDER BY bloque_orden) s)
) AS resultado;

NOTIFY pgrst, 'reload schema';
