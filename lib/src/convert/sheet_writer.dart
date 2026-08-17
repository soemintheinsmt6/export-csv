import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'csv_writer.dart';
import 'source_budget.dart';

/// Writes one sheet as one CSV, or as several when the sheet is too large to
/// be accepted as a single NotebookLM source.
///
/// Each part is filled to just under the budget before the next is started, so
/// a sheet uses as few sources as it can — sources are the scarce resource in a
/// notebook, not file count. Rows are never split across parts, and every part
/// repeats the sheet's header so it can be read on its own.
class SheetCsvWriter {
  SheetCsvWriter({
    required this.directory,
    required this.stem,
    this.addBom = false,
    this.tokenBudget,
  });

  final String directory;

  /// File name without the `.csv`, e.g. `Ledger(January)`.
  final String stem;

  final bool addBom;

  /// Maximum estimated tokens per file, or null to never split.
  final int? tokenBudget;

  /// How far into the sheet to look for the row holding the column names.
  static const int _headerScanDepth = 6;

  /// Upper bound on how many opening rows get repeated, so an odd sheet can
  /// never turn its whole top into a header block.
  static const int _maxHeaderRows = 3;

  final List<String> _paths = [];
  CsvWriter? _current;

  /// Opening rows held back until the header row has been identified.
  final List<List<String>> _pending = [];
  List<List<String>>? _headerRows;

  TokenCost _costInPart = TokenCost.zero;
  int _rowsInPart = 0;
  int _rowsWritten = 0;

  int get rowsWritten => _rowsWritten;
  int get partCount => _paths.length;

  Future<void> writeRow(List<String> cells) async {
    _rowsWritten++;

    if (tokenBudget == null) {
      await _emit(cells);
      return;
    }

    if (_headerRows == null) {
      _pending.add(cells);
      if (_pending.length >= _headerScanDepth) await _resolveHeader();
      return;
    }

    await _emit(cells);
  }

  /// Closes the sheet and returns the files written, named for how many there
  /// turned out to be.
  Future<List<String>> close() async {
    if (_headerRows == null && _pending.isNotEmpty) await _resolveHeader();

    await _current?.close();
    _current = null;
    if (_paths.length < 2) return List.of(_paths);

    final total = _paths.length;
    final width = total.toString().length;
    final renamed = <String>[];
    for (var i = 0; i < total; i++) {
      final part = (i + 1).toString().padLeft(width, '0');
      final target = p.join(directory, '$stem part $part of $total.csv');
      File(_paths[i]).renameSync(target);
      renamed.add(target);
    }
    _paths
      ..clear()
      ..addAll(renamed);
    return List.of(_paths);
  }

  /// Removes everything written so far, for a run that failed or was cancelled.
  void deleteAll() {
    for (final path in _paths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Best effort only.
      }
    }
    _paths.clear();
  }

  Future<void> _resolveHeader() async {
    _headerRows = chooseHeaderRows(_pending);
    for (final row in _pending) {
      await _emit(row);
    }
    _pending.clear();
  }

  Future<void> _emit(List<String> cells) async {
    final line = CsvWriter.encodeRow(cells);
    final cost = measureTokens(line);
    final budget = tokenBudget;
    final headerRows = _headerRows?.length ?? 0;

    if (_current == null) {
      _startPart();
    } else if (budget != null &&
        _rowsInPart > headerRows &&
        (_costInPart + cost).tokens > budget) {
      await _rollOver();
    }

    _current!.writeLine(line);
    _costInPart += cost;
    _rowsInPart++;
    await _current!.flushIfNeeded();
  }

  Future<void> _rollOver() async {
    await _current!.close();
    // The first part was written under the plain name, on the assumption that
    // one file would do. Now that it will not, give it a part number.
    if (_paths.length == 1) {
      final renamed = p.join(directory, '$stem part 1.csv');
      File(_paths[0]).renameSync(renamed);
      _paths[0] = renamed;
    }
    _startPart();

    for (final row in _headerRows ?? const <List<String>>[]) {
      final line = CsvWriter.encodeRow(row);
      _current!.writeLine(line);
      _costInPart += measureTokens(line);
      _rowsInPart++;
    }
  }

  void _startPart() {
    final name =
        _paths.isEmpty ? '$stem.csv' : '$stem part ${_paths.length + 1}.csv';
    final path = p.join(directory, name);
    _paths.add(path);
    _current = CsvWriter(path, addBom: addBom);
    _costInPart = TokenCost.zero;
    _rowsInPart = 0;
  }

  /// Picks the opening rows to repeat at the top of every part.
  ///
  /// The column names are not always in row 1. Ledger exports often open with a
  /// title or a summary line — branch code, date range, totals — and put the
  /// column names underneath. A part that repeats only row 1 would arrive
  /// without any column names at all, which is exactly the context a reader
  /// needs. So the real header is found by looking for the first row that is
  /// nearly all labels, and everything above it comes along.
  static List<List<String>> chooseHeaderRows(List<List<String>> rows) {
    if (rows.isEmpty) return const [];

    final limit = math.min(rows.length, _headerScanDepth);
    for (var i = 0; i < limit; i++) {
      final row = rows[i];
      final filled = row.where((cell) => cell.trim().isNotEmpty).length;
      final labels = row.where(_isLabel).length;
      // A header row is text nearly all the way across; a data row carries
      // numbers among its text.
      if (labels >= 3 && filled > 0 && labels / filled >= 0.9) {
        return i < _maxHeaderRows
            ? rows.sublist(0, i + 1)
            : <List<String>>[row];
      }
    }
    return <List<String>>[rows.first];
  }

  static final RegExp _letter = RegExp(r'[A-Za-zက-႟]');

  /// A cell that reads as a word rather than a figure or a date.
  static bool _isLabel(String cell) {
    final text = cell.trim();
    if (text.isEmpty) return false;
    if (double.tryParse(text.replaceAll(',', '')) != null) return false;
    return _letter.hasMatch(text);
  }
}
