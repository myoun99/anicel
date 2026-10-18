import 'canvas_point.dart';

/// How a lane's PATH passes through a key in space (I-89 ④) — beside how
/// fast it travels there ([KeySide]), After Effects' spatial
/// interpolation.
///
/// A key new on such a lane is smooth through the key as its neighbours
/// lay it, AE's auto bezier (I-89-Q10 B — the one write is
/// `pathLaneKeyed`); the key window turns it into a corner and back,
/// and a handle pulled on the canvas then stays where it was left, the
/// other side following as its mirror (④-Q4 A). ↩️A key was a corner by
/// default — a pan runs straight — the key window making it a curve.
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
    {'tangent': final Map<String, dynamic> tangent} => HandledPath(
      CanvasPoint.fromJson(tangent),
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

/// Smooth through the key along a handle the hand placed: [tangent] is how
/// far, and which way, it reaches out AHEAD of the key on the canvas — and
/// it reaches as far behind it the other way, its mirror.
final class HandledPath extends KeyPath {
  const HandledPath(this.tangent);

  final CanvasPoint tangent;

  @override
  bool get curved => true;

  @override
  Object? toJson() => {'tangent': tangent.toJson()};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandledPath && other.tangent == tangent;

  @override
  int get hashCode => tangent.hashCode;

  @override
  String toString() => 'KeyPath.handled($tangent)';
}
