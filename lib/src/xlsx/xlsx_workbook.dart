import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml_events.dart';

import 'cell_format.dart';
import 'cell_value.dart';

/// A package relationship: where a part lives and what role it plays.
class _Relationship {
  _Relationship(this.target, this.type);

  final String target;
  final String type;
}

/// A problem with the workbook itself, phrased for the person using the app.
class XlsxException implements Exception {
  XlsxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One worksheet listed in the workbook, in tab order.
class XlsxSheet {
  XlsxSheet({required this.name, required this.entryPath, required this.hidden});

  final String name;

  /// Path of the sheet XML inside the zip, e.g. `xl/worksheets/sheet1.xml`.
  final String entryPath;

  final bool hidden;
}

/// A single row of a worksheet, with its 1-based row number so that callers can
/// see where the file skipped blank rows.
class XlsxRow {
  XlsxRow(this.number, this.cells);

  final int number;
  final List<String> cells;

  bool get isEmpty => cells.every((cell) => cell.isEmpty);
}

/// Reads `.xlsx`/`.xlsm` workbooks a row at a time.
///
/// Written against the raw OOXML instead of a spreadsheet package for two
/// reasons: formula cells keep the cached result Excel stored with them (the
/// number a ledger actually wants) rather than the formula text, and rows are
/// streamed so a large workbook never has to sit in memory as an object graph.
class XlsxWorkbook {
  XlsxWorkbook._(
    this._archive,
    this._input,
    this.sheets,
    this._sharedStrings,
    this._styleKinds, {
    required this.date1904,
  });

  final Archive _archive;
  final InputFileStream _input;
  final List<XlsxSheet> sheets;
  final List<String> _sharedStrings;

  /// Number-format kind per `cellXfs` index, looked up by a cell's `s`.
  final List<CellFormatKind> _styleKinds;

  final bool date1904;

  static XlsxWorkbook open(String path) {
    _assertLooksLikeXlsx(path);

    final input = InputFileStream(path);
    Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (error) {
      input.closeSync();
      throw XlsxException('The file could not be opened as a workbook ($error).');
    }

    try {
      final workbookPath = _findWorkbookPart(archive);
      final base = p.url.dirname(workbookPath);
      final rels = _readRelationships(archive, workbookPath);

      final workbookXml = _readEntry(archive, workbookPath);
      if (workbookXml == null) {
        throw XlsxException('The workbook is missing its $workbookPath part.');
      }

      var date1904 = false;
      final sheets = <XlsxSheet>[];
      for (final event in parseEvents(workbookXml)) {
        if (event is! XmlStartElementEvent) continue;
        switch (event.localName) {
          case 'workbookPr':
            date1904 = _isTrue(_attr(event, 'date1904'));
          case 'sheet':
            final relId = _attr(event, 'id', matchSuffix: true);
            final rel = relId == null ? null : rels[relId];
            // Chart sheets and dialog sheets hold no cells worth exporting.
            if (rel == null || !rel.type.endsWith('/worksheet')) continue;
            final entryPath = _resolveTarget(base, rel.target);
            final state = _attr(event, 'state');
            sheets.add(
              XlsxSheet(
                name: _attr(event, 'name') ?? 'Sheet${sheets.length + 1}',
                entryPath: entryPath,
                hidden: state == 'hidden' || state == 'veryHidden',
              ),
            );
        }
      }

      if (sheets.isEmpty) {
        throw XlsxException('The workbook contains no worksheets.');
      }

      final sharedStringsPath = _partByType(rels, 'sharedStrings', base) ??
          p.url.join(base, 'sharedStrings.xml');
      final stylesPath =
          _partByType(rels, 'styles', base) ?? p.url.join(base, 'styles.xml');

      return XlsxWorkbook._(
        archive,
        input,
        sheets,
        _readSharedStrings(archive, sharedStringsPath),
        _readStyleKinds(archive, stylesPath),
        date1904: date1904,
      );
    } catch (_) {
      input.closeSync();
      rethrow;
    }
  }

  /// Streams the rows of [sheet]. Rows the file omits entirely (blank rows) are
  /// not emitted; the gaps show up as jumps in [XlsxRow.number].
  Iterable<XlsxRow> readRows(XlsxSheet sheet) sync* {
    final xml = _readEntry(_archive, sheet.entryPath);
    if (xml == null) return;

    var rowNumber = 0;
    var cells = <String>[];
    var column = 0;
    var inRow = false;

    String? cellType;
    var cellStyle = 0;
    final value = StringBuffer();
    final inline = StringBuffer();
    final formula = StringBuffer();
    StringBuffer? textSink;
    var phoneticDepth = 0;

    for (final event in parseEvents(xml)) {
      if (event is XmlTextEvent) {
        textSink?.write(event.value);
        continue;
      }
      if (event is XmlCDATAEvent) {
        textSink?.write(event.value);
        continue;
      }

      if (event is XmlStartElementEvent) {
        switch (event.localName) {
          case 'row':
            final ref = _attr(event, 'r');
            rowNumber = int.tryParse(ref ?? '') ?? rowNumber + 1;
            cells = <String>[];
            column = 0;
            inRow = true;
          case 'c':
            final ref = _attr(event, 'r');
            column = ref == null ? column : _columnOfRef(ref);
            cellType = _attr(event, 't');
            cellStyle = int.tryParse(_attr(event, 's') ?? '') ?? 0;
            value.clear();
            inline.clear();
            formula.clear();
          case 'v':
            if (!event.isSelfClosing) textSink = value;
          case 'f':
            if (!event.isSelfClosing) textSink = formula;
          case 't':
            if (!event.isSelfClosing && phoneticDepth == 0) textSink = inline;
          case 'rPh':
            if (!event.isSelfClosing) phoneticDepth++;
        }

        if (!event.isSelfClosing) continue;
        // Fall through to the end-element handling for `<c r="A1"/>` and
        // friends, which the parser reports as a single self-closing event.
      }

      final name = switch (event) {
        XmlStartElementEvent(:final localName) => localName,
        XmlEndElementEvent(:final localName) => localName,
        _ => null,
      };

      switch (name) {
        case 'v' || 'f' || 't':
          textSink = null;
        case 'rPh':
          if (phoneticDepth > 0) phoneticDepth--;
          textSink = null;
        case 'c':
          final text = _resolveCell(
            type: cellType,
            style: cellStyle,
            value: value.toString(),
            inline: inline.toString(),
            formula: formula.toString(),
          );
          if (text.isNotEmpty) {
            while (cells.length < column) {
              cells.add('');
            }
            if (cells.length == column) {
              cells.add(text);
            } else {
              cells[column] = text;
            }
          }
          column++;
        case 'row':
          if (inRow) {
            yield XlsxRow(rowNumber, cells);
            inRow = false;
          }
      }
    }
  }

  void close() {
    _input.closeSync();
  }

  String _resolveCell({
    required String? type,
    required int style,
    required String value,
    required String inline,
    required String formula,
  }) {
    switch (type) {
      case 's':
        final index = int.tryParse(value.trim());
        if (index == null || index < 0 || index >= _sharedStrings.length) {
          return '';
        }
        return _sharedStrings[index];
      case 'inlineStr':
        return inline;
      case 'str': // string result of a formula
      case 'e': // error value such as #DIV/0!
      case 'd': // ISO-8601 date, already human readable
        return value;
      case 'b':
        if (value.isEmpty) return '';
        return value.trim() == '0' ? 'FALSE' : 'TRUE';
      default:
        if (value.isEmpty) {
          // A formula whose cached result was not stored: keep the formula so
          // nothing silently disappears from the ledger.
          return formula.isEmpty ? '' : '=$formula';
        }
        final kind = style >= 0 && style < _styleKinds.length
            ? _styleKinds[style]
            : CellFormatKind.general;
        return formatNumericCell(value, kind, date1904: date1904);
    }
  }

  static void _assertLooksLikeXlsx(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw XlsxException('The file no longer exists.');
    }
    final RandomAccessFile handle;
    try {
      handle = file.openSync();
    } on FileSystemException catch (error) {
      throw XlsxException('The file could not be read (${error.osError?.message ?? error.message}).');
    }
    try {
      final magic = handle.readSync(8);
      if (magic.length >= 2 && magic[0] == 0x50 && magic[1] == 0x4B) return; // "PK"
      const oleMagic = [0xD0, 0xCF, 0x11, 0xE0];
      if (magic.length >= 4 &&
          List.generate(4, (i) => magic[i] == oleMagic[i]).every((ok) => ok)) {
        throw XlsxException(
          'This is an old .xls workbook. Open it in Excel and use '
          'File > Save As to save a copy as .xlsx, then convert that.',
        );
      }
      throw XlsxException('This is not an Excel workbook.');
    } finally {
      handle.closeSync();
    }
  }

  static String? _readEntry(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    final bytes = file.readBytes();
    if (bytes == null) return null;
    final text = utf8.decode(bytes, allowMalformed: true);
    // Each part is read once; dropping the decompressed copy keeps peak memory
    // to roughly one sheet rather than the whole workbook.
    file.clear();
    return text;
  }

  static String _findWorkbookPart(Archive archive) {
    final rels = _readEntry(archive, '_rels/.rels');
    if (rels != null) {
      for (final event in parseEvents(rels)) {
        if (event is! XmlStartElementEvent) continue;
        if (event.localName != 'Relationship') continue;
        final type = _attr(event, 'Type') ?? '';
        final target = _attr(event, 'Target');
        if (target != null && type.endsWith('/officeDocument')) {
          return _resolveTarget('', target);
        }
      }
    }
    return 'xl/workbook.xml';
  }

  /// Relationship id -> relationship, for the `.rels` file of [partPath].
  static Map<String, _Relationship> _readRelationships(
    Archive archive,
    String partPath,
  ) {
    final relsPath = p.url.join(
      p.url.dirname(partPath),
      '_rels',
      '${p.url.basename(partPath)}.rels',
    );
    final xml = _readEntry(archive, relsPath);
    final result = <String, _Relationship>{};
    if (xml == null) return result;
    for (final event in parseEvents(xml)) {
      if (event is! XmlStartElementEvent) continue;
      if (event.localName != 'Relationship') continue;
      final id = _attr(event, 'Id');
      final target = _attr(event, 'Target');
      if (id != null && target != null) {
        result[id] = _Relationship(target, _attr(event, 'Type') ?? '');
      }
    }
    return result;
  }

  static String? _partByType(
    Map<String, _Relationship> rels,
    String typeSuffix,
    String base,
  ) {
    for (final rel in rels.values) {
      if (rel.type.endsWith('/$typeSuffix')) {
        return _resolveTarget(base, rel.target);
      }
    }
    return null;
  }

  static List<String> _readSharedStrings(Archive archive, String path) {
    final xml = _readEntry(archive, path);
    final strings = <String>[];
    if (xml == null) return strings;

    StringBuffer? current;
    StringBuffer? textSink;
    var phoneticDepth = 0;

    for (final event in parseEvents(xml)) {
      if (event is XmlTextEvent) {
        textSink?.write(event.value);
        continue;
      }
      if (event is XmlCDATAEvent) {
        textSink?.write(event.value);
        continue;
      }
      if (event is XmlStartElementEvent) {
        switch (event.localName) {
          case 'si':
            current = StringBuffer();
            if (event.isSelfClosing) {
              strings.add('');
              current = null;
            }
          case 't':
            if (!event.isSelfClosing && phoneticDepth == 0) textSink = current;
          case 'rPh':
            if (!event.isSelfClosing) phoneticDepth++;
        }
        continue;
      }
      if (event is XmlEndElementEvent) {
        switch (event.localName) {
          case 'si':
            strings.add(current?.toString() ?? '');
            current = null;
          case 't':
            textSink = null;
          case 'rPh':
            if (phoneticDepth > 0) phoneticDepth--;
        }
      }
    }
    return strings;
  }

  static List<CellFormatKind> _readStyleKinds(Archive archive, String path) {
    final xml = _readEntry(archive, path);
    if (xml == null) return const [];

    final customFormats = <int, String>{};
    final kinds = <CellFormatKind>[];
    var inCellXfs = false;

    for (final event in parseEvents(xml)) {
      if (event is XmlEndElementEvent && event.localName == 'cellXfs') {
        inCellXfs = false;
        continue;
      }
      if (event is! XmlStartElementEvent) continue;
      switch (event.localName) {
        case 'numFmt':
          final id = int.tryParse(_attr(event, 'numFmtId') ?? '');
          final code = _attr(event, 'formatCode');
          if (id != null && code != null) customFormats[id] = code;
        case 'cellXfs':
          inCellXfs = true;
        case 'xf':
          // `xf` also appears under cellStyleXfs, which cells never reference.
          if (!inCellXfs) continue;
          final id = int.tryParse(_attr(event, 'numFmtId') ?? '') ?? 0;
          kinds.add(classifyNumberFormat(id, customFormats[id]));
      }
    }
    return kinds;
  }

  /// Resolves a relationship target against the part's directory.
  static String _resolveTarget(String base, String target) {
    if (target.startsWith('/')) return target.substring(1);
    return p.url.normalize(base.isEmpty ? target : p.url.join(base, target));
  }

  static String? _attr(
    XmlStartElementEvent event,
    String name, {
    bool matchSuffix = false,
  }) {
    for (final attribute in event.attributes) {
      if (attribute.localName == name) return attribute.value;
      if (matchSuffix && attribute.name.endsWith(':$name')) return attribute.value;
    }
    return null;
  }

  static bool _isTrue(String? value) => value == '1' || value == 'true';

  /// `BC12` -> 54 (0-based column index).
  static int _columnOfRef(String ref) {
    var column = 0;
    for (final unit in ref.codeUnits) {
      if (unit >= 0x41 && unit <= 0x5A) {
        column = column * 26 + (unit - 0x40);
      } else if (unit >= 0x61 && unit <= 0x7A) {
        column = column * 26 + (unit - 0x60);
      } else {
        break;
      }
    }
    return column > 0 ? column - 1 : 0;
  }
}
