/// Interpretation of a cell's number format, which is what decides whether a
/// raw numeric value in the file is a plain number or an Excel date serial.
enum CellFormatKind { general, date, time, dateTime }

/// Built-in number formats that mean "date" without the file spelling out a
/// format code (ECMA-376 §18.8.30).
const Map<int, CellFormatKind> _builtInFormats = {
  14: CellFormatKind.date, // m/d/yy
  15: CellFormatKind.date, // d-mmm-yy
  16: CellFormatKind.date, // d-mmm
  17: CellFormatKind.date, // mmm-yy
  18: CellFormatKind.time, // h:mm AM/PM
  19: CellFormatKind.time, // h:mm:ss AM/PM
  20: CellFormatKind.time, // h:mm
  21: CellFormatKind.time, // h:mm:ss
  22: CellFormatKind.dateTime, // m/d/yy h:mm
  45: CellFormatKind.time, // mm:ss
  46: CellFormatKind.time, // [h]:mm:ss
  47: CellFormatKind.time, // mmss.0
};

/// Classifies a number format, either by its built-in id or by reading a custom
/// format code such as `dd/mm/yyyy hh:mm`.
CellFormatKind classifyNumberFormat(int numFmtId, String? formatCode) {
  if (formatCode == null || formatCode.isEmpty) {
    return _builtInFormats[numFmtId] ?? CellFormatKind.general;
  }
  return classifyFormatCode(formatCode) ??
      _builtInFormats[numFmtId] ??
      CellFormatKind.general;
}

/// Reads a custom format code and reports what kind of value it renders.
///
/// Returns `null` when the code carries no date or time tokens at all, so the
/// caller can fall back to the built-in id.
CellFormatKind? classifyFormatCode(String code) {
  // Only the first section applies to positive numbers, and that is enough to
  // tell a date format from a numeric one.
  final section = _firstSection(code);
  var hasDate = false;
  var hasTime = false;
  var hasMonthOrMinute = false;

  for (var i = 0; i < section.length; i++) {
    final ch = section[i];
    switch (ch) {
      case '"': // literal text: "day " => skip to the closing quote
        i = _skipTo(section, i + 1, '"');
      case '\\': // escaped single character
        i++;
      case '[': // colours, conditions and elapsed-time markers: [h], [Red]
        final end = _skipTo(section, i + 1, ']');
        final marker = section.substring(i + 1, end < section.length ? end : section.length);
        if (RegExp(r'^h+$|^m+$|^s+$', caseSensitive: false).hasMatch(marker)) {
          hasTime = true;
        }
        i = end;
      // `e`/`E` is deliberately not treated as a date token: it is the
      // exponent marker in codes such as `0.00E+00`.
      case 'y' || 'Y' || 'd' || 'D':
        hasDate = true;
      case 'h' || 'H' || 's' || 'S':
        hasTime = true;
      case 'm' || 'M':
        hasMonthOrMinute = true;
    }
  }

  // A bare `m` is a month unless the code is otherwise a pure time format,
  // where it means minutes — and there it is already covered by `hasTime`.
  if (hasMonthOrMinute && !hasDate && !hasTime) hasDate = true;

  if (hasDate && hasTime) return CellFormatKind.dateTime;
  if (hasDate) return CellFormatKind.date;
  if (hasTime) return CellFormatKind.time;
  return null;
}

String _firstSection(String code) {
  for (var i = 0; i < code.length; i++) {
    final ch = code[i];
    if (ch == '"') {
      i = _skipTo(code, i + 1, '"');
    } else if (ch == '\\') {
      i++;
    } else if (ch == '[') {
      i = _skipTo(code, i + 1, ']');
    } else if (ch == ';') {
      return code.substring(0, i);
    }
  }
  return code;
}

/// Index of the next [terminator] at or after [start], or the string length.
int _skipTo(String source, int start, String terminator) {
  final index = source.indexOf(terminator, start);
  return index < 0 ? source.length : index;
}
