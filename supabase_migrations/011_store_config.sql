-- 011_store_config.sql
-- Crea configuración global de tienda (versión mínima + IGV)
-- para evitar PGRST205 en ConfigService/SupabaseService.

CREATE TABLE IF NOT EXISTS public.store_config (
  id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  min_version text,
  igv_rate numeric(6,4) NOT NULL DEFAULT 0.18,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS store_config_singleton_idx ON public.store_config ((true));

CREATE OR REPLACE FUNCTION public.touch_store_config_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_store_config_updated_at ON public.store_config;
CREATE TRIGGER trg_store_config_updated_at
BEFORE UPDATE ON public.store_config
FOR EACH ROW
EXECUTE FUNCTION public.touch_store_config_updated_at();

-- Semilla singleton
INSERT INTO public.store_config (min_version, igv_rate)
SELECT '1.0.0', 0.18
WHERE NOT EXISTS (SELECT 1 FROM public.store_config);

ALTER TABLE public.store_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS store_config_read_authenticated ON public.store_config;
CREATE POLICY store_config_read_authenticated
  ON public.store_config
  FOR SELECT
  TO authenticated
  USING (true);
