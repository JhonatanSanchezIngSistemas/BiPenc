-- 018_link_pedido_venta.sql
-- Vincula ventas con order_lists y persiste correlativo_comprobante para trazabilidad completa.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- A) Nuevas columnas y constraints
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.order_lists
  ADD COLUMN IF NOT EXISTS correlativo_comprobante TEXT,
  ALTER COLUMN estado DROP DEFAULT,
  DROP CONSTRAINT IF EXISTS order_lists_estado_check,
  ADD CONSTRAINT order_lists_estado_check
    CHECK (
      estado IN (
        'PENDIENTE',
        'LISTO',
        'ENTREGADO',
        'CANCELADO',
        'COMPLETADO',
        'PENDIENTE_REGISTRO',
        'REGISTRANDO'
      )
    ),
  ALTER COLUMN estado SET DEFAULT 'PENDIENTE';

ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS order_list_id uuid
    REFERENCES public.order_lists(id) ON UPDATE CASCADE ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ventas_order_list_id
  ON public.ventas(order_list_id);

CREATE INDEX IF NOT EXISTS idx_order_lists_correlativo
  ON public.order_lists(correlativo_comprobante);

-- ─────────────────────────────────────────────────────────────────────────────
-- B) Trigger: al guardar/actualizar venta con order_list_id, marca pedido como completado
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_mark_order_completed()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.order_list_id IS NOT NULL THEN
    UPDATE public.order_lists
       SET estado = 'COMPLETADO',
           correlativo_comprobante = COALESCE(
             NEW.correlativo,
             NEW.id::text,
             correlativo_comprobante
           ),
           updated_at = now()
     WHERE id = NEW.order_list_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_order_from_venta ON public.ventas;
CREATE TRIGGER trg_set_order_from_venta
AFTER INSERT OR UPDATE OF order_list_id, correlativo ON public.ventas
FOR EACH ROW EXECUTE FUNCTION public.trg_mark_order_completed();

COMMIT;
