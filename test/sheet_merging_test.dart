import 'dart:io';

import 'package:export_csv/src/convert/conversion_models.dart';
import 'package:export_csv/src/convert/converter.dart';
import 'package:export_csv/src/convert/sheet_grouping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixtures/workbook_builder.dart';

void main() {
  group('parseSheetDate', () {
    test('reads the forms these ledgers actually use', () {
      expect(parseSheetDate('10-6-2026')?.iso, '2026-06-10');
      expect(parseSheetDate('1-Jun-26')?.iso, '2026-06-01');
      expect(parseSheetDate('13-June-2026')?.iso, '2026-06-13');
      expect(parseSheetDate('30-Jun-2026')?.iso, '2026-06-30');
      expect(parseSheetDate('26-Jan-2026')?.iso, '2026-01-26');
      expect(parseSheetDate('8-6-2026')?.iso, '2026-06-08');
      expect(parseSheetDate('2026-06-01')?.iso, '2026-06-01');
      expect(parseSheetDate('13 June 2026')?.iso, '2026-06-13');
    });

    test('keeps the label written after the date', () {
      final parsed = parseSheetDate('17-6-2026 Plan Ground');
      expect(parsed?.iso, '2026-06-17');
      expect(parsed?.label, 'Plan Ground');
      expect(parseSheetDate('10-6-2026')?.label, '');
    });

    test('rejects sheet names that are not dates', () {
      for (final name in [
        'Stock Balance',
        'Sheet3',
        'List',
        'ယာယီ risk',
        'Main item Comparison',
        '1-2-3', // too short to be a year
        '32-6-2026', // no such day
        '31-Jun-2026', // June has 30 days
        '10-13-2026', // no such month
      ]) {
        expect(parseSheetDate(name), isNull, reason: name);
      }
    });

    test('does not read a day range as a year', () {
      // Real tab names: the 23rd and 24th of June on one sheet, and the 21st
      // and 22nd on another. Read as ISO dates these become the years 2324 and
      // 2122, which would drag them into the wrong daily run.
      expect(parseSheetDate('2324-6-26'), isNull);
      expect(parseSheetDate('2122-6-26'), isNull);
      // A genuine ISO date is still read.
      expect(parseSheetDate('2026-6-26')?.iso, '2026-06-26');
    });
  });

  group('groupSheets', () {
    test('leaves every sheet alone when merging is off', () {
      final groups = groupSheets(['1-6-2026', '2-6-2026'], merge: false);
      expect(groups.map((g) => g.label), ['1-6-2026', '2-6-2026']);
      expect(groups.every((g) => !g.isMerged), isTrue);
    });

    test('collects the daily run and names it by its span', () {
      final groups = groupSheets(
        ['List', '1-6-2026', 'Stock Balance', '2-6-2026', '30-Jun-2026'],
        merge: true,
      );
      expect(groups.map((g) => g.label), [
        'List',
        'Daily 2026-06-01 to 2026-06-30',
        'Stock Balance',
      ]);
      final daily = groups[1];
      expect(daily.members, [1, 3, 4]);
      expect(daily.dates, ['2026-06-01', '2026-06-02', '2026-06-30']);
    });

    test('keeps a labelled series apart from the plain dailies', () {
      final groups = groupSheets(
        ['1-6-2026', '2-6-2026', '17-6-2026 Plan Ground', '18-6-2026 Plan Ground'],
        merge: true,
      );
      expect(groups.map((g) => g.label), [
        'Daily 2026-06-01 to 2026-06-02',
        'Daily 2026-06-17 to 2026-06-18 Plan Ground',
      ]);
    });

    test('does not rename a lone dated sheet', () {
      final groups = groupSheets(['List', '1-6-2026'], merge: true);
      expect(groups.map((g) => g.label), ['List', '1-6-2026']);
      expect(groups.last.isMerged, isFalse);
    });
  });

  group('merged output', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('merge_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    String sheetXml(int startRow, List<List<String>> rows) {
      final buffer = StringBuffer();
      for (var r = 0; r < rows.length; r++) {
        final rowNumber = startRow + r;
        buffer.write('<row r="$rowNumber">');
        for (var c = 0; c < rows[r].length; c++) {
          final ref = '${String.fromCharCode(0x41 + c)}$rowNumber';
          buffer.write(
            '<c r="$ref" t="inlineStr"><is><t>${rows[r][c]}</t></is></c>',
          );
        }
        buffer.write('</row>');
      }
      return buffer.toString();
    }

    test('merges dailies into one file with a date column', () async {
      final source = p.join(temp.path, 'Branch.xlsx');
      writeFixtureWorkbook(source, sheets: [
        FixtureSheet('List', sheetXml(1, [
          ['Code', 'Item', 'Group'],
          ['A1', 'Widget', 'Parts'],
        ])),
        FixtureSheet('1-6-2026', sheetXml(1, [
          ['Code', 'Item', 'Qty'],
          ['A1', 'Widget', '5'],
          ['A2', 'Gadget', '7'],
        ])),
        FixtureSheet('2-Jun-2026', sheetXml(1, [
          ['Code', 'Item', 'Qty'],
          ['A3', 'Doohickey', '2'],
        ])),
      ]);

      final out = p.join(temp.path, 'out');
      final outcome = await convertWorkbook(
        sourcePath: source,
        options: ConversionOptions(
          outputDirectory: out,
          mergeDailySheets: true,
        ),
      );

      final names = Directory(out).listSync().map((e) => p.basename(e.path)).toSet();
      expect(names, {
        'Branch(List).csv',
        'Branch(Daily 2026-06-01 to 2026-06-02).csv',
      });

      final merged = File(
        p.join(out, 'Branch(Daily 2026-06-01 to 2026-06-02).csv'),
      ).readAsStringSync();
      expect(merged, [
        'Sheet date,Code,Item,Qty',
        '2026-06-01,A1,Widget,5',
        '2026-06-01,A2,Gadget,7',
        '2026-06-02,A3,Doohickey,2',
        '',
      ].join('\n'));

      final daily = outcome.sheets
          .firstWhere((s) => s.sheetName.startsWith('Daily'));
      expect(daily.wasMerged, isTrue);
      expect(daily.mergedSheetCount, 2);
      expect(daily.message, contains('Merged 2 daily sheets'));
    });

    test('carries a title row above the column names into the merged header',
        () async {
      final source = p.join(temp.path, 'Branch.xlsx');
      final opening = [
        ['', 'YGN', 'Start Date', '2026-06-01'],
        ['No.', 'Code', 'Item', 'Group'],
      ];
      writeFixtureWorkbook(source, sheets: [
        FixtureSheet('1-6-2026', sheetXml(1, [
          ...opening,
          ['1', 'A1', 'Widget', 'Parts'],
        ])),
        FixtureSheet('2-6-2026', sheetXml(1, [
          ...opening,
          ['2', 'A2', 'Gadget', 'Parts'],
        ])),
      ]);

      final out = p.join(temp.path, 'out');
      await convertWorkbook(
        sourcePath: source,
        options: ConversionOptions(
          outputDirectory: out,
          mergeDailySheets: true,
        ),
      );

      final lines = File(Directory(out).listSync().single.path).readAsLinesSync();
      expect(lines, [
        ',,YGN,Start Date,2026-06-01',
        'Sheet date,No.,Code,Item,Group',
        '2026-06-01,1,A1,Widget,Parts',
        '2026-06-02,2,A2,Gadget,Parts',
      ]);
    });

    test('keeps rows of a differently shaped day rather than dropping them',
        () async {
      final source = p.join(temp.path, 'Branch.xlsx');
      writeFixtureWorkbook(source, sheets: [
        FixtureSheet('1-6-2026', sheetXml(1, [
          ['Code', 'Item', 'Qty'],
          ['A1', 'Widget', '5'],
        ])),
        // Same series, but this day's sheet opens straight into data.
        FixtureSheet('2-6-2026', sheetXml(1, [
          ['A2', 'Gadget', '7'],
        ])),
      ]);

      final out = p.join(temp.path, 'out');
      await convertWorkbook(
        sourcePath: source,
        options: ConversionOptions(
          outputDirectory: out,
          mergeDailySheets: true,
        ),
      );

      final lines = File(Directory(out).listSync().single.path).readAsLinesSync();
      expect(lines, [
        'Sheet date,Code,Item,Qty',
        '2026-06-01,A1,Widget,5',
        '2026-06-02,A2,Gadget,7',
      ]);
    });

    test('is off by default, so one sheet still means one file', () async {
      final source = p.join(temp.path, 'Branch.xlsx');
      writeFixtureWorkbook(source, sheets: [
        FixtureSheet('1-6-2026', sheetXml(1, [['Code'], ['A1']])),
        FixtureSheet('2-6-2026', sheetXml(1, [['Code'], ['A2']])),
      ]);

      final out = p.join(temp.path, 'out');
      await convertWorkbook(
        sourcePath: source,
        options: ConversionOptions(outputDirectory: out),
      );

      expect(
        Directory(out).listSync().map((e) => p.basename(e.path)).toSet(),
        {'Branch(1-6-2026).csv', 'Branch(2-6-2026).csv'},
      );
    });
  });
}
