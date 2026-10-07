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

  /// Rendering first: true from where a run begins — or reaches a frame
  /// that is not there — until [aheadIsFilled].
  bool _filling = false;

  /// A run begins: rendering first, it fills before it goes.
  void runBegins() => _filling = true;

  /// Whether the clock must wait on [playlistFrame].
  bool holds(int playlistFrame) {
    final mode = this.mode();
    if (mode == PlaybackMode.skipFrames) {
      return false;
    }
    final there = pictureIsThere(playlistFrame);
    if (there == null) {
      // A run nobody makes pictures for would wait for good.
      return false;
    }
    if (mode == PlaybackMode.everyPicture) {
      return !there;
    }
    if (!there) {
      _filling = true;
    } else if (_filling && aheadIsFilled()) {
      _filling = false;
    }
    return _filling;
  }
}
