import 'dart:io';

import 'package:path/path.dart' as p;

import '../xlsx/xlsx_workbook.dart';
import 'conversion_models.dart';
import 'output_naming.dart';
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

  try {
    for (final sheet in workbook.sheets) {
      if (sheet.hidden && !options.includeHiddenSheets) {
        final outcome = SheetOutcome(
          sheetName: sheet.name,
          status: SheetStatus.hidden,
          message: 'Hidden sheet skipped',
        );
        outcomes.add(outcome);
        onSheetFinished?.call(outcome);
        continue;
      }

      final fileName = names.nameFor(bookName, sheet.name);
      final stem = fileName.substring(0, fileName.length - 4);
      onSheetStarted?.call(
        sheet.name,
        p.join(options.outputDirectory, fileName),
      );

      final outcome = await _convertSheet(
        workbook: workbook,
        sheet: sheet,
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

Future<SheetOutcome> _convertSheet({
  required XlsxWorkbook workbook,
  required XlsxSheet sheet,
  required String stem,
  required ConversionOptions options,
}) async {
  final writer = SheetCsvWriter(
    directory: options.outputDirectory,
    stem: stem,
    addBom: options.addBom,
    tokenBudget: options.splitLargeSheets ? defaultTokenBudget : null,
  );
  int? lastRowNumber;

  try {
    for (final row in workbook.readRows(sheet)) {
      if (row.isEmpty) continue;

      // Blank rows are reconstructed from the row numbers rather than emitted
      // as they are read, which also drops the blank run at the top and bottom
      // of a sheet instead of padding the CSV with it.
      if (options.keepBlankRows && lastRowNumber != null) {
        for (var gap = row.number - lastRowNumber - 1; gap > 0; gap--) {
          await writer.writeRow(const []);
        }
      }

      await writer.writeRow(row.cells);
      lastRowNumber = row.number;
    }
  } catch (error) {
    await writer.close();
    writer.deleteAll();
    return SheetOutcome(
      sheetName: sheet.name,
      status: SheetStatus.failed,
      message: '$error',
    );
  }

  final rows = writer.rowsWritten;
  final paths = await writer.close();

  if (rows == 0) {
    return SheetOutcome(
      sheetName: sheet.name,
      status: SheetStatus.empty,
      message: 'No data',
    );
  }

  return SheetOutcome(
    sheetName: sheet.name,
    status: SheetStatus.converted,
    outputPaths: paths,
    rowCount: rows,
    message: paths.length > 1
        ? 'Split into ${paths.length} files to fit a NotebookLM source'
        : null,
  );
}
