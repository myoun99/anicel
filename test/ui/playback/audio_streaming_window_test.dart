import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// The shared windowed upload (AUDIO-PRO R6): what the transport AND the
/// scrubber hand the device when a schedule mixes resident and streaming
/// sources. The C mixer sees a window through `sourceStart`; everything
/// here pins that the window is the RIGHT slice of the right file.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-stream-window');
  });

  tearDown(() => directory.delete(recursive: true));

  // Deliberately tiny numbers: 100 Hz "project rate", 10 fps — one frame
  // is ten samples, and the 2 s / 30 s window geometry stays readable.
  const sampleRate = 100;
  const rate = ProjectFrameRate.integer(10);
  const longFrames =
      sampleRate * AudioConformStore.streamingThresholdSeconds + 50;

  Float32List ramp(int length) {
    final samples = Float32List(length);
    for (var index = 0; index < length; index += 1) {
      samples[index] = ((index % 1000) - 500) / 1000.0;
    }
    return samples;
  }

  /// A store holding one STREAMING entry ('long', a real conform WAV on
  /// disk past the threshold) and one resident entry ('short').
  Future<(AudioConformStore, Float32List)> storeWithBoth() async {
    final longSamples = ramp(longFrames);
    final conformPath = '${directory.path}/long.wav.wav';
    File(conformPath).writeAsBytesSync(
      encodeConformWav(
        samples: longSamples,
        channels: 1,
        sampleRate: sampleRate,
      ),
    );
    final store = AudioConformStore(
      resolveConformPath: (_) => conformPath,
      projectSampleRate: sampleRate,
      runner: (request) async => request.sourcePath == 'long'
          ? ConformResult(
              outcome: ConformOutcome.built,
              conformPath: conformPath,
              samples: longSamples,
              channels: 1,
              sampleRate: sampleRate,
              frames: longFrames,
            )
          : ConformResult(
              outcome: ConformOutcome.built,
              samples: ramp(100),
              channels: 1,
              sampleRate: sampleRate,
              frames: 100,
            ),
      log: (_) {},
    );
    store.resultFor('long');
    store.resultFor('short');
    await pumpEventQueue();
    expect(store.isStreaming('long'), isTrue);
    expect(store.isStreaming('short'), isFalse);
    return (store, longSamples);
  }

  AudioMixSchedule mixOf(List<ScheduledAudioClip> schedule) =>
      audioMixScheduleFrom(
        schedule: schedule,
        rate: rate,
        sampleRate: sampleRate,
      );

  test('a streaming clip gets a PRIVATE windowed source; the resident one '
      'rides unchanged', () async {
    final (store, longSamples) = await storeWithBoth();
    final upload = windowedMixUpload(
      mix: mixOf(const [
        ScheduledAudioClip(
          filePath: 'long',
          startFrame: 0,
          endFrameExclusive: 1200,
          pan: -0.5,
          gain: 0.7,
        ),
        ScheduledAudioClip(filePath: 'short', startFrame: 0,
            endFrameExclusive: 10),
      ]),
      conformStore: store,
      deviceRate: sampleRate,
      centerSample: 5000,
    );
    expect(upload, isNotNull);
    expect(upload!.hasStreaming, isTrue);
    expect(upload.sources, hasLength(2));
    expect(upload.clips, hasLength(2));

    // The resident source: the whole file, sourceStart 0.
    final residentClip = upload.clips[1];
    final resident = upload.sources[residentClip.sourceIndex];
    expect(resident.sourceStart, 0);
    expect(resident.samples, hasLength(100));

    // The streaming source: 2 s back, 30 s ahead of sample 5000 —
    // [4800, 8000) — and byte-for-byte the decode's slice.
    final streamedClip = upload.clips[0];
    final streamed = upload.sources[streamedClip.sourceIndex];
    expect(streamed.sourceStart, 5000 - 2 * sampleRate);
    expect(streamed.samples, hasLength(32 * sampleRate));
    for (var index = 0; index < streamed.samples.length; index += 1) {
      expect(
        streamed.samples[index],
        closeTo(longSamples[streamed.sourceStart + index], 1e-4),
        reason: 'window sample $index diverged from the resident decode',
      );
    }

    // The R1 controls survive the rebuild.
    expect(streamedClip.gain, 0.7);
    expect(streamedClip.panLeft, isNot(streamedClip.panRight),
        reason: 'the pan must not be flattened by the source remap');
    store.dispose();
  });

  test('the window clamps into the clip span: a center before the clip '
      'reads its head, one past it reads its tail', () async {
    final (store, _) = await storeWithBoth();
    final mix = mixOf(const [
      ScheduledAudioClip(
        filePath: 'long',
        startFrame: 100, // timeline sample 1000
        endFrameExclusive: 1300,
      ),
    ]);

    final before = windowedMixUpload(
      mix: mix,
      conformStore: store,
      deviceRate: sampleRate,
      centerSample: 0, // playhead long before the clip
    )!;
    expect(before.sources.single.sourceStart, 0,
        reason: 'not yet started: the window covers the clip head');

    final past = windowedMixUpload(
      mix: mix,
      conformStore: store,
      deviceRate: sampleRate,
      centerSample: 1000000,
    )!;
    final tail = past.sources.single;
    // The clip spans 1200 frames = 12000 source samples; the file's extra
    // 50 are never audible through this clip and are never read.
    expect(tail.sourceStart + tail.samples.length, 12000,
        reason: 'played out: the window ends at the clip SPAN, not the file');
    store.dispose();
  });

  test('streaming on a device off the project rate refuses — the caller '
      'stands down instead of pitching the audio', () async {
    final (store, _) = await storeWithBoth();
    expect(
      windowedMixUpload(
        mix: mixOf(const [
          ScheduledAudioClip(filePath: 'long', startFrame: 0,
              endFrameExclusive: 1200),
        ]),
        conformStore: store,
        deviceRate: 44100,
        centerSample: 0,
      ),
      isNull,
    );
    store.dispose();
  });

  test('a missing resident source refuses the whole upload (the old '
      'schedule keeps playing)', () async {
    final (store, _) = await storeWithBoth();
    expect(
      windowedMixUpload(
        mix: mixOf(const [
          ScheduledAudioClip(filePath: 'never-conformed', startFrame: 0,
              endFrameExclusive: 10),
        ]),
        conformStore: store,
        deviceRate: sampleRate,
        centerSample: 0,
      ),
      isNull,
    );
    store.dispose();
  });

  test('the session lets go before the cache is collected: the entry that '
      'IS its file stands down, the resident one does not', () async {
    // 🚨 The conform cache now has a size bound and a Preferences button
    // that empties it, and the collector cannot know what this session is
    // holding. A streaming entry is its file — delete the file underneath
    // and nothing notices: `resultFor` keeps answering "usable" so no
    // rebuild is ever kicked, `streamReaderFor` opens nothing, and the
    // schedule stands down. The clip is silent for the rest of the
    // session and silent in the export, with a debug line as the trace.
    //
    // The mirror on Windows is just as bad: an open reader makes the
    // delete fail, so the biggest entries survive the emptying that
    // existed to reclaim them.
    final (store, _) = await storeWithBoth();
    addTearDown(store.dispose);
    final conformPath = '${directory.path}/long.wav.wav';
    expect(store.streamReaderFor('long'), isNotNull, reason: 'reader open');

    store.releaseDiskBacked();

    expect(
      store.isStreaming('long'),
      isFalse,
      reason: 'left standing, it would answer for a file that is gone',
    );
    expect(
      File(conformPath).deleteSync,
      returnsNormally,
      reason: 'and the reader is closed, so the collector can actually '
          'remove it',
    );
    expect(
      store.resultFor('short'),
      isNotNull,
      reason: 'resident PCM is untouched — losing the file costs it '
          'nothing until the next session',
    );
  });
}
