import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'conversion_models.dart';
import 'conversion_runner.dart';
import 'output_naming.dart';

enum JobStatus { pending, converting, done, failed, cancelled }

/// One workbook queued for conversion, plus whatever the run has learned
/// about it so far.
class ConversionJob {
  ConversionJob(this.sourcePath);

  final String sourcePath;

  JobStatus status = JobStatus.pending;
  int sheetCount = 0;
  String? error;
  final List<SheetOutcome> sheets = [];

  String get fileName => p.basename(sourcePath);

  int get convertedCount =>
      sheets.where((s) => s.status == SheetStatus.converted).length;

  int get rowCount => sheets.fold(0, (sum, sheet) => sum + sheet.rowCount);

  void reset() {
    status = JobStatus.pending;
    sheetCount = 0;
    error = null;
    sheets.clear();
  }
}

/// Holds the queue, the options and the progress of the current run.
class ConversionController extends ChangeNotifier {
  ConversionController({ConversionRunner? runner})
      : _runner = runner ?? ConversionRunner();

  static const supportedExtensions = {'.xlsx', '.xlsm'};

  final ConversionRunner _runner;
  StreamSubscription<ConversionEvent>? _subscription;

  final List<ConversionJob> _jobs = [];
  List<ConversionJob> get jobs => List.unmodifiable(_jobs);

  String? _outputDirectory;
  String? get outputDirectory => _outputDirectory;

  /// The last folder the user picked or dropped as a whole.
  String? _lastAddedFolder;

  bool includeHiddenSheets = true;
  bool keepBlankRows = false;
  bool addBom = false;
  bool tidyFileNames = true;
  bool splitLargeSheets = true;
  bool mergeDailySheets = true;

  bool _running = false;
  bool get isRunning => _running;

  int _currentJob = 0;
  int get currentJob => _currentJob;

  String? _currentSheet;
  String? get currentSheet => _currentSheet;

  /// Output path of the sheet currently being written, so a cancelled run can
  /// remove the half-written file.
  String? _pendingOutputPath;

  String? _message;
  String? get message => _message;

  bool get canStart =>
      !_running && _jobs.isNotEmpty && (_outputDirectory?.isNotEmpty ?? false);

  bool get hasResults =>
      !_running && _jobs.any((job) => job.status != JobStatus.pending);

  int get totalConverted =>
      _jobs.fold(0, (sum, job) => sum + job.convertedCount);

  /// Fraction of the queue processed, used for the progress bar.
  double get progress {
    if (_jobs.isEmpty) return 0;
    final done = _jobs
        .where((job) => job.status == JobStatus.done || job.status == JobStatus.failed)
        .length;
    return done / _jobs.length;
  }

  void setOutputDirectory(String? path) {
    _outputDirectory = path;
    notifyListeners();
  }

  void setIncludeHiddenSheets(bool value) {
    includeHiddenSheets = value;
    notifyListeners();
  }

  void setKeepBlankRows(bool value) {
    keepBlankRows = value;
    notifyListeners();
  }

  void setAddBom(bool value) {
    addBom = value;
    notifyListeners();
  }

  void setTidyFileNames(bool value) {
    tidyFileNames = value;
    notifyListeners();
  }

  void setSplitLargeSheets(bool value) {
    splitLargeSheets = value;
    notifyListeners();
  }

  void setMergeDailySheets(bool value) {
    mergeDailySheets = value;
    notifyListeners();
  }

  /// The name the next run would give a sheet of [job], so the UI can show the
  /// effect of the naming options before anything is written.
  String previewName(ConversionJob job) {
    final raw = p.basenameWithoutExtension(job.sourcePath);
    return csvFileName(
      tidyFileNames ? tidyWorkbookName(raw) : raw,
      'sheet name',
    );
  }

  /// Adds workbooks, expanding any folders that were dropped or picked and
  /// ignoring anything that is not a supported spreadsheet.
  int addPaths(Iterable<String> paths) {
    final existing = _jobs.map((job) => job.sourcePath).toSet();
    var added = 0;

    for (final path in paths) {
      if (Directory(path).existsSync()) _lastAddedFolder = path;
    }

    for (final path in _expand(paths)) {
      if (!existing.add(path)) continue;
      _jobs.add(ConversionJob(path));
      added++;
    }

    // Convert in the order the files are named, which is how ledgers are
    // usually numbered.
    _jobs.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));

    if (added > 0) {
      _message = null;
      _outputDirectory ??= _defaultOutputDirectory();
      notifyListeners();
    }
    return added;
  }

  void removeJob(ConversionJob job) {
    if (_running) return;
    _jobs.remove(job);
    notifyListeners();
  }

  void clearJobs() {
    if (_running) return;
    _jobs.clear();
    _message = null;
    notifyListeners();
  }

  Future<void> start() async {
    if (!canStart) return;

    // Check here rather than inside the isolate: on macOS the app is sandboxed
    // and can only write where the user has granted access.
    final problem = checkOutputWritable(_outputDirectory!);
    if (problem != null) {
      _message = problem;
      notifyListeners();
      return;
    }

    for (final job in _jobs) {
      job.reset();
    }
    _running = true;
    _currentJob = 0;
    _currentSheet = null;
    _pendingOutputPath = null;
    _message = null;
    notifyListeners();

    final options = ConversionOptions(
      outputDirectory: _outputDirectory!,
      includeHiddenSheets: includeHiddenSheets,
      keepBlankRows: keepBlankRows,
      addBom: addBom,
      tidyFileNames: tidyFileNames,
      splitLargeSheets: splitLargeSheets,
      mergeDailySheets: mergeDailySheets,
    );

    _subscription = _runner
        .start(_jobs.map((job) => job.sourcePath).toList(), options)
        .listen(_onEvent, onDone: _onDone);
  }

  void cancel() {
    if (!_running) return;
    _runner.cancel();
    _subscription?.cancel();
    _subscription = null;

    // The sheet in flight was cut off mid-write; a truncated CSV is worse than
    // no CSV at all.
    final partial = _pendingOutputPath;
    if (partial != null) _deletePartials(partial);
    _pendingOutputPath = null;

    for (final job in _jobs) {
      if (job.status == JobStatus.pending || job.status == JobStatus.converting) {
        job.status = JobStatus.cancelled;
      }
    }
    _running = false;
    _currentSheet = null;
    _message = 'Conversion cancelled. ${_summary()}';
    notifyListeners();
  }

  void _onEvent(ConversionEvent event) {
    switch (event) {
      case WorkbookStarted(:final index, :final sheetCount):
        _currentJob = index;
        _jobs[index]
          ..status = JobStatus.converting
          ..sheetCount = sheetCount;
      case SheetStarted(:final sheetName, :final outputPath):
        _currentSheet = sheetName;
        _pendingOutputPath = outputPath;
      case SheetFinished(:final index, :final outcome):
        _jobs[index].sheets.add(outcome);
        _pendingOutputPath = null;
      case WorkbookFinished(:final index, :final outcome):
        final job = _jobs[index];
        job.error = outcome.error;
        job.status = outcome.error == null ? JobStatus.done : JobStatus.failed;
        _currentSheet = null;
      case BatchFinished():
        _finish(_summary());
      case BatchFailed(:final message):
        _finish(message);
    }
    notifyListeners();
  }

  void _onDone() {
    if (!_running) return;
    _finish(_summary());
    notifyListeners();
  }

  void _finish(String summary) {
    _running = false;
    _currentSheet = null;
    _pendingOutputPath = null;
    _subscription?.cancel();
    _subscription = null;
    _message = summary;
  }

  String _summary() {
    final files = totalConverted;
    final books = _jobs.where((job) => job.status == JobStatus.done).length;
    final failed = _jobs.where((job) => job.status == JobStatus.failed).length;
    final buffer = StringBuffer()
      ..write('$files CSV ${_plural(files, 'file', 'files')} from ')
      ..write('$books ${_plural(books, 'workbook', 'workbooks')}');
    if (failed > 0) {
      buffer.write(' · $failed could not be read');
    }
    return buffer.toString();
  }

  /// Files first, then everything inside any folder that was passed in.
  static List<String> _expand(Iterable<String> paths) {
    final result = <String>[];
    for (final path in paths) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        final children = directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .where(isSupported)
            .toList()
          ..sort();
        result.addAll(children);
        continue;
      }
      if (isSupported(path) && File(path).existsSync()) result.add(path);
    }
    return result;
  }

  /// Temporary files Excel leaves behind (`~$Ledger.xlsx`) are not workbooks.
  static bool isSupported(String path) {
    final name = p.basename(path);
    if (name.startsWith('~\$') || name.startsWith('.')) return false;
    return supportedExtensions.contains(p.extension(path).toLowerCase());
  }

  /// Prefers a folder the user picked or dropped outright, because on macOS
  /// that is the one the sandbox has actually granted write access to. Picking
  /// individual files grants access to those files and nothing around them.
  String? _defaultOutputDirectory() {
    final parent = _lastAddedFolder ??
        (_jobs.isEmpty ? null : p.dirname(_jobs.first.sourcePath));
    return parent == null ? null : p.join(parent, 'csv_for_notebooklm');
  }

  /// Confirms the app can actually create files in [path], and explains what to
  /// do when it cannot.
  ///
  /// Creating the folder is not proof on its own: when the folder already
  /// exists, a sandbox denial only shows up on the first write.
  static String? checkOutputWritable(String path) {
    try {
      Directory(path).createSync(recursive: true);
      File(p.join(path, '.export_csv_write_test'))
        ..writeAsStringSync('')
        ..deleteSync();
      return null;
    } on FileSystemException catch (error) {
      final reason = error.osError?.message ?? error.message;
      final advice = Platform.isMacOS
          ? 'Choose the folder with the “Change…” button — macOS only lets this '
              'app write to folders you pick yourself.'
          : 'Choose a different folder, or check that it is not read-only.';
      return 'Cannot write to $path. $advice ($reason)';
    }
  }

  /// Removes the half-written sheet, including every `… part N.csv` a split
  /// sheet had produced before the run was stopped.
  static void _deletePartials(String basePath) {
    final stem = p.basenameWithoutExtension(basePath);
    final directory = Directory(p.dirname(basePath));
    if (!directory.existsSync()) return;
    try {
      for (final entry in directory.listSync().whereType<File>()) {
        final name = p.basename(entry.path);
        if (name == '$stem.csv' || name.startsWith('$stem part ')) {
          entry.deleteSync();
        }
      }
    } on FileSystemException {
      // Best effort only.
    }
  }

  static String _plural(int count, String one, String many) =>
      count == 1 ? one : many;

  @override
  void dispose() {
    _subscription?.cancel();
    if (_running) _runner.cancel();
    super.dispose();
  }
}
