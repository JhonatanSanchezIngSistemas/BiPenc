import 'package:bipenc/features/pos/pos_provider.dart';
import 'package:bipenc/features/pos/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PosScreen renderiza elementos base', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PosProvider(testMode: true),
        child: const MaterialApp(
          home: PosScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Carrito vacío'), findsOneWidget);
    expect(find.textContaining('Buscar por nombre'), findsOneWidget);
    expect(find.text('COBRAR'), findsOneWidget);
  });
}
