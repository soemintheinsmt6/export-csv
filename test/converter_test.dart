import 'dart:io';

import 'package:export_csv/src/convert/conversion_models.dart';
import 'package:export_csv/src/convert/converter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixtures/workbook_builder.dart';

void main() {
  late Directory temp;
  late String outputDirectory;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('converter_test');
    outputDirectory = p.join(temp.path, 'out');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  ConversionOptions options({
    bool includeHiddenSheets = true,
    bool keepBlankRows = false,
    bool addBom = false,
  }) =>
      ConversionOptions(
        outputDirectory: outputDirectory,
        includeHiddenSheets: includeHiddenSheets,
        keepBlankRows: keepBlankRows,
        addBom: addBom,
      );

  String textRow(int row, List<String> values) {
    final cells = <String>[];
    for (var i = 0; i < values.length; i++) {
      final ref = '${String.fromCharCode(0x41 + i)}$row';
      cells.add('<c r="$ref" t="inlineStr"><is><t>${values[i]}</t></is></c>');
    }
    return '<row r="$row">${cells.join()}</row>';
  }

  test('writes one CSV per sheet, named Workbook(Sheet).csv', () async {
    final source = p.join(temp.path, 'AR Ledger 2024.xlsx');
    writeFixtureWorkbook(
      source,
      sheets: [
        FixtureSheet('January', textRow(1, ['Date', 'Amount'])),
        FixtureSheet('February', textRow(1, ['Date', 'Amount'])),
      ],
    );

    final outcome = await convertWorkbook(
      sourcePath: source,
      options: options(),
    );

    expect(outcome.error, isNull);
    expect(outcome.convertedCount, 2);
    expect(
      Directory(outputDirectory).listSync().map((e) => p.basename(e.path)).toSet(),
      {'AR Ledger 2024(January).csv', 'AR Ledger 2024(February).csv'},
    );
  });

  test('escapes fields and separates rows', () async {
    final source = p.join(temp.path, 'Book.xlsx');
    writeFixtureWorkbook(
      source,
      sheets: [
        FixtureSheet(
          'Sheet1',
          '${textRow(1, ['Name', 'Note'])}'
          '<row r="2">'
          '<c r="A2" t="inlineStr"><is><t>Aung, U</t></is></c>'
          '<c r="B2" t="inlineStr"><is><t>said "ok"</t></is></c>'
          '</row>',
        ),
      ],
    );

    await convertWorkbook(sourcePath: source, options: options());

    final csv = File(p.join(outputDirectory, 'Book(Sheet1).csv')).readAsStringSync();
    expect(csv, 'Name,Note\n"Aung, U","said ""ok"""\n');
  });

  test('skips empty sheets without leaving a file behind', () async {
    final source = p.join(temp.path, 'Book.xlsx');
    writeFixtureWorkbook(
      source,
      sheets: [
        FixtureSheet('Data', textRow(1, ['x'])),
        FixtureSheet('Blank', '<row r="1"><c r="A1"/></row>'),
      ],
    );

    final outcome = await convertWorkbook(sourcePath: source, options: options());

    expect(outcome.sheets.map((s) => s.status),
        [SheetStatus.converted, SheetStatus.empty]);
    expect(File(p.join(outputDirectory, 'Book(Blank).csv')).existsSync(), isFalse);
  });

  test('drops blank rows by default and rebuilds gaps when asked', () async {
    final source = p.join(temp.path, 'Book.xlsx');
    final rows = '${textRow(3, ['first'])}${textRow(6, ['second'])}';
    writeFixtureWorkbook(source, sheets: [FixtureSheet('Sheet1', rows)]);

    await convertWorkbook(sourcePath: source, options: options());
    expect(
      File(p.join(outputDirectory, 'Book(Sheet1).csv')).readAsStringSync(),
      'first\nsecond\n',
    );

    Directory(outputDirectory).deleteSync(recursive: true);
    await convertWorkbook(
      sourcePath: source,
      options: options(keepBlankRows: true),
    );
    // The two blank rows between them are restored; the ones above row 3 are
    // not, because leading blank rows carry no information.
    expect(
      File(p.join(outputDirectory, 'Book(Sheet1).csv')).readAsStringSync(),
      'first\n\n\nsecond\n',
    );
  });

  test('can leave hidden sheets out', () async {
    final source = p.join(temp.path, 'Book.xlsx');
    writeFixtureWorkbook(
      source,
      sheets: [
        FixtureSheet('Visible', textRow(1, ['x'])),
        FixtureSheet('Rates', textRow(1, ['y']), hidden: true),
      ],
    );

    final outcome = await convertWorkbook(
      sourcePath: source,
      options: options(includeHiddenSheets: false),
    );

    expect(outcome.sheets.last.status, SheetStatus.hidden);
    expect(Directory(outputDirectory).listSync().length, 1);
  });

  test('reports a workbook it cannot open instead of failing the run', () async {
    final broken = p.join(temp.path, 'Broken.xlsx');
    File(broken).writeAsStringSync('this is not a workbook');
    final good = p.join(temp.path, 'Good.xlsx');
    writeFixtureWorkbook(good, sheets: [FixtureSheet('S', textRow(1, ['x']))]);

    final events = <ConversionEvent>[];
    await runConversion(
      sources: [broken, good],
      options: options(),
      emit: events.add,
    );

    final finished = events.whereType<WorkbookFinished>().toList();
    expect(finished, hasLength(2));
    expect(finished.first.outcome.error, isNotNull);
    expect(finished.last.outcome.convertedCount, 1);
    expect(events.last, isA<BatchFinished>());
  });

  test('gives colliding sheet names distinct file names', () async {
    final source = p.join(temp.path, 'Book.xlsx');
    writeFixtureWorkbook(
      source,
      sheets: [
        FixtureSheet('Q1/Q2', textRow(1, ['a'])),
        FixtureSheet('Q1:Q2', textRow(1, ['b'])),
      ],
    );

    await convertWorkbook(sourcePath: source, options: options());

    final names = Directory(outputDirectory)
        .listSync()
        .map((e) => p.basename(e.path))
        .toSet();
    expect(names, {'Book(Q1_Q2).csv', 'Book(Q1_Q2) (2).csv'});
  });

  test('names files after the ledger, not the export id', () async {
    final source = p.join(
      temp.path,
      'Stock-Balance__ef86c541-70a3-4bf8-a1ae-736f125adb7c.xlsx',
    );
    writeFixtureWorkbook(
      source,
      sheets: [FixtureSheet('June', textRow(1, ['x']))],
    );

    await convertWorkbook(sourcePath: source, options: options());
    expect(
      File(p.join(outputDirectory, 'Stock-Balance(June).csv')).existsSync(),
      isTrue,
    );

    Directory(outputDirectory).deleteSync(recursive: true);
    await convertWorkbook(
      sourcePath: source,
      options: ConversionOptions(
        outputDirectory: outputDirectory,
        tidyFileNames: false,
      ),
    );
    expect(
      Directory(outputDirectory).listSync().single.path,
      endsWith('Stock-Balance__ef86c541-70a3-4bf8-a1ae-736f125adb7c(June).csv'),
    );
  });

  test('writes a BOM only when asked', () async {
    final source = p.join(temp.path, 'Book.xlsx');
    writeFixtureWorkbook(
      source,
      sheets: [FixtureSheet('Sheet1', textRow(1, ['x']))],
    );

    await convertWorkbook(sourcePath: source, options: options(addBom: true));

    final bytes =
        File(p.join(outputDirectory, 'Book(Sheet1).csv')).readAsBytesSync();
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
  });
}
