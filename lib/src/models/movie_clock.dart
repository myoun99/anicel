import '../native/qa_video_decoder.dart' show QaVideoInfo;
import 'project_frame_rate.dart';

/// THE MOVIE RIDES THE SOUND'S CLOCK (유저 2026-09-11, 미디어 배치 라운드 6:
/// 「영상의 시간은 소리와 같은 시계로 맞춘다 — 소리가 실시간이라 그림도
/// 시간으로 매핑해야 짝이 안 어긋난다」).
///
/// A movie's pictures and its sound land as two blocks that move apart (the
/// SE lane was the choice for sound, 09-01), so the one thing that keeps
/// them in step is that both read time the same way: a project frame is
/// its exact start at the project's rate, scaled by the project's audio
/// speed — the pull a pulldown rate change applies to every sound
/// (EXPORT-AUDIO ④) — and the movie shows the frame that holds that
/// instant.
///
/// ⛔NOT FRAME FOR FRAME. A 23.976 take in a 24 project would drift one
/// frame every 41.7 seconds against its own soundtrack. With the pull on, a
/// 23.976→24 change keeps every frame where it was, exactly as it keeps
/// every sound's frame span; with it off both keep real time.
class MovieClock {
  const MovieClock({
    required this.projectRate,
    required this.audioSpeed,
    required this.movieRate,
  });

  final ProjectFrameRate projectRate;

  /// The project's accumulated audio pull ([Project.audioSpeedNumerator] /
  /// [Project.audioSpeedDenominator]) — 1/1 until a pulldown change.
  final ({int numerator, int denominator}) audioSpeed;

  /// The movie's own rate as the decoder reports it — a fraction, because
  /// 30000/1001 is not 29.97.
  final ({int numerator, int denominator}) movieRate;

  /// The movie frame on screen [elapsedFrames] project frames into the
  /// movie — the frame that holds that instant, so a slower movie holds and
  /// a faster one skips.
  int movieFrameAt(int elapsedFrames) {
    if (elapsedFrames <= 0 || _degenerate) {
      return 0;
    }
    return elapsedFrames *
        projectRate.denominator *
        audioSpeed.numerator *
        movieRate.numerator ~/
        (projectRate.numerator *
            audioSpeed.denominator *
            movieRate.denominator);
  }

  /// Whole project frames that show a movie of [movieFrames] frames, rounded
  /// up — the block a whole take occupies on the timeline.
  int projectFramesCovering(int movieFrames) {
    if (movieFrames <= 0 || _degenerate) {
      return 0;
    }
    final numerator =
        movieFrames *
        movieRate.denominator *
        projectRate.numerator *
        audioSpeed.denominator;
    final denominator =
        movieRate.numerator * projectRate.denominator * audioSpeed.numerator;
    return (numerator + denominator - 1) ~/ denominator;
  }

  /// A rate or a speed of zero measures nothing; everything reads frame 0.
  bool get _degenerate =>
      projectRate.numerator <= 0 ||
      projectRate.denominator <= 0 ||
      audioSpeed.numerator <= 0 ||
      audioSpeed.denominator <= 0 ||
      movieRate.numerator <= 0 ||
      movieRate.denominator <= 0;
}

/// The clock [movie] runs on in a project at [projectRate] whose sounds
/// carry [audioSpeed].
///
/// 🚨★★★ONE ASSEMBLY. Three places each unpacked the decoder's rate
/// fraction into a [MovieClock] of their own — the import window's preview,
/// the door that PLACES a movie, and the hydrator that DECODES one — and
/// the three have to answer identically or the app contradicts itself: the
/// preview's IN/OUT is what lands, and a bake has to land on exactly the
/// frames the reference was showing. Nothing here decides anything; it
/// exists so that the unpacking is written once, beside the law it feeds.
MovieClock movieClockFor({
  required ProjectFrameRate projectRate,
  required ({int numerator, int denominator}) audioSpeed,
  required QaVideoInfo movie,
}) {
  return MovieClock(
    projectRate: projectRate,
    audioSpeed: audioSpeed,
    movieRate: (
      numerator: movie.fpsNumerator,
      denominator: movie.fpsDenominator,
    ),
  );
}
