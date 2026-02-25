import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/product.dart';
import '../../data/local/db_helper.dart';

/// Formulario de carga rápida — Constitución BiPenc Artículo 3.1
/// Nombre, Precio Base, Precio Mayorista (opcional), Categoría.
/// Ideal cuando hay cola y no hay tiempo para fotos.
class QuickAddForm extends StatefulWidget {
  const QuickAddForm({super.key});

  @override
  State<QuickAddForm> createState() => _QuickAddFormState();
}

class _QuickAddFormState extends State<QuickAddForm> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _precioMayoristaCtrl = TextEditingController();
  String _categoria = 'Escritura';
  bool _guardando = false;

  static const _categorias = ['Escritura', 'Arte', 'Cuadernos', 'Papelería', 'Otro'];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _precioMayoristaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final precioBase = double.tryParse(_precioCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final precioMayorista = double.tryParse(_precioMayoristaCtrl.text.replaceAll(',', '.')) ?? 0.0;

    // SKU auto-generado con prefijo QK (Quick) para identificar productos pendientes de completar
    final sku = 'QK-${Random().nextInt(99999).toString().padLeft(5, '0')}';

    final product = Product(
      sku: sku,
      nombre: _nombreCtrl.text.trim(),
      marca: '',
      categoria: _categoria,
      precioBase: precioBase,
      precioMayorista: precioMayorista,
    );

    try {
      await DBHelper().insertProduct(product);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${product.nombre} guardado (pendiente de completar)'),
            backgroundColor: Colors.orange.shade700,
            action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('⚡ Carga Rápida'),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Aviso de pendiente
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade700),
              ),
              child: const Row(
                children: [
                  Icon(Icons.pending_actions, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Este producto quedará como PENDIENTE.\nPuedes completar marca, foto y SKU después.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nombre (requerido)
            _campo(
              _nombreCtrl, 'Nombre del producto *', Icons.label_outline,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 14),

            // Categoría
            DropdownButtonFormField<String>(
              value: _categoria,
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('Categoría', Icons.category_outlined),
              items: _categorias
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _categoria = v!),
            ),
            const SizedBox(height: 14),

            // Precios
            Row(
              children: [
                Expanded(
                  child: _campoPrecio(
                    _precioCtrl, 'Precio Unitario *',
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campoPrecio(_precioMayoristaCtrl, 'P. Mayor 3+'),
                ),
              ],
            ),
            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Icon(Icons.flash_on),
              label: const Text('Guardar Rápido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(TextEditingController ctrl, String label, IconData icon,
      {String? Function(String?)? validator}) =>
      TextFormField(
        controller: ctrl,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: _deco(label, icon),
      );

  Widget _campoPrecio(TextEditingController ctrl, String label,
      {String? Function(String?)? validator}) =>
      TextFormField(
        controller: ctrl,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _deco(label, Icons.attach_money).copyWith(
          prefixText: 'S/. ',
          prefixStyle: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
        ),
      );

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.orange),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
      );
}
