import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';

/// Behavioural pins for the mixer's Dart reference. The native byte-parity
/// suite proves the C AGREES with this file; this file proves the answers
/// are right in the first place.
void main() {
  AudioMixSource constantSource(double value, int samples, {int channels = 1}) {
    final data = Float32List(samples * channels);
    for (var index = 0; index < data.length; index += 1) {
      data[index] = value;
    }
    return AudioMixSource(samples: data, channels: channels);
  }

  /// A source whose sample N is N (so a mis-seek is instantly visible).
  AudioMixSource rampSource(int samples, {int channels = 1}) {
    final data = Float32List(samples * channels);
    for (var index = 0; index < samples; index += 1) {
      for (var channel = 0; channel < channels; channel += 1) {
        data[index * channels + channel] = index.toDouble();
      }
    }
    return AudioMixSource(samples: data, channels: channels);
  }

  group('placement', () {
    test('a clip lands on exactly its own samples', () {
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 2, endSample: 5)],
        sources: [constantSource(1.0, 16)],
        startSample: 0,
        sampleCount: 8,
        outChannels: 1,
      );
      expect(bus.toList(), [0, 0, 1, 1, 1, 0, 0, 0]);
    });

    test('the trim seeks into the source, it does not shift the clip', () {
      // offset 3 means "start playing the file from its 4th sample".
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 4,
            sourceOffset: 3,
          ),
        ],
        sources: [rampSource(16)],
        startSample: 0,
        sampleCount: 4,
        outChannels: 1,
      );
      expect(bus.toList(), [3, 4, 5, 6]);
    });

    test('a clip is sample-exact however far into the movie it sits', () {
      // The whole point of mixing rather than "starting" clips: position
      // 10 million costs the same accuracy as position 0.
      const far = 10000000;
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(sourceIndex: 0, startSample: far, endSample: far + 3),
        ],
        sources: [rampSource(8)],
        startSample: far - 1,
        sampleCount: 5,
        outChannels: 1,
      );
      expect(bus.toList(), [0, 0, 1, 2, 0]);
    });

    test('a block that starts mid-clip reads the right source samples', () {
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 8)],
        sources: [rampSource(16)],
        startSample: 5,
        sampleCount: 3,
        outChannels: 1,
      );
      expect(bus.toList(), [5, 6, 7]);
    });
  });

  group('summing', () {
    test('overlapping clips add', () {
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 4),
          AudioMixClip(sourceIndex: 0, startSample: 2, endSample: 6),
        ],
        sources: [constantSource(0.25, 16)],
        startSample: 0,
        sampleCount: 6,
        outChannels: 1,
      );
      expect(bus.toList(), [0.25, 0.25, 0.5, 0.5, 0.25, 0.25]);
    });

    test('the bus is allowed past unity — headroom is not clipping', () {
      // Preview must not quietly disagree with export. The old path
      // clamped the platform player's volume at 1.0 while ffmpeg applied
      // gain exactly; the bus applies it exactly too.
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 2, gain: 2.5),
        ],
        sources: [constantSource(1.0, 4)],
        startSample: 0,
        sampleCount: 2,
        outChannels: 1,
      );
      expect(bus.toList(), [2.5, 2.5]);
    });
  });

  group('fades', () {
    test('a fade-in ramps linearly from silence', () {
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 8,
            fadeInSamples: 4,
          ),
        ],
        sources: [constantSource(1.0, 8)],
        startSample: 0,
        sampleCount: 5,
        outChannels: 1,
      );
      expect(bus.toList(), [0.0, 0.25, 0.5, 0.75, 1.0]);
    });

    test('a fade-out ramps to silence at the clip end', () {
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 4,
            fadeOutSamples: 4,
          ),
        ],
        sources: [constantSource(1.0, 8)],
        startSample: 0,
        sampleCount: 4,
        outChannels: 1,
      );
      // remaining = end - position: 4, 3, 2, 1 over a 4-sample fade.
      expect(bus.toList(), [1.0, 0.75, 0.5, 0.25]);
    });

    test('overlapping fades multiply', () {
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 4,
            fadeInSamples: 4,
            fadeOutSamples: 4,
          ),
        ],
        sources: [constantSource(1.0, 8)],
        startSample: 0,
        sampleCount: 4,
        outChannels: 1,
      );
      expect(bus.toList(), [0.0, 0.75 * 0.25, 0.5 * 0.5, 0.25 * 0.75]);
    });

    test('gain scales the whole envelope', () {
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 4,
            gain: 0.5,
            fadeInSamples: 2,
          ),
        ],
        sources: [constantSource(1.0, 8)],
        startSample: 0,
        sampleCount: 4,
        outChannels: 1,
      );
      expect(bus.toList(), [0.0, 0.25, 0.5, 0.5]);
    });
  });

  group('channels', () {
    test('a mono source feeds every output channel', () {
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 2)],
        sources: [constantSource(0.5, 4)],
        startSample: 0,
        sampleCount: 2,
        outChannels: 2,
      );
      expect(bus.toList(), [0.5, 0.5, 0.5, 0.5]);
    });

    test('a stereo source maps straight across', () {
      final data = Float32List.fromList([1, 2, 3, 4]);
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 2)],
        sources: [AudioMixSource(samples: data, channels: 2)],
        startSample: 0,
        sampleCount: 2,
        outChannels: 2,
      );
      expect(bus.toList(), [1, 2, 3, 4]);
    });

    test('a mono source is not silently widened in memory', () {
      // Animation SE are overwhelmingly mono; duplicating them to stereo
      // at load would spend half the audio RAM saying nothing new.
      final source = constantSource(1.0, 100);
      expect(source.samples.length, 100);
      expect(source.length, 100);
    });
  });

  group('windowing', () {
    test('samples past the source end are silence, not garbage', () {
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 6)],
        sources: [constantSource(1.0, 3)],
        startSample: 0,
        sampleCount: 6,
        outChannels: 1,
      );
      expect(bus.toList(), [1, 1, 1, 0, 0, 0]);
    });

    test('a windowed source contributes only what it holds', () {
      // This is how a STREAMED clip presents itself: samples 4..7 of the
      // source, sitting in a ring buffer. Everything outside the window is
      // silence — the mixer never waits for I/O, because an audio callback
      // that waits is a dropout.
      final window = AudioMixSource(
        samples: Float32List.fromList([1, 1, 1, 1]),
        channels: 1,
        sourceStart: 4,
      );
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 10)],
        sources: [window],
        startSample: 0,
        sampleCount: 10,
        outChannels: 1,
      );
      expect(bus.toList(), [0, 0, 0, 0, 1, 1, 1, 1, 0, 0]);
    });
  });

  group('output stage', () {
    test('int16 conversion clips, the bus does not', () {
      final bus = Float64List.fromList([0, 1.0, -1.0, 2.5, -2.5, 0.5]);
      // -1.0 reaches -32768: the full negative range is representable, and
      // only +1.0 needs clamping because 32768 does not fit an int16.
      expect(audioBusToInt16(bus).toList(), [
        0,
        32767,
        -32768,
        32767,
        -32768,
        16384,
      ]);
    });

    test('a unity-gain clip survives the chain bit-exactly', () {
      // The property the 32768 convention buys, and the reason it is worth
      // stating: decode gives raw/32768, the mixer passes it through at
      // unity, and the output stage multiplies back — landing on the SAME
      // int16 the file held, for every value including -32768.
      final raw = <int>[-32768, -32767, -1, 0, 1, 16384, 32766, 32767];
      final bus = Float64List.fromList([
        for (final value in raw) value / 32768.0,
      ]);
      expect(audioBusToInt16(bus).toList(), raw);
    });

    test('float conversion narrows without clipping', () {
      final bus = Float64List.fromList([2.5, -2.5]);
      expect(audioBusToFloat(bus).toList(), [2.5, -2.5]);
    });

    test('rounding is half away from zero, like the C llround', () {
      // 0.5/32768 lands exactly on .5 — Dart's round() and C's llround
      // both go away from zero, which is the arithmetic contract the
      // whole native core rests on.
      final bus = Float64List.fromList([0.5 / 32768.0, -0.5 / 32768.0]);
      expect(audioBusToInt16(bus).toList(), [1, -1]);
    });
  });

  group('the timebase bridge', () {
    test('clip positions come from the exact rate, not a rounded one', () {
      // A clip anchored at video frame 100 of a 23.976 project starts at
      // this sample and no other. Getting the rate wrong by the 0.1%
      // pulldown puts it 4 samples out here — and proportionally further
      // the longer the movie runs.
      const rate = ProjectFrameRate.ntsc(24);
      const sampleRate = 48000;
      final start = rate.frameToSample(100, sampleRate);
      expect(start, (100 * sampleRate * 1001 + 23999) ~/ 24000);
      expect(rate.sampleToFrame(start, sampleRate), 100);

      final bus = mixAudioReference(
        clips: [
          AudioMixClip(
            sourceIndex: 0,
            startSample: start,
            endSample: start + 2,
          ),
        ],
        sources: [constantSource(1.0, 4)],
        startSample: start - 1,
        sampleCount: 4,
        outChannels: 1,
      );
      expect(bus.toList(), [0, 1, 1, 0]);
    });
  });

  group('degenerate input', () {
    test('empty clips, empty sources and zero counts stay silent', () {
      expect(
        mixAudioReference(
          clips: const [],
          sources: const [],
          startSample: 0,
          sampleCount: 4,
          outChannels: 1,
        ).toList(),
        [0, 0, 0, 0],
      );
      expect(
        mixAudioReference(
          clips: const [
            AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 4),
          ],
          sources: const [],
          startSample: 0,
          sampleCount: 2,
          outChannels: 1,
        ).toList(),
        [0, 0],
      );
      expect(
        mixAudioReference(
          clips: const [],
          sources: const [],
          startSample: 0,
          sampleCount: 0,
          outChannels: 2,
        ).toList(),
        isEmpty,
      );
    });

    test('an out-of-range source index is ignored, not a crash', () {
      final bus = mixAudioReference(
        clips: const [
          AudioMixClip(sourceIndex: 5, startSample: 0, endSample: 2),
          AudioMixClip(sourceIndex: -1, startSample: 0, endSample: 2),
          AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 2),
        ],
        sources: [constantSource(1.0, 4)],
        startSample: 0,
        sampleCount: 2,
        outChannels: 1,
      );
      expect(bus.toList(), [1, 1]);
    });

    test('a reversed clip contributes nothing', () {
      final bus = mixAudioReference(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 4, endSample: 2)],
        sources: [constantSource(1.0, 8)],
        startSample: 0,
        sampleCount: 6,
        outChannels: 1,
      );
      expect(bus.toList(), [0, 0, 0, 0, 0, 0]);
    });
  });
}
