import 'measurement_mode.dart';

/// 🔬THE PLAYBACK WARMER'S PACE: how long each frame's picture took to make,
/// from the ask to its landing (`PlaybackPrerenderScheduler`), and how many
/// it made in all. The frame statistics read these (`FrameStats`, Settings ▸
/// Debug), and nothing is counted while they are off.
///
/// 🗣️H74, 유저 2026-11-24 on a Galaxy Tab (card
/// cut-346-plays-with-frames-missing-on-the-galaxy-tab): 「컷 346 재생시
/// 모든프레임이 로드안됨. 재생하면서 일부만 로드 … bg에 트랜스폼 건거 비지블
/// on하면 그런데, 이런 fx가 아직 무거운듯」 — a run that falls behind its
/// pictures does so for room (the BUDGET line, the census's frame pictures)
/// or for pace: a picture made slower than a frame lasts. This is the pace.
abstract final class WarmSteps {
  /// How many pictures' times [madeMicros] keeps: a few seconds of a run's.
  static const int picturesKept = 120;

  /// The pictures counted in all.
  static int get picturesCounted => _picturesCounted;
  static int _picturesCounted = 0;

  /// How long each of the newest pictures took, from the ask to its
  /// landing, in microseconds, oldest first.
  static List<int> get madeMicros => List.unmodifiable(_made);
  static final List<int> _made = [];

  /// A picture landed, [micros] after it was asked for.
  static void made(int micros) {
    if (!MeasurementMode.frameStats.value) {
      return;
    }
    _picturesCounted += 1;
    _made.add(micros);
    if (_made.length > picturesKept) {
      _made.removeAt(0);
    }
  }

  /// No picture counted yet: what was counted while the statistics were
  /// last up says nothing of now.
  static void forget() {
    _picturesCounted = 0;
    _made.clear();
  }
}
