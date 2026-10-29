import 'dart:io';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/media/movie_span.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/encoded_movie.dart';
import '../../helpers/native_call_watch.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/project_scratch_folder.dart';

/// A trimmed movie's piece carries the span's own sound. Since 10-09 it is
/// cut from a decode that holds only the span (board
/// sound-lands-on-its-exact-sample-Q5), so each project frame's samples are
/// counted from the span's first frame, not the sound's — and a click in the
/// span has to come back where it sat in it.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  void reset() {
    QaAudioDecoder.debugResetForTests();
    QaVideoDecoder.debugResetForTests();
    QaVideoEncoder.debugResetForTests();
  }

  setUp(() {
    reset();
    debugQaEngineLibraryPathOverride = libraryPath;
  });
  tearDown(() {
    reset();
    debugQaEngineLibraryPathOverride = null;
  });

  test('a click inside the span comes back where it sat in it', () async {
    // A movie read and written through the engine can stop inside a native
    // call under load (board the-trimmed-movie-test-can-hang-on-windows-ci —
    // this test, unwatched, held a whole run once): the watch names the
    // step and ends the file instead.
    final watch = await NativeCallWatch.start('a movie piece keeps its sound');
    addTearDown(watch.stop);
    watch.step('asking for the encoder and writing the take');
    final directory = Directory.systemTemp.createTempSync('qa_movie_piece');
    deleteAfterSessionEnds(directory);
    String at(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    const rate = 48000;
    const perFrame = rate ~/ 24;
    const clickFrame = 6;
    if (!writeEncodedMovie(
      at('source.mp4'),
      frames: 12,
      sampleRate: rate,
      sound: (sample) {
        final index = sample - clickFrame * perFrame;
        // A decaying click, so the codec keeps it.
        return index < 0 || index >= 48
            ? 0
            : ((index.isEven ? 1 : -1) * 30000 * (1 - index / 48)).round();
      },
    )) {
      return;
    }

    watch.step('cutting the piece');
    final cut = writeMovieSpan(
      at('source.mp4'),
      at('piece.mp4'),
      trim: (inFrame: 3, outFrame: 8),
      clock: (
        rate: ProjectFrameRate.fps24,
        speed: (numerator: 1, denominator: 1),
      ),
    );
    expect(cut.failure, isNull);
    expect(cut.kept!.first, 3);

    watch.step('reading the sound of the piece');
    final sound = decodeAudioFile(at('piece.mp4'));
    expect(sound, isNotNull, reason: 'the piece carries a sound');
    var peakAt = -1;
    var peak = 0.0;
    for (var frame = 0; frame < sound!.length; frame += 1) {
      final value = sound.samples[frame * sound.channels].abs();
      if (value > peak) {
        peak = value;
        peakAt = frame;
      }
    }
    const want = (clickFrame - 3) * perFrame;
    expect(
      peakAt,
      inInclusiveRange(want - 4, want + 4),
      reason: 'the click sat 3 frames into the span; it came back at '
          '$peakAt, ${peakAt / perFrame} frames in',
    );
  }, skip: skip);
}
