import 'dart:collection';
import 'dart:math' as math;

import '../core/collection_equality.dart';
import 'key_path.dart';
import 'key_side.dart';
import 'non_negative_index_map.dart';

export 'key_path.dart';
export 'key_side.dart';

/// One keyframe of a single property.
class PropertyKey<T> {
  const PropertyKey(
    this.value, {
    this.incoming = KeySide.linear,
    this.outgoing = KeySide.linear,
    this.path = KeyPath.straight,
    this.roving = false,
    this.name,
  });

  final T value;

  /// How the segment ARRIVING at this key ends — AE's incoming temporal
  /// interpolation.
  final KeySide incoming;

  /// How the segment LEAVING this key starts, or the hold that freezes it
  /// — AE's outgoing (the staple of stepped 2D animation and the sheet's
  /// SLIDE notation is that hold).
  final KeyExit outgoing;

  /// How the path the value walks in space passes through the key — a
  /// position lane's (I-89 ④); every other lane's keys are straight.
  final KeyPath path;

  /// Whether the key's TIME is its run's to place — After Effects' Rove
  /// Across Time (I-89 ①: 「위치에만, 처음 · 끝 키 시간 고정, 가운데 키는
  /// 시간을 풀어 속도를 고르게」). Between the fixed keys either side, the
  /// value walks the path through it at the pace those two set, and the
  /// key stands on the frame nearest where that walk passes it
  /// ([PropertyTrack.withRovingKeysSlotted]). A position lane's alone; the
  /// first and the last key are fixed.
  final bool roving;

  /// The key's NAME, and with it a link: keys sharing a name inside one
  /// naming space hold the same value, exactly the way frame names mean
  /// "the same drawing" (user 2026-07-30). Null is the ordinary unnamed
  /// key — duplicates are free and nothing is shared.
  ///
  /// Lives on the key rather than in a registry because the link is
  /// DERIVED from the name; there is no identity to keep somewhere else.
  final String? name;

  /// What a name hands every key it links: the number, both sides, the
  /// path through it and whether its time roves.
  NamedKeyValue<T> get held => (
    value: value,
    incoming: incoming,
    outgoing: outgoing,
    path: path,
    roving: roving,
  );

  /// This key holding [held] — its name kept: what a link lands on every
  /// key it reaches, and what naming a range lands on the keys it names.
  PropertyKey<T> withHeld(NamedKeyValue<T> held) => PropertyKey(
    held.value,
    incoming: held.incoming,
    outgoing: held.outgoing,
    path: held.path,
    roving: held.roving,
    name: name,
  );

  PropertyKey<T> copyWith({
    T? value,
    KeySide? incoming,
    KeyExit? outgoing,
    KeyPath? path,
    bool? roving,
    String? Function()? name,
  }) {
    return PropertyKey(
      value ?? this.value,
      incoming: incoming ?? this.incoming,
      outgoing: outgoing ?? this.outgoing,
      path: path ?? this.path,
      roving: roving ?? this.roving,
      // A closure so a key can be UNnamed (the plain-nullable convention
      // cannot say "clear it").
      name: name == null ? this.name : name(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyKey<T> && other.held == held && other.name == name;

  @override
  int get hashCode =>
      Object.hash(value, incoming, outgoing, path, roving, name);

  @override
  String toString() =>
      'PropertyKey($value, $incoming → $outgoing'
      '${path == KeyPath.straight ? '' : ', $path'}'
      '${roving ? ', roving' : ''}'
      '${name == null ? '' : ', $name'})';
}

/// What the values of a track are to its resolver: how to stand between
/// two of them ([lerp]) and where a third falls on the way from one to the
/// other ([inverseLerp] — the first 0, the second 1), which is how an auto
/// side reads its neighbours. One object, so the two answers cannot come
/// from different spaces.
class KeyValueSpace<T> {
  const KeyValueSpace({
    required this.lerp,
    required this.inverseLerp,
    this.walk,
  });

  final T Function(T a, T b, double t) lerp;

  /// Where [value] falls along the line from [a] to [b] — 0 when the two
  /// are one value and there is no line to fall on.
  final double Function(T a, T b, T value) inverseLerp;

  /// The walk along the segment from the key at frame `from` to the key at
  /// frame `to` of [keys], where the values walk a path the keys shape (a
  /// position lane's, I-89 ④) — [lerp] between the two values where it is
  /// null, and no key roves there ([PropertyKey.roving]). A track lays a
  /// segment's walk once and asks it for every point along it
  /// ([PropertyTrack.resolveAtTime]).
  final SegmentWalker<T>? walk;
}

/// What lays a [SegmentWalk]: the way from the key at frame `from` to the
/// key at frame `to` of `keys`.
typedef SegmentWalker<T> =
    SegmentWalk<T> Function(
      SplayTreeMap<int, PropertyKey<T>> keys,
      int from,
      int to,
    );

/// Where a segment between two keys stands at a `progress` of its way
/// ([at]), and how long that way is — what a run of segments shares its
/// way out by, a roving key's (I-89 ④) ([KeyValueSpace.walk]).
typedef SegmentWalk<T> = ({T Function(double progress) at, double length});

/// The walk from a fixed key to the next through every roving key between
/// them (I-89 ④), by distance: each segment's share of the way is its
/// length's. A run of one segment is that segment, read as it is.
final class _RunWalk<T> {
  _RunWalk(this.segments) : stops = _stopsAlong(segments);

  final List<SegmentWalk<T>> segments;

  /// The share of the way at which the walk passes each key it goes
  /// through — the first 0, the last 1; evenly spaced where the way has no
  /// length to share.
  final List<double> stops;

  static List<double> _stopsAlong(List<SegmentWalk<Object?>> segments) {
    final total = segments.fold(0.0, (sum, segment) => sum + segment.length);
    if (total <= 0) {
      return [
        for (var index = 0; index <= segments.length; index += 1)
          index / segments.length,
      ];
    }
    var reached = 0.0;
    return [
      0,
      for (final segment in segments) (reached += segment.length) / total,
    ];
  }

  T at(double progress) {
    if (segments.length == 1) {
      return segments.single.at(progress);
    }
    var index = 0;
    while (index < segments.length - 1 && progress > stops[index + 1]) {
      index += 1;
    }
    final from = stops[index];
    final share = stops[index + 1] - from;
    return segments[index].at(share <= 0 ? 0 : (progress - from) / share);
  }
}

/// The pace of a way between two fixed keys: the leaving side of the one
/// and the arriving side of the other, as handles ([segmentProgress]).
typedef KeyPace = ({KeyHandle leaving, KeyHandle arriving});

/// The share of a way's time at which its [pace] has come [share] of the
/// way — [segmentProgress] read back; a crossing of it where a speed asks
/// for an overshoot.
double _timeAtShare(double share, KeyPace pace) {
  var lo = 0.0;
  var hi = 1.0;
  for (var step = 0; step < 50; step += 1) {
    final mid = (lo + hi) / 2;
    final reached = segmentProgress(
      mid,
      leaving: pace.leaving,
      arriving: pace.arriving,
    );
    if (reached < share) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// A single animated property, keyed independently of every other property
/// (the After Effects model: Position can carry three keys while Scale
/// carries none).
///
/// Resolution semantics ([resolveAt]): exact keys win; frames before the
/// first key hold the first value and frames after the last hold the last;
/// between two keys the segment moves as the out side of the key it leaves
/// and the in side of the key it reaches say ([segmentProgress]) — a hold
/// freezes it. An empty track means "no animation" — consumers supply
/// their own default.
class PropertyTrack<T> {
  PropertyTrack({Map<int, PropertyKey<T>>? keys})
    : keys = nonNegativeIndexedCopy(
        keys ?? const {},
        argumentName: 'keys',
        indexNoun: 'Property key',
      );

  factory PropertyTrack.empty() => PropertyTrack();

  final SplayTreeMap<int, PropertyKey<T>> keys;

  /// The walk a [KeyValueSpace.walk] laid of each way asked along — a
  /// segment, or a run through roving keys — by the frame it starts on: a
  /// position's curve, measured once and read again for every point asked
  /// along it (a trail or a header graph asks for hundreds). The keys never
  /// change under it: an edit is a new track.
  Map<int, _RunWalk<T>>? _walked;

  /// Whether a key roves here ([PropertyKey.roving]).
  late final bool _anyRoving = keys.values.any((key) => key.roving);

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;

  PropertyKey<T>? keyAt(int frameIndex) => keys[frameIndex];

  PropertyTrack<T> withKey(
    int frameIndex,
    T value, {
    KeySide? incoming,
    KeyExit? outgoing,
    KeyPath? path,
  }) {
    final existing = keys[frameIndex];
    return PropertyTrack(
      keys: {
        ...keys,
        frameIndex: PropertyKey(
          value,
          // A key's NAME and its TYPE both survive a value edit: they are
          // the key's identity, not part of what it holds. 🗣️유저
          // 2026-09-12: 「홀드인상태서 캔버스쪽 직접 컨트롤해서 값 바꾸면
          // 홀드가 리니어로 돌아와」 — the camera's pose facade writes
          // through here with no type to hand over, and the hold was gone
          // on every drag. Its PATH survives it the same way: a key dragged
          // across the canvas keeps the curve it was given (I-89 ④).
          incoming: incoming ?? existing?.incoming ?? KeySide.linear,
          outgoing: outgoing ?? existing?.outgoing ?? KeySide.linear,
          path: path ?? existing?.path ?? KeyPath.straight,
          name: existing?.name,
        ),
      },
    );
  }

  /// Every key inside [rangeStartIndex, [rangeEndIndexExclusive]) shifted
  /// by [frameDelta] — the ONE loop of the lane-scoped range move
  /// (UI-R23 #3 part 2), shared by the transform, effect and name-tag
  /// families so the rigid all-or-nothing discipline cannot fork. Null
  /// when nothing moves, a landing dips below 0, or a landing collides
  /// with an UNSHIFTED key on this lane (the block discipline: nothing
  /// merges silently).
  PropertyTrack<T>? withRangedKeysShifted({
    required int rangeStartIndex,
    required int rangeEndIndexExclusive,
    required int frameDelta,
  }) {
    final moved = <int>{
      for (final frame in keys.keys)
        if (frame >= rangeStartIndex && frame < rangeEndIndexExclusive) frame,
    };
    if (moved.isEmpty) {
      return null;
    }
    final next = <int, PropertyKey<T>>{
      for (final entry in keys.entries)
        if (!moved.contains(entry.key)) entry.key: entry.value,
    };
    for (final frame in moved) {
      final landing = frame + frameDelta;
      if (landing < 0 || next.containsKey(landing)) {
        return null;
      }
      next[landing] = keys[frame]!;
    }
    return PropertyTrack(keys: next);
  }

  /// [frameIndex]'s key with a new [name] (null clears it). A no-op when
  /// no key sits there.
  PropertyTrack<T> withKeyName(int frameIndex, String? name) {
    final key = keys[frameIndex];
    if (key == null) {
      return this;
    }
    return PropertyTrack(
      keys: {...keys, frameIndex: key.copyWith(name: () => name)},
    );
  }

  /// Every key called [name] set to [held] — the link "same name, same
  /// key" applied to this track.
  ///
  /// The write that starts a propagation runs this over its own track and
  /// over every other track sharing the naming space, so a named key edited
  /// in one place moves everywhere it appears.
  PropertyTrack<T> withNamedKey(String name, NamedKeyValue<T> held) =>
      withNamedKeys({name: held});

  /// [this] with every key whose name appears in [held] set to that name's
  /// value AND sides — the many-names form of [withNamedKey].
  ///
  /// One transform write can move several named keys at once (a pose key
  /// touches position, scale and rotation together), so the link applies
  /// them in one pass rather than rebuilding the track per name.
  PropertyTrack<T> withNamedKeys(Map<String, NamedKeyValue<T>> held) {
    if (held.isEmpty || keys.isEmpty) {
      return this;
    }
    var changed = false;
    final next = <int, PropertyKey<T>>{};
    for (final entry in keys.entries) {
      final key = entry.value;
      final name = key.name;
      final linked = name == null ? null : held[name];
      if (linked != null && key.held != linked) {
        next[entry.key] = key.withHeld(linked);
        changed = true;
        continue;
      }
      next[entry.key] = key;
    }
    return changed ? PropertyTrack(keys: next) : this;
  }

  /// The key the name [name] holds here, or null when this track does not
  /// use the name.
  ///
  /// The link IS "same name, same key", so every match holds the same
  /// number and the same sides, and the first one speaks for all of them.
  /// This is the read a rename does before it commits: joining a name
  /// adopts what the name ALREADY holds, the way linking a frame adopts
  /// the drawing that is already there rather than overwriting it (user
  /// 2026-08-10).
  /// [excludeFrames] drops keys a RANGE rename is about to name: those are
  /// the keys doing the joining, so they must not answer for the name they
  /// are joining. "Is it taken?" and "what does it hold?" are the same
  /// question, so they stay one method — a range asks it with the range
  /// excluded, a single key with nothing excluded.
  PropertyKey<T>? keyForName(
    String name, {
    Set<int> excludeFrames = const {},
  }) {
    for (final entry in keys.entries) {
      if (entry.value.name == name && !excludeFrames.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// [this] with every key at [frames] named [name] — and, when named, all
  /// of them collapsed onto ONE value. Null when nothing here changed.
  ///
  /// ★The collapse IS the intent, not a side effect (user 2026-08-10:
  /// "같은행 여러키 이름변경할때 한값으로 뭉개는거 맞음. 그게 의도"). A
  /// name MEANS "same value", so asking for one name across five keys is
  /// asking for exactly that. Un-naming (a null [name]) touches no values:
  /// there is no shared number left to agree on.
  ///
  /// Which KEY they land on, in order: [adopted] when the name already
  /// holds one somewhere (joining adopts, the frame-link rule), else the
  /// key at [preferredFrame] — the one you are standing on — else the
  /// earliest key in range. Its SIDES ride across with its value, and its
  /// path and whether its time roves (I-89 ④).
  ///
  /// ⛔This REVERSES "interpolation rides across untouched; adopting a
  /// value must not restyle the segment leaving a key" (mine, no user
  /// behind it). 🗣️유저 2026-09-12: 「겸용컷끼리 홀드/리니어타입
  /// 링크안되는건가? 싹다링크해야하는데」 — a name is ONE key seen in
  /// several places, and a joined key holding the name's number with its
  /// own hold is exactly the half-link they reported.
  PropertyTrack<T>? withRangeNamed({
    required Set<int> frames,
    required String? name,
    PropertyKey<T>? adopted,
    int? preferredFrame,
  }) {
    final keyed = frames.where((frame) => keys[frame] != null).toList()..sort();
    if (keyed.isEmpty) {
      return null;
    }
    var next = this;
    if (name != null) {
      // The standing key only speaks for a range it is IN. Reading it from
      // outside would let the playhead's number reach in and overwrite a
      // key it was never pointing at — which is what naming one far-away
      // key did before this guard.
      final standing = preferredFrame != null && keyed.contains(preferredFrame)
          ? keys[preferredFrame]
          : null;
      final landing = (adopted ?? standing ?? keys[keyed.first]!).held;
      next =
          _withKeysAt(
            keyed.toSet(),
            (key) => key.held == landing ? null : key.withHeld(landing),
          ) ??
          this;
    }
    for (final frame in keyed) {
      next = next.withKeyName(frame, name);
    }
    return next == this ? null : next;
  }

  /// The keys inside [frames] with [edit]'s sides — the TYPE half of the
  /// key window, in the range form the name half already has (F-17, 유저
  /// 2026-09-01: 「해당 키 공용 편집창 손봐서 이름변경이랑 오른쪽에 유니언
  /// 타입 변경 두개 존재하도록」). Values and names ride across untouched.
  /// Null when nothing here changed.
  PropertyTrack<T>? withKeySides({
    required Set<int> frames,
    required KeySidesEdit edit,
  }) => _withKeysAt(frames, (key) {
    final sides = edit.applyTo(incoming: key.incoming, outgoing: key.outgoing);
    return sides.incoming == key.incoming && sides.outgoing == key.outgoing
        ? null
        : key.copyWith(incoming: sides.incoming, outgoing: sides.outgoing);
  });

  /// The keys inside [frames] bending through as [curved] says — the PATH
  /// half of the key window (I-89 ④-Q4, A while it is asked): a corner
  /// made a curve is laid smooth by its neighbours ([KeyPath.auto]), a key
  /// already curved keeps its handle, and a straight one has none. Values,
  /// sides and names ride across untouched. Null when nothing here changed.
  PropertyTrack<T>? withKeyPaths({
    required Set<int> frames,
    required bool curved,
  }) => _withKeysAt(
    frames,
    (key) => key.path.curved == curved
        ? null
        : key.copyWith(path: curved ? KeyPath.auto : KeyPath.straight),
  );

  /// The keys inside [frames] roving as [roving] says — the time half of
  /// the key window (I-89 ④-Q5, A′ while it is asked): a key's time left to
  /// its run to place ([PropertyKey.roving]), or held where it stands. The
  /// first and the last key keep their time by where they are, and are
  /// left. Values, sides, paths and names ride across untouched. Null when
  /// nothing here changed.
  PropertyTrack<T>? withKeysRoving({
    required Set<int> frames,
    required bool roving,
  }) => isEmpty
      ? null
      : _withKeysAt(
          frames.difference({keys.firstKey(), keys.lastKey()}),
          (key) => key.roving == roving ? null : key.copyWith(roving: roving),
        );

  /// The key at [frame] bending through as [path] says — a handle the hand
  /// placed on the canvas (I-89 ④). Its value, sides and name ride across
  /// untouched. Null where no key stands or it already bends so.
  PropertyTrack<T>? withKeyPath(int frame, KeyPath path) => _withKeysAt(
    {frame},
    (key) => key.path == path ? null : key.copyWith(path: path),
  );

  /// The keys inside [frames] as [edit] leaves each — null where it changes
  /// it not — or null when it changed none.
  PropertyTrack<T>? _withKeysAt(
    Set<int> frames,
    PropertyKey<T>? Function(PropertyKey<T> key) edit,
  ) {
    Map<int, PropertyKey<T>>? next;
    for (final frame in frames) {
      final key = keys[frame];
      final edited = key == null ? null : edit(key);
      if (edited != null) {
        (next ??= Map<int, PropertyKey<T>>.of(keys))[frame] = edited;
      }
    }
    return next == null ? null : PropertyTrack(keys: next);
  }

  /// The NAMED keys by frame — what a lane row hands its band so the link
  /// is visible where it lives. Frames absent here are unnamed.
  Map<int, String> get namedKeysByFrame => {
    for (final entry in keys.entries)
      if (entry.value.name case final String name) entry.key: name,
  };

  /// Each key's two sides by frame — what a header graph's handles stand
  /// for (I-89 ③).
  Map<int, ({KeySide incoming, KeyExit outgoing})> get sidesByFrame => {
    for (final MapEntry(key: frame, value: key) in keys.entries)
      frame: (incoming: key.incoming, outgoing: key.outgoing),
  };

  /// The names this track uses, in frame order — what a naming space asks
  /// for when it checks whether a name is already taken.
  Set<String> get keyNames => {
    for (final key in keys.values)
      if (key.name != null) key.name!,
  };

  PropertyTrack<T> withoutKey(int frameIndex) {
    final next = Map<int, PropertyKey<T>>.of(keys)..remove(frameIndex);
    return PropertyTrack(keys: next);
  }

  /// Resolves the property value at [frameIndex]; [orElse] supplies the
  /// empty-track default and [space] what the values are made of.
  T resolveAt({
    required int frameIndex,
    required T Function() orElse,
    required KeyValueSpace<T> space,
  }) => resolveAtTime(
    time: frameIndex.toDouble(),
    orElse: orElse,
    space: space,
  );

  /// [resolveAt] at a [time] between two frames as well as on one — what a
  /// header graph (I-89 ③) draws its curve through, so the line and the
  /// value printed at a frame are one reading of the track. A key that
  /// keeps its time is only ever ON a frame: between two, the way they
  /// bound answers.
  ///
  /// A roving key's time is its run's (I-89 ④): where keys rove, time sees
  /// the keys that keep theirs alone, and the way between two of them walks
  /// through every roving key between, at the pace those two set — a
  /// roving key's frame says where it stands, not when it is passed.
  T resolveAtTime({
    required double time,
    required T Function() orElse,
    required KeyValueSpace<T> space,
  }) {
    if (isEmpty) {
      return orElse();
    }
    final walk = space.walk;
    final roves = walk != null && _anyRoving;

    final frame = time.floor();
    if (frame == time) {
      final exact = keys[frame];
      if (exact != null && _keepsItsTime(frame, roves: roves)) {
        return exact.value;
      }
    }

    final previousIndex = _timedKeyBefore(frame + 1, roves: roves);
    final nextIndex = _timedKeyAfter(frame, roves: roves);
    if (previousIndex == null) {
      return keys[nextIndex!]!.value;
    }
    if (nextIndex == null) {
      return keys[previousIndex]!.value;
    }

    final from = keys[previousIndex]!;
    // A hold freezes the segment on the key it leaves.
    if (from.outgoing is! KeySide) {
      return from.value;
    }
    final pace = _paceBetween(previousIndex, nextIndex, space, roves: roves);
    final progress = segmentProgress(
      (time - previousIndex) / (nextIndex - previousIndex),
      leaving: pace.leaving,
      arriving: pace.arriving,
    );
    if (walk == null) {
      return space.lerp(from.value, keys[nextIndex]!.value, progress);
    }
    return _walkFrom(previousIndex, nextIndex, walk).at(progress);
  }

  /// Whether the key at [frame] keeps its own time: every key, but a
  /// roving one between the first and the last where keys [roves].
  bool _keepsItsTime(int frame, {required bool roves}) =>
      !roves ||
      !keys[frame]!.roving ||
      frame == keys.firstKey() ||
      frame == keys.lastKey();

  /// The last key before [frame] that keeps its own time.
  int? _timedKeyBefore(int frame, {required bool roves}) {
    var at = keys.lastKeyBefore(frame);
    while (at != null && !_keepsItsTime(at, roves: roves)) {
      at = keys.lastKeyBefore(at);
    }
    return at;
  }

  /// The first key after [frame] that keeps its own time.
  int? _timedKeyAfter(int frame, {required bool roves}) {
    var at = keys.firstKeyAfter(frame);
    while (at != null && !_keepsItsTime(at, roves: roves)) {
      at = keys.firstKeyAfter(at);
    }
    return at;
  }

  /// The pace of the way from the timed key at [from] to the next, at
  /// [to]: the leaving side of the one — straight where it holds, which a
  /// hold's run is placed by ([rovingTimes]) — and the arriving side of the
  /// other. An auto side reads the timed keys either side of the way, how
  /// far along it they stand.
  KeyPace _paceBetween(
    int from,
    int to,
    KeyValueSpace<T> space, {
    required bool roves,
  }) {
    final start = keys[from]!;
    final end = keys[to]!;
    final span = to - from;
    double along(T value) => space.inverseLerp(start.value, end.value, value);
    final leaving = start.outgoing;
    return (
      leaving: leaving is KeySide
          ? keyHandleOf(leaving, () {
              final before = _timedKeyBefore(from, roves: roves);
              return before == null
                  ? linearKeyHandle.speed
                  : autoSideSpeed(
                      (1 - along(keys[before]!.value)) * span / (to - before),
                    );
            })
          : linearKeyHandle,
      arriving: keyHandleOf(end.incoming, () {
        final after = _timedKeyAfter(to, roves: roves);
        return after == null
            ? linearKeyHandle.speed
            : autoSideSpeed(along(keys[after]!.value) * span / (after - from));
      }),
    );
  }

  /// The way from the timed key at [from] to the next, at [to], through
  /// every key between — each of them roving — laid once ([_walked]).
  _RunWalk<T> _walkFrom(int from, int to, SegmentWalker<T> walk) =>
      (_walked ??= {})[from] ??= _RunWalk([
        for (final (start, end) in _stepsBetween(from, to))
          walk(keys, start, end),
      ]);

  /// Each key from [from] to [to] with the one after it, in order.
  Iterable<(int, int)> _stepsBetween(int from, int to) sync* {
    var at = from;
    while (at < to) {
      final next = keys.firstKeyAfter(at)!;
      yield (at, next);
      at = next;
    }
  }

  /// When the walk through each roving key's run passes it, by its frame
  /// ([resolveAtTime]): its share of the way, at the pace the run's timed
  /// ends set — a hold's run as if it did not hold, since its hold passes
  /// none of them. Empty where no key roves or [space] walks no path.
  Map<int, double> rovingTimes(KeyValueSpace<T> space) {
    final walk = space.walk;
    final times = <int, double>{};
    if (walk == null || !_anyRoving) {
      return times;
    }
    for (var from = keys.firstKey(); from != null;) {
      final to = _timedKeyAfter(from, roves: true);
      if (to == null) {
        break;
      }
      final stops = _walkFrom(from, to, walk).stops;
      if (stops.length > 2) {
        final pace = _paceBetween(from, to, space, roves: true);
        var passed = 0;
        for (final (_, frame) in _stepsBetween(from, to)) {
          passed += 1;
          if (frame != to) {
            times[frame] =
                from + (to - from) * _timeAtShare(stops[passed], pace);
          }
        }
      }
      from = to;
    }
    return times;
  }

  /// [this] with each roving key on the frame nearest when its run passes
  /// it ([rovingTimes]) — in their order, one to a frame, between the
  /// run's timed ends — and the first and the last key, whose time is
  /// their own (I-89 ①: 「처음 · 끝 키 시간 고정」), not roving. Where
  /// [space] walks no path, no key roves. [this] where every key already
  /// stands so.
  ///
  /// It always fits: a run's keys stood on frames of their own between its
  /// ends. Where they go is read off the timed keys and the way's lengths
  /// alone, never off where they stood, so a placed track stays as it is.
  PropertyTrack<T> withRovingKeysSlotted(KeyValueSpace<T> space) {
    if (!_anyRoving) {
      return this;
    }
    PropertyKey<T>? timed(PropertyKey<T> key) =>
        key.roving ? key.copyWith(roving: false) : null;
    if (space.walk == null) {
      return _withKeysAt(keys.keys.toSet(), timed)!;
    }
    final ends = _withKeysAt({keys.firstKey()!, keys.lastKey()!}, timed);
    if (ends != null) {
      return ends.withRovingKeysSlotted(space);
    }
    final times = rovingTimes(space);
    final placed = <int, int>{};
    for (var from = keys.firstKey(); from != null;) {
      final to = _timedKeyAfter(from, roves: true);
      if (to == null) {
        break;
      }
      final run = [
        for (final (_, frame) in _stepsBetween(from, to))
          if (frame != to) frame,
      ];
      var before = from;
      for (var index = 0; index < run.length; index += 1) {
        final nearest = times[run[index]]!.round();
        final within = math.min(
          math.max(nearest, from + index + 1),
          to - (run.length - index),
        );
        before = math.max(before + 1, within);
        placed[run[index]] = before;
      }
      from = to;
    }
    if (placed.entries.every((entry) => entry.key == entry.value)) {
      return this;
    }
    return PropertyTrack(
      keys: {
        for (final MapEntry(key: frame, :value) in keys.entries)
          placed[frame] ?? frame: value,
      },
    );
  }

  List<Map<String, dynamic>> toJson(Object? Function(T value) encodeValue) => [
    for (final entry in keys.entries)
      {
        'index': entry.key,
        'value': encodeValue(entry.value.value),
        if (entry.value.incoming != KeySide.linear)
          'in': entry.value.incoming.toJson(),
        if (entry.value.outgoing != KeySide.linear)
          'out': entry.value.outgoing.toJson(),
        if (entry.value.path.toJson() case final Object path) 'path': path,
        if (entry.value.roving) 'rove': true,
        if (entry.value.name != null) 'name': entry.value.name,
      },
  ];

  /// [toJson] read back. A key may rove only on a lane whose keys walk a
  /// path ([roves]); one that roves anywhere else is a file this build
  /// cannot read, and says so.
  static PropertyTrack<T> fromJson<T>(
    List<dynamic>? json,
    T Function(Object? value) decodeValue, {
    bool roves = false,
  }) {
    final keys = <int, PropertyKey<T>>{};
    for (final item in json ?? const []) {
      final entry = item as Map<String, dynamic>;
      final index = entry['index'] as int;
      if (keys.containsKey(index)) {
        throw FormatException('Duplicate property key index: $index');
      }
      final roving = entry['rove'] == true;
      if (roving && !roves) {
        throw FormatException('A key roves on a lane walking no path: $index');
      }
      final incoming = entry['in'];
      final outgoing = entry['out'];
      keys[index] = PropertyKey(
        decodeValue(entry['value']),
        incoming: incoming == null
            ? KeySide.linear
            : KeySide.fromJson(incoming),
        outgoing: outgoing == null
            ? KeySide.linear
            : KeyExit.fromJson(outgoing),
        path: KeyPath.fromJson(entry['path']),
        roving: roving,
        name: entry['name'] as String?,
      );
    }
    return PropertyTrack(keys: keys);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyTrack<T> && mapEquals(other.keys, keys);

  @override
  int get hashCode => Object.hashAll(
    keys.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );

  @override
  String toString() => 'PropertyTrack(keys: $keys)';
}

/// What a named key hands its link: the number AND both of its sides AND
/// the path through it AND whether its time roves ([PropertyKey.held]).
///
/// 🗣️유저 2026-09-12: 「겸용컷끼리 홀드/리니어타입 링크안되는건가?
/// 싹다링크해야하는데」 — a name is ONE key seen in several places, so they
/// travel together or the link is only half there.
typedef NamedKeyValue<T> = ({
  T value,
  KeySide incoming,
  KeyExit outgoing,
  KeyPath path,
  bool roving,
});

/// The named keys one track edit MOVED between [before] and [after] — what
/// it hands the "same name, same key" link.
///
/// A RENAME carries nothing, and neither does a key that ARRIVES already
/// named: joining a name adopts what that name ALREADY holds, which the
/// rename verb pulls before it commits (the frame-link rule, user
/// 2026-08-10). That is why a key whose NAME changed is skipped rather than
/// trusted to have moved nothing — a joining key carrying its own hold
/// would otherwise impose it on every key the name reaches.
Map<String, NamedKeyValue<T>> movedNamedKeys<T>(
  PropertyTrack<T> before,
  PropertyTrack<T> after,
) {
  final moved = <String, NamedKeyValue<T>>{};
  if (after.isEmpty) {
    return moved;
  }
  for (final entry in after.keys.entries) {
    final key = entry.value;
    final name = key.name;
    if (name == null) {
      continue;
    }
    final old = before.keys[entry.key];
    if (old == null || old.name != name || old.held == key.held) {
      continue;
    }
    moved[name] = key.held;
  }
  return moved;
}
