import '../../models/layer_effect.dart';
import '../../models/property_track.dart';
import '../../models/se_name_tag.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/transform_track.dart';
import '../timeline/effect_lane_editing.dart' show effectLaneLens;
import '../timeline/effect_lane_policy.dart' show parseEffectLaneId;
import '../timeline/lane_span_keys_shift.dart' show laneSpanKeysShifted;
import '../timeline/property_lane_lens.dart';
import '../timeline/reference_lane_policy.dart' show transformLanesByHome;
import '../timeline/se_name_tag_lane_policy.dart'
    show laneIsSeNameTag, seNameTagLaneLens;
import '../timeline/transform_lane_editing.dart' show transformLaneLens;
import 'lane_edit_subject.dart';

/// ONE HOME of a row's keys (F-374): what it holds, the lanes of a span
/// that live there — in its own words — and how a lane id reaches into it
/// ([LaneLens]). A row keeps its lanes' keys in four: its own transform
/// track (the cut's camera, on the camera row), its reference fx, its
/// effect chain and, on an SE row, its name tag ([RowLaneHomes]).
///
/// 🚨THE SPAN VERBS ARE WRITTEN ONCE, OVER THESE. A lane span is sliced out
/// of the rows the rail drew (#1381, 2026-08-30), so it may hold lanes of
/// every home — 절대명령 2: 「선택범위는 레이어 불문 자유롭게」. Each verb asked
/// whether an EFFECT lane was among them and then worked one family, the
/// effect chain else the transform, so the rest of the span was left where
/// it was; and a span of a name tag's lanes made, took and named nothing.
/// ↩️The range move's 「safe because the span keeps a lane selection
/// single-family」 stopped being true with #1381.
class LaneHome<T> {
  const LaneHome(this.keys, this.laneIds, this.lensOf);

  /// What the home holds now.
  final T keys;

  /// The lanes of the span that live here, in the home's own words: a
  /// reference fx's member as the transform lane it holds.
  final List<String> laneIds;

  /// How a lane id reaches into [keys] — null for one that cannot.
  final LaneLens<T>? Function(String laneId) lensOf;

  /// Whether a lane here holds a key at a frame [covers] takes.
  bool keyedWhere(bool Function(int frame) covers) => laneIds.any(
    (laneId) => lensOf(laneId)?.keyFrames(keys).any(covers) ?? false,
  );

  /// The keys every lane here holds at a frame [covers] takes, lane by lane
  /// — a lane with none there as an empty map.
  Iterable<LaneKeys> keysWhere(bool Function(int frame) covers) sync* {
    for (final laneId in laneIds) {
      final held = lensOf(laneId)?.keysOf(keys) ?? const {};
      yield (
        laneId: laneId,
        keys: {
          for (final MapEntry(key: frame, value: key) in held.entries)
            if (covers(frame)) frame: key,
        },
      );
    }
  }

  /// [edit] on every lane here, in turn — null where none changed.
  T? edited(PropertyLaneEdit edit) => editedEach((_) => edit);

  /// Each lane here edited as [editOf] says — a lane it gives no edit left
  /// as it is — null where none changed.
  T? editedEach(PropertyLaneEdit? Function(String laneId) editOf) =>
      foldedEdits(keys, laneIds, (value, laneId) {
        final edit = editOf(laneId);
        return edit == null ? null : lensOf(laneId)?.update(value, edit);
      });

  /// A key on every frame of [frames] a lane here holds none at: the one
  /// [frozen] makes there of [keys] as they stand — the lane navigator's ◆
  /// — so it holds what the lane SHOWS there. Null where none is made.
  ///
  /// ↩️The effect chain's Create froze each key on the keys frozen before
  /// it, so between eased keys every one was read off a curve the one
  /// before had bent; the transform's read the row as it stood (F-374).
  T? keyedAt(
    Iterable<int> frames,
    T? Function(T keys, String laneId, int frame) frozen,
  ) => foldedEdits(keys, laneIds, (value, laneId) {
    final lens = lensOf(laneId);
    if (lens == null) {
      return null;
    }
    final keyed = lens.keyFrames(keys);
    final made = <int, PropertyKey<Object?>>{
      for (final frame in frames)
        if (!keyed.contains(frame))
          if (frozen(keys, laneId, frame) case final single?)
            frame: ?lens.keysOf(single)[frame],
    };
    return made.isEmpty ? null : lens.update(value, _keysPut(made));
  });

  /// The keys of every lane here that [span] covers, shifted by
  /// [frameDelta] — ONE rigid group ([laneSpanKeysShifted]): null when a
  /// landing is blocked, and when no key here moves.
  T? shifted(TimelineLaneSelection span, int frameDelta) =>
      laneSpanKeysShifted(
        keys,
        laneIds: laneIds,
        lensOf: lensOf,
        rangeStartIndex: span.startIndex,
        rangeEndIndexExclusive: span.endIndexExclusive,
        frameDelta: frameDelta,
      );
}

/// One lane's keys, by frame ([LaneHome.keysWhere]).
typedef LaneKeys = ({String laneId, Map<int, PropertyKey<Object?>> keys});

/// A copy of keys (`KeyBoard`, F-388): each lane's keys by their frame from
/// the copy's first, and the frames the copy spans — the run a paste puts
/// in, its gaps and all, as a frame copy's run is.
typedef KeyCopy = ({List<LaneKeys> lanes, int length});

/// The four homes of a row's keys ([LaneHome]).
typedef RowLaneHomes = ({
  LaneHome<TransformTrack> own,
  LaneHome<TransformTrack> reference,
  LaneHome<List<LayerEffect>> effects,
  LaneHome<SeNameTagTrack> nameTag,
});

/// [subject]'s homes, each holding the lanes of [laneIds] that live there.
RowLaneHomes rowLaneHomes(LaneEditSubject subject, List<String> laneIds) {
  final effects = <String>[];
  final nameTag = <String>[];
  final transform = <String>[];
  for (final laneId in laneIds) {
    (parseEffectLaneId(laneId) != null
            ? effects
            : laneIsSeNameTag(laneId)
            ? nameTag
            : transform)
        .add(laneId);
  }
  final byHome = transformLanesByHome(transform);
  return (
    own: LaneHome(subject.transformTrack, byHome.own, transformLaneLens),
    reference: LaneHome(
      subject.referenceFx ?? TransformTrack.empty(),
      byHome.reference,
      transformLaneLens,
    ),
    effects: LaneHome(subject.effects, effects, effectLaneLens),
    nameTag: LaneHome(
      subject.seNameTag?.track ?? SeNameTagTrack.empty(),
      nameTag,
      seNameTagLaneLens,
    ),
  );
}

/// Whether a lane of [homes] holds a key at a frame [covers] takes.
bool rowLaneHomesKeyedWhere(
  RowLaneHomes homes,
  bool Function(int frame) covers,
) =>
    homes.own.keyedWhere(covers) ||
    homes.reference.keyedWhere(covers) ||
    homes.effects.keyedWhere(covers) ||
    homes.nameTag.keyedWhere(covers);

/// What [verb] leaves [subject]'s row at, home by home — each home it
/// answers null for left alone.
LaneEdit rowLaneHomesEdited(
  LaneEditSubject subject,
  RowLaneHomes homes,
  T? Function<T>(LaneHome<T> home) verb,
) => LaneEdit(
  transform: (own: verb(homes.own), reference: verb(homes.reference)),
  effects: verb(homes.effects),
  nameTag: subject.nameTagWith(verb(homes.nameTag)),
);

/// Every key at a frame [covers] takes, taken away — nothing where the lane
/// holds none there. What Delete does to each lane of a span.
PropertyLaneEdit laneKeysRemovedWhere(bool Function(int frame) covers) =>
    <U>(PropertyTrack<U> lane) {
      final frames = [
        for (final frame in lane.keys.keys)
          if (covers(frame)) frame,
      ];
      return frames.isEmpty
          ? null
          : frames.fold<PropertyTrack<U>>(
              lane,
              (track, frame) => track.withoutKey(frame),
            );
    };

/// [keys], by their frame from the paste's first, put in at [start] as a
/// frame paste puts its run in: the [liftCount] frames from [start] taken
/// out with their keys, and every key after them moved by what the
/// [length] pasted puts in their place. Null for a lane whose values are
/// not those keys' kind — a position's keys go on a position, a number's
/// on a number — and where nothing changes.
///
/// 🗣️F-388-Q1 (유저 2026-10-20): 「프레임과 똑같이 끼워 넣기 — 그냥
/// 생각할것도없이 프레임블록 복붙이랑 똑같은 규칙」: with nothing selected
/// the keys go in at the playhead and every key from there on moves back by
/// the copy's length; a selection is replaced, and what follows it moves by
/// the difference. AE leaves the keys after alone — the board weighed that
/// and was answered.
PropertyLaneEdit laneKeysSpliced({
  required int start,
  required int liftCount,
  required int length,
  required Map<int, PropertyKey<Object?>> keys,
}) => <U>(PropertyTrack<U> lane) {
  if (!keys.values.every((key) => key is PropertyKey<U>)) {
    return null;
  }
  final end = start + liftCount;
  final moved = lane.keys.keys.any(
    (frame) => frame >= start && (frame < end || length != liftCount),
  );
  if (keys.isEmpty && !moved) {
    return null;
  }
  return PropertyTrack<U>(
    keys: {
      for (final MapEntry(key: frame, value: key) in lane.keys.entries)
        if (frame < start)
          frame: key
        else if (frame >= end)
          frame + length - liftCount: key,
      for (final MapEntry(key: offset, value: key) in keys.entries)
        start + offset: key as PropertyKey<U>,
    },
  );
};

/// [made] put on the lane as they are — each a key of this very lane, made
/// of it as it stood ([LaneHome.keyedAt]).
PropertyLaneEdit _keysPut(Map<int, PropertyKey<Object?>> made) =>
    <U>(PropertyTrack<U> lane) => PropertyTrack<U>(
      keys: {...lane.keys, ...made.cast<int, PropertyKey<U>>()},
    );

/// [start] with [step] applied for each of [items] in turn, or null when no
/// step changed it — a step answers null when it leaves the value alone.
///
/// ⛔THE LANE-KEY VERBS FOLD THIS WAY. Create, Delete and the key window's
/// name/type write each walked their lanes and frames with the same
/// accumulate-and-flag loop, once per family (effect chain, transform
/// track), and the clone scan named the third copy when the window's TYPE
/// arrived (F-17, 2026-09-11).
T? foldedEdits<T, I>(
  T start,
  Iterable<I> items,
  T? Function(T value, I item) step,
) {
  T? result;
  for (final item in items) {
    result = step(result ?? start, item) ?? result;
  }
  return result;
}
