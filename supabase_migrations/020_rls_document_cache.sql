-- 020_rls_document_cache.sql
-- Habilita RLS en document_cache (datos sensibles) y permite acceso a usuarios autenticados.

ALTER TABLE IF EXISTS public.document_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy WHERE polname = 'document_cache_auth'
  ) THEN
    CREATE POLICY document_cache_auth ON public.document_cache
      FOR ALL TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END$$;
