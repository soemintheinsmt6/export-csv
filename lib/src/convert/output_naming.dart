/// Characters no mainstream desktop file system accepts in a name, plus the
/// control range. Sheet names in Excel can contain most of them.
final RegExp _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

/// Longest name we will produce, leaving room for the extension and for
/// Windows' 260-character path limit on deep output folders.
const int _maxNameLength = 180;

/// A UUID that an export system appended to the file name, with the `_` or
/// `__` that joins it — dashed or bare hex.
final RegExp _exportSuffix = RegExp(
  r'_{1,2}(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
  r'|[0-9a-f]{32})$',
  caseSensitive: false,
);

/// Drops the tracking id that reporting tools bolt onto an export, so
/// `Stock-Balance__ef86c541-70a3-…` becomes `Stock-Balance`.
///
/// NotebookLM identifies a source by its file name alone, and 36 characters of
/// hex push the part that means something out of sight.
String tidyWorkbookName(String name) {
  final trimmed = name.replaceFirst(_exportSuffix, '');
  final cleaned = trimmed.replaceFirst(RegExp(r'[\s_-]+$'), '');
  return cleaned.isEmpty ? name : cleaned;
}

/// Builds `Workbook(Sheet).csv`, the layout NotebookLM shows in its source
/// list, so every source says which ledger and which tab it came from.
String csvFileName(String workbookBaseName, String sheetName) {
  final book = _sanitize(workbookBaseName, fallback: 'Workbook');
  final sheet = _sanitize(sheetName, fallback: 'Sheet');
  final name = '$book($sheet)';
  return '${_truncate(name)}.csv';
}

/// Hands out file names for one conversion run, keeping them unique.
///
/// Two sheets can legitimately collide — `Jan/Feb` and `Jan-Feb` both sanitise
/// to `Jan_Feb`, and on macOS and Windows the comparison is case-insensitive —
/// so later collisions get a numeric suffix instead of silently overwriting.
class OutputNamer {
  final Set<String> _taken = <String>{};

  String nameFor(String workbookBaseName, String sheetName) {
    final base = csvFileName(workbookBaseName, sheetName);
    if (_taken.add(base.toLowerCase())) return base;

    final stem = base.substring(0, base.length - 4);
    for (var counter = 2;; counter++) {
      final candidate = '${_truncate(stem, reserve: 6)} ($counter).csv';
      if (_taken.add(candidate.toLowerCase())) return candidate;
    }
  }
}

String _sanitize(String value, {required String fallback}) {
  var result = value.replaceAll(_illegal, '_').trim();
  // Windows rejects names that end in a dot or a space.
  while (result.endsWith('.') || result.endsWith(' ')) {
    result = result.substring(0, result.length - 1).trim();
  }
  return result.isEmpty ? fallback : result;
}

String _truncate(String name, {int reserve = 0}) {
  final limit = _maxNameLength - reserve;
  return name.length <= limit ? name : name.substring(0, limit).trim();
}
