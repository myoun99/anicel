import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_pcm_scale.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/media/media_byte_source.dart'
    show MediaFileBytes;
import '../../helpers/temp_dir.dart';

/// The disk half of streaming (AUDIO-PRO R6): windowed reads out of a
/// conform WAV must return byte-for-byte what a full decode would have —
/// the same audio must never land at two levels depending on whether it
/// streamed or sat resident.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-wav-stream-test');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// A stereo ramp whose VALUE encodes its position, so a window read
  /// from the wrong offset cannot accidentally look right.
  String writeRamp(int lengthSamples) {
    final samples = Float32List(lengthSamples * 2);
    for (var index = 0; index < lengthSamples; index += 1) {
      samples[index * 2] = (index % 1000) / 1000.0;
      samples[index * 2 + 1] = -((index % 1000) / 1000.0);
    }
    final path = '${directory.path}/ramp.wav';
    File(path).writeAsBytesSync(
      encodeConform(samples: samples, channels: 2, sampleRate: 48000),
    );
    return path;
  }

  test('the header parses and a middle window matches the full decode', () {
    final path = writeRamp(4000);
    final reader = ConformPcmStreamReader.open(path);
    expect(reader, isNotNull);
    expect(reader!.channels, 2);
    expect(reader.sampleRate, 48000);
    expect(reader.length, 4000);

    final full = decodeConform(File(path).readAsBytesSync());
    final window = reader.readWindow(1234, 500);
    expect(window.startSample, 1234);
    expect(window.samples, hasLength(500 * 2));
    for (var index = 0; index < window.samples.length; index += 1) {
      expect(
        window.samples[index],
        full.samples[1234 * 2 + index],
        reason: 'streamed sample $index diverged from the resident decode',
      );
    }
  });

  test('windows clamp into the file instead of inventing samples', () {
    final reader = ConformPcmStreamReader.open(writeRamp(1000))!;

    final head = reader.readWindow(-50, 100);
    expect(head.startSample, 0);
    expect(head.samples, hasLength(100 * 2));

    final tail = reader.readWindow(950, 100);
    expect(tail.startSample, 950);
    expect(
      tail.samples,
      hasLength(50 * 2),
      reason: 'only 50 samples exist past 950',
    );

    final past = reader.readWindow(5000, 100);
    expect(past.samples, isEmpty);
  });

  test('a provenance chunk before the data does not shift the window', () {
    // qacf rides between fmt and data in every conform this app writes;
    // the reader must find data by WALKING, not by assuming offset 44.
    final samples = Float32List.fromList([0.5, -0.5, 0.25, -0.25]);
    final path = '${directory.path}/tagged.wav';
    File(path).writeAsBytesSync(
      encodeConform(
        samples: samples,
        channels: 2,
        sampleRate: 48000,
        fingerprint: const ConformSourceFingerprint(
          sourceLength: 123,
          sourceCrc32: 456,
        ),
      ),
    );
    final reader = ConformPcmStreamReader.open(path)!;
    expect(reader.length, 2);
    final window = reader.readWindow(0, 2);
    expect(window.samples[0], closeTo(0.5, 1e-4));
    expect(window.samples[2], closeTo(0.25, 1e-4));
  });

  test('not a WAV: open answers null, never throws', () {
    final path = '${directory.path}/notwav.bin';
    File(path).writeAsBytesSync([1, 2, 3, 4, 5]);
    expect(ConformPcmStreamReader.open(path), isNull);
    expect(
      ConformPcmStreamReader.open('${directory.path}/missing.wav'),
      isNull,
    );
  });

  /// 🚨The export's mix is a WAV, and the OS encoder streams it into the
  /// movie through this reader — which opened it as a conform from 08-30,
  /// came back null, and sent every such movie out without its sound
  /// (09-25).
  group('the mix — a WAV this app wrote', () {
    /// The same stereo ramp as [writeRamp], as the export writes a mix.
    String writeMix(int lengthSamples) {
      final samples = Float32List(lengthSamples * 2);
      for (var index = 0; index < lengthSamples; index += 1) {
        samples[index * 2] = (index % 1000) / 1000.0;
        samples[index * 2 + 1] = -((index % 1000) / 1000.0);
      }
      final path = '${directory.path}/mix.wav';
      File(path).writeAsBytesSync(
        wav16Bytes(int16PcmOf(samples), sampleRate: 48000, channels: 2),
      );
      return path;
    }

    test('🚨it opens, and a middle window is the samples the mix holds', () {
      final reader = ConformPcmStreamReader.overWav16(
        MediaFileBytes(writeMix(4000)),
      );
      expect(reader, isNotNull, reason: 'opened as a conform, it was null');
      expect(reader!.channels, 2);
      expect(reader.sampleRate, 48000);
      expect(reader.length, 4000);

      final window = reader.readWindow(1234, 500);
      expect(window.startSample, 1234);
      expect(window.samples, hasLength(500 * 2));
      for (var frame = 0; frame < 500; frame += 1) {
        final value = ((1234 + frame) % 1000) / 1000.0;
        expect(window.samples[frame * 2], int16FromUnitSample(value) / 32768);
        expect(
          window.samples[frame * 2 + 1],
          int16FromUnitSample(-value) / 32768,
        );
      }
    });

    test('a conform is not the mix, and the mix is not a conform', () {
      expect(
        ConformPcmStreamReader.overWav16(MediaFileBytes(writeRamp(100))),
        isNull,
      );
      expect(ConformPcmStreamReader.open(writeMix(100)), isNull);
    });

    test('a mix shorter than its header claims is not streamed', () {
      final path = writeMix(1000);
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length - 10));

      expect(ConformPcmStreamReader.overWav16(MediaFileBytes(path)), isNull);
    });

    test('another program\'s WAV is the decoders\' — a chunk before the '
        'samples, or eight-bit ones, is not ours to stream', () {
      final ours = wav16HeaderBytes(
        dataBytes: 4,
        sampleRate: 48000,
        channels: 1,
      );
      expect(readWav16Header(ours), isNotNull, reason: 'the premise');
      final listed = Uint8List.fromList(ours)
        ..setRange(36, 40, 'LIST'.codeUnits);
      final eightBit = Uint8List.fromList(ours);
      ByteData.sublistView(eightBit).setUint16(34, 8, Endian.little);

      expect(readWav16Header(listed), isNull);
      expect(readWav16Header(eightBit), isNull);
    });
  });
}
