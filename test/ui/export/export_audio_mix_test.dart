import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/ui/export/export_audio_mix.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import '../../helpers/temp_dir.dart';

/// The export mix renderer: the same mixer that carries playback writes
/// the WAV, and the WAV says so — exact length, exact levels, output-stage
/// clipping, silence where a source could not be had.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-export-mix-test');
  });

  tearDown(() => deleteTempQuietly(directory));

  const rate = ProjectFrameRate.integer(10);
  // One int16 step: what a level loses on the way through the WAV.
  const step = 1 / 32768;

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

    final wav = readWav16(File(path).readAsBytesSync());
    expect(wav.sampleRate, 48000);
    expect(wav.channels, 2);
    // 10 frames at 10fps/48k = one second exactly — nothing for ffmpeg's
    // -shortest to trim.
    expect(wav.samples.length ~/ wav.channels, 48000);
    // Before the clip: silence. Inside: the mono source on BOTH channels
    // at -3 dB a side (native-to-rust-Q12), to one int16 step. After:
    // silence again.
    expect(wav.samples[2 * 4800 * 2 - 2], 0);
    expect(wav.samples[5 * 4800 * 2], closeTo(0.5 * audioMonoOnStereo, step));
    expect(
      wav.samples[5 * 4800 * 2 + 1],
      closeTo(0.5 * audioMonoOnStereo, step),
    );
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
      resolveSource: (_) async => constantSource(0.8, 48000),
      outputPath: path,
    );
    final wav = readWav16(File(path).readAsBytesSync());
    // (0.8 + 0.8) x 0.707 = 1.13 a side on the bus; the int16 output
    // stage clamps to just under full scale (32767/32768).
    expect(wav.samples[24000], closeTo(32767 / 32768, 1e-6));
  });

  test(
    'a volume line ramps from silence exactly as playback draws it',
    () async {
      final path = '${directory.path}/mix.wav';
      await writeExportAudioMixWav(
        schedule: const [
          ScheduledAudioClip(
            filePath: 'a',
            startFrame: 0,
            endFrameExclusive: 10,
            volume: [(frame: 0, gain: 0.0), (frame: 5, gain: 1.0)],
          ),
        ],
        rate: rate,
        totalFrames: 10,
        sampleRate: 48000,
        resolveSource: (_) async => constantSource(0.8, 48000),
        outputPath: path,
      );
      final wav = readWav16(File(path).readAsBytesSync());
      expect(wav.samples[0], 0, reason: 'the ramp starts at silence');
      // Halfway up the 5-frame ramp (~frame 2.5 = sample 12000): half
      // the level — a mono source's, -3 dB a side.
      expect(
        wav.samples[12000 * 2],
        closeTo(0.4 * audioMonoOnStereo, 0.01),
      );
      // Past the ramp: full level.
      expect(
        wav.samples[8 * 4800 * 2],
        closeTo(0.8 * audioMonoOnStereo, 0.001),
      );
    },
  );

  test('pan and the volume line survive into the render — the R1 '
      'controls must not exist only in the preview', () async {
    final path = '${directory.path}/mix.wav';
    await writeExportAudioMixWav(
      schedule: const [
        // Hard-left pan: the compensated law puts sqrt2 x gain on the
        // left and NOTHING on the right — on a mono source, which lies at
        // -3 dB a side, that is unity (Pro Tools' law).
        ScheduledAudioClip(
          filePath: 'a',
          startFrame: 0,
          endFrameExclusive: 5,
          pan: -1.0,
        ),
        // A volume line held at half gain from frame 5 on.
        ScheduledAudioClip(
          filePath: 'a',
          startFrame: 5,
          endFrameExclusive: 10,
          volume: [(frame: 0, gain: 0.5)],
        ),
      ],
      rate: rate,
      totalFrames: 10,
      sampleRate: 48000,
      resolveSource: (_) async => constantSource(0.5, 48000),
      outputPath: path,
    );
    final wav = readWav16(File(path).readAsBytesSync());
    // Panned clip, mid-clip sample: left = 0.5 x sqrt2 x 0.707, right = 0.
    expect(wav.samples[24000 * 2 - 2], closeTo(0.5, 0.001));
    expect(
      wav.samples[24000 * 2 - 1],
      0,
      reason: 'a hard-left clip must leave the right channel empty',
    );
    // The half-volume clip: half gain on both sides.
    expect(
      wav.samples[7 * 4800 * 2],
      closeTo(0.25 * audioMonoOnStereo, 0.001),
    );
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
      encodeConform(samples: ramp, channels: 1, sampleRate: 48000),
    );
    const schedule = [
      ScheduledAudioClip(
        filePath: 'long',
        startFrame: 2,
        endFrameExclusive: 18,
        offsetFrames: 1,
        gain: 0.8,
        pan: 0.5,
        volume: [(frame: 0, gain: 0.0), (frame: 3, gain: 1.0)],
      ),
    ];

    // The resident reference mixes the SAME int16-quantized samples the
    // stream reads off disk — parity means the same floats in, not the
    // pre-quantization ramp.
    //
    // ⚠️A CONFORM, not a WAV: this fixture is what the stream reader opens
    // below, and reading it with the WAV reader would parse a 64-byte
    // header as a 44-byte one — which is how this test first failed.
    final quantized = decodeConform(File(wavPath).readAsBytesSync());
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
    final reader = ConformPcmStreamReader.open(wavPath)!;
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
    final wav = readWav16(File(path).readAsBytesSync());
    expect(wav.samples[2 * 4800 * 2], closeTo(0.5 * audioMonoOnStereo, step));
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

  /// 🗣️유저 2026-11-10 (board an-mp4-reopened-loses-its-first-9-ms-of-
  /// sound-Q2): the frame a writer puts before a movie's mix holds the sound
  /// just before it — the END of the mix of the frames before.
  test('the tail of a mix is its END as written — behind silence where the '
      'mix is shorter than what is asked for', () async {
    // A ramp: no two stretches of it are alike.
    final ramp = Float32List(9600);
    for (var index = 0; index < ramp.length; index += 1) {
      ramp[index] = 0.1 + 0.8 * index / ramp.length;
    }
    final path = '${directory.path}/mix.wav';
    await writeExportAudioMixWav(
      schedule: const [
        ScheduledAudioClip(
          filePath: 'ramp',
          startFrame: 0,
          endFrameExclusive: 2,
        ),
      ],
      rate: rate,
      totalFrames: 2,
      sampleRate: 48000,
      resolveSource: (_) async => AudioMixSource(samples: ramp, channels: 1),
      outputPath: path,
    );
    final written = Int16List.sublistView(
      File(path).readAsBytesSync(),
      wav16HeaderLength,
    );
    expect(written, hasLength(9600 * 2));
    expect(written.first, isNot(0));

    final tail = exportAudioMixTail(path, 1024)!;
    expect(tail, written.sublist(written.length - 1024 * 2));
    expect(tail.first, isNot(written.first), reason: 'the head is elsewhere');

    final padded = exportAudioMixTail(path, 9600 + 1200)!;
    expect(padded.sublist(0, 1200 * 2), everyElement(0));
    expect(padded.sublist(1200 * 2), written);

    expect(exportAudioMixTail('${directory.path}/none.wav', 1024), isNull);
  });
}

/// Reads back the WAV this export writes — a REAL WAV, which is a foreign
/// format to the conform codec since 2026-08-30.
///
/// ⚠️These assertions used to call `decodeConformWav`, which worked only
/// while a conform happened to BE a WAV. The export still writes one (its
/// file leaves the app), so the fixture reads one — canonical 44-byte
/// header, exactly what [wav16HeaderBytes] lays down.
({Float32List samples, int channels, int sampleRate}) readWav16(
  Uint8List bytes,
) {
  final view = ByteData.sublistView(bytes);
  final channels = view.getUint16(22, Endian.little);
  final sampleRate = view.getUint32(24, Endian.little);
  final dataBytes = view.getUint32(40, Endian.little);
  final count = dataBytes ~/ 2;
  final samples = Float32List(count);
  for (var i = 0; i < count; i += 1) {
    samples[i] = view.getInt16(44 + i * 2, Endian.little) / 32768.0;
  }
  return (samples: samples, channels: channels, sampleRate: sampleRate);
}
