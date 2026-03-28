-- 017_reset_ventas_rpc.sql
-- Procedimiento seguro para limpiar ventas y venta_items sin tocar configuraciones.

CREATE OR REPLACE FUNCTION public.reset_ventas()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Limpia tablas transaccionales
  IF to_regclass('public.venta_items') IS NOT NULL THEN
    TRUNCATE TABLE public.venta_items CASCADE;
  END IF;

  IF to_regclass('public.ventas') IS NOT NULL THEN
    TRUNCATE TABLE public.ventas CASCADE;
  END IF;

  -- Opcional: resetear correlativos de serie en supabase si se usan allí
  IF to_regclass('public.correlativos') IS NOT NULL THEN
    UPDATE public.correlativos SET last = 0, updated_at = now();
  END IF;

  -- Nota: NO toca empresa_config ni configuraciones de branding.
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_ventas() TO authenticated;
