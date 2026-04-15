import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slides/main.dart';

void main() {
  testWidgets('Slide show loads bundled slides', (WidgetTester tester) async {
    await tester.pumpWidget(const SlidesApp());
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
