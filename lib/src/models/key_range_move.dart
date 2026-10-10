/// Pure planning for KEY-RANGE moves (UI-R20 #2 second half, P3b-2): the
/// instruction rows' event spans shift with a range selection exactly like
/// drawing blocks slide — rigid group, one delta, all-or-nothing (an
/// illegal landing voids the whole plan).
///
/// ↩️The camera row's keyframes were planned here too, as a map of whole
/// poses. They are the keys of the camera's LANES, and shift by the lanes'
/// own range move (F-309, `FrameRangeMoveDrag`); what this file still says
/// of a transform track is what its header row shows.
library;

import 'camera_instruction.dart';
import 'cel_bank_lanes.dart';
import 'drawing_block_move.dart';
import 'key_mark.dart';
import 'key_range_shift.dart';
import 'layer.dart';
import 'transform_track.dart';

/// The transform group header's marks — its members' ([unionKeyMarks]):
/// the camera row and the layer's Transform header draw this one union.
///
/// 🚨F-17 (유저): 「**멤버 타입이 서로 다르면 헤더에 동그라미**」 — where the
/// keyed members disagree the union says so, rather than draw one member's
/// mark as though the group agreed.
///
/// ↩️It was two sets, the all-hold frames and the disagreeing ones, walked
/// together so a frame could never claim both; a map from frame to ONE
/// mark cannot.
Map<int, KeyMark> transformKeyMarkUnion(TransformTrack track) =>
    unionKeyMarks(track.lanes.map(keyMarksOf));

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
  final tracks = track.lanes;
  final names = <int, String>{};
  for (final frame in track.keyedFrames) {
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
    // An SE row is TRACK-owned, and a track-owned row is never linked
    // (`UpdateLayerTimelineCommand`), so no other lane shares its bank.
    sourceBank: CelBankLanes.unshared,
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

/// The instruction map with the events STARTING at [starts] shifted by
/// [frameDelta]; null when any landing dips below 0 or overlaps an
/// unmoved event's span ([shiftKeysAt]). The starts are the ones a range
/// selection holds — on a cut's rail, the spans its transition marks show,
/// mapped back to the global row.
Map<int, InstructionEvent>? shiftInstructionEventsAt({
  required Map<int, InstructionEvent> events,
  required Set<int> starts,
  required int frameDelta,
}) => shiftKeysAt(
  entries: events,
  moved: starts,
  frameDelta: frameDelta,
  extentOf: (event) => event.length,
);
