import 'package:flutter/material.dart';

import '../../models/movie_clock.dart' show ProjectClock;
import '../../models/project_frame_rate.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'import_file_settings.dart' show MovieParts;

/// What the person answers when a movie about to be placed runs at the
/// project's pulldown partner ([pulldownPartnerOf]).
enum MovieRateAnswer {
  /// The project keeps its rate; the movie is fitted to it in time, as it
  /// always was.
  keep,

  /// The project keeps its rate, and the movie carried in is rewritten at
  /// its speed — frame for frame, its sound pulled with its pictures
  /// (🗣️F-588, 유저 2026-11-14: 「이 영상만」).
  fit,

  /// The project takes the movie's rate, its sound keeping its real time
  /// (「오디오 타이밍 유지」) — frame for frame with the movie from then on.
  take,
}

/// Asks, before a movie at [movie] lands in a project on [project]'s clock,
/// what is matched to what — null when the person backed out of the import.
///
/// 🗣️import-movie-fps-mismatch-notice (유저 10-06: 「알리는게 좋겠어」 ·
/// 「셋다 맞고」 — ③ the sound keeps its timing; 10-10 「1번」 — asked when
/// Import is pressed).
///
/// 🗣️F-588 (유저 2026-11-14: 「이 영상만」 — the slot always there, pressed
/// only where it can be; the labels in plain words, the numbers in the
/// hover): [MovieRateAnswer.fit] can be pressed where [fit] says every such
/// movie is carried in — a movie pointed at, or one the pool holds already,
/// has no bytes of the import's own to rewrite. Its label and hover say
/// what of the movie [fit] brings: a sound alone is the sound rewritten.
Future<MovieRateAnswer?> showMovieRateDialog(
  BuildContext context, {
  required ProjectClock project,
  required ProjectFrameRate movie,
  required ({bool can, MovieParts brings}) fit,
}) {
  final strings = AppText.strings;
  final rate = project.rate.label;
  final apart = _secondsAFrameApart(
    project.rate.inSourceTime(project.speed),
    movie,
  );
  return showDialog<MovieRateAnswer>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('import-movie-rate-dialog'),
      title: strings.imRateTitle(movie: movie.label, project: rate),
      titleIcon: Icons.speed_outlined,
      message: strings.imRateBody,
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('import-movie-rate-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.imRateKeep(rate),
          actionKey: const ValueKey<String>('import-movie-rate-keep'),
          tooltip: apart == null ? null : strings.imRateKeepTip(apart),
          onPressed: () => Navigator.of(context).pop(MovieRateAnswer.keep),
        ),
        AppWindowAction(
          label: fit.brings == MovieParts.sound
              ? strings.imRateFitSound(rate)
              : strings.imRateFitMovie(rate),
          actionKey: const ValueKey<String>('import-movie-rate-fit'),
          tooltip: switch (fit.brings) {
            MovieParts.pictureAndSound => strings.imRateFitTipPictureAndSound,
            MovieParts.picture => strings.imRateFitTipPicture,
            MovieParts.sound => strings.imRateFitTipSound,
          },
          onPressed: fit.can
              ? () => Navigator.of(context).pop(MovieRateAnswer.fit)
              : null,
        ),
        AppWindowAction(
          label: strings.imRateTake(movie.label),
          actionKey: const ValueKey<String>('import-movie-rate-take'),
          tooltip: strings.imRateTakeTip(movie.label),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(MovieRateAnswer.take),
        ),
      ],
    ),
  );
}

/// How many seconds pass, rounded, before a movie at [movie] kept on a
/// project running at [pace] in its own time has drifted one frame from its
/// pictures — 42 for 23.976 in 24 — or null where it does not drift.
int? _secondsAFrameApart(ProjectFrameRate pace, ProjectFrameRate movie) {
  final seconds = pace.denominator * movie.denominator;
  final frames =
      (pace.numerator * movie.denominator - movie.numerator * pace.denominator)
          .abs();
  return frames == 0 ? null : (2 * seconds + frames) ~/ (2 * frames);
}
