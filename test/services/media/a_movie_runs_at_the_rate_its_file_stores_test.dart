import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';

import '../../helpers/mpeg4_visual_movie.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**A MOVIE RUNS AT THE RATE ITS FILE STORES.**
///
/// 검증 2026-10-23 (movie-23976-mpeg4-part2-asks-no-speed): a 23.976 `.mov`
/// in MPEG-4 Part 2 came into a 24 project without the speed question. On
/// Windows the app had it at 10000000/417188 — 23.97, no pulldown partner —
/// and that number was nobody's but the DECODER's: the file stores 23.976,
/// the decoder hands its pictures over on the file's own times, but it
/// describes itself at a rate it worked out, and the conversion to RGB took
/// that rate and stamped every picture on it. The same clock counted a
/// movie a frame short, and some two thousand frames in it played and
/// jumped onto the wrong pictures.
///
/// The movies are MPEG-4 Part 2 because that is the decoder that does it,
/// and nothing in this app encodes one — [mpeg4VisualMovie] writes them by
/// hand. Every frame is a flat grey of its own, so a frame read from the
/// wrong place cannot pass for the right one.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaVideoDecoder.instance?.close();
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  /// [bytes] as a movie on disk, for as long as the run lasts.
  String onDisk(Uint8List bytes) {
    final directory = Directory.systemTemp.createTempSync('qa_mpeg4_visual');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}${Platform.pathSeparator}movie.mov';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  // Four apart, so the frame before and the frame after are both another.
  const greys = [40, 100, 160, 220];
  int greyOf(int frame) => greys[frame % greys.length];

  /// Which grey [rgba] shows — the nearest one, because the conversion to
  /// RGB widens video range (40 comes back 28 here, 220 comes back 237) and
  /// no two platforms need do that alike.
  int shownGrey(Uint8List rgba, QaVideoInfo info) {
    final value = rgba[(info.height ~/ 2 * info.width + info.width ~/ 2) * 4];
    return greys.reduce(
      (nearest, grey) =>
          (value - grey).abs() < (value - nearest).abs() ? grey : nearest,
    );
  }

  test('🚨a 23.976 movie is 23.976 — a 24 project\'s pulldown partner — and '
      'a 24 one is 24, each with every frame counted', () {
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    for (final movie in [
      (scale: 24000, ticks: 1001, partner: const ProjectFrameRate.ntsc(24)),
      (scale: 24, ticks: 1, partner: null),
    ]) {
      final document = decoder.openDocument(
        onDisk(
          mpeg4VisualMovie(
            frames: 12,
            timeScale: movie.scale,
            sampleTicks: movie.ticks,
            lumaOf: greyOf,
          ),
        ),
      );
      expect(document, isNotNull, reason: decoder.lastError);
      final info = document!.info;
      final rate = '${info.fpsNumerator}/${info.fpsDenominator}';
      expect(
        info.fps,
        closeTo(movie.scale / movie.ticks, 1e-4),
        reason: '$movie read as $rate — the decoder\'s own rate for 23.976 '
            'is 10000000/417188',
      );
      expect(
        pulldownPartnerOf(ProjectFrameRate.fps24, (
          numerator: info.fpsNumerator,
          denominator: info.fpsDenominator,
        )),
        movie.partner,
        reason: '🚨the question on import (F-405) is asked of this rate',
      );
      expect(
        info.frameCount,
        12,
        reason: '$movie read as $rate: twelve frames on a clock slower than '
            'the file\'s are eleven and some',
      );
    }
  }, skip: skip);

  test('🚨every frame plays as itself to the end, and a jump two thousand '
      'frames in lands where it was sent', () {
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    // Long enough for 23.97 and 23.976 to part by more than half a frame —
    // a quarter of a thousandth of one each frame.
    const frames = 2100;
    final document = decoder.openDocument(
      onDisk(mpeg4VisualMovie(frames: frames, lumaOf: greyOf)),
    );
    expect(document, isNotNull, reason: decoder.lastError);
    final info = document!.info;
    expect(info.frameCount, frames);

    final wrong = <int>[];
    for (var frame = 0; frame < frames; frame += 1) {
      final rgba = decoder.frameOf(document, frame);
      if (rgba == null || shownGrey(rgba, info) != greyOf(frame)) {
        wrong.add(frame);
      }
    }
    expect(
      wrong,
      isEmpty,
      reason: '🚨on the decoder\'s clock the next frame\'s picture began to '
          'show from frame 1900 on — now and then, then every time',
    );

    // Backwards as well as forwards: each of these is a seek.
    for (final frame in [1999, 2001, 2050, frames - 1, 3]) {
      final rgba = decoder.frameOf(document, frame);
      expect(rgba, isNotNull, reason: 'frame $frame: ${decoder.lastError}');
      expect(shownGrey(rgba!, info), greyOf(frame), reason: 'a jump to $frame');
    }
  }, skip: skip);
}
