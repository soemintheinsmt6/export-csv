import 'dart:io';

import 'package:export_csv/src/convert/conversion_models.dart';
import 'package:export_csv/src/convert/conversion_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixtures/workbook_builder.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('runner_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('converts a batch in a background isolate and reports progress',
      () async {
    final outputDirectory = p.join(temp.path, 'out');

    // Two workbooks, one of them large enough that rows are streamed rather
    // than held in memory.
    final ledger = p.join(temp.path, 'Ledger 01.xlsx');
    writeFixtureWorkbook(
      ledger,
      sharedStrings: ['Date', 'Particulars', 'Debit', 'Credit'],
      sheets: [
        FixtureSheet('Jan', _headerRow() + _dataRows(5000)),
        FixtureSheet('Feb', _headerRow() + _dataRows(10)),
      ],
    );

    final summary = p.join(temp.path, 'Ledger 02.xlsx');
    writeFixtureWorkbook(
      summary,
      sheets: [FixtureSheet('Summary', _headerRow() + _dataRows(3))],
    );

    final events = <ConversionEvent>[];
    await ConversionRunner()
        .start(
          [ledger, summary],
          ConversionOptions(outputDirectory: outputDirectory),
        )
        .forEach(events.add);

    expect(events.last, isA<BatchFinished>());
    expect(events.whereType<WorkbookStarted>().map((e) => e.sheetCount), [2, 1]);
    expect(events.whereType<SheetStarted>(), hasLength(3));

    final files = Directory(outputDirectory)
        .listSync()
        .map((entry) => p.basename(entry.path))
        .toSet();
    expect(files, {
      'Ledger 01(Jan).csv',
      'Ledger 01(Feb).csv',
      'Ledger 02(Summary).csv',
    });

    final januaryLines =
        File(p.join(outputDirectory, 'Ledger 01(Jan).csv')).readAsLinesSync();
    expect(januaryLines, hasLength(5001)); // header plus data
    expect(januaryLines.first, 'Date,Particulars,Debit,Credit');
    // A date serial, a cached formula result and money, in that order.
    expect(januaryLines[1], '2023-03-15,Row 1,1234.56,0');
  });
}

String _headerRow() =>
    '<row r="1">'
    '<c r="A1" t="s"><v>0</v></c>'
    '<c r="B1" t="s"><v>1</v></c>'
    '<c r="C1" t="s"><v>2</v></c>'
    '<c r="D1" t="s"><v>3</v></c>'
    '</row>';

String _dataRows(int count) {
  final buffer = StringBuffer();
  for (var i = 1; i <= count; i++) {
    final row = i + 1;
    buffer
      ..write('<row r="$row">')
      ..write('<c r="A$row" s="1"><v>45000</v></c>')
      ..write('<c r="B$row" t="inlineStr"><is><t>Row $i</t></is></c>')
      ..write('<c r="C$row" s="3"><f>D$row+1234.56</f><v>1234.5600000000002</v></c>')
      ..write('<c r="D$row" s="3"><v>0</v></c>')
      ..write('</row>');
  }
  return buffer.toString();
}
