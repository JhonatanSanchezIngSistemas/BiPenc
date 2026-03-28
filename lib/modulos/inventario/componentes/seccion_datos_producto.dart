import 'package:flutter/material.dart';
import 'campos_formulario_producto.dart';

class SeccionDatosProducto extends StatelessWidget {
  final TextEditingController skuCtrl;
  final TextEditingController nombreCtrl;
  final TextEditingController marcaCtrl;
  final TextEditingController descripcionCtrl;
  final List<String> marcasSugeridas;
  final List<String> categorias;
  final String categoriaSeleccionada;
  final String nuevaCategoriaLabel;
  final VoidCallback onEscanearSku;
  final VoidCallback onNuevaCategoria;
  final ValueChanged<String> onCategoriaSeleccionada;
  final VoidCallback onEliminarCategoria;
  final bool puedeEliminarCategoria;
  final VoidCallback onSugerirDescripcion;
  final ValueChanged<String> onSeleccionarMarca;

  const SeccionDatosProducto({
    super.key,
    required this.skuCtrl,
    required this.nombreCtrl,
    required this.marcaCtrl,
    required this.descripcionCtrl,
    required this.marcasSugeridas,
    required this.categorias,
    required this.categoriaSeleccionada,
    required this.nuevaCategoriaLabel,
    required this.onEscanearSku,
    required this.onNuevaCategoria,
    required this.onCategoriaSeleccionada,
    required this.onEliminarCategoria,
    required this.puedeEliminarCategoria,
    required this.onSugerirDescripcion,
    required this.onSeleccionarMarca,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CamposFormularioProducto.campo(
                skuCtrl,
                'SKU / Código',
                Icons.qr_code,
                hint: 'Ej: LAP-FA-001 (vacío = auto)',
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
              ),
              onPressed: onEscanearSku,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        const SizedBox(height: 14),
        CamposFormularioProducto.campo(
          nombreCtrl,
          'Nombre del Producto',
          Icons.label_outline,
          validator: (v) => v == null || v.trim().isEmpty
              ? 'El nombre es requerido'
              : null,
        ),
        const SizedBox(height: 14),
        CamposFormularioProducto.campo(
          marcaCtrl,
          'Marca',
          Icons.branding_watermark_outlined,
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: marcaCtrl,
          builder: (context, value, _) {
            if (marcasSugeridas.isEmpty) return const SizedBox.shrink();
            final filtro = value.text.trim().toLowerCase();
            final sugeridas = marcasSugeridas
                .where((m) => filtro.isEmpty
                    ? true
                    : m.toLowerCase().contains(filtro))
                .take(8)
                .toList();
            if (sugeridas.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: sugeridas
                    .map((m) => ActionChip(
                          label: Text(m),
                          onPressed: () => onSeleccionarMarca(m),
                        ))
                    .toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: categoriaSeleccionada,
                dropdownColor: Colors.grey.shade900,
                style: const TextStyle(color: Colors.white),
                decoration: CamposFormularioProducto.decoracion(
                    'Categoría', Icons.category_outlined),
                items: [
                  ...categorias
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  DropdownMenuItem(
                    value: nuevaCategoriaLabel,
                    child: Text(
                      nuevaCategoriaLabel,
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v == nuevaCategoriaLabel) {
                    onNuevaCategoria();
                  } else {
                    onCategoriaSeleccionada(v);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
              tooltip: 'Eliminar categoría',
              onPressed: puedeEliminarCategoria ? onEliminarCategoria : null,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 14),
        CamposFormularioProducto.campo(
          descripcionCtrl,
          'Descripción',
          Icons.description_outlined,
          hint: 'Detalles del producto...',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onSugerirDescripcion,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Sugerir descripción'),
          ),
        ),
      ],
    );
  }
}
