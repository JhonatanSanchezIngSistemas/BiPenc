import 'package:flutter/material.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/ui/modales/modal_detalle_producto.dart';
import 'hoja_vincular_codigo.dart';

/// REFACTOR: Resumen del carrito en componente reutilizable.
class ResumenCarrito extends StatelessWidget {
  final ProveedorCaja pos;
  final Future<void> Function() onScanProduct;
  const ResumenCarrito({super.key, required this.pos, required this.onScanProduct});

  @override
  Widget build(BuildContext context) {
    if (pos.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_cart_outlined,
                size: 64, color: Colors.white12),
            const SizedBox(height: 12),
            const Text('Carrito vacío',
                style: TextStyle(color: Colors.white24, fontSize: 16)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onScanProduct,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('ESCANEAR PRODUCTO'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                foregroundColor: Colors.tealAccent,
                side: const BorderSide(color: Colors.teal),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: pos.items.length,
      itemBuilder: (ctx, i) => FilaItemCarrito(
        index: i,
        item: pos.items[i],
        pos: pos,
      ),
    );
  }
}

class FilaItemCarrito extends StatelessWidget {
  final int index;
  final ItemCarrito item;
  final ProveedorCaja pos;
  const FilaItemCarrito({super.key, required this.index, required this.item, required this.pos});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('item_${index}_${item.producto.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.red.shade800,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => pos.eliminarItem(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          onLongPress: () => _editarItemCompleto(context),
          title: Text(item.producto.nombre,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              IconButton(
                iconSize: 30,
                color: Colors.white70,
                onPressed: () => pos.actualizarCantidad(index, -1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.cantidad}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                iconSize: 30,
                color: Colors.tealAccent,
                onPressed: () => pos.actualizarCantidad(index, 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 8),
              if (item.producto.precioMayorista < item.producto.precioBase)
                GestureDetector(
                  onTap: () => pos.toggleMayorista(index),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      item.etiquetaPrecio,
                      style: TextStyle(
                        color: item.presentacion.id == 'mayo'
                            ? Colors.tealAccent
                            : Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          trailing: GestureDetector(
            onLongPress: () => _editarPrecio(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('S/.${item.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text('@${item.precioActual.toStringAsFixed(2)}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editarPrecio(BuildContext context) {
    final ctrl =
        TextEditingController(text: item.precioActual.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Precio Especial',
            style: TextStyle(color: Colors.white)),
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
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              final p = double.tryParse(ctrl.text);
              if (p != null && p > 0) pos.setPrecioManual(index, p);
              Navigator.pop(ctx);
            },
            child: const Text('Aplicar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _editarItemCompleto(BuildContext context) {
    if (item.producto.id.startsWith('GEN-')) {
      _mostrarDialogoEdicionGenerico(context);
      return;
    }

    // Para productos reales: opciones incluyendo edición y corrección de vínculo
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white70),
              title: const Text('Ver detalle / Editar precio',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ModalDetalleProducto(
                    producto: item.producto,
                    onApplyManualPrice: (precio) =>
                        pos.setPrecioManual(index, precio),
                  ),
                );
              },
            ),
            // Botón Corregir Vínculo — solo si el producto tiene código de barras
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: Colors.tealAccent),
              title: const Text('Corregir vínculo de código',
                  style: TextStyle(color: Colors.tealAccent)),
              subtitle: const Text(
                '¿El código escaneado era de otro producto?',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                // Obtener el código de barras actual del primer presentación
                final codigo = item.producto.presentaciones.isNotEmpty
                    ? (item.producto.presentaciones.first.barcode ?? item.producto.skuCode)
                    : item.producto.skuCode;
                await showHojaVincularCodigo(
                  context,
                  pos: pos,
                  codigoBarras: codigo,
                  productoAntiguo: item.producto,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoEdicionGenerico(BuildContext context) {
    final nombreCtrl = TextEditingController(text: item.producto.nombre);
    final precioCtrl =
        TextEditingController(text: item.precioActual.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Editar Producto Rápido',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Nombre',
                  labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: precioCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Precio',
                labelStyle: TextStyle(color: Colors.white54),
                prefixText: 'S/. ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final p = double.tryParse(precioCtrl.text.replaceAll(',', '.'));
              if (p != null) {
                pos.editarItemGenerico(index, nombreCtrl.text.trim(), p);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
