import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme.light() builds a usable MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('Beauty Clinic POS')),
      ),
    );

    expect(find.text('Beauty Clinic POS'), findsOneWidget);
  });
}
