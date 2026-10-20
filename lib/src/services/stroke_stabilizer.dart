import 'dart:math' as math;

import '../models/canvas_point.dart';

/// Clip Studio's 손떨림 보정 (手ブレ補正): the line runs a little behind the
/// pen and closes the same share of the distance left in the same time —
/// so it keeps going while the pen rests, and jitter quicker than the lag
/// never reaches it.
///
/// 🗣️Straight for the pen, not along the way it came (유저 2026-10-20,
/// F-418-Q4 「곧장 커서로 간다 — 꺾임을 가로지른다」): a corner the pen
/// turned is cut across, as Clip Studio cuts it.
///
/// 🗣️The pen lifts and the line goes to where it lifted (F-418-Q2 「클튜는
/// 100으로 하면 선을 떼면 바로 뗀 자리까지 선이 감」) — [finish].
///
/// ↩️It was a pull string (P7, 2026-07-11, mine): a rope of fixed screen
/// pixels the pen dragged the brush on, which never moved while the pen was
/// within a rope of it, and a line that ended where the brush stood (H45).
///
/// Times are the PEN's: a sample's [follow] carries the event's time, and
/// a frame's [lookAtFrame] is counted from the first frame after the last
/// sample — the two clocks are never compared.
class StrokeStabilizer {
  StrokeStabilizer({
    required this.lag,
    required CanvasPoint start,
    required Duration at,
  }) : _brush = start,
       _pen = start,
       _brushAt = at,
       _sampleAt = at;

  /// How far behind the pen the line runs — the time it takes to close all
  /// but 1/e of the distance left.
  final Duration lag;

  /// Closer than this, in canvas pixels, the line is where the pen is.
  static const double _settlesWithin = 0.01;

  CanvasPoint _brush;
  CanvasPoint _pen;

  /// The pen time the brush stands at.
  Duration _brushAt;

  /// The pen time of the latest sample, and the frame that first looked
  /// after it — or null while no frame has.
  Duration _sampleAt;
  Duration? _firstFrameAfterSample;

  /// Where the line has got to.
  CanvasPoint get position => _brush;

  /// The line has reached the pen and nothing moves it until the pen does.
  bool get settled => _brush == _pen;

  /// The pen at [pen] at its time [at]; the brush closes on it for the time
  /// since it last moved. Answers where the brush is.
  CanvasPoint follow(CanvasPoint pen, {required Duration at}) {
    _pen = pen;
    _sampleAt = at;
    _firstFrameAfterSample = null;
    _closeTo(at);
    return _brush;
  }

  /// A frame at [frameAt] on the frame clock: the brush keeps closing on
  /// the pen while it rests. Answers where the brush moved to, or null when
  /// this frame moved it nowhere — the first frame after a sample only
  /// marks where the pen's time stands on the frame clock.
  CanvasPoint? lookAtFrame(Duration frameAt) {
    if (settled) {
      return null;
    }
    final firstFrame = _firstFrameAfterSample;
    if (firstFrame == null) {
      _firstFrameAfterSample = frameAt;
      return null;
    }
    final before = _brush;
    _closeTo(_sampleAt + (frameAt - firstFrame));
    return _brush == before ? null : _brush;
  }

  /// The pen lifted: the line goes straight to where it was. Answers that
  /// point, or null when the line was already there.
  CanvasPoint? finish() {
    if (settled) {
      return null;
    }
    return _brush = _pen;
  }

  void _closeTo(Duration at) {
    final elapsed = at - _brushAt;
    if (elapsed <= Duration.zero) {
      return;
    }
    _brushAt = at;
    final share =
        1 - math.exp(-elapsed.inMicroseconds / lag.inMicroseconds);
    _brush = CanvasPoint.lerp(_brush, _pen, share);
    if (_brush.distanceTo(_pen) < _settlesWithin) {
      _brush = _pen;
    }
  }
}
