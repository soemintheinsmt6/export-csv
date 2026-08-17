import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'app_icon_painter.dart';

/// Writes the app icon for both platforms.
///
///     flutter test tool/generate_app_icon.dart
///
/// Regenerate after changing [paintAppIcon]; the results are committed, since
/// the CI builds package them and do not run this.
const IconVariant chosen = IconVariant.stack;

/// macOS insets its icons so the artwork does not crowd its neighbours in the
/// Dock — Apple's own grid puts an 1024px icon's tile at about 824px. Windows
/// icons are full-bleed.
const double macInset = 0.098;

const _macSizes = [16, 32, 64, 128, 256, 512, 1024];

/// The sizes Windows picks between: the 256 goes in as PNG and the rest as
/// 32-bit DIBs, which is how the Flutter template's own icon is built.
const _icoSizes = [16, 32, 48, 64, 128, 256];

void main() {
  test('write macOS appiconset and Windows ico', () async {
    final iconset = Directory('macos/Runner/Assets.xcassets/AppIcon.appiconset');
    expect(iconset.existsSync(), isTrue, reason: 'run from the project root');

    for (final size in _macSizes) {
      final image = await _render(size, inset: macInset);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${iconset.path}/app_icon_$size.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    }

    final entries = <_IcoEntry>[];
    for (final size in _icoSizes) {
      final image = await _render(size, inset: 0);
      if (size == 256) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        entries.add(_IcoEntry(size, png!.buffer.asUint8List(), isPng: true));
      } else {
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        entries.add(_IcoEntry(size, _dib(raw!.buffer.asUint8List(), size)));
      }
      image.dispose();
    }
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(_ico(entries));

    // ignore: avoid_print
    print('wrote ${_macSizes.length} macOS PNGs and a ${_icoSizes.length}-entry .ico');
  });
}

Future<ui.Image> _render(int size, {required double inset}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final margin = size * inset;
  canvas.save();
  canvas.translate(margin, margin);
  paintAppIcon(canvas, size - margin * 2, chosen);
  canvas.restore();
  return recorder.endRecording().toImage(size, size);
}

class _IcoEntry {
  _IcoEntry(this.size, this.bytes, {this.isPng = false});

  final int size;
  final Uint8List bytes;
  final bool isPng;
}

/// Packs the entries into an `.ico`.
Uint8List _ico(List<_IcoEntry> entries) {
  const headerSize = 6;
  const entrySize = 16;
  final directory = headerSize + entrySize * entries.length;
  final total = entries.fold<int>(directory, (sum, e) => sum + e.bytes.length);

  final out = Uint8List(total);
  final view = ByteData.view(out.buffer);
  view.setUint16(0, 0, Endian.little); // reserved
  view.setUint16(2, 1, Endian.little); // 1 = icon
  view.setUint16(4, entries.length, Endian.little);

  var offset = directory;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final at = headerSize + entrySize * i;
    // 256 is written as 0: the field is one byte wide.
    out[at] = entry.size == 256 ? 0 : entry.size;
    out[at + 1] = entry.size == 256 ? 0 : entry.size;
    out[at + 2] = 0; // palette size, 0 for truecolour
    out[at + 3] = 0; // reserved
    view.setUint16(at + 4, 1, Endian.little); // colour planes
    view.setUint16(at + 6, 32, Endian.little); // bits per pixel
    view.setUint32(at + 8, entry.bytes.length, Endian.little);
    view.setUint32(at + 12, offset, Endian.little);
    out.setRange(offset, offset + entry.bytes.length, entry.bytes);
    offset += entry.bytes.length;
  }
  return out;
}

/// Builds the DIB an `.ico` entry expects: a BITMAPINFOHEADER whose height
/// counts the image twice — once for the colours and once for a mask — then
/// bottom-up BGRA rows, then the mask itself. The mask stays zero because the
/// alpha channel already carries the transparency.
Uint8List _dib(Uint8List rgba, int size) {
  const headerSize = 40;
  final pixelBytes = size * size * 4;
  final maskStride = ((size + 31) ~/ 32) * 4;
  final maskBytes = maskStride * size;

  final out = Uint8List(headerSize + pixelBytes + maskBytes);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, headerSize, Endian.little);
  view.setInt32(4, size, Endian.little);
  view.setInt32(8, size * 2, Endian.little);
  view.setUint16(12, 1, Endian.little); // planes
  view.setUint16(14, 32, Endian.little); // bit count
  view.setUint32(16, 0, Endian.little); // BI_RGB
  view.setUint32(20, pixelBytes + maskBytes, Endian.little);

  var out_ = headerSize;
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      out[out_++] = rgba[i + 2]; // blue
      out[out_++] = rgba[i + 1]; // green
      out[out_++] = rgba[i]; // red
      out[out_++] = rgba[i + 3]; // alpha
    }
  }
  return out;
}
