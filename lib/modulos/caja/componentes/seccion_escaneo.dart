import 'package:flutter/material.dart';
import 'package:bipenc/datos/modelos/producto.dart';

/// REFACTOR: Sección aislada de búsqueda/escaneo para el POS.
class SeccionEscaneo extends StatelessWidget {
  final TextEditingController searchCtrl;
  final bool buscando;
  final List<Producto> resultados;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final void Function(Producto) onTapProducto;
  final void Function(Producto) onDetalleProducto;

  const SeccionEscaneo({
    super.key,
    required this.searchCtrl,
    required this.buscando,
    required this.resultados,
    required this.onQueryChanged,
    required this.onClear,
    required this.onTapProducto,
    required this.onDetalleProducto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: TextField(
            controller: searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              hintText: 'Buscar por nombre, SKU o marca...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.teal, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (buscando)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.teal)),
                    ),
                  if (searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear,
                          color: Colors.white54, size: 20),
                      onPressed: onClear,
                    ),
                ],
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.07),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        if (resultados.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: resultados.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.white12),
              itemBuilder: (ctx, i) {
                final p = resultados[i];
                return ListTile(
                  dense: true,
                  title: Text(p.nombre,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text('${p.marca} • ${p.categoria}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('S/.${p.precioBase.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      if (p.precioMayorista < p.precioBase)
                        Text('May: S/.${p.precioMayorista.toStringAsFixed(2)}',
                            style:
                                const TextStyle(color: Colors.amber, fontSize: 10)),
                    ],
                  ),
                  onTap: () => onTapProducto(p),
                  onLongPress: () => onDetalleProducto(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
