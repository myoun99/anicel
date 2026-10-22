import '../../models/playback_mode.dart';

/// Whether a run's clock waits for a frame — for its picture, by
/// [PlaybackMode]'s three settings read against what the warmer has made,
/// or for its sound ([soundIsComing]) under every one — and whether a run
/// behind its clock shows every picture all the same.
///
/// The one place the modes part. Everything else — which pictures are made,
/// in what order, how many are kept — is the same under each.
///
/// 🚨ONE LAW, ONE CODE for every surface that runs — the canvas's run and
/// the media viewer's (viewer-plays-by-the-one-playback-law), its sound
/// with it (playback-waits-for-its-sound). ↩️It was the picture's wait
/// alone (`PlaybackPictureWait`), and a run whose sound was not ready
/// played on without it.
class PlaybackWait {
  PlaybackWait({
    required this.mode,
    required this.pictureIsThere,
    required this.aheadIsFilled,
    required this.soundIsComing,
  });

  final PlaybackMode Function() mode;

  /// Whether the run's sound is on its way — its output being opened, a
  /// source being made ready (`OutputComing`) — and the run waits for it
  /// where it stands.
  ///
  /// 🗣️유저 2026-10-16 (se-fallback-opens-the-original-path-Q2): 「대체
  /// 재생을 안 쓰고, 소리가 준비될 때까지 기다린다」 — under every mode:
  /// skipping frames keeps time with the sound, and has none to keep before
  /// it comes.
  final bool Function() soundIsComing;

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

  /// Whether the clock must wait for [playlistFrame]: its picture, or the
  /// run's sound ([soundIsComing]). [placed] when someone PUT the run on the
  /// frame — play was pressed there, the ruler was dragged there — rather
  /// than its clock reaching it: rendering first, a run fills before it goes
  /// from wherever it was put.
  bool holds(int playlistFrame, {required bool placed}) =>
      // The picture first, always: its fill counts every ask.
      _pictureHolds(playlistFrame, placed: placed) || soundIsComing();

  bool _pictureHolds(int playlistFrame, {required bool placed}) {
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
  /// to it, rather than go over the pictures it is late for (`playheadWay`,
  /// `BehindItsClock`): every mode that waits for its pictures does, and
  /// skipping frames alone keeps time.
  ///
  /// 🗣️유저 2026-10-15 (F-364-Q1 b): 「하나도 안 건너뛴다 — 소리를 그림에 다시
  /// 맞춘다」 — every picture, however late the app, and the sound put back
  /// as where a picture that is not there yet is waited for. 10-16
  /// (F-364-every-picture-even-when-late-Q1 a): 「재생 전 굽기도 안
  /// 건너뛴다(뷰어도)」 — rendering first as well, and with it the media
  /// viewer, which plays by it. ↩️Rendering first kept time until it was
  /// decided.
  bool showsEveryPicture() => mode() != PlaybackMode.skipFrames;
}
