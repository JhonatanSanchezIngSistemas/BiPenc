-- 010_fix_perfiles_rls_recursion.sql
-- Corrige error 42P17: "infinite recursion detected in policy for relation perfiles".
-- Estrategia:
-- 1) Eliminar TODAS las policies existentes sobre public.perfiles (incluidas las creadas manualmente).
-- 2) Crear policies no recursivas que no consulten la misma tabla en USING/WITH CHECK.

ALTER TABLE IF EXISTS public.perfiles ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  p record;
BEGIN
  FOR p IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'perfiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.perfiles', p.policyname);
  END LOOP;
END$$;

-- Helper lógico repetido:
-- usuario_admin := JWT role == ADMIN (custom claim o app_metadata.role)
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    COALESCE(auth.jwt() ->> 'role', '') = 'ADMIN'
    OR COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'ADMIN';
$$;

CREATE POLICY perfiles_select_policy
  ON public.perfiles
  FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
    OR public.is_admin()
  );

CREATE POLICY perfiles_insert_policy
  ON public.perfiles
  FOR INSERT
  TO authenticated
  WITH CHECK (
    id = auth.uid()
    OR public.is_admin()
  );

CREATE POLICY perfiles_update_policy
  ON public.perfiles
  FOR UPDATE
  TO authenticated
  USING (
    id = auth.uid()
    OR public.is_admin()
  )
  WITH CHECK (
    id = auth.uid()
    OR public.is_admin()
  );

CREATE POLICY perfiles_delete_policy
  ON public.perfiles
  FOR DELETE
  TO authenticated
  USING (
    id = auth.uid()
    OR public.is_admin()
  );
