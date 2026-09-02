import 'dart:collection';
import 'dart:math' as math;

import '../models/audio_clip.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/text_cel_style.dart';
import '../models/timeline_coverage.dart';
import 'cut_duplicate_helpers.dart' show duplicateFrameContent;
import '../models/timeline_exposure.dart';
import '../models/timeline_repeat.dart';
import '../models/timeline_splice.dart';
import '../services/command.dart';
import '../services/commands/update_cut_durations_command.dart';
import '../services/commands/update_layer_kind_command.dart';
import '../services/commands/update_layer_timeline_command.dart';
import '../services/history_manager.dart';
import '../services/project_repository.dart';

part 'timeline/timeline_marks.dart';
part 'timeline/timeline_exposure_edge.dart';
part 'timeline/timeline_blank_spans.dart';
part 'timeline/timeline_paste.dart';
part 'timeline/timeline_frame_names.dart';
part 'timeline/timeline_drawing_frames.dart';

/// Timeline queries and editing commands over the unified timeline model
/// (drawing blocks with explicit lengths + inbetween marks; emptiness is
/// the absence of coverage).
///
/// All coverage lookups go through `timeline_coverage.dart` (SplayTreeMap
/// navigation, O(log n)) so the controller, playback compositing and UI
/// mapping always agree.
class TimelineController {
  TimelineController({
    required ProjectRepository repository,
    required CutId? cutId,
    HistoryManager? historyManager,
    int initialFrameIndex = 0,
    int Function(LayerId layerId)? frameOffsetForLayer,
    List<Layer> Function()? trackSeLayers,
  }) : _repository = repository,
       _historyManager = historyManager,
       _cutId = cutId,
       _frameOffsetForLayer = frameOffsetForLayer,
       _trackSeLayers = trackSeLayers {
    selectFrameIndex(initialFrameIndex);
  }

  final ProjectRepository _repository;
  final HistoryManager? _historyManager;

  /// NULL = the session has no active cut (gap state, UI-R9 #3): queries
  /// resolve against no cut and mutations are unreachable (the UI stands
  /// down); [_requireLayer] still throws as the defensive backstop.
  final CutId? _cutId;

  /// Track-owned SE support: SE timelines live on the track's GLOBAL frame
  /// axis while this controller's playhead is cut-local. [_requireLayer]
  /// falls back to these GLOBAL layers, and every index-based mutation
  /// shifts by [_frameOffsetForLayer] (the active cut's global start for
  /// track-SE ids, 0 otherwise). Read-side `can*` gates keep taking the
  /// cut-local DISPLAY clones + local indexes — the same coverage answer.
  final int Function(LayerId layerId)? _frameOffsetForLayer;
  final List<Layer> Function()? _trackSeLayers;

  int _currentFrameIndex = 0;

  int _editFrameIndexFor(LayerId layerId) =>
      _currentFrameIndex + (_frameOffsetForLayer?.call(layerId) ?? 0);

  int get currentFrameIndex => _currentFrameIndex;

  void selectFrameIndex(int frameIndex) {
    if (frameIndex < 0) {
      throw ArgumentError.value(
        frameIndex,
        'frameIndex',
        'Timeline frame index cannot be negative.',
      );
    }

    _currentFrameIndex = frameIndex;
  }

  // --- Queries -------------------------------------------------------------

  int get authoredTimelineExtentFrameCount {
    final cut = _findCutOrNull();
    if (cut == null || cut.layers.isEmpty) {
      return 0;
    }

    var maxExtent = 0;
    for (final layer in cut.layers) {
      final extent = authoredTimelineExtent(layer.timeline);
      if (extent > maxExtent) {
        maxExtent = extent;
      }
    }
    return maxExtent;
  }

  /// The drawing block covering [frameIndex] (or the current frame).
  TimelineDrawingBlock? blockForLayerAt({
    required Layer layer,
    int? frameIndex,
  }) {
    final targetIndex = frameIndex ?? _currentFrameIndex;
    if (targetIndex < 0) {
      return null;
    }
    return coveringDrawingBlockAt(layer.timeline, targetIndex);
  }

  Frame? resolveFrameForLayer({required Layer layer, int? frameIndex}) {
    final frameId = blockForLayerAt(
      layer: layer,
      frameIndex: frameIndex,
    )?.frameId;
    if (frameId == null) {
      return null;
    }
    return _frameOrNull(layer: layer, frameId: frameId);
  }

  FrameId? resolveFrameIdForLayer({required Layer layer, int? frameIndex}) {
    return blockForLayerAt(layer: layer, frameIndex: frameIndex)?.frameId;
  }

  Frame? getSelectedFrameForLayer(Layer layer) {
    return resolveFrameForLayer(layer: layer);
  }

  FrameId? getSelectedFrameIdForLayer(Layer layer) {
    return getSelectedFrameForLayer(layer)?.id;
  }

  bool hasSelectedFrameForLayer(Layer layer) {
    return getSelectedFrameForLayer(layer) != null;
  }

  // ── the drawing frames: their own object ────────────────────────────
  //
  // A collaborator (controllers/timeline/timeline_drawing_frames.dart, a part of this
  // library). The controller keeps the public verbs as forwarders.
  late final _TimelineDrawingFrames _drawings = _TimelineDrawingFrames(this);

  bool hasDrawingAtCurrentFrame({required Layer layer}) =>
      _drawings.hasDrawingAtCurrentFrame(layer: layer);
  bool isDrawingStartForLayer({
    required Layer layer,
    required int frameIndex,
  }) => _drawings.isDrawingStartForLayer(layer: layer, frameIndex: frameIndex);
  bool canCreateDrawingAt({required Layer layer, required int frameIndex}) =>
      _drawings.canCreateDrawingAt(layer: layer, frameIndex: frameIndex);
  void createDrawingFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    int length = 1,
    String? name,
    String? seName,
  }) => _drawings.createDrawingFrameForLayer(
    layerId: layerId,
    frameId: frameId,
    length: length,
    name: name,
    seName: seName,
  );
  Command createDrawingFrameCommandForLayer({
    required LayerId layerId,
    required FrameId frameId,
    int length = 1,
    String? name,
    String? seName,
  }) => _drawings.createDrawingFrameCommandForLayer(
    layerId: layerId,
    frameId: frameId,
    length: length,
    name: name,
    seName: seName,
  );
  void createDrawingFramesForLayers(
    Map<
      LayerId,
      List<({int startIndex, int length, FrameId frameId, String? name})>
    >
    fillsByLayer, {
    String description = 'Create selected cells',
  }) => _drawings.createDrawingFramesForLayers(
    fillsByLayer,
    description: description,
  );
  List<Command> drawingFramesCommandsForLayers(
    Map<
      LayerId,
      List<({int startIndex, int length, FrameId frameId, String? name})>
    >
    fillsByLayer,
  ) => _drawings.drawingFramesCommandsForLayers(fillsByLayer);

  bool isHeldExposureForLayer({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0 ||
        isDrawingStartForLayer(layer: layer, frameIndex: frameIndex)) {
      return false;
    }
    return coveringDrawingBlockAt(layer.timeline, frameIndex) != null;
  }

  // ── the marks: their own object, in their own file ──────────────────
  //
  // A collaborator (controllers/timeline/timeline_marks.dart, a part of this
  // library). The controller keeps the public verbs as forwarders.
  late final _TimelineMarks _marks = _TimelineMarks(this);

  bool hasMarkAt({required Layer layer, required int frameIndex}) =>
      _marks.hasMarkAt(layer: layer, frameIndex: frameIndex);
  bool canToggleMarkAt({required Layer layer, required int frameIndex}) =>
      _marks.canToggleMarkAt(layer: layer, frameIndex: frameIndex);
  void toggleMarkForLayer({required LayerId layerId}) =>
      _marks.toggleMarkForLayer(layerId: layerId);
  Map<LayerId, List<int>> markableFramesInBand({
    required Iterable<LayerId> layerIds,
    required int startIndex,
    required int endIndexExclusive,
  }) => _marks.markableFramesInBand(
    layerIds: layerIds,
    startIndex: startIndex,
    endIndexExclusive: endIndexExclusive,
  );
  bool bandFramesAreAllMarked(Map<LayerId, List<int>> framesByLayer) =>
      _marks.bandFramesAreAllMarked(framesByLayer);
  void setMarksForFrames(
    Map<LayerId, List<int>> framesByLayer, {
    required bool marked,
  }) => _marks.setMarksForFrames(framesByLayer, marked: marked);

  int? exposureStartIndexForLayer({
    required Layer layer,
    required FrameId frameId,
  }) {
    for (final entry in layer.timeline.entries) {
      if (entry.value.isDrawing && entry.value.frameId == frameId) {
        return entry.key;
      }
    }
    return null;
  }

  int? effectiveDurationForLayerFrame({
    required Layer layer,
    required FrameId frameId,
  }) {
    final startIndex = exposureStartIndexForLayer(
      layer: layer,
      frameId: frameId,
    );
    if (startIndex == null) {
      return null;
    }
    return layer.timeline[startIndex]!.length;
  }

  int? effectiveDurationForLayerAt({required Layer layer, int? frameIndex}) {
    return blockForLayerAt(layer: layer, frameIndex: frameIndex)?.length;
  }

  int linkedUseCountForLayerFrame({
    required Layer layer,
    required FrameId frameId,
  }) {
    return layer.timeline.values
        .where((entry) => entry.isDrawing && entry.frameId == frameId)
        .length;
  }

  // --- Drawing creation ------------------------------------------------------

  // --- Cut exposure (the timesheet "X here" action) -------------------------

  /// Ends the covering block's hold just before [frameIndex] so the cell
  /// (and the rest of the old hold) becomes empty. Only meaningful on held
  /// cells — cutting at a block start would leave a zero-length block.
  bool canCutExposureAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
    return block != null && frameIndex > block.startIndex;
  }

  void cutExposureForLayer({required LayerId layerId}) {
    final before = _requireLayer(layerId);
    final frameIndex = _editFrameIndexFor(layerId);
    if (!canCutExposureAt(layer: before, frameIndex: frameIndex)) {
      return;
    }

    final block = coveringDrawingBlockAt(before.timeline, frameIndex)!;
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    nextTimeline[block.startIndex] = block.entry.copyWith(
      length: frameIndex - block.startIndex,
    );
    _applyLayerEdit(
      before: before,
      after: before.copyWith(timeline: nextTimeline),
    );
  }

  // --- Marks (block-owned inbetween dots) --------------------------------------

  // ── the blank spans: their own object ───────────────────────────────
  //
  // A collaborator (controllers/timeline/timeline_blank_spans.dart, a part of this
  // library). The controller keeps the public verbs as forwarders.
  late final _TimelineBlankSpans _blank = _TimelineBlankSpans(this);

  Map<LayerId, ({int start, int endExclusive})> blankableSpanInBand({
    required Iterable<LayerId> layerIds,
    required int startIndex,
    required int endExclusive,
  }) => _blank.blankableSpanInBand(
    layerIds: layerIds,
    startIndex: startIndex,
    endExclusive: endExclusive,
  );
  void blankSpansForLayers(
    Map<LayerId, ({int start, int endExclusive})> spansByLayer,
  ) => _blank.blankSpansForLayers(spansByLayer);

  // --- Cell deletion ----------------------------------------------------------

  /// Standing ANYWHERE inside a real drawing block deletes it (UI-R17 #1)
  /// — the old head-only rule made held cells feel dead.
  bool canDeleteCellAt({required Layer layer, required int frameIndex}) {
    final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
    return block != null && !block.entry.ghost;
  }

  void deleteCellForLayer({required LayerId layerId}) {
    final before = _requireLayer(layerId);
    final frameIndex = _editFrameIndexFor(layerId);
    if (!canDeleteCellAt(layer: before, frameIndex: frameIndex)) {
      return;
    }
    deleteBlocksForLayer(
      layerId: layerId,
      blockStartIndexes: [
        coveringDrawingBlockAt(before.timeline, frameIndex)!.startIndex,
      ],
    );
  }

  /// Deletes every block starting at [blockStartIndexes] in ONE undo step
  /// (UI-R17 #2 — multi-selection delete). Ghost instances are skipped
  /// (derived); frames no longer referenced anywhere are GC'd with them.
  void deleteBlocksForLayer({
    required LayerId layerId,
    required List<int> blockStartIndexes,
  }) {
    deleteBlocksForLayers({layerId: blockStartIndexes});
  }

  /// The cross-layer form (UI-R17 #8): every layer's deletions compose
  /// into ONE undo step.
  void deleteBlocksForLayers(Map<LayerId, List<int>> blockStartsByLayer) {
    final commands = <Command>[];
    for (final entry in blockStartsByLayer.entries) {
      final before = _requireLayer(entry.key);
      final after = _deletedBlocksLayer(before, entry.value);
      if (after != null) {
        commands.add(_layerEditCommand(before: before, after: after));
      }
    }
    _executeCommands(commands, description: 'Delete selected cells');
  }

  Layer? _deletedBlocksLayer(Layer before, List<int> blockStartIndexes) {
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    final removedFrameIds = <FrameId>{};
    for (final startIndex in blockStartIndexes) {
      final entry = before.timeline[startIndex];
      if (entry == null || !entry.isDrawing || entry.ghost) {
        continue;
      }
      nextTimeline.remove(startIndex);
      final frameId = entry.frameId;
      if (frameId != null) {
        removedFrameIds.add(frameId);
      }
    }
    if (nextTimeline.length == before.timeline.length) {
      return null;
    }
    var nextFrames = before.frames;
    final unreferenced = removedFrameIds
        .where((frameId) => !_timelineReferencesFrame(nextTimeline, frameId))
        .toSet();
    if (unreferenced.isNotEmpty) {
      nextFrames = before.frames
          .where((frame) => !unreferenced.contains(frame.id))
          .toList(growable: false);
    }
    return before.copyWith(
      frames: nextFrames,
      timeline: nextTimeline,
      audioClips: _audioClipsForFrames(before, nextFrames),
    );
  }

  /// The layer's audio clips minus links to frames that are not in
  /// [nextFrames] (REC1-A). A frame that leaves the layer takes its
  /// linked sounds with it — the AudioClip contract: the sound belongs
  /// to the instance. A kept dangling link plays nothing yet makes the
  /// media pool's remove-guard refuse the asset forever.
  List<AudioClip> _audioClipsForFrames(Layer before, List<Frame> nextFrames) {
    if (before.audioClips.isEmpty || identical(nextFrames, before.frames)) {
      return before.audioClips;
    }
    final liveIds = {for (final frame in nextFrames) frame.id};
    final kept = [
      for (final clip in before.audioClips)
        if (liveIds.contains(clip.frameId)) clip,
    ];
    return kept.length == before.audioClips.length ? before.audioClips : kept;
  }

  // --- Bulk retime (UI-R17 #3/#7) --------------------------------------------

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

    var prevOldEnd = blocks[firstRetimed].endIndexExclusive;
    var prevNewEnd = newStarts[firstRetimed] + newLengths[firstRetimed];
    for (var i = firstRetimed + 1; i < blocks.length; i += 1) {
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

    final next = SplayTreeMap<int, TimelineExposure>();
    for (var i = 0; i < blocks.length; i += 1) {
      next[newStarts[i]] = blocks[i].entry.copyWith(length: newLengths[i]);
    }
    final after = rederiveRunBehaviors(
      layer.copyWith(timeline: next),
      cutFrameCount: _cutFrameCount(),
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
      final before = _requireLayer(entry.key);
      final after = retimedLayerForBlocks(
        layer: before,
        newLengthByStart: entry.value,
      );
      if (after != null) {
        commands.add(_layerEditCommand(before: before, after: after));
      }
    }
    _executeCommands(commands, description: 'Set comma exposure');
  }

  /// Commits several layers' already-previewed drags as ONE undo step
  /// (the cross-layer bulk edge drag's release).
  void commitLayerTimelineDrags(List<({Layer before, Layer after})> edits) {
    final commands = <Command>[
      for (final edit in edits)
        if (edit.before != edit.after)
          _layerEditCommand(before: edit.before, after: edit.after),
    ];
    _executeCommands(commands, description: 'Adjust selected exposures');
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
          _layerEditCommand(before: edit.before, after: edit.after),
      if (durationsChanged)
        UpdateCutDurationsCommand(
          repository: _repository,
          before: beforeDurations,
          after: afterDurations,
          beforeGaps: beforeGaps,
          afterGaps: afterGaps,
        ),
    ];
    _executeCommands(commands, description: description);
  }

  void _executeCommands(List<Command> commands, {required String description}) {
    if (commands.isEmpty) {
      return;
    }
    final command = commands.length == 1
        ? commands.single
        : CompositeCommand(description: description, commands: commands);
    final historyManager = _historyManager;
    if (historyManager == null) {
      command.execute();
    } else {
      historyManager.execute(command);
    }
  }

  // --- Linked paste ------------------------------------------------------------

  // ── copy and paste: their own object ────────────────────────────────
  //
  // A collaborator (controllers/timeline/timeline_paste.dart, a part of this
  // library). The controller keeps the public verbs as forwarders.
  late final _TimelinePaste _paste = _TimelinePaste(this);

  bool canPasteLinkedFrameAt({
    required Layer layer,
    required int frameIndex,
    required FrameId copiedFrameId,
  }) => _paste.canPasteLinkedFrameAt(
    layer: layer,
    frameIndex: frameIndex,
    copiedFrameId: copiedFrameId,
  );
  void pasteLinkedFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
  }) => _paste.pasteLinkedFrameForLayer(layerId: layerId, frameId: frameId);
  void pasteIndependentFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required FrameId newFrameId,
  }) => _paste.pasteIndependentFrameForLayer(
    layerId: layerId,
    frameId: frameId,
    newFrameId: newFrameId,
  );
  TimelineClipRow copyRunForLayer({
    required LayerId layerId,
    required int index,
    required int count,
  }) => _paste.copyRunForLayer(layerId: layerId, index: index, count: count);

  // --- The one splice ----------------------------------------------------------

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
      final before = _requireLayer(run.layerId);
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
          if (_timelineReferencesFrame(nextTimeline, frame.id) ||
              !_timelineReferencesFrame(before.timeline, frame.id))
            frame,
      ];
      final after = before.copyWith(
        frames: nextFrames,
        timeline: nextTimeline,
        audioClips: _audioClipsForFrames(before, nextFrames),
      );
      if (before != after) {
        commands.add(_layerEditCommand(before: before, after: after));
      }
    }
    _executeCommands(commands, description: description);
  }

  // --- Frame rename / link -------------------------------------------------------

  // ── the frame names: their own object ───────────────────────────────
  //
  // A collaborator (controllers/timeline/timeline_frame_names.dart, a part of this
  // library). The controller keeps the public verbs as forwarders.
  late final _TimelineFrameNames _names = _TimelineFrameNames(this);

  bool canRenameFrameAt({required Layer layer, required int frameIndex}) =>
      _names.canRenameFrameAt(layer: layer, frameIndex: frameIndex);
  FrameId? conflictingFrameIdForRename({
    required Layer layer,
    required FrameId frameId,
    required String? name,
  }) => _names.conflictingFrameIdForRename(
    layer: layer,
    frameId: frameId,
    name: name,
  );
  void renameFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required String? name,
    bool allowDuplicateName = false,
    String? seName,
    bool updateSeName = false,
  }) => _names.renameFrameForLayer(
    layerId: layerId,
    frameId: frameId,
    name: name,
    allowDuplicateName: allowDuplicateName,
    seName: seName,
    updateSeName: updateSeName,
  );

  /// Sets a TEXT cel's parameters (R5, §6-s) — the frame edit travels the
  /// same before/after layer command as a rename, so linked-cut mirroring
  /// and the single undo step come with it. The raster projection is the
  /// session's business (the bake sweep re-renders from the model).
  void setTextContentForFrame({
    required LayerId layerId,
    required FrameId frameId,
    required TextCelContent? textContent,
  }) {
    final before = _requireLayer(layerId);
    _requireFrameInLayer(layer: before, frameId: frameId);
    final nextFrames = before.frames
        .map(
          (frame) => frame.id == frameId
              ? frame.copyWith(textContent: textContent)
              : frame,
        )
        .toList(growable: false);
    final after = before.copyWith(frames: nextFrames);
    if (after == before) {
      return;
    }

    _applyLayerEdit(before: before, after: after);
  }

  /// Rasterizes a TEXT layer (§6-s: "래스터라이즈로 드로잉이 된다"): the
  /// row BECOMES an animation layer — every cel's parameters go, the baked
  /// pixels stay, and the brush unlocks. One undo restores the kind and
  /// every frame's parameters together.
  ///
  /// Two commands compose the step because they mirror DIFFERENTLY: the
  /// frames edit mirrors the shared cel bank, and the KIND must travel
  /// [UpdateLayerKindCommand] so every 겸용 member converts together — a
  /// kind smuggled through the frames funnel left linked siblings as
  /// content-less text rows, and the bake sweep blank-baked the shared
  /// bank both cuts display.
  void rasterizeTextLayer({required LayerId layerId}) {
    final cutId = _cutId;
    if (cutId == null) {
      return;
    }
    final before = _requireLayer(layerId);
    if (before.kind != LayerKind.text) {
      return;
    }
    final strippedFrames = before.frames
        .map((frame) => frame.copyWith(textContent: null))
        .toList(growable: false);
    final command = CompositeCommand(
      description: 'Rasterize text layer',
      commands: [
        _layerEditCommand(
          before: before,
          after: before.copyWith(frames: strippedFrames),
        ),
        UpdateLayerKindCommand(
          repository: _repository,
          cutId: cutId,
          layerId: layerId,
          kind: LayerKind.animation,
        ),
      ],
    );
    final historyManager = _historyManager;
    if (historyManager == null) {
      command.execute();
    } else {
      historyManager.execute(command);
    }
  }

  void linkFrameForLayer({
    required LayerId layerId,
    required FrameId sourceFrameId,
    required FrameId targetFrameId,
  }) {
    final before = _requireLayer(layerId);
    _requireFrameInLayer(layer: before, frameId: sourceFrameId);
    _requireFrameInLayer(layer: before, frameId: targetFrameId);
    if (sourceFrameId == targetFrameId) {
      return;
    }

    final nextTimeline = SplayTreeMap<int, TimelineExposure>();
    for (final entry in before.timeline.entries) {
      final exposure = entry.value;
      if (exposure.isDrawing && exposure.frameId == sourceFrameId) {
        nextTimeline[entry.key] = exposure.copyWith(frameId: targetFrameId);
      } else {
        nextTimeline[entry.key] = exposure;
      }
    }

    var nextFrames = before.frames;
    if (!_timelineReferencesFrame(nextTimeline, sourceFrameId)) {
      nextFrames = before.frames
          .where((frame) => frame.id != sourceFrameId)
          .toList(growable: false);
    }

    final after = before.copyWith(
      frames: nextFrames,
      timeline: nextTimeline,
      audioClips: _audioClipsForFrames(before, nextFrames),
    );
    if (after == before) {
      return;
    }

    _applyLayerEdit(before: before, after: after);
  }

  // --- Comma adjustment (TVPaint-style edge shift) ------------------------------

  // ── the exposure edge: its own object, in its own file ──────────────
  //
  // A collaborator (controllers/timeline/timeline_exposure_edge.dart, a part of this
  // library). The controller keeps the public verbs as forwarders.
  late final _TimelineExposureEdge _edge = _TimelineExposureEdge(this);

  bool canShiftExposureEdge({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) => _edge.canShiftExposureEdge(
    layer: layer,
    blockStartIndex: blockStartIndex,
    edge: edge,
    delta: delta,
  );
  Layer? shiftedLayerForEdge({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) => _edge.shiftedLayerForEdge(
    layer: layer,
    blockStartIndex: blockStartIndex,
    edge: edge,
    delta: delta,
  );
  void shiftExposureEdge({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) => _edge.shiftExposureEdge(
    layerId: layerId,
    blockStartIndex: blockStartIndex,
    edge: edge,
    delta: delta,
  );
  int clampExposureEdgeDelta({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) => _edge.clampExposureEdgeDelta(
    layer: layer,
    blockStartIndex: blockStartIndex,
    edge: edge,
    delta: delta,
  );

  /// Commits an already-applied drag as one undoable step: the repository
  /// currently holds [after]; the command's execute is idempotent.
  void commitLayerTimelineDrag({required Layer before, required Layer after}) {
    if (before == after) {
      return;
    }
    _applyLayerEdit(before: before, after: after);
  }

  // --- Shift internals -----------------------------------------------------------

  /// How far the start edge can grow backward: empty space in front plus
  /// the gaps the preceding glued/pushed chain can absorb before its head
  /// hits frame 0. Mirrors the shift algorithm's contact rules.
  int _startEdgeGrowRoom(
    SplayTreeMap<int, TimelineExposure> timeline, {
    required int blockStartIndex,
  }) {
    // Total space before the block minus the total length of all blocks in
    // front of it: pushing can compact every gap, so that difference is
    // exactly the reachable room.
    var precedingLengths = 0;
    for (final entry in timeline.entries) {
      if (entry.key >= blockStartIndex) {
        break;
      }
      if (entry.value.isDrawing) {
        precedingLengths += entry.value.length!;
      }
    }
    return blockStartIndex - precedingLengths;
  }

  // --- Shared internals -------------------------------------------------------

  /// Whether an AUTHORED exposure still points at [frameId] — the question
  /// every cel-lifetime decision in this file is really asking.
  ///
  /// 🚨⛔`!ghost`, and the filter is the whole fix for a measured defect.
  /// A ghost is DERIVED: a repeat run recomputes its instances from the
  /// authored exposure that owns them. Counting one as a reference means
  /// "keep this cel because something that only exists while the cel's own
  /// block exists is pointing at it" — circular, and it comes apart the
  /// moment the block goes. Put an end-hold on an animation row and delete
  /// the cel and you got `frames=1 / timeline={}`: the ghosts kept the cel
  /// alive through the delete, then re-derived themselves out of existence
  /// and left it orphaned.
  ///
  /// ⚠️Measured before changing it, because the note that filed this said
  /// "셀뱅크·undo 파급이라 별도 라운드": there is none. [BrushFrameStore]
  /// has no removal API at all (it is append-only), so what leaves
  /// `layer.frames` frees nothing there either way; and all three callers
  /// build an `after` layer for a command whose undo restores `before`
  /// wholesale, so the shape of an undo step does not change. The blast
  /// radius is `layer.frames` and nothing else.
  ///
  /// ⛔And no caller wants the other answer. Deletion, splice and relink
  /// each ask "is this cel still spoken for by something a person wrote";
  /// a ghost is never that.
  bool _timelineReferencesFrame(
    Map<int, TimelineExposure> timeline,
    FrameId frameId,
  ) {
    return timeline.values.any(
      (exposure) =>
          exposure.isDrawing && !exposure.ghost && exposure.frameId == frameId,
    );
  }

  Frame _requireFrameInLayer({required Layer layer, required FrameId frameId}) {
    for (final frame in layer.frames) {
      if (frame.id == frameId) {
        return frame;
      }
    }

    throw StateError('Frame not found in layer ${layer.id}: $frameId');
  }

  /// THE run-behavior normalize choke point (UI-R8/R9): every timeline
  /// edit builds through here, so the derived ghost entries re-arrange
  /// with whatever the edit did to their source run (live sync). Layers
  /// without behaviors/ghosts pass through untouched (identity).
  UpdateLayerTimelineCommand _layerEditCommand({
    required Layer before,
    required Layer after,
  }) {
    return UpdateLayerTimelineCommand(
      repository: _repository,
      before: before,
      after: rederiveRunBehaviors(after, cutFrameCount: _cutFrameCount()),
    );
  }

  void _applyLayerEdit({required Layer before, required Layer after}) {
    final command = _layerEditCommand(before: before, after: after);
    final historyManager = _historyManager;
    if (historyManager == null) {
      command.execute();
    } else {
      historyManager.execute(command);
    }
  }

  Layer _requireLayer(LayerId layerId) {
    final cut = _findCutOrNull();
    for (final layer in cut?.layers ?? const <Layer>[]) {
      if (layer.id == layerId) {
        return layer;
      }
    }

    // 🚨A TRACK-OWNED ROW IS NOT A CUT'S TENANT (유저 H11, 2026-08-22).
    //
    // > 「다시말하지만 각 행들은 **독립적인 글로벌행**이라 뭐든 가능해야함」
    //
    // Track-owned SE rows: mutations edit the GLOBAL layer (never the
    // cut-local display clone) — indexes shift via _editFrameIndexFor.
    //
    // ⛔This lookup used to demand the cut FIRST and throw without one, so
    // the fallback below was unreachable in a gap parking. Three separate
    // gates then had to say "a parked playhead has no cut to lens through"
    // — the same sentence three times, guarding one lookup. The row lives
    // on the TRACK, so the gap has no bearing on finding it: the shift it
    // asks for is `activeCutGlobalStartFrame`, which is 0 with no cut,
    // which is exactly the identity a global row wants.
    for (final layer in _trackSeLayers?.call() ?? const <Layer>[]) {
      if (layer.id == layerId) {
        return layer;
      }
    }

    if (cut == null) {
      throw StateError('Cut not found: $_cutId');
    }
    throw StateError('Layer not found: $layerId');
  }

  /// The run-behavior fill boundary: hold/repeat edges fill ghosts to the
  /// cut end. Zero (no cut) renders no end-side ghosts.
  int _cutFrameCount() => _findCutOrNull()?.duration ?? 0;

  Cut? _findCutOrNull() {
    final project = _repository.currentProject;
    if (project == null || _cutId == null) {
      return null;
    }

    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == _cutId) {
          return cut;
        }
      }
    }

    return null;
  }

  Frame? _frameOrNull({required Layer layer, required FrameId frameId}) {
    for (final frame in layer.frames) {
      if (frame.id == frameId) {
        return frame;
      }
    }
    return null;
  }
}
