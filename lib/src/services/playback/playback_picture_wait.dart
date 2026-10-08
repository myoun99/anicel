import '../../models/playback_mode.dart';

/// Whether a run's clock stands on a frame: [PlaybackMode]'s three settings,
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

  /// Whether the clock must wait on [playlistFrame]. [placed] when someone
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
}
