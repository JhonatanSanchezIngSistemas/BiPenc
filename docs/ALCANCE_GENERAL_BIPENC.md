# Alcance General — BiPenc

_Última actualización: 2026-05-16_

## Objetivo

BiPenc es una app Flutter orientada a operación de negocio (caja/ventas), inventario y reportes, con backend en Supabase y soporte de persistencia local.

## Alcance (incluido)

- **Caja**: flujo de venta/cobro y sus componentes (`lib/modulos/caja/`).
- **Inventario**: catálogo/productos/presentaciones (`lib/modulos/inventario/`).
- **Pedidos**: creación y detalle de pedidos (`lib/modulos/pedidos/`).
- **Reportes**: boletas/cierre de caja y utilidades de exportación (`lib/modulos/reportes/`).
- **Administración**: tablero admin y tabs de métricas/gestión (`lib/modulos/administracion/`).
- **Autenticación / Arranque**: login y bootstrap inicial (`lib/modulos/autenticacion/`, `lib/modulos/arranque/`).
- **Ajustes / Configuración**: configuración de negocio, correlativos, impresora, etc. (`lib/modulos/ajustes/`, `lib/modulos/configuracion/`).

## No alcance (por definir)

- [ ] Listar explícitamente integraciones fuera de P0 (ej.: SUNAT/OSE, Web Admin, analítica avanzada) y su estado real.

## Arquitectura (mapa práctico)

- `lib/modulos/`: pantallas y widgets por feature.
- `lib/servicios/`: capa de servicios (Supabase, DB local, sesión, sincronización, impresión, etc.).
- `lib/datos/`: modelos y lógica de dominio ligera.
- `lib/ui/`: UI común (layout, modales, componentes compartidos, guardias).
- `lib/base/`: constantes/tema/llaves y piezas base.
- `lib/utilidades/`: utilitarios cross-cutting (ej. `RegistroApp`).

### Convenciones de dependencias

- UI (`lib/modulos`, `lib/ui`) **no** debería hablar directo con Supabase/DB: usar `lib/servicios`.
- No usar `catch (_) {}` silenciosos: registrar con `RegistroApp.error()` / `RegistroApp.critical()`.

## Señales del grafo (Graphify)

Análisis reconstruido el **2026-05-16** desde commit `797e9e1d`:

- Núcleo claro: `RegistroApp` aparece como abstracción central (telemetría unificada).
- No se detectaron “surprising connections” entre módulos (buen indicador de límites).
- `Community 0` (caja/componentes) tiene cohesión baja: normal por composición de widgets, pero es buen candidato para **ordenar por sub-feature** (escaneo/cobro/carrito/pedido) si queremos mejorar navegabilidad.

## Checklist rápido (antes de commitear)

- `flutter analyze`
- `flutter test`
