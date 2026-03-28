-- Crea tabla venta_items si no existe (compatibilidad PGRST204)
CREATE TABLE IF NOT EXISTS public.venta_items (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  venta_id uuid REFERENCES public.ventas(id),
  producto_id text,
  presentacion_id text,
  cantidad numeric(12,2),
  precio_unitario numeric(12,2),
  subtotal numeric(12,2),
  precio_override numeric(12,2),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.venta_items ENABLE ROW LEVEL SECURITY;

-- Basic Policy (Allow all for now, following project style)
DROP POLICY IF EXISTS "Allow all on venta_items" ON public.venta_items;
CREATE POLICY "Allow all on venta_items" ON public.venta_items FOR ALL USING (true);

CREATE INDEX IF NOT EXISTS idx_venta_items_venta_id ON public.venta_items(venta_id);
