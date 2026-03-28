import 'package:flutter/material.dart';
import 'package:bipenc/datos/modelos/producto.dart';

/// Modal que aparece cuando un código de barras pertenece a más de un producto.
/// El usuario elige cuál es el correcto y el seleccionado se retorna como resultado.
///
/// Uso:
/// ```dart
/// final seleccionado = await showResolvedorConflictoProducto(context, codigo, productos);
/// if (seleccionado != null) pos.agregarProducto(seleccionado);
/// ```
Future<Producto?> showResolvedorConflictoProducto(
  BuildContext context, {
  required String codigo,
  required List<Producto> productos,
}) {
  return showModalBottomSheet<Producto>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ResolvedorConflictoProducto(
      codigo: codigo,
      productos: productos,
    ),
  );
}

class ResolvedorConflictoProducto extends StatelessWidget {
  final String codigo;
  final List<Producto> productos;

  const ResolvedorConflictoProducto({
    super.key,
    required this.codigo,
    required this.productos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.compare_arrows_rounded,
                    color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Código Ambiguo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Código "$codigo" — ¿Cuál es el producto correcto?',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Lista de productos en conflicto
          ...productos.map((p) => _TarjetaProducto(
                producto: p,
                onTap: () => Navigator.of(context).pop(p),
              )),

          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  final Producto producto;
  final VoidCallback onTap;

  const _TarjetaProducto({required this.producto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final precio = producto.precioBase;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              // Imagen / ícono placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: producto.imagenPath != null
                    ? Image.network(
                        producto.imagenPath!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _iconoProducto(),
                      )
                    : _iconoProducto(),
              ),
              const SizedBox(width: 12),

              // Datos del producto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (producto.marca.isNotEmpty)
                      Text(
                        producto.marca,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      precio > 0 ? 'S/. ${precio.toStringAsFixed(2)}' : '—',
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              // Flecha de acción
              const Icon(Icons.chevron_right, color: Colors.white24, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconoProducto() {
    return Container(
      width: 52,
      height: 52,
      color: Colors.white10,
      child: const Icon(Icons.inventory_2_outlined,
          color: Colors.white38, size: 26),
    );
  }
}
