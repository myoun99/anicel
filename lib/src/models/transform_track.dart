import 'dart:collection';

import 'camera_pose.dart';
import 'canvas_point.dart';
import 'position_path.dart';
import 'property_track.dart';
import 'transform_pose.dart';

export 'transform_pose.dart';

/// The AE-unified transform property set, in After Effects order. Display
/// conventions live at the UI/clipboard layer (Scale shown as zoom·100 %,
/// Rotation shown with AE's clockwise-positive sign, Opacity as ·100 %).
enum TransformPropertyId { anchorPoint, position, scale, rotation, opacity }

/// A keyframed transform in the After Effects model: every property is its
/// own independently keyed [PropertyTrack] (Position can carry three keys
/// while Scale carries none), each key easing its two sides ([KeySide]).
///
/// The original pose-keyed API ([keyframes]/[keyframeAt]/[withKeyframe]/
/// [withoutKeyframe]) survives as a FACADE: a pose key means synchronized
/// keys on position+scale+rotation at that frame, and the keyframes view
/// yields resolved poses at the union of keyed frames. The camera keeps
/// speaking pose while the property lanes speak per-property.
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y」. The
/// [scale] lane holds TWO numbers, one value, like Position and Anchor
/// Point — AE's Scale is one property with two components, so its keys,
/// its names and its clipboard line stay one. The camera writes its one
/// zoom to both (the same option's terms: 「카메라는 줌 하나 그대로」)
/// through its own wrapper (`CutCamera`), which is where a [CameraPose]
/// goes in and comes out; the track itself speaks [TransformPose].
///
/// An empty track means "no transform work" — consumers supply their own
/// default pose (the camera's canvas-centered pose, a layer's identity).
class TransformTrack {
  TransformTrack({Map<int, TransformPose>? keyframes})
    : anchorPoint = PropertyTrack.empty(),
      position = PropertyTrack(
        keys: _poseComponentKeys(keyframes, (pose) => pose.center),
      ),
      scale = PropertyTrack(
        keys: _poseComponentKeys(keyframes, (pose) => pose.scale),
      ),
      rotation = PropertyTrack(
        keys: _poseComponentKeys(keyframes, (pose) => pose.rotationDegrees),
      ),
      opacity = PropertyTrack.empty(),
      _written = null;

  /// The five lanes as given — but for [position]'s roving keys, each on
  /// the frame its run passes it nearest ([PropertyTrack.withRovingKeysSlotted],
  /// I-89 ④): a roving key's frame is never anywhere else, whichever edit
  /// made the track.
  TransformTrack.properties({
    required this.anchorPoint,
    required PropertyTrack<CanvasPoint> position,
    required this.scale,
    required this.rotation,
    required this.opacity,
  }) : position = position.withRovingKeysSlotted(positionKeySpace),
       _written = position;

  factory TransformTrack.empty() => TransformTrack();

  final PropertyTrack<CanvasPoint> anchorPoint;
  final PropertyTrack<CanvasPoint> position;

  /// [position] as the edit that made this track wrote it, before its
  /// roving keys were placed — what the name link reads that edit by
  /// ([transformNamedKeyChanges]). The link pairs a key with what it was
  /// by its frame, and a roving key the edit changed may stand on another
  /// frame once placed (I-89 ④): read off [position], the change would be
  /// lost on the way to the keys its name links.
  PropertyTrack<CanvasPoint> get writtenPosition => _written ?? position;
  final PropertyTrack<CanvasPoint>? _written;

  /// The scale along each axis as ONE value — x across, y down, 1 being the
  /// size the layer has (`TransformPose.scale`).
  final PropertyTrack<CanvasPoint> scale;
  final PropertyTrack<double> rotation;
  final PropertyTrack<double> opacity;

  TransformTrack copyWith({
    PropertyTrack<CanvasPoint>? anchorPoint,
    PropertyTrack<CanvasPoint>? position,
    PropertyTrack<CanvasPoint>? scale,
    PropertyTrack<double>? rotation,
    PropertyTrack<double>? opacity,
  }) {
    return TransformTrack.properties(
      anchorPoint: anchorPoint ?? this.anchorPoint,
      // The position as written, so an edit of another lane after it in
      // the same verb leaves the link the position's own edit to read
      // ([writtenPosition]); placed again, it stands as it stood.
      position: position ?? writtenPosition,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
    );
  }

  /// Every property, in AE's order — what a reading of the whole track walks
  /// (its keys, the group header's marks and names) rather than naming the
  /// five again.
  List<PropertyTrack<Object?>> get lanes => [
    anchorPoint,
    position,
    scale,
    rotation,
    opacity,
  ];

  bool get isEmpty => lanes.every((lane) => lane.isEmpty);
  bool get isNotEmpty => !isEmpty;

  /// The union of every property's keyed frames, first to last.
  Set<int> get keyedFrames => SplayTreeSet<int>()
    ..addAll([for (final lane in lanes) ...lane.keys.keys]);

  /// POSE FACADE: resolved poses at the union of keyed frames. While keys
  /// stay pose-synchronized (the camera panel writes whole poses) this is
  /// exactly the old pose-keyed view.
  SplayTreeMap<int, TransformPose> get keyframes {
    final result = SplayTreeMap<int, TransformPose>();
    for (final frame in keyedFrames) {
      result[frame] = resolveAt(frameIndex: frame, orElse: _defaultFacadePose);
    }
    return result;
  }

  /// POSE FACADE: the resolved pose at [frameIndex] when ANY property keys
  /// there, null otherwise.
  TransformPose? keyframeAt(int frameIndex) {
    final keyed =
        anchorPoint.keyAt(frameIndex) != null ||
        position.keyAt(frameIndex) != null ||
        scale.keyAt(frameIndex) != null ||
        rotation.keyAt(frameIndex) != null ||
        opacity.keyAt(frameIndex) != null;
    if (!keyed) {
      return null;
    }
    return resolveAt(frameIndex: frameIndex, orElse: _defaultFacadePose);
  }

  /// POSE FACADE: keys position+scale+rotation together at [frameIndex].
  TransformTrack withKeyframe(int frameIndex, TransformPose pose) {
    return copyWith(
      position: positionLaneKeyed(position, frameIndex, pose.center),
      scale: scale.withKey(frameIndex, pose.scale),
      rotation: rotation.withKey(frameIndex, pose.rotationDegrees),
    );
  }

  /// POSE FACADE: removes every property's key at [frameIndex].
  TransformTrack withoutKeyframe(int frameIndex) {
    return TransformTrack.properties(
      anchorPoint: anchorPoint.withoutKey(frameIndex),
      position: position.withoutKey(frameIndex),
      scale: scale.withoutKey(frameIndex),
      rotation: rotation.withoutKey(frameIndex),
      opacity: opacity.withoutKey(frameIndex),
    );
  }

  /// Resolves the pose at [frameIndex] property by property; [orElse]
  /// supplies the empty-track defaults (e.g. the camera's canvas-centered
  /// pose, a layer's identity).
  TransformPose resolveAt({
    required int frameIndex,
    required TransformPose Function() orElse,
  }) => resolveAtTime(time: frameIndex.toDouble(), orElse: orElse);

  /// [resolveAt] at a [time] between frames as well — a header graph's
  /// curve (I-89 ③, [PropertyTrack.resolveAtTime]).
  TransformPose resolveAtTime({
    required double time,
    required TransformPose Function() orElse,
  }) {
    TransformPose? defaultPose;
    TransformPose fallback() => defaultPose ??= orElse();

    final scales = scale.resolveAtTime(
      time: time,
      orElse: () => fallback().scale,
      space: pointKeySpace,
    );
    return TransformPose(
      center: position.resolveAtTime(
        time: time,
        orElse: () => fallback().center,
        space: positionKeySpace,
      ),
      scaleX: scales.x,
      scaleY: scales.y,
      rotationDegrees: rotation.resolveAtTime(
        time: time,
        orElse: () => fallback().rotationDegrees,
        space: doubleKeySpace,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    if (anchorPoint.isNotEmpty)
      'anchorPoint': anchorPoint.toJson((value) => value.toJson()),
    if (position.isNotEmpty)
      'position': position.toJson((value) => value.toJson()),
    if (scale.isNotEmpty) 'scale': scale.toJson((value) => value.toJson()),
    if (rotation.isNotEmpty) 'rotation': rotation.toJson((value) => value),
    if (opacity.isNotEmpty) 'opacity': opacity.toJson((value) => value),
  };

  factory TransformTrack.fromJson(Map<String, dynamic> json) {
    // ↩️A pose-keyed track ({'keyframes': [{index, pose}]}) migrated to
    // per-property keys here — the shape of files whose format is refused
    // by its number now (the save law, 유저 2026-10-06).
    return TransformTrack.properties(
      anchorPoint: PropertyTrack.fromJson(
        json['anchorPoint'] as List?,
        (value) => CanvasPoint.fromJson(value! as Map<String, dynamic>),
      ),
      position: PropertyTrack.fromJson(
        json['position'] as List?,
        (value) => CanvasPoint.fromJson(value! as Map<String, dynamic>),
        roves: true,
      ),
      scale: PropertyTrack.fromJson(
        json['scale'] as List?,
        (value) => CanvasPoint.fromJson(value! as Map<String, dynamic>),
      ),
      rotation: PropertyTrack.fromJson(
        json['rotation'] as List?,
        (value) => (value! as num).toDouble(),
      ),
      opacity: PropertyTrack.fromJson(
        json['opacity'] as List?,
        (value) => (value! as num).toDouble(),
      ),
    );
  }

  /// The facade default when a pose view is requested while some property
  /// has no keys at all: identity-ish components (centered pose is a
  /// CONSUMER default — the facade only needs stable placeholders for the
  /// unkeyed components, and pose-synchronized writers never hit them).
  static TransformPose _defaultFacadePose() =>
      TransformPose(center: CanvasPoint(x: 0, y: 0));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransformTrack &&
          other.anchorPoint == anchorPoint &&
          other.position == position &&
          other.scale == scale &&
          other.rotation == rotation &&
          other.opacity == opacity;

  @override
  int get hashCode =>
      Object.hash(anchorPoint, position, scale, rotation, opacity);

  @override
  String toString() => 'TransformTrack(keyframes: $keyframes)';
}

/// The named keys one transform write moved, lane by lane — a transform's
/// half of the "same name, same value" link.
///
/// Lanes stay SEPARATE because the naming space is one property: Rotation's
/// "A" and Position's "A" are different names by construction, which is
/// what lets one name sit on a whole pose without the numbers colliding
/// (user 2026-07-30). It is also why this is five maps and not one.
class TransformNamedChanges {
  const TransformNamedChanges({
    this.anchorPoint = const {},
    this.position = const {},
    this.scale = const {},
    this.rotation = const {},
    this.opacity = const {},
  });

  final Map<String, NamedKeyValue<CanvasPoint>> anchorPoint;
  final Map<String, NamedKeyValue<CanvasPoint>> position;
  final Map<String, NamedKeyValue<CanvasPoint>> scale;
  final Map<String, NamedKeyValue<double>> rotation;
  final Map<String, NamedKeyValue<double>> opacity;

  bool get isEmpty =>
      anchorPoint.isEmpty &&
      position.isEmpty &&
      scale.isEmpty &&
      rotation.isEmpty &&
      opacity.isEmpty;
}

/// What [before] → [after] hands the link — [movedNamedKeys] per lane, so
/// a transform lane and an effect parameter cannot disagree about what
/// "moved" means.
TransformNamedChanges transformNamedKeyChanges(
  TransformTrack before,
  TransformTrack after,
) => TransformNamedChanges(
  anchorPoint: movedNamedKeys(before.anchorPoint, after.anchorPoint),
  position: movedNamedKeys(before.position, after.writtenPosition),
  scale: movedNamedKeys(before.scale, after.scale),
  rotation: movedNamedKeys(before.rotation, after.rotation),
  opacity: movedNamedKeys(before.opacity, after.opacity),
);

/// [track] with every name in [changes] set to its value and type — the
/// other half of the link, applied to the written row AND to its 겸용
/// siblings.
TransformTrack transformTrackWithNamedKeys(
  TransformTrack track,
  TransformNamedChanges changes,
) {
  if (changes.isEmpty) {
    return track;
  }
  return TransformTrack.properties(
    anchorPoint: track.anchorPoint.withNamedKeys(changes.anchorPoint),
    position: track.position.withNamedKeys(changes.position),
    scale: track.scale.withNamedKeys(changes.scale),
    rotation: track.rotation.withNamedKeys(changes.rotation),
    opacity: track.opacity.withNamedKeys(changes.opacity),
  );
}

/// The property a BARE transform lane id addresses ('anchor-point',
/// 'position', 'scale', 'rotation', 'opacity'); null when [laneId] is
/// something else — an `fx:` parameter lane, a group header.
///
/// The lane ids are the UI's display spelling and the enum is the model's,
/// so the translation lives here rather than being re-guessed at each verb
/// that has to cross between them.
TransformPropertyId? transformPropertyOfLaneId(String laneId) =>
    switch (laneId) {
      'anchor-point' => TransformPropertyId.anchorPoint,
      'position' => TransformPropertyId.position,
      'scale' => TransformPropertyId.scale,
      'rotation' => TransformPropertyId.rotation,
      'opacity' => TransformPropertyId.opacity,
      _ => null,
    };

/// Whether [property]'s keys walk a path in space ([KeyPath], I-89 ④) —
/// Position's alone: it resolves through [positionKeySpace], and no other
/// lane's key is offered a path.
bool walksAPath(TransformPropertyId property) =>
    property == TransformPropertyId.position;

/// [lane] — a position lane — with [value] keyed at [frameIndex]: the one
/// write of a position key. A key new there is smooth through its
/// neighbours ([KeyPath.auto]), as After Effects lays a new key on a motion
/// path (I-89-Q10 B, 유저 2026-10-12: 「AE 처럼 처음부터 곡선」) — a move of
/// two keys still runs straight, one of three or more bends. A key already
/// there keeps the path it was given. ↩️A new key was a corner, the key
/// window making it a curve (④-Q4 A).
PropertyTrack<CanvasPoint> positionLaneKeyed(
  PropertyTrack<CanvasPoint> lane,
  int frameIndex,
  CanvasPoint value,
) => lane.withKey(
  frameIndex,
  value,
  path: lane.keyAt(frameIndex) == null ? KeyPath.auto : null,
);

/// [property]'s lane of [track], read without knowing its value type — so
/// a key's NAME and its TYPE (the key window's two halves) and whether it
/// may rove come off the same read.
PropertyTrack<Object?> transformLaneOf(
  TransformTrack track,
  TransformPropertyId property,
) => switch (property) {
  TransformPropertyId.anchorPoint => track.anchorPoint,
  TransformPropertyId.position => track.position,
  TransformPropertyId.scale => track.scale,
  TransformPropertyId.rotation => track.rotation,
  TransformPropertyId.opacity => track.opacity,
};

/// [property]'s key at [frameIndex], or null ([transformLaneOf]).
PropertyKey<Object?>? transformLaneKeyAt(
  TransformTrack track,
  TransformPropertyId property,
  int frameIndex,
) => transformLaneOf(track, property).keyAt(frameIndex);

/// Whether [property]'s key at [frameIndex] may give its time up (I-89 ④):
/// a key between the first and the last ([PropertyTrack.keyCanRove]) of a
/// lane whose keys walk a path ([walksAPath]).
bool transformLaneKeyCanRove(
  TransformTrack track,
  TransformPropertyId property,
  int frameIndex,
) =>
    walksAPath(property) &&
    transformLaneOf(track, property).keyCanRove(frameIndex);

/// Whether [name] is already used by [property]'s lane in [track] — the
/// read a rename does before it commits.
/// [excludeFrames] drops the keys a RANGE rename is about to name — they
/// are the ones joining, so they must not answer for the name.
bool transformLaneUsesName(
  TransformTrack track,
  TransformPropertyId property,
  String name, {
  Set<int> excludeFrames = const {},
}) {
  final lane = transformLaneOf(track, property);
  return lane.keyForName(name, excludeFrames: excludeFrames) != null;
}

/// Samples an AE Opacity track as a 0..1 multiplier; 1 while the track is
/// empty. Deliberately track-level and layer-agnostic — a layer's animated
/// opacity multiplies its static opacity, and the storyboard V-track fades
/// ride the same function.
double resolveOpacityTrackAt(PropertyTrack<double> track, int frameIndex) =>
    resolveOpacityTrackAtTime(track, frameIndex.toDouble());

/// [resolveOpacityTrackAt] at a [time] between frames as well (I-89 ③).
double resolveOpacityTrackAtTime(PropertyTrack<double> track, double time) {
  if (track.isEmpty) {
    return 1;
  }
  return track
      .resolveAtTime(time: time, orElse: () => 1, space: doubleKeySpace)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Samples an anchor-point track; null while the track is empty (the
/// consumer supplies its default — the canvas center for layer poses).
CanvasPoint? resolveAnchorTrackAt(
  PropertyTrack<CanvasPoint> track,
  int frameIndex,
) => resolveAnchorTrackAtTime(track, frameIndex.toDouble());

/// [resolveAnchorTrackAt] at a [time] between frames as well (I-89 ③).
CanvasPoint? resolveAnchorTrackAtTime(
  PropertyTrack<CanvasPoint> track,
  double time,
) {
  if (track.isEmpty) {
    return null;
  }
  return track.resolveAtTime(
    time: time,
    orElse: () => CanvasPoint(x: 0, y: 0),
    space: pointKeySpace,
  );
}

double lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// [lerpDouble] undone: where [value] falls from [a] (0) to [b] (1).
double inverseLerpDouble(double a, double b, double value) =>
    a == b ? 0 : (value - a) / (b - a);

/// A number's [KeyValueSpace].
const KeyValueSpace<double> doubleKeySpace = KeyValueSpace(
  lerp: lerpDouble,
  inverseLerp: inverseLerpDouble,
);

/// A point's [KeyValueSpace] — Anchor Point's, and Scale's two numbers.
const KeyValueSpace<CanvasPoint> pointKeySpace = KeyValueSpace(
  lerp: CanvasPoint.lerp,
  inverseLerp: CanvasPoint.inverseLerp,
);

/// Position's [KeyValueSpace]: a point's, its segments walking the path in
/// space their keys bend ([positionPathBetween], I-89 ④).
const KeyValueSpace<CanvasPoint> positionKeySpace = KeyValueSpace(
  lerp: CanvasPoint.lerp,
  inverseLerp: CanvasPoint.inverseLerp,
  walk: positionPathBetween,
);

/// An ARGB colour's [KeyValueSpace], channel by channel like [lerpArgb].
const KeyValueSpace<int> argbKeySpace = KeyValueSpace(
  lerp: lerpArgb,
  inverseLerp: _inverseLerpArgb,
);

/// A boolean's [KeyValueSpace]: it never tweens ([lerpBoolHold]), so no
/// value falls between two keys.
const KeyValueSpace<bool> boolHoldKeySpace = KeyValueSpace(
  lerp: lerpBoolHold,
  inverseLerp: _nothingBetween,
);

/// ARGB interpolation, channel by channel (R5 #7 — the first colour lanes).
///
/// Straight sRGB, not linear light: these are UI inks picked off a swatch
/// roster, and someone who keys white → red expects the midpoint they see
/// in the picker. Gamma-correct blending is the compositor's business, not
/// the value track's.
int lerpArgb(int a, int b, double t) {
  int channel(int shift) {
    final from = (a >> shift) & 0xFF;
    final to = (b >> shift) & 0xFF;
    return (from + (to - from) * t).round().clamp(0, 255);
  }

  return (channel(24) << 24) |
      (channel(16) << 16) |
      (channel(8) << 8) |
      channel(0);
}

/// Booleans never tween: half a shown line is not a state (R5 #7).
///
/// Written as a lerp rather than special-cased at each call so a boolean
/// lane rides the ordinary [PropertyTrack.resolveAt] path — the value HOLDS
/// until the next key, which is what AE's checkbox properties do.
bool lerpBoolHold(bool a, bool b, double t) => a;

/// [lerpArgb] undone: [value]'s channels projected onto the line from [a]
/// to [b].
double _inverseLerpArgb(int a, int b, int value) {
  var along = 0.0;
  var length = 0.0;
  for (final shift in const [24, 16, 8, 0]) {
    final from = (a >> shift) & 0xFF;
    final step = ((b >> shift) & 0xFF) - from;
    along += (((value >> shift) & 0xFF) - from) * step;
    length += step * step;
  }
  return length == 0 ? 0 : along / length;
}

double _nothingBetween(bool a, bool b, bool value) => 0;

Map<int, PropertyKey<T>> _poseComponentKeys<T>(
  Map<int, TransformPose>? keyframes,
  T Function(TransformPose pose) component,
) {
  if (keyframes == null) {
    return const {};
  }
  return {
    for (final entry in keyframes.entries)
      entry.key: PropertyKey(component(entry.value)),
  };
}
