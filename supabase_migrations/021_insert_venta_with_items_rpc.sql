-- 021_insert_venta_with_items_rpc.sql
-- Inserta venta + items en una sola transacción (atomicidad).

BEGIN;

CREATE OR REPLACE FUNCTION public.insert_venta_with_items(
  p_correlativo text,
  p_serie text,
  p_tipo_comprobante_cod text,
  p_items jsonb,
  p_items_norm jsonb,
  p_total numeric,
  p_subtotal numeric,
  p_operacion_gravada numeric,
  p_igv numeric,
  p_nombre_cliente text,
  p_dni_cliente text,
  p_alias_vendedor text,
  p_metodo_pago text,
  p_despachado boolean,
  p_order_list_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_venta_id uuid;
BEGIN
  INSERT INTO public.ventas(
    correlativo,
    serie,
    tipo_comprobante_cod,
    items,
    total,
    subtotal,
    operacion_gravada,
    igv,
    nombre_cliente,
    documento_cliente,
    dni_cliente,
    alias_vendedor,
    metodo_pago,
    despachado,
    order_list_id
  ) VALUES (
    p_correlativo,
    COALESCE(p_serie, 'B001'),
    COALESCE(p_tipo_comprobante_cod, '03'),
    COALESCE(p_items, '[]'::jsonb),
    p_total,
    p_subtotal,
    p_operacion_gravada,
    p_igv,
    p_nombre_cliente,
    p_dni_cliente,
    p_dni_cliente,
    p_alias_vendedor,
    COALESCE(p_metodo_pago, 'EFECTIVO'),
    COALESCE(p_despachado, false),
    p_order_list_id
  )
  RETURNING id INTO v_venta_id;

  IF p_items_norm IS NOT NULL THEN
    INSERT INTO public.venta_items(
      venta_id,
      producto_id,
      presentacion_id,
      cantidad,
      precio_unitario,
      subtotal,
      precio_override
    )
    SELECT
      v_venta_id,
      NULLIF(item->>'producto_id','')::text,
      NULLIF(item->>'presentacion_id','')::text,
      NULLIF(item->>'cantidad','')::numeric,
      NULLIF(item->>'precio_unitario','')::numeric,
      NULLIF(item->>'subtotal','')::numeric,
      NULLIF(item->>'precio_override','')::numeric
    FROM jsonb_array_elements(COALESCE(p_items_norm, '[]'::jsonb)) AS item;
  END IF;

  RETURN v_venta_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_venta_with_items(
  text,
  text,
  text,
  jsonb,
  jsonb,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  boolean,
  uuid
) TO authenticated;

COMMIT;
