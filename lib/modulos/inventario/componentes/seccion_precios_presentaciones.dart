import 'package:flutter/material.dart';
import 'campos_formulario_producto.dart';
import 'borrador_presentacion.dart';

class SeccionPreciosPresentaciones extends StatelessWidget {
  final TextEditingController precioBaseCtrl;
  final TextEditingController precioMayoristaCtrl;
  final TextEditingController precioEspecialCtrl;
  final List<BorradorPresentacion> presentaciones;
  final VoidCallback onAgregarPresentacion;
  final void Function(int index) onEliminarPresentacion;

  const SeccionPreciosPresentaciones({
    super.key,
    required this.precioBaseCtrl,
    required this.precioMayoristaCtrl,
    required this.precioEspecialCtrl,
    required this.presentaciones,
    required this.onAgregarPresentacion,
    required this.onEliminarPresentacion,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CamposFormularioProducto.campoPrecio(
                precioBaseCtrl,
                'Precio Unitario *',
                validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Requerido'
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CamposFormularioProducto.campoPrecio(
                  precioMayoristaCtrl, 'Precio Mayorista'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: CamposFormularioProducto.campoPrecio(
                precioEspecialCtrl,
                'Precio Especial / Distribuidor',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ExpansionTile(
          collapsedIconColor: Colors.white70,
          iconColor: Colors.tealAccent,
          title: const Text('Presentaciones adicionales (dinámicas)',
              style: TextStyle(color: Colors.white)),
          subtitle: const Text(
              'Opcional: agrega las que necesites (docena, pack, caja, resma...)',
              style: TextStyle(color: Colors.white54)),
          children: [
            ...presentaciones.asMap().entries.map((entry) {
              final index = entry.key;
              final p = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CamposFormularioProducto.campo(
                              p.nombreCtrl,
                              'Nombre presentación ${index + 1}',
                              Icons.inventory_2_outlined,
                              hint: 'Ej: Pack x25 / Docena / Caja x50',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Eliminar presentación',
                            onPressed: () => onEliminarPresentacion(index),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: CamposFormularioProducto.campoNumero(
                              p.factorCtrl,
                              'Factor (unidades)',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CamposFormularioProducto.campoPrecio(
                              p.precioCtrl,
                              'Precio presentación',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAgregarPresentacion,
                icon: const Icon(Icons.add),
                label: const Text('Agregar presentación'),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ],
    );
  }
}
