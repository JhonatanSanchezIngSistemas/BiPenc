-- 019_global_updates_latest.sql
-- Objetivo: Sincronizar el esquema de Supabase con los últimos features
-- añadidos a la app (estado SUNAT, anulaciones, identity compartida de códigos).

BEGIN;

-- 1. Añadir columnas de control de estado y anulación a la tabla ventas
ALTER TABLE IF EXISTS public.ventas
  ADD COLUMN IF NOT EXISTS app_version TEXT,
  ADD COLUMN IF NOT EXISTS estado TEXT DEFAULT 'PENDIENTE',
  ADD COLUMN IF NOT EXISTS estado_sunat TEXT DEFAULT 'PENDIENTE',
  ADD COLUMN IF NOT EXISTS error_msg TEXT,
  ADD COLUMN IF NOT EXISTS anulado BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS anulado_motivo TEXT,
  ADD COLUMN IF NOT EXISTS anulado_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS anulado_por TEXT;

-- 2. Asegurar que la tabla puente producto_codigos exista
-- (Esto permite que múltiples productos compartan un mismo código de barras)
CREATE TABLE IF NOT EXISTS public.producto_codigos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_barras text NOT NULL,
  producto_sku text REFERENCES public.productos(sku) ON DELETE CASCADE,
  descripcion_variante text,
  creado_en timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_producto_codigos_barcode ON public.producto_codigos(codigo_barras);

-- Políticas RLS para producto_codigos (todos pueden leer y escribir temporalmente mientras estén autenticados)
ALTER TABLE public.producto_codigos ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'producto_codigos' AND policyname = 'Permitir todo a usuarios autenticados en producto_codigos'
    ) THEN
        CREATE POLICY "Permitir todo a usuarios autenticados en producto_codigos" 
        ON public.producto_codigos FOR ALL TO authenticated USING (true);
    END IF;
END
$$;

COMMIT;
