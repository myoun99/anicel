import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/encoded_movie.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/os_video_codec.dart';
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
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    final directory = Directory.systemTemp.createTempSync('qa_movie_length');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}movie.mp4';
    // Seventy-two frames' worth of sound, the first twelve with a picture
    // each — a quiet tone, so the codec has something to keep.
    if (!writeEncodedMovie(
      path,
      frames: 12,
      sampleRate: 48000,
      sound: (sample) => sample % 48 < 24 ? 2000 : -2000,
      soundFrames: 72,
    )) {
      return;
    }
    // ⛔The premise: the sound DOES run three seconds — sixty frames past
    // the pictures — or a count of twelve would say nothing.
    final sound = decodeAudioFile(path);
    expect(sound, isNotNull);
    expect(sound!.length / sound.sampleRate, closeTo(3, 0.1));

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
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    // Twelve pictures at 24 a tick short of twelve frames either way they
    // are read: the track says 11999/24000 (what AVFoundation counts), and
    // Media Foundation hands the last picture's end over as 4999999 100ns
    // ticks. ↩️Red on the Mac and TestFlight builds of 2026-10-24 while
    // only the Windows backend counted to the nearest frame.
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
