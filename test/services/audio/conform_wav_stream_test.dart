import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/services/audio/conform_wav_stream.dart';

/// The disk half of streaming (AUDIO-PRO R6): windowed reads out of a
/// conform WAV must return byte-for-byte what a full decode would have —
/// the same audio must never land at two levels depending on whether it
/// streamed or sat resident.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-wav-stream-test');
  });

  tearDown(() => directory.delete(recursive: true));

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
      encodeConformWav(samples: samples, channels: 2, sampleRate: 48000),
    );
    return path;
  }

  test('the header parses and a middle window matches the full decode', () {
    final path = writeRamp(4000);
    final reader = ConformWavStreamReader.open(path);
    expect(reader, isNotNull);
    expect(reader!.channels, 2);
    expect(reader.sampleRate, 48000);
    expect(reader.length, 4000);

    final full = decodeConformWav(File(path).readAsBytesSync());
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
    reader.close();
  });

  test('windows clamp into the file instead of inventing samples', () {
    final reader = ConformWavStreamReader.open(writeRamp(1000))!;

    final head = reader.readWindow(-50, 100);
    expect(head.startSample, 0);
    expect(head.samples, hasLength(100 * 2));

    final tail = reader.readWindow(950, 100);
    expect(tail.startSample, 950);
    expect(tail.samples, hasLength(50 * 2),
        reason: 'only 50 samples exist past 950');

    final past = reader.readWindow(5000, 100);
    expect(past.samples, isEmpty);
    reader.close();
  });

  test('a provenance chunk before the data does not shift the window', () {
    // qacf rides between fmt and data in every conform this app writes;
    // the reader must find data by WALKING, not by assuming offset 44.
    final samples = Float32List.fromList([0.5, -0.5, 0.25, -0.25]);
    final path = '${directory.path}/tagged.wav';
    File(path).writeAsBytesSync(
      encodeConformWav(
        samples: samples,
        channels: 2,
        sampleRate: 48000,
        fingerprint: const ConformSourceFingerprint(
          sourceLength: 123,
          sourceModifiedMicros: 456,
        ),
      ),
    );
    final reader = ConformWavStreamReader.open(path)!;
    expect(reader.length, 2);
    final window = reader.readWindow(0, 2);
    expect(window.samples[0], closeTo(0.5, 1e-4));
    expect(window.samples[2], closeTo(0.25, 1e-4));
    reader.close();
  });

  test('not a WAV: open answers null, never throws', () {
    final path = '${directory.path}/notwav.bin';
    File(path).writeAsBytesSync([1, 2, 3, 4, 5]);
    expect(ConformWavStreamReader.open(path), isNull);
    expect(
      ConformWavStreamReader.open('${directory.path}/missing.wav'),
      isNull,
    );
  });
}
