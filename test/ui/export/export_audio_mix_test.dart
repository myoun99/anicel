import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart'
    show AudioVolumeKey;
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/services/audio/conform_wav_stream.dart';
import 'package:anicel/src/ui/export/export_audio_mix.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// The export mix renderer: the same mixer that carries playback writes
/// the WAV, and the WAV says so — exact length, exact levels, output-stage
/// clipping, silence where a source could not be had.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-export-mix-test');
  });

  tearDown(() => directory.delete(recursive: true));

  const rate = ProjectFrameRate.integer(10);

  AudioMixSource constantSource(double value, int frames) {
    final samples = Float32List(frames);
    for (var index = 0; index < frames; index += 1) {
      samples[index] = value;
    }
    return AudioMixSource(samples: samples, channels: 1);
  }

  test('renders the schedule to EXACTLY the video length, at the level the '
      'preview played', () async {
    final path = '${directory.path}/mix.wav';
    final written = await writeExportAudioMixWav(
      schedule: const [
        ScheduledAudioClip(
          filePath: 'tone.wav',
          startFrame: 2,
          endFrameExclusive: 8,
        ),
      ],
      rate: rate,
      totalFrames: 10,
      sampleRate: 48000,
      resolveSource: (_) async => constantSource(0.5, 48000),
      outputPath: path,
    );
    expect(written, isTrue);

    final wav = decodeConformWav(File(path).readAsBytesSync());
    expect(wav.sampleRate, 48000);
    expect(wav.channels, 2);
    // 10 frames at 10fps/48k = one second exactly — nothing for ffmpeg's
    // -shortest to trim.
    expect(wav.length, 48000);
    // Before the clip: silence. Inside: the mono source on BOTH channels
    // at unity (0.5 survives the int16 round-trip bit-exactly). After:
    // silence again.
    expect(wav.samples[2 * 4800 * 2 - 2], 0);
    expect(wav.samples[5 * 4800 * 2], 0.5);
    expect(wav.samples[5 * 4800 * 2 + 1], 0.5);
    expect(wav.samples[9 * 4800 * 2], 0);
  });

  test('overlapping clips sum with headroom and clip at the OUTPUT stage — '
      'the same semantics playback mixes with', () async {
    final path = '${directory.path}/mix.wav';
    await writeExportAudioMixWav(
      schedule: const [
        ScheduledAudioClip(filePath: 'a', startFrame: 0, endFrameExclusive: 10),
        ScheduledAudioClip(filePath: 'a', startFrame: 0, endFrameExclusive: 10),
      ],
      rate: rate,
      totalFrames: 10,
      sampleRate: 48000,
      resolveSource: (_) async => constantSource(0.6, 48000),
      outputPath: path,
    );
    final wav = decodeConformWav(File(path).readAsBytesSync());
    // 0.6 + 0.6 = 1.2 on the bus; the int16 output stage clamps to just
    // under full scale (32767/32768).
    expect(wav.samples[24000], closeTo(32767 / 32768, 1e-6));
  });

  test('a fade-in ramps from silence exactly like the playback envelope',
      () async {
    final path = '${directory.path}/mix.wav';
    await writeExportAudioMixWav(
      schedule: const [
        ScheduledAudioClip(
          filePath: 'a',
          startFrame: 0,
          endFrameExclusive: 10,
          fadeInFrames: 5,
        ),
      ],
      rate: rate,
      totalFrames: 10,
      sampleRate: 48000,
      resolveSource: (_) async => constantSource(0.8, 48000),
      outputPath: path,
    );
    final wav = decodeConformWav(File(path).readAsBytesSync());
    expect(wav.samples[0], 0, reason: 'the ramp starts at silence');
    // Halfway through the 5-frame fade (~frame 2.5 = sample 12000): half
    // the level.
    expect(wav.samples[12000 * 2], closeTo(0.4, 0.01));
    // Past the fade: full level.
    expect(wav.samples[8 * 4800 * 2], closeTo(0.8, 0.001));
  });

  test('pan and the volume envelope survive into the render — the R1 '
      'controls must not exist only in the preview', () async {
    final path = '${directory.path}/mix.wav';
    await writeExportAudioMixWav(
      schedule: const [
        // Hard-left pan: the compensated law puts sqrt2 x gain on the
        // left and NOTHING on the right.
        ScheduledAudioClip(
          filePath: 'a',
          startFrame: 0,
          endFrameExclusive: 5,
          pan: -1.0,
        ),
        // An envelope dropping to half gain from frame 5 on.
        ScheduledAudioClip(
          filePath: 'a',
          startFrame: 5,
          endFrameExclusive: 10,
          volumeKeys: [
            AudioVolumeKey(frame: 0, gain: 0.5),
          ],
        ),
      ],
      rate: rate,
      totalFrames: 10,
      sampleRate: 48000,
      resolveSource: (_) async => constantSource(0.5, 48000),
      outputPath: path,
    );
    final wav = decodeConformWav(File(path).readAsBytesSync());
    // Panned clip, mid-clip sample: left = 0.5 x sqrt2, right = 0.
    expect(wav.samples[24000 * 2 - 2], closeTo(0.5 * 1.41421, 0.001));
    expect(wav.samples[24000 * 2 - 1], 0,
        reason: 'a hard-left clip must leave the right channel empty');
    // Enveloped clip: half gain on both sides.
    expect(wav.samples[7 * 4800 * 2], closeTo(0.25, 0.001));
  });

  test('a STREAMING source renders byte-for-byte what the resident render '
      'writes (AUDIO-PRO R6)', () async {
    // A ramp whose value encodes position: a window read from the wrong
    // offset cannot accidentally match.
    final ramp = Float32List(96000);
    for (var index = 0; index < ramp.length; index += 1) {
      ramp[index] = ((index % 2000) - 1000) / 2000.0;
    }
    final wavPath = '${directory.path}/long.wav';
    File(wavPath).writeAsBytesSync(
      encodeConformWav(samples: ramp, channels: 1, sampleRate: 48000),
    );
    const schedule = [
      ScheduledAudioClip(
        filePath: 'long',
        startFrame: 2,
        endFrameExclusive: 18,
        offsetFrames: 1,
        gain: 0.8,
        pan: 0.5,
        fadeInFrames: 3,
      ),
    ];

    // The resident reference mixes the SAME int16-quantized samples the
    // stream reads off disk — parity means the same floats in, not the
    // pre-quantization ramp.
    final quantized = decodeConformWav(File(wavPath).readAsBytesSync());
    final residentPath = '${directory.path}/resident.wav';
    await writeExportAudioMixWav(
      schedule: schedule,
      rate: rate,
      totalFrames: 20,
      sampleRate: 48000,
      resolveSource: (_) async =>
          AudioMixSource(samples: quantized.samples, channels: 1),
      outputPath: residentPath,
    );

    final streamedPath = '${directory.path}/streamed.wav';
    final reader = ConformWavStreamReader.open(wavPath)!;
    final written = await writeExportAudioMixWav(
      schedule: schedule,
      rate: rate,
      totalFrames: 20,
      sampleRate: 48000,
      resolveSource: (_) async =>
          fail('a streamable source must never be loaded whole'),
      resolveStreamReader: (_) => reader,
      outputPath: streamedPath,
    );
    reader.close();
    expect(written, isTrue);
    expect(
      File(streamedPath).readAsBytesSync(),
      File(residentPath).readAsBytesSync(),
      reason: 'residency is a policy; the mix must not hear it',
    );
  });

  test('an unresolvable source renders ITS clip silent; nothing at all '
      'renders no file', () async {
    final path = '${directory.path}/mix.wav';
    final written = await writeExportAudioMixWav(
      schedule: const [
        ScheduledAudioClip(filePath: 'ok', startFrame: 0, endFrameExclusive: 5),
        ScheduledAudioClip(
          filePath: 'gone',
          startFrame: 5,
          endFrameExclusive: 10,
        ),
      ],
      rate: rate,
      totalFrames: 10,
      sampleRate: 48000,
      resolveSource: (filePath) async =>
          filePath == 'ok' ? constantSource(0.5, 48000) : null,
      outputPath: path,
      log: (_) {},
    );
    expect(written, isTrue);
    final wav = decodeConformWav(File(path).readAsBytesSync());
    expect(wav.samples[2 * 4800 * 2], 0.5);
    expect(wav.samples[7 * 4800 * 2], 0, reason: 'the missing clip is silent');

    expect(
      await writeExportAudioMixWav(
        schedule: const [
          ScheduledAudioClip(
            filePath: 'gone',
            startFrame: 0,
            endFrameExclusive: 5,
          ),
        ],
        rate: rate,
        totalFrames: 10,
        sampleRate: 48000,
        resolveSource: (_) async => null,
        outputPath: '${directory.path}/none.wav',
        log: (_) {},
      ),
      isFalse,
      reason: 'nothing audible means video-only encode, no silent track',
    );

    expect(
      await writeExportAudioMixWav(
        schedule: const [],
        rate: rate,
        totalFrames: 10,
        sampleRate: 48000,
        resolveSource: (_) async => null,
        outputPath: '${directory.path}/empty.wav',
      ),
      isFalse,
    );
  });
}
