// Per-lane edits on an SE row's SOUND (I-140), keyed by the lane ids
// [seSoundPropertyLanes] emits. Every function returns the edited sound
// (or null when the edit is a no-op / not a sound lane) — callers commit it
// as ONE undo step, exactly like the name tag's and the transform's.

import '../../models/property_track.dart' show KeyTypePick, PropertyTrack;
import '../../models/se_sound.dart';
import '../../models/transform_track.dart' show doubleKeySpace;
import '../text/readout_text.dart' show columnValueOf;
import 'se_sound_lane_policy.dart';
import 'transform_lane_editing.dart' show laneResetOver;

/// Adds a key at [frameIndex] on member lane [laneId] holding what the row
/// plays there (AE: keying a property freezes what it currently shows), or
/// removes the one there — the keyframe navigator's diamond toggle. The
/// Pan keys as the Volume does (audio-fx-grows-like-the-pros-Q7).
SeSound? seSoundWithLaneKeyToggled(
  SeSound sound, {
  required String laneId,
  required int frameIndex,
}) {
  if (frameIndex < 0) {
    return null;
  }
  final at = frameIndex.toDouble();
  return switch (laneId) {
    seSoundVolumeLaneId => sound.copyWith(
      volume: _keyToggled(sound.volume, frameIndex, sound.volumeAt(at)),
    ),
    seSoundPanLaneId => sound.copyWith(
      pan: _keyToggled(sound.pan, frameIndex, sound.panAt(at)),
    ),
    _ => null,
  };
}

PropertyTrack<double> _keyToggled(
  PropertyTrack<double> lane,
  int frame,
  double shown,
) => lane.keyAt(frame) != null
    ? lane.withoutKey(frame)
    : lane.withKey(frame, shown);

/// Applies a value typed into a member's value editor: it KEYS at
/// [frameIndex] — always, as every lane's value does (R9 #18, F-407: 「fx는
/// 키가 찍히는게 규칙」), the Pan as the Volume (Q7). Null on parse failure.
///
/// Accepted input: the Volume as a per cent (`80` or `80%`); the Pan as it
/// prints (`L50`, `R50`, `C`) or a signed per cent.
SeSound? seSoundWithLaneValueEdited(
  SeSound sound, {
  required String laneId,
  required int frameIndex,
  required String input,
}) {
  if (frameIndex < 0) {
    return null;
  }
  switch (laneId) {
    case seSoundVolumeLaneId:
      final percent = columnValueOf(input);
      return percent == null
          ? null
          : sound.copyWith(
              volume: sound.volume.withKey(
                frameIndex,
                volumeLaneNumbers.held(percent),
              ),
            );
    case seSoundPanLaneId:
      final pan = panOfLaneText(input);
      return pan == null
          ? null
          : sound.copyWith(pan: sound.pan.withKey(frameIndex, pan));
  }
  return null;
}

/// The key window's write on member lane [laneId]: the keys inside [frames]
/// named as [naming] says and given [pick]'s sides — ONE write of the lane,
/// the transform's (`PropertyLaneLens.keysWritten`). Null when nothing
/// changed.
SeSound? seSoundWithLaneKeysWritten(
  SeSound sound, {
  required String laneId,
  required Set<int> frames,
  ({String? name, int? preferredFrame})? naming,
  SeSound? adoptFrom,
  KeyTypePick pick = const KeyTypePick(),
}) => seSoundLaneLens(laneId)?.keysWritten(
  sound,
  frames: frames,
  naming: naming,
  adoptFrom: adoptFrom,
  pick: pick,
);

/// AE's group Reset for the 「오디오」 header — the rule every group header's
/// takes (`seNameTagWithGroupReset`): **키를 삭제하진 않고 값만 리셋**. A keyed
/// lane takes its rest — the Volume 100%, the Pan the middle — at
/// [frameIndexes]: at every one at the playhead, on the keys a lane range
/// covers alone ([keyedFramesOnly]); an unkeyed one already plays at its
/// rest. The Total is left as it is: it is the S row's bar, not a value of
/// this group (🗣️I-177 — `seSoundGroupLaneId`).
///
/// Null when nothing changed.
SeSound? seSoundWithGroupReset(
  SeSound sound, {
  required Iterable<int> frameIndexes,
  bool keyedFramesOnly = false,
}) {
  final frames = frameIndexes.where((frame) => frame >= 0).toSet();
  if (frames.isEmpty) {
    return null;
  }
  PropertyTrack<double> reset(PropertyTrack<double> lane, double rest) =>
      laneResetOver(
        lane,
        frames,
        rest,
        space: doubleKeySpace,
        keyedFramesOnly: keyedFramesOnly,
      );

  final next = sound.copyWith(
    volume: reset(sound.volume, 1.0),
    pan: reset(sound.pan, 0.0),
  );
  return next == sound ? null : next;
}
