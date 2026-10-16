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
///
/// 🗣️On Windows it leaves the process's threads behind first (Q1, 유저
/// 2026-10-16: 「예외 하나 — 감시가 멈춤을 본 뒤 한 번만, 바깥에서 덤프」): the
/// step named, the stop would not show again — forty real runs and 13,000
/// in a repro never stopped once — so what the stuck call waits on has to
/// be kept the one time it does. A minidump, written from OUTSIDE the
/// process ([_dumpFromOutside]).
class NativeCallWatch {
  NativeCallWatch._(this._inbox, this._isolate);

  final SendPort _inbox;
  final Isolate _isolate;

  /// A watch over [test], each of whose steps may take up to [limit].
  ///
  /// [told] takes the sentence instead of the process ending — for the
  /// watch's own pin, which has to outlive what it sets off.
  ///
  /// [dumps] is the folder the dump goes in — null for none.
  ///
  /// Real async: inside a `testWidgets`, start it in `tester.runAsync`.
  static Future<NativeCallWatch> start(
    String test, {
    Duration limit = const Duration(minutes: 3),
    SendPort? told,
    String? dumps = 'build/native_call_watch',
  }) async {
    final reply = ReceivePort();
    final isolate = await Isolate.spawn(
      _watch,
      (
        reply: reply.sendPort,
        test: test,
        limit: limit,
        told: told,
        dumps: dumps,
      ),
      debugName: 'native call watch',
    );
    final inbox = await reply.first as SendPort;
    return NativeCallWatch._(inbox, isolate);
  }

  /// [name] starts now — the step the watch names if it never ends.
  void step(String name) => _inbox.send(name);

  /// Every step has ended — the watch and its alarm go.
  void stop() => _isolate.kill(priority: Isolate.immediate);
}

void _watch(
  ({
    SendPort reply,
    String test,
    Duration limit,
    SendPort? told,
    String? dumps,
  })
  watch,
) {
  final inbox = ReceivePort();
  watch.reply.send(inbox.sendPort);
  var step = 'its first step';
  Timer? alarm;
  void arm() {
    alarm?.cancel();
    alarm = Timer(watch.limit, () async {
      // Before a word is said: the dump is of the process as it stands in
      // the call, and saying it ends the run.
      final dump = await _dumpFromOutside(watch.dumps, watch.test);
      final said =
          '🚨「${watch.test}」 has been in 「$step」 for '
          '${watch.limit.inSeconds} s — a native call there did not return '
          '(board the-trimmed-movie-test-can-hang-on-windows-ci). '
          '${dump == null ? '' : 'Its threads as they stood: $dump. '}'
          'The run ends here so the next file can go.';
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
    step = message as String;
    arm();
  });
  arm();
}

/// A minidump of this process in [folder], written by another process —
/// its path, or null where none was written.
///
/// 🚨The one process a test may start (`tests_do_not_race_the_code_test`),
/// and only here: by now the run is lost, so it competes with nothing. ONE
/// start, the SDK's own `dart` on [_dumper], capped at a minute — the
/// process's threads stand still while it is written (about a second).
Future<String?> _dumpFromOutside(String? folder, String test) async {
  final dart = _sdkDart();
  if (folder == null || dart == null || !Platform.isWindows) {
    return null;
  }
  final into = Directory(folder).absolute..createSync(recursive: true);
  final name = test.replaceAll(RegExp('[^A-Za-z0-9]+'), '_');
  final file =
      '${into.path}${Platform.pathSeparator}'
      '${name.length > 60 ? name.substring(0, 60) : name}-$pid.dmp';
  final dumping = await Process.start(
    dart,
    [_dumper, '$pid', file],
    mode: ProcessStartMode.inheritStdio,
  );
  final ended = await dumping.exitCode.timeout(
    const Duration(minutes: 1),
    onTimeout: () {
      dumping.kill();
      return -1;
    },
  );
  return ended == 0 ? file : null;
}

/// What writes the dump — from outside the process it dumps.
const _dumper = 'test/helpers/native_call_watch_dump.dart';

/// The SDK's own `dart`, beside the Flutter the run is on — it needs
/// nothing installed.
String? _sdkDart() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    return null;
  }
  final dart = File('$root/bin/cache/dart-sdk/bin/dart.exe');
  return dart.existsSync() ? dart.path : null;
}
