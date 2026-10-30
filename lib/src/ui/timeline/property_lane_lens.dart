import '../../models/property_track.dart';

/// A verb on ONE lane, written without knowing the lane's value type: it
/// reads the lane and answers its replacement, or null for "nothing to
/// write". Every lane-scoped edit is this shape, so a verb is written once
/// and dispatched through a table instead of once per `switch (laneId)`
/// arm.
typedef PropertyLaneEdit = PropertyTrack<U>? Function<U>(PropertyTrack<U> lane);

/// A [PropertyLaneEdit] that reads the same lane of another track as well
/// ([beside], null where there is none) — the key a name already holds on
/// a 겸용 sibling's track, adopted by the keys that join it.
typedef PropertyLaneEditBeside =
    PropertyTrack<U>? Function<U>(
      PropertyTrack<U> lane,
      PropertyTrack<U>? beside,
    );

/// Where a lane LIVES on its track — the address a verb dispatches over.
/// The property is data, the verb is written once (Blender's RNA property
/// paths, Krita's keyframe-channel lookups: the same shape).
///
/// 🚨The transform track and the SE name-tag track each carried a
/// `switch (laneId)` per VERB — seven arms and four — every arm reading one
/// field and writing it back through copyWith, and the two families'
/// keys-shift verbs were one algorithm over two such switches (the audit's
/// clone scan, round 8, 2026-09-06). This is that dispatch as a value: one
/// table per family, one entry per lane id, and the verbs stop knowing the
/// fields. A family whose lanes are not fields (the effect chain, addressed
/// by parsed (effectId, parameterId) over a list) implements the same two
/// answers its own way.
abstract interface class LaneLens<Track> {
  /// [track] with this lane replaced by what [edit] answers; null when
  /// [edit] answers null (nothing to write) or the lane cannot be reached.
  Track? update(Track track, PropertyLaneEdit edit);

  /// The lane's keyed frames — the keyframe navigator's ◀/▶ jump targets.
  Set<int> keyFrames(Track track);

  /// The lane's keys, frame by frame — what the key window reads of the
  /// keys a span covers (their names and types), whichever family the
  /// lane is of (F-374).
  Map<int, PropertyKey<Object?>> keysOf(Track track);

  /// The number [held] — a value of this lane of [track] — shows as in its
  /// value column; null for a lane of no numbers.
  double? numberShown(Track track, double held);

  /// What this lane of [track] holds for the number [shown] — what its
  /// value editor makes of it typed, clamped where the lane's range ends;
  /// null for a lane of no numbers.
  double? numberHeld(Track track, double shown);
}

/// How a lane of numbers reads them: the number its value column shows for
/// one it holds, and the one it holds for a number it is given — as its
/// value editor takes it typed ([LaneLens.numberHeld]).
typedef LaneNumbers = ({
  double Function(double held) shown,
  double Function(double shown) held,
});

/// A lane whose numbers show as they are held, any number taken — a
/// rotation's degrees, a letter's size.
const LaneNumbers numbersAsHeld = (shown: _asIs, held: _asIs);

double _asIs(double number) => number;

/// A lane that is ONE [PropertyTrack] field of its track: read by [get],
/// written back by [set].
class PropertyLaneLens<Track, T> implements LaneLens<Track> {
  const PropertyLaneLens({required this.get, required this.set, this.numbers});

  final PropertyTrack<T> Function(Track track) get;
  final Track Function(Track track, PropertyTrack<T> lane) set;

  /// How the lane reads its numbers — null for a lane of none.
  final LaneNumbers? numbers;

  @override
  Track? update(Track track, PropertyLaneEdit edit) {
    final next = edit<T>(get(track));
    return next == null ? null : set(track, next);
  }

  /// [update], [edit] handed this lane of [beside] too, as the same type.
  Track? updateBeside(
    Track track,
    Track? beside,
    PropertyLaneEditBeside edit,
  ) {
    final next = edit<T>(get(track), beside == null ? null : get(beside));
    return next == null ? null : set(track, next);
  }

  /// The key window's write on this lane (F-17 · I-89): the keys inside
  /// [frames] named as [naming] says (a null name un-names them) — all
  /// collapsed onto ONE value, the key the name already holds on
  /// [adoptFrom] where it holds one — and then given [pick]. ONE write of
  /// the lane ([PropertyTrack.withKeysWritten]); null when nothing changed.
  /// What of the window's pick a lane takes is its family's to say.
  ///
  /// ⛔Written once for every lane that is a field of its track: the name
  /// tag's took the transform's body when its lanes reached the window
  /// (F-374).
  Track? keysWritten(
    Track track, {
    required Set<int> frames,
    ({String? name, int? preferredFrame})? naming,
    Track? adoptFrom,
    KeyTypePick pick = const KeyTypePick(),
  }) => updateBeside(track, adoptFrom, <U>(
    PropertyTrack<U> lane,
    PropertyTrack<U>? holder,
  ) {
    final name = naming?.name;
    return lane.withKeysWritten(
      frames: frames,
      naming: naming == null
          ? null
          : (
              name: name,
              adopted: name == null ? null : holder?.keyForName(name),
              preferredFrame: naming.preferredFrame,
            ),
      pick: pick,
    );
  });

  @override
  Set<int> keyFrames(Track track) => get(track).keys.keys.toSet();

  @override
  Map<int, PropertyKey<Object?>> keysOf(Track track) => get(track).keys;

  @override
  double? numberShown(Track track, double held) => numbers?.shown(held);

  @override
  double? numberHeld(Track track, double shown) => numbers?.held(shown);
}
