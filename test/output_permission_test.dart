import 'dart:io';

import 'package:export_csv/src/convert/conversion_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('permission_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('accepts a writable folder and creates it if missing', () {
    final target = p.join(temp.path, 'nested', 'csv');
    expect(ConversionController.checkOutputWritable(target), isNull);
    expect(Directory(target).existsSync(), isTrue);
  });

  test('leaves no probe file behind', () {
    ConversionController.checkOutputWritable(temp.path);
    expect(temp.listSync(), isEmpty);
  });

  test('explains itself when the folder cannot be written to', () {
    // A file where a folder is expected: the same FileSystemException path a
    // sandbox denial takes, without needing a sandboxed process to test it.
    final blocked = p.join(temp.path, 'not-a-folder');
    File(blocked).writeAsStringSync('');

    final problem = ConversionController.checkOutputWritable(blocked);
    expect(problem, isNotNull);
    expect(problem, contains(blocked));
    expect(problem, contains('Cannot write to'));
  });
}
