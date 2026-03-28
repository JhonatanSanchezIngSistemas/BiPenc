import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/modulos/caja/pantalla_caja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PantallaCaja renderiza elementos base', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProveedorCaja(testMode: true),
        child: const MaterialApp(
          home: PantallaCaja(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Carrito vacío'), findsOneWidget);
    expect(find.textContaining('Buscar por nombre'), findsOneWidget);
    expect(find.text('COBRAR'), findsOneWidget);
  });
}
