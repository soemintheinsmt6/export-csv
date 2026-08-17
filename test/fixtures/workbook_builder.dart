import 'dart:io';

import 'package:archive/archive.dart';

/// A sheet to place in a synthetic workbook.
class FixtureSheet {
  FixtureSheet(this.name, this.rowsXml, {this.hidden = false});

  final String name;

  /// Raw `<row>` elements, so tests can express exactly the cell shapes they
  /// care about — cached formula results, inline strings, gaps, and so on.
  final String rowsXml;

  final bool hidden;
}

/// Writes a minimal but standards-shaped `.xlsx` to [path].
///
/// Building the OOXML by hand is deliberate: it lets tests cover the parts of
/// the format real ledgers contain but a spreadsheet library would never emit,
/// such as a formula cell that carries its cached value.
void writeFixtureWorkbook(
  String path, {
  required List<FixtureSheet> sheets,
  List<String> sharedStrings = const [],
  bool date1904 = false,
}) {
  final archive = Archive();

  void add(String name, String content) {
    archive.add(ArchiveFile.string(name, content));
  }

  final sheetEntries = <String>[];
  final relEntries = <String>[];
  for (var i = 0; i < sheets.length; i++) {
    final sheet = sheets[i];
    final id = i + 1;
    sheetEntries.add(
      '<sheet name="${_escape(sheet.name)}" sheetId="$id" '
      '${sheet.hidden ? 'state="hidden" ' : ''}r:id="rId$id"/>',
    );
    relEntries.add(
      '<Relationship Id="rId$id" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet$id.xml"/>',
    );
    add(
      'xl/worksheets/sheet$id.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>${sheet.rowsXml}</sheetData></worksheet>',
    );
  }

  final nextRel = sheets.length + 1;

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="rels" '
    'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '</Types>',
  );

  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdWb" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/></Relationships>',
  );

  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '${date1904 ? '<workbookPr date1904="1"/>' : ''}'
    '<sheets>${sheetEntries.join()}</sheets></workbook>',
  );

  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${relEntries.join()}'
    '<Relationship Id="rId$nextRel" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" '
    'Target="sharedStrings.xml"/>'
    '<Relationship Id="rId${nextRel + 1}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/></Relationships>',
  );

  add(
    'xl/sharedStrings.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'count="${sharedStrings.length}" uniqueCount="${sharedStrings.length}">'
    '${sharedStrings.map((s) => '<si><t>${_escape(s)}</t></si>').join()}'
    '</sst>',
  );

  // Style 0: general. Style 1: built-in date. Style 2: custom date+time.
  // Style 3: currency, which must NOT be read as a date.
  add(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="2">'
    '<numFmt numFmtId="164" formatCode="dd/mm/yyyy hh:mm"/>'
    '<numFmt numFmtId="165" formatCode="#,##0.00 &quot;MMK&quot;"/>'
    '</numFmts>'
    '<cellStyleXfs count="1"><xf numFmtId="0"/></cellStyleXfs>'
    '<cellXfs count="4">'
    '<xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/><xf numFmtId="165"/>'
    '</cellXfs></styleSheet>',
  );

  final zipped = ZipEncoder().encode(archive);
  File(path).writeAsBytesSync(zipped);
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
