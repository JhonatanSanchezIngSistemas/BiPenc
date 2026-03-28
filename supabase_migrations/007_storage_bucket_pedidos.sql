-- 007_storage_bucket_pedidos.sql
-- Crea el bucket 'pedidos' como público y configura las políticas de Storage.

-- 1. Crear el bucket como público
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pedidos',
  'pedidos',
  true,                          -- público: URLs accesibles sin token
  10485760,                      -- límite 10 MB por foto
  ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/heic']
)
ON CONFLICT (id) DO UPDATE
  SET public = true,
      file_size_limit = 10485760,
      allowed_mime_types = ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/heic'];

-- 2. Política: usuarios autenticados pueden subir (INSERT) imágenes
CREATE POLICY "pedidos_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'pedidos');

-- 3. Política: lectura pública (bucket público, pero la policy explícita es buena práctica)
CREATE POLICY "pedidos_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'pedidos');

-- 4. Política: el propietario puede actualizar/eliminar su propia imagen
CREATE POLICY "pedidos_update_owner"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'pedidos' AND owner_id::text = auth.uid()::text);

CREATE POLICY "pedidos_delete_owner"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'pedidos' AND owner_id::text = auth.uid()::text);
