import 'cell_format.dart';

/// Turns the raw `<v>` payload of a numeric cell into the text that goes into
/// the CSV, honouring the cell's number format for dates and times.
String formatNumericCell(
  String raw,
  CellFormatKind kind, {
  required bool date1904,
}) {
  if (kind == CellFormatKind.general) return formatNumber(raw);

  final serial = double.tryParse(raw);
  if (serial == null || !serial.isFinite) return raw;

  final date = excelSerialToDateTime(serial, date1904: date1904);
  return switch (kind) {
    CellFormatKind.date => _formatDate(date),
    CellFormatKind.time => _formatTime(date),
    CellFormatKind.dateTime => '${_formatDate(date)} ${_formatTime(date)}',
    CellFormatKind.general => raw,
  };
}

/// Converts an Excel date serial to a `DateTime`.
///
/// Serials are counted from 1899-12-30 in the 1900 date system — two days
/// before 1900-01-01 — which absorbs Excel's deliberate 1900-leap-year bug for
/// every date from 1900-03-01 onwards. Workbooks authored on old Macs use the
/// 1904 system instead, flagged by `date1904` in `workbook.xml`.
DateTime excelSerialToDateTime(double serial, {required bool date1904}) {
  final epoch = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
  // Ledger data never needs sub-second precision, and rounding to the second
  // hides the float noise in values such as 0.7083333333333334 (17:00).
  return epoch.add(Duration(seconds: (serial * 86400).round()));
}

/// Normalises a numeric literal from the file for output.
///
/// Excel writes computed values at full binary precision, so a column that
/// reads `1234.56` on screen can be stored as `1234.5600000000002`. Fifteen
/// significant digits round-trips every value Excel itself can represent while
/// dropping that noise.
String formatNumber(String raw) {
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) return raw;

  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }

  var text = value.toStringAsPrecision(15);
  if (text.contains('e') || text.contains('E')) return raw;
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text;
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String _formatTime(DateTime d) =>
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

String _two(int value) => value.toString().padLeft(2, '0');
