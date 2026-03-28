-- 002_indexes_constraints.sql
-- Añade índices, constraints y tabla de correlativos para generar números consecutivos.

-- Tabla correlativos para mantener el último número por punto de venta / tienda
CREATE TABLE IF NOT EXISTS public.correlativos (
  id serial PRIMARY KEY,
  scope text NOT NULL, -- p.ej. store_id o tipo de documento
  last bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS correlativos_scope_idx ON public.correlativos(scope);

-- Índices recomendados para rendimiento en búsquedas y joins
CREATE INDEX IF NOT EXISTS ventas_created_at_idx ON public.ventas(created_at);
CREATE INDEX IF NOT EXISTS venta_items_venta_id_idx ON public.venta_items(venta_id);
CREATE INDEX IF NOT EXISTS productos_sku_idx ON public.productos(sku);

-- Constraints ejemplo: asegurar que venta_items tenga cantidad positiva
ALTER TABLE IF EXISTS public.venta_items
  ADD CONSTRAINT IF NOT EXISTS venta_items_cantidad_positive CHECK (cantidad > 0);

-- Asegurar integridad referencial (si las tablas existen)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='venta_items')
  THEN
    BEGIN
      ALTER TABLE public.venta_items
        ADD CONSTRAINT IF NOT EXISTS fk_venta_items_venta FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON DELETE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END;
  END IF;
END$$;
