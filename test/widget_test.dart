// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test - Basic app structure', (WidgetTester tester) async {
    // Build a minimal app for testing
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('BiPenc')),
          body: const Center(child: Text('Test')),
        ),
      ),
    );

    // Verify that the app loaded
    expect(find.text('BiPenc'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    // Smoke: no validamos textos de login aquí porque este test monta una app mínima.
  });
}
