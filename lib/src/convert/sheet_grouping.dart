/// A sheet name that turned out to be a date, plus whatever was written after
/// it — `17-6-2026 Plan Ground` is the 17th, labelled `Plan Ground`.
class SheetDate {
  const SheetDate(this.date, this.label);

  final DateTime date;

  /// The part of the name that is not the date, trimmed. Empty for a plain
  /// daily tab.
  final String label;

  /// `2026-06-17`, the form written into the merged sheet's date column.
  String get iso => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// One output file: either a single sheet, or several daily sheets merged.
class SheetGroup {
  SheetGroup({required this.label, required this.members, required this.dates});

  /// Stands in for the sheet name when the output file is named.
  final String label;

  /// Indexes into the sheet list the group was built from, in workbook order.
  final List<int> members;

  /// The date for each member, in the same order, used for the added column.
  /// Empty when the group is a single ordinary sheet.
  final List<String> dates;

  bool get isMerged => members.length > 1;
}

const Map<String, int> _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

// `2026-06-17`, optionally followed by a label.
final RegExp _isoPattern = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(.*)$');

// `17-6-2026`, `1-Jun-26`, `13 June 2026`, optionally followed by a label.
final RegExp _dayFirstPattern =
    RegExp(r'^(\d{1,2})[-/.\s]([A-Za-z]{3,9}|\d{1,2})[-/.\s](\d{2,4})(.*)$');

/// Reads a sheet name as a date, or returns null when it is not one.
///
/// Day-first is assumed for the all-numeric form: every dated tab seen in these
/// ledgers is written that way (`30-Jun-2026`, `1-June-2026`), and a workbook
/// mixing both conventions in one tab strip would be unreadable to its own
/// author too.
SheetDate? parseSheetDate(String name) {
  final text = name.trim();

  final iso = _isoPattern.firstMatch(text);
  if (iso != null) {
    return _build(
      year: int.parse(iso.group(1)!),
      month: int.parse(iso.group(2)!),
      day: int.parse(iso.group(3)!),
      rest: iso.group(4)!,
    );
  }

  final dayFirst = _dayFirstPattern.firstMatch(text);
  if (dayFirst == null) return null;

  final monthText = dayFirst.group(2)!;
  final month = int.tryParse(monthText) ??
      _months[monthText.toLowerCase().substring(0, 3)];
  if (month == null) return null;

  var year = int.parse(dayFirst.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;

  return _build(
    year: year,
    month: month,
    day: int.parse(dayFirst.group(1)!),
    rest: dayFirst.group(4)!,
  );
}

/// Years outside this range are not dates but something else that happens to
/// be written with dashes. `2324-6-26` is one of these: a tab covering the 23rd
/// and 24th of June, not the year 2324. Guessing at a day range would be worse
/// than leaving the sheet alone, so it stays a file of its own under its own
/// name and nothing is lost.
bool _plausibleYear(int year) => year >= 1900 && year <= 2100;

SheetDate? _build({
  required int year,
  required int month,
  required int day,
  required String rest,
}) {
  if (!_plausibleYear(year)) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  // Rejects the 31st of a 30-day month, which DateTime would roll forward.
  if (date.month != month || date.day != day) return null;

  final label = rest.replaceFirst(RegExp(r'^[-/.\s]+'), '').trim();
  return SheetDate(date, label);
}

/// Decides which sheets become which output files.
///
/// With [merge] off, every sheet is its own file. With it on, sheets whose
/// names are dates are collected into one file per label — the plain daily tabs
/// together, and any suffixed set such as `Plan Ground` separately, since those
/// are a different table that happens to be dated the same way.
List<SheetGroup> groupSheets(List<String> sheetNames, {required bool merge}) {
  if (!merge) {
    return [
      for (var i = 0; i < sheetNames.length; i++)
        SheetGroup(label: sheetNames[i], members: [i], dates: const []),
    ];
  }

  final dated = <String, List<int>>{};
  final dates = <int, SheetDate>{};

  for (var i = 0; i < sheetNames.length; i++) {
    final parsed = parseSheetDate(sheetNames[i]);
    if (parsed == null) continue;
    dates[i] = parsed;
    dated.putIfAbsent(parsed.label.toLowerCase(), () => <int>[]).add(i);
  }

  // A lone dated sheet is not a series; leave it named after itself.
  dated.removeWhere((_, members) => members.length < 2);

  final groupOfSheet = <int, String>{};
  for (final entry in dated.entries) {
    for (final member in entry.value) {
      groupOfSheet[member] = entry.key;
    }
  }

  final groups = <SheetGroup>[];
  final emitted = <String>{};
  for (var i = 0; i < sheetNames.length; i++) {
    final key = groupOfSheet[i];
    if (key == null) {
      groups.add(SheetGroup(label: sheetNames[i], members: [i], dates: const []));
      continue;
    }
    // The merged file takes the place of its first member.
    if (!emitted.add(key)) continue;
    final members = dated[key]!;
    final memberDates = [for (final m in members) dates[m]!];
    groups.add(
      SheetGroup(
        label: _mergedLabel(memberDates),
        members: members,
        dates: [for (final d in memberDates) d.iso],
      ),
    );
  }
  return groups;
}

String _mergedLabel(List<SheetDate> dates) {
  final sorted = [...dates]..sort((a, b) => a.date.compareTo(b.date));
  final first = sorted.first.iso;
  final last = sorted.last.iso;
  final span = first == last ? first : '$first to $last';
  final suffix = sorted.first.label;
  return suffix.isEmpty ? 'Daily $span' : 'Daily $span $suffix';
}
