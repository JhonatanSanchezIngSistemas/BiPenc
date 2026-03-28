import 'package:flutter/material.dart';
import '../datos/modelos/venta.dart';
import '../ui/modales/modal_checklist.dart';
import '../servicios/servicio_db_local.dart';
import '../servicios/servicio_impresion.dart';
import '../base/llaves.dart';

class ServicioDespacho {
  static final ServicioDespacho _instance = ServicioDespacho._();
  factory ServicioDespacho() => _instance;
  ServicioDespacho._();

  /// Muestra el modal de picking directamente.
  /// Se usa desde el historial o cuando el usuario ya confirmó que quiere ver la guía.
  Future<void> abrirPicking(BuildContext context, Venta venta, {bool isReprint = false}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // Forzar verificación
      backgroundColor: Colors.transparent,
      builder: (ctx) => ModalListaChequeo(
        venta: venta,
        onFinish: (reimprimir) async {
          // 1. Marcar como despachado en DB Local
          if (venta.dbId != null) {
            await ServicioDbLocal.marcarDespachado(venta.dbId!);
          }

          // 2. Cerrar el modal (sin rootNavigator para no tocar el stack de GoRouter)
          if (ctx.mounted) Navigator.of(ctx).pop();

          if (!reimprimir) {
            scaffoldMessengerKey.currentState?.showSnackBar(
              const SnackBar(
                content: Row(children: [
                  Icon(Icons.check_circle_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Despacho confirmado sin reimprimir.')),
                ]),
                backgroundColor: Colors.teal,
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }

          // 3. Reimprimir comprobante solo si el usuario lo eligió
          final impreso = await ServicioImpresion().imprimirComprobante(venta);
          if (!impreso) {
            scaffoldMessengerKey.currentState?.showSnackBar(
              const SnackBar(
                content: Row(children: [
                  Icon(Icons.print_disabled, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('No hay impresora conectada. La venta fue registrada correctamente.')),
                ]),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
        },
      ),
    );
  }

  /// Flujo post-venta: Pregunta si desea ver la guía.
  Future<void> preguntarYAbrirPicking(BuildContext context, Venta venta) async {
    final bool? abrir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.tealAccent),
            SizedBox(width: 12),
            Text('Venta Exitosa', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          '¿Deseas abrir la guía de despacho (Picking) ahora mismo?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('MÁS TARDE', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, AHORA'),
          ),
        ],
      ),
    );

    if (abrir == true && context.mounted) {
      await abrirPicking(context, venta);
    }
  }
}
