// Where an import LANDS, and what it must know before it reads a byte.
//
// Its own object since round 8 (G1, 2026-09-06): the image, PSD and PDF
// doors each carried their own copy of the destination gate and of the
// six facts derived from it, and all three then called one landing verb.
// The gate is the law; three copies of it were three chances for one to
// slip behind a decode.

import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/drawing_block_move.dart' show planDrawingRangeMove;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_section_defaults.dart' show nextSeLayerName;
import '../../models/media_asset.dart';
import '../../models/new_row_placement.dart';
import '../../models/se_take_placement.dart';
import '../../models/timeline_coverage.dart' show drawingBlocks;
import '../../models/timeline_empty_gaps.dart' show emptyGapsBetween;
import '../../models/timeline_repeat.dart' show rederiveRunBehaviors;
import '../../models/track_se_window.dart';
import '../../services/command.dart' show CompositeCommand;
import '../../services/commands/import_media_command.dart';
import '../../services/commands/track_se_layer_commands.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../services/editing/default_cut_helpers.dart'
    show createDefaultCut, defaultCutCanvasSize, importedCut;
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/project_lookup.dart' show projectLayerIdValues;
import 'layer_id_mint.dart';
import 'session_roles.dart';

/// Where this import is landing, and the identity it lands under.
///
/// ⛔THE DESTINATION GATE RUNS BEFORE ANY READ. Each door said it in its
/// own words — "before any decode", "before any read", "before any native
/// work" — because a refused import must not have images, a PSD's bytes
/// or an open PDF document to leak. It is one law, so it is one object:
/// [ImportLanding.arriveAt] answers null when the destination refuses,
/// and every door's first statement is that answer.
class ImportArrival {
  ImportArrival({
    required this.targetCut,
    required this.canvasSize,
    required this.mint,
    required this.source,
    required this.displayName,
    required this.projectFps,
    this.spot,
  });

  /// The cut the layers join, or null when this import brings its own.
  ///
  /// ⛔This is also the answer to "which destination was asked for": the
  /// gate refuses [ImportDestination.activeCutLayer] with no active cut,
  /// so a non-null cut here IS that destination and a null one is the new
  /// cut. One field, one question — the destination used to be carried
  /// alongside and the two had to agree.
  final Cut? targetCut;
  final CanvasSize canvasSize;
  final ImportIdMint mint;

  /// The source file, spelled the one way the project records paths.
  final String source;
  final String displayName;
  final int projectFps;

  /// Where in [targetCut] a DROP put this import — null for every entrance
  /// that is not a drop. The gate has already checked it: frames bound for
  /// a row that takes none never get this far.
  final ImportLayerSpot? spot;

  /// The one line the undo stack shows for this import, whichever way it
  /// lands.
  String get undoDescription => 'Import $displayName';

  /// The cut this import lands in — the target's own id, or a fresh one.
  ///
  /// ⚠️Minted on FIRST READ, which is after the decode in every door. A
  /// door that refuses its file (unreadable, undecodable, no pages) must
  /// not have spent a cut number on it.
  CutId get cutId => _cutId ??= targetCut?.id ?? mint.nextCutId();
  CutId? _cutId;

  /// How long a STILL holds: the cut it joins keeps its own length, and a
  /// new cut takes what the import window asked for, or a project second.
  int stillDuration({int? lengthFrames}) {
    final cut = targetCut;
    if (cut == null) {
      return lengthFrames ?? projectFps;
    }
    return cut.duration < 1 ? 1 : cut.duration;
  }

  /// This arrival on a canvas of [size] — the destination gate has already
  /// run; only the canvas a NEW cut is made at changes.
  ///
  /// A new cut is made at its file's own size, so the 1:1 fit the window
  /// locks for it fills it exactly (유저 2026-09-11: 「새 컷 캔버스크기:
  /// 추천대로」). The size is only known once the file has been read, which
  /// is why this exists instead of the gate answering it.
  ///
  /// An id already minted travels with the copy, so one import spends one
  /// cut number whichever of the two is read.
  ImportArrival withCanvasSize(CanvasSize size) => ImportArrival(
    targetCut: targetCut,
    canvasSize: size,
    mint: mint,
    source: source,
    displayName: displayName,
    projectFps: projectFps,
    spot: spot,
  ).._cutId = _cutId;
}

/// The gate every media-file import passes, the id mint it passes it
/// with, and the one landing both destinations go through.
class ImportLanding {
  ImportLanding({
    required ProjectAccess project,
    required SelectionAccess selection,
    required FrameIds frameIds,
    required TimelineAccess timeline,
    required LayerIdMint layerIds,
    required int Function() layerIndexAboveActive,
    required bool Function(LayerId layerId) acceptsPlacedFrames,
  }) : _project = project,
       _selection = selection,
       _frameIds = frameIds,
       _timeline = timeline,
       _layerIds = layerIds,
       _layerIndexAboveActive = layerIndexAboveActive,
       _acceptsPlacedFrames = acceptsPlacedFrames;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final FrameIds _frameIds;
  final TimelineAccess _timeline;
  final LayerIdMint _layerIds;

  /// Add Layer's own slot above the active row — asked, not re-derived.
  final int Function() _layerIndexAboveActive;

  /// Which rows take dropped frames — the session's one answer.
  final bool Function(LayerId layerId) _acceptsPlacedFrames;

  int _importCutSequence = 0;

  /// Whether this import may land where it was aimed, and everything the
  /// door needs about the file once it may — or null when the destination
  /// refuses, which is the door's first `return`.
  ImportArrival? arriveAt(
    ImportDestination destination, {
    required String path,
    ImportLayerSpot? spot,
  }) {
    final targetCut = destination == ImportDestination.activeCutLayer
        ? _project.activeCutOrNull
        : null;
    if (destination == ImportDestination.activeCutLayer && targetCut == null) {
      return null;
    }
    // A drop on a row's frames is the gate's to refuse too: a row that is
    // not in this cut, or takes no frames, turns it away before any read.
    if (spot is RowFramesSpot) {
      final inCut =
          targetCut?.layers.any((layer) => layer.id == spot.layerId) ?? false;
      if (!inCut || !_acceptsPlacedFrames(spot.layerId)) {
        return null;
      }
    }
    // A sound let go on an SE cell needs that row on this track.
    if (spot is SeCellSpot &&
        (targetCut == null ||
            !_selection.activeTrack.seLayers.any(
              (layer) => layer.id == spot.layerId,
            ))) {
      return null;
    }
    final source = normalizedMediaPath(path);
    return ImportArrival(
      targetCut: targetCut,
      canvasSize:
          targetCut?.canvasSize ??
          _project.activeCutOrNull?.canvasSize ??
          defaultCutCanvasSize,
      mint: idMint(),
      source: source,
      displayName: mediaAssetDefaultName(source),
      projectFps: _project.repository.requireProject().fps,
      spot: spot,
    );
  }

  ImportIdMint idMint() {
    // ONE scan for the whole batch. An import mints an id per layer and per
    // cut it brings in, and scanning the project inside each of those turns
    // a 200-layer PSD landing in a heavy project into 200 walks of every
    // layer in it. The snapshot stays correct because the counters only
    // climb: an id minted a moment ago is not in this set, and it is not
    // reachable again either.
    final usedLayerIds = projectLayerIdValues(
      _project.repository.requireProject(),
    );
    final usedCutIds = {
      for (final track in _project.repository.requireProject().tracks)
        for (final cut in track.cuts) cut.id.value,
    };
    return ImportIdMint(
      nextLayerId: () => _layerIds.mint(usedIds: usedLayerIds),
      // Through the MINT, not the formatter. `nextFrameId` reads
      // `_frameSequence` and does not advance it, so calling it directly
      // leaves the wall clock as the only thing telling two cels apart —
      // and an import mints a whole layer inside one clock tick. Every cel
      // of that layer came out with the SAME id, which is not "cels that
      // look alike": it is one drawing exposed N times. A 10-drawing layer
      // arrived as one drawing.
      nextFrameId: _frameIds.mintFrameId,
      nextCutId: () {
        _importCutSequence += 1;
        var candidate = 'import-cut-$_importCutSequence';
        while (usedCutIds.contains(candidate)) {
          _importCutSequence += 1;
          candidate = 'import-cut-$_importCutSequence';
        }
        return CutId(candidate);
      },
    );
  }

  /// Lands imported [layers] where [arrival] says: as rows in the cut
  /// that is already there, or as a NEW cut built from the default — and,
  /// when a drop chose the spot ([ImportArrival.spot]), directly above the
  /// active row or INTO the row it was dropped on.
  ///
  /// ⛔THREE IMPORTERS, ONE LANDING. Image, PSD and PDF each wrote both
  /// arms out with their own ImportMediaCommand, so a field the command
  /// grew reached one importer's new cut and not another's — and the two
  /// arms have to agree about the description the undo stack shows, which
  /// is the only thing the user sees of either.
  ///
  /// Answers false only when frames bound for a row could not be planned
  /// onto it.
  bool land(
    List<Layer> layers, {
    required ImportArrival arrival,
    required int duration,
    List<MediaAsset> assets = const [],
  }) {
    final description = arrival.undoDescription;
    if (arrival.spot case final RowFramesSpot rowSpot) {
      return _landIntoRow(
        layers.single,
        spot: rowSpot,
        arrival: arrival,
        assets: assets,
      );
    }
    if (arrival.targetCut != null) {
      // A drop's spot aims the new rows — above the active row, or at the
      // gap the rail's caret showed — and they join the stack the way every
      // new row does ([newRowPlacement]): the folder of the row below,
      // never inside an attach group. No spot is the import menu's answer,
      // the top of the stack.
      final stack = _project.requireActiveCut.layers;
      final placement = switch (arrival.spot) {
        AboveActiveLayerSpot() => newRowPlacement(
          stack,
          _layerIndexAboveActive(),
        ),
        LayerSlotSpot(:final insertionIndex) => newRowPlacement(
          stack,
          insertionIndex,
        ),
        _ => null,
      };
      final folderId = placement?.folderId;
      _project.historyManager.execute(
        ImportMediaCommand(
          repository: _project.repository,
          editingSession: _timeline.editingSession,
          targetCutId: arrival.cutId,
          // The batch's own top rows join; rows an imported folder holds
          // keep pointing at it.
          newLayers: folderId == null
              ? layers
              : [
                  for (final layer in layers)
                    layer.folderId == null
                        ? layer.copyWith(folderId: folderId)
                        : layer,
                ],
          layerInsertionIndex: placement?.index,
          assetAdditions: assets,
          description: description,
        ),
      );
      return true;
    }
    final cut = importedCut(
      defaultCut: createDefaultCut(
        cutId: arrival.cutId,
        name: arrival.displayName,
        layerId: arrival.mint.nextLayerId(),
        canvasSize: arrival.canvasSize,
      ),
      layers: layers,
      duration: duration,
    );
    _project.historyManager.execute(
      ImportMediaCommand(
        repository: _project.repository,
        editingSession: _timeline.editingSession,
        trackId: _selection.selectedTrackId,
        newCuts: [cut],
        assetAdditions: assets,
        description: description,
      ),
    );
    return true;
  }

  /// A drop on a picture row's frame area: [planned]'s cels land on that
  /// row from the dropped cell on (유저 2026-09-11: 「그 칸부터 새 프레임,
  /// 항상 굽기」).
  ///
  /// ⛔NOT A SECOND RULE for what is in the way. The blocks there move
  /// exactly as they move for a block dragged in from another row, because
  /// this IS that plan, with [planned] as the row the frames came from —
  /// the user's words when it was drawn: 「새로 만든 규칙이 아니라 … 지금
  /// 쓰는 계산 그대로다」. The row's rewrite and the pool's registration
  /// are ONE undo step.
  bool _landIntoRow(
    Layer planned, {
    required RowFramesSpot spot,
    required ImportArrival arrival,
    required List<MediaAsset> assets,
  }) {
    // The gate already turned away a row that takes no frames.
    final row = _project.layerById(spot.layerId);
    final blocks = drawingBlocks(planned.timeline);
    if (row == null || blocks.isEmpty) {
      return false;
    }
    final cutFrameCount = _project.activeCutFrameCount;
    final landed = planDrawingRangeMove(
      source: planned,
      target: row,
      rangeStartIndex: blocks.first.startIndex,
      rangeEndIndexExclusive: blocks.last.endIndexExclusive,
      frameDelta: spot.frameIndex - blocks.first.startIndex,
      cutFrameCount: cutFrameCount,
    )?.targetAfter;
    if (landed == null) {
      return false;
    }
    _project.historyManager.execute(
      CompositeCommand(
        description: arrival.undoDescription,
        commands: [
          UpdateLayerTimelineCommand(
            repository: _project.repository,
            before: row,
            after: rederiveRunBehaviors(landed, cutFrameCount: cutFrameCount),
          ),
          if (assets.isNotEmpty)
            ImportMediaCommand(
              repository: _project.repository,
              editingSession: _timeline.editingSession,
              assetAdditions: assets,
              description: arrival.undoDescription,
            ),
        ],
      ),
    );
    return true;
  }

  /// A SOUND onto the track's SE rows: from the active cut's start, the
  /// first row with room for it ([firstSeRowFreeFor]) or a new row after the
  /// last — or, let go on an SE row's empty cell ([SeCellSpot]), that row
  /// from that cell. Its block is tagged 「SE」 and carries the file's name
  /// as its dialogue (유저 2026-09-11: 「블록의 이름을 SE(SE 고정 …), 대사를
  /// 파일 이름(확장자포함)으로」).
  ///
  /// ⛔NOT A SECOND WAY TO PUT A SOUND ON A ROW. The block and its clip land
  /// the way a recorded take lands — [planSeTakePlacement], the one planner
  /// for that — and the row's change and the pool's registration are ONE
  /// undo step, as a take's are.
  bool landSound({
    required ImportArrival arrival,
    required int offsetFrames,
    required int lengthFrames,
    List<MediaAsset> assets = const [],
  }) {
    final cut = arrival.targetCut;
    if (cut == null || lengthFrames < 1) {
      return false;
    }
    final track = _selection.activeTrack;
    // The ONE converter between the cut's frames and the track's.
    final window = TrackSeWindow(
      cutStartFrame: _project.activeCutGlobalStartFrame,
      cutDurationFrames: cut.duration,
    );
    final Layer? free;
    final int start;
    var length = lengthFrames;
    if (arrival.spot case final SeCellSpot cell) {
      // The row and the cell it was let go on (「SE 행의 빈 칸 → 새
      // 블록」); the next block bounds its length, as it bounds any entry
      // written onto a row.
      start = window.toGlobalFrame(cell.frameIndex);
      free = track.seLayers
          .where((layer) => layer.id == cell.layerId)
          .firstOrNull;
      final gaps = free == null
          ? const <({int startIndex, int length})>[]
          : emptyGapsBetween(free, start, start + lengthFrames);
      if (gaps.isEmpty || gaps.first.startIndex != start) {
        return false;
      }
      length = gaps.first.length;
    } else {
      start = window.toGlobalFrame(0);
      free = firstSeRowFreeFor(
        track.seLayers,
        startFrame: start,
        lengthFrames: lengthFrames,
      );
    }
    final row =
        free ??
        Layer(
          id: _layerIds.mint(),
          name: nextSeLayerName(track.seLayers),
          frames: const [],
          timeline: const {},
          kind: LayerKind.se,
        );
    final plan = planSeTakePlacement(
      layer: row,
      startFrame: start,
      lengthFrames: length,
      filePath: arrival.source,
      takeFrameId: _frameIds.mintFrameId(row.id),
      newFrameId: () => _frameIds.mintFrameId(row.id),
      name: arrival.displayName,
      seName: placedSoundNameTag,
      offsetFrames: offsetFrames,
    );
    if (plan == null) {
      return false;
    }
    _project.historyManager.execute(
      CompositeCommand(
        description: arrival.undoDescription,
        commands: [
          if (free == null)
            AddTrackSeLayerCommand(
              repository: _project.repository,
              trackId: track.id,
              layer: plan.layer,
            )
          else
            UpdateLayerTimelineCommand(
              repository: _project.repository,
              before: free,
              after: plan.layer,
            ),
          if (assets.isNotEmpty)
            ImportMediaCommand(
              repository: _project.repository,
              editingSession: _timeline.editingSession,
              assetAdditions: assets,
              description: arrival.undoDescription,
            ),
        ],
      ),
    );
    return true;
  }
}
