-- ============================================================
-- MIGRATION: 009_load_master_data.sql
-- PURPOSE: Cargar datos maestro de demostración
-- SCOPE: Datos de prueba para peluquería + librería muestra
-- DATE: 8 Marzo 2026
-- RUN AFTER: 008_clean_test_data.sql
-- ============================================================

-- ============================================================
-- CATEGORÍAS MAESTRO
-- ============================================================
INSERT INTO public.categorias (nombre, descripcion, creado_at) VALUES
('Servicios Peluquería', 'Cortes, peinados, tratamientos', NOW()),
('Productos Cabello', 'Champús, acondicionadores, tratamientos', NOW()),
('Accesorios', 'Peines, clips, diademas, extensiones', NOW()),
('Libros', 'Autores variados, géneros mixtos', NOW()),
('Papelería', 'Útiles escolares y de oficina', NOW()),
('Mochilas & Bolsas', 'Mochilas escolares y bolsas de viaje', NOW())
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================
-- MARCAS MAESTRO
-- ============================================================
INSERT INTO public.marcas_maestras (nombre, descripcion, creado_at) VALUES
('Laboratorio Natural', 'Productos naturales para cabello', NOW()),
('Elite Pro', 'Línea profesional de estilismo', NOW()),
('Scholastic', 'Editorial educativa', NOW()),
('Miguelitos', 'Papelería nacional peruana', NOW()),
('No Brand', 'Productos genéricos', NOW())
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================
-- UNIDADES DE MEDIDA
-- ============================================================
INSERT INTO public.unidades_medida (nombre, abreviatura, creado_at) VALUES
('Unidad', 'Und', NOW()),
('Cajas', 'Caj', NOW()),
('Kilogramos', 'Kg', NOW()),
('Litros', 'L', NOW()),
('Metros', 'M', NOW())
ON CONFLICT (nombre) DO NOTHING;

-- ============================================================
-- PRODUCTOS PELUQUERÍA (10 items)
-- ============================================================
INSERT INTO public.productos (
  sku, nombre, descripcion, precio_base, precio_mayorista, 
  categoria_id, marca_id, unidad_medida_id, stock, creado_at
) VALUES
-- Champús
('SKU-001', 'Champú Natural 500ml', 'Champú con extracto de aloe vera', 25.50, 20.00, 
  (SELECT id FROM categorias WHERE nombre='Productos Cabello' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Laboratorio Natural' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  50, NOW()),

('SKU-002', 'Acondicionador Profesional 250ml', 'Acondicionador para cabello dañado', 32.00, 26.00,
  (SELECT id FROM categorias WHERE nombre='Productos Cabello' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Elite Pro' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  35, NOW()),

('SKU-003', 'Tratamiento Capilar Premium 200ml', 'Botella de tratamiento intenso', 48.90, 40.00,
  (SELECT id FROM categorias WHERE nombre='Productos Cabello' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Elite Pro' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  20, NOW()),

-- Accesorios
('SKU-004', 'Peine de Carbono', 'Peine profesional antiestático', 15.90, 12.00,
  (SELECT id FROM categorias WHERE nombre='Accesorios' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='No Brand' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  100, NOW()),

('SKU-005', 'Clips Metálicos (10 piezas)', 'Juego de clips para secado', 12.50, 10.00,
  (SELECT id FROM categorias WHERE nombre='Accesorios' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='No Brand' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Cajas' LIMIT 1),
  75, NOW()),

('SKU-006', 'Diadema Antislip', 'Diadema deportiva no resbalosa', 18.00, 14.00,
  (SELECT id FROM categorias WHERE nombre='Accesorios' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='No Brand' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  60, NOW()),

-- Servicios (virtuales, stock=999)
('SKU-010', 'Corte de Cabello', 'Servicio de corte profesional', 40.00, 35.00,
  (SELECT id FROM categorias WHERE nombre='Servicios Peluquería' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Elite Pro' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  999, NOW()),

('SKU-011', 'Peinado + Arreglo', 'Peinado y arreglo completo', 60.00, 50.00,
  (SELECT id FROM categorias WHERE nombre='Servicios Peluquería' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Elite Pro' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  999, NOW()),

('SKU-012', 'Alisado Japonés 1.5hrs', 'Alisado químico japonés', 150.00, 120.00,
  (SELECT id FROM categorias WHERE nombre='Servicios Peluquería' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Elite Pro' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  999, NOW());

-- ============================================================
-- PRODUCTOS LIBRERÍA (10 items)
-- ============================================================
INSERT INTO public.productos (
  sku, nombre, descripcion, precio_base, precio_mayorista, 
  categoria_id, marca_id, unidad_medida_id, stock, creado_at
) VALUES
-- Libros
('SKU-101', 'El Quijote - Cervantes', 'Novela clásica, 500 páginas', 89.90, 70.00,
  (SELECT id FROM categorias WHERE nombre='Libros' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Scholastic' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  25, NOW()),

('SKU-102', 'Harry Potter 1 - Rowling', 'Fantasía infantil, bestseller', 62.50, 50.00,
  (SELECT id FROM categorias WHERE nombre='Libros' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Scholastic' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  40, NOW()),

('SKU-103', 'Cien Años de Soledad - García Márquez', 'Realismo mágico, clásico', 75.00, 60.00,
  (SELECT id FROM categorias WHERE nombre='Libros' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Scholastic' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  15, NOW()),

-- Papelería
('SKU-110', 'Cuaderno Profesional A4 (100 hojas)', 'Cuaderno rayado, tapa dura', 18.50, 14.00,
  (SELECT id FROM categorias WHERE nombre='Papelería' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Miguelitos' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  200, NOW()),

('SKU-111', 'Bolígrafos Azules (12 pack)', 'Lapiceros de gel premium', 12.00, 9.00,
  (SELECT id FROM categorias WHERE nombre='Papelería' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Miguelitos' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Cajas' LIMIT 1),
  150, NOW()),

('SKU-112', 'Lápices de Color (24 colores)', 'Set profesional de colores', 32.90, 26.00,
  (SELECT id FROM categorias WHERE nombre='Papelería' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='Miguelitos' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Cajas' LIMIT 1),
  80, NOW()),

-- Mochilas
('SKU-200', 'Mochila Escolar Azul', 'Mochila ergonómica para niños', 125.00, 100.00,
  (SELECT id FROM categorias WHERE nombre='Mochilas & Bolsas' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='No Brand' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  40, NOW()),

('SKU-201', 'Mochila Universitaria Negra', 'Mochila grande para universitarios', 189.90, 150.00,
  (SELECT id FROM categorias WHERE nombre='Mochilas & Bolsas' LIMIT 1),
  (SELECT id FROM marcas_maestras WHERE nombre='No Brand' LIMIT 1),
  (SELECT id FROM unidades_medida WHERE nombre='Unidad' LIMIT 1),
  25, NOW());

-- ============================================================
-- POST-LOAD CHECKLIST
-- ============================================================
-- ✅ Verificar que los datos se cargaron correctamente:
SELECT COUNT(*) as total_productos FROM productos;
SELECT COUNT(*) as categorias FROM categorias;
SELECT COUNT(*) as marcas FROM marcas_maestras;
SELECT COUNT(*) as unidades FROM unidades_medida;

-- ✅ Verificar stock total:
SELECT SUM(stock) as stock_total FROM productos;

-- ✅ Listar todos los productos cargados:
SELECT sku, nombre, precio_base, stock FROM productos ORDER BY sku;

-- ============================================================
-- NEXT STEPS
-- ============================================================
-- 1. Sincronizar en local DB vía app (Pull de Inventario)
-- 2. Verificar que aparecen en POS
-- 3. Hacer venta de prueba
-- 4. Validar que descuente stock
-- 5. Cierre de caja test
