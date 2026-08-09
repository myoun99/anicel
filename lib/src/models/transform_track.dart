import 'dart:collection';

import 'camera_pose.dart';
import 'canvas_point.dart';
import 'property_track.dart';

/// The shared transform pose shape: a point in canvas coordinates plus
/// uniform scale and rotation. The camera has used this shape since C0
/// (center/zoom/rotation); layer transforms resolve to the same shape, so
/// the dedicated name arrives with the property-lanes rename.
typedef TransformPose = CameraPose;

/// The AE-unified transform property set, in After Effects order. Display
/// conventions live at the UI/clipboard layer (Scale shown as zoom·100 %,
/// Rotation shown with AE's clockwise-positive sign, Opacity as ·100 %).
enum TransformPropertyId { anchorPoint, position, scale, rotation, opacity }

/// A keyframed transform in the After Effects model: every property is its
/// own independently keyed [PropertyTrack] (Position can carry three keys
/// while Scale carries none), with linear or HOLD interpolation per key.
///
/// The original pose-keyed API ([keyframes]/[keyframeAt]/[withKeyframe]/
/// [withoutKeyframe]) survives as a FACADE: a pose key means synchronized
/// keys on position+scale+rotation at that frame, and the keyframes view
/// yields resolved poses at the union of keyed frames. The camera keeps
/// speaking pose while the property lanes speak per-property.
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
        keys: _poseComponentKeys(keyframes, (pose) => pose.zoom),
      ),
      rotation = PropertyTrack(
        keys: _poseComponentKeys(keyframes, (pose) => pose.rotationDegrees),
      ),
      opacity = PropertyTrack.empty();

  const TransformTrack.properties({
    required this.anchorPoint,
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });

  factory TransformTrack.empty() => TransformTrack();

  final PropertyTrack<CanvasPoint> anchorPoint;
  final PropertyTrack<CanvasPoint> position;
  final PropertyTrack<double> scale;
  final PropertyTrack<double> rotation;
  final PropertyTrack<double> opacity;

  TransformTrack copyWith({
    PropertyTrack<CanvasPoint>? anchorPoint,
    PropertyTrack<CanvasPoint>? position,
    PropertyTrack<double>? scale,
    PropertyTrack<double>? rotation,
    PropertyTrack<double>? opacity,
  }) {
    return TransformTrack.properties(
      anchorPoint: anchorPoint ?? this.anchorPoint,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
    );
  }

  bool get isEmpty =>
      anchorPoint.isEmpty &&
      position.isEmpty &&
      scale.isEmpty &&
      rotation.isEmpty &&
      opacity.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// The union of every property's keyed frames.
  Set<int> get keyedFrames => SplayTreeSet<int>()
    ..addAll(anchorPoint.keys.keys)
    ..addAll(position.keys.keys)
    ..addAll(scale.keys.keys)
    ..addAll(rotation.keys.keys)
    ..addAll(opacity.keys.keys);

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
      position: position.withKey(frameIndex, pose.center),
      scale: scale.withKey(frameIndex, pose.zoom),
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
  }) {
    TransformPose? defaultPose;
    TransformPose fallback() => defaultPose ??= orElse();

    return TransformPose(
      center: position.resolveAt(
        frameIndex: frameIndex,
        orElse: () => fallback().center,
        lerp: lerpCanvasPoint,
      ),
      zoom: scale.resolveAt(
        frameIndex: frameIndex,
        orElse: () => fallback().zoom,
        lerp: lerpDouble,
      ),
      rotationDegrees: rotation.resolveAt(
        frameIndex: frameIndex,
        orElse: () => fallback().rotationDegrees,
        lerp: lerpDouble,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    if (anchorPoint.isNotEmpty)
      'anchorPoint': anchorPoint.toJson((value) => value.toJson()),
    if (position.isNotEmpty)
      'position': position.toJson((value) => value.toJson()),
    if (scale.isNotEmpty) 'scale': scale.toJson((value) => value),
    if (rotation.isNotEmpty) 'rotation': rotation.toJson((value) => value),
    if (opacity.isNotEmpty) 'opacity': opacity.toJson((value) => value),
  };

  factory TransformTrack.fromJson(Map<String, dynamic> json) {
    // Legacy pose-keyed tracks ({'keyframes': [{index, pose}]}) migrate to
    // synchronized per-property keys on load.
    if (json.containsKey('keyframes')) {
      final keyframes = <int, TransformPose>{};
      for (final item in json['keyframes'] as List? ?? const []) {
        final entry = item as Map<String, dynamic>;
        final index = entry['index'] as int;
        if (keyframes.containsKey(index)) {
          throw FormatException('Duplicate transform keyframe index: $index');
        }
        keyframes[index] = TransformPose.fromJson(
          entry['pose'] as Map<String, dynamic>,
        );
      }
      return TransformTrack(keyframes: keyframes);
    }

    return TransformTrack.properties(
      anchorPoint: PropertyTrack.fromJson(
        json['anchorPoint'] as List?,
        (value) => CanvasPoint.fromJson(value as Map<String, dynamic>),
      ),
      position: PropertyTrack.fromJson(
        json['position'] as List?,
        (value) => CanvasPoint.fromJson(value as Map<String, dynamic>),
      ),
      scale: PropertyTrack.fromJson(
        json['scale'] as List?,
        (value) => (value as num).toDouble(),
      ),
      rotation: PropertyTrack.fromJson(
        json['rotation'] as List?,
        (value) => (value as num).toDouble(),
      ),
      opacity: PropertyTrack.fromJson(
        json['opacity'] as List?,
        (value) => (value as num).toDouble(),
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

/// Samples an AE Opacity track as a 0..1 multiplier; 1 while the track is
/// empty. Deliberately track-level and layer-agnostic — a layer's animated
/// opacity multiplies its static opacity, and the storyboard V-track fades
/// ride the same function.
double resolveOpacityTrackAt(PropertyTrack<double> track, int frameIndex) {
  if (track.isEmpty) {
    return 1;
  }
  return track
      .resolveAt(frameIndex: frameIndex, orElse: () => 1, lerp: lerpDouble)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Samples an anchor-point track; null while the track is empty (the
/// consumer supplies its default — the canvas center for layer poses).
CanvasPoint? resolveAnchorTrackAt(
  PropertyTrack<CanvasPoint> track,
  int frameIndex,
) {
  if (track.isEmpty) {
    return null;
  }
  return track.resolveAt(
    frameIndex: frameIndex,
    orElse: () => CanvasPoint(x: 0, y: 0),
    lerp: lerpCanvasPoint,
  );
}

/// Component-wise linear interpolation; rotation lerps as-is (no
/// wrap-around), so keyframing 0 → 360 produces a full turn.
TransformPose lerpTransformPose(TransformPose a, TransformPose b, double t) {
  return TransformPose(
    center: lerpCanvasPoint(a.center, b.center, t),
    zoom: lerpDouble(a.zoom, b.zoom, t),
    rotationDegrees: lerpDouble(a.rotationDegrees, b.rotationDegrees, t),
  );
}

CanvasPoint lerpCanvasPoint(CanvasPoint a, CanvasPoint b, double t) =>
    CanvasPoint(x: lerpDouble(a.x, b.x, t), y: lerpDouble(a.y, b.y, t));

double lerpDouble(double a, double b, double t) => a + (b - a) * t;

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
