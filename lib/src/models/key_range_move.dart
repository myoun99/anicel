/// Pure planning for KEY-RANGE moves (UI-R20 #2 second half, P3b-2): the
/// camera row's keyframes and the instruction rows' event spans shift with
/// a range selection exactly like drawing blocks slide — rigid group, one
/// delta, all-or-nothing (an illegal landing voids the whole plan).
library;

import 'camera_instruction.dart';
import 'camera_pose.dart';
import 'drawing_block_move.dart';
import 'layer.dart';
import 'property_track.dart';
import 'transform_track.dart';

/// The camera keyframes with every key in [rangeStartIndex,
/// [rangeEndIndexExclusive]) shifted by [frameDelta]; null when any
/// shifted key would land below frame 0 or on an UNSHIFTED key (the
/// block discipline: nothing merges silently).
Map<int, CameraPose>? shiftCameraKeysInRange({
  required Map<int, CameraPose> keyframes,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  bool inRange(int frame) =>
      frame >= rangeStartIndex && frame < rangeEndIndexExclusive;
  final moved = <int>{
    for (final frame in keyframes.keys)
      if (inRange(frame)) frame,
  };
  if (moved.isEmpty || frameDelta == 0) {
    return null;
  }
  final shifted = <int, CameraPose>{};
  for (final entry in keyframes.entries) {
    if (!moved.contains(entry.key)) {
      shifted[entry.key] = entry.value;
    }
  }
  for (final frame in moved) {
    final landing = frame + frameDelta;
    if (landing < 0 || shifted.containsKey(landing)) {
      return null;
    }
    shifted[landing] = keyframes[frame]!;
  }
  return shifted;
}

/// Every frame carrying a key on ANY lane of [track] — the transform
/// group header's summary display (UI-R20 #13, the camera row pattern).
Set<int> transformKeyFrameUnion(TransformTrack track) => {
  ...track.anchorPoint.keys.keys,
  ...track.position.keys.keys,
  ...track.scale.keys.keys,
  ...track.rotation.keys.keys,
  ...track.opacity.keys.keys,
};

/// The union frames whose keyed lanes ALL hold — the union mark draws the
/// AE hold square there, a diamond everywhere else.
///
/// This was the camera row's ■ rule alone while its summary was a text
/// glyph; the 2026-08-17 unification (B4) made it the ONE law every union
/// mark reads — camera row and transform group header alike — through
/// [transformUnionHeader]'s hold set.
Set<int> transformKeyHoldUnion(TransformTrack track) {
  final lanes = [
    track.anchorPoint,
    track.position,
    track.scale,
    track.rotation,
    track.opacity,
  ];
  final holds = <int>{};
  for (final frame in transformKeyFrameUnion(track)) {
    final interpolations = [
      for (final lane in lanes)
        if (lane.keyAt(frame) case final key?) key.interpolation,
    ];
    if (interpolations.isNotEmpty &&
        interpolations.every(
          (interpolation) => interpolation == PropertyKeyInterpolation.hold,
        )) {
      holds.add(frame);
    }
  }
  return holds;
}

/// The union header's NAME at each frame.
///
/// ㉚ (user, 2026-08-12): 「유니언 그룹 이름 규칙 — 해당 인덱스 멤버들 이름이
/// 같으면 그 이름 그대로, 다르면 `...`」.
///
/// Two edges the rule does not spell out, decided here so they are visible
/// and cheap to reverse:
/// - a frame where NO keyed member is named gets no entry at all. `...`
///   means "several different names"; over a set with none it would be
///   noise where the row used to print nothing.
/// - a frame where one member is named and another is not DIFFERS, so it
///   reads `...`. The alternative — letting the lone name speak for the
///   group — would claim the whole union carries a name that only one lane
///   actually has.
Map<int, String> transformKeyNameUnion(TransformTrack track) {
  final tracks = [
    track.anchorPoint,
    track.position,
    track.scale,
    track.rotation,
    track.opacity,
  ];
  final names = <int, String>{};
  for (final frame in transformKeyFrameUnion(track)) {
    // Only the lanes that actually hold a key here get a vote.
    final memberNames = <String?>[
      for (final member in tracks)
        if (member.keys.containsKey(frame)) member.keys[frame]!.name,
    ];
    if (memberNames.every((name) => name == null)) {
      continue;
    }
    final first = memberNames.first;
    names[frame] = first != null && memberNames.every((name) => name == first)
        ? first
        : unionMixedKeyName;
  }
  return names;
}

/// What a union prints where its members disagree (㉚).
const String unionMixedKeyName = '...';

/// Whether any lane of [track] holds a key inside the range.
bool transformTrackHasKeysInRange(
  TransformTrack track,
  int rangeStartIndex,
  int rangeEndIndexExclusive,
) => transformKeyFrameUnion(
  track,
).any((frame) => frame >= rangeStartIndex && frame < rangeEndIndexExclusive);

/// The transform track with every keyed frame in range shifted by
/// [frameDelta] on EVERY lane; null when any landing dips below 0 or
/// collides with an unshifted key on the same lane (all-or-nothing, the
/// block discipline).
TransformTrack? shiftTransformKeysInRange({
  required TransformTrack track,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  bool inRange(int frame) =>
      frame >= rangeStartIndex && frame < rangeEndIndexExclusive;
  PropertyTrack<T>? shiftLane<T>(PropertyTrack<T> lane) {
    final moved = <int>{
      for (final frame in lane.keys.keys)
        if (inRange(frame)) frame,
    };
    if (moved.isEmpty) {
      return lane;
    }
    final next = <int, PropertyKey<T>>{};
    for (final entry in lane.keys.entries) {
      if (!moved.contains(entry.key)) {
        next[entry.key] = entry.value;
      }
    }
    for (final frame in moved) {
      final landing = frame + frameDelta;
      if (landing < 0 || next.containsKey(landing)) {
        return null;
      }
      next[landing] = lane.keys[frame]!;
    }
    return PropertyTrack(keys: next);
  }

  final anchorPoint = shiftLane(track.anchorPoint);
  final position = shiftLane(track.position);
  final scale = shiftLane(track.scale);
  final rotation = shiftLane(track.rotation);
  final opacity = shiftLane(track.opacity);
  if (anchorPoint == null ||
      position == null ||
      scale == null ||
      rotation == null ||
      opacity == null) {
    return null;
  }
  return TransformTrack.properties(
    anchorPoint: anchorPoint,
    position: position,
    scale: scale,
    rotation: rotation,
    opacity: opacity,
  );
}

/// An SE→SE ROW move (P3b-4, 같은 섹션 행이동): the selected sound
/// blocks land on a SIBLING SE row — cels travel with the blocks (the
/// drawing-move planner's cross-layer carry) and the AUDIO CLIPS follow
/// their cels by [AudioClip.frameId] (a clip anchors to its cel, so its
/// timing rides the landed block for free). Null on any illegal landing
/// (overlap on the target, partially covered blocks, negative frames).
({Layer sourceAfter, Layer targetAfter})? planSeRangeRowMove({
  required Layer source,
  required Layer target,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  final plan = planDrawingRangeMove(
    source: source,
    target: target,
    rangeStartIndex: rangeStartIndex,
    rangeEndIndexExclusive: rangeEndIndexExclusive,
    frameDelta: frameDelta,
  );
  final targetAfter = plan?.targetAfter;
  if (plan == null || targetAfter == null) {
    return null;
  }
  final movedIds = plan.movedFrameIds.toSet();
  return (
    sourceAfter: plan.sourceAfter.copyWith(
      audioClips: [
        for (final clip in source.audioClips)
          if (!movedIds.contains(clip.frameId)) clip,
      ],
    ),
    targetAfter: targetAfter.copyWith(
      audioClips: [
        ...target.audioClips,
        for (final clip in source.audioClips)
          if (movedIds.contains(clip.frameId)) clip,
      ],
    ),
  );
}

/// An instruction→instruction ROW move (P3b-4): events STARTING in the
/// range land on a sibling instruction row at start+[frameDelta]; null
/// when nothing moves, a landing dips below 0, or it overlaps one of the
/// target's existing events (moved events keep their relative spacing,
/// so they never collide with each other).
({
  Map<int, InstructionEvent> sourceAfter,
  Map<int, InstructionEvent> targetAfter,
})?
planInstructionRangeRowMove({
  required Map<int, InstructionEvent> source,
  required Map<int, InstructionEvent> target,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  bool inRange(int frame) =>
      frame >= rangeStartIndex && frame < rangeEndIndexExclusive;
  final moved = <int>{
    for (final start in source.keys)
      if (inRange(start)) start,
  };
  if (moved.isEmpty) {
    return null;
  }
  final sourceAfter = <int, InstructionEvent>{
    for (final entry in source.entries)
      if (!moved.contains(entry.key)) entry.key: entry.value,
  };
  final targetAfter = Map<int, InstructionEvent>.of(target);
  for (final start in moved) {
    final event = source[start]!;
    final landing = start + frameDelta;
    if (landing < 0) {
      return null;
    }
    final landingEnd = landing + event.length;
    for (final other in targetAfter.entries) {
      final otherEnd = other.key + other.value.length;
      if (landing < otherEnd && other.key < landingEnd) {
        return null;
      }
    }
    targetAfter[landing] = event;
  }
  return (sourceAfter: sourceAfter, targetAfter: targetAfter);
}

/// The instruction map with every event STARTING in the range shifted by
/// [frameDelta]; null when any landing dips below 0 or overlaps an
/// unmoved event's span.
Map<int, InstructionEvent>? shiftInstructionEventsInRange({
  required Map<int, InstructionEvent> events,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  bool inRange(int frame) =>
      frame >= rangeStartIndex && frame < rangeEndIndexExclusive;
  final moved = <int>{
    for (final start in events.keys)
      if (inRange(start)) start,
  };
  if (moved.isEmpty || frameDelta == 0) {
    return null;
  }
  final shifted = <int, InstructionEvent>{};
  for (final entry in events.entries) {
    if (!moved.contains(entry.key)) {
      shifted[entry.key] = entry.value;
    }
  }
  for (final start in moved) {
    final event = events[start]!;
    final landing = start + frameDelta;
    if (landing < 0) {
      return null;
    }
    final landingEnd = landing + event.length;
    for (final other in shifted.entries) {
      final otherEnd = other.key + other.value.length;
      if (landing < otherEnd && other.key < landingEnd) {
        return null;
      }
    }
    shifted[landing] = event;
  }
  return shifted;
}
