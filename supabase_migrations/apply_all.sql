-- apply_all.sql
-- Ejecuta en orden incremental.

\echo 'Applying 001_rls_and_policies.sql'
\i 001_rls_and_policies.sql

\echo 'Applying 002_indexes_constraints.sql'
\i 002_indexes_constraints.sql

\echo 'Applying 003_triggers_audit.sql'
\i 003_triggers_audit.sql

\echo 'Applying 004_correlativo.sql'
\i 004_correlativo.sql

\echo 'Applying 005_generar_correlativo_rpc.sql'
\i 005_generar_correlativo_rpc.sql

\echo 'Applying 006_order_lists.sql'
\i 006_order_lists.sql

\echo 'Applying 007_storage_bucket_pedidos.sql'
\i 007_storage_bucket_pedidos.sql

\echo 'Applying 008_clean_test_data.sql'
\i 008_clean_test_data.sql

\echo 'Applying 009_load_master_data.sql'
\i 009_load_master_data.sql

\echo 'Applying 010_fix_perfiles_rls_recursion.sql'
\i 010_fix_perfiles_rls_recursion.sql

\echo 'Applying 011_store_config.sql'
\i 011_store_config.sql

\echo 'Applying 012_performance_indexes.sql'
\i 012_performance_indexes.sql

\echo 'Applying 013_normalize_ventas_schema.sql'
\i 013_normalize_ventas_schema.sql

\echo 'Applying 014_create_venta_items.sql'
\i 014_create_venta_items.sql

\echo 'Applying 015_create_document_cache.sql'
\i 015_create_document_cache.sql

\echo 'Applying 016_create_empresa_config.sql'
\i 016_create_empresa_config.sql

\echo 'Applying 017_reset_ventas_rpc.sql'
\i 017_reset_ventas_rpc.sql

\echo 'Applying 018_link_pedido_venta.sql'
\i 018_link_pedido_venta.sql

\echo 'Applying 019_global_updates_latest.sql'
\i 019_global_updates_latest.sql

\echo 'Applying 020_rls_document_cache.sql'
\i 020_rls_document_cache.sql

\echo 'Applying 021_insert_venta_with_items_rpc.sql'
\i 021_insert_venta_with_items_rpc.sql

\echo 'Applying 022_create_carts_live.sql'
\i 022_create_carts_live.sql

\echo 'Applying 023_add_live_carts_enabled.sql'
\i 023_add_live_carts_enabled.sql

\echo 'All migrations applied.'
