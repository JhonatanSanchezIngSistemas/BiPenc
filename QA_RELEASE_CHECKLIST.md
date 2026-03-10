# QA Release Checklist (BiPenc)

## 1. Precondiciones
- `flutter analyze` sin errores.
- `flutter test` completo pasando.
- Build release instalado en dispositivo real Android.
- Impresora térmica emparejada (58/80mm según configuración).
- Supabase accesible y credenciales válidas en `.env`.

## 2. Login y Sesión
- Login con usuario válido.
- Login inválido muestra error claro.
- Biometría: entra correctamente cuando hay sesión.
- Cerrar sesión y volver a abrir requiere autenticación.

## 3. Inventario
- Crear producto manual con SKU, nombre, categoría y precio.
- Crear producto desde escaneo en POS (`initialSku` precargado).
- Editar producto existente y persistir cambios.
- Eliminar producto y verificar que desaparece en listado local.
- Buscar por nombre, SKU y marca.
- Capturar imagen y guardar (con y sin internet).

## 4. POS y Venta
- Buscar producto por texto y por escáner.
- Agregar/quitar cantidad, validar total, subtotal e IGV.
- Cobro en efectivo con cálculo de vuelto.
- Cobro en tarjeta/yape-plin sin vuelto.
- Generar venta y verificar correlativo visible.

## 5. Boletas / Impresión / PDF
- Reimprimir boleta desde listado.
- Verificar formato térmico en 58mm y 80mm.
- Verificar QR impreso y datos fiscales mínimos.
- Exportar PDF A4 y PDF ticket.
- Validar fecha en formato `dd/MM/yyyy HH:mm`.

## 6. Anulación
- Anular boleta con motivo obligatorio.
- Confirmar estado `ANULADO` en listado.
- Reintentar anulación de boleta ya anulada (debe bloquear).
- Verificar cola de sincronización cuando no hay internet.

## 7. Sincronización
- Sin internet: ventas se guardan local.
- Recuperar internet: sync automático procesa pendientes.
- Verificar que sync no corre en `none` y respeta regla de WiFi.
- Revisar logs de errores de sync y reintentos.

## 8. Cuenta de Usuario
- Editar nombre/apellido/alias (alias visible para boletas nuevas).
- Cambiar contraseña (validación mínima).
- Guardar foto (URL) y persistencia en perfil.

## 9. Resiliencia
- Reiniciar app durante operaciones y validar recuperación.
- Simular impresora desconectada: boleta en cola de impresión.
- Simular fallo de red durante venta: no perder transacción local.

## 10. Criterio de salida
- 0 bloqueantes en flujo: login, inventario, venta, impresión, anulación, sync.
- Sin errores críticos en logs.
- Todos los casos marcados como OK en dispositivo real.
