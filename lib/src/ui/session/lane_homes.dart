import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/property_track.dart';
import '../../models/se_name_tag.dart';
import '../../models/se_sound.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/transform_track.dart';
import '../timeline/effect_lane_editing.dart'
    show effectLaneLens, effectLaneWalksAPath;
import '../timeline/effect_lane_policy.dart' show parseEffectLaneId;
import '../timeline/lane_span_keys_shift.dart' show laneSpanKeysMoved;
import '../timeline/property_lane_lens.dart';
import '../timeline/reference_lane_policy.dart' show transformLanesByHome;
import '../timeline/se_name_tag_lane_policy.dart'
    show laneIsSeNameTag, seNameTagLaneLens;
import '../timeline/se_sound_lane_policy.dart'
    show laneIsSeSound, seSoundLaneLens;
import '../timeline/transform_lane_editing.dart' show transformLaneLens;
import 'lane_edit_subject.dart';

/// ONE HOME of a row's keys (F-374): what it holds, the lanes of a span
/// that live there — in its own words — and how a lane id reaches into it
/// ([LaneLens]). A row keeps its lanes' keys in five: its own transform
/// track (the cut's camera, on the camera row), its reference fx, its
/// effect chain and, on an SE row, its name tag and its sound
/// ([RowLaneHomes]).
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
  const LaneHome(
    this.keys,
    this.laneIds,
    this.lensOf, {
    bool Function(T keys, String laneId) walks = _walksNoPath,
  }) : _walks = walks;

  /// What the home holds now.
  final T keys;

  /// The lanes of the span that live here, in the home's own words: a
  /// reference fx's member as the transform lane it holds.
  final List<String> laneIds;

  /// How a lane id reaches into [keys] — null for one that cannot.
  final LaneLens<T>? Function(String laneId) lensOf;

  /// Whether the keys of a lane of [keys] walk a path — the home's own
  /// family's answer: a transform's by the lane's id ([laneWalksAPath]),
  /// an effect's by the effect it is of ([effectLaneWalksAPath]).
  final bool Function(T keys, String laneId) _walks;

  /// Whether the keys of lane [laneId] here walk a path.
  bool walksAPath(String laneId) => _walks(keys, laneId);

  /// Whether a lane here holds a key at a frame [covers] takes.
  bool keyedWhere(bool Function(int frame) covers) =>
      keyedOnWhere((_, frame) => covers(frame));

  /// Whether a lane here holds a key at a frame [covers] takes on it.
  bool keyedOnWhere(bool Function(String laneId, int frame) covers) =>
      laneIds.any(
        (laneId) =>
            lensOf(laneId)?.keyFrames(keys).any(
              (frame) => covers(laneId, frame),
            ) ??
            false,
      );

  /// The keys every lane here holds at a frame [covers] takes, lane by lane
  /// — a lane with none there as an empty map.
  Iterable<LaneKeys> keysWhere(bool Function(int frame) covers) sync* {
    for (final laneId in laneIds) {
      final lens = lensOf(laneId);
      final kept = lens?.keysOf(keys) ?? const {};
      yield (
        laneId: laneId,
        keys: {
          for (final MapEntry(key: frame, value: key) in kept.entries)
            if (covers(frame)) frame: key,
        },
        walksAPath: walksAPath(laneId),
        shown: (held) => lens?.numberShown(keys, held),
      );
    }
  }

  /// [keys] of a lane whose numbers show by [shown], as lane [laneId] here
  /// takes them: each number held as this lane holds a number given it
  /// ([LaneLens.numberHeld]) — a key of no number, or where either lane is
  /// of none, as it came.
  Map<int, PropertyKey<Object?>> numbersTaken(
    String laneId,
    Map<int, PropertyKey<Object?>> keys,
    double? Function(double held) shown,
  ) {
    PropertyKey<Object?> taken(PropertyKey<Object?> key) {
      if (key is! PropertyKey<double>) {
        return key;
      }
      final number = shown(key.value);
      final held = number == null
          ? null
          : lensOf(laneId)?.numberHeld(this.keys, number);
      return held == null ? key : key.copyWith(value: held);
    }

    return {
      for (final MapEntry(key: frame, value: key) in keys.entries)
        frame: taken(key),
    };
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

  /// The keys of every lane here that [span] covers, each moved to the
  /// frame [to] gives it on its lane — ONE rigid group ([laneSpanKeysMoved]):
  /// null when a landing is blocked, and when no key here moves.
  T? moved(
    TimelineLaneSelection span,
    int Function(String laneId, int frame) to,
  ) =>
      laneSpanKeysMoved(
        keys,
        laneIds: laneIds,
        lensOf: lensOf,
        moveOn: (laneId) => (
          rangeStartIndex: span.startIndex,
          rangeEndIndexExclusive: span.endIndexExclusive,
          to: (frame) => to(laneId, frame),
        ),
      );
}

/// One lane's keys, by frame ([LaneHome.keysWhere]) — and what its row
/// says of them, read where they are taken: whether they walk a path
/// ([LaneHome.walksAPath]) and the number one of them shows as
/// ([LaneLens.numberShown]). ⛔Not read again off the lane's id where they
/// land: a copy may land on another row, and an effect's lane id says only
/// what its effect does — a plugin's ids are its own (I-132).
typedef LaneKeys = ({
  String laneId,
  Map<int, PropertyKey<Object?>> keys,
  bool walksAPath,
  double? Function(double held) shown,
});

bool _walksNoPath(Object? keys, String laneId) => false;

/// A bare transform lane's keys walk a path by its id ([laneWalksAPath]) —
/// a row's own and its reference fx's.
bool _transformLaneWalksAPath(TransformTrack keys, String laneId) =>
    laneWalksAPath(laneId);

/// A copy of keys (`KeyBoard`, F-388): each lane's keys by their frame from
/// the copy's first, and the frames the copy spans — the run a paste puts
/// in, its gaps and all, as a frame copy's run is.
typedef KeyCopy = ({List<LaneKeys> lanes, int length});

/// A band's copy of the keys on one layer's lane rows, taken without that
/// layer's cells (`LaneVerbs.bandKeysBesides`) — [camera] where the layer
/// is its cut's camera, whose keys go to the camera of the cut they are
/// pasted in.
typedef LanesAlone = ({LayerId layerId, bool camera, KeyCopy keys});

/// The five homes of a row's keys ([LaneHome]).
typedef RowLaneHomes = ({
  LaneHome<TransformTrack> own,
  LaneHome<TransformTrack> reference,
  LaneHome<List<LayerEffect>> effects,
  LaneHome<SeNameTagTrack> nameTag,
  LaneHome<SeSound> sound,
});

/// [subject]'s homes, each holding the lanes of [laneIds] that live there.
RowLaneHomes rowLaneHomes(LaneEditSubject subject, List<String> laneIds) {
  final effects = <String>[];
  final nameTag = <String>[];
  final sound = <String>[];
  final transform = <String>[];
  for (final laneId in laneIds) {
    (parseEffectLaneId(laneId) != null
            ? effects
            : laneIsSeNameTag(laneId)
            ? nameTag
            : laneIsSeSound(laneId)
            ? sound
            : transform)
        .add(laneId);
  }
  final byHome = transformLanesByHome(transform);
  return (
    own: LaneHome(
      subject.transformTrack,
      byHome.own,
      transformLaneLens,
      walks: _transformLaneWalksAPath,
    ),
    reference: LaneHome(
      subject.referenceFx ?? TransformTrack.empty(),
      byHome.reference,
      transformLaneLens,
      walks: _transformLaneWalksAPath,
    ),
    effects: LaneHome(
      subject.effects,
      effects,
      effectLaneLens,
      walks: effectLaneWalksAPath,
    ),
    nameTag: LaneHome(
      subject.seNameTag?.track ?? SeNameTagTrack.empty(),
      nameTag,
      seNameTagLaneLens,
    ),
    sound: LaneHome(subject.seSound ?? const SeSound(), sound, seSoundLaneLens),
  );
}

/// Every home of [homes], in the order a copy reads them
/// ([LaneVerbs.laneKeysCopiedFrom]) — what a verb asks of each in turn.
List<LaneHome<Object?>> rowLaneHomesInOrder(RowLaneHomes homes) => [
  homes.own,
  homes.reference,
  homes.effects,
  homes.nameTag,
  homes.sound,
];

/// Whether a lane of [homes] holds a key at a frame [covers] takes.
bool rowLaneHomesKeyedWhere(
  RowLaneHomes homes,
  bool Function(int frame) covers,
) => rowLaneHomesInOrder(homes).any((home) => home.keyedWhere(covers));

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
  sound: verb(homes.sound),
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

/// Where a paste puts its run in ([laneKeysSpliced]): the frame it goes
/// in at, how many frames from there it lifts, how many it puts in, and
/// the last a key may be left on — none but a camera's.
typedef KeysSplice = ({int start, int liftCount, int length, int? last});

/// [keys], by their frame from the paste's first, put in at [start] as a
/// frame paste puts its run in: the [liftCount] frames from [start] taken
/// out with their keys, and every key after them moved by what the
/// [length] pasted puts in their place. Null for a lane whose values are
/// not those keys' value type — a point's keys go on a point, a number's
/// on a number; which points pair is the caller's — and where nothing
/// changes.
///
/// 🗣️F-388-Q1 (유저 2026-10-20): 「프레임과 똑같이 끼워 넣기 — 그냥
/// 생각할것도없이 프레임블록 복붙이랑 똑같은 규칙」: with nothing selected
/// the keys go in at the playhead and every key from there on moves back by
/// the copy's length; a selection is replaced, and what follows it moves by
/// the difference. AE leaves the keys after alone — the board weighed that
/// and was answered.
///
/// With [last] — a camera's, its cut's last drawn frame (`cameraKeyFits`)
/// — no key goes past it: the key on [last] the run pushes out stays on
/// it, holding it against whatever lands there, and every other key past
/// it goes, a pasted one too. 🗣️F-388-Q3 (유저 2026-10-22): 「끝 키는 끝에
/// 남고, 밖으로 밀린 나머지는 버린다」 — the end key keeps to the cut's end
/// as it does when the cut is drawn longer (I-73-camera-row-Q4).
PropertyLaneEdit laneKeysSpliced({
  required KeysSplice splice,
  required Map<int, PropertyKey<Object?>> keys,
}) => <U>(PropertyTrack<U> lane) {
  if (!keys.values.every((key) => key is PropertyKey<U>)) {
    return null;
  }
  final (:start, :liftCount, :length, :last) = splice;
  final end = start + liftCount;
  final shift = length - liftCount;
  bool fits(int frame) => last == null || frame <= last;
  final next = PropertyTrack<U>(
    keys: {
      for (final MapEntry(key: frame, value: key) in lane.keys.entries)
        if (frame < start)
          frame: key
        else if (frame >= end && fits(frame + shift))
          frame + shift: key,
      for (final MapEntry(key: offset, value: key) in keys.entries)
        if (fits(start + offset)) start + offset: key as PropertyKey<U>,
      if (last != null && last >= end && shift > 0) last: ?lane.keys[last],
    },
  );
  return next == lane ? null : next;
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
