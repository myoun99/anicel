import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

/// Stands in for the ffmpeg process in video-export tests: collects the raw
/// frames piped to stdin and exits with [exitCodeValue] once stdin closes
/// (or the service kills it).
class FakeFfmpegProcess implements Process {
  FakeFfmpegProcess({
    this.exitCodeValue = 0,
    this.stderrText = '',
    this.onFrame,
    this.breaksAtFrame,
  });

  final int exitCodeValue;
  final String stderrText;

  /// Called with the running frame count as each frame reaches stdin — the
  /// seam a test needs to STOP an export midway, deterministically,
  /// instead of racing a timer against the encoder.
  final void Function(int framesSoFar)? onFrame;

  /// The frame (counted from 1) the pipe breaks at instead of taking it —
  /// ffmpeg gone mid-stream. Null never breaks.
  final int? breaksAtFrame;
  final BytesBuilder collectedStdin = BytesBuilder();
  bool killed = false;

  late final _FakeStdinSink _stdin = _FakeStdinSink(
    collectedStdin,
    onClose: _completeExit,
    onFrame: onFrame == null ? null : () => onFrame!(receivedFrameCount),
    breaksAtFrame: breaksAtFrame,
  );

  // ZONE TRAP: this fake is usually CONSTRUCTED in a widget test's
  // fake-async zone but AWAITED inside runAsync (real time). Any Future
  // object created at construction time is bound to the fake zone, so
  // awaiting it after completion schedules the microtask on the fake
  // zone's queue — which never pumps during runAsync — deadlocking the
  // await on [exitCode]. So no Completer lives on the instance: futures
  // are created lazily in the CALLER's zone.
  int? _exitCodeValue;
  final List<Completer<int>> _exitWaiters = [];

  void _completeExit() {
    if (_exitCodeValue != null) {
      return;
    }
    _exitCodeValue = exitCodeValue;
    for (final waiter in _exitWaiters) {
      waiter.complete(exitCodeValue);
    }
    _exitWaiters.clear();
  }

  /// The frames ffmpeg received: a raw frame goes down the pipe in one
  /// write, and nothing in the bytes says where one ends.
  int get receivedFrameCount => _stdin.frames;

  @override
  Future<int> get exitCode {
    final value = _exitCodeValue;
    if (value != null) {
      return Future<int>.value(value);
    }
    final waiter = Completer<int>.sync();
    _exitWaiters.add(waiter);
    return waiter.future;
  }

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr =>
      Stream<List<int>>.value(utf8.encode(stderrText));

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    _completeExit();
    return true;
  }

  @override
  int get pid => 4242;
}

class _FakeStdinSink implements IOSink {
  _FakeStdinSink(
    this.buffer, {
    required this.onClose,
    this.onFrame,
    this.breaksAtFrame,
  });

  final BytesBuilder buffer;
  final void Function() onClose;
  final void Function()? onFrame;
  final int? breaksAtFrame;

  /// How many writes were taken.
  int frames = 0;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {
    if (frames + 1 == breaksAtFrame) {
      throw const SocketException('Broken pipe');
    }
    buffer.add(data);
    frames += 1;
    onFrame?.call();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async => onClose();

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) => add(utf8.encode('$object'));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}
