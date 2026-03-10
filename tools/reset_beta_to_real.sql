-- tools/reset_beta_to_real.sql
-- ══════════════════════════════════════════════════════════════════════
-- ⚠️  RESET BETA → REAL
-- Ejecutar UNA SOLA VEZ antes del lanzamiento al público real.
-- Borra todos los datos de prueba de las tablas de inventario y reinicia
-- los correlativos a 0 para que la primera venta real sea B001-00001.
--
-- PRERREQUISITOS:
--   1. Haber completado la carga real de productos en la tabla `productos`.
--   2. Haber revisado que no existen ventas reales en la tabla `ventas`.
--   3. Ejecutar desde el SQL Editor de Supabase o con psql con rol ADMIN.
-- ══════════════════════════════════════════════════════════════════════

-- Paso 1: Revisar cuántos registros hay antes de borrar (seguridad visual)
SELECT
  'brands'                  AS tabla, COUNT(*) AS filas FROM public.brands        UNION ALL
  SELECT 'categories',                               COUNT(*) FROM public.categories       UNION ALL
  SELECT 'products',                                 COUNT(*) FROM public.products          UNION ALL
  SELECT 'product_presentations',                    COUNT(*) FROM public.product_presentations UNION ALL
  SELECT 'presentation_prices',                      COUNT(*) FROM public.presentation_prices   UNION ALL
  SELECT 'unit_conversions',                         COUNT(*) FROM public.unit_conversions      UNION ALL
  SELECT 'product_attributes',                       COUNT(*) FROM public.product_attributes    UNION ALL
  SELECT 'product_attribute_values',                 COUNT(*) FROM public.product_attribute_values UNION ALL
  SELECT 'presentation_variants',                    COUNT(*) FROM public.presentation_variants UNION ALL
  SELECT 'correlativos',                             COUNT(*) FROM public.correlativos;

-- ══════════════════════════════════════════════════════════════════════
-- Paso 2: ¡ACCIÓN IRREVERSIBLE! Descomentar y ejecutar solo cuando estés seguro.
-- ══════════════════════════════════════════════════════════════════════

/*
TRUNCATE TABLE
  public.presentation_variants,
  public.product_attribute_values,
  public.product_attributes,
  public.presentation_prices,
  public.unit_conversions,
  public.product_presentations,
  public.products,
  public.categories,
  public.brands,
  public.correlativos
RESTART IDENTITY CASCADE;

-- Confirmar resultado
SELECT 'RESET COMPLETADO ✓ — Primera venta será B001-00001' AS mensaje;
*/
