import 'dart:collection';

import '../core/collection_equality.dart';
import 'key_side.dart';
import 'non_negative_index_map.dart';

export 'key_side.dart';

/// One keyframe of a single property.
class PropertyKey<T> {
  const PropertyKey(
    this.value, {
    this.incoming = KeySide.linear,
    this.outgoing = KeySide.linear,
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

  /// The key's NAME, and with it a link: keys sharing a name inside one
  /// naming space hold the same value, exactly the way frame names mean
  /// "the same drawing" (user 2026-07-30). Null is the ordinary unnamed
  /// key — duplicates are free and nothing is shared.
  ///
  /// Lives on the key rather than in a registry because the link is
  /// DERIVED from the name; there is no identity to keep somewhere else.
  final String? name;

  /// What a name hands every key it links: the number and both sides.
  NamedKeyValue<T> get held =>
      (value: value, incoming: incoming, outgoing: outgoing);

  PropertyKey<T> copyWith({
    T? value,
    KeySide? incoming,
    KeyExit? outgoing,
    String? Function()? name,
  }) {
    return PropertyKey(
      value ?? this.value,
      incoming: incoming ?? this.incoming,
      outgoing: outgoing ?? this.outgoing,
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
  int get hashCode => Object.hash(value, incoming, outgoing, name);

  @override
  String toString() =>
      'PropertyKey($value, $incoming → $outgoing'
      '${name == null ? '' : ', $name'})';
}

/// What the values of a track are to its resolver: how to stand between
/// two of them ([lerp]) and where a third falls on the way from one to the
/// other ([inverseLerp] — the first 0, the second 1), which is how an auto
/// side reads its neighbours. One object, so the two answers cannot come
/// from different spaces.
class KeyValueSpace<T> {
  const KeyValueSpace({required this.lerp, required this.inverseLerp});

  final T Function(T a, T b, double t) lerp;

  /// Where [value] falls along the line from [a] to [b] — 0 when the two
  /// are one value and there is no line to fall on.
  final double Function(T a, T b, T value) inverseLerp;
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

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;

  PropertyKey<T>? keyAt(int frameIndex) => keys[frameIndex];

  PropertyTrack<T> withKey(
    int frameIndex,
    T value, {
    KeySide? incoming,
    KeyExit? outgoing,
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
          // on every drag.
          incoming: incoming ?? existing?.incoming ?? KeySide.linear,
          outgoing: outgoing ?? existing?.outgoing ?? KeySide.linear,
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
        next[entry.key] = key.copyWith(
          value: linked.value,
          incoming: linked.incoming,
          outgoing: linked.outgoing,
        );
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
  /// earliest key in range. Its SIDES ride across with its value.
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
      final landing = adopted ?? standing ?? keys[keyed.first]!;
      for (final frame in keyed) {
        if (next.keys[frame]!.held != landing.held) {
          next = next.withKey(
            frame,
            landing.value,
            incoming: landing.incoming,
            outgoing: landing.outgoing,
          );
        }
      }
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
  }) {
    Map<int, PropertyKey<T>>? next;
    for (final frame in frames) {
      final key = keys[frame];
      if (key == null) {
        continue;
      }
      final sides = edit.applyTo(
        incoming: key.incoming,
        outgoing: key.outgoing,
      );
      if (sides.incoming == key.incoming && sides.outgoing == key.outgoing) {
        continue;
      }
      (next ??= Map<int, PropertyKey<T>>.of(keys))[frame] = key.copyWith(
        incoming: sides.incoming,
        outgoing: sides.outgoing,
      );
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
  /// value printed at a frame are one reading of the track. A key is only
  /// ever ON a frame: between two, the segment they bound answers.
  T resolveAtTime({
    required double time,
    required T Function() orElse,
    required KeyValueSpace<T> space,
  }) {
    if (isEmpty) {
      return orElse();
    }

    final frame = time.floor();
    if (frame == time) {
      final exact = keys[frame];
      if (exact != null) {
        return exact.value;
      }
    }

    final previousIndex = keys.lastKeyBefore(frame + 1);
    final nextIndex = keys.firstKeyAfter(frame);
    if (previousIndex == null) {
      return keys[nextIndex!]!.value;
    }
    if (nextIndex == null) {
      return keys[previousIndex]!.value;
    }

    final from = keys[previousIndex]!;
    final to = keys[nextIndex]!;
    // A hold freezes the segment on the key it leaves.
    final leaving = from.outgoing;
    if (leaving is! KeySide) {
      return from.value;
    }
    final span = nextIndex - previousIndex;
    double along(T value) => space.inverseLerp(from.value, to.value, value);
    final progress = segmentProgress(
      (time - previousIndex) / span,
      leaving: keyHandleOf(leaving, () {
        final before = keys.lastKeyBefore(previousIndex);
        return before == null
            ? linearKeyHandle.speed
            : autoSideSpeed(
                (1 - along(keys[before]!.value)) * span / (nextIndex - before),
              );
      }),
      arriving: keyHandleOf(to.incoming, () {
        final after = keys.firstKeyAfter(nextIndex);
        return after == null
            ? linearKeyHandle.speed
            : autoSideSpeed(
                along(keys[after]!.value) * span / (after - previousIndex),
              );
      }),
    );
    return space.lerp(from.value, to.value, progress);
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
        if (entry.value.name != null) 'name': entry.value.name,
      },
  ];

  static PropertyTrack<T> fromJson<T>(
    List<dynamic>? json,
    T Function(Object? value) decodeValue,
  ) {
    final keys = <int, PropertyKey<T>>{};
    for (final item in json ?? const []) {
      final entry = item as Map<String, dynamic>;
      final index = entry['index'] as int;
      if (keys.containsKey(index)) {
        throw FormatException('Duplicate property key index: $index');
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

/// What a named key hands its link: the number AND both of its sides
/// ([PropertyKey.held]).
///
/// 🗣️유저 2026-09-12: 「겸용컷끼리 홀드/리니어타입 링크안되는건가?
/// 싹다링크해야하는데」 — a name is ONE key seen in several places, so they
/// travel together or the link is only half there.
typedef NamedKeyValue<T> = ({T value, KeySide incoming, KeyExit outgoing});

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
