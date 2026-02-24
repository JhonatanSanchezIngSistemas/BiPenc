import 'package:flutter/material.dart';
import '../models/producto.dart';

/// Widget modular para un ítem del carrito.
class ItemCarritoWidget extends StatelessWidget {
  final ItemCarrito item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final ValueChanged<double> onPrecioEditado;

  const ItemCarritoWidget({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onPrecioEditado,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tieneDescuento = item.tieneDescuento;

    return Card(
      color: const Color(0xFF1E1E2C),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fila superior: nombre + eliminar ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.producto.nombre,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            item.producto.marca,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                          ),
                          const SizedBox(width: 8),
                          // Etiqueta de presentación usando el nombre real
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.tealAccent.withOpacity(0.2)),
                            ),
                            child: Text(
                              item.presentacion.nombre.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.redAccent.shade100,
                  tooltip: 'Eliminar',
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Fila de precios ──
            Row(
              children: [
                if (tieneDescuento)
                  Text(
                    'S/ ${item.precioOriginal.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.redAccent,
                      color: Colors.redAccent.shade100,
                    ),
                  ),
                if (tieneDescuento) const SizedBox(width: 8),
                Text(
                  'S/ ${item.precioActual.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tieneDescuento ? const Color(0xFF2ECC71) : Colors.tealAccent,
                  ),
                ),
                const Spacer(),
                Text(
                  'Sub: S/ ${item.subtotal.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Fila de controles ──
            Row(
              children: [
                // Botones cantidad
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BotonCantidad(icon: Icons.remove, onTap: onDecrement),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          '${item.cantidad}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _BotonCantidad(icon: Icons.add, onTap: onIncrement),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Botón Precio Amigo
                OutlinedButton.icon(
                  onPressed: () => _mostrarDialogoPrecio(context),
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('Precio Amigo', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2ECC71),
                    side: const BorderSide(color: Color(0xFF2ECC71), width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                const Spacer(),

                // Indicador de factor de presentación
                if (item.presentacion.factor > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      '×${item.presentacion.factor} = ${item.unidadesTotales} uds',
                      style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoPrecio(BuildContext context) {
    final controller = TextEditingController(text: item.precioActual.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Precio Amigo', style: TextStyle(color: Colors.tealAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Precio normal: S/ ${item.producto.precioBase.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 22),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: 'S/ ',
                prefixStyle: TextStyle(color: Colors.grey.shade400, fontSize: 22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.tealAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.tealAccent, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              onPrecioEditado(item.producto.precioBase);
              Navigator.pop(ctx);
            },
            child: const Text('Restaurar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              final valor = double.tryParse(controller.text.replaceAll(',', '.'));
              if (valor != null && valor > 0) onPrecioEditado(valor);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }
}

class _BotonCantidad extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _BotonCantidad({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: Colors.tealAccent),
      ),
    );
  }
}
