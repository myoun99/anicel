import 'package:flutter/material.dart';

import '../../models/project_frame_rate.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// What the person answers when a movie about to be placed runs at the
/// project's pulldown partner ([pulldownPartnerOf]).
enum MovieRateAnswer {
  /// The project keeps its rate; the movie is fitted to it in time, as it
  /// always was.
  keep,

  /// The project takes the movie's rate, its sound keeping its real time
  /// (「오디오 타이밍 유지」) — frame for frame with the movie from then on.
  take,
}

/// Asks, before a movie at [movie] lands in a project at [project], whether
/// the project takes the movie's rate — null when the person backed out of
/// the import.
///
/// 🗣️import-movie-fps-mismatch-notice (유저 10-06: 「알리는게 좋겠어」 ·
/// 「셋다 맞고」 — ③ the sound keeps its timing; 10-10 「1번」 — asked when
/// Import is pressed).
Future<MovieRateAnswer?> showMovieRateDialog(
  BuildContext context, {
  required ProjectFrameRate project,
  required ProjectFrameRate movie,
}) {
  final strings = AppText.strings;
  return showDialog<MovieRateAnswer>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('import-movie-rate-dialog'),
      title: strings.imRateTitle(movie: movie.label, project: project.label),
      titleIcon: Icons.speed_outlined,
      message: strings.imRateBody(movie.label),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('import-movie-rate-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.imRateKeep(project.label),
          actionKey: const ValueKey<String>('import-movie-rate-keep'),
          onPressed: () => Navigator.of(context).pop(MovieRateAnswer.keep),
        ),
        AppWindowAction(
          label: strings.imRateTake(movie.label),
          actionKey: const ValueKey<String>('import-movie-rate-take'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(MovieRateAnswer.take),
        ),
      ],
    ),
  );
}
