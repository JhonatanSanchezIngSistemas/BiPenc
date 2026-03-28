-- 001_rls_and_policies.sql
-- Habilita RLS y agrega políticas mínimas por tabla.
-- Revisa y adapta `owner` / `store_id` según tu esquema real.

-- Habilitar RLS en tablas críticas
ALTER TABLE IF EXISTS public.productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.venta_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.print_queue ENABLE ROW LEVEL SECURITY;

-- Políticas ejemplo: permitir SELECT público para productos (catálogo),
-- y operaciones restringidas a usuario autenticado (owner) o a claims del JWT.

-- Productos: lectura pública, modificación sólo por usuarios con claim 'role' = 'admin'
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'productos_select_public'
  ) THEN
    CREATE POLICY productos_select_public ON public.productos
      FOR SELECT USING (true);
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'productos_modify_admin'
  ) THEN
    CREATE POLICY productos_modify_admin ON public.productos
      FOR ALL TO authenticated USING (
        current_setting('jwt.claims.role', true) = 'admin'
      ) WITH CHECK (
        current_setting('jwt.claims.role', true) = 'admin'
      );
  END IF;
END$$;

-- Ventas y venta_items: lectura y escritura permitida sólo al creator o a servicios internos
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'ventas_owner_policy'
  ) THEN
    CREATE POLICY ventas_owner_policy ON public.ventas
      FOR ALL TO authenticated USING (
        -- permitir select/update/delete sólo si el claim sub (uid) coincide con created_by
        (created_by IS NOT NULL AND created_by = auth.uid())
        OR current_setting('jwt.claims.role', true) = 'admin'
      ) WITH CHECK (
        (created_by IS NOT NULL AND created_by = auth.uid())
        OR current_setting('jwt.claims.role', true) = 'admin'
      );
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'venta_items_owner_policy'
  ) THEN
    CREATE POLICY venta_items_owner_policy ON public.venta_items
      FOR ALL TO authenticated USING (
        (venta_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.ventas v WHERE v.id = venta_id AND v.created_by = auth.uid()))
        OR current_setting('jwt.claims.role', true) = 'admin'
      ) WITH CHECK (
        (venta_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.ventas v WHERE v.id = venta_id AND v.created_by = auth.uid()))
        OR current_setting('jwt.claims.role', true) = 'admin'
      );
  END IF;
END$$;

-- Print queue: sólo lectura por UI; creación permitida por usuarios autenticados
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'print_queue_insert_auth'
  ) THEN
    CREATE POLICY print_queue_insert_auth ON public.print_queue
      FOR INSERT TO authenticated WITH CHECK (true);
  END IF;
END$$;

-- Nota: estas políticas son ejemplos. Ajusta columnas (created_by, owner, store_id)
-- y las claims usadas en JWT según cómo generes tokens en Supabase Auth.
