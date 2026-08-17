import 'dart:io';

import 'package:export_csv/src/xlsx/xlsx_workbook.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fixtures/workbook_builder.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('xlsx_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  String workbookAt(
    String name, {
    required List<FixtureSheet> sheets,
    List<String> sharedStrings = const [],
    bool date1904 = false,
  }) {
    final path = p.join(temp.path, name);
    writeFixtureWorkbook(
      path,
      sheets: sheets,
      sharedStrings: sharedStrings,
      date1904: date1904,
    );
    return path;
  }

  List<List<String>> rowsOf(XlsxWorkbook book, int sheetIndex) =>
      book.readRows(book.sheets[sheetIndex]).map((row) => row.cells).toList();

  test('lists sheets in tab order and reports hidden ones', () {
    final path = workbookAt(
      'Ledger.xlsx',
      sheets: [
        FixtureSheet('January', '<row r="1"><c r="A1"><v>1</v></c></row>'),
        FixtureSheet('Lookups', '<row r="1"><c r="A1"><v>2</v></c></row>',
            hidden: true),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    expect(book.sheets.map((s) => s.name), ['January', 'Lookups']);
    expect(book.sheets.map((s) => s.hidden), [false, true]);
  });

  test('reads shared strings, inline strings, numbers and booleans', () {
    final path = workbookAt(
      'Ledger.xlsx',
      sharedStrings: ['Date', 'Description', 'ကျပ်'],
      sheets: [
        FixtureSheet(
          'Sheet1',
          '<row r="1">'
          '<c r="A1" t="s"><v>0</v></c>'
          '<c r="B1" t="s"><v>1</v></c>'
          '<c r="C1" t="s"><v>2</v></c>'
          '</row>'
          '<row r="2">'
          '<c r="A2"><v>42</v></c>'
          '<c r="B2" t="inlineStr"><is><t>Opening balance</t></is></c>'
          '<c r="C2" t="b"><v>1</v></c>'
          '</row>',
        ),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    expect(rowsOf(book, 0), [
      ['Date', 'Description', 'ကျပ်'],
      ['42', 'Opening balance', 'TRUE'],
    ]);
  });

  test('uses the cached result of a formula, not the formula text', () {
    final path = workbookAt(
      'Ledger.xlsx',
      sheets: [
        FixtureSheet(
          'Totals',
          '<row r="1">'
          '<c r="A1"><f>SUM(B1:B9)</f><v>1234.5</v></c>'
          '<c r="B1" t="str"><f>CONCATENATE("A","B")</f><v>AB</v></c>'
          '</row>',
        ),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    expect(rowsOf(book, 0), [
      ['1234.5', 'AB'],
    ]);
  });

  test('keeps the formula when no cached result was stored', () {
    final path = workbookAt(
      'Ledger.xlsx',
      sheets: [
        FixtureSheet('Totals', '<row r="1"><c r="A1"><f>SUM(B1:B9)</f></c></row>'),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    expect(rowsOf(book, 0), [
      ['=SUM(B1:B9)'],
    ]);
  });

  test('renders date-formatted numbers as dates and money as numbers', () {
    final path = workbookAt(
      'Ledger.xlsx',
      sheets: [
        FixtureSheet(
          'Sheet1',
          // s="1" built-in date, s="2" custom dd/mm/yyyy hh:mm,
          // s="3" currency, s="0" general.
          '<row r="1">'
          '<c r="A1" s="1"><v>45000</v></c>'
          '<c r="B1" s="2"><v>45000.5</v></c>'
          '<c r="C1" s="3"><v>1250000</v></c>'
          '<c r="D1" s="0"><v>45000</v></c>'
          '</row>',
        ),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    expect(rowsOf(book, 0), [
      ['2023-03-15', '2023-03-15 12:00:00', '1250000', '45000'],
    ]);
  });

  test('honours the 1904 date system', () {
    final path = workbookAt(
      'Mac.xlsx',
      date1904: true,
      sheets: [
        FixtureSheet('Sheet1', '<row r="1"><c r="A1" s="1"><v>0</v></c></row>'),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    expect(rowsOf(book, 0), [
      ['1904-01-01'],
    ]);
  });

  test('places cells by their column reference, filling the gaps', () {
    final path = workbookAt(
      'Ledger.xlsx',
      sheets: [
        FixtureSheet(
          'Sheet1',
          '<row r="1"><c r="A1"><v>1</v></c><c r="D1"><v>4</v></c></row>'
          '<row r="5"><c r="B5"><v>2</v></c></row>',
        ),
      ],
    );

    final book = XlsxWorkbook.open(path);
    addTearDown(book.close);

    final rows = book.readRows(book.sheets[0]).toList();
    expect(rows.map((row) => row.number), [1, 5]);
    expect(rows.map((row) => row.cells), [
      ['1', '', '', '4'],
      ['', '2'],
    ]);
  });

  test('reports a friendly error for a legacy .xls file', () {
    final path = p.join(temp.path, 'Old.xls');
    File(path).writeAsBytesSync([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);

    expect(
      () => XlsxWorkbook.open(path),
      throwsA(
        isA<XlsxException>().having(
          (e) => e.message,
          'message',
          contains('Save As'),
        ),
      ),
    );
  });
}
