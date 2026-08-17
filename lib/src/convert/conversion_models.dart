/// Settings that apply to a whole conversion run.
class ConversionOptions {
  const ConversionOptions({
    required this.outputDirectory,
    this.includeHiddenSheets = true,
    this.keepBlankRows = false,
    this.addBom = false,
    this.tidyFileNames = true,
    this.splitLargeSheets = true,
    this.mergeDailySheets = true,
  });

  /// Combines sheets named after dates into a single CSV per workbook, with a
  /// column recording the day each row came from.
  ///
  /// A month of daily tabs is one table split across thirty sheets, not thirty
  /// documents, and a notebook's source allowance is spent either way.
  final bool mergeDailySheets;

  /// Splits a sheet across several CSVs when it would be too large for
  /// NotebookLM to accept as one source, filling each file to the limit first.
  final bool splitLargeSheets;

  final String outputDirectory;

  /// Strips the tracking id some reporting systems append to an export, so the
  /// CSV is named after the ledger rather than after a UUID.
  final bool tidyFileNames;

  /// Hidden tabs usually hold lookup tables, but they can hold real ledger
  /// data, so they are exported unless the user says otherwise.
  final bool includeHiddenSheets;

  /// Blank rows inside a sheet are dropped by default: they carry no meaning
  /// once the sheet is text, and NotebookLM only has to read more.
  final bool keepBlankRows;

  /// A UTF-8 byte order mark makes Excel open the CSV with the right encoding.
  /// NotebookLM does not need it, so it is off by default.
  final bool addBom;
}

enum SheetStatus {
  /// A `.csv` was written.
  converted,

  /// The sheet had no cells with content, so no file was written.
  empty,

  /// The sheet was skipped because it is hidden and hidden sheets are excluded.
  hidden,

  /// The sheet could not be read.
  failed,
}

/// What happened to one sheet.
class SheetOutcome {
  const SheetOutcome({
    required this.sheetName,
    required this.status,
    this.outputPaths = const [],
    this.rowCount = 0,
    this.mergedSheetCount = 0,
    this.message,
  });

  final String sheetName;
  final SheetStatus status;

  /// The CSV files written for this sheet — more than one when it had to be
  /// split to fit a NotebookLM source.
  final List<String> outputPaths;

  final int rowCount;

  /// How many sheets went into this file, when daily sheets were merged.
  final int mergedSheetCount;

  final String? message;

  String? get outputPath => outputPaths.isEmpty ? null : outputPaths.first;

  bool get wasSplit => outputPaths.length > 1;

  bool get wasMerged => mergedSheetCount > 1;
}

/// Header of the column added when daily sheets are merged.
const String dateColumnName = 'Sheet date';

/// What happened to one workbook.
class WorkbookOutcome {
  const WorkbookOutcome({
    required this.sourcePath,
    required this.sheets,
    this.error,
  });

  final String sourcePath;
  final List<SheetOutcome> sheets;

  /// Set when the workbook could not be opened at all.
  final String? error;

  int get convertedCount =>
      sheets.where((s) => s.status == SheetStatus.converted).length;
}

/// Progress reported while a run is in flight.
sealed class ConversionEvent {
  const ConversionEvent();
}

class WorkbookStarted extends ConversionEvent {
  const WorkbookStarted(this.index, this.sheetCount);

  final int index;
  final int sheetCount;
}

/// Emitted before a sheet is written so a cancelled run knows which partial
/// file to clean up.
class SheetStarted extends ConversionEvent {
  const SheetStarted(this.index, this.sheetName, this.outputPath);

  final int index;
  final String sheetName;
  final String outputPath;
}

class SheetFinished extends ConversionEvent {
  const SheetFinished(this.index, this.outcome);

  final int index;
  final SheetOutcome outcome;
}

class WorkbookFinished extends ConversionEvent {
  const WorkbookFinished(this.index, this.outcome);

  final int index;
  final WorkbookOutcome outcome;
}

class BatchFinished extends ConversionEvent {
  const BatchFinished();
}

class BatchFailed extends ConversionEvent {
  const BatchFailed(this.message);

  final String message;
}
