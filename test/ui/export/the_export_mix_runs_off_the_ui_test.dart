import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/ui/export/export_audio_mix.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

import '../../helpers/temp_dir.dart';

/// 🚨★★★**AN EXPORT'S SOUND IS MIXED WITHOUT THE THREAD THAT DRAWS**
/// (the-export-sound-blocks-the-ui-isolate, the CPU census — 2026-11-13).
///
/// The whole timeline was mixed on the UI isolate in one stretch before the
/// first frame was encoded. It is mixed on a worker now: the sources cross
/// by where they lie when the output device made them, and the streaming
/// readers cross whole — and the file it writes is the one written here.
void main() {
  late Directory directory;

  setUp(() async {
    QaAudioDevice.debugResetForTests();
    directory = await Directory.systemTemp.createTemp('qa-mix-worker');
  });

  tearDown(() {
    debugWorkersRunHere = true;
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    deleteTempQuietly(directory);
  });

  const rate = ProjectFrameRate.integer(10);
  const sampleRate = 48000;
  const frames = 20;

  /// A ramp whose value encodes its position, so a sample from the wrong
  /// place cannot look right.
  Float32List ramp(int length, double scale) {
    final samples = Float32List(length);
    for (var index = 0; index < length; index += 1) {
      samples[index] = ((index % 2000) - 1000) / 2000.0 * scale;
    }
    return samples;
  }

  const schedule = [
    ScheduledAudioClip(
      filePath: 'resident',
      startFrame: 0,
      endFrameExclusive: 12,
      gain: 0.7,
      pan: -0.4,
    ),
    ScheduledAudioClip(
      filePath: 'streamed',
      startFrame: 5,
      endFrameExclusive: 20,
      offsetFrames: 2,
      gain: 0.6,
      pan: 0.3,
    ),
  ];

  /// The mix of [schedule] at [path], 'resident' answered by [resident] —
  /// 'streamed' read off a conform on disk, a block at a time.
  Future<void> writeMix(
    String path, {
    required Float32List resident,
    QaAudioDevice? device,
    void Function()? onResolved,
  }) async {
    final conformPath = '${directory.path}/streamed.conform';
    if (!File(conformPath).existsSync()) {
      File(conformPath).writeAsBytesSync(
        encodeConform(
          samples: ramp(96000, 0.9),
          channels: 1,
          sampleRate: sampleRate,
        ),
      );
    }
    final written = await writeExportAudioMixWav(
      schedule: schedule,
      rate: rate,
      totalFrames: frames,
      sampleRate: sampleRate,
      resolveSource: (_) async {
        onResolved?.call();
        return AudioMixSource(samples: resident, channels: 1);
      },
      resolveStreamReader: (path) => path == 'streamed'
          ? ConformPcmStreamReader.open(conformPath)
          : null,
      outputPath: path,
      device: () => device,
    );
    expect(written, isTrue);
  }

  test('🎯the mix is written on a worker — the thread that draws takes its '
      'turns meanwhile — and the file is the one written here', () async {
    final resident = ramp(96000, 1);
    var turned = false;
    void turnBeforeTheMix() => Timer.run(() => turned = true);

    final herePath = '${directory.path}/here.wav';
    await writeMix(herePath, resident: resident, onResolved: turnBeforeTheMix);
    expect(
      turned,
      isFalse,
      reason: 'the probe cannot tell: a mix written here took no turn, '
          'and this one says it did',
    );
    await pumpEventQueue();

    // The road production takes: a real isolate.
    debugWorkersRunHere = false;
    turned = false;
    final workerPath = '${directory.path}/worker.wav';
    await writeMix(
      workerPath,
      resident: resident,
      onResolved: turnBeforeTheMix,
    );

    expect(
      turned,
      isTrue,
      reason: 'the mix held the thread that draws until it was written',
    );
    expect(
      File(workerPath).readAsBytesSync(),
      File(herePath).readAsBytesSync(),
      reason: 'where the mix runs is a matter of turns, not of what it '
          'writes',
    );
  });

  test('a source the device made crosses by where it lies — held while the '
      'mix reads it, let go after — and mixes as the same samples',
      () async {
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: sampleRate, useNullBackend: true),
      greaterThan(0),
    );
    final copied = ramp(96000, 1);
    final made = device.newSamples(copied.length)!..setAll(0, copied);

    final copiedPath = '${directory.path}/copied.wav';
    await writeMix(copiedPath, resident: copied);
    await pumpEventQueue();

    debugWorkersRunHere = false;
    int? holdsWhileMixing;
    final lentPath = '${directory.path}/lent.wav';
    await writeMix(
      lentPath,
      resident: made,
      device: device,
      onResolved: () =>
          Timer.run(() => holdsWhileMixing = device.debugHoldsOf(made)),
    );

    expect(
      holdsWhileMixing,
      2,
      reason: 'the mix read a copy, not the buffer where the samples lie',
    );
    expect(device.debugHoldsOf(made), 1, reason: 'the lend was never let go');
    expect(
      File(lentPath).readAsBytesSync(),
      File(copiedPath).readAsBytesSync(),
      reason: 'a lent source mixed as other samples than the ones it holds',
    );
  });
}
