import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/build_stamp.dart';
import 'package:anicel/src/services/diagnostics/gpu_loss_log.dart';

/// The losses a graphics device's reset leaves (H63): each one written as it
/// is heard, the newest [GpuLossLog.kept] kept across runs.
void main() {
  late File log;

  setUp(() {
    log = File(GpuLossLog.logPath());
    if (log.existsSync()) {
      log.deleteSync();
    }
  });
  tearDown(() {
    if (log.existsSync()) {
      log.deleteSync();
    }
  });

  List<String> titles() => [
    for (final line in log.readAsLinesSync())
      if (line.startsWith(GpuLossLog.opening)) line.split(') ').last,
  ];

  test('a loss is its title, the build and its lines, after those before '
      'it', () {
    GpuLossLog.write('first', ['a', 'b']);
    GpuLossLog.write('second', ['c']);

    final lines = log.readAsLinesSync();
    expect(lines, hasLength(7));
    expect(lines[0], startsWith(GpuLossLog.opening));
    expect(lines[0], endsWith('first'));
    expect(lines[1], 'build $buildStamp');
    expect(lines.sublist(2, 4), ['a', 'b']);
    expect(lines[4], endsWith('second'));
    expect(lines[5], 'build $buildStamp');
    expect(lines[6], 'c');
  });

  test('the newest losses are kept, the oldest let go', () {
    for (var loss = 0; loss < GpuLossLog.kept + 2; loss += 1) {
      GpuLossLog.write('loss $loss', ['line of $loss']);
    }

    expect(titles(), [
      for (var loss = 2; loss < GpuLossLog.kept + 2; loss += 1) 'loss $loss',
    ]);
    expect(log.readAsLinesSync().first, startsWith(GpuLossLog.opening));
  });
}
