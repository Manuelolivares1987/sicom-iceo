-- Seed mínimo ANONIMIZADO (datos ficticios; ningún dato real de la empresa).
SET client_min_messages = warning;

-- Usuarios de prueba (uuids fijos para referenciarlos en los tests).
INSERT INTO usuarios_perfil (id, email, nombre_completo, rol, activo) VALUES
 ('11111111-1111-1111-1111-111111111111','admin@test.local','Admin Test','administrador',true),
 ('22222222-2222-2222-2222-222222222222','tecnico@test.local','Tecnico Test','tecnico_mantenimiento',true),
 ('33333333-3333-3333-3333-333333333333','bodega@test.local','Bodega Test','bodeguero',true),
 ('44444444-4444-4444-4444-444444444444','comercial@test.local','Comercial Test','comercial',true),
 ('55555555-5555-5555-5555-555555555555','super@test.local','Supervisor Test','supervisor',true),
 ('66666666-6666-6666-6666-666666666666','baja@test.local','Deshabilitado Test','supervisor',false)
ON CONFLICT (id) DO NOTHING;
-- (El usuario 99999999-... NO se inserta: simula "usuario sin perfil".)

INSERT INTO marcas (id, nombre) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','MarcaTest') ON CONFLICT DO NOTHING;
INSERT INTO modelos (id, marca_id, nombre, tipo_activo) VALUES
 ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','ModeloTest','camion') ON CONFLICT DO NOTHING;

INSERT INTO contratos (id, codigo, nombre, cliente, estado) VALUES
 ('cccccccc-0000-0000-0000-000000000001','CT-TEST-1','Contrato Test','Cliente Ficticio SA','activo')
ON CONFLICT (id) DO NOTHING;

-- Activos de flota rodante (no dado_baja).
INSERT INTO activos (id, modelo_id, codigo, nombre, tipo, estado, estado_comercial, patente, cliente_actual, categoria_uso) VALUES
 ('dddddddd-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','EQ-001','Camion Ficticio 1','camion','operativo','disponible','ZZAA11','Cliente Ficticio SA','arriendo_comercial'),
 ('dddddddd-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','EQ-002','Camion Ficticio 2','camion','operativo','arrendado','ZZAA22','Cliente Ficticio SA','arriendo_comercial')
ON CONFLICT (id) DO NOTHING;

-- Estanques: uno REAL con valor inflado (reproduce bug C5) y uno DEMO.
INSERT INTO combustible_estanques (id, codigo, nombre, capacidad_lt, stock_teorico_lt, costo_promedio_lt, valor_total_stock, activo, tipo, es_demo) VALUES
 ('eeeeeeee-0000-0000-0000-000000000001','EST-TEST-1K','Estanque Test 1K',5000,117.00,0.4780,94700.00,true,'fijo',false),
 ('eeeeeeee-0000-0000-0000-000000000002','EST-TEST-15K','Estanque Test 15K',15000,986.00,0.4724,4493.33,true,'fijo',false),
 ('eeeeeeee-0000-0000-0000-0000000000d1','CAM-DEMO-TEST','Estanque DEMO',20000,0.00,800.0000,16000000.00,true,'movil',true)
ON CONFLICT (id) DO NOTHING;

-- Un kardex previo por estanque real (para que el "último valor" exista).
INSERT INTO combustible_kardex_valorizado
 (id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento, litros_entrada, litros_salida, costo_unitario_movimiento, stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues, created_by)
VALUES
 (gen_random_uuid(),'eeeeeeee-0000-0000-0000-000000000001', now(), 'stock_inicial','SEED-1',117,0,0.4780,117.00,0.4780,55.93,'11111111-1111-1111-1111-111111111111')
ON CONFLICT DO NOTHING;

-- Secuencia usada por fn_generar_folio_salida_combustible (existe en prod).
CREATE SEQUENCE IF NOT EXISTS seq_folio_salida_combustible;

-- ── Portal cliente (sección 3): tabla + usuario portal + usuario DUAL ────────
CREATE TABLE IF NOT EXISTS cliente_portal_perfil (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  nombre_visible text,
  empresa text,
  activo boolean NOT NULL DEFAULT true,
  creado_at timestamptz DEFAULT now()
);
-- Usuario SOLO portal (no está en usuarios_perfil): uuid 99999999...
INSERT INTO cliente_portal_perfil (user_id, nombre_visible, empresa, activo)
VALUES ('99999999-9999-9999-9999-999999999999','Portal Cliente Test','Cliente SA', true)
ON CONFLICT DO NOTHING;
-- Usuario DUAL: administrador interno QUE ADEMÁS es portal cliente → debe DENEGAR P0.
INSERT INTO usuarios_perfil (id, email, nombre_completo, rol, activo)
VALUES ('dddddddd-dead-dead-dead-dddddddddddd','dual@test.local','Dual Interno+Portal','administrador', true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO cliente_portal_perfil (user_id, nombre_visible, empresa, activo)
VALUES ('dddddddd-dead-dead-dead-dddddddddddd','Dual','Cliente SA', true)
ON CONFLICT DO NOTHING;
