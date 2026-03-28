-- ⚠️ ADVERTENCIA: Este script ELIMINA TODOS LOS DATOS de productos y ventas en Supabase.
-- Solo usar para pasar de la fase de pruebas (Beta) a Producción real.

-- 1. Truncar tablas de ventas y pedidos (Movimientos)
TRUNCATE TABLE public.venta_items CASCADE;
TRUNCATE TABLE public.ventas CASCADE;
TRUNCATE TABLE public.order_lists CASCADE;

-- 2. Truncar tablas de inventario (Maestros)
TRUNCATE TABLE public.stocks CASCADE;
TRUNCATE TABLE public.presentation_prices CASCADE;
TRUNCATE TABLE public.product_attribute_values CASCADE;
TRUNCATE TABLE public.product_presentations CASCADE;
TRUNCATE TABLE public.products CASCADE;

-- 3. Truncar tablas legadas o secundarias
TRUNCATE TABLE public.productos CASCADE;
TRUNCATE TABLE public.validaciones_productos CASCADE;
TRUNCATE TABLE public.logs_precios CASCADE;

-- 4. Re-inicializar categorías y marcas si se desea (opcional)
-- TRUNCATE TABLE public.categories CASCADE;
-- TRUNCATE TABLE public.brands CASCADE;

-- 5. Reiniciar contadores de correlativos para facturación
UPDATE public.correlativos SET last = 0;

-- 6. Registrar evento de limpieza en auditoría
INSERT INTO public.sync_conflicts (tabla, registro_id, resultado) 
VALUES ('SYSTEM', 'HARD_RESET_' || NOW()::TEXT, 'SUCCESS');
