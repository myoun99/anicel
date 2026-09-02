part of '../timeline_controller.dart';

/// THE DRAWING FRAMES — whether a cell holds or may take a drawing, and
/// making one for a layer or for several, as a command — as their own
/// object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: seven controller members
/// shared. It reaches the controller through `_controller`.
class _TimelineDrawingFrames {
  _TimelineDrawingFrames(this._controller);

  final TimelineController _controller;

  bool hasDrawingAtCurrentFrame({required Layer layer}) {
    return _controller.hasSelectedFrameForLayer(layer);
  }

  bool isDrawingStartForLayer({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    return layer.timeline[frameIndex]?.isDrawing ?? false;
  }

  /// A drawing can be created on any uncovered cell — and INSIDE a block,
  /// where it divides that block instead (user's rule 2026-07-27).
  ///
  /// `1-----` with the cell cursor on the third frame becomes `1--o--`: the
  /// new drawing takes over the rest of the hold. Only a block's own START
  /// refuses, because there is nothing there to divide — the drawing the
  /// press would make is already there.
  ///
  /// D20/D21 (2026-08-18): a GHOST covering block is no coverage at all —
  /// 「데이터가 있는 곳 취급인 듯하나 고스트일 뿐이니 생성 허용」. Ghosts
  /// are projections the rederive pass wipes and rebuilds (the splice law
  /// already says "ghosts are not spliced"; the run [+] already authors
  /// into ghost space), so a repeat part's start (D20) and the hold
  /// ghost's start one cell after a held block (D21 — the same predicate,
  /// which is why fixing one fixes both) are authoring room.
  bool canCreateDrawingAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
    if (block == null || block.entry.ghost) {
      return true;
    }
    return frameIndex > block.startIndex;
  }

  void createDrawingFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    int length = 1,
    String? name,
    String? seName,
  }) => _makeDrawingFrame(
    layerId: layerId,
    frameId: frameId,
    length: length,
    name: name,
    seName: seName,
    apply: (before, after) =>
        _controller._applyLayerEdit(before: before, after: after),
  );

  /// ⛔ONE BODY, two entry points — see [createDrawingFrameCommandForLayer].
  void _makeDrawingFrame({
    required LayerId layerId,
    required FrameId frameId,
    required int length,
    required String? name,
    required String? seName,
    required void Function(Layer before, Layer after) apply,
  }) {
    if (length < 1) {
      throw ArgumentError.value(
        length,
        'length',
        'Drawing exposure length must be at least 1.',
      );
    }

    final before = _controller._requireLayer(layerId);
    final frameIndex = _controller._editFrameIndexFor(layerId);
    if (!canCreateDrawingAt(layer: before, frameIndex: frameIndex)) {
      throw StateError(
        'Timeline cell is already covered at index $frameIndex.',
      );
    }

    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    final covering = coveringDrawingBlockAt(before.timeline, frameIndex);
    // D19/D20/D21: a GHOST-covered cell authors like an EMPTY one — the
    // press makes a fresh 1-comma block (「원래 1칸 블록」), never a divide
    // of the projection (dividing a ghost wrote ghost-flagged data the
    // rederive pass silently deleted). The working copy sheds every ghost
    // up front: an authored entry overlapping a stale ghost would trip
    // the coverage invariant, ghost starts are not clamp walls, and the
    // rederive choke point rebuilds the projection clamped around the new
    // block right after this edit.
    nextTimeline.removeWhere((_, exposure) => exposure.ghost);
    final int clampedLength;
    // INSIDE a block: the press divides it, and the new drawing takes over
    // the rest of the hold — the frames do not move, the division does.
    // (The user's rule 2026-07-27 — REAL blocks only.)
    if (covering != null && !covering.entry.ghost) {
      final splitOffset = frameIndex - covering.startIndex;
      clampedLength = covering.endIndexExclusive - frameIndex;
      nextTimeline[covering.startIndex] = covering.entry.copyWith(
        length: splitOffset,
      );
      nextTimeline[frameIndex] = TimelineExposure.drawing(
        frameId,
        length: clampedLength,
        // The dots are the BLOCK's (they time these very frames), so the
        // ones past the division travel with the half they mark. The memo
        // stays with the left half: it describes that drawing.
        breakdownOffsets: [
          for (final offset in covering.entry.breakdownOffsets)
            if (offset > splitOffset) offset - splitOffset,
        ],
      );
    } else {
      // Clamp against the WORKING copy: after a ghost shed, the next
      // authored block is the honest wall (a ghost start is not one).
      final nextBlock = nextDrawingBlockAfter(nextTimeline, frameIndex);
      final maxLength = nextBlock == null
          ? length
          : nextBlock.startIndex - frameIndex;
      clampedLength = length > maxLength ? maxLength : length;
      nextTimeline[frameIndex] = TimelineExposure.drawing(
        frameId,
        length: clampedLength,
      );
    }
    final after = before.copyWith(
      frames: [
        ...before.frames,
        Frame(
          id: frameId,
          duration: clampedLength,
          strokes: const [],
          name: _controller._names.normalizeFrameName(name),
          seName: _controller._names.normalizeFrameName(seName),
        ),
      ],
      timeline: nextTimeline,
    );
    apply(before, after);
  }

  /// The same edit as [createDrawingFrameForLayer], handed back as a command
  /// this caller will EXECUTE and hold rather than push.
  ///
  /// 🚨I-10 wants ONE undo for 「the block appeared and I drew on it」, and
  /// the two halves happen at different MOMENTS: the block has to exist at
  /// pen-DOWN (there is nowhere for ink to go otherwise) and the stroke is
  /// committed at pen-UP. `runAsOneStep` groups commands run inside one
  /// synchronous body, so it cannot span that gap — the caller keeps this
  /// command and composes it with the stroke when the pen lifts.
  ///
  /// ⛔It shares [createDrawingFrameForLayer]'s body rather than copying it:
  /// the divide-a-held-block rule, the ghost shed and the clamp are one
  /// piece of reasoning and must not exist twice ([[no-copy-to-share]]).
  Command createDrawingFrameCommandForLayer({
    required LayerId layerId,
    required FrameId frameId,
    int length = 1,
    String? name,
    String? seName,
  }) {
    Command? made;
    _makeDrawingFrame(
      layerId: layerId,
      frameId: frameId,
      length: length,
      name: name,
      seName: seName,
      apply: (before, after) =>
          made = _controller._layerEditCommand(before: before, after: after),
    );
    return made!;
  }

  /// The cross-layer CREATE form (UI-R25 #3, the delete form's mirror):
  /// every layer's new drawings compose into ONE undo step. Each fill is
  /// (cut-local startIndex, length, frameId, name/seName) — indexes shift
  /// per layer like every edit (track-SE rows land on their global
  /// timeline). Fills whose cell is already covered are skipped, never
  /// thrown: the selection sweep offers only empty gaps, but a stale
  /// offer must not sink the whole composite.
  void createDrawingFramesForLayers(
    Map<
      LayerId,
      List<({int startIndex, int length, FrameId frameId, String? name})>
    >
    fillsByLayer, {
    String description = 'Create selected cells',
  }) {
    _controller._executeCommands(
      drawingFramesCommandsForLayers(fillsByLayer),
      description: description,
    );
  }

  /// The same authoring as [createDrawingFramesForLayers], handed back as
  /// commands so a caller can fold them into a LARGER single undo step —
  /// the range create spans camera/instruction rows too (R26 #1).
  List<Command> drawingFramesCommandsForLayers(
    Map<
      LayerId,
      List<({int startIndex, int length, FrameId frameId, String? name})>
    >
    fillsByLayer,
  ) {
    final commands = <Command>[];
    for (final entry in fillsByLayer.entries) {
      final before = _controller._requireLayer(entry.key);
      final offset = _controller._frameOffsetForLayer?.call(entry.key) ?? 0;
      final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
        before.timeline,
      );
      // D20: ghosts are authoring room — shed them from the working copy
      // (the same sentence as the single-cell verb; the rederive choke
      // point rebuilds the projection clamped around whatever lands, and
      // a layer where nothing lands discards this copy untouched).
      nextTimeline.removeWhere((_, exposure) => exposure.ghost);
      final newFrames = <Frame>[];
      for (final fill in entry.value) {
        final startIndex = fill.startIndex + offset;
        if (startIndex < 0 ||
            fill.length < 1 ||
            coveringDrawingBlockAt(nextTimeline, startIndex) != null) {
          continue;
        }
        final nextBlock = nextDrawingBlockAfter(nextTimeline, startIndex);
        final maxLength = nextBlock == null
            ? fill.length
            : nextBlock.startIndex - startIndex;
        final length = fill.length > maxLength ? maxLength : fill.length;
        if (length < 1) {
          continue;
        }
        nextTimeline[startIndex] = TimelineExposure.drawing(
          fill.frameId,
          length: length,
        );
        newFrames.add(
          Frame(
            id: fill.frameId,
            duration: length,
            strokes: const [],
            name: _controller._names.normalizeFrameName(fill.name),
          ),
        );
      }
      if (newFrames.isEmpty) {
        continue;
      }
      commands.add(
        _controller._layerEditCommand(
          before: before,
          after: before.copyWith(
            frames: [...before.frames, ...newFrames],
            timeline: nextTimeline,
          ),
        ),
      );
    }
    return commands;
  }
}
