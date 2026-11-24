// CONFORM READ PROBE — does a sound's conform tell how far it has read its
// file, in the real app process, with its time of day — for a file that
// comes down while it is read (an online-only cloud file).
//
//   flutter build windows --debug -t tool/probe/conform_read_probe_main.dart
//   SOUND_IN=<a sound or movie> SOUND_OUT=<report.txt> \
//     build/windows/x64/runner/Debug/Anicel.exe
//
// flutter_tester never loads the engine's decoder with a cloud file under
// it, so how the percent moves while the OS fetches the file is only seen
// here (decoder-reads-skip-the-percent, 11-24).
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply.
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:anicel/src/services/audio/audio_conform_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final input = Platform.environment['SOUND_IN']!;
  final output = Platform.environment['SOUND_OUT']!;
  final out = File(output).openSync(mode: FileMode.write);
  void line(String words) {
    out.writeStringSync('${DateTime.now().toIso8601String()} $words\n');
    out.flushSync();
  }

  final conform = '${Directory.systemTemp.path}/conform_read_probe.pcm';
  line('file=$input conform=$conform');
  var told = 0;
  var last = -1.0;
  var rising = true;
  var shown = -1;
  final watch = Stopwatch()..start();
  try {
    final result = runConformHere(
      ConformRequest(sourcePath: input, conformPath: conform),
      onRead: (fraction) {
        told += 1;
        if (fraction < last) {
          rising = false;
        }
        last = fraction;
        final percent = (fraction * 100).floor();
        if (percent != shown) {
          shown = percent;
          line('${watch.elapsedMilliseconds}ms $percent% (told $told)');
        }
      },
    );
    line(
      'done ${watch.elapsedMilliseconds}ms outcome=${result.outcome} '
      'frames=${result.frames} told=$told last=$last rising=$rising',
    );
  } on Object catch (error, stack) {
    line('FAILED: $error\n$stack');
  }
  final left = File(conform);
  if (left.existsSync()) {
    left.deleteSync();
  }
  out.closeSync();
  exit(0);
}
