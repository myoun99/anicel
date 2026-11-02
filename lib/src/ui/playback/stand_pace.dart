import 'dart:async';
import 'dart:ui' show VoidCallback;

import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../gpu_fences.dart';

/// 🚨★★ONE FRAME AS IT STANDS ON ITS WAY AT A TIME, as one step of a stroke is
/// (`_stepOnItsWay`, F-512; card a-dragged-opacity-slider-lags-at-rest): each
/// value of a drag was composed as it came, two frames of the whole stack
/// stood in line on the raster thread, and the value let go of came after
/// them. What a view is handed while the raster thread is on the last one
/// waits ([waits]), and only the newest stands once it is past. 🔬Surface
/// Pro 11, profile, S5_BA cut 353, every row on, an opacity dragged 30 steps
/// at 16 ms and let go, with a canvas's frame as it stands keeping what it
/// draws whole (`FramePictures.frameAsItStands`): a row in the blurred folder,
/// the longest a frame waited 1.4–1.8 → 0.60–0.86 s, let go to its picture
/// 1.3–1.6 → 0.67–2.0 s (mostly 1.0); a row beside the folders, the longest
/// a frame waited 0.30–0.41 → 0.27–0.31 s, let go to its picture as it was.
///
/// Told by the fence ([rasterThreadBehind]) and only once it has come: a
/// frame a fence has said nothing of goes out as it was handed.
final class StandPace {
  StandPace({
    Future<void> Function() behind = rasterThreadBehind,
    int Function()? nowMicros,
  }) : _behind = behind,
       _now = nowMicros ?? _stopwatch();

  final Future<void> Function() _behind;
  final int Function() _now;

  /// ⚖️What a frame may take the raster thread and leave the next one
  /// unwaited for: two on their way behind each other, under this, are gone
  /// before anyone is left waiting for them.
  static const int _lagsFromMicros = 33000;

  bool _onItsWay = false;
  bool _lags = false;

  /// Whether a frame handed now waits for the one on its way.
  bool get waits => _onItsWay && _lags;

  /// A frame as it stands goes out with this frame: [past] is called once
  /// the raster thread is past it. ⛔Not asked at the paint: a fence laid
  /// there goes ahead of the frame it is to stand behind.
  void stood(VoidCallback past) {
    if (_onItsWay) {
      return;
    }
    _onItsWay = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final from = _now();
      // ⛔No frame waits for a fence that failed: it said nothing.
      unawaited(
        _behind().then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
          _lags = _now() - from >= _lagsFromMicros;
          _onItsWay = false;
          past();
        }),
      );
    });
  }

  static int Function() _stopwatch() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds;
  }
}
