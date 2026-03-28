-- rollback_all.sql
-- Script de rollback para deshacer los cambios aplicados por los migrations.
-- Úsalo con cuidado; revisa antes de ejecutar en producción.

-- Eliminar triggers de auditoría
DO $$
DECLARE
  tbl text;
  tablas text[] := ARRAY['ventas','venta_items','productos','print_queue'];
BEGIN
  FOREACH tbl IN ARRAY tablas LOOP
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=tbl) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS audit_trigger ON public.%I', tbl);
    END IF;
  END LOOP;
END$$;

-- Eliminar function audit_if_changes si existe
DROP FUNCTION IF EXISTS public.audit_if_changes();

-- Eliminar audit_log
DROP TABLE IF EXISTS public.audit_log;

-- Eliminar correlativos y función
DROP FUNCTION IF EXISTS public.generar_siguiente_correlativo(text);
DROP TABLE IF EXISTS public.correlativos;

-- Eliminar carts_live
DROP TABLE IF EXISTS public.carts_live;
-- Eliminar flag live_carts_enabled
ALTER TABLE IF EXISTS public.store_config
  DROP COLUMN IF EXISTS live_carts_enabled;

-- Eliminar RPC de inserción atómica de ventas
DROP FUNCTION IF EXISTS public.insert_venta_with_items(
  text, text, text, jsonb, jsonb, numeric, numeric, numeric, numeric, text,
  text, text, text, boolean, uuid
);

-- Eliminar índices y constraints creados
DROP INDEX IF EXISTS ventas_created_at_idx;
DROP INDEX IF EXISTS venta_items_venta_id_idx;
DROP INDEX IF EXISTS productos_sku_idx;
ALTER TABLE IF EXISTS public.venta_items DROP CONSTRAINT IF EXISTS venta_items_cantidad_positive;
ALTER TABLE IF EXISTS public.venta_items DROP CONSTRAINT IF EXISTS fk_venta_items_venta;

-- Eliminar policies (nota: deberías revisar políticas manualmente si tienes otras existentes)
-- Policies creadas en 001_rls_and_policies.sql usan nombres: productos_select_public, productos_modify_admin, ventas_owner_policy, venta_items_owner_policy, print_queue_insert_auth
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'productos_select_public') THEN
    ALTER TABLE public.productos DISABLE ROW LEVEL SECURITY;
    DELETE FROM pg_policy WHERE polname = 'productos_select_public';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'productos_modify_admin') THEN
    DELETE FROM pg_policy WHERE polname = 'productos_modify_admin';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'ventas_owner_policy') THEN
    DELETE FROM pg_policy WHERE polname = 'ventas_owner_policy';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'venta_items_owner_policy') THEN
    DELETE FROM pg_policy WHERE polname = 'venta_items_owner_policy';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'print_queue_insert_auth') THEN
    DELETE FROM pg_policy WHERE polname = 'print_queue_insert_auth';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'document_cache_auth') THEN
    ALTER TABLE public.document_cache DISABLE ROW LEVEL SECURITY;
    DELETE FROM pg_policy WHERE polname = 'document_cache_auth';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'carts_live_upsert_own') THEN
    DELETE FROM pg_policy WHERE polname = 'carts_live_upsert_own';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'carts_live_update_own') THEN
    DELETE FROM pg_policy WHERE polname = 'carts_live_update_own';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'carts_live_select_admin') THEN
    DELETE FROM pg_policy WHERE polname = 'carts_live_select_admin';
  END IF;
END$$;

\echo 'Rollback completed. Review policies and RLS state manually.'
