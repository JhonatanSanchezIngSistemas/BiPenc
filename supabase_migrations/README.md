# Supabase migrations and operations

Archivos SQL para revisar y aplicar manualmente en el SQL editor de Supabase.

Resumen de archivos:
- `001_rls_and_policies.sql`: Habilita RLS en tablas críticas y agrega políticas ejemplo.
- `002_indexes_constraints.sql`: Crea tabla `correlativos`, índices y constraints básicos.
- `003_triggers_audit.sql`: Crea `audit_log` y trigger genérico para auditar cambios.
- `004_correlativo.sql`: Función `generar_siguiente_correlativo(scope)` para obtener números consecutivos.
- `010_fix_perfiles_rls_recursion.sql`: Elimina policies recursivas en `public.perfiles` y crea policies seguras no recursivas.
- `011_store_config.sql`: Crea `store_config` (min_version + igv_rate) y evita errores `PGRST205`.
- `012_performance_indexes.sql`: Agrega índices de rendimiento para `ventas`, `productos` y `sync_queue_v2`.
- `013_normalize_ventas_schema.sql`: Normaliza `public.ventas` (documento, correlativo, comprobante, impuestos), añade trigger de compatibilidad y crea índices para boletas/reimpresión.

Cómo aplicar
1. Haz copia de seguridad: antes de ejecutar cualquier script, exporta el SQL desde Supabase o crea un snapshot del proyecto.
2. Abre `SQL Editor` en Supabase (Project → SQL Editor).
3. Pega el contenido de cada archivo en orden y ejecútalos uno por uno.
4. Verifica logs y la tabla `audit_log` para confirmar triggers.
5. Si aparece `42P17 infinite recursion ... perfiles`, ejecuta `010_fix_perfiles_rls_recursion.sql` inmediatamente.

Notas de seguridad
- Algunos cambios (p. ej. habilitar RLS) requieren revisar las claims que aporta tu JWT. Ajusta `jwt.claims.role` y `created_by` según tu modelo.
- Para operaciones administrativas (DROP, cambios schema sensibles) usa la `SERVICE_ROLE` desde la consola si es necesario.

Rollback rápido
- Para deshacer parcialmente: eliminar triggers (`DROP TRIGGER IF EXISTS audit_trigger ON table`), eliminar policies creadas y funciones `DROP FUNCTION public.generar_siguiente_correlativo(text)`.

Si quieres, puedo:
- Generar un script combinado `apply_all.sql` y uno `rollback_all.sql`.
- Probar consultas puntuales con la `SUPABASE_ANON_KEY` que ya tienes (si las tablas permiten lectura).
- Ejecutar los SQL automáticamente si me facilitas la `SUPABASE_SERVICE_ROLE_KEY` (ten precaución al compartirla).
