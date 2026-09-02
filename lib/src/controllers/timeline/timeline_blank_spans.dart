part of '../timeline_controller.dart';

/// THE BLANK SPANS — the span a band can blank and blanking it across
/// layers — as their own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). It reaches the controller through `_controller`.
class _TimelineBlankSpans {
  _TimelineBlankSpans(this._controller);

  final TimelineController _controller;

  /// 🚨결정 14 ①ⓑ (유저 확정 2026-08-22) — **X BLANKS EXACTLY WHAT WAS
  /// SWEPT, AND NOTHING ELSE.**
  ///
  /// The playhead X truncates: it cuts the covering block off at the pressed
  /// frame and everything after goes uncovered. Over a BAND that would blank
  /// past the sweep — a block running 0..5 swept at 1..3 would lose 4 and 5
  /// as well — so the user chose the other reading: the swept cells go
  /// empty and the block's tail stays exactly where it stands.
  ///
  /// ⇒ a block straddling the span is left as TWO entries pointing at the
  /// same cel: the head keeps `[start, sweepStart)`, and a second exposure
  /// re-opens at `sweepEnd` with the remainder. Two entries on one frameId
  /// is not a new shape — it is what linked reuse already is
  /// ([_controller.linkedUseCountForLayerFrame] counts exactly this).
  ///
  /// ⛔Nothing shifts. This is not [_controller.spliceRunsForLayers]: a splice lifts
  /// cells and drags the tail back, which is the 잘라내기 verb. X leaves
  /// holes.
  ///
  /// ⚠️GHOSTS are skipped, the way the delete collector skips them: they are
  /// derived projections the rederive pass rebuilds, so blanking one edits
  /// nothing and would only look like it worked.
  ///
  /// ⚠️The block's MARKS travel with the head and are re-based on the tail:
  /// a dot at offset 4 of a block that now restarts at the sweep's end is
  /// still on the same drawn frame, and dropping it would silently lose
  /// authored data.
  Map<LayerId, ({int start, int endExclusive})> blankableSpanInBand({
    required Iterable<LayerId> layerIds,
    required int startIndex,
    required int endExclusive,
  }) {
    final byLayer = <LayerId, ({int start, int endExclusive})>{};
    for (final layerId in layerIds) {
      final layer = _controller._requireLayer(layerId);
      var covered = false;
      for (var index = startIndex; index < endExclusive; index += 1) {
        final block = coveringDrawingBlockAt(layer.timeline, index);
        if (block != null && !block.entry.ghost) {
          covered = true;
          break;
        }
      }
      if (covered) {
        byLayer[layerId] = (start: startIndex, endExclusive: endExclusive);
      }
    }
    return byLayer;
  }

  /// Blanks each row's swept span — ONE undo step.
  void blankSpansForLayers(
    Map<LayerId, ({int start, int endExclusive})> spansByLayer,
  ) {
    final commands = <Command>[];
    for (final entry in spansByLayer.entries) {
      final before = _controller._requireLayer(entry.key);
      final after = _blankedSpanLayer(
        before,
        entry.value.start,
        entry.value.endExclusive,
      );
      if (after != null) {
        commands.add(
          _controller._layerEditCommand(before: before, after: after),
        );
      }
    }
    _controller._executeCommands(commands, description: 'Blank selected cells');
  }

  Layer? _blankedSpanLayer(Layer before, int start, int endExclusive) {
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    var changed = false;
    // Walk the AUTHORED starts, not the frames: a block is edited once even
    // when the span covers ten of its cells.
    for (final blockStart in before.timeline.keys.toList()) {
      final entry = before.timeline[blockStart];
      if (entry == null || !entry.isDrawing || entry.ghost) {
        continue;
      }
      final length = entry.length ?? 1;
      final blockEnd = blockStart + length;
      if (blockEnd <= start || blockStart >= endExclusive) {
        continue; // Clear of the span.
      }
      changed = true;
      nextTimeline.remove(blockStart);
      if (blockStart < start) {
        nextTimeline[blockStart] = entry.copyWith(
          length: start - blockStart,
          breakdownOffsets: [
            for (final offset in entry.breakdownOffsets)
              if (offset < start - blockStart) offset,
          ],
        );
      }
      if (blockEnd > endExclusive) {
        final tailStart = endExclusive;
        final shift = tailStart - blockStart;
        nextTimeline[tailStart] = entry.copyWith(
          length: blockEnd - tailStart,
          // Offset 0 IS the drawing, so a dot that lands there is dropped:
          // the tail's first cell is now the block start.
          breakdownOffsets: [
            for (final offset in entry.breakdownOffsets)
              if (offset - shift > 0) offset - shift,
          ],
        );
      }
    }
    return changed ? before.copyWith(timeline: nextTimeline) : null;
  }
}
