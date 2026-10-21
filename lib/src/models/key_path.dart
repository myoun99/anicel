import 'canvas_point.dart';

/// How a lane's PATH passes through a key in space (I-89 ④) — beside how
/// fast it travels there ([KeySide]), After Effects' spatial
/// interpolation.
///
/// A key new on such a lane is smooth through the key as its neighbours
/// lay it, AE's auto bezier (I-89-Q10 B — the one write is
/// `pathLaneKeyed`); the key window turns it into a corner and back,
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
