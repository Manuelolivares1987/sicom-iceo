-- SICOM-ICEO | Usuarios Demo por Perfil
-- ============================================================================
-- INSTRUCCIONES:
-- 1. Primero crear los usuarios en Supabase Dashboard > Authentication > Users
--    (Add user > email + password) para cada uno
-- 2. Copiar el UUID que Supabase genera para cada usuario
-- 3. Reemplazar los UUIDs de abajo con los reales
-- 4. Ejecutar este SQL
-- ============================================================================

-- ============================================================================
-- PASO 1: Crear estos usuarios en Supabase Auth Dashboard:
--
-- Email: operador@pillado.cl     Password: Pillado2026!
-- Email: supervisor@pillado.cl   Password: Pillado2026!
-- Email: bodeguero@pillado.cl    Password: Pillado2026!
-- Email: planificador@pillado.cl Password: Pillado2026!
-- Email: gerencia@pillado.cl     Password: Pillado2026!
--
-- PASO 2: Después de crear cada uno, copiar su UUID y pegarlo abajo
-- ============================================================================


-- ============================================================================
-- PASO 3: Insertar perfiles (REEMPLAZAR UUIDs con los reales)
-- ============================================================================

-- NOTA: Reemplace 'PASTE-UUID-HERE-xxx' con el UUID real de cada usuario
-- creado en el paso 1. El UUID aparece en la columna "User UID" del dashboard.

/*
-- Descomentar y ejecutar después de reemplazar UUIDs:

INSERT INTO usuarios_perfil (id, email, nombre_completo, rut, cargo, rol, faena_id, activo)
VALUES
  -- Operador de terreno (escanea QR, ejecuta OTs, registra materiales)
  ('PASTE-UUID-HERE-operador',
   'operador@pillado.cl',
   'Carlos Muñoz Pérez',
   '15.234.567-8',
   'Técnico de Mantenimiento',
   'tecnico_mantenimiento',
   (SELECT id FROM faenas WHERE codigo = 'FAE-MP' LIMIT 1),
   true),

  -- Supervisor (revisa OTs, cierra OTs, ve KPI de su faena)
  ('PASTE-UUID-HERE-supervisor',
   'supervisor@pillado.cl',
   'Roberto Soto Henríquez',
   '12.987.654-3',
   'Supervisor de Terreno',
   'supervisor',
   (SELECT id FROM faenas WHERE codigo = 'FAE-MP' LIMIT 1),
   true),

  -- Bodeguero (gestiona inventario, conteos, salidas)
  ('PASTE-UUID-HERE-bodeguero',
   'bodeguero@pillado.cl',
   'María González Tapia',
   '16.543.210-9',
   'Bodeguero',
   'bodeguero',
   (SELECT id FROM faenas WHERE codigo = 'FAE-MP' LIMIT 1),
   true),

  -- Planificador (crea OTs, asigna técnicos, gestiona PM)
  ('PASTE-UUID-HERE-planificador',
   'planificador@pillado.cl',
   'Andrea Villalobos Riquelme',
   '14.876.543-2',
   'Planificador de Mantenimiento',
   'planificador',
   (SELECT id FROM faenas WHERE codigo = 'FAE-MP' LIMIT 1),
   true),

  -- Gerencia (solo ve dashboards, KPI, ICEO, reportes)
  ('PASTE-UUID-HERE-gerencia',
   'gerencia@pillado.cl',
   'Fernando Pillado Araya',
   '10.123.456-7',
   'Gerente de Operaciones',
   'gerencia',
   NULL,
   true)
ON CONFLICT (id) DO NOTHING;

*/

-- ============================================================================
-- QUÉ VE CADA PERFIL (filtrado por use-permissions.ts)
-- ============================================================================
--
-- TÉCNICO DE MANTENIMIENTO (operador@pillado.cl):
-- ├── Dashboard
-- ├── Mis OTs ← solo sus OTs asignadas
-- ├── Activos (solo ver)
-- └── Inventario (solo ver)
-- Flujo demo: Login → Mis OTs → abrir OT → checklist → evidencia → finalizar
-- También: escanear QR de equipo → ver ficha pública
--
-- SUPERVISOR (supervisor@pillado.cl):
-- ├── Dashboard
-- ├── Mis OTs
-- ├── Órdenes de Trabajo (todas de su faena)
-- ├── Activos
-- ├── Mantenimiento
-- ├── Cumplimiento
-- ├── KPI
-- ├── ICEO
-- └── Reportes
-- Flujo demo: ver OTs ejecutadas → revisar → cerrar con supervisor
--
-- BODEGUERO (bodeguero@pillado.cl):
-- ├── Dashboard
-- ├── Inventario (stock, movimientos, conteos)
-- ├── Activos (solo ver)
-- ├── Órdenes de Trabajo (solo ver, para validar OT en salidas)
-- └── Reportes
-- Flujo demo: salida inventario con escáner → conteo con pistola
--
-- PLANIFICADOR (planificador@pillado.cl):
-- ├── Dashboard
-- ├── Órdenes de Trabajo (crear, asignar, editar)
-- ├── Activos
-- ├── Mantenimiento (crear planes PM)
-- ├── Inventario (solo ver)
-- ├── Cumplimiento
-- ├── KPI
-- └── Reportes
-- Flujo demo: crear OT → asignar técnico → ver calendario PM
--
-- GERENCIA (gerencia@pillado.cl):
-- ├── Dashboard
-- ├── Contratos
-- ├── Activos
-- ├── Órdenes de Trabajo (solo ver)
-- ├── Mantenimiento (solo ver)
-- ├── Inventario (solo ver)
-- ├── Abastecimiento (solo ver)
-- ├── Cumplimiento
-- ├── KPI
-- ├── ICEO
-- ├── Reportes
-- ├── Auditoría
-- └── Administración (solo ver)
-- Flujo demo: dashboard ejecutivo → ICEO → KPI drill-down → reportes
--
-- ADMINISTRADOR (tu usuario actual):
-- └── TODO (acceso completo)
--
-- ============================================================================
