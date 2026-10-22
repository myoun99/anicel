import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../core/turn_trig.dart';
import 'canvas_point.dart';

/// After Effects' four names for how a path passes through a key — the
/// key window's 「경로」 row (anchor-walks-a-path-Q4, 유저 10-21: 「네 칸 —
/// AE 이름 그대로」), in AE's order.
enum KeyPathKind {
  /// AE's Linear — a corner ([KeyPath.straight]).
  linear('Linear'),

  /// AE's Bezier — a handle on each side, each its own way ([SplitPath]).
  bezier('Bezier'),

  /// AE's Continuous Bezier — the two handles in one line ([JoinedPath]).
  continuousBezier('Continuous Bezier'),

  /// AE's Auto Bezier — laid by the keys either side ([KeyPath.auto]).
  autoBezier('Auto Bezier');

  const KeyPathKind(this.label);

  /// The kind's English name; every other language's is the string
  /// tables' (I-4's contract — `labelFor` in `model_vocabulary.dart`).
  final String label;
}

/// How a lane's PATH passes through a key in space (I-89 ④) — beside how
/// fast it travels there ([KeySide]), After Effects' spatial
/// interpolation.
///
/// A key new on such a lane is smooth through the key as its neighbours
/// lay it, AE's auto bezier (I-89-Q10 B — the one write is
/// `pathLaneKeyed`); the key window makes it any of AE's four ([turned]),
/// and a handle pulled on the canvas then stays where it was left
/// (`keyPathPulled`). ↩️A key was a corner by default — a pan runs
/// straight — the key window making it a curve.
///
/// ⚠️Only the keys of a Position or an Anchor Point lane walk a path
/// (`walksAPath`); every other key is [straight] and is never offered
/// another.
sealed class KeyPath {
  const KeyPath();

  /// A corner: the path arrives and leaves along straight lines.
  static const KeyPath straight = StraightPath._();

  /// Smooth through the key, its handle laid by the keys either side of it
  /// — and laid again whenever they move.
  static const KeyPath auto = AutoPath._();

  /// Whether the path bends through the key.
  bool get curved;

  /// Which of After Effects' four it is.
  KeyPathKind get kind;

  /// How far, and which way, its handle reaches out of a key standing [at]
  /// — [ahead], towards the key after it, or behind, towards the key
  /// before — the key [before] it and the one [after] it standing where
  /// they do, null at an end:
  ///
  /// - a corner ([straight]) has none;
  /// - handles the hand placed reach as it left them: a joined pair
  ///   ([JoinedPath]) along its one line, a split pair ([SplitPath]) each its
  ///   own way;
  /// - an auto key ([auto]) lies along the line from the key before it to
  ///   the key after it, reaching a third of the way to the neighbour on
  ///   that side — none at the first and the last key, which have no line
  ///   to lie along, nor where the two neighbours stand at one point.
  ///   ⚠️The third is this round's choice — the reach at which a straight
  ///   run's controls sit evenly on it; how far After Effects' own auto
  ///   bezier reaches was not read.
  Offset reach({
    required bool ahead,
    required CanvasPoint at,
    CanvasPoint? before,
    CanvasPoint? after,
  }) {
    switch (this) {
      case StraightPath():
        return Offset.zero;
      case JoinedPath(:final degrees, ahead: final front, :final behind):
        final way = Offset(turnCos(degrees), turnSin(degrees));
        return ahead ? way * front : way * -behind;
      case SplitPath(ahead: final front, :final behind):
        final handle = ahead ? front : behind;
        return Offset(handle.x, handle.y);
      case AutoPath():
        if (before == null || after == null) {
          return Offset.zero;
        }
        final through = Offset(after.x - before.x, after.y - before.y);
        if (through == Offset.zero) {
          return Offset.zero;
        }
        final length = (ahead ? after : before).distanceTo(at) / 3;
        return through / through.distance * (ahead ? length : -length);
    }
  }

  /// The way, in degrees, its handle ahead of a key standing [at] between
  /// [before] and [after] points ([reach]) — or, where that reaches nowhere,
  /// away from the one behind; along the canvas's x axis where neither
  /// reaches.
  double wayAhead({
    required CanvasPoint at,
    CanvasPoint? before,
    CanvasPoint? after,
  }) {
    if (this case JoinedPath(:final degrees)) {
      return degrees;
    }
    final front = reach(ahead: true, at: at, before: before, after: after);
    final way = front != Offset.zero
        ? front
        : -reach(ahead: false, at: at, before: before, after: after);
    return way == Offset.zero ? 0 : handleDegrees(way);
  }

  /// This path made [kind] on a key standing [at] between [before] and
  /// [after] — the key window's 「경로」 row (anchor-walks-a-path-Q4 A,
  /// 유저 10-21): a corner or an auto key made a bezier, split or joined,
  /// starts from the handles the neighbours lay ([auto]) — as After
  /// Effects first places a Bezier key's; a joined pair split keeps its two
  /// handles as they reach; a split pair joined lines the one behind up
  /// with the one ahead ([wayAhead]), each keeping its length. Its own
  /// kind leaves it as it is.
  KeyPath turned(
    KeyPathKind kind, {
    required CanvasPoint at,
    CanvasPoint? before,
    CanvasPoint? after,
  }) {
    if (kind == this.kind) {
      return this;
    }
    final from = this is StraightPath ? auto : this;
    Offset handle({required bool ahead}) =>
        from.reach(ahead: ahead, at: at, before: before, after: after);
    return switch (kind) {
      KeyPathKind.linear => straight,
      KeyPathKind.autoBezier => auto,
      KeyPathKind.bezier => SplitPath(
        ahead: _pointOf(handle(ahead: true)),
        behind: _pointOf(handle(ahead: false)),
      ),
      KeyPathKind.continuousBezier => JoinedPath(
        degrees: from.wayAhead(at: at, before: before, after: after),
        ahead: handle(ahead: true).distance,
        behind: handle(ahead: false).distance,
      ),
    };
  }

  /// What a file says of it — nothing for [straight], which every key is
  /// unless told otherwise.
  Object? toJson();

  /// [toJson] read back. A path this build has no word for is a file it
  /// cannot read, and says so.
  static KeyPath fromJson(Object? json) => switch (json) {
    null => straight,
    AutoPath._json => auto,
    {
      'joined': {
        'degrees': final num degrees,
        'ahead': final num ahead,
        'behind': final num behind,
      },
    }
        when ahead >= 0 && behind >= 0 =>
      JoinedPath(
        degrees: degrees.toDouble(),
        ahead: ahead.toDouble(),
        behind: behind.toDouble(),
      ),
    {
      'split': {
        'ahead': final Map<String, dynamic> ahead,
        'behind': final Map<String, dynamic> behind,
      },
    } =>
      SplitPath(
        ahead: CanvasPoint.fromJson(ahead),
        behind: CanvasPoint.fromJson(behind),
      ),
    _ => throw FormatException('Unknown key path: $json'),
  };
}

/// [KeyPath.straight]'s type.
final class StraightPath extends KeyPath {
  const StraightPath._();

  @override
  bool get curved => false;

  @override
  KeyPathKind get kind => KeyPathKind.linear;

  @override
  Object? toJson() => null;

  @override
  String toString() => 'KeyPath.straight';
}

/// [KeyPath.auto]'s type.
final class AutoPath extends KeyPath {
  const AutoPath._();

  static const String _json = 'auto';

  @override
  bool get curved => true;

  @override
  KeyPathKind get kind => KeyPathKind.autoBezier;

  @override
  Object? toJson() => _json;

  @override
  String toString() => 'KeyPath.auto';
}

/// Smooth through the key along handles the hand placed, the two in ONE
/// line through it — After Effects' continuous bezier (I-89 ②): the
/// handle AHEAD of the key points [degrees] round from the canvas's x
/// axis and reaches [ahead] out of it, the one behind reaches [behind] the
/// other way.
///
/// ⛔One way and two reaches, not two handles: a pair that has left the
/// line cannot be written down. AE keeps a key's two spatial tangents
/// apart, continuity a mark over them (its scripting guide:
/// `keyInSpatialTangent` · `keyOutSpatialTangent` ·
/// `keySpatialContinuous`) — so each reaches its own length.
/// ↩️A placed handle's behind was its mirror (④-Q4 A, this session's
/// recommendation and never set against AE — 유저 10-13 「구조는 최대한
/// AE랑 통일하려고」).
final class JoinedPath extends KeyPath {
  const JoinedPath({
    required this.degrees,
    required this.ahead,
    required this.behind,
  });

  final double degrees;
  final double ahead;
  final double behind;

  @override
  bool get curved => true;

  @override
  KeyPathKind get kind => KeyPathKind.continuousBezier;

  @override
  Object? toJson() => {
    'joined': {'degrees': degrees, 'ahead': ahead, 'behind': behind},
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinedPath &&
          other.degrees == degrees &&
          other.ahead == ahead &&
          other.behind == behind;

  @override
  int get hashCode => Object.hash(degrees, ahead, behind);

  @override
  String toString() => 'KeyPath.joined($degrees°, $ahead, $behind)';
}

/// Smooth on each side of the key along a handle of that side's own — AE's
/// bezier (I-89 ②): [ahead] is how far, and which way, the handle ahead
/// of the key reaches out of it on the canvas, [behind] the one behind.
/// The path may turn a corner at the key where the two disagree.
final class SplitPath extends KeyPath {
  const SplitPath({required this.ahead, required this.behind});

  final CanvasPoint ahead;
  final CanvasPoint behind;

  @override
  bool get curved => true;

  @override
  KeyPathKind get kind => KeyPathKind.bezier;

  @override
  Object? toJson() => {
    'split': {'ahead': ahead.toJson(), 'behind': behind.toJson()},
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitPath && other.ahead == ahead && other.behind == behind;

  @override
  int get hashCode => Object.hash(ahead, behind);

  @override
  String toString() => 'KeyPath.split($ahead, $behind)';
}

/// The way [way] points, in degrees round from the canvas's x axis — a
/// joined pair's [JoinedPath.degrees].
double handleDegrees(Offset way) => way.direction * 180 / math.pi;

CanvasPoint _pointOf(Offset handle) => CanvasPoint(x: handle.dx, y: handle.dy);
