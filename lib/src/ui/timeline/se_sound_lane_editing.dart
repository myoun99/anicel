// Per-lane edits on an SE row's SOUND (I-140), keyed by the lane ids
// [seSoundPropertyLanes] emits. Every function returns the edited sound
// (or null when the edit is a no-op / not a sound lane) — callers commit it
// as ONE undo step, exactly like the name tag's and the transform's.

import '../../models/property_track.dart' show KeyTypePick;
import '../../models/se_sound.dart';
import '../text/readout_text.dart' show columnValueOf;
import 'se_sound_lane_policy.dart';

/// Adds a Volume key at [frameIndex] holding what the row plays there
/// (AE: keying a property freezes what it currently shows), or removes the
/// one there — the keyframe navigator's diamond toggle. The Pan holds no
/// keys (I-140-Q3).
SeSound? seSoundWithLaneKeyToggled(
  SeSound sound, {
  required String laneId,
  required int frameIndex,
}) {
  if (frameIndex < 0 || laneId != seSoundVolumeLaneId) {
    return null;
  }
  final volume = sound.volume;
  return sound.copyWith(
    volume: volume.keyAt(frameIndex) != null
        ? volume.withoutKey(frameIndex)
        : volume.withKey(frameIndex, sound.volumeAt(frameIndex.toDouble())),
  );
}

/// Applies a value typed into a member's value editor. The Volume KEYS at
/// [frameIndex] — always, as every lane's value does (R9 #18, F-407: 「fx는
/// 키가 찍히는게 규칙」); the Total (I-145-Q1) and the Pan (I-140-Q3) are the
/// row's one value each and take it as it is — the speaker's window writes
/// the Total through here too. Null on parse failure.
///
/// Accepted input: the Volume and the Total as a per cent (`80` or `80%`);
/// the Pan as it prints (`L50`, `R50`, `C`) or a signed per cent.
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
    case seSoundTotalVolumeLaneId:
      final percent = columnValueOf(input);
      return percent == null
          ? null
          : sound.copyWith(totalVolume: volumeLaneNumbers.held(percent));
    case seSoundPanLaneId:
      final pan = panOfLaneText(input);
      return pan == null ? null : sound.copyWith(pan: pan);
  }
  return null;
}

/// The key window's write on member lane [laneId]: the keys inside [frames]
/// named as [naming] says and given [pick]'s sides — ONE write of the lane,
/// the transform's (`PropertyLaneLens.keysWritten`). Null when nothing
/// changed, and for the Pan, which holds no keys.
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
/// Volume takes 100% at [frameIndexes] — at every one at the playhead, on
/// the keys a lane range covers alone ([keyedFramesOnly]); an unkeyed one
/// already plays at 100%. The Total goes back to 100%, the Pan to the
/// middle.
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
  var volume = sound.volume;
  for (final frame in frames) {
    if (sound.isKeyed &&
        (!keyedFramesOnly || sound.volume.keyAt(frame) != null)) {
      volume = volume.withKey(frame, 1.0);
    }
  }
  final next = sound.copyWith(pan: 0.0, totalVolume: 1.0, volume: volume);
  return next == sound ? null : next;
}
