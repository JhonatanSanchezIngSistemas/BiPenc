import 'dart:io';
import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../utils/precio_engine.dart';

/// Tarjeta Material 3 para mostrar un producto en la vista de venta.
class ProductoCard extends StatefulWidget {
  final Producto producto;
  final void Function(Producto, int, Presentacion) onAgregar;

  const ProductoCard({
    super.key,
    required this.producto,
    required this.onAgregar,
  });

  @override
  State<ProductoCard> createState() => _ProductoCardState();
}

class _ProductoCardState extends State<ProductoCard> {
  late int _cantidadSeleccionada;
  late String _sku;
  late Presentacion _presentacionSeleccionada;

  @override
  void initState() {
    super.initState();
    _cantidadSeleccionada = 1;
    // Buscar la presentación 'unid' o la primera disponible
    _presentacionSeleccionada = widget.producto.presentaciones.firstWhere(
      (p) => p.id == 'unid',
      orElse: () => widget.producto.presentaciones.isNotEmpty 
          ? widget.producto.presentaciones.first 
          : Presentacion.unidad,
    );
    _sku = widget.producto.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final escalas = PrecioEngine.getPresentaciones(_sku);
    // Precio 'base' para el motor es el de la unidad
    final unidadPrice = widget.producto.presentaciones.firstWhere((p) => p.id == 'unid', orElse: () => Presentacion.unidad).precio;
    
    final resultado = PrecioEngine.calcularPrecio(
      sku: _sku,
      cantidad: _cantidadSeleccionada,
      precioBase: unidadPrice,
    );

    return GestureDetector(
      onLongPress: () => _mostrarModalPresentaciones(context),
      child: Card(
        color: const Color(0xFF1E1E2C),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Ícono de categoría
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.producto.imagenPath != null
                      ? Image.file(
                          File(widget.producto.imagenPath!),
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          _iconoCategoria(widget.producto.categoria),
                          color: Colors.tealAccent,
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              // Info del producto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.producto.nombre,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          widget.producto.marca,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildTierBadge(widget.producto.marca),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.producto.presentaciones.map((p) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _buildChoiceChip(p.nombre, p),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              // Precio
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'S/ ${_getPrecioActual().toStringAsFixed(2)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.tealAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    onPressed: () => widget.onAgregar(widget.producto, _cantidadSeleccionada, _presentacionSeleccionada),
                    icon: const Icon(Icons.add_circle_outline, size: 28),
                    color: Colors.tealAccent,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Agregar al carrito',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarModalPresentaciones(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black12,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: widget.producto.imagenPath != null
                          ? Image.file(File(widget.producto.imagenPath!), fit: BoxFit.cover)
                          : const Icon(Icons.inventory_2, color: Colors.tealAccent, size: 32),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.producto.nombre,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          '${widget.producto.marca} • ${widget.producto.categoria}',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Seleccione Presentación:',
                style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: widget.producto.presentaciones.map((p) {
                  final isSel = _presentacionSeleccionada.id == p.id;
                  return InkWell(
                    onTap: () {
                      setState(() => _presentacionSeleccionada = p);
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSel ? Colors.tealAccent : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            p.nombre,
                            style: TextStyle(
                              color: isSel ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'S/ ${p.precio.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSel ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onAgregar(widget.producto, _cantidadSeleccionada, _presentacionSeleccionada);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Agregar Rápidamente'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChoiceChip(String label, Presentacion p) {
    final isSelected = _presentacionSeleccionada.id == p.id;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _presentacionSeleccionada = p);
      },
      selectedColor: Colors.tealAccent.withOpacity(0.2),
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.tealAccent : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? Colors.tealAccent : Colors.grey.shade800,
        width: 1,
      ),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  double _getPrecioActual() {
    return _presentacionSeleccionada.precio;
  }

  String _getLabelPresentacion() {
    return 'por ${_presentacionSeleccionada.nombre}';
  }

  Widget _buildTierBadge(String marca) {
// ... rest of the file
    final tier = PrecioEngine.getTier(marca);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Color(int.parse(tier.hexColor.replaceFirst('#', '0xFF'))).withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Color(int.parse(tier.hexColor.replaceFirst('#', '0xFF'))).withOpacity(0.4),
        ),
      ),
      child: Text(
        tier.label.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Color(int.parse(tier.hexColor.replaceFirst('#', '0xFF'))),
        ),
      ),
    );
  }

  IconData _iconoCategoria(String categoria) {
    switch (categoria) {
      case 'Cuadernos':
        return Icons.menu_book_rounded;
      case 'Lapiceros':
        return Icons.edit;
      case 'Arte':
        return Icons.palette;
      case 'Útiles':
        return Icons.build_circle_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }
}
