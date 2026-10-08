import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// 🚨★A WATCH ON NATIVE CALLS MADE ON THE TEST'S OWN ISOLATE.
///
/// A synchronous native call that never returns stops that isolate's event
/// loop, and every Dart timer with it — the test's own timeout included.
/// Nothing ends the run then but the job's (25 minutes on CI), and the
/// reporter, which prints only the tests that finished, cannot say where it
/// stood (board `the-trimmed-movie-test-can-hang-on-windows-ci`: three
/// sightings of one test, each under the load of several runs at once).
///
/// The watch is another isolate, so its clock runs whatever this one is
/// stuck in. It is told each step as the step starts; a step not followed
/// by another within the limit is named on stderr and the process ends —
/// the run goes on to the next file, red, with the step that stopped.
class NativeCallWatch {
  NativeCallWatch._(this._inbox, this._isolate);

  final SendPort _inbox;
  final Isolate _isolate;

  /// A watch over [test], each of whose steps may take up to [limit].
  ///
  /// [told] takes the sentence instead of the process ending — for the
  /// watch's own pin, which has to outlive what it sets off.
  ///
  /// Real async: inside a `testWidgets`, start it in `tester.runAsync`.
  static Future<NativeCallWatch> start(
    String test, {
    Duration limit = const Duration(minutes: 3),
    SendPort? told,
  }) async {
    final reply = ReceivePort();
    final isolate = await Isolate.spawn(
      _watch,
      (reply: reply.sendPort, test: test, limit: limit, told: told),
      debugName: 'native call watch',
    );
    final inbox = await reply.first as SendPort;
    return NativeCallWatch._(inbox, isolate);
  }

  /// [name] starts now — the step the watch names if it never ends.
  void step(String name) => _inbox.send(name);

  /// Every step has ended.
  void stop() {
    _inbox.send(null);
    _isolate.kill();
  }
}

void _watch(
  ({SendPort reply, String test, Duration limit, SendPort? told}) watch,
) {
  final inbox = ReceivePort();
  watch.reply.send(inbox.sendPort);
  var step = 'its first step';
  Timer? alarm;
  void arm() {
    alarm?.cancel();
    alarm = Timer(watch.limit, () async {
      final said =
          '🚨「${watch.test}」 has been in 「$step」 for '
          '${watch.limit.inSeconds} s — a native call there did not return '
          '(board the-trimmed-movie-test-can-hang-on-windows-ci). The run '
          'ends here so the next file can go.';
      final told = watch.told;
      if (told != null) {
        told.send(said);
        return;
      }
      // Both, and flushed: `exit` waits for nothing, and which of the two
      // a runner keeps of a process that died is the runner's choice.
      stdout.writeln(said);
      stderr.writeln(said);
      await Future.wait([stdout.flush(), stderr.flush()]);
      exit(1);
    });
  }

  inbox.listen((message) {
    if (message == null) {
      alarm?.cancel();
      inbox.close();
      return;
    }
    step = message as String;
    arm();
  });
  arm();
}
