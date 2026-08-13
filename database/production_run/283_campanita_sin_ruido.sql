-- ============================================================================
-- SICOM-ICEO | 283 — Que la campanita vuelva a servir
-- ============================================================================
-- Ricardo: "tampoco me llegan las alertas de solicitudes de repuestos".
--
-- Sí le llegan. Tiene 11 esperando aprobación. El problema es que están
-- enterradas bajo 724 alertas sin leer — de las cuales solo 154 son asuntos
-- distintos. Los crones diarios vuelven a insertar la MISMA alerta cada
-- mañana: 304 avisos de OT vencida sobre las mismas OT, 352 de documentos.
-- Una campanita con 724 arriba no se abre nunca, y ahí adentro estaban las 11
-- que sí pedían una decisión suya.
--
-- Dos cambios:
--   1. Una alerta no se repite mientras la anterior siga sin leer. El aviso
--      diario sirve para enterarse, no para acumular.
--   2. Se distingue lo que ESPERA UNA DECISIÓN suya (aprobar un repuesto,
--      atender una no conformidad) de lo que solo informa (documentos por
--      vencer). La campanita cuenta lo primero.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Qué espera una decisión y qué solo informa ───────────────────────────
ALTER TABLE alertas ADD COLUMN IF NOT EXISTS requiere_accion BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN alertas.requiere_accion IS
    'La alerta espera una decisión del destinatario (aprobar, planificar), no solo informarlo. MIG283.';

CREATE OR REPLACE FUNCTION fn_alerta_requiere_accion(p_tipo TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT p_tipo IN (
        'recurso_solicitado',   -- el operador pide repuestos: el jefe aprueba
        'recurso_por_comprar',  -- aprobado sin stock: hay que comprarlo
        'recurso_recibido',     -- llegó: se puede continuar la OT
        'vale_emitido',         -- vale listo: bodega prepara la entrega
        'no_conformidad',       -- hallazgo nuevo: hay que planificarlo
        'bloqueante'            -- algo detiene el trabajo
    );
$$;

COMMENT ON FUNCTION fn_alerta_requiere_accion(TEXT) IS
    'Separa lo accionable de lo informativo en la campanita. MIG283.';


-- ── 2. Una alerta no se repite mientras la anterior siga sin leer ───────────
CREATE OR REPLACE FUNCTION fn_trg_alerta_sin_repetir()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    NEW.requiere_accion := fn_alerta_requiere_accion(NEW.tipo);

    -- El mismo asunto, al mismo destinatario, todavía sin leer: no se apila.
    -- Se refresca la fecha para que suba en la lista y se descarta el insert.
    IF NEW.entidad_id IS NOT NULL AND NOT COALESCE(NEW.leida, false) THEN
        UPDATE alertas
           SET created_at = COALESCE(NEW.created_at, now()),
               mensaje    = COALESCE(NEW.mensaje, mensaje),
               severidad  = NEW.severidad
         WHERE destinatario_id IS NOT DISTINCT FROM NEW.destinatario_id
           AND tipo = NEW.tipo
           AND entidad_id = NEW.entidad_id
           AND NOT leida;
        IF FOUND THEN RETURN NULL; END IF;
    END IF;

    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_alerta_sin_repetir ON alertas;
CREATE TRIGGER trg_alerta_sin_repetir
    BEFORE INSERT ON alertas
    FOR EACH ROW EXECUTE FUNCTION fn_trg_alerta_sin_repetir();


-- ── 3. Limpiar lo ya apilado ────────────────────────────────────────────────
-- De cada grupo repetido queda la más reciente; las demás se dan por leídas
-- (no se borran: la campanita las oculta, el histórico las conserva).
WITH ranked AS (
    SELECT id, row_number() OVER (
               PARTITION BY destinatario_id, tipo, entidad_id
               ORDER BY created_at DESC, id) AS rn
      FROM alertas
     WHERE NOT leida AND entidad_id IS NOT NULL
)
UPDATE alertas a
   SET leida = true, leida_en = now()
  FROM ranked r
 WHERE a.id = r.id AND r.rn > 1;

-- Y se clasifica lo que quedó.
UPDATE alertas SET requiere_accion = fn_alerta_requiere_accion(tipo)
 WHERE requiere_accion IS DISTINCT FROM fn_alerta_requiere_accion(tipo);

CREATE INDEX IF NOT EXISTS idx_alertas_pendientes
    ON alertas (destinatario_id, requiere_accion, created_at DESC) WHERE NOT leida;


SELECT 'MIG283 OK' AS resultado,
       count(*) FILTER (WHERE NOT leida AND requiere_accion)     AS jefe_por_decidir,
       count(*) FILTER (WHERE NOT leida AND NOT requiere_accion) AS jefe_informativas
  FROM alertas WHERE destinatario_id = 'b3e47022-488f-48b6-99f0-7d9e2648b2f3';
