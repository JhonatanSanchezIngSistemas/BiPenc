# P0 — Estabilidad para producción

- [x] Investigar y resolver inconsistencia `venta_items` vacía
- [x] Eliminar todos los `catch (_) {}` silenciosos → reemplazar por `RegistroApp.error()`
- [x] Ejecutar `dart fix --apply` y resolver warnings
- [x] Crear 1 integration test mínimo del flujo de venta

# P1 — Core completo

- [x] UI completa de paquetes abiertos en caja (apertura + consumo + trazabilidad)
- [x] Completar módulo de cierre de caja (`caja_turnos` tiene 0 filas)
- [x] Definir reglas de conflicto multi-dispositivo
- [x] Extraer router y bootstrap de `main.dart`

# P2 — Crecimiento

- [x] Facturación electrónica SUNAT (OSE/APISUNAT)
- [x] Analítica por turno (margen, top productos, alertas)
- [x] CI/CD (GitHub Actions: test + build + deploy)
- [x] Web admin (Flutter Web o Next.js sobre mismo Supabase)
