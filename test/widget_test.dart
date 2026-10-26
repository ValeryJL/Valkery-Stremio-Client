import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Valkery app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Valkery Stremio Client'),
          ),
        ),
      ),
    );

    expect(find.text('Valkery Stremio Client'), findsOneWidget);
  });
}
