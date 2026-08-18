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

  bool hasDrawingAtCurrentFrame({required Layer layer}) {
    return hasSelectedFrameForLayer(layer);
  }

  bool isDrawingStartForLayer({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    return layer.timeline[frameIndex]?.isDrawing ?? false;
  }

  bool isHeldExposureForLayer({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0 ||
        isDrawingStartForLayer(layer: layer, frameIndex: frameIndex)) {
      return false;
    }
    return coveringDrawingBlockAt(layer.timeline, frameIndex) != null;
  }

  bool hasMarkAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    return hasBreakdownDotAt(layer.timeline, frameIndex);
  }

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
  }) {
    if (length < 1) {
      throw ArgumentError.value(
        length,
        'length',
        'Drawing exposure length must be at least 1.',
      );
    }

    final before = _requireLayer(layerId);
    final frameIndex = _editFrameIndexFor(layerId);
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
          name: _normalizeFrameName(name),
          seName: _normalizeFrameName(seName),
        ),
      ],
      timeline: nextTimeline,
    );
    _applyLayerEdit(before: before, after: after);
  }

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

  /// Inbetween dots live on the HELD cells of a real drawing block only
  /// (offset 1..length-1): a block start is the drawing itself, an empty
  /// cell has no block to own the dot (author an unnamed frame first), and
  /// ghosts are derived — their dots come from the source block.
  bool canToggleMarkAt({required Layer layer, required int frameIndex}) {
    if (frameIndex < 0) {
      return false;
    }
    final block = coveringDrawingBlockAt(layer.timeline, frameIndex);
    return block != null && !block.entry.ghost && frameIndex > block.startIndex;
  }

  void toggleMarkForLayer({required LayerId layerId}) {
    final before = _requireLayer(layerId);
    final frameIndex = _editFrameIndexFor(layerId);
    if (!canToggleMarkAt(layer: before, frameIndex: frameIndex)) {
      return;
    }

    final block = coveringDrawingBlockAt(before.timeline, frameIndex)!;
    final offset = frameIndex - block.startIndex;
    final entry = block.entry;
    final nextTimeline = SplayTreeMap<int, TimelineExposure>.from(
      before.timeline,
    );
    nextTimeline[block.startIndex] = entry.copyWith(
      breakdownOffsets: entry.hasBreakdownAt(offset)
          ? [
              for (final existing in entry.breakdownOffsets)
                if (existing != offset) existing,
            ]
          : [...entry.breakdownOffsets, offset],
    );
    _applyLayerEdit(
      before: before,
      after: before.copyWith(timeline: nextTimeline),
    );
  }

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
    _executeCommands(
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
      final before = _requireLayer(entry.key);
      final offset = _frameOffsetForLayer?.call(entry.key) ?? 0;
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
            name: _normalizeFrameName(fill.name),
          ),
        );
      }
      if (newFrames.isEmpty) {
        continue;
      }
      commands.add(
        _layerEditCommand(
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

  bool canPasteLinkedFrameAt({
    required Layer layer,
    required int frameIndex,
    required FrameId copiedFrameId,
  }) {
    if (frameIndex < 0) {
      return false;
    }
    return _frameOrNull(layer: layer, frameId: copiedFrameId) != null;
  }

  void pasteLinkedFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
  }) {
    final before = _requireLayer(layerId);
    if (!canPasteLinkedFrameAt(
      layer: before,
      frameIndex: _editFrameIndexFor(layerId),
      copiedFrameId: frameId,
    )) {
      return;
    }
    _pasteFrameForLayer(layerId: layerId, frameId: frameId);
  }

  /// ㉕ 독립 붙여넣기: the copied cel's CONTENT here, as a cel of its OWN.
  ///
  /// The only difference from the linked paste is which cel the exposure
  /// ends up pointing at — a new one rather than the copied one — so the
  /// placement rules (relink on a block start, split inside a hold, fill an
  /// empty cell up to the next block) are shared rather than restated.
  /// Drawing on the result must not reach the frame it came from; that is
  /// the whole of what "독립" means here.
  void pasteIndependentFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required FrameId newFrameId,
  }) {
    final before = _requireLayer(layerId);
    if (!canPasteLinkedFrameAt(
      layer: before,
      frameIndex: _editFrameIndexFor(layerId),
      copiedFrameId: frameId,
    )) {
      return;
    }
    final source = _frameOrNull(layer: before, frameId: frameId);
    if (source == null) {
      return;
    }
    _pasteFrameForLayer(
      layerId: layerId,
      frameId: newFrameId,
      // 🚨IT COMES OUT UNNAMED, and that is the point rather than an
      // omission. A cel's name is its IDENTITY inside the layer — the
      // rename path REFUSES a duplicate and offers to merge instead, which
      // is this app's 「같은 이름 = 같은 그림」 rule. Carrying the source's
      // name would assert the very link this verb exists to avoid, and do
      // it behind that dialog's back: two cels claiming one name, a state
      // no rename could ever produce.
      //
      // Unnamed cels coexist freely, so "not named yet" is a legal answer
      // and the animator gives it one when they mean to. `seName` DOES
      // travel — a speaker label is a property, not a name that links.
      bornFrame: duplicateFrameContent(
        frame: source,
        newFrameId: newFrameId,
      ).copyWith(name: null),
    );
  }

  /// Puts [frameId]'s exposure at the edit index. [bornFrame] is the
  /// independent paste's new cel, which joins the layer before anything
  /// points at it; null is the linked paste, where reuse IS the point.
  ///
  /// 🚨T3 — this is [spliceRunsForLayers] with a one-cell clip and no lift.
  /// It used to hold the three placement rules of its own (relink on a block
  /// start, split inside a hold, fill an empty cell up to the next block),
  /// and ⛔those are RETIRED: 「내가 하고싶은건 프레임만 복붙이 아니라 코마까지
  /// 포함해서 블록 자체를 복붙한다는 느낌」. The clip brings its length and
  /// the tail moves aside. Kept as a named entry point because the one-cel
  /// paste is still a real verb, not because the old rules survive anywhere.
  void _pasteFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    Frame? bornFrame,
  }) {
    spliceRunsForLayers(
      runs: [
        (
          layerId: layerId,
          index: _editFrameIndexFor(layerId),
          liftCount: 0,
          clip: TimelineClipRow(
            exposures: {0: TimelineExposure.drawing(frameId, length: 1)},
            length: 1,
          ),
          bornFrames: bornFrame == null ? const <Frame>[] : [bornFrame],
        ),
      ],
      description: 'Paste frame',
    );
  }

  // --- The one splice ----------------------------------------------------------

  /// Reads [count] cells off [layerId] without changing the row.
  ///
  /// Indexes are the EDIT axis, the same one the paste and the playhead use,
  /// so a track-owned SE row reads at its shifted position rather than the
  /// cut-local one.
  TimelineClipRow copyRunForLayer({
    required LayerId layerId,
    required int index,
    required int count,
  }) {
    return captureTimelineRun(
      timeline: _requireLayer(layerId).timeline,
      index: index,
      count: count,
    );
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

  bool canRenameFrameAt({required Layer layer, required int frameIndex}) {
    // Ghost cells RESOLVE to their anchor cel deliberately (UI-R19b,
    // user decision): renaming from a repeat instance renames the
    // source — a feature, not a leak. Only DELETE stays refused on
    // ghosts (they are derived; there is no block to remove).
    return resolveFrameForLayer(layer: layer, frameIndex: frameIndex) != null;
  }

  FrameId? conflictingFrameIdForRename({
    required Layer layer,
    required FrameId frameId,
    required String? name,
  }) {
    _requireFrameInLayer(layer: layer, frameId: frameId);
    final normalizedName = _normalizeFrameName(name);
    if (normalizedName == null) {
      return null;
    }

    for (final frame in layer.frames) {
      if (frame.id != frameId && frame.name == normalizedName) {
        return frame.id;
      }
    }

    return null;
  }

  void renameFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required String? name,
    bool allowDuplicateName = false,
    String? seName,
    bool updateSeName = false,
  }) {
    final before = _requireLayer(layerId);
    _requireFrameInLayer(layer: before, frameId: frameId);
    if (!allowDuplicateName) {
      final conflictingFrameId = conflictingFrameIdForRename(
        layer: before,
        frameId: frameId,
        name: name,
      );
      if (conflictingFrameId != null) {
        return;
      }
    }

    final normalizedName = _normalizeFrameName(name);
    final normalizedSeName = _normalizeFrameName(seName);
    final nextFrames = before.frames
        .map(
          (frame) => frame.id == frameId
              ? (updateSeName
                    // Name + SE speaker name land in the same edit — the SE
                    // dialog commits both as ONE undo step.
                    ? frame.copyWith(
                        name: normalizedName,
                        seName: normalizedSeName,
                      )
                    : frame.copyWith(name: normalizedName))
              : frame,
        )
        .toList(growable: false);
    final after = before.copyWith(frames: nextFrames);
    if (after == before) {
      return;
    }

    _applyLayerEdit(before: before, after: after);
  }

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

  /// Whether the block starting at [blockStartIndex] can shift its [edge]
  /// at all in the direction of [delta] (used to enable UI affordances;
  /// the actual applied delta is clamped by [clampExposureEdgeDelta]).
  bool canShiftExposureEdge({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    return clampExposureEdgeDelta(
          layer: layer,
          blockStartIndex: blockStartIndex,
          edge: edge,
          delta: delta,
        ) !=
        0;
  }

  /// The largest applicable portion of [delta] for an edge shift:
  /// shrinking stops at length 1, and start-edge growth stops when the
  /// pushed chain would cross frame 0. Growth toward the open end is
  /// unlimited.
  int clampExposureEdgeDelta({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final entry = layer.timeline[blockStartIndex];
    if (entry == null || !entry.isDrawing || delta == 0) {
      return 0;
    }
    final length = entry.length!;

    switch (edge) {
      case TimelineBlockEdge.end:
        if (delta > 0) {
          return delta;
        }
        // Shrink from the end: keep at least one frame.
        return delta < 1 - length ? 1 - length : delta;
      case TimelineBlockEdge.start:
        if (delta > 0) {
          // Shrink from the front: keep at least one frame.
          return delta > length - 1 ? length - 1 : delta;
        }
        // Grow backward: limited by the room the preceding glued/pushed
        // chain has before frame 0.
        final maxGrow = _startEdgeGrowRoom(
          layer.timeline,
          blockStartIndex: blockStartIndex,
        );
        return delta < -maxGrow ? -maxGrow : delta;
    }
  }

  /// Pure computation of the layer after a comma edge shift; `null` when
  /// the clamped delta is zero. Exposed for drag previews (apply directly,
  /// commit once on release) while [shiftExposureEdge] applies it as a
  /// single undoable command.
  Layer? shiftedLayerForEdge({
    required Layer layer,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final clampedDelta = clampExposureEdgeDelta(
      layer: layer,
      blockStartIndex: blockStartIndex,
      edge: edge,
      delta: delta,
    );
    if (clampedDelta == 0) {
      return null;
    }

    final nextTimeline = _shiftEdgeTimeline(
      layer.timeline,
      blockStartIndex: blockStartIndex,
      edge: edge,
      delta: clampedDelta,
    );
    // Live preview keeps the ghosts following the dragged run (UI-R8).
    return rederiveRunBehaviors(
      layer.copyWith(timeline: nextTimeline),
      cutFrameCount: _cutFrameCount(),
    );
  }

  void shiftExposureEdge({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final before = _requireLayer(layerId);
    // Callers pass the block start as DISPLAYED (cut-local); track-SE
    // layers store it at the global offset.
    final after = shiftedLayerForEdge(
      layer: before,
      blockStartIndex:
          blockStartIndex + (_frameOffsetForLayer?.call(layerId) ?? 0),
      edge: edge,
      delta: delta,
    );
    if (after == null || after == before) {
      return;
    }
    _applyLayerEdit(before: before, after: after);
  }

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

  SplayTreeMap<int, TimelineExposure> _shiftEdgeTimeline(
    SplayTreeMap<int, TimelineExposure> timeline, {
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    final blocks = drawingBlocks(timeline);
    final targetIndex = blocks.indexWhere(
      (block) => block.startIndex == blockStartIndex,
    );
    if (targetIndex == -1) {
      throw StateError('No drawing block starts at index $blockStartIndex.');
    }

    // New start/length per block, seeded with the resized target.
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

    final target = blocks[targetIndex];
    switch (edge) {
      case TimelineBlockEdge.end:
        newLengths[targetIndex] = target.length + delta;
      case TimelineBlockEdge.start:
        newStarts[targetIndex] = target.startIndex + delta;
        newLengths[targetIndex] = target.length - delta;
    }

    // Ripple following blocks (end-edge resizes and front shrinks change
    // where the target ends; contact rules: glued blocks stay glued,
    // separated blocks move only when overlapped).
    var prevOldEnd = target.endIndexExclusive;
    var prevNewEnd = newStarts[targetIndex] + newLengths[targetIndex];
    for (var i = targetIndex + 1; i < blocks.length; i += 1) {
      final block = blocks[i];
      final glued = block.startIndex == prevOldEnd;
      var start = glued ? prevNewEnd : block.startIndex;
      if (start < prevNewEnd) {
        start = prevNewEnd;
      }
      newStarts[i] = start;
      prevOldEnd = block.endIndexExclusive;
      prevNewEnd = start + block.length;
    }

    // Ripple preceding blocks (start-edge moves): mirror of the above.
    var nextOldStart = target.startIndex;
    var nextNewStart = newStarts[targetIndex];
    for (var i = targetIndex - 1; i >= 0; i -= 1) {
      final block = blocks[i];
      final glued = block.endIndexExclusive == nextOldStart;
      var end = glued ? nextNewStart : block.endIndexExclusive;
      if (end > nextNewStart) {
        end = nextNewStart;
      }
      newStarts[i] = end - block.length;
      nextOldStart = block.startIndex;
      nextNewStart = newStarts[i];
    }

    if (newStarts.isNotEmpty && newStarts.first < 0) {
      throw StateError(
        'Comma edge shift would push a block before frame 0 '
        '(clamp deltas with clampExposureEdgeDelta first).',
      );
    }

    // Rebuild: drawings at their new starts. Block-owned dots ride inside
    // the entries for free; copyWith drops offsets a shrink cut off.
    final next = SplayTreeMap<int, TimelineExposure>();
    for (var i = 0; i < blocks.length; i += 1) {
      next[newStarts[i]] = blocks[i].entry.copyWith(length: newLengths[i]);
    }
    return next;
  }

  // --- Shared internals -------------------------------------------------------

  String? _normalizeFrameName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _timelineReferencesFrame(
    Map<int, TimelineExposure> timeline,
    FrameId frameId,
  ) {
    return timeline.values.any(
      (exposure) => exposure.isDrawing && exposure.frameId == frameId,
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
    if (cut == null) {
      throw StateError('Cut not found: $_cutId');
    }

    for (final layer in cut.layers) {
      if (layer.id == layerId) {
        return layer;
      }
    }

    // Track-owned SE rows: mutations edit the GLOBAL layer (never the
    // cut-local display clone) — indexes shift via _editFrameIndexFor.
    for (final layer in _trackSeLayers?.call() ?? const <Layer>[]) {
      if (layer.id == layerId) {
        return layer;
      }
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
