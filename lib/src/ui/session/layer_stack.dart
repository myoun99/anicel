// THE CUT'S ROW STACK: which rows it can gain, and what a row's block
// holds.
//
// Its own object since round 8 (G2, 2026-09-07). The two halves are one
// object because they are one question asked from two sides — the Add
// Layer menu asks what row this cut may still take, the row rail asks
// what the row it already has is holding — and both are pure reads of
// the ACTIVE cut's layer list plus the cel store behind it.
//
// ⛔It does not implement "insert a row above the active one": that verb
// is [LayerVerbs.addRowAboveActive] and this calls it. What lives here is
// the kind-by-kind decision of WHAT to insert and whether it is allowed
// at all — a different question, and the reason the two are not merged.

import 'package:flutter/foundation.dart';

import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart' show createFolderLayer;
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_section_defaults.dart';
import '../../services/commands/cut_command_input_planner.dart'
    show nextFolderName;
import '../../services/commands/track_se_layer_commands.dart';
import '../../services/editing/default_layer_helpers.dart';
import 'folder_bands.dart';
import 'layer_verbs.dart';
import 'render_caches.dart';
import 'active_cut_controllers.dart';
import 'layer_id_mint.dart';
import 'session_roles.dart';
import 'standing.dart';

/// The Add Layer entrance and the unworked-block query, as one object.
class LayerStack {
  LayerStack({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required LayerIdMint layerIds,
    required LayerVerbs layerVerbs,
    required Standing standing,
    required FolderBands folderBands,
    required RenderCaches renderCaches,
    required ValueNotifier<bool> brushInputActive,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _internals = internals,
       _layerIds = layerIds,
       _layerVerbs = layerVerbs,
       _standing = standing,
       _folderBands = folderBands,
       _renderCaches = renderCaches,
       _brushInputActive = brushInputActive;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final LayerIdMint _layerIds;
  final LayerVerbs _layerVerbs;
  final Standing _standing;
  final FolderBands _folderBands;
  final RenderCaches _renderCaches;
  final ValueNotifier<bool> _brushInputActive;

  /// THE unified Add Layer entrance: a new layer of the ACTIVE layer's
  /// kind, inserted directly above it, named by its section's own scheme
  /// (cel letters / S3 / CAM 2). The camera cannot be duplicated (exactly
  /// one per cut) — with it (or nothing) active, a default cel is added.
  void addLayer() =>
      addLayerOfKind(_selection.activeLayer?.kind ?? LayerKind.animation);

  /// Whether the ACTIVE cut can take another row of [kind] (R9 #7): false
  /// once a singleton kind already has its one row. The Add Layer menu
  /// reads this to disable the entry rather than swallowing the tap, so a
  /// dead menu item never looks like a bug.

  bool canAddLayerOfKind(LayerKind kind) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return !kind.isSingletonPerCut ||
        !cut.layers.any((layer) => layer.kind == kind);
  }

  /// Kind-explicit Add Layer (the split button's ▾ list): the same naming
  /// and insertion rules as [addLayer] with the requested kind.
  void addLayerOfKind(LayerKind kind) {
    if (_project.activeCutOrNull == null) {
      return; // Gap state: no cut to add into (SE rows need one too —
      //         selection lives in the cut-scoped row list).
    }
    if (!canAddLayerOfKind(kind)) {
      return; // The cut already holds its one row of a singleton kind.
    }
    final layerId = _layerIds.mint();
    switch (kind) {
      case LayerKind.transition:
        // A track fixture, created with the track — "Add layer" never makes
        // one (canAddLayerOfKind refuses first; this keeps the switch
        // exhaustive and the intent stated).
        return;
      case LayerKind.se:
        // SE rows are track-owned: insert directly above the active SE row
        // in the TRACK list (the same S1,S3,S2 insertion order the
        // timeline shows — the single ordering every panel renders).
        final seLayers = _selection.activeTrack.seLayers;
        final activeIndex = seLayers.indexWhere(
          (layer) => layer.id == _selection.activeLayerId,
        );
        final newLayer = Layer(
          id: layerId,
          name: nextSeLayerName(seLayers),
          frames: const [],
          timeline: const {},
          kind: LayerKind.se,
        );
        _project.historyManager.execute(
          AddTrackSeLayerCommand(
            repository: _project.repository,
            trackId: _selection.selectedTrackId,
            layer: newLayer,
            insertionIndex: activeIndex < 0 ? null : activeIndex + 1,
          ),
        );
        _controllers.layerController.selectLayer(layerId);
      case LayerKind.instruction:
        _controllers.layerController.addLayer(
          layer: Layer(
            id: layerId,
            name: nextInstructionLayerName(_controllers.layerController.layers),
            frames: const [],
            timeline: const {},
            kind: LayerKind.instruction,
          ),
        );
      case LayerKind.animation:
      case LayerKind.storyboard:
      case LayerKind.image:
        // The COVERING kinds (storyboard, image) are born covering their
        // cut — one cell, edge to edge. There is no "X" in their world,
        // so they never start empty and then have to be filled.
        Layer newLayerFor(Cut cut) => kind.coversWithoutGaps
            ? createCoveringLayer(
                layerId: layerId,
                frameId: FrameId(_frameIds.nextFrameId(layerId)),
                cut: cut,
                kind: kind,
              )
            : createDefaultAnimationLayer(layerId: layerId, cut: cut);
        // F-76: a row made from nothing wears its kind's label
        // ([LayerMark.bornOfKind]).
        _layerVerbs.addRowAboveActive(
          (cut) => newLayerFor(cut).copyWith(mark: LayerMark.bornOfKind(kind)),
        );
      case LayerKind.adjustment:
        // R6b: a real row you ADD (unlike a folder), joining the stack
        // above the active layer like every other kind — which is exactly
        // what puts the rows it filters below it.
        _layerVerbs.addRowAboveActive(
          (cut) => createAdjustmentLayer(
            id: layerId,
            name: nextAdjustmentLayerName(cut.layers),
          ),
        );
      case LayerKind.folder:
        // R5 #14: a folder is ADDED now, and it is born EMPTY.
        //
        // It used to be MADE by wrapping the active row, and Add Layer with
        // a folder selected quietly added a drawing cel instead. The user
        // asked for the file-manager shape every other app they work in
        // has: make the container, then put things in it by dropping them
        // on it. The drop is this round's other half; without it an empty
        // folder would be a room with no door, because a caret between
        // rows cannot address the inside of a folder that has none (the
        // "in" and the "below" are the same slot).
        _layerVerbs.addRowAboveActive(
          (cut) => createFolderLayer(id: layerId, name: nextFolderName(cut)),
        );
      case LayerKind.camera:
        _controllers.layerController.addLayerWithDefaults(layerId: layerId);
    }
    // F-20: the row you just made IS the subject now. Every arm above seats
    // the controller's active layer directly, so none of them went through
    // [selectLayer].
    _standing.seatVerbRowOnActiveLayer();
    _changes.notifyChanged();
  }

  /// R26 #44: whether the drawing block covering [frameIndex] holds ANY
  /// picture in its cel — the ACTION-section rows' unworked-block tint
  /// reads this. Non-drawing sections (SE / camera / instruction) and
  /// uncovered cells always answer true (no tint).
  bool celHasContentForLayer(Layer layer, int frameIndex) {
    if (layer.kind.groupsLayers) {
      // R28 #11 carried onto the shared painter: a folder frame is grey
      // only when NO member drew there ("다른곳에서 해당위치에 그림그려진
      // 하얀 블록 존재하면 하얗게"). Without this arm the folder falls into
      // the drawing-section branch, resolves no frame of its own and
      // answers `true` — the union grey would vanish silently.
      return _folderBands
          .folderBandMembersOf(layer.id)
          .any((member) => celHasContentForLayer(member, frameIndex));
    }
    // 🚨THE QUESTION IS 「CAN THIS ROW HOLD A PICTURE」, not 「is it in the
    // drawing SECTION」 (유저 2026-08-27, R27 #16: 「추가로 **없으면 블록을
    // 회색으로**. 로직은 통일」). The direction row is a camera-section row
    // that holds cels, so the section test answered `true` — no tint — and
    // an empty block there was indistinguishable from a full one.
    //
    // ⛔The two only looked like one question while every cel-holding row
    // happened to sit in the drawing section, which is the same trap R27
    // #16 found in `LayerKind.carriesInstructions`.
    if (!layer.kind.isDrawingCel) {
      return true;
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return true;
    }
    final frame = _controllers.timelineController.resolveFrameForLayer(
      layer: layer,
      frameIndex: frameIndex,
    );
    if (frame == null) {
      // A cell with no frame is not a block at all: nothing to tint.
      //
      // ↩️A span-covered cell on a DIRECTION row used to be the exception —
      // a block with no cel behind it yet, tinted here because 유저 asked
      // to see exactly that state (「추가로 **없으면 블록을 회색으로**」).
      // Since R27 every span is a block on a cel of its own, so that grey
      // comes from the unworked-cel rule below, like any empty cel's.
      return true;
    }
    // A LIVE stroke already counts. The store only learns about pixels at
    // commit (`markCelEdited` on pen-up), so waiting for it left the block
    // grey for the whole stroke — the user asked for it to go white the
    // moment the line starts, which is also when the cel stops being
    // "unworked" in any sense that matters.
    if (_brushInputActive.value &&
        layer.id == _selection.activeLayerId &&
        frame.id == _selection.selectedFrame?.id) {
      return true;
    }
    return _renderCaches.brushFrameStore.celHasRenderableContent(
      _internals.brushFrameKeyForCut(cut, layer.id, frame.id),
    );
  }

  /// Bumps whenever [celHasContentForLayer] can have changed anywhere: the
  /// store crosses empty↔drawn, or the pen goes down on a cel.
  ///
  /// The store's own crossing signal (R27 #13) already existed and NOTHING
  /// SUBSCRIBED TO IT — which is the whole bug: the tint is derived state
  /// living outside the immutable Layer, so with no listener it only caught
  /// up when an unrelated edit announced app-wide (switch layers, rename a
  /// frame). This adds the live-stroke half and hands the row painters one
  /// thing to listen to.
  final ValueNotifier<int> celTintRevision = ValueNotifier<int>(0);

  void _bumpCelTintRevision() => celTintRevision.value += 1;

  /// The three events that can flip [celHasContentForLayer]'s answer.
  void attach() {
    // The unworked-block tint's two events (see [celTintRevision]): the
    // store's empty↔drawn crossing, and the pen going down on a cel.
    _renderCaches.brushFrameStore.celContentRevision.addListener(
      _bumpCelTintRevision,
    );
    _brushInputActive.addListener(_bumpCelTintRevision);
    // 🚨And the THIRD: any pixel edit at all. The crossing detector above
    // asks whether the store HOLDS a surface for the cel, not whether that
    // surface has ink in it — so 픽셀 비우기 leaves an all-transparent
    // surface, `has == had`, and it never bumps. The block went on showing
    // 「그려짐」 for a cel with nothing in it (유저 2026-08-27: 「블록도
    // 반영안되는데」), because the tint's own revision never moved and the
    // painter's repaint gating had no reason to re-ask.
    //
    // ⚠️This fires as often as the user draws — but the timeline host ALSO
    // merges `celPixelRevision` into its frame-ready signal, so the rebuild
    // it costs is one that was already happening; what changes is that the
    // tint re-reads inside it instead of serving a stale answer.
    _renderCaches.brushFrameStore.celPixelRevision.addListener(
      _bumpCelTintRevision,
    );
  }

  void dispose() {
    _renderCaches.brushFrameStore.celContentRevision.removeListener(
      _bumpCelTintRevision,
    );
    _renderCaches.brushFrameStore.celPixelRevision.removeListener(
      _bumpCelTintRevision,
    );
    _brushInputActive.removeListener(_bumpCelTintRevision);
    celTintRevision.dispose();
  }
}
