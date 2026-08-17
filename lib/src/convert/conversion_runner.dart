import 'dart:async';
import 'dart:isolate';

import 'conversion_models.dart';
import 'converter.dart';

/// Runs a conversion in a background isolate.
///
/// Parsing a workbook is CPU-bound and synchronous; doing it on the UI isolate
/// would freeze the window for the length of a large ledger.
class ConversionRunner {
  Isolate? _isolate;
  ReceivePort? _port;

  bool get isRunning => _isolate != null;

  /// Starts a run and yields progress events until the batch ends.
  Stream<ConversionEvent> start(
    List<String> sources,
    ConversionOptions options,
  ) {
    if (_isolate != null) {
      throw StateError('A conversion is already running.');
    }

    final controller = StreamController<ConversionEvent>();
    final port = ReceivePort();
    _port = port;

    void finish() {
      _cleanUp();
      if (!controller.isClosed) controller.close();
    }

    port.listen((message) {
      if (controller.isClosed) return;
      switch (message) {
        case ConversionEvent event:
          controller.add(event);
          if (event is BatchFinished || event is BatchFailed) finish();
        case List entries: // uncaught error forwarded by onError
          final detail = entries.isEmpty ? 'unknown error' : '${entries.first}';
          controller.add(BatchFailed('The converter failed: $detail'));
          finish();
        case null: // onExit, reached only if the run never reported an end
          controller.add(BatchFailed('The converter stopped unexpectedly.'));
          finish();
      }
    });

    Isolate.spawn(
      _isolateMain,
      _Payload(port.sendPort, sources, options),
      onError: port.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
    ).then((isolate) {
      // The run may already have been cancelled while the isolate spawned.
      if (_port == null) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = isolate;
    }).catchError((Object error) {
      controller.add(BatchFailed('Could not start the converter: $error'));
      _cleanUp();
      controller.close();
    });

    return controller.stream;
  }

  /// Stops the run immediately. The sheet being written is left partially
  /// converted, so the caller removes that file.
  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _cleanUp();
  }

  void _cleanUp() {
    _isolate = null;
    _port?.close();
    _port = null;
  }
}

class _Payload {
  _Payload(this.port, this.sources, this.options);

  final SendPort port;
  final List<String> sources;
  final ConversionOptions options;
}

Future<void> _isolateMain(_Payload payload) async {
  try {
    await runConversion(
      sources: payload.sources,
      options: payload.options,
      emit: payload.port.send,
    );
  } catch (error) {
    payload.port.send(BatchFailed('$error'));
  }
}
