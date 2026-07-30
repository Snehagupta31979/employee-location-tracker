import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:employee_tracker_app/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const EmployeeTrackerApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}