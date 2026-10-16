import '../../models/playback_mode.dart';

/// Whether a run's clock waits for a frame — and whether a run behind its
/// clock shows every picture all the same: [PlaybackMode]'s three settings,
/// read against what the warmer has made.
///
/// The one place the modes part. Everything else — which pictures are made,
/// in what order, how many are kept — is the same under each.
class PlaybackPictureWait {
  PlaybackPictureWait({
    required this.mode,
    required this.pictureIsThere,
    required this.aheadIsFilled,
  });

  final PlaybackMode Function() mode;

  /// Whether playlist frame [playlistFrame]'s picture is there to show — or
  /// null when nothing is making the run's pictures, and so nothing would
  /// ever say one had come.
  final bool? Function(int playlistFrame) pictureIsThere;

  /// Whether everything ahead of the playhead is made — or no more fits, and
  /// what is held is the window.
  final bool Function() aheadIsFilled;

  /// Rendering first: true from where a run is put — or reaches a frame
  /// that is not there — until [aheadIsFilled].
  bool _filling = false;

  /// Whether the clock must wait for [playlistFrame]. [placed] when someone
  /// PUT the run on the frame — play was pressed there, the ruler was
  /// dragged there — rather than its clock reaching it: rendering first, a
  /// run fills before it goes from wherever it was put.
  bool holds(int playlistFrame, {required bool placed}) {
    final mode = this.mode();
    final there = mode == PlaybackMode.skipFrames
        ? null
        : pictureIsThere(playlistFrame);
    if (there == null || mode != PlaybackMode.renderFirst) {
      // The fill is render-first's alone: a mode picked under a run starts
      // from nothing, whatever was being filled when it was last left.
      _filling = false;
      // Skipping frames never waits — and a run nobody makes pictures for
      // would wait for good.
      return there != null && !there;
    }
    if (placed || !there) {
      _filling = true;
    } else if (_filling && aheadIsFilled()) {
      _filling = false;
    }
    return _filling;
  }

  /// Whether a run behind its clock — the app was longer than a frame —
  /// shows the next picture all the same, its clock and its sound put back
  /// to it, rather than go over the pictures it is late for (`playheadWay`).
  ///
  /// 🗣️유저 2026-10-15 (F-364-Q1 b): 「하나도 안 건너뛴다 — 소리를 그림에 다시
  /// 맞춘다」 — every picture, however late the app, and the sound put back
  /// as where a picture that is not there yet is waited for. Skipping frames
  /// keeps time. ⚠️Rendering first is not decided yet (board
  /// F-364-every-picture-even-when-late-Q1 — the media viewer plays by it
  /// too), and keeps time until it is.
  bool showsEveryPicture() => mode() == PlaybackMode.everyPicture;
}
