import 'package:flutter/material.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';

class BarraInferiorCaja extends StatelessWidget {
  final ProveedorCaja pos;
  final VoidCallback onCobrar;
  const BarraInferiorCaja({super.key, required this.pos, required this.onCobrar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${pos.cantidadArticulos} art.',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('S/. ${pos.totalCobrar.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22)),
                ],
              ),
            ),
            if (pos.items.isNotEmpty)
              TextButton(
                onPressed: () => pos.vaciarCarrito(),
                child: const Text('Limpiar',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed:
                  pos.items.isEmpty || !pos.cobroHabilitado ? null : onCobrar,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('COBRAR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (!pos.cobroHabilitado)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 6),
                child: Text('Caja cerrada / modo inventario',
                    style: TextStyle(color: Colors.orange, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}
