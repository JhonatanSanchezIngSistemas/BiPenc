import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../servicios/supabase/servicio_catalogo.dart';

class TabProductos extends StatefulWidget {
  final List<Map<String, dynamic>> productos;
  const TabProductos({super.key, required this.productos});

  @override
  State<TabProductos> createState() => _TabProductosState();
}

class _TabProductosState extends State<TabProductos> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = widget.productos.where((p) {
      if (query.isEmpty) return true;
      final nombre = (p['nombre'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      final marca = (p['marca'] ?? '').toString().toLowerCase();
      return nombre.contains(query) || sku.contains(query) || marca.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar producto (nombre, SKU, marca)',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF141C2B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtrados.isEmpty
              ? const Center(
                  child: Text('Sin productos coincidentes',
                      style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtrados.length,
                  itemBuilder: (context, i) {
                    final p = filtrados[i];
                    final nombre = p['nombre'] ?? 'Sin nombre';
                    final sku = p['sku'] ?? '—';
                    final marca = p['marca'] ?? '—';
                    final estado = (p['estado'] ?? 'ACTIVO').toString();
                    final stockStatus = (p['stock_status'] ?? 'DISPONIBLE').toString();
                    final precio = (p['precio_propuesto'] as num?)?.toDouble() ?? 0.0;
                    final updated = DateTime.tryParse((p['updated_at'] ?? '').toString())?.toLocal();

                    return Card(
                      color: Colors.grey.shade900,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white10),
                      ),
                      child: ListTile(
                        leading: _buildStockBadge(stockStatus),
                        title: Text(nombre,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('SKU: $sku • Marca: $marca',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('S/. ${precio.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Colors.tealAccent,
                                        fontWeight: FontWeight.bold)),
                                Text(estado,
                                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                if (updated != null)
                                  Text(DateFormat('dd/MM HH:mm').format(updated),
                                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
                              ],
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white54),
                              color: const Color(0xFF1A1A2E),
                              onSelected: (val) async {
                                try {
                                  final id = p['id'].toString();
                                  await ServicioCatalogoSupabase.actualizarEstadoStock(id, val);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Estado actualizado a $val')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                                    );
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'DISPONIBLE', child: Text('DISPONIBLE', style: TextStyle(color: Colors.greenAccent))),
                                const PopupMenuItem(value: 'BAJOSTOCK', child: Text('BAJO STOCK', style: TextStyle(color: Colors.orangeAccent))),
                                const PopupMenuItem(value: 'AGOTADO', child: Text('AGOTADO', style: TextStyle(color: Colors.redAccent))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStockBadge(String status) {
    Color color;
    IconData icon;
    switch (status) {
      case 'AGOTADO':
        color = Colors.redAccent;
        icon = Icons.block;
        break;
      case 'BAJOSTOCK':
        color = Colors.orangeAccent;
        icon = Icons.warning_amber_rounded;
        break;
      default:
        color = Colors.greenAccent;
        icon = Icons.check_circle_outline;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
