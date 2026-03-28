-- 006_order_lists.sql
-- Tabla para registrar listas de pedidos (preventa) con fotos, montos adelantados y fechas de recojo.

CREATE TABLE public.order_lists (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  alias_vendedor   text        REFERENCES public.perfiles(alias) ON UPDATE CASCADE,
  cliente_nombre   text,
  cliente_telefono text,
  items            jsonb       NOT NULL DEFAULT '[]',
  total_estimado   numeric(10,2) NOT NULL DEFAULT 0,
  monto_adelantado numeric(10,2) NOT NULL DEFAULT 0,
  fecha_recojo     date,
  fotos_urls       text[]      NOT NULL DEFAULT '{}',
  estado           text        NOT NULL DEFAULT 'PENDIENTE'
                               CHECK (estado IN ('PENDIENTE','LISTO','ENTREGADO','CANCELADO')),
  notas            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Índices de búsqueda frecuente
CREATE INDEX order_lists_alias_idx        ON public.order_lists(alias_vendedor);
CREATE INDEX order_lists_fecha_recojo_idx ON public.order_lists(fecha_recojo);
CREATE INDEX order_lists_estado_idx       ON public.order_lists(estado);

-- Trigger de actualización automática de updated_at
CREATE TRIGGER order_lists_updated_at
  BEFORE UPDATE ON public.order_lists
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ── RLS ──────────────────────────────────────────────────────────────
ALTER TABLE public.order_lists ENABLE ROW LEVEL SECURITY;

-- Vendedor: ve y gestiona sus propios pedidos
CREATE POLICY "vendedor_ve_sus_pedidos"
  ON public.order_lists FOR SELECT TO authenticated
  USING (
    alias_vendedor = (
      SELECT alias FROM public.perfiles WHERE id = auth.uid() LIMIT 1
    )
  );

CREATE POLICY "vendedor_inserta_pedidos"
  ON public.order_lists FOR INSERT TO authenticated
  WITH CHECK (
    alias_vendedor = (
      SELECT alias FROM public.perfiles WHERE id = auth.uid() LIMIT 1
    )
  );

CREATE POLICY "vendedor_actualiza_sus_pedidos"
  ON public.order_lists FOR UPDATE TO authenticated
  USING (
    alias_vendedor = (
      SELECT alias FROM public.perfiles WHERE id = auth.uid() LIMIT 1
    )
  );

-- Admin: acceso total (rol_usuario solo tiene 'ADMIN' y 'USER')
CREATE POLICY "admin_todos_pedidos"
  ON public.order_lists FOR ALL TO authenticated
  USING (
    (SELECT rol FROM public.perfiles WHERE id = auth.uid() LIMIT 1)::text = 'ADMIN'
  );
