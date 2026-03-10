-- SUPABASE RLS IMPLEMENTATION
-- Ejecutar este script en: Supabase Dashboard > SQL Editor
-- ==================================================================================

-- 1. TABLA PERFILES: Solo el propietario + ADMIN
-- ==================================================================================
ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

-- Eliminar políticas existentes
DROP POLICY IF EXISTS "perfiles_owner" ON perfiles;
DROP POLICY IF EXISTS "perfiles_admin" ON perfiles;

-- Política: Cada usuario ve solo su perfil
CREATE POLICY "perfiles_owner" ON perfiles
  FOR ALL 
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Política: ADMIN ve todos los perfiles
CREATE POLICY "perfiles_admin" ON perfiles
  FOR ALL
  USING (
    (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  )
  WITH CHECK (
    (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  );

-- ==================================================================================
-- 2. TABLA VENTAS: Solo vendedores ven sus ventas, ADMIN ve todo
-- ==================================================================================
ALTER TABLE ventas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ventas_own" ON ventas;
DROP POLICY IF EXISTS "ventas_insert_own" ON ventas;
DROP POLICY IF EXISTS "ventas_admin" ON ventas;

-- Política: Vendedores ven sus propias ventas
CREATE POLICY "ventas_own" ON ventas
  FOR SELECT 
  USING (
    alias_vendedor = (
      SELECT alias FROM perfiles WHERE id = auth.uid()
    )
    OR (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  );

-- Política: Solo se pueden insertar propias ventas
CREATE POLICY "ventas_insert_own" ON ventas
  FOR INSERT 
  WITH CHECK (
    alias_vendedor = (
      SELECT alias FROM perfiles WHERE id = auth.uid()
    )
  );

-- Política: ADMIN full control
CREATE POLICY "ventas_admin_full" ON ventas
  FOR ALL
  USING (
    (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  )
  WITH CHECK (
    (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  );

-- ==================================================================================
-- 3. TABLA PRODUCTOS: Todos leen, solo ADMIN escribe
-- ==================================================================================
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "productos_read" ON productos;
DROP POLICY IF EXISTS "productos_write" ON productos;

-- Política: Todos leen productos
CREATE POLICY "productos_read" ON productos
  FOR SELECT 
  USING (true);

-- Política: Solo ADMIN inserta, actualiza, borra
CREATE POLICY "productos_write_admin" ON productos
  FOR INSERT, UPDATE, DELETE
  USING (
    (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  )
  WITH CHECK (
    (SELECT rol FROM perfiles WHERE id = auth.uid()) = 'ADMIN'
  );

-- ==================================================================================
-- 4. TABLA CATEGORÍAS: Todos leen
-- ==================================================================================
ALTER TABLE categorias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "categorias_read" ON categorias;

CREATE POLICY "categorias_read" ON categorias
  FOR SELECT 
  USING (true);

-- ==================================================================================
-- TESTING / VALIDACIÓN después de aplicar RLS
-- ==================================================================================

-- Login como VENTAS (rol = 'VENTAS'):
-- SELECT * FROM ventas;  → Debería ver solo SUS ventas
-- SELECT COUNT(*) FROM productos;  → Debería ver TODOS

-- Login como ADMIN (rol = 'ADMIN'):
-- SELECT * FROM ventas;  → Debería ver TODAS las ventas
-- UPDATE productos SET nombre = 'X' WHERE id = 'Y';  → OK

-- Login como VENTAS B intentando actualizar producto:
-- UPDATE productos SET nombre = 'Hack' WHERE id = 'X';  → DENIED

-- ==================================================================================
-- AUDITORÍA: Crear tabla de audit log (RECOMENDADO)
-- ==================================================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  tabla TEXT NOT NULL,
  accion TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
  usuario_id UUID NOT NULL,
  datos_antes JSONB,
  datos_despues JSONB,
  creado_at TIMESTAMP DEFAULT NOW(),
  
  FOREIGN KEY (usuario_id) REFERENCES perfiles(id) ON DELETE CASCADE
);

-- Trigger para registrar cambios en ventas (OPCIONAL pero RECOMENDADO)
CREATE OR REPLACE FUNCTION log_venta_changes()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (tabla, accion, usuario_id, datos_antes, datos_despues)
  VALUES (
    'ventas',
    TG_OP,
    auth.uid(),
    CASE WHEN TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN row_to_json(OLD) ELSE NULL END,
    CASE WHEN TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN row_to_json(NEW) ELSE NULL END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER venta_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON ventas
FOR EACH ROW
EXECUTE FUNCTION log_venta_changes();

-- ==================================================================================
-- FIN SCRIPT RLS
-- ==================================================================================
