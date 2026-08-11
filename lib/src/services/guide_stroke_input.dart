import '../models/brush_dab.dart';
import '../models/canvas_point.dart';
import '../models/drawing_guide.dart';
import 'guide_geometry.dart';

/// How far a stroke must travel, in SCREEN pixels, before the perspective
/// snap commits to a ray.
///
/// The first sample or two of a stroke point almost nowhere — pen jitter is
/// the same size as the travel — and picking a ray from that noise would
/// have the stroke jump families on nearly-identical gestures. A short wait
/// makes the choice stable. It is divided by zoom at stroke start, the same
/// way the stabilizer freezes its rope length, so the feel does not change
/// with magnification.
const double kPerspectiveSnapLockTravel = 6.0;

/// Locks a stroke onto ONE perspective ray and holds it there.
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
class PerspectiveSnapSession {
  PerspectiveSnapSession._(this._candidates, this._start, this._lockTravel);

  /// A session for [guides], or null when nothing is snapping — callers
  /// skip the whole mechanism then and the stroke path is untouched.
  static PerspectiveSnapSession? maybeStart({
    required CutGuides guides,
    required CanvasPoint start,
    required double zoom,
  }) {
    final snapping = guides.snappingPerspectives.toList();
    if (snapping.isEmpty) return null;
    final candidates = snapCandidatesAt(snapping, start);
    if (candidates.isEmpty) return null;
    final lockTravel = zoom > 0
        ? kPerspectiveSnapLockTravel / zoom
        : kPerspectiveSnapLockTravel;
    return PerspectiveSnapSession._(candidates, start, lockTravel);
  }

  final List<SnapCandidate> _candidates;
  final CanvasPoint _start;
  final double _lockTravel;

  final List<CanvasPoint> _held = <CanvasPoint>[];
  SnapCandidate? _locked;

  /// The ray this stroke settled on, or null while it is still undecided.
  SnapCandidate? get lockedRay => _locked;

  /// Feeds one stabilized point; returns the points the stroke should now
  /// advance through, in order. Empty while the ray is still being decided.
  List<CanvasPoint> follow(CanvasPoint point) {
    final locked = _locked;
    if (locked != null) {
      return [locked.project(point)];
    }
    _held.add(point);
    final dx = point.x - _start.x;
    final dy = point.y - _start.y;
    if (dx * dx + dy * dy < _lockTravel * _lockTravel) {
      return const [];
    }
    return _lockOnto(dx, dy);
  }

  /// Pen-up: settles on a ray even if the stroke never travelled far enough,
  /// so a short flick still draws instead of vanishing.
  List<CanvasPoint> finish() {
    if (_locked != null || _held.isEmpty) {
      return const [];
    }
    final last = _held.last;
    return _lockOnto(last.x - _start.x, last.y - _start.y);
  }

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

/// Every dab of [dabs] repeated through [transforms], the original run
/// first, renumbered into one continuous sequence starting at
/// [firstSequence].
///
/// Replication happens on DABS rather than on pen samples so interpolation,
/// spacing and the pressure dynamics are computed once. The transforms are
/// rigid, so distances — and therefore spacing — survive them exactly.
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
