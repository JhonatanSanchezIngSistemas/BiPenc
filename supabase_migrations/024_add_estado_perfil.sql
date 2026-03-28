-- 024_add_estado_perfil.sql
-- Agrega columna de estado a perfiles para permitir desactivar usuarios.

ALTER TABLE IF EXISTS public.perfiles
  ADD COLUMN IF NOT EXISTS estado text NOT NULL DEFAULT 'ACTIVO';

-- Opcional: normalizar valores existentes
UPDATE public.perfiles
SET estado = 'ACTIVO'
WHERE estado IS NULL OR estado = '';
