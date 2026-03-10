import 'package:flutter/material.dart';
import '../../data/models/venta.dart';

class ChecklistModal extends StatefulWidget {
  final Venta venta;
  /// Callback al completar el checklist. Si [reimprimir] es true, se
  /// solicitará reimpresión del comprobante; en caso contrario solo se
  /// confirma el despacho.
  final Future<void> Function(bool reimprimir) onFinish;

  const ChecklistModal({
    super.key,
    required this.venta,
    required this.onFinish,
  });

  @override
  State<ChecklistModal> createState() => _ChecklistModalState();
}

class _ChecklistModalState extends State<ChecklistModal> {
  late List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(widget.venta.items.length, false);
  }

  @override
  Widget build(BuildContext context) {
    final allChecked = _checked.every((e) => e);

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.tealAccent),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Verificación de Despacho', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('Confirme que los productos están listos', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white38)),
            ],
          ),
          const Divider(height: 32, color: Colors.white10),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.venta.items.length,
              itemBuilder: (context, index) {
                final item = widget.venta.items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    value: _checked[index],
                    onChanged: (val) => setState(() => _checked[index] = val ?? false),
                    activeColor: Colors.tealAccent,
                    checkColor: Colors.black,
                    tileColor: Colors.white.withValues(alpha: 0.03),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(item.producto.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('${item.cantidad} x ${item.presentacion.name}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          if (allChecked)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await widget.onFinish(false);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('CONFIRMAR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: const BorderSide(color: Colors.tealAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await widget.onFinish(true);
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('VOLVER A IMPRIMIR'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.checklist),
              label: const Text('MARCA TODOS PARA CONTINUAR',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.grey.shade900,
                foregroundColor: Colors.white30,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
        ],
      ),
    );
  }
}
