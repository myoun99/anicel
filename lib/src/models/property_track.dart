import 'dart:collection';

import '../core/collection_equality.dart';

/// AE-style temporal interpolation OUT of a key: how the segment between
/// this key and the next one moves.
enum PropertyKeyInterpolation {
  /// Linear ramp to the next key (AE default).
  linear,

  /// Freeze on this key's value until the next key (AE hold keyframe) —
  /// the staple of stepped 2D animation and the sheet's SLIDE notation.
  hold;

  String toJson() => name;

  static PropertyKeyInterpolation fromJson(Object? json) =>
      values.asNameMap()[json] ?? PropertyKeyInterpolation.linear;
}

/// One keyframe of a single transform property.
class PropertyKey<T> {
  const PropertyKey(
    this.value, {
    this.interpolation = PropertyKeyInterpolation.linear,
    this.name,
  });

  final T value;

  /// Interpolation of the segment LEAVING this key.
  final PropertyKeyInterpolation interpolation;

  /// The key's NAME, and with it a link: keys sharing a name inside one
  /// naming space hold the same value, exactly the way frame names mean
  /// "the same drawing" (user 2026-07-30). Null is the ordinary unnamed
  /// key — duplicates are free and nothing is shared.
  ///
  /// Lives on the key rather than in a registry because the link is
  /// DERIVED from the name; there is no identity to keep somewhere else.
  final String? name;

  PropertyKey<T> copyWith({
    T? value,
    PropertyKeyInterpolation? interpolation,
    String? Function()? name,
  }) {
    return PropertyKey(
      value ?? this.value,
      interpolation: interpolation ?? this.interpolation,
      // A closure so a key can be UNnamed (the plain-nullable convention
      // cannot say "clear it").
      name: name == null ? this.name : name(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyKey<T> &&
          other.value == value &&
          other.interpolation == interpolation &&
          other.name == name;

  @override
  int get hashCode => Object.hash(value, interpolation, name);

  @override
  String toString() =>
      'PropertyKey($value, $interpolation${name == null ? '' : ', $name'})';
}

/// A single animated property, keyed independently of every other property
/// (the After Effects model: Position can carry three keys while Scale
/// carries none).
///
/// Resolution semantics ([resolveAt]): exact keys win; frames before the
/// first key hold the first value and frames after the last hold the last;
/// between two keys the PREVIOUS key's interpolation decides — linear
/// ramps, hold freezes. An empty track means "no animation" — consumers
/// supply their own default.
class PropertyTrack<T> {
  PropertyTrack({Map<int, PropertyKey<T>>? keys})
    : keys = _immutableKeys(keys ?? const {});

  factory PropertyTrack.empty() => PropertyTrack();

  final SplayTreeMap<int, PropertyKey<T>> keys;

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;

  PropertyKey<T>? keyAt(int frameIndex) => keys[frameIndex];

  PropertyTrack<T> withKey(
    int frameIndex,
    T value, {
    PropertyKeyInterpolation interpolation = PropertyKeyInterpolation.linear,
  }) {
    return PropertyTrack(
      keys: {
        ...keys,
        frameIndex: PropertyKey(
          value,
          interpolation: interpolation,
          // A name survives value edits: it is the key's identity, not
          // part of what it holds.
          name: keys[frameIndex]?.name,
        ),
      },
    );
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

  /// Every key called [name] set to [value] — the link "same name, same
  /// value" applied to this track.
  ///
  /// The write that starts a propagation runs this over its own track and
  /// over every other track sharing the naming space, so a named key edited
  /// in one place moves everywhere it appears.
  PropertyTrack<T> withNamedValue(String name, T value) {
    var changed = false;
    final next = <int, PropertyKey<T>>{};
    for (final entry in keys.entries) {
      final key = entry.value;
      if (key.name == name && key.value != value) {
        next[entry.key] = key.copyWith(value: value);
        changed = true;
      } else {
        next[entry.key] = key;
      }
    }
    return changed ? PropertyTrack(keys: next) : this;
  }

  /// [this] with every key whose name appears in [values] set to that
  /// name's value — the many-names form of [withNamedValue].
  ///
  /// One transform write can move several named keys at once (a pose key
  /// touches position, scale and rotation together), so the link applies
  /// them in one pass rather than rebuilding the track per name.
  PropertyTrack<T> withNamedValues(Map<String, T> values) {
    if (values.isEmpty || keys.isEmpty) {
      return this;
    }
    var changed = false;
    final next = <int, PropertyKey<T>>{};
    for (final entry in keys.entries) {
      final key = entry.value;
      final name = key.name;
      if (name != null && values.containsKey(name)) {
        final value = values[name] as T;
        if (key.value != value) {
          next[entry.key] = key.copyWith(value: value);
          changed = true;
          continue;
        }
      }
      next[entry.key] = key;
    }
    return changed ? PropertyTrack(keys: next) : this;
  }

  /// The value the keys called [name] hold here, or null when this track
  /// does not use the name.
  ///
  /// The link IS "same name, same value", so every match holds the same
  /// number and the first one speaks for all of them. This is the read a
  /// rename does before it commits: joining a name adopts the value the
  /// name ALREADY has, the way linking a frame adopts the drawing that is
  /// already there rather than overwriting it (user 2026-08-10).
  /// [excludeFrames] drops keys a RANGE rename is about to name: those are
  /// the keys doing the joining, so they must not answer for the name they
  /// are joining. "Is it taken?" and "what does it hold?" are the same
  /// question, so they stay one method — a range asks it with the range
  /// excluded, a single key with nothing excluded.
  T? valueForName(String name, {Set<int> excludeFrames = const {}}) {
    for (final entry in keys.entries) {
      if (entry.value.name == name && !excludeFrames.contains(entry.key)) {
        return entry.value.value;
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
  /// Which value they land on, in order: [adopted] when the name already
  /// holds one somewhere (joining adopts, the frame-link rule), else the
  /// key at [preferredFrame] — the one you are standing on — else the
  /// earliest key in range. Interpolation rides across untouched; adopting
  /// a value must not restyle the segment leaving a key.
  PropertyTrack<T>? withRangeNamed({
    required Set<int> frames,
    required String? name,
    T? adopted,
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
          ? keys[preferredFrame]?.value
          : null;
      final value = adopted ?? standing ?? keys[keyed.first]!.value;
      for (final frame in keyed) {
        final key = next.keys[frame]!;
        if (key.value != value) {
          next = next.withKey(frame, value, interpolation: key.interpolation);
        }
      }
    }
    for (final frame in keyed) {
      next = next.withKeyName(frame, name);
    }
    return next == this ? null : next;
  }

  /// The NAMED keys by frame — what a lane row hands its band so the link
  /// is visible where it lives. Frames absent here are unnamed.
  Map<int, String> get namedKeysByFrame => {
    for (final entry in keys.entries)
      if (entry.value.name case final String name) entry.key: name,
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
  /// empty-track default and [lerp] the component interpolation.
  T resolveAt({
    required int frameIndex,
    required T Function() orElse,
    required T Function(T a, T b, double t) lerp,
  }) {
    if (isEmpty) {
      return orElse();
    }

    final exact = keys[frameIndex];
    if (exact != null) {
      return exact.value;
    }

    final previousIndex = keys.lastKeyBefore(frameIndex);
    final nextIndex = keys.firstKeyAfter(frameIndex);
    if (previousIndex == null) {
      return keys[nextIndex!]!.value;
    }
    if (nextIndex == null) {
      return keys[previousIndex]!.value;
    }

    final previous = keys[previousIndex]!;
    if (previous.interpolation == PropertyKeyInterpolation.hold) {
      return previous.value;
    }
    return lerp(
      previous.value,
      keys[nextIndex]!.value,
      (frameIndex - previousIndex) / (nextIndex - previousIndex),
    );
  }

  List<Map<String, dynamic>> toJson(Object? Function(T value) encodeValue) => [
    for (final entry in keys.entries)
      {
        'index': entry.key,
        'value': encodeValue(entry.value.value),
        if (entry.value.interpolation != PropertyKeyInterpolation.linear)
          'interpolation': entry.value.interpolation.toJson(),
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
      keys[index] = PropertyKey(
        decodeValue(entry['value']),
        interpolation: PropertyKeyInterpolation.fromJson(
          entry['interpolation'],
        ),
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

/// The named keys whose VALUE moved between [before] and [after] — what one
/// track edit hands the "same name, same value" link.
///
/// A RENAME carries nothing, and neither does a key that ARRIVES already
/// named: joining a name adopts the value that name ALREADY holds, which
/// the rename verb pulls before it commits (the frame-link rule, user
/// 2026-08-10). Only a number that MOVED propagates from here.
Map<String, T> movedNamedValues<T>(
  PropertyTrack<T> before,
  PropertyTrack<T> after,
) {
  final moved = <String, T>{};
  if (after.isEmpty) {
    return moved;
  }
  for (final entry in after.keys.entries) {
    final name = entry.value.name;
    if (name == null) {
      continue;
    }
    final old = before.keys[entry.key];
    if (old == null || old.value == entry.value.value) {
      continue;
    }
    moved[name] = entry.value.value;
  }
  return moved;
}

SplayTreeMap<int, PropertyKey<T>> _immutableKeys<T>(
  Map<int, PropertyKey<T>> keys,
) {
  final result = SplayTreeMap<int, PropertyKey<T>>();
  for (final entry in keys.entries) {
    if (entry.key < 0) {
      throw ArgumentError.value(
        entry.key,
        'keys',
        'Property key indexes must be non-negative.',
      );
    }
    result[entry.key] = entry.value;
  }
  return result;
}
