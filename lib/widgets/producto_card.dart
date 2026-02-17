import 'dart:io';
import 'package:flutter/material.dart';
import '../models/producto.dart';

/// Tarjeta Material 3 para mostrar un producto en la vista de venta.
class ProductoCard extends StatelessWidget {
  final Producto producto;
  final VoidCallback onAgregar;

  const ProductoCard({
    super.key,
    required this.producto,
    required this.onAgregar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
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
                color: Colors.tealAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: producto.imagenPath != null
                    ? Image.file(
                        File(producto.imagenPath!),
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        _iconoCategoria(producto.categoria),
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
                    producto.nombre,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    producto.marca,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
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
                  'S/ ${producto.precioBase.toStringAsFixed(2)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.tealAccent,
                  ),
                ),
                Text(
                  'May. S/ ${producto.precioMayorista.toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Botón agregar
            IconButton(
              onPressed: onAgregar,
              icon: const Icon(Icons.add_circle_outline),
              color: Colors.tealAccent,
              tooltip: 'Agregar al carrito',
            ),
          ],
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
