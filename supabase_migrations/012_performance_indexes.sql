-- 012_performance_indexes.sql
-- Índices de rendimiento para consultas frecuentes en producción:
-- - Búsqueda por correlativo de boleta
-- - Listado reciente de ventas
-- - Búsqueda de productos por SKU/nombre/marca
-- - Barrido de colas de sincronización

DO $$
BEGIN
  IF to_regclass('public.ventas') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_ventas_correlativo ON public.ventas(correlativo)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_ventas_created_at ON public.ventas(created_at DESC)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_ventas_tipo_cod ON public.ventas(tipo_comprobante_cod)';
  END IF;
END$$;

DO $$
BEGIN
  IF to_regclass('public.productos') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_productos_sku ON public.productos(sku)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_productos_nombre ON public.productos(nombre)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_productos_marca ON public.productos(marca)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_productos_categoria ON public.productos(categoria)';
  END IF;
END$$;

DO $$
BEGIN
  IF to_regclass('public.sync_queue_v2') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sync_v2_estado_intentos ON public.sync_queue_v2(sincronizado, intentos)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sync_v2_created_at ON public.sync_queue_v2(created_at DESC)';
  END IF;
END$$;

