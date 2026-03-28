import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TabCarritos extends StatelessWidget {
  final List<Map<String, dynamic>> carritos;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const TabCarritos({
    super.key,
    required this.carritos,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SwitchListTile(
            value: enabled,
            onChanged: onToggle,
            title: const Text('Monitoreo de carritos en vivo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text(
              'Envia snapshots cada 5s solo si hay cambios. Solo Admin.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            activeColor: Colors.tealAccent,
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (!enabled) {
      return const Center(
        child: Text('Monitoreo desactivado',
            style: TextStyle(color: Colors.white54)),
      );
    }
    if (carritos.isEmpty) {
      return const Center(
        child: Text('Sin carritos en vivo (nadie está vendiendo ahora)',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: carritos.length,
      itemBuilder: (context, i) {
        final c = carritos[i];
        final alias = (c['alias'] ?? 'Vendedor').toString();
        final rol = (c['rol'] ?? 'VENTAS').toString().toUpperCase();
        final activeIndex = (c['active_cart_index'] as num?)?.toInt() ?? 0;
        final activeTotal = (c['active_cart_total'] as num?)?.toDouble() ?? 0;
        final activeCount = (c['active_cart_items_count'] as num?)?.toInt() ?? 0;
        final updatedStr = (c['updated_at'] ?? '').toString();
        final updated = DateTime.tryParse(updatedStr)?.toLocal();
        
        // Un carrito se considera "stale" (estancado) si no se actualiza en 3 minutos
        final stale = updated != null && 
            now.difference(updated) > const Duration(minutes: 3);

        final itemsPreview = (c['items_preview'] is List)
            ? (c['items_preview'] as List)
            : const [];

        return Card(
          color: Colors.grey.shade900,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: stale 
                ? Colors.red.withValues(alpha: 0.4) 
                : Colors.white10
            ),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text('$alias • $rol',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Carrito activo: C${activeIndex + 1} • $activeCount ítems',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text('Total: S/. ${activeTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.tealAccent, fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (updated != null)
                  Text(DateFormat('HH:mm:ss').format(updated),
                      style: TextStyle(
                          color: stale ? Colors.redAccent : Colors.white38,
                          fontSize: 11)),
                const Icon(Icons.expand_more, color: Colors.white24, size: 20),
              ],
            ),
            children: [
              if (itemsPreview.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('El carrito no tiene productos',
                      style: TextStyle(color: Colors.white24, fontSize: 12)),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: Colors.white12),
                      const Text('VISTRA PREVIA DE PRODUCTOS:',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...itemsPreview.take(8).map((it) {
                        final nombre = (it['nombre'] ?? 'Producto').toString();
                        final cantidad = (it['cantidad'] as num?)?.toDouble() ?? 0;
                        final precio = (it['precio'] as num?)?.toDouble() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text('•', style: TextStyle(color: Colors.tealAccent.withValues(alpha: 0.5))),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(nombre,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11)),
                              ),
                              Text(
                                '${cantidad.toStringAsFixed(1)} x S/. ${precio.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      if (itemsPreview.length > 8)
                        Text('... y ${itemsPreview.length - 8} más',
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
