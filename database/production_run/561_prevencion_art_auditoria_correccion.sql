-- ============================================================================
-- MIG561 · Prevención: ART del supervisor + auditoría de prevención + corrección
-- ============================================================================
-- Manuel (2026-09-14), tres pedidos:
--   1. Los supervisores deben poder subir sus ART (Análisis de Riesgo del
--      Trabajo) — herramienta preventiva SAFEWORK (punto 5.7 del Anexo 10.2).
--      Tipo nuevo ART, ofrecido en las dos Lomas (las demás faenas mapeadas
--      conservan su catálogo del mandante; agregar ART a otra = un INSERT).
--   2. Todo lo que suben los supervisores lo AUDITA prevención: columnas de
--      revisión en prevencion_registros. El prevencionista (admin del módulo
--      por fn_prevencion_reporta_puede_admin) marca revisado vía la política
--      de UPDATE existente; el panel muestra la marca y la observación.
--   3. El supervisor puede CORREGIR si se equivocó: editar ya podía (política
--      de UPDATE: autor con registro abierto o < 24 h); faltaba poder BORRAR
--      lo propio recién cargado — se abre DELETE al autor dentro de 24 h.
-- ============================================================================

BEGIN;

-- ── 1. Tipo ART, ofrecido en las dos Lomas ──────────────────────────────────
INSERT INTO prevencion_actividad_tipos (codigo, nombre, descripcion, requiere_cierre, orden)
VALUES ('ART', 'ART',
        'Análisis de Riesgo del Trabajo — herramienta preventiva diaria (SAFEWORK).',
        false, 105)
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO prevencion_faena_tipos (faena_id, tipo_codigo)
SELECT f.id, 'ART'
  FROM faenas f
 WHERE f.codigo IN ('FAE-LOMASBAYAS', 'FAE-LOMASBAYAS-LUB')
ON CONFLICT DO NOTHING;

-- ── 2. Auditoría de prevención sobre lo cargado ─────────────────────────────
ALTER TABLE prevencion_registros
    ADD COLUMN IF NOT EXISTS revisado             BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS revisado_por         UUID REFERENCES auth.users(id),
    ADD COLUMN IF NOT EXISTS revisado_at          TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS revision_observacion TEXT;

COMMENT ON COLUMN prevencion_registros.revisado IS
    'Prevención auditó este registro (MIG561). La marca la pone un rol admin del módulo; la observación vuelve al supervisor en /m/prevencion.';

-- ── 3. El autor puede borrar lo suyo dentro de 24 h ─────────────────────────
DROP POLICY IF EXISTS prev_reg_delete ON prevencion_registros;
CREATE POLICY prev_reg_delete ON prevencion_registros
    FOR DELETE TO authenticated
    USING (
        fn_prevencion_reporta_puede_admin()
        OR (creado_por = auth.uid() AND created_at > now() - interval '24 hours')
    );

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT f.codigo, string_agg(ft.tipo_codigo, ', ' ORDER BY t.orden) AS tipos
FROM prevencion_faena_tipos ft
JOIN faenas f ON f.id = ft.faena_id
JOIN prevencion_actividad_tipos t ON t.codigo = ft.tipo_codigo
WHERE f.codigo LIKE 'FAE-LOMASBAYAS%'
GROUP BY f.codigo;

SELECT column_name FROM information_schema.columns
WHERE table_name = 'prevencion_registros' AND column_name LIKE 'revis%';
