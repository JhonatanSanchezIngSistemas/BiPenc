-- 023_add_live_carts_enabled.sql
-- Agrega flag de configuración para habilitar monitoreo de carritos en vivo

ALTER TABLE IF EXISTS public.store_config
  ADD COLUMN IF NOT EXISTS live_carts_enabled BOOLEAN DEFAULT FALSE;
