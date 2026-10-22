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

/// The transform group header's names — its members' ([unionKeyNames]).
Map<int, String> transformKeyNameUnion(TransformTrack track) =>
    unionKeyNames(track.lanes);

/// The NAME [track]'s keys carry where they are written on a picture — the
/// one its lanes agree on ([transformKeyNameUnion]); a key whose lanes
/// disagree carries none, as an unnamed one does (유저 2026-09-30: 「레인끼리
/// 달라서 헤더가 ...으로 표시되는 경우 … 이름 안정해진거랑 같은 규칙으로」).
Map<int, String> transformKeyAgreedNames(TransformTrack track) => {
  for (final MapEntry(:key, :value) in transformKeyNameUnion(track).entries)
    if (value != unionMixedKeyName) key: value,
};

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
