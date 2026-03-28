-- ============================================================
-- MIGRATION: 008_clean_test_data.sql
-- PURPOSE: Limpiar datos de prueba antes de Go-Live
-- DATE: 8 Marzo 2026
-- CAUTION: ⚠️ TRUNCATE IRREVERSIBLE - BACKUP PRIMERO
-- ============================================================

--- Backup: Exportar datos antes de ejecutar
--- TODO: Hacer EXPORT de estas tablas con:
--- SELECT * INTO OUTFILE '/backup/ventas_backup.csv' FROM ventas;

-- Paso 1: Limpiar tabla de ventas (ordenes ficticias)
TRUNCATE TABLE ventas RESTART IDENTITY CASCADE;
-- Nota: CASCADE debido a FKs con:
--   - detalles_venta (venta_id)
--   - movimientos_caja (venta_id)
--   - audit_log (entity_id)

-- Paso 2: Resetear correlativo de ventas
-- Reinicia el contador a 0 para que la próxima venta sea B001-00001
UPDATE correlativo_ventas 
SET ultimo_numero = 0 
WHERE id = 1;

-- Paso 3: Limpiar tabla de productos
TRUNCATE TABLE productos RESTART IDENTITY CASCADE;
-- Nota: CASCADE debido a FKs con:
--   - detalles_venta (producto_id)
--   - listas_pedido_items (producto_id)
--   - marcas_maestras
--   - auditoria

-- Paso 4: Limpiar tabla de listas de pedido (order_lists)
TRUNCATE TABLE order_lists RESTART IDENTITY CASCADE;
-- Nota: CASCADE limpia:
--   - order_list_items (asociados)
--   - storage files (pedidos/*) se limpian manualmente después

-- Paso 5: Limpiar tabla de auditoría
TRUNCATE TABLE audit_log RESTART IDENTITY CASCADE;

-- Paso 6: Limpiar tabla de movimientos de caja
TRUNCATE TABLE movimientos_caja RESTART IDENTITY CASCADE;

-- Opcional: Limpiar tabla de conflictos de sincronización
TRUNCATE TABLE sync_conflicts RESTART IDENTITY CASCADE;

-- ============================================================
-- POST-LIMPIEZA CHECKLIST
-- ============================================================
-- ✅ Verificar que todas las tablas estén vacías:
SELECT COUNT(*) as total_ventas FROM ventas;
SELECT COUNT(*) as total_productos FROM productos;
SELECT COUNT(*) as total_ordenes FROM order_lists;
SELECT COUNT(*) as total_audits FROM audit_log;

-- ✅ Verificar que correlativo está en 0:
SELECT * FROM correlativo_ventas WHERE id = 1;

-- ✅ Si todo está OK, pasar a: 009_load_master_data.sql
