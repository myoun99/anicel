import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/audio/sound_span.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// What a movie piece's writer is handed to put before the piece's own sound
/// ([int16PcmBefore]; 유저 2026-11-10, board an-mp4-reopened-loses-its-
/// first-9-ms-of-sound-Q2: 「무음, 범위 앞에 소리가 있으면 그 소리」): the
/// samples the source plays just before the span's first, each where it lay
/// against it.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sound-before-a-sample');
  });

  tearDown(() => deleteTempQuietly(directory));

  const rate = 48000;
  const lead = 1024;

  /// A stereo sound of [samples] frames whose every sample says where it
  /// lies: frame n holds n + 1 on the left and its negative on the right.
  MediaFileBytes soundOf(int samples) {
    final pcm = Int16List(samples * 2);
    for (var index = 0; index < samples; index += 1) {
      pcm[index * 2] = index + 1;
      pcm[index * 2 + 1] = -(index + 1);
    }
    final path = '${directory.path}${Platform.pathSeparator}sound.wav';
    File(path).writeAsBytesSync(wav16Bytes(pcm, sampleRate: rate, channels: 2));
    return MediaFileBytes(path);
  }

  /// The sound frame [pcm] holds at [index], both channels.
  List<int> frameAt(Int16List pcm, int index) => [
    pcm[index * 2],
    pcm[index * 2 + 1],
  ];

  test('the samples just before it, in their order', () {
    final before = int16PcmBefore(soundOf(4000), 2000, count: lead)!;

    expect(before, hasLength(lead * 2));
    expect(frameAt(before, 0), [977, -977]);
    expect(frameAt(before, lead - 1), [2000, -2000]);
  });

  test('silence stands where the sound has not begun — what there is of it '
      'keeps its place against the sample', () {
    // 224 of the 1,024 lie before the sound's first.
    final before = int16PcmBefore(soundOf(4000), 800, count: lead)!;

    expect(before, hasLength(lead * 2));
    expect(before.sublist(0, 224 * 2), everyElement(0));
    expect(frameAt(before, 224), [1, -1]);
    expect(frameAt(before, lead - 1), [800, -800]);
  });

  test('silence stands where the sound is already over', () {
    final before = int16PcmBefore(soundOf(1500), 2000, count: lead)!;

    expect(before, hasLength(lead * 2));
    expect(frameAt(before, 0), [977, -977]);
    expect(frameAt(before, 523), [1500, -1500]);
    expect(before.sublist(524 * 2), everyElement(0));
  });

  test('nothing lies before the first sample', () {
    expect(int16PcmBefore(soundOf(4000), 0, count: lead), isNull);
  });
}
