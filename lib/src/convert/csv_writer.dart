import 'dart:convert';
import 'dart:io';

/// Writes RFC 4180 CSV to a file, one row at a time.
///
/// The file handle is opened on the first row so that a sheet with no data
/// never leaves an empty `.csv` behind.
class CsvWriter {
  CsvWriter(this.path, {this.addBom = false, this.lineEnding = '\n'});

  final String path;
  final bool addBom;
  final String lineEnding;

  IOSink? _sink;
  int _rowsWritten = 0;
  int _rowsAtLastFlush = 0;

  int get rowsWritten => _rowsWritten;
  bool get hasOutput => _sink != null;

  void writeRow(List<String> cells) => writeLine(encodeRow(cells, lineEnding));

  /// Writes an already-encoded line, so a caller that had to measure the line
  /// before deciding where it goes does not have to encode it twice.
  void writeLine(String line) {
    (_sink ??= _openSink()).write(line);
    _rowsWritten++;
  }

  /// Pushes buffered rows to disk every [every] rows. An `IOSink` buffers
  /// without bound, so a long sheet would otherwise be held in memory twice.
  Future<void> flushIfNeeded({int every = 2000}) async {
    final sink = _sink;
    if (sink == null || _rowsWritten - _rowsAtLastFlush < every) return;
    _rowsAtLastFlush = _rowsWritten;
    await sink.flush();
  }

  Future<void> close() async {
    final sink = _sink;
    if (sink == null) return;
    await sink.flush();
    await sink.close();
    _sink = null;
  }

  IOSink _openSink() {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final sink = file.openWrite(encoding: utf8);
    if (addBom) sink.write('\u{feff}');
    return sink;
  }

  /// Encodes a whole row, including its line ending.
  static String encodeRow(List<String> cells, [String lineEnding = '\n']) {
    final buffer = StringBuffer();
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(encodeField(cells[i]));
    }
    buffer.write(lineEnding);
    return buffer.toString();
  }

  /// Quotes a field only when it has to be quoted, which keeps the output
  /// readable for anything that reads the CSV as plain text.
  static String encodeField(String value) {
    if (value.isEmpty) return value;
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
