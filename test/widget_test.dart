import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intronews/ui/logo.dart';

void main() {
  testWidgets('logo draws IntroNews', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IntroNewsLogo())),
    );
    expect(find.text('Intro'), findsOneWidget);
    expect(find.text('News'), findsOneWidget);
  });
}
