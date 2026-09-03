part of '../timeline_controller.dart';

/// RETIMING — blocks given new lengths on a layer or across layers, runs
/// spliced, and the timeline drags committed with their cut durations —
/// as their own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: seven controller members
/// shared. It reaches the controller through `_controller`.
class _TimelineRetime {
  _TimelineRetime(this._controller);

  final TimelineController _controller;

  /// The layer with each block in [newLengthByStart] resized to its new
  /// exposure length, everything downstream rippling with the edge-shift
  /// contact rules: glued blocks STAY glued (so shrinking a selected run
  /// packs it — 1--2--3-- set to 1콤마 reads 123, the TVP compaction),
  /// separated blocks keep their own start unless overlapped. Blocks
  /// before the first retimed one never move. Ghost entries cannot be
  /// retimed (derived); returns null when nothing changes.
  Layer? retimedLayerForBlocks({
    required Layer layer,
    required Map<int, int> newLengthByStart,
  }) {
    final blocks = drawingBlocks(layer.timeline);
    final newStarts = List<int>.generate(
      blocks.length,
      (i) => blocks[i].startIndex,
      growable: false,
    );
    final newLengths = List<int>.generate(
      blocks.length,
      (i) => blocks[i].length,
      growable: false,
    );
    var firstRetimed = -1;
    for (var i = 0; i < blocks.length; i += 1) {
      final requested = newLengthByStart[blocks[i].startIndex];
      if (requested == null || blocks[i].entry.ghost) {
        continue;
      }
      newLengths[i] = math.max(1, requested);
      if (firstRetimed == -1) {
        firstRetimed = i;
      }
    }
    if (firstRetimed == -1) {
      return null;
    }

    _relayBlocksAfter(blocks, newStarts, newLengths, firstRetimed);

    final next = SplayTreeMap<int, TimelineExposure>();
    for (var i = 0; i < blocks.length; i += 1) {
      next[newStarts[i]] = blocks[i].entry.copyWith(length: newLengths[i]);
    }
    final after = rederiveRunBehaviors(
      layer.copyWith(timeline: next),
      cutFrameCount: _controller._cutFrameCount(),
    );
    return after == layer ? null : after;
  }

  /// Commits [retimedLayerForBlocks] as one undo step (the 1/2/3/4/N
  /// comma buttons' path).
  void retimeBlocksForLayer({
    required LayerId layerId,
    required Map<int, int> newLengthByStart,
  }) {
    retimeBlocksForLayers({layerId: newLengthByStart});
  }

  /// The cross-layer form (UI-R17 #8): every layer's retime composes into
  /// ONE undo step.
  void retimeBlocksForLayers(Map<LayerId, Map<int, int>> newLengthsByLayer) {
    final commands = <Command>[];
    for (final entry in newLengthsByLayer.entries) {
      final before = _controller._requireLayer(entry.key);
      final after = retimedLayerForBlocks(
        layer: before,
        newLengthByStart: entry.value,
      );
      if (after != null) {
        commands.add(
          _controller._layerEditCommand(before: before, after: after),
        );
      }
    }
    _controller._executeCommands(commands, description: 'Set comma exposure');
  }

  /// Commits already-previewed layer drags TOGETHER with the cut duration
  /// and gap changes they imply, as ONE undo step.
  ///
  /// A storyboard row and its cut's length are one thing (feedback #5/#9):
  /// re-timing the row's commas moves the cut's end, and undoing half of
  /// that would leave a drawing outside its cut. The fade re-anchor maps
  /// are gone (R4): fade keys are TRACK data on the global axis, and a
  /// cut resize moves none of them.
  void commitLayerTimelineDragsWithCutDurations({
    required List<({Layer before, Layer after})> edits,
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
    Map<CutId, int> beforeGaps = const {},
    Map<CutId, int> afterGaps = const {},
    required String description,
  }) {
    final durationsChanged =
        afterDurations.entries.any(
          (entry) => beforeDurations[entry.key] != entry.value,
        ) ||
        afterGaps.entries.any((entry) => beforeGaps[entry.key] != entry.value);
    final commands = <Command>[
      for (final edit in edits)
        if (edit.before != edit.after)
          _controller._layerEditCommand(before: edit.before, after: edit.after),
      if (durationsChanged)
        UpdateCutDurationsCommand(
          repository: _controller._repository,
          before: beforeDurations,
          after: afterDurations,
          beforeGaps: beforeGaps,
          afterGaps: afterGaps,
        ),
    ];
    _controller._executeCommands(commands, description: description);
  }

  /// 🚨★★★ THE ONE SPLICE (T2·T3) — every row's lift and insert in ONE undo.
  ///
  /// 유저 확정 2026-08-13: 「N칸을 들어내고 클립을 넣는다」에서 **N만 다르다**
  /// — 붙여넣기(선택 없음)는 N 0, 갈아끼우기는 N 선택길이, 잘라내기는 클립이
  /// 없는 쪽. So there is one entry point and the callers differ only in what
  /// they pass, rather than three verbs that have to be kept agreeing.
  ///
  /// ⛔The cut's length is never consulted. 「컷 길이는 소재와 관계없다」 —
  /// blocks pushed past the end line belong past the end line.
  ///
  /// [bornFrames] are the independent paste's new cels, which join the layer
  /// in the same command that first points at them.
  void spliceRunsForLayers({
    required List<
      ({
        LayerId layerId,
        int index,
        int liftCount,
        TimelineClipRow? clip,
        List<Frame> bornFrames,
      })
    >
    runs,
    required String description,
  }) {
    final commands = <Command>[];
    for (final run in runs) {
      final before = _controller._requireLayer(run.layerId);
      final nextTimeline = spliceTimeline(
        timeline: before.timeline,
        index: run.index,
        liftCount: run.liftCount,
        clip: run.clip,
      );
      // A cel nothing points at any more leaves with the exposure that was
      // its last use — the same bookkeeping the retired relink branch did,
      // now asked of the WHOLE row rather than of one replaced block.
      //
      // ⚠️Only cels THIS splice orphaned. A layer may legitimately hold a
      // cel no exposure points at (drawn, then its block deleted), and
      // "unreferenced after" alone would take those out with it — a splice
      // three rows away silently emptying the bank.
      final nextFrames = [
        for (final frame in [...before.frames, ...run.bornFrames])
          if (_controller._timelineReferencesFrame(nextTimeline, frame.id) ||
              !_controller._timelineReferencesFrame(before.timeline, frame.id))
            frame,
      ];
      final after = before.copyWith(
        frames: nextFrames,
        timeline: nextTimeline,
        audioClips: _controller._audioClipsForFrames(before, nextFrames),
      );
      if (before != after) {
        commands.add(
          _controller._layerEditCommand(before: before, after: after),
        );
      }
    }
    _controller._executeCommands(commands, description: description);
  }
}

/// Re-lays the blocks after [from] once its start or length changed: a
/// block glued to its predecessor's OLD end follows the NEW end, any other
/// keeps its start unless the new end pushes it. The one law the comma
/// edge and the retime move neighbours by — each used to spell it.
void _relayBlocksAfter(
  List<TimelineDrawingBlock> blocks,
  List<int> newStarts,
  List<int> newLengths,
  int from,
) {
  var prevOldEnd = blocks[from].endIndexExclusive;
  var prevNewEnd = newStarts[from] + newLengths[from];
  for (var i = from + 1; i < blocks.length; i += 1) {
    final block = blocks[i];
    final glued = block.startIndex == prevOldEnd;
    var start = glued ? prevNewEnd : block.startIndex;
    if (start < prevNewEnd) {
      start = prevNewEnd;
    }
    newStarts[i] = start;
    prevOldEnd = block.endIndexExclusive;
    prevNewEnd = start + newLengths[i];
  }
}
