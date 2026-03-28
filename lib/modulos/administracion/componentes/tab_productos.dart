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
  String _statusFilter = 'ACTIVO';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    
    final filtrados = widget.productos.where((p) {
      final matchesQuery = query.isEmpty ||
          (p['nombre'] ?? '').toString().toLowerCase().contains(query) ||
          (p['sku'] ?? '').toString().toLowerCase().contains(query) ||
          (p['marca'] ?? '').toString().toLowerCase().contains(query);
      
      final matchesStatus = (p['status'] ?? 'ACTIVO') == _statusFilter;
      
      return matchesQuery && matchesStatus;
    }).toList();

    final agotadosCount = widget.productos.where((p) => p['stock_status'] == 'AGOTADO').length;
    final pendientesCount = widget.productos.where((p) => p['status'] == 'PENDIENTE').length;

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _InfoCard(label: 'Agotados', count: agotadosCount, color: Colors.redAccent),
              const SizedBox(width: 12),
              _InfoCard(label: 'Pendientes', count: pendientesCount, color: Colors.orangeAccent),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('ACTIVOS'),
                selected: _statusFilter == 'ACTIVO',
                onSelected: (s) => setState(() => _statusFilter = 'ACTIVO'),
                selectedColor: Colors.teal.withValues(alpha: 0.3),
                checkmarkColor: Colors.tealAccent,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('PENDIENTES'),
                selected: _statusFilter == 'PENDIENTE',
                onSelected: (s) => setState(() => _statusFilter = 'PENDIENTE'),
                selectedColor: Colors.orange.withValues(alpha: 0.3),
                checkmarkColor: Colors.orangeAccent,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar en ${_statusFilter.toLowerCase()}...',
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
                                final id = p['id'].toString();
                                if (val == 'PRECIO') {
                                  _mostrarDialogoPrecio(context, p);
                                  return;
                                }
                                if (val == 'APROBAR') {
                                  try {
                                    await ServicioCatalogoSupabase.actualizarEstadoProducto(id, 'ACTIVO');
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Producto aprobado exitosamente')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  }
                                  return;
                                }
                                try {
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
                                const PopupMenuItem(value: 'PRECIO', child: Row(children: [Icon(Icons.edit_note, size: 18, color: Colors.tealAccent), SizedBox(width: 8), Text('Corregir Precio')])),
                                if (p['status'] == 'PENDIENTE')
                                  const PopupMenuItem(value: 'APROBAR', child: Row(children: [Icon(Icons.check_circle_outline, size: 18, color: Colors.greenAccent), SizedBox(width: 8), Text('Aprobar Producto')])),
                                const PopupMenuDivider(),
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

  void _mostrarDialogoPrecio(BuildContext context, Map<String, dynamic> p) {
    final TextEditingController ctrl = TextEditingController(
      text: (p['precio_propuesto'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Corregir Precio: ${p['nombre']}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.tealAccent, fontSize: 24, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            prefixText: 'S/. ',
            hintText: '0.00',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text);
              if (val == null) return;
              try {
                // TODO: Implementar ServicioCatalogoSupabase.actualizarPrecio(id, val)
                // Por ahora usamos la lógica de la Edge Function o el servicio correspondiente si existe
                await ServicioCatalogoSupabase.actualizarPrecioPropuesto(p['id'].toString(), val);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Precio actualizado correctamente')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
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

class _InfoCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _InfoCard({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600)),
          Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
