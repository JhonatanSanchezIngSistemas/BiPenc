import 'package:flutter/material.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/ui/comun/imagen_robusta.dart';
import 'package:bipenc/servicios/servicio_etiqueta_pdf.dart';

class ModalDetalleProducto extends StatelessWidget {
  final Producto producto;
  final ValueChanged<Presentacion>? onAddWithPresentation;
  final ValueChanged<double>? onApplyManualPrice;
  final bool readOnly;

  const ModalDetalleProducto({
    super.key,
    required this.producto,
    this.onAddWithPresentation,
    this.onApplyManualPrice,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final pUnit = _findPresentation(
      producto,
      'unid',
      fallbackName: 'Unitario',
      fallbackPrice: producto.precioBase,
    );
    final pMayo = _findPresentation(
      producto,
      'mayo',
      fallbackName: 'Mayorista',
      fallbackPrice: producto.precioMayorista,
    );
    final pEspe = _findPresentation(
      producto,
      'espe',
      fallbackName: 'Especial',
      fallbackPrice: producto.precioEspecial,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF121B2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ImagenRobusta(
                    imagePath: producto.imagenPath,
                    width: 120,
                    height: 120,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          producto.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'SKU: ${producto.skuCode}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        Text(
                          'Marca: ${producto.marca.isEmpty ? "Sin marca" : producto.marca}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        Text(
                          'Categoría: ${producto.categoria.isEmpty ? "Sin categoría" : producto.categoria}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if ((producto.descripcion ?? '').trim().isNotEmpty) ...[
                const Text(
                  'Descripción',
                  style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  producto.descripcion!.trim(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Precios',
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _FilaPrecio(
                label: pUnit.name,
                amount: pUnit.getPriceByType('NORMAL'),
                accent: Colors.tealAccent,
                enabled: !readOnly && onAddWithPresentation != null,
                onTap: () {
                  onAddWithPresentation?.call(pUnit);
                  Navigator.pop(context);
                },
              ),
              if (pMayo.getPriceByType('NORMAL') > 0)
                _FilaPrecio(
                  label: pMayo.name,
                  amount: pMayo.getPriceByType('NORMAL'),
                  accent: Colors.amberAccent,
                  enabled: !readOnly && onAddWithPresentation != null,
                  onTap: () {
                    onAddWithPresentation?.call(pMayo);
                    Navigator.pop(context);
                  },
                ),
              if (pEspe.getPriceByType('NORMAL') > 0)
                _FilaPrecio(
                  label: pEspe.name,
                  amount: pEspe.getPriceByType('NORMAL'),
                  accent: Colors.blueAccent,
                  enabled: !readOnly && onAddWithPresentation != null,
                  onTap: () {
                    onAddWithPresentation?.call(pEspe);
                    Navigator.pop(context);
                  },
                ),
              if (!readOnly && onApplyManualPrice != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openManualPriceDialog(
                      context, pUnit.getPriceByType('NORMAL')),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Precio manual en venta'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _imprimirEtiqueta(context),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Imprimir etiqueta A4'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: const BorderSide(color: Colors.tealAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Presentacion _findPresentation(
    Producto p,
    String id, {
    required String fallbackName,
    required double fallbackPrice,
  }) {
    try {
      return p.presentaciones.firstWhere((x) => x.id == id);
    } catch (_) {
      return Presentacion(
        id: id,
        skuCode: p.skuCode,
        name: fallbackName,
        conversionFactor: 1,
        prices: [PuntoPrecio(type: 'NORMAL', amount: fallbackPrice)],
      );
    }
  }

  void _openManualPriceDialog(BuildContext context, double basePrice) {
    final ctrl = TextEditingController(text: basePrice.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title:
            const Text('Precio manual', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: 'S/. ',
            prefixStyle: TextStyle(color: Colors.teal),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              final p = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (p != null && p > 0) {
                onApplyManualPrice?.call(p);
              }
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Aplicar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimirEtiqueta(BuildContext context) async {
    final etiquetas = List<Producto>.filled(8, producto);
    final pdf = await ServicioEtiquetaPdf.generateEtiquetasPdf(etiquetas);
    await ServicioEtiquetaPdf.share(pdf);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Etiquetas generadas en PDF A4')),
      );
    }
  }
}

class _FilaPrecio extends StatelessWidget {
  final String label;
  final double amount;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;

  const _FilaPrecio({
    required this.label,
    required this.amount,
    required this.accent,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white)),
            const Spacer(),
            Text(
              'S/. ${amount.toStringAsFixed(2)}',
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
            if (enabled) ...[
              const SizedBox(width: 8),
              const Icon(Icons.add_circle_outline,
                  size: 18, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
  }
}
