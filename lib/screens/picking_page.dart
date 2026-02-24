import 'package:flutter/material.dart';
import '../models/producto.dart';

/// Pantalla de picking para verificación física de productos post-venta.
class PickingPage extends StatefulWidget {
  const PickingPage({super.key});

  @override
  State<PickingPage> createState() => _PickingPageState();
}

class _PickingPageState extends State<PickingPage> {
  late List<ItemCarrito> items;
  late double total;
  late String documento;
  late List<bool> checked;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
      items = args['items'] as List<ItemCarrito>;
      total = args['total'] as double;
      documento = args['documento'] as String;
      checked = List.filled(items.length, false);
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allChecked = checked.every((element) => element);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Módulo de Picking', 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: const Icon(Icons.inventory_2_outlined, color: Colors.tealAccent),
      ),
      body: Column(
        children: [
          // Info Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.tealAccent.withOpacity(0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(documento, style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    const Text('Verificar entrega física', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
                Text('S/ ${total.toStringAsFixed(2)}', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
          ),

          // List of items
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => Divider(color: Colors.grey.shade900, height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return CheckboxListTile(
                  value: checked[index],
                  activeColor: Colors.tealAccent,
                  checkColor: Colors.black,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) => setState(() => checked[index] = val ?? false),
                  title: Text(item.producto.nombre, 
                    style: TextStyle(
                      color: checked[index] ? Colors.grey : Colors.white,
                      decoration: checked[index] ? TextDecoration.lineThrough : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${item.cantidad} x ${item.presentacion.nombre.toUpperCase()} - ${item.producto.marca}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  secondary: CircleAvatar(
                    backgroundColor: Colors.tealAccent.withOpacity(0.1),
                    child: Text('${index + 1}', style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                  ),
                );
              },
            ),
          ),

          // Action Button
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: allChecked ? () => Navigator.pop(context) : null,
                icon: const Icon(Icons.done_all),
                label: const Text('FINALIZAR DESPACHO'),
                style: FilledButton.styleFrom(
                  backgroundColor: allChecked ? Colors.tealAccent : Colors.grey.shade800,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.shade900,
                  disabledForegroundColor: Colors.grey.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
