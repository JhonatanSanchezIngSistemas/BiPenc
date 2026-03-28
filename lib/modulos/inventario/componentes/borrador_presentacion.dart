import 'package:flutter/material.dart';

class BorradorPresentacion {
  final TextEditingController nombreCtrl;
  final TextEditingController factorCtrl;
  final TextEditingController precioCtrl;

  BorradorPresentacion({
    String nombre = '',
    String factor = '',
    String precio = '',
  })  : nombreCtrl = TextEditingController(text: nombre),
        factorCtrl = TextEditingController(text: factor),
        precioCtrl = TextEditingController(text: precio);

  void dispose() {
    nombreCtrl.dispose();
    factorCtrl.dispose();
    precioCtrl.dispose();
  }
}
