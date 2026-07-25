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
    required this.opacity,
    this.tint,
  });

  final FrameId frameId;
  final double opacity;

  /// ARGB tint (Colors mode); null shows the artwork's own colors.
  final int? tint;
}

/// Resolves which of the ACTIVE layer's cels ghost at [frameIndex].
///
/// [OnionSkinStep.blocks] (the default) walks DRAWINGS: peg k is the
/// (k+1)-th unique drawing before/after the current exposure, holds are
/// respected (a held block is one drawing), linked-cel repeats of an
/// already-collected (or the current) cel are skipped, and a silent peg
/// still consumes its slot (peg 2 stays "two drawings back" while peg 1
/// is at 0).
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
      // Advance to the next block showing a cel we have not ghosted yet.
      while (true) {
        blockStart = nextBlockStart(cursor);
        if (blockStart == null) {
          break;
        }
        cursor = blockStart;
        blockFrameId = timeline[blockStart]?.frameId;
        if (blockFrameId != null && seen.add(blockFrameId)) {
          break;
        }
        blockFrameId = null;
      }
      if (blockStart == null || blockFrameId == null) {
        break;
      }
      if (peg.shows) {
        plans.add(
          OnionSkinFramePlan(
            frameId: blockFrameId,
            opacity: peg.opacity,
            tint: settings.mode == OnionSkinMode.colors ? tint : null,
          ),
        );
      }
    }
    return plans;
  }

  // The BEFORE walk starts from the current block's START (so a held
  // mid-block playhead still sees the previous drawing, not its own
  // block); the AFTER walk from the current index.
  final currentBlock = coveringDrawingBlockAt(timeline, frameIndex);
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
          startCursor: currentBlock?.startIndex ?? frameIndex,
          nextBlockStart: (cursor) =>
              previousDrawingBlockBefore(timeline, cursor)?.startIndex,
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
          nextBlockStart: (cursor) =>
              nextDrawingBlockAfter(timeline, cursor)?.startIndex,
        );

  // Furthest ghosts paint first (bottom), nearest last, before then after.
  return [...before.reversed, ...after];
}
