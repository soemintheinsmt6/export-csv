import 'dart:math' as math;
import 'dart:ui';

/// Candidate designs for the app icon.
enum IconVariant {
  /// A stack of CSV files coming off a workbook: one in, many out.
  stack,

  /// A spreadsheet grid with an arrow, spelling out the conversion.
  arrow,

  /// One sheet whose lower half separates into columns.
  split,
}

const Color _tealLight = Color(0xFF2A8B71);
const Color _tealDark = Color(0xFF12514A);
const Color _paper = Color(0xFFFFFFFF);
const Color _ink = Color(0xFF4A625C);
const Color _accent = Color(0xFF6FE0B4);

/// Paints the icon into a square of [size] logical pixels.
///
/// Everything is expressed as a fraction of [size] so one routine serves the
/// 1024px master and the 16px menu-bar version alike.
void paintAppIcon(Canvas canvas, double size, IconVariant variant) {
  _paintTile(canvas, size);
  switch (variant) {
    case IconVariant.stack:
      _paintStack(canvas, size);
    case IconVariant.arrow:
      _paintArrow(canvas, size);
    case IconVariant.split:
      _paintSplit(canvas, size);
  }
}

/// The rounded tile both platforms show the artwork on.
void _paintTile(Canvas canvas, double size) {
  final rect = Rect.fromLTWH(0, 0, size, size);
  // The proportion Apple uses for its own rounded-square icons.
  final radius = Radius.circular(size * 0.2237);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, radius),
    Paint()
      ..shader = Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [_tealLight, _tealDark],
      ),
  );
}

void _paintStack(Canvas canvas, double size) {
  final width = size * 0.42;
  final height = size * 0.54;
  final step = size * 0.055;
  final left = size * 0.24;
  final top = size * 0.19;

  // Two sheets behind, dimmed, so the eye reads "several files".
  for (final depth in [2, 1]) {
    final rect = Rect.fromLTWH(
      left + step * depth,
      top + step * depth,
      width,
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size * 0.05)),
      Paint()..color = _paper.withValues(alpha: depth == 2 ? 0.35 : 0.6),
    );
  }

  final front = Rect.fromLTWH(left, top, width, height);
  canvas.drawRRect(
    RRect.fromRectAndRadius(front, Radius.circular(size * 0.05)),
    Paint()..color = _paper,
  );

  // A header band and rows of text: a table, without the fussiness of a grid.
  final pad = width * 0.16;
  final barHeight = height * 0.115;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(front.left + pad, front.top + pad, width - pad * 2, barHeight),
      Radius.circular(barHeight * 0.5),
    ),
    Paint()..color = _accent,
  );

  for (var row = 1; row <= 3; row++) {
    final y = front.top + pad + barHeight * (1 + row * 1.75);
    final rowWidth = (width - pad * 2) * (row == 3 ? 0.6 : 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(front.left + pad, y, rowWidth, barHeight * 0.62),
        Radius.circular(barHeight * 0.31),
      ),
      Paint()..color = _ink.withValues(alpha: 0.55),
    );
  }
}

void _paintArrow(Canvas canvas, double size) {
  final sheet = Rect.fromLTWH(size * 0.14, size * 0.26, size * 0.34, size * 0.48);
  canvas.drawRRect(
    RRect.fromRectAndRadius(sheet, Radius.circular(size * 0.045)),
    Paint()..color = _paper,
  );

  // Two rows only. Any more and the cells merge into a smear at 16px.
  final cellWidth = sheet.width * 0.66;
  final cellHeight = sheet.height * 0.2;
  for (var row = 0; row < 3; row++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          sheet.left + sheet.width * 0.17,
          sheet.top + sheet.height * 0.17 + row * cellHeight * 1.42,
          row == 2 ? cellWidth * 0.62 : cellWidth,
          cellHeight,
        ),
        Radius.circular(cellHeight * 0.35),
      ),
      row == 0 ? (Paint()..color = _accent) : (Paint()..color = _ink.withValues(alpha: 0.5)),
    );
  }

  // A chevron rather than a full arrow: it holds its shape when small.
  final stroke = size * 0.095;
  final path = Path()
    ..moveTo(size * 0.585, size * 0.35)
    ..lineTo(size * 0.75, size * 0.5)
    ..lineTo(size * 0.585, size * 0.65);
  canvas.drawPath(
    path,
    Paint()
      ..color = _paper
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  // Two stubs standing for the files that come out; three was noise.
  for (var i = 0; i < 2; i++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size * 0.80, size * 0.425 + i * size * 0.1, size * 0.1, size * 0.055),
        Radius.circular(size * 0.027),
      ),
      Paint()..color = _paper.withValues(alpha: 1 - i * 0.3),
    );
  }
}

void _paintSplit(Canvas canvas, double size) {
  final sheet = Rect.fromLTWH(size * 0.22, size * 0.2, size * 0.56, size * 0.6);
  final radius = Radius.circular(size * 0.05);

  // The top stays whole; the bottom separates into three columns, which is the
  // conversion in one picture.
  final top = Rect.fromLTWH(sheet.left, sheet.top, sheet.width, sheet.height * 0.42);
  canvas.drawRRect(
    RRect.fromRectAndCorners(top, topLeft: radius, topRight: radius),
    Paint()..color = _paper,
  );

  final band = Rect.fromLTWH(
    top.left + top.width * 0.12,
    top.top + top.height * 0.26,
    top.width * 0.76,
    top.height * 0.2,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(band, Radius.circular(band.height * 0.5)),
    Paint()..color = _accent,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(band.left, band.bottom + top.height * 0.16, band.width * 0.62, band.height),
      Radius.circular(band.height * 0.5),
    ),
    Paint()..color = _ink.withValues(alpha: 0.45),
  );

  final gap = sheet.width * 0.075;
  final columnWidth = (sheet.width - gap * 2) / 3;
  final columnTop = sheet.top + sheet.height * 0.5;
  // Equal weight and equal length: three pieces of one sheet, not a bar chart.
  for (var i = 0; i < 3; i++) {
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(
          sheet.left + i * (columnWidth + gap),
          columnTop,
          columnWidth,
          sheet.height * 0.5,
        ),
        bottomLeft: radius,
        bottomRight: radius,
      ),
      Paint()..color = _paper,
    );
  }
}

/// Draws [image] into [destination] without smoothing, so a 16px icon can be
/// inspected pixel by pixel.
void drawPixelated(Canvas canvas, Image image, Rect destination) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    destination,
    Paint()..filterQuality = FilterQuality.none,
  );
}

/// Fraction of a full turn, for callers that want to rotate artwork.
double turns(double value) => value * 2 * math.pi;
