import 'dart:ui';

import '../../models/transition_geometry.dart' show TransitionVeil;

/// Lays the screens one-sided transitions put over a cut ([veils], in
/// order) across [rect] — its whole unit: the camera frame, or the canvas.
///
/// 🗣️F-192 (유저 2026-09-27): 「컷의 페이드인은 애초에 쌩 검은화면에서
/// 바뀐단거였음. 화이트인은 쌩 흰화면에서 바뀌는거고」. ONE draw for every
/// surface that shows a fade — the playback and export stack
/// (`PlaybackFramePainter`), the canvas-size bakes and the editing canvas —
/// so what is edited against is what plays and what exports.
///
/// [thinnedBy] is the unit's own weight when the caller thins the picture
/// by its paint rather than by a layer around the whole unit (a track above
/// the stage): the screen belongs to the unit, so it thins with it.
void paintTransitionVeils(
  Canvas canvas,
  Rect rect,
  List<TransitionVeil> veils, {
  double thinnedBy = 1,
}) {
  for (final veil in veils) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color(
          veil.color,
        ).withValues(alpha: (veil.opacity * thinnedBy).clamp(0.0, 1.0)),
    );
  }
}
