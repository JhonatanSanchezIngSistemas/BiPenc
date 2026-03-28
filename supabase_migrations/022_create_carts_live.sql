-- 022_create_carts_live.sql
-- Tabla para monitoreo de carritos en vivo (Admin)

CREATE TABLE IF NOT EXISTS public.carts_live (
  user_id uuid PRIMARY KEY,
  alias text,
  rol text,
  device_id text,
  active_cart_index int,
  active_cart_total numeric(12,2),
  active_cart_items_count int,
  carts jsonb DEFAULT '[]'::jsonb,
  items_preview jsonb DEFAULT '[]'::jsonb,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.carts_live ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS carts_live_upsert_own ON public.carts_live;
CREATE POLICY carts_live_upsert_own ON public.carts_live
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS carts_live_update_own ON public.carts_live;
CREATE POLICY carts_live_update_own ON public.carts_live
  FOR UPDATE
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS carts_live_select_admin ON public.carts_live;
CREATE POLICY carts_live_select_admin ON public.carts_live
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.perfiles p
      WHERE p.id = auth.uid() AND p.rol = 'ADMIN'
    )
  );
