import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**A MOVIE IS AS LONG AS ITS PICTURES — NOT AS ITS SOUND.**
///
/// 유저 2026-08-31 (F-54): 「72프레임짜리 비디오인데 73프레임째의 빈 화면이
/// 생성되어있음」 — a movie's sound runs past its last picture, and a count
/// taken off the whole presentation turns the overshoot into frames with
/// nothing in them. The fix asked the video track, and on Windows it was
/// never answered (검증 2026-10-23,
/// windows-counts-a-movie-by-its-longest-track): a 72-frame `.mov` whose
/// sound ran 69ms longer was still 73 frames, the last one empty.
///
/// The movie here is the app's own — twelve pictures and three seconds of
/// sound — so the overshoot is not a fraction of a frame that rounding
/// hides but sixty frames that are plainly not there.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaVideoDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaVideoDecoder.instance?.close();
    QaVideoDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  test('🚨twelve pictures with three seconds of sound are twelve frames, and '
      'the last of them is a picture', () {
    final decoder = QaVideoDecoder.instance;
    final encoder = QaVideoEncoder.instance;
    if (decoder == null ||
        !decoder.isSupported ||
        encoder == null ||
        !encoder.isSupported) {
      return;
    }
    final directory = Directory.systemTemp.createTempSync('qa_movie_length');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}movie.mp4';
    const rate = 48000;
    const perFrame = rate ~/ 24;
    expect(
      encoder.open(
        path: path,
        width: 64,
        height: 48,
        fpsNumerator: 24,
        fpsDenominator: 1,
        sampleRate: rate,
        channels: 2,
      ),
      isTrue,
      reason: encoder.lastError,
    );
    // Seventy-two frames' worth of sound, the first twelve with a picture
    // each.
    for (var frame = 0; frame < 72; frame += 1) {
      if (frame < 12) {
        final grey = Uint8List(64 * 48 * 4)..fillRange(0, 64 * 48 * 4, 128);
        expect(encoder.writeFrame(grey), isTrue, reason: encoder.lastError);
      }
      final pcm = Int16List(perFrame * 2);
      for (var index = 0; index < perFrame; index += 1) {
        // A quiet tone, so the codec has something to keep.
        final value = (index % 48 < 24 ? 2000 : -2000);
        pcm[index * 2] = value;
        pcm[index * 2 + 1] = value;
      }
      expect(encoder.writeAudio(pcm, perFrame), isTrue);
    }
    expect(encoder.finish(), isTrue, reason: encoder.lastError);

    final document = decoder.openDocument(path);
    expect(document, isNotNull, reason: decoder.lastError);
    expect(
      document!.info.frameCount,
      12,
      reason: 'the sound runs to frame 72 — counted off the whole '
          'presentation, sixty frames of nothing',
    );
    expect(
      decoder.frameOf(document, 11),
      isNotNull,
      reason: 'the last frame counted is a picture: ${decoder.lastError}',
    );
  }, skip: skip);

  test('a movie whose last picture ends a tick short of a whole frame still '
      'counts that frame', () {
    final decoder = QaVideoDecoder.instance;
    if (decoder == null || !decoder.isSupported) {
      return;
    }
    // Twelve pictures at 24, whose end Media Foundation hands over as
    // 4999999 hundred-nanosecond ticks — rounded, a tick short of twelve.
    final document = decoder.openDocument(
      File('test/fixtures/tone_with_video.mp4').absolute.path,
    );
    expect(document, isNotNull, reason: decoder.lastError);
    expect(
      document!.info.frameCount,
      12,
      reason: 'counted to the nearest frame — truncated, it is eleven',
    );
  }, skip: skip);
}
