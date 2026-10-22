import 'dart:math' as math;

import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../models/brush_dab.dart';
import '../models/canvas_point.dart';
import '../models/drawing_guide.dart';
import 'guide_geometry.dart';

/// How far a stroke must travel, in SCREEN pixels, before its ray lock
/// commits to a ray.
///
/// The first sample or two of a stroke point almost nowhere — pen jitter is
/// the same size as the travel — and picking a ray from that noise would
/// have the stroke jump families on nearly-identical gestures. A short wait
/// makes the choice stable. It is divided by zoom at stroke start, the same
/// way the stabilizer freezes its rope length, so the feel does not change
/// with magnification.
const double kRayLockTravel = 6.0;

/// Locks a stroke onto ONE ray of its candidates and holds it there — a
/// perspective guide's ([RayLock.ofGuides]), or one of the eight ways Shift
/// holds a stroke to ([RayLock.eightWays]).
///
/// The ray is chosen once, shortly after the stroke starts, and never
/// revisited: projecting each point onto whichever ray is nearest right now
/// would have the stroke hop between families mid-line.
///
/// Deciding needs travel the stroke has not made yet, so early points are
/// HELD and released the moment the ray is known — the pipeline draws
/// nothing until then. Drawing them unsnapped first and correcting after
/// would put a wrong frame on screen, and a visible frame that has to be
/// taken back is exactly what this project does not do. The wait is a few
/// pointer samples, and the stroke origin is on the ray by construction, so
/// the released run starts flush with the pen-down point.
///
/// ★THE SESSION LIVES ON THE CANVAS. The guides are the canvas's, the
/// travel that locks is travel the user sees, and the ray is a ray of the
/// picture — so a stroke drawn in a posed row's artwork ([space]) hands its
/// points OUT through the row's placement and takes the snapped ones back
/// ([GuideSpace] has what measuring in the artwork got wrong).
class RayLock {
  RayLock._(
    this._candidates,
    this._start,
    this._lockTravel,
    this._space,
  );

  /// A lock onto the rays of [guides], or null when nothing is snapping —
  /// callers skip the whole mechanism then and the stroke path is
  /// untouched.
  ///
  /// [start], and every point fed and handed back after it, is in the
  /// stroke's own [space].
  static RayLock? ofGuides({
    required CutGuides guides,
    required CanvasPoint start,
    required double zoom,
    GuideSpace space = GuideSpace.canvas,
  }) {
    final snapping = guides.snappingPerspectives.toList();
    if (snapping.isEmpty) return null;
    return _onto(
      (onCanvas) => snapCandidatesAt(snapping, onCanvas),
      start: start,
      zoom: zoom,
      space: space,
    );
  }

  /// A lock onto the nearest of the EIGHT WAYS from [start] — across, down
  /// and the two diagonals of the canvas, 45° apart (I-61-Q1: 「Shift 는
  /// 45° 잠금」; 유저 09-14: 「45도로 스냅하면 결과적으로 수직수평 구현되니
  /// 로직 단순화」). Four lines: a line has no forward, so each is two ways
  /// ([chooseSnapCandidate]).
  static RayLock eightWays({
    required CanvasPoint start,
    required double zoom,
    GuideSpace space = GuideSpace.canvas,
  }) => _onto(
    (onCanvas) => [
      for (final (dx, dy) in const [
        (1.0, 0.0),
        (math.sqrt1_2, math.sqrt1_2),
        (0.0, 1.0),
        (-math.sqrt1_2, math.sqrt1_2),
      ])
        SnapCandidate(origin: onCanvas, dx: dx, dy: dy),
    ],
    start: start,
    zoom: zoom,
    space: space,
  )!;

  /// A lock already on [ray] — a ray of the CANVAS — from the first point
  /// it is fed: what a stroke drawn under the line Shift holds takes
  /// ([ShiftLine]).
  factory RayLock.along(
    SnapCandidate ray, {
    GuideSpace space = GuideSpace.canvas,
  }) => RayLock._([ray], ray.origin, 0, space).._locked = ray;

  static RayLock? _onto(
    List<SnapCandidate> Function(CanvasPoint onCanvas) candidatesAt, {
    required CanvasPoint start,
    required double zoom,
    required GuideSpace space,
  }) {
    final onCanvas = space.isCanvas ? start : space.toCanvas.apply(start);
    final candidates = candidatesAt(onCanvas);
    if (candidates.isEmpty) return null;
    final lockTravel = zoom > 0 ? kRayLockTravel / zoom : kRayLockTravel;
    return RayLock._(candidates, onCanvas, lockTravel, space);
  }

  final List<SnapCandidate> _candidates;

  /// Where the stroke started, on the canvas.
  final CanvasPoint _start;
  final double _lockTravel;
  final GuideSpace _space;

  /// The points held while the ray is undecided, on the canvas.
  final List<CanvasPoint> _held = <CanvasPoint>[];
  SnapCandidate? _locked;

  /// The ray this stroke settled on — a ray of the CANVAS — or null while
  /// it is still undecided.
  SnapCandidate? get lockedRay => _locked;

  /// Feeds one stabilized point; returns the points the stroke should now
  /// advance through, in order. Empty while the ray is still being decided.
  List<CanvasPoint> follow(CanvasPoint point) {
    final onCanvas = _space.isCanvas ? point : _space.toCanvas.apply(point);
    final locked = _locked;
    if (locked != null) {
      return _inTheStrokesSpace([locked.project(onCanvas)]);
    }
    _held.add(onCanvas);
    final dx = onCanvas.x - _start.x;
    final dy = onCanvas.y - _start.y;
    if (dx * dx + dy * dy < _lockTravel * _lockTravel) {
      return const [];
    }
    return _inTheStrokesSpace(_lockOnto(dx, dy));
  }

  /// Pen-up: settles on a ray even if the stroke never travelled far enough,
  /// so a short flick still draws instead of vanishing.
  List<CanvasPoint> finish() {
    if (_locked != null || _held.isEmpty) {
      return const [];
    }
    final last = _held.last;
    return _inTheStrokesSpace(
      _lockOnto(last.x - _start.x, last.y - _start.y),
    );
  }

  List<CanvasPoint> _inTheStrokesSpace(List<CanvasPoint> onCanvas) =>
      _space.isCanvas
      ? onCanvas
      : [for (final point in onCanvas) _space.toStroke.apply(point)];

  List<CanvasPoint> _lockOnto(double dx, double dy) {
    // A stroke that has not moved at all names no direction; keep holding
    // rather than locking onto an arbitrary ray.
    if (dx == 0 && dy == 0) return const [];
    final chosen = chooseSnapCandidate(_candidates, dx: dx, dy: dy);
    if (chosen == null) {
      final released = List<CanvasPoint>.of(_held);
      _held.clear();
      return released;
    }
    _locked = chosen;
    final released = [for (final point in _held) chosen.project(point)];
    _held.clear();
    return released;
  }
}

/// THE STROKE'S LOCK, A STRETCH AT A TIME: the rays of its guides — or,
/// while Shift is held, the eight ways ([RayLock.eightWays]).
///
/// 🗣️I-61-Q2 (유저 2026-10-08): 「누르고 있는 동안만 — 누른 그 자리에서부터
/// 잠긴다」 — held before the stroke, it locks from the start; pressed in
/// the middle, from where the stroke has got to; let go, the stroke goes on
/// free from there; and as often as it is pressed in one stroke. So a
/// stretch begins at the press and at every change of Shift, where the
/// stroke stands then, and its lock is made there — the points the last
/// one still held let go of first.
///
/// ⚠️FREE IS AS THE GUIDES HAVE IT: let go of Shift, a stroke drawn with a
/// snapping perspective goes on along a ray of that, chosen afresh where it
/// was let go. Mine (유저 09-14: 「로직은 맡기니 단순화」) — Shift wins while
/// it is held, and nothing else changes.
///
/// The guides, the zoom and the [space] are the stroke's, read once at its
/// start: an edit landing mid-stroke changes no stretch of it.
///
/// ★[line] is what Shift held past the stroke before this one (I-121,
/// [ShiftLine]): a stretch under Shift goes on along it, and the line it
/// locks onto is kept there for the next. A stroke with none of its own
/// keeps one for itself alone — what every stroke did before I-121.
class StrokeLock {
  StrokeLock({
    required CutGuides guides,
    required CanvasPoint start,
    required double zoom,
    GuideSpace space = GuideSpace.canvas,
    ShiftLine? line,
  }) : _guides = guides,
       _zoom = zoom,
       _space = space,
       _line = line ?? ShiftLine(),
       _end = start,
       _lock = RayLock.ofGuides(
         guides: guides,
         start: start,
         zoom: zoom,
         space: space,
       );

  final CutGuides _guides;
  final double _zoom;
  final GuideSpace _space;
  final ShiftLine _line;

  /// The lock of the stretch under way — null where it is free.
  RayLock? _lock;

  /// Whether Shift was held for the stretch under way.
  bool _shift = false;

  /// Where the stroke stands: the last point handed out, or its start.
  CanvasPoint _end;

  /// Feeds one stabilized point, with whether Shift is held now; returns
  /// the points the stroke should advance through, in order.
  ///
  /// ★Asked at EVERY point, as the shape tool asks Shift of every move
  /// (`_shapeKeepsRatioNow`): held before the press and pressed during the
  /// drag are one question.
  List<CanvasPoint> follow(CanvasPoint point, {required bool shift}) {
    final out = <CanvasPoint>[];
    if (shift != _shift) {
      out.addAll(_handOut(_lock?.finish() ?? const []));
    }
    _line.heldNow(shift);
    if (shift != _shift) {
      _shift = shift;
      final held = _line._ray;
      _lock = !shift
          ? RayLock.ofGuides(
              guides: _guides,
              start: _end,
              zoom: _zoom,
              space: _space,
            )
          : held != null
          ? RayLock.along(held, space: _space)
          : RayLock.eightWays(start: _end, zoom: _zoom, space: _space);
    }
    final lock = _lock;
    out.addAll(_handOut(lock == null ? [point] : lock.follow(point)));
    return out;
  }

  /// Pen-up: what the stretch under way still holds, settled
  /// ([RayLock.finish]).
  List<CanvasPoint> finish() => _handOut(_lock?.finish() ?? const []);

  /// [points] handed out — the stroke now stands at the last — and the
  /// line a stretch under Shift locked onto kept for the next stroke.
  List<CanvasPoint> _handOut(List<CanvasPoint> points) {
    if (points.isNotEmpty) {
      _end = points.last;
    }
    if (_shift) {
      _line._ray ??= _lock?.lockedRay;
    }
    return points;
  }
}

/// THE LINE SHIFT HOLDS — the ray a stretch under Shift locked onto, kept
/// past its stroke for as long as Shift stays held, so the next stroke
/// drawn under the same hold goes on along it from its press ([onTheLine],
/// [StrokeLock]). A ray of the CANVAS, as every lock's is.
///
/// 🗣️I-121 (유저 2026-10-21): 「스냅 발생하면 쉬프트 떼기 전까지는 같은스냅.
/// 즉 스트로크로 라인 그리다가 스트로크만 떼고 다음 포인트에서 같은 라인의
/// 직선을 그릴 수 있게되는거지. 그걸 기본으로.」
///
/// ⚠️THE HOLD ENDS WHERE ITS OWNER HEARS IT END, between strokes too: a
/// press, and a finger holding Shift lifting, say whether Shift is held
/// now ([heldNow]); a Shift pressed anew says the hold before it ended
/// ([heardKey]). ⛔Not the key's release: on Windows a pen hovering lets
/// Shift go in the engine's record with the key still down, and the real
/// release after it is never heard (I-61, `ModifierKeys`) — so "held now"
/// is asked of `ModifierKeys`, and a release is known by the press after it.
final class ShiftLine {
  SnapCandidate? _ray;

  /// Shift as it stands now — let go, the line goes with it.
  void heldNow(bool shift) {
    if (!shift) {
      _ray = null;
    }
  }

  /// A key [event] as the keyboard hears it (`HardwareKeyboard.addHandler`):
  /// a Shift pressed anew lets go of the line the hold before it kept.
  /// Always false — the key goes on to its other readers.
  ///
  /// ⚠️Not a synthesized press: the Windows engine puts Shift back down of
  /// its own when a mouse move carries it after a pen let it go (I-61) —
  /// the same hold.
  bool heardKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        !event.synthesized &&
        (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
            event.logicalKey == LogicalKeyboardKey.shiftRight)) {
      _ray = null;
    }
    return false;
  }

  /// [point] — a press, in a stroke's [space] — on the line held, or as
  /// it is when none is.
  CanvasPoint onTheLine(
    CanvasPoint point, {
    GuideSpace space = GuideSpace.canvas,
  }) {
    final ray = _ray;
    return ray == null
        ? point
        : RayLock.along(ray, space: space).follow(point).single;
  }
}

/// Every dab of [dabs] repeated through [transforms], the original run
/// first, renumbered into one continuous sequence starting at
/// [firstSequence].
///
/// Replication happens on DABS rather than on pen samples so interpolation,
/// spacing and the pressure dynamics are computed once. The transforms are
/// rigid ON THE CANVAS, so distances — and therefore spacing — survive them
/// exactly where the stroke is seen ([symmetryCopiesIn]).
///
/// With a single identity transform the result is the input, sequence
/// numbers included: a cut with no acting symmetry runs the code path it
/// always did.
List<BrushDab> replicateDabs(
  List<BrushDab> dabs,
  List<GuideTransform> transforms, {
  required int firstSequence,
}) {
  if (dabs.isEmpty) return dabs;
  if (transforms.length <= 1) {
    return dabs;
  }
  final replicated = <BrushDab>[];
  for (var copy = 0; copy < transforms.length; copy += 1) {
    final transform = transforms[copy];
    final base = firstSequence + copy * dabs.length;
    for (var index = 0; index < dabs.length; index += 1) {
      final dab = dabs[index];
      replicated.add(
        transform.isIdentity
            ? dab.copyWith(sequence: base + index)
            : dab.copyWith(
                center: transform.apply(dab.center),
                // The tip turns with the copy. Reading the angle back out of
                // the mapped axis covers rotations and reflections with one
                // rule instead of a sign case for each.
                angleDegrees: transform.mapTipAngleDegrees(dab.angleDegrees),
                sequence: base + index,
              ),
      );
    }
  }
  return replicated;
}
