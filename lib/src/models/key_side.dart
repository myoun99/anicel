/// THE TWO SIDES OF A KEY (I-89).
///
/// 🗣️유저 2026-10-10: 「키 양쪽. 업계 표준인 전문 툴대로 하고싶어. 그게
/// ae고」 — a key shapes the segment ARRIVING at it with its in side and the
/// one LEAVING it with its out side, After Effects' temporal interpolation.
/// A segment is the out side of the key it leaves and the in side of the
/// key it reaches, so the curve one segment draws ([segmentProgress]) is
/// what those two sides say together. ↩️A key carried ONE type, linear or
/// hold, for the segment leaving it — 「지금 리니어/홀드 있는거라던가는
/// 아주 초기단계니까 다 갈아엎어도되고」.
library;

/// What the side LEAVING a key does: shape the segment the way any side
/// can ([KeySide]), or [hold] the key's value until the next key.
///
/// ⛔A hold is an OUT side only (I-89, 「홀드(나가는 쪽)」): a segment
/// arriving at a key while still holding the value before it is the
/// segment the key before LEAVES with a hold, so a hold on an in side
/// would be a second way to say one thing. The in side is typed [KeySide],
/// which has no hold to say it with.
sealed class KeyExit {
  const KeyExit();

  /// AE's Hold: the value stays where the key put it until the next key.
  static const KeyExit hold = KeyHold._();

  Object toJson();

  /// [toJson] read back.
  static KeyExit fromJson(Object? json) =>
      json == KeyHold._json ? hold : KeySide.fromJson(json);
}

/// [KeyExit.hold]'s type.
final class KeyHold extends KeyExit {
  const KeyHold._();

  static const String _json = 'hold';

  @override
  Object toJson() => _json;

  @override
  String toString() => 'KeyExit.hold';
}

/// How one side of a key moves the value near the key — either side.
sealed class KeySide extends KeyExit {
  const KeySide();

  /// AE's Linear: a straight ramp.
  static const KeySide linear = LinearSide._();

  /// AE's Auto Bezier: smooth THROUGH the key.
  static const KeySide auto = AutoSide._();

  /// [toJson] read back. A side this build has no word for is a file it
  /// cannot read, and says so — and so is an in side that holds.
  static KeySide fromJson(Object? json) => switch (json) {
    LinearSide._json => linear,
    AutoSide._json => auto,
    {'kind': EaseSide._json} => EaseSide.fromJson(
      json as Map<String, dynamic>,
    ),
    _ => throw FormatException('Unknown key side: $json'),
  };
}

/// [KeySide.linear]'s type.
final class LinearSide extends KeySide {
  const LinearSide._();

  static const String _json = 'linear';

  @override
  Object toJson() => _json;

  @override
  String toString() => 'KeySide.linear';
}

/// [KeySide.auto]'s type: the speed at the key is the one its neighbours'
/// values imply ([autoSideSpeed]).
final class AutoSide extends KeySide {
  const AutoSide._();

  static const String _json = 'auto';

  @override
  Object toJson() => _json;

  @override
  String toString() => 'KeySide.auto';
}

/// AE's Bezier side: the value slows toward the key for [influence] of the
/// segment and moves at [speed] times the segment's average when it gets
/// there — 0 stops at the key, AE's Easy Ease.
final class EaseSide extends KeySide {
  const EaseSide({this.influence = easeInfluence, this.speed = 0})
    : assert(influence > 0 && influence <= 1),
      assert(speed > double.negativeInfinity && speed < double.infinity);

  /// [toJson] read back; [KeySide.fromJson] is the door.
  factory EaseSide.fromJson(Map<String, dynamic> json) {
    final influence = (json['influence'] as num).toDouble();
    final speed = (json['speed'] as num).toDouble();
    if (!(influence > 0 && influence <= 1) || !speed.isFinite) {
      throw FormatException('Key ease out of range: $json');
    }
    return EaseSide(influence: influence, speed: speed);
  }

  /// AE's Easy Ease: a third of the segment, 33.33%.
  static const double easeInfluence = 1 / 3;

  static const String _json = 'ease';

  /// How far into the segment the side reaches, 0 < influence ≤ 1 — AE's
  /// influence %.
  final double influence;

  /// The value's speed at the key, as a multiple of the segment's average.
  final double speed;

  EaseSide copyWith({double? influence, double? speed}) => EaseSide(
    influence: influence ?? this.influence,
    speed: speed ?? this.speed,
  );

  @override
  Object toJson() => {'kind': _json, 'influence': influence, 'speed': speed};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EaseSide && other.influence == influence && other.speed == speed;

  @override
  int get hashCode => Object.hash(influence, speed);

  @override
  String toString() => 'EaseSide($influence, $speed)';
}

/// What a side IS — what its half of the key's mark draws, what a union
/// compares and what the key window offers (I-89 ②). An ease at 33% and
/// one at 50% are one kind.
enum KeySideKind {
  /// AE's Linear — half a diamond.
  linear,

  /// AE's Bezier, 「천천히」 — half an hourglass.
  ease,

  /// AE's Auto Bezier, 「부드럽게 지나감」 — half a disc.
  auto,

  /// AE's Hold — half a square. Only ever a leaving side ([KeyExit]).
  hold,
}

/// [side]'s kind.
KeySideKind keySideKindOf(KeyExit side) => switch (side) {
  LinearSide() => KeySideKind.linear,
  EaseSide() => KeySideKind.ease,
  AutoSide() => KeySideKind.auto,
  KeyHold() => KeySideKind.hold,
};

/// A write to ONE side of a key, as the key window gives it (I-89 ②): the
/// KIND the side becomes and the INFLUENCE its ease takes, either or both —
/// each only what the user picked.
///
/// A side already of [side]'s kind keeps its own — an ease its influence
/// and its speed — so picking the kind a key has changes nothing, which is
/// what lights a choice: by kind, as the key's mark draws it, not by its
/// numbers.
final class KeySideEdit<S extends KeyExit> {
  const KeySideEdit({this.side, this.influence})
    : assert(influence == null || (influence > 0 && influence <= 1));

  /// What a side of another kind becomes — the kind picked, at its
  /// defaults (an ease is AE's Easy Ease). Null leaves the kind as it is.
  final S? side;

  /// The influence an ease takes, its speed kept — AE's influence % alone.
  /// Null leaves it as it is; a side that is no ease has none to take.
  final double? influence;

  /// [current] with this edit on it.
  S applyTo(S current) {
    final side = this.side;
    final kept = side == null || keySideKindOf(side) == keySideKindOf(current)
        ? current
        : side;
    final influence = this.influence;
    return influence != null && kept is EaseSide
        // An ease is a KeySide, so it is an S whichever side this edits.
        ? kept.copyWith(influence: influence) as S
        : kept;
  }
}

/// A write to a key's sides: each side edited as its [KeySideEdit] says,
/// the side left out as it was — AE's Easy Ease In touches the in side
/// alone, its Easy Ease both.
class KeySidesEdit {
  const KeySidesEdit({this.incoming, this.outgoing});

  /// Both sides straight — AE's Linear.
  static const KeySidesEdit linear = KeySidesEdit(
    incoming: KeySideEdit(side: KeySide.linear),
    outgoing: KeySideEdit(side: KeySide.linear),
  );

  /// The value held from the key on — AE's Toggle Hold Keyframe.
  static const KeySidesEdit hold = KeySidesEdit(
    outgoing: KeySideEdit(side: KeyExit.hold),
  );

  final KeySideEdit<KeySide>? incoming;
  final KeySideEdit<KeyExit>? outgoing;

  /// A key's sides with this edit on them.
  ({KeySide incoming, KeyExit outgoing}) applyTo({
    required KeySide incoming,
    required KeyExit outgoing,
  }) => (
    incoming: this.incoming?.applyTo(incoming) ?? incoming,
    outgoing: this.outgoing?.applyTo(outgoing) ?? outgoing,
  );
}

/// What [sides] say TOGETHER — a row of the key window, over every key it
/// covers (I-89 ②): the kind they all are, null where they differ; and
/// where they are all eases, the influence they all take, null where those
/// differ. The rule the window's name follows (「다르면 …」): it shows what
/// the keys agree on.
({KeySideKind? kind, double? influence}) keySidesTogether(
  Iterable<KeyExit> sides,
) {
  final kind = {for (final side in sides) keySideKindOf(side)}.singleOrNull;
  return (
    kind: kind,
    influence: kind == KeySideKind.ease
        ? {
            for (final side in sides)
              if (side is EaseSide) side.influence,
          }.singleOrNull
        : null,
  );
}

/// Where a side's Bézier handle sits in a segment's unit square:
/// [influence] of the way in time, moving at [speed] times the segment's
/// average.
typedef KeyHandle = ({double influence, double speed});

/// A straight ramp's handle — a third of the way, at the average speed —
/// and the handle every side but an ease takes: an auto side with the
/// speed its neighbours imply put in.
const KeyHandle linearKeyHandle = (influence: 1 / 3, speed: 1);

/// The handle [side] puts in its segment. [autoSpeed] is read only for an
/// auto side.
KeyHandle keyHandleOf(KeySide side, double Function() autoSpeed) =>
    switch (side) {
      LinearSide() => linearKeyHandle,
      EaseSide(:final influence, :final speed) => (
        influence: influence,
        speed: speed,
      ),
      AutoSide() => (influence: linearKeyHandle.influence, speed: autoSpeed()),
    };

/// The speed an auto side moves at through its key, given how far the
/// neighbour on the key's far side [reach]es along the segment's own line —
/// in the segment's units (its two keys 0 and 1) per its own length in
/// time, i.e. the Catmull-Rom tangent over the segment's average speed.
///
/// ⛔Clamped to 0..3: an auto side never overshoots. A key between a rise
/// and a fall (a negative reach) stops level, and a pull steeper than the
/// segment can take stops at 3, where the handle sits level with the far
/// key and the curve stays between the two keys' values. This is the
/// smooth default the tools ship (Blender's Auto Clamped, Maya's clamped
/// tangents); I-89 asks only for 「이웃 값이 정하는 속도」, so the clamp is
/// mine (2026-10-10) — a curve that leaves the two values it joins is what
/// an ease or a graph handle asks for on purpose.
double autoSideSpeed(double reach) => reach.clamp(0.0, 3.0).toDouble();

/// How far a segment has come at [x], the fraction of its TIME gone (0..1):
/// the unit cubic Bézier through (0, 0), the [leaving] key's handle
/// (`influence`, `influence · speed`), the [arriving] key's handle
/// (`1 − influence`, `1 − influence · speed`) and (1, 1) — AE's temporal
/// curve over one segment, its speeds relative to the segment's average.
/// Two straight ramps' handles lie on the diagonal, so they give x itself.
///
/// Each influence stays within the segment, so the curve's time runs
/// forward wherever the two reach; the progress leaves 0..1 only where a
/// speed asks for an overshoot.
double segmentProgress(
  double x, {
  required KeyHandle leaving,
  required KeyHandle arriving,
}) {
  if (x <= 0) {
    return 0;
  }
  if (x >= 1) {
    return 1;
  }
  final x1 = leaving.influence;
  final y1 = leaving.influence * leaving.speed;
  final x2 = 1 - arriving.influence;
  final y2 = 1 - arriving.influence * arriving.speed;
  double bezier(double t, double p1, double p2) {
    final u = 1 - t;
    return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t;
  }

  // Newton's step where it lands inside the bracket, a halving where it
  // does not: with both handles' times inside the segment the curve's time
  // never runs back, so the bracket always holds the one answer.
  var lo = 0.0;
  var hi = 1.0;
  var t = x;
  for (var step = 0; step < 32; step += 1) {
    final off = bezier(t, x1, x2) - x;
    if (off.abs() < 1e-10) {
      break;
    }
    if (off > 0) {
      hi = t;
    } else {
      lo = t;
    }
    final u = 1 - t;
    final slope = 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2);
    final next = slope.abs() > 1e-12 ? t - off / slope : (lo + hi) / 2;
    t = next > lo && next < hi ? next : (lo + hi) / 2;
  }
  return bezier(t, y1, y2);
}
