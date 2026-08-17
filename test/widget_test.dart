import 'package:export_csv/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on the empty queue with conversion disabled',
      (tester) async {
    await tester.pumpWidget(const ExportCsvApp());

    expect(find.text('Drag your ledgers here'), findsOneWidget);
    expect(find.text('No workbooks added yet.'), findsOneWidget);

    final convert = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Convert'),
    );
    expect(convert.onPressed, isNull);
  });
}
