-- ============================================================================
-- SICOM-ICEO | 143 — Categorías de productos editables (catálogo administrable)
-- ----------------------------------------------------------------------------
-- El CHECK rígido chk_productos_categoria solo permitía 6 categorías. Se
-- reemplaza por un catálogo editable `producto_categorias` (admin puede agregar/
-- renombrar/desactivar), enlazado por FK. Se siembra con las 6 actuales +
-- "Artículos de ferretería". IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS producto_categorias (
    codigo      VARCHAR(40) PRIMARY KEY,             -- slug guardado en productos.categoria
    nombre      VARCHAR(100) NOT NULL,               -- nombre visible/editable
    activo      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO producto_categorias (codigo, nombre) VALUES
    ('combustible', 'Combustible'),
    ('lubricante',  'Lubricante'),
    ('filtro',      'Filtro'),
    ('repuesto',    'Repuesto'),
    ('consumible',  'Consumible'),
    ('epp',         'EPP'),
    ('ferreteria',  'Artículos de ferretería')
ON CONFLICT (codigo) DO NOTHING;

-- Reemplazar el CHECK rígido por una FK al catálogo (editable).
ALTER TABLE productos DROP CONSTRAINT IF EXISTS chk_productos_categoria;
ALTER TABLE productos DROP CONSTRAINT IF EXISTS fk_productos_categoria;
ALTER TABLE productos ADD CONSTRAINT fk_productos_categoria
    FOREIGN KEY (categoria) REFERENCES producto_categorias(codigo) ON UPDATE CASCADE;

-- RLS: lectura para todos; escritura para roles de gestión.
ALTER TABLE producto_categorias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_prodcat_sel ON producto_categorias;
CREATE POLICY pol_prodcat_sel ON producto_categorias FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_prodcat_wr ON producto_categorias;
CREATE POLICY pol_prodcat_wr ON producto_categorias FOR ALL TO authenticated
    USING (fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento'));

SELECT (SELECT count(*) FROM producto_categorias) AS categorias,
       (SELECT count(*) FROM pg_constraint WHERE conname='fk_productos_categoria') AS fk_ok,
       (SELECT count(*) FROM pg_constraint WHERE conname='chk_productos_categoria') AS check_viejo;
