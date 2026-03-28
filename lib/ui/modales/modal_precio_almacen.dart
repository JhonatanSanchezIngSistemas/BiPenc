import 'package:flutter/material.dart';
import '../../datos/modelos/producto.dart';
import '../../datos/modelos/presentacion.dart';
import '../comun/imagen_robusta.dart';

class ModalPrecioAlmacen extends StatelessWidget {
  final Producto producto;
  final Function(Presentacion) onPriceSelected;
  final bool isAdmin;

  const ModalPrecioAlmacen({
    super.key,
    required this.producto,
    required this.onPriceSelected,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Definir las 3 presentaciones clave
    final pUnit = producto.presentaciones.firstWhere(
      (p) => p.id == 'unid',
      orElse: () => Presentacion(id: 'unid', skuCode: producto.skuCode, name: 'Unitario', conversionFactor: 1, prices: [PuntoPrecio(type: 'NORMAL', amount: producto.precioBase)]),
    );
    
    final pMayo = producto.presentaciones.firstWhere(
      (p) => p.id == 'mayo',
      orElse: () => Presentacion(id: 'mayo', skuCode: producto.skuCode, name: 'Mayorista', conversionFactor: 1, prices: [PuntoPrecio(type: 'NORMAL', amount: producto.precioMayorista)]),
    );

    final pEspe = producto.presentaciones.firstWhere(
      (p) => p.id == 'espe',
      orElse: () => Presentacion(id: 'espe', skuCode: producto.skuCode, name: 'Especial', conversionFactor: 1, prices: [PuntoPrecio(type: 'NORMAL', amount: producto.precioEspecial)]),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Info del producto
          Row(
            children: [
              ImagenRobusta(
                imagePath: producto.imagenPath,
                width: 70,
                height: 70,
                borderRadius: BorderRadius.circular(16),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              if (isAdmin)
                IconButton(
                  onPressed: () {
                    // Acción para editar precios (placeholder para futura expansión)
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.edit_note, color: Colors.white54),
                ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'ALMACÉN DE PRECIOS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          // Lista de precios
          _buildPriceItem(
            context,
            title: 'Precio Unitario',
            subtitle: 'Venta al detalle',
            presentacion: pUnit,
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 12),
          _buildPriceItem(
            context,
            title: 'Precio Mayorista',
            subtitle: 'A partir de 3 unidades',
            presentacion: pMayo,
            color: Colors.orangeAccent,
          ),
          const SizedBox(height: 12),
          _buildPriceItem(
            context,
            title: 'Precio Especial',
            subtitle: 'Clientes frecuentes / Promoción',
            presentacion: pEspe,
            color: Colors.purpleAccent,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPriceItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Presentacion presentacion,
    required Color color,
  }) {
    return InkWell(
      onTap: () {
        onPriceSelected(presentacion);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'S/ ${presentacion.getPriceByType('NORMAL').toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
