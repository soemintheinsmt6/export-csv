import 'dart:io';

import 'package:export_csv/src/convert/conversion_models.dart';
import 'package:export_csv/src/convert/converter.dart';
import 'package:export_csv/src/convert/sheet_writer.dart';
import 'package:export_csv/src/convert/source_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixtures/workbook_builder.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('split_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  List<String> namesIn(String directory) => Directory(directory)
      .listSync()
      .map((entry) => p.basename(entry.path))
      .toList()
    ..sort();

  group('token estimate', () {
    test('counts Myanmar script far more heavily than Latin', () {
      // Both strings are 20 characters; only the token cost differs.
      expect(estimateTokens('a' * 20), 5);
      expect(estimateTokens('က' * 20), 20);
    });

    test('adds the two together', () {
      expect(estimateTokens('${'a' * 8}${'က' * 3}'), 2 + 3);
    });
  });

  group('SheetCsvWriter', () {
    test('writes one file when the sheet fits', () async {
      final writer = SheetCsvWriter(
        directory: temp.path,
        stem: 'Book(Sheet)',
        tokenBudget: 1000,
      );
      await writer.writeRow(['a', 'b']);
      await writer.writeRow(['1', '2']);
      final paths = await writer.close();

      expect(paths, hasLength(1));
      expect(namesIn(temp.path), ['Book(Sheet).csv']);
      expect(File(paths.single).readAsStringSync(), 'a,b\n1,2\n');
    });

    test('splits when the budget runs out, repeating the header', () async {
      final writer = SheetCsvWriter(
        directory: temp.path,
        stem: 'Book(Sheet)',
        // 'code,name\n' costs 3 tokens, each data row 4; two data rows plus the
        // header exceed 10, so the third row starts a new part.
        tokenBudget: 10,
      );
      await writer.writeRow(['code', 'name']);
      for (var i = 1; i <= 4; i++) {
        await writer.writeRow(['item$i', 'value$i']);
      }
      final paths = await writer.close();

      expect(paths.length, greaterThan(1));
      expect(namesIn(temp.path), [
        for (var i = 1; i <= paths.length; i++) 'Book(Sheet) part $i of ${paths.length}.csv',
      ]);
      for (final path in paths) {
        expect(File(path).readAsLinesSync().first, 'code,name',
            reason: 'every part must carry the header');
      }
      // No row is lost or duplicated: 4 data rows across the parts.
      final data = paths
          .expand((path) => File(path).readAsLinesSync().skip(1))
          .toList();
      expect(data, ['item1,value1', 'item2,value2', 'item3,value3', 'item4,value4']);
    });

    test('fills each part before starting the next', () async {
      final writer = SheetCsvWriter(
        directory: temp.path,
        stem: 'Book(Sheet)',
        tokenBudget: 100,
      );
      await writer.writeRow(['h']);
      for (var i = 0; i < 200; i++) {
        await writer.writeRow(['row$i']);
      }
      final paths = await writer.close();

      // Every part except the last should sit close under the budget rather
      // than being cut short.
      for (final path in paths.take(paths.length - 1)) {
        final tokens = estimateTokens(File(path).readAsStringSync());
        expect(tokens, lessThanOrEqualTo(100));
        expect(tokens, greaterThan(90));
      }
    });

    test('never splits a single oversized row', () async {
      final writer = SheetCsvWriter(
        directory: temp.path,
        stem: 'Book(Sheet)',
        tokenBudget: 5,
      );
      await writer.writeRow(['h']);
      await writer.writeRow(['x' * 400]);
      final paths = await writer.close();

      final long = paths
          .expand((path) => File(path).readAsLinesSync())
          .firstWhere((line) => line.startsWith('x'));
      expect(long.length, 400);
    });

    test('deleteAll removes every part', () async {
      final writer = SheetCsvWriter(
        directory: temp.path,
        stem: 'Book(Sheet)',
        tokenBudget: 10,
      );
      for (var i = 0; i < 20; i++) {
        await writer.writeRow(['row$i', 'value$i']);
      }
      await writer.close();
      writer.deleteAll();

      expect(namesIn(temp.path), isEmpty);
    });
  });

  group('header detection', () {
    test('uses row 1 when row 1 holds the column names', () {
      final rows = [
        ['', 'Code', 'Item', 'Group', 'Qty'],
        ['', 'IP11BCB', 'iPhone 11 Backglass', 'Parts', '8'],
      ];
      expect(SheetCsvWriter.chooseHeaderRows(rows), [rows[0]]);
    });

    test('carries the title row down to the real header row', () {
      // The shape a ledger export actually has: a summary line first, column
      // names underneath.
      final rows = [
        ['', '', 'YGN', '6069', 'Start Date', '2026-06-01', 'End Date'],
        ['', 'No.', 'Code', 'Item', 'Sub Group', 'Group', 'Opening'],
        ['', '3507', '1P12RTLORG', 'One Plus 12R', 'T + L ORG', 'One Plus', '0'],
      ];
      expect(SheetCsvWriter.chooseHeaderRows(rows), [rows[0], rows[1]]);
    });

    test('does not mistake a text-heavy data row for a header', () {
      final rows = [
        ['Code', 'Item', 'Qty', 'Price', 'Total'],
        ['IP11', 'iPhone 11 Backglass Black', '8', '1200', '9600'],
      ];
      expect(SheetCsvWriter.chooseHeaderRows(rows), [rows[0]]);
    });

    test('falls back to row 1 when nothing looks like a header', () {
      final rows = [
        ['1', '2', '3'],
        ['4', '5', '6'],
      ];
      expect(SheetCsvWriter.chooseHeaderRows(rows), [rows[0]]);
    });

    test('every part carries the whole header block', () async {
      final writer = SheetCsvWriter(
        directory: temp.path,
        stem: 'Book(Sheet)',
        tokenBudget: 40,
      );
      await writer.writeRow(['', '', 'YGN', '6069', 'Start Date', '2026-06-01']);
      await writer.writeRow(['', 'No.', 'Code', 'Item', 'Sub Group', 'Group']);
      for (var i = 1; i <= 40; i++) {
        await writer.writeRow(['', '$i', 'CODE$i', 'Item $i', 'Sub', 'Grp']);
      }
      final paths = await writer.close();

      expect(paths.length, greaterThan(1));
      for (final path in paths) {
        final lines = File(path).readAsLinesSync();
        expect(lines[0], startsWith(',,YGN,6069'));
        expect(lines[1], startsWith(',No.,Code,Item'));
      }
    });
  });

  group('conversion', () {
    test('splits an oversized sheet and leaves small ones alone', () async {
      final source = p.join(temp.path, 'Book.xlsx');
      final rows = StringBuffer('<row r="1">'
          '<c r="A1" t="inlineStr"><is><t>code</t></is></c>'
          '<c r="B1" t="inlineStr"><is><t>qty</t></is></c></row>');
      // Roughly 400k characters of Latin text: about 100k tokens, so this must
      // land in more than one file.
      for (var i = 2; i <= 12000; i++) {
        rows.write('<row r="$i">'
            '<c r="A$i" t="inlineStr"><is><t>ITEM-CODE-LONG-DESCRIPTION-$i</t></is></c>'
            '<c r="C$i" t="inlineStr"><is><t>Warehouse location row $i</t></is></c>'
            '<c r="B$i"><v>$i</v></c></row>');
      }

      writeFixtureWorkbook(source, sheets: [
        FixtureSheet('Big', rows.toString()),
        FixtureSheet('Small',
            '<row r="1"><c r="A1" t="inlineStr"><is><t>x</t></is></c></row>'),
      ]);

      final outputDirectory = p.join(temp.path, 'out');
      final outcome = await convertWorkbook(
        sourcePath: source,
        options: ConversionOptions(outputDirectory: outputDirectory),
      );

      final big = outcome.sheets.firstWhere((s) => s.sheetName == 'Big');
      final small = outcome.sheets.firstWhere((s) => s.sheetName == 'Small');

      expect(big.wasSplit, isTrue);
      expect(big.message, contains('Split into'));
      expect(small.wasSplit, isFalse);
      expect(namesIn(outputDirectory), contains('Book(Small).csv'));

      for (final path in big.outputPaths) {
        expect(estimateTokens(File(path).readAsStringSync()),
            lessThanOrEqualTo(defaultTokenBudget));
      }
      // Every data row survives the split.
      final dataRows = big.outputPaths
          .expand((path) => File(path).readAsLinesSync().skip(1))
          .length;
      expect(dataRows, 11999);
    });

    test('leaves sheets whole when splitting is turned off', () async {
      final source = p.join(temp.path, 'Book.xlsx');
      final rows = StringBuffer();
      for (var i = 1; i <= 12000; i++) {
        rows.write('<row r="$i">'
            '<c r="A$i" t="inlineStr"><is><t>ITEM-CODE-$i</t></is></c></row>');
      }
      writeFixtureWorkbook(source, sheets: [FixtureSheet('Big', rows.toString())]);

      final outputDirectory = p.join(temp.path, 'out');
      final outcome = await convertWorkbook(
        sourcePath: source,
        options: ConversionOptions(
          outputDirectory: outputDirectory,
          splitLargeSheets: false,
        ),
      );

      expect(outcome.sheets.single.wasSplit, isFalse);
      expect(namesIn(outputDirectory), ['Book(Big).csv']);
    });
  });
}
