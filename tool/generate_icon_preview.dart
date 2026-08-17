import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'app_icon_painter.dart';

/// Renders the candidate icons to a sheet for review.
///
///     flutter test tool/generate_icon_preview.dart
///
/// Writes build/icon_preview.png: each design large, then at the sizes the
/// menu bar and the taskbar actually use, magnified so the small ones can be
/// judged honestly.
void main() {
  test('render icon candidates', () async {
    const large = 220.0;
    const smallSizes = [64, 32, 16];
    const labelBand = 0.0;
    const margin = 28.0;
    const gap = 26.0;

    final magnified = smallSizes.fold<double>(0, (sum, s) => sum + 96 + gap);
    final rowHeight = large + labelBand;
    final width = margin * 2 + large + gap + magnified;
    final height = margin * 2 + rowHeight * IconVariant.values.length +
        gap * (IconVariant.values.length - 1);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = const ui.Color(0xFFF2F4F3),
    );

    for (var v = 0; v < IconVariant.values.length; v++) {
      final variant = IconVariant.values[v];
      final top = margin + v * (rowHeight + gap);

      canvas.save();
      canvas.translate(margin, top);
      paintAppIcon(canvas, large, variant);
      canvas.restore();


      var x = margin + large + gap;
      for (final size in smallSizes) {
        final image = await _renderVariant(variant, size);
        const box = 96.0;
        final y = top + (large - box) / 2;
        drawPixelated(canvas, image, ui.Rect.fromLTWH(x, y, box, box));
        image.dispose();
        x += box + gap;
      }
    }

    final picture = recorder.endRecording();
    final sheet = await picture.toImage(width.round(), height.round());
    final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/icon_preview.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.path}');
  });
}

Future<ui.Image> _renderVariant(IconVariant variant, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintAppIcon(canvas, size.toDouble(), variant);
  return recorder.endRecording().toImage(size, size);
}

