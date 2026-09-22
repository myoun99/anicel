import 'dart:collection';

import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/onion_skin_settings.dart';
import '../models/timeline_coverage.dart';
import '../models/timeline_exposure.dart';

/// One onion frame to ghost onto the canvas.
class OnionSkinFramePlan {
  const OnionSkinFramePlan({
    required this.frameId,
    required this.frameIndex,
    required this.opacity,
    this.tint,
  });

  final FrameId frameId;

  /// The sheet index this ghost's drawing is exposed at.
  ///
  /// ★Carried so the ghost's EFFECT chain samples at its OWN time. Read at
  /// the playhead instead, a keyframed brightness would paint a past
  /// drawing with the present frame's value — a ghost is a picture of THEN
  /// and has to answer with then's numbers.
  final int frameIndex;

  final double opacity;

  /// ARGB tint (Colors mode); null shows the artwork's own colors.
  final int? tint;
}

/// Resolves which of the ACTIVE layer's cels ghost at [frameIndex].
///
/// [OnionSkinStep.blocks] (the default) walks UNITS: a held block is one
/// unit, an EMPTY STRETCH is one unit however long it is, linked-cel
/// repeats of an already-collected (or the current) cel are skipped, and a
/// silent peg still consumes its slot (peg 2 stays "two units back" while
/// peg 1 is at 0).
///
/// 🚨★★AN EMPTY STRETCH SPENDS ITS PEG AND SHOWS NOTHING (F-175, 유저
/// 2026-09-21): 「어니언스킨 블록 단위일때, 사이에 빈 공간 있는데도 그
/// 너머의 첫번째 블럭이 인식됨. 빈 공간 한칸은 블럭으로서 한칸으로 쳐서
/// 빈공간이면 다음 1번의 어니언스킨 안보이게.」 The walk used to jump
/// over the stretch to the drawing beyond it, so peg 1 ghosted a drawing
/// the sheet shows as two steps away. See [nextUnitStartAfter].
///
/// [OnionSkinStep.frames] walks the sheet instead: peg k is whatever is
/// exposed k frames away. Inside a hold that is the drawing already on
/// screen, and ghosting it would only paint the current drawing under
/// itself — so it draws nothing.
List<OnionSkinFramePlan> planOnionSkin({
  required Layer layer,
  required int frameIndex,
  required OnionSkinSettings settings,
}) {
  if (frameIndex < 0) {
    return const [];
  }
  final timeline = SplayTreeMap<int, TimelineExposure>.of(layer.timeline);
  final currentFrameId = exposedFrameIdAt(timeline, frameIndex);

  List<OnionSkinFramePlan> collectFrames({
    required List<OnionPeg> pegs,
    required int? tint,
    required int direction,
  }) {
    final plans = <OnionSkinFramePlan>[];
    for (var peg = 0; peg < pegs.length; peg += 1) {
      final index = frameIndex + direction * (peg + 1);
      if (index < 0) {
        break;
      }
      if (!pegs[peg].shows) {
        continue;
      }
      final frameId = exposedFrameIdAt(timeline, index);
      if (frameId == null || frameId == currentFrameId) {
        continue;
      }
      plans.add(
        OnionSkinFramePlan(
          frameId: frameId,
          frameIndex: index,
          opacity: pegs[peg].opacity,
          tint: settings.mode == OnionSkinMode.colors ? tint : null,
        ),
      );
    }
    return plans;
  }

  List<OnionSkinFramePlan> collectBlocks({
    required List<OnionPeg> pegs,
    required int? tint,
    required int? Function(int cursor) nextBlockStart,
    required int startCursor,
  }) {
    final plans = <OnionSkinFramePlan>[];
    final seen = <FrameId>{?currentFrameId};
    var cursor = startCursor;
    for (final peg in pegs) {
      int? blockStart;
      FrameId? blockFrameId;
      var emptyStretch = false;
      // Advance to the next unit: an empty stretch, or a block showing a
      // cel we have not ghosted yet.
      while (true) {
        blockStart = nextBlockStart(cursor);
        if (blockStart == null) {
          break;
        }
        cursor = blockStart;
        final exposure = timeline[blockStart];
        if (exposure == null) {
          emptyStretch = true;
          break;
        }
        blockFrameId = exposure.frameId;
        if (blockFrameId != null && seen.add(blockFrameId)) {
          break;
        }
        blockFrameId = null;
      }
      if (blockStart == null) {
        break;
      }
      if (emptyStretch) {
        // F-175: the stretch IS this peg's step — spent, nothing to ghost.
        continue;
      }
      if (blockFrameId == null) {
        break;
      }
      if (peg.shows) {
        plans.add(
          OnionSkinFramePlan(
            frameId: blockFrameId,
            frameIndex: blockStart,
            opacity: peg.opacity,
            tint: settings.mode == OnionSkinMode.colors ? tint : null,
          ),
        );
      }
    }
    return plans;
  }

  // The BEFORE walk starts from the current UNIT's start (so a held
  // mid-block playhead still sees the previous unit, not its own block,
  // and a playhead standing in an empty stretch counts that stretch as
  // where it is); the AFTER walk from the current index.
  final frameSteps = settings.step == OnionSkinStep.frames;
  final before = frameSteps
      ? collectFrames(
          pegs: settings.beforePegs,
          tint: settings.tintBefore,
          direction: -1,
        )
      : collectBlocks(
          pegs: settings.beforePegs,
          tint: settings.tintBefore,
          startCursor: unitStartAt(timeline, frameIndex),
          nextBlockStart: (cursor) => previousUnitStartBefore(timeline, cursor),
        );
  final after = frameSteps
      ? collectFrames(
          pegs: settings.afterPegs,
          tint: settings.tintAfter,
          direction: 1,
        )
      : collectBlocks(
          pegs: settings.afterPegs,
          tint: settings.tintAfter,
          startCursor: frameIndex,
          nextBlockStart: (cursor) => nextUnitStartAfter(timeline, cursor),
        );

  // Furthest ghosts paint first (bottom), nearest last, before then after.
  return [...before.reversed, ...after];
}
