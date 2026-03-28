import 'package:flutter/material.dart';

class CamposFormularioProducto {
  CamposFormularioProducto._();

  static Widget campo(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDeco(label, icon, hint: hint),
    );
  }

  static Widget campoPrecio(
    TextEditingController ctrl,
    String label, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDeco(label, Icons.attach_money).copyWith(
        prefixText: 'S/. ',
        prefixStyle:
            const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
      ),
    );
  }

  static Widget campoNumero(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDeco(label, Icons.functions_outlined),
    );
  }

  static InputDecoration decoracion(String label, IconData icon, {String? hint}) {
    return _inputDeco(label, icon, hint: hint);
  }

  static InputDecoration _inputDeco(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white54),
      hintStyle: const TextStyle(color: Colors.white24),
      prefixIcon: Icon(icon, color: Colors.teal),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.teal),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}
