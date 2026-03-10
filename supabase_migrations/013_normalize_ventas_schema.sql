-- 013_normalize_ventas_schema.sql
-- Objetivo:
-- 1) Normalizar esquema de public.ventas para boletas/facturas.
-- 2) Mantener compatibilidad temporal entre documento_cliente / dni_cliente / dni_ruc.
-- 3) Reducir errores PGRST204/PGRST205 por drift de columnas.

BEGIN;

-- ---------------------------------------------------------------------------
-- A) Columnas canónicas y de compatibilidad
-- ---------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.ventas
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS correlativo TEXT,
  ADD COLUMN IF NOT EXISTS serie TEXT DEFAULT 'B001',
  ADD COLUMN IF NOT EXISTS tipo_comprobante_cod TEXT DEFAULT '03',
  ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS subtotal NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS operacion_gravada NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS igv NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS total NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS metodo_pago TEXT DEFAULT 'EFECTIVO',
  ADD COLUMN IF NOT EXISTS alias_vendedor TEXT,
  ADD COLUMN IF NOT EXISTS nombre_cliente TEXT,
  ADD COLUMN IF NOT EXISTS documento_cliente TEXT,
  ADD COLUMN IF NOT EXISTS dni_cliente TEXT,
  ADD COLUMN IF NOT EXISTS dni_ruc TEXT,
  ADD COLUMN IF NOT EXISTS tipo_documento TEXT,
  ADD COLUMN IF NOT EXISTS despachado BOOLEAN DEFAULT FALSE;

-- ---------------------------------------------------------------------------
-- B) Backfill de documento y datos fiscales
-- ---------------------------------------------------------------------------
UPDATE public.ventas
SET documento_cliente = COALESCE(
  NULLIF(documento_cliente, ''),
  NULLIF(dni_cliente, ''),
  NULLIF(dni_ruc, '')
)
WHERE COALESCE(NULLIF(documento_cliente, ''), NULLIF(dni_cliente, ''), NULLIF(dni_ruc, '')) IS NOT NULL;

UPDATE public.ventas
SET dni_cliente = COALESCE(NULLIF(dni_cliente, ''), NULLIF(documento_cliente, ''), NULLIF(dni_ruc, ''))
WHERE COALESCE(NULLIF(dni_cliente, ''), NULLIF(documento_cliente, ''), NULLIF(dni_ruc, '')) IS NOT NULL;

UPDATE public.ventas
SET dni_ruc = COALESCE(NULLIF(dni_ruc, ''), NULLIF(documento_cliente, ''), NULLIF(dni_cliente, ''))
WHERE COALESCE(NULLIF(dni_ruc, ''), NULLIF(documento_cliente, ''), NULLIF(dni_cliente, '')) IS NOT NULL;

UPDATE public.ventas
SET tipo_documento = CASE
  WHEN length(regexp_replace(COALESCE(documento_cliente, ''), '\D', '', 'g')) = 11 THEN 'RUC'
  WHEN length(regexp_replace(COALESCE(documento_cliente, ''), '\D', '', 'g')) = 8 THEN 'DNI'
  ELSE tipo_documento
END
WHERE COALESCE(documento_cliente, '') <> '';

-- ---------------------------------------------------------------------------
-- C) Trigger de compatibilidad de documento (bidireccional simple)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_ventas_documento_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  doc TEXT;
BEGIN
  doc := COALESCE(
    NULLIF(NEW.documento_cliente, ''),
    NULLIF(NEW.dni_cliente, ''),
    NULLIF(NEW.dni_ruc, '')
  );

  NEW.documento_cliente := doc;
  NEW.dni_cliente := doc;
  NEW.dni_ruc := doc;

  IF doc IS NOT NULL THEN
    IF length(regexp_replace(doc, '\D', '', 'g')) = 11 THEN
      NEW.tipo_documento := COALESCE(NEW.tipo_documento, 'RUC');
    ELSIF length(regexp_replace(doc, '\D', '', 'g')) = 8 THEN
      NEW.tipo_documento := COALESCE(NEW.tipo_documento, 'DNI');
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_ventas_documento_fields ON public.ventas;
CREATE TRIGGER trg_sync_ventas_documento_fields
BEFORE INSERT OR UPDATE ON public.ventas
FOR EACH ROW
EXECUTE FUNCTION public.sync_ventas_documento_fields();

-- ---------------------------------------------------------------------------
-- D) Defaults y constraints de consistencia básica
-- ---------------------------------------------------------------------------
ALTER TABLE public.ventas
  ALTER COLUMN serie SET DEFAULT 'B001',
  ALTER COLUMN tipo_comprobante_cod SET DEFAULT '03',
  ALTER COLUMN metodo_pago SET DEFAULT 'EFECTIVO',
  ALTER COLUMN despachado SET DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ventas_tipo_comprobante_cod_chk'
      AND conrelid = 'public.ventas'::regclass
  ) THEN
    ALTER TABLE public.ventas
      ADD CONSTRAINT ventas_tipo_comprobante_cod_chk
      CHECK (tipo_comprobante_cod IN ('01', '03')) NOT VALID;
  END IF;
END$$;

-- ---------------------------------------------------------------------------
-- E) Índices funcionales para búsqueda/reimpresión/sync
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_ventas_correlativo_v2 ON public.ventas (correlativo);
CREATE INDEX IF NOT EXISTS idx_ventas_created_at_v2 ON public.ventas (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ventas_alias_vendedor_v2 ON public.ventas (alias_vendedor);
CREATE INDEX IF NOT EXISTS idx_ventas_documento_cliente_v2 ON public.ventas (documento_cliente);

COMMIT;

