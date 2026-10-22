import 'dart:math' as math;

import '../models/canvas_point.dart';
import 'input/pen_readings.dart';
import 'stroke_corners.dart';

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
/// The readings come behind the pen with the line, by the same share: a
/// line a lag behind carries what the pen read a lag ago, so a pen that
/// presses harder thickens the line where the line is, not ahead of it
/// (F-418, the plan put to the user with Q1–Q3).
///
/// ↩️It was a pull string (P7, 2026-07-11, mine): a rope of fixed screen
/// pixels the pen dragged the brush on, which never moved while the pen was
/// within a rope of it, and a line that ended where the brush stood (H45).
///
/// A brush that keeps its corners (角をとがらせる, [StrokeCorners]) takes the
/// way through each corner the pen turned that the line has yet to reach,
/// and closes the same share of that way — with none, the way is straight
/// for the pen, as above.
///
/// Times are the PEN's: a sample's [follow] carries the event's time, and
/// a frame's [lookAtFrame] is counted from the first frame after the last
/// sample — the two clocks are never compared.
///
/// Each move answers the way the line went: every corner it went through,
/// and then where it got to.
class StrokeStabilizer {
  StrokeStabilizer({
    required this.lagAt,
    required PenPoint start,
    required Duration at,
    bool keepsCorners = false,
  }) : _brush = start,
       _pen = start,
       _brushAt = at,
       _sampleAt = at,
       _corners = keepsCorners ? (StrokeCorners()..add(start)) : null;

  /// How far behind the pen the line runs while the pen moves at a speed
  /// (normalised, as the pen's readings carry it) — the time it takes to
  /// close all but 1/e of the distance left. Clip Studio's 速度による手ブレ
  /// 補正 bends it by the speed; without it, it is one time.
  final Duration Function(double speed) lagAt;

  /// Closer than this, in canvas pixels, the line is where the pen is.
  static const double _settlesWithin = 0.01;

  PenPoint _brush;
  PenPoint _pen;

  /// The pen's corners, for a brush that keeps them — and those the line
  /// has yet to go through, in order.
  final StrokeCorners? _corners;
  final List<PenPoint> _ahead = [];

  /// The pen time the brush stands at.
  Duration _brushAt;

  /// The pen time of the latest sample, and the frame that first looked
  /// after it — or null while no frame has.
  Duration _sampleAt;
  Duration? _firstFrameAfterSample;

  /// Where the line has got to, and what it reads there.
  PenPoint get brush => _brush;

  /// The line has reached the pen and nothing moves it until the pen does.
  bool get settled => _brush == _pen;

  /// The pen at [pen], reading [readings], at its time [at]; the brush
  /// closes on it for the time since it last moved.
  List<PenPoint> follow(
    CanvasPoint pen,
    PenReadings readings, {
    required Duration at,
  }) {
    _pen = (position: pen, readings: readings);
    _goThrough(_corners?.add(_pen) ?? const []);
    _sampleAt = at;
    _firstFrameAfterSample = null;
    return [..._closeTo(at), _brush];
  }

  /// A frame at [frameAt] on the frame clock: the brush keeps closing on
  /// the pen while it rests. Answers nothing when this frame moved it
  /// nowhere — the first frame after a sample only marks where the pen's
  /// time stands on the frame clock.
  List<PenPoint> lookAtFrame(Duration frameAt) {
    if (settled) {
      return const [];
    }
    final firstFrame = _firstFrameAfterSample;
    if (firstFrame == null) {
      _firstFrameAfterSample = frameAt;
      return const [];
    }
    final before = _brush;
    final through = _closeTo(_sampleAt + (frameAt - firstFrame));
    return _brush == before ? const [] : [...through, _brush];
  }

  /// The pen lifted: the line goes straight to where it was, reading what
  /// it read there — through the corners it had yet to reach. Answers
  /// nothing when the line was already there.
  List<PenPoint> finish() {
    _goThrough(_corners?.end() ?? const []);
    if (settled) {
      return const [];
    }
    final way = [..._ahead, _pen];
    _ahead.clear();
    _brush = _pen;
    return way;
  }

  /// The line will go through [corners] — those it has not already cut
  /// past: a corner known only once the pen is on past it can be behind a
  /// line that runs close behind the pen.
  void _goThrough(List<StrokeCorner> corners) {
    for (final (at: _, :point) in corners) {
      if (_brush.position.distanceTo(_pen.position) >
          point.position.distanceTo(_pen.position)) {
        _ahead.add(point);
      }
    }
  }

  /// Closes the share of the way left that the time to [at] closes;
  /// answers the corners the line went through on it.
  List<PenPoint> _closeTo(Duration at) {
    final elapsed = at - _brushAt;
    if (elapsed <= Duration.zero) {
      return const [];
    }
    _brushAt = at;
    final lag = lagAt(_pen.readings.speed);
    final share =
        1 - math.exp(-elapsed.inMicroseconds / lag.inMicroseconds);
    if (_ahead.isEmpty) {
      _moveTo(_brush, _pen, share);
      return const [];
    }
    var go = share * _wayLeft();
    final through = <PenPoint>[];
    var from = _brush;
    while (_ahead.isNotEmpty &&
        from.position.distanceTo(_ahead.first.position) <= go) {
      go -= from.position.distanceTo(_ahead.first.position);
      from = _ahead.removeAt(0);
      through.add(from);
    }
    final to = _ahead.isEmpty ? _pen : _ahead.first;
    final leg = from.position.distanceTo(to.position);
    _moveTo(from, to, leg == 0 ? 1.0 : math.min(1.0, go / leg));
    return through;
  }

  /// The length of the way from the brush through the corners ahead to the
  /// pen.
  double _wayLeft() {
    var way = 0.0;
    var from = _brush.position;
    for (final point in [..._ahead, _pen]) {
      way += from.distanceTo(point.position);
      from = point.position;
    }
    return way;
  }

  /// The brush [share] of the way from [from] to [to] — on the pen, once
  /// it is that close to it with nothing left to go through.
  void _moveTo(PenPoint from, PenPoint to, double share) {
    final position = CanvasPoint.lerp(from.position, to.position, share);
    _brush =
        _ahead.isEmpty && position.distanceTo(_pen.position) < _settlesWithin
        ? _pen
        : (
            position: position,
            readings: readingsBetween(from.readings, to.readings, share),
          );
  }
}
