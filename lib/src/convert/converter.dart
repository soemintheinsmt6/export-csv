import 'dart:io';

import 'package:path/path.dart' as p;

import '../xlsx/xlsx_workbook.dart';
import 'conversion_models.dart';
import 'output_naming.dart';
import 'sheet_grouping.dart';
import 'sheet_writer.dart';
import 'source_budget.dart';

/// Converts every workbook in [sources], writing one CSV per sheet into
/// [options.outputDirectory] and reporting progress through [emit].
///
/// Workbooks are handled one at a time: the bottleneck is disk and memory, and
/// a predictable order makes the progress list easy to follow.
Future<void> runConversion({
  required List<String> sources,
  required ConversionOptions options,
  required void Function(ConversionEvent event) emit,
}) async {
  Directory(options.outputDirectory).createSync(recursive: true);
  // One namer for the whole run: everything lands in the same folder, so two
  // workbooks with the same name must not overwrite each other's sheets.
  final namer = OutputNamer();

  for (var index = 0; index < sources.length; index++) {
    final outcome = await convertWorkbook(
      sourcePath: sources[index],
      options: options,
      namer: namer,
      onSheetCount: (count) => emit(WorkbookStarted(index, count)),
      onSheetStarted: (sheet, path) => emit(SheetStarted(index, sheet, path)),
      onSheetFinished: (sheet) => emit(SheetFinished(index, sheet)),
    );
    emit(WorkbookFinished(index, outcome));
  }

  emit(const BatchFinished());
}

/// Converts a single workbook. Exposed separately so it can be tested without
/// the isolate and the UI around it.
Future<WorkbookOutcome> convertWorkbook({
  required String sourcePath,
  required ConversionOptions options,
  OutputNamer? namer,
  void Function(int sheetCount)? onSheetCount,
  void Function(String sheetName, String outputPath)? onSheetStarted,
  void Function(SheetOutcome outcome)? onSheetFinished,
}) async {
  final names = namer ?? OutputNamer();
  final rawName = p.basenameWithoutExtension(sourcePath);
  final bookName = options.tidyFileNames ? tidyWorkbookName(rawName) : rawName;

  XlsxWorkbook workbook;
  try {
    workbook = XlsxWorkbook.open(sourcePath);
  } on XlsxException catch (error) {
    onSheetCount?.call(0);
    return WorkbookOutcome(
      sourcePath: sourcePath,
      sheets: const [],
      error: error.message,
    );
  } catch (error) {
    onSheetCount?.call(0);
    return WorkbookOutcome(
      sourcePath: sourcePath,
      sheets: const [],
      error: 'Could not read the workbook: $error',
    );
  }

  onSheetCount?.call(workbook.sheets.length);
  final outcomes = <SheetOutcome>[];

  // Sheets are reported in the order the workbook lists them, so the results
  // read like the tab strip. A merged file takes the place of its first member.
  final visible = <XlsxSheet>[];
  final visibleIndexOf = <int, int>{};
  for (var i = 0; i < workbook.sheets.length; i++) {
    final sheet = workbook.sheets[i];
    if (options.includeHiddenSheets || !sheet.hidden) {
      visibleIndexOf[i] = visible.length;
      visible.add(sheet);
    }
  }

  final groups = groupSheets(
    [for (final sheet in visible) sheet.name],
    merge: options.mergeDailySheets,
  );
  final groupOfSheet = <int, int>{};
  for (var g = 0; g < groups.length; g++) {
    for (final member in groups[g].members) {
      groupOfSheet[member] = g;
    }
  }

  try {
    final written = <int>{};
    for (var i = 0; i < workbook.sheets.length; i++) {
      final sheet = workbook.sheets[i];
      final visibleIndex = visibleIndexOf[i];

      if (visibleIndex == null) {
        final outcome = SheetOutcome(
          sheetName: sheet.name,
          status: SheetStatus.hidden,
          message: 'Hidden sheet skipped',
        );
        outcomes.add(outcome);
        onSheetFinished?.call(outcome);
        continue;
      }

      final groupIndex = groupOfSheet[visibleIndex]!;
      if (!written.add(groupIndex)) continue; // already written with its first member
      final group = groups[groupIndex];

      final fileName = names.nameFor(bookName, group.label);
      final stem = fileName.substring(0, fileName.length - 4);
      onSheetStarted?.call(
        group.label,
        p.join(options.outputDirectory, fileName),
      );

      final outcome = await _convertGroup(
        workbook: workbook,
        sheets: [for (final index in group.members) visible[index]],
        dates: group.dates,
        label: group.label,
        stem: stem,
        options: options,
      );
      outcomes.add(outcome);
      onSheetFinished?.call(outcome);
    }
  } finally {
    workbook.close();
  }

  return WorkbookOutcome(sourcePath: sourcePath, sheets: outcomes);
}

/// Writes one output file from one sheet, or from a run of daily sheets.
///
/// When several sheets are merged, each row gains a leading date column naming
/// the tab it came from, and the header block is written once — a repeat of it
/// at the top of every day would be read as data.
Future<SheetOutcome> _convertGroup({
  required XlsxWorkbook workbook,
  required List<XlsxSheet> sheets,
  required List<String> dates,
  required String label,
  required String stem,
  required ConversionOptions options,
}) async {
  final merged = sheets.length > 1;
  final writer = SheetCsvWriter(
    directory: options.outputDirectory,
    stem: stem,
    addBom: options.addBom,
    tokenBudget: options.splitLargeSheets ? defaultTokenBudget : null,
  );

  List<List<String>>? sharedHeader;

  try {
    for (var i = 0; i < sheets.length; i++) {
      // A sheet can only be read once — the workbook releases its decompressed
      // data as it goes — so the opening rows are pulled off the same iterator
      // that then supplies the rest.
      final rows = _dataRows(workbook, sheets[i], options).iterator;

      if (!merged) {
        while (rows.moveNext()) {
          await writer.writeRow(rows.current);
        }
        continue;
      }

      final date = dates[i];

      if (sharedHeader == null) {
        // The first sheet of the run defines the shape of the merged file.
        final opening = _pull(rows, SheetCsvWriter.headerScanDepth);
        sharedHeader = SheetCsvWriter.chooseHeaderRows(opening);
        for (var h = 0; h < sharedHeader.length; h++) {
          final isNameRow = h == sharedHeader.length - 1;
          await writer.writeRow([
            isNameRow ? dateColumnName : '',
            ...sharedHeader[h],
          ]);
        }
        for (final cells in opening.skip(sharedHeader.length)) {
          await writer.writeRow([date, ...cells]);
        }
      } else {
        // Later sheets repeat those rows; drop them only when they match, so a
        // sheet with a different shape keeps everything it had.
        final opening = _pull(rows, sharedHeader.length);
        if (!_sameRows(opening, sharedHeader)) {
          for (final cells in opening) {
            await writer.writeRow([date, ...cells]);
          }
        }
      }

      while (rows.moveNext()) {
        await writer.writeRow([date, ...rows.current]);
      }
    }
  } catch (error) {
    await writer.close();
    writer.deleteAll();
    return SheetOutcome(
      sheetName: label,
      status: SheetStatus.failed,
      message: '$error',
    );
  }

  final rows = writer.rowsWritten;
  final paths = await writer.close();

  if (rows == 0) {
    return SheetOutcome(
      sheetName: label,
      status: SheetStatus.empty,
      message: 'No data',
    );
  }

  final notes = [
    if (merged) 'Merged ${sheets.length} daily sheets',
    if (paths.length > 1)
      'Split into ${paths.length} files to fit a NotebookLM source',
  ];

  return SheetOutcome(
    sheetName: label,
    status: SheetStatus.converted,
    outputPaths: paths,
    rowCount: rows,
    mergedSheetCount: merged ? sheets.length : 0,
    message: notes.isEmpty ? null : notes.join(' · '),
  );
}

/// The rows of a sheet with the blanks already dealt with.
Iterable<List<String>> _dataRows(
  XlsxWorkbook workbook,
  XlsxSheet sheet,
  ConversionOptions options,
) sync* {
  int? lastRowNumber;
  for (final row in workbook.readRows(sheet)) {
    if (row.isEmpty) continue;

    // Blank rows are reconstructed from the row numbers rather than emitted as
    // they are read, which also drops the blank run at the top and bottom of a
    // sheet instead of padding the CSV with it.
    if (options.keepBlankRows && lastRowNumber != null) {
      for (var gap = row.number - lastRowNumber - 1; gap > 0; gap--) {
        yield const [];
      }
    }

    yield row.cells;
    lastRowNumber = row.number;
  }
}

/// Takes up to [count] rows off [rows], leaving the iterator where it stopped.
List<List<String>> _pull(Iterator<List<String>> rows, int count) {
  final taken = <List<String>>[];
  while (taken.length < count && rows.moveNext()) {
    taken.add(rows.current);
  }
  return taken;
}

bool _sameRows(List<List<String>> a, List<List<String>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) return false;
    }
  }
  return true;
}
