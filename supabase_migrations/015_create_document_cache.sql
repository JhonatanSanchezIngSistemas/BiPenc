-- Crea cache compartido DNI/RUC en Supabase (compatible con el cliente)
CREATE TABLE IF NOT EXISTS public.document_cache (
  numero      TEXT PRIMARY KEY,
  tipo        TEXT NOT NULL,
  nombre      TEXT NOT NULL,
  direccion   TEXT,
  cached_at   BIGINT NOT NULL,
  expires_at  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_document_cache_expires_supabase
  ON public.document_cache(expires_at);
