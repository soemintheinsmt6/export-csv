import 'package:export_csv/src/convert/csv_writer.dart';
import 'package:export_csv/src/convert/output_naming.dart';
import 'package:export_csv/src/xlsx/cell_format.dart';
import 'package:export_csv/src/xlsx/cell_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('number formats', () {
    test('classifies built-in ids', () {
      expect(classifyNumberFormat(0, null), CellFormatKind.general);
      expect(classifyNumberFormat(14, null), CellFormatKind.date);
      expect(classifyNumberFormat(21, null), CellFormatKind.time);
      expect(classifyNumberFormat(22, null), CellFormatKind.dateTime);
    });

    test('reads custom format codes', () {
      expect(classifyFormatCode('dd/mm/yyyy'), CellFormatKind.date);
      expect(classifyFormatCode('yyyy-mm-dd hh:mm:ss'), CellFormatKind.dateTime);
      expect(classifyFormatCode('h:mm AM/PM'), CellFormatKind.time);
      expect(classifyFormatCode('mmm'), CellFormatKind.date);
      expect(classifyFormatCode('[h]:mm:ss'), CellFormatKind.time);
    });

    test('does not mistake money or science for dates', () {
      expect(classifyFormatCode(r'#,##0.00'), isNull);
      expect(classifyFormatCode(r'#,##0.00 "MMK"'), isNull);
      expect(classifyFormatCode(r'0.00E+00'), isNull);
      expect(classifyFormatCode(r'[Red]#,##0;[Red]-#,##0'), isNull);
      expect(classifyFormatCode(r'_-* #,##0.00_-;-* #,##0.00_-'), isNull);
    });
  });

  group('cell values', () {
    test('converts serials in both date systems', () {
      expect(
        excelSerialToDateTime(44927, date1904: false),
        DateTime.utc(2023, 1, 1),
      );
      expect(
        excelSerialToDateTime(0, date1904: true),
        DateTime.utc(1904, 1, 1),
      );
    });

    test('formats according to the cell format', () {
      expect(
        formatNumericCell('45000.75', CellFormatKind.date, date1904: false),
        '2023-03-15',
      );
      expect(
        formatNumericCell('45000.75', CellFormatKind.dateTime, date1904: false),
        '2023-03-15 18:00:00',
      );
      expect(
        formatNumericCell('0.5', CellFormatKind.time, date1904: false),
        '12:00:00',
      );
    });

    test('strips binary noise from stored numbers', () {
      expect(formatNumber('1234.5600000000002'), '1234.56');
      expect(formatNumber('0.30000000000000004'), '0.3');
      expect(formatNumber('42'), '42');
      expect(formatNumber('42.0'), '42');
      expect(formatNumber('-1250000'), '-1250000');
      expect(formatNumber('not a number'), 'not a number');
    });
  });

  group('csv encoding', () {
    test('quotes only what needs quoting', () {
      expect(CsvWriter.encodeField('plain'), 'plain');
      expect(CsvWriter.encodeField('a,b'), '"a,b"');
      expect(CsvWriter.encodeField('say "hi"'), '"say ""hi"""');
      expect(CsvWriter.encodeField('line\nbreak'), '"line\nbreak"');
      expect(CsvWriter.encodeField(''), '');
    });
  });

  group('output naming', () {
    test('builds Workbook(Sheet).csv', () {
      expect(csvFileName('Ledger 2024', 'January'), 'Ledger 2024(January).csv');
    });

    test('replaces characters a file system rejects', () {
      expect(csvFileName('AP/AR', 'Q1:Q2'), 'AP_AR(Q1_Q2).csv');
      expect(csvFileName('Book', ''), 'Book(Sheet).csv');
      expect(csvFileName('Book.', 'Sheet '), 'Book(Sheet).csv');
    });

    test('drops the tracking id an export tool appends', () {
      expect(
        tidyWorkbookName(
          '6-June-2026-61-MDY-Branch-Stock-Balance'
          '__ef86c541-70a3-4bf8-a1ae-736f125adb7c',
        ),
        '6-June-2026-61-MDY-Branch-Stock-Balance',
      );
      expect(
        tidyWorkbookName(
          'June-2026-Stock-Balance-All-Branch-1-1'
          '_70f634db-22e3-465c-914a-ce37d80382b4',
        ),
        'June-2026-Stock-Balance-All-Branch-1-1',
      );
      expect(
        tidyWorkbookName('Report_0123456789abcdef0123456789abcdef'),
        'Report',
      );
    });

    test('leaves ordinary names alone', () {
      expect(tidyWorkbookName('AR Ledger 2024'), 'AR Ledger 2024');
      // Not a UUID: a real name that merely contains dashes and digits.
      expect(tidyWorkbookName('Stock-Balance_2026-06-01'),
          'Stock-Balance_2026-06-01');
      // Stripping everything would leave nothing to name the file after.
      expect(
        tidyWorkbookName('_ef86c541-70a3-4bf8-a1ae-736f125adb7c'),
        '_ef86c541-70a3-4bf8-a1ae-736f125adb7c',
      );
    });

    test('keeps names unique within a run, ignoring case', () {
      final namer = OutputNamer();
      expect(namer.nameFor('Book', 'Jan'), 'Book(Jan).csv');
      expect(namer.nameFor('Book', 'jan'), 'Book(jan) (2).csv');
      expect(namer.nameFor('Book', 'Jan'), 'Book(Jan) (3).csv');
    });
  });
}
