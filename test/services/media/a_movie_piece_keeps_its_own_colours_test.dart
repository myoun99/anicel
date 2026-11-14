import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/media/movie_span.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/encoded_movie.dart';
import '../../helpers/native_call_watch.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

/// A trimmed movie's piece is the movie's own pictures, named as the movie
/// names them — not turned to the app's colour law on the way
/// (🗣️trimmed-movie-decodes-to-nv12-Q1, 유저 2026-11-14: 「원본의 색을
/// 그대로 따라 쓴다」).
void main() {
  test('a piece names what its movie names and keeps its own luma', () async {
    // As the sound's pieces are (a_movie_piece_keeps_its_own_sound_test):
    // a movie read and written through the engine can stop inside a
    // native call under load, and the watch names the step.
    final watch = await NativeCallWatch.start('a movie piece keeps colours');
    addTearDown(watch.stop);
    watch.step('asking for the encoder and writing the take');
    final directory = Directory.systemTemp.createTempSync('qa_movie_piece');
    deleteAfterSessionEnds(directory);
    String at(String name) =>
        '${directory.path}${Platform.pathSeparator}$name';
    // As a PAL camera names its pictures — its primaries, BT.709's
    // transfer, BT.601's matrix, studio range: not the app's law, and each
    // a code of its own, so none can be read for another.
    const pal = (primaries: 5, transfer: 1, matrix: 6, range: 0);
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null ||
        !writeEncodedMovie(at('source.mp4'), frames: 8, colours: pal)) {
      return;
    }

    watch.step('cutting the piece');
    final cut = writeMovieSpan(
      at('source.mp4'),
      at('piece.mp4'),
      trim: (inFrame: 2, outFrame: 5),
      clock: (
        rate: ProjectFrameRate.fps24,
        speed: (numerator: 1, denominator: 1),
      ),
      withSound: false,
    );
    expect(cut.failure, isNull);

    watch.step('reading the piece');
    final piece = decoder.openNv12Document(at('piece.mp4'));
    expect(piece, isNotNull, reason: decoder.lastError);
    addTearDown(() => decoder.closeDocument(piece!));
    expect(piece!.colours, pal, reason: 'what the movie named');
    final (width, height) = (piece.info.width, piece.info.height);
    final frame = Uint8List(piece.frameBytes);
    for (var index = 0; index < 4; index += 1) {
      final nv12 = decoder.frameOf(piece, index, into: frame);
      expect(nv12, isNotNull, reason: decoder.lastError);
      expect(
        nv12![width * (height ~/ 2) + width ~/ 2],
        closeTo(encodedMovieLumaOf(index + 2), 3),
        reason: 'the piece\'s frame $index is the movie\'s frame '
            '${index + 2}, its luma as the movie wrote it',
      );
    }
  });
}
