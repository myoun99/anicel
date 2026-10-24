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
// at all — a different question, and the reason the two are not merged —
// and the one kind born elsewhere: a cut's conte row, at the bottom of
// ACTION (F-369, [LayerVerbs.addRow]).

import 'package:flutter/foundation.dart';

import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart' show createFolderLayer;
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_section_defaults.dart';
import '../../models/se_audio_spans.dart';
import '../../models/new_row_placement.dart' show conteRowPlacement;
import '../../models/timeline_row_address.dart';
import '../../models/working_panel.dart';
import '../../services/commands/cut_command_input_planner.dart'
    show nextFolderName;
import '../../services/commands/track_se_layer_commands.dart';
import '../../services/editing/default_layer_helpers.dart';
import '../timeline/timeline_drag_preview.dart'
    show TimelineDragPreview, celPixelsOf, timelineDragPreviewLayerFor;
import '../audio/sound_cannot_play.dart';
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
    required LayerIdMint layerIds,
    required LayerVerbs layerVerbs,
    required Standing standing,
    required FolderBands folderBands,
    required RenderCaches renderCaches,
    required ValueNotifier<bool> brushInputActive,
    required ValueListenable<TimelineDragPreview?> dragPreview,
    required SoundCannotPlay? Function(String filePath) soundCannotPlay,
    required Listenable Function() soundsMoved,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _layerIds = layerIds,
       _layerVerbs = layerVerbs,
       _standing = standing,
       _folderBands = folderBands,
       _renderCaches = renderCaches,
       _brushInputActive = brushInputActive,
       _dragPreview = dragPreview,
       _soundCannotPlay = soundCannotPlay,
       _soundsMoved = soundsMoved;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final LayerIdMint _layerIds;
  final LayerVerbs _layerVerbs;
  final Standing _standing;
  final FolderBands _folderBands;
  final RenderCaches _renderCaches;
  final ValueNotifier<bool> _brushInputActive;

  /// The drag in flight: a folder's band asks its rows where the drag has
  /// them ([celHasContentForLayer]).
  final ValueListenable<TimelineDragPreview?> _dragPreview;

  /// Why the sound at a file path cannot be played
  /// (`PlaybackRig.soundCannotPlay`) — what an SE block answers
  /// [celCannotBeReadForLayer] by.
  final SoundCannotPlay? Function(String filePath) _soundCannotPlay;

  /// What fires when [_soundCannotPlay]'s answers may have moved
  /// (`PlaybackRig.soundsMoved`) — asked for at [attach], once the rig is
  /// there to give it.
  final Listenable Function() _soundsMoved;
  Listenable? _soundsMovedHeard;

  /// Each row's sounds, block by block, read once per row as it stands —
  /// [soundCannotPlayAt] is asked at every cell a row paints.
  final Expando<List<SeAudioSpan>> _soundSpans = Expando('sound spans');

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
    if (kind == LayerKind.se) {
      return true; // TRACK-owned: a gap takes one as well as a cut does.
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return !kind.isSingletonPerCut || !holdsSingletonOfKind(cut.layers, kind);
  }

  /// Kind-explicit Add Layer (the split button's ▾ list): the same naming
  /// and insertion rules as [addLayer] with the requested kind.
  void addLayerOfKind(LayerKind kind) {
    if (!canAddLayerOfKind(kind)) {
      return; // A gap has no cut to add a cut's row into, and a cut holds
      //         one row of a singleton kind.
    }
    final layerId = _layerIds.mint();
    switch (kind) {
      case LayerKind.transition:
        // A track fixture, created with the track — "Add layer" never makes
        // one (canAddLayerOfKind refuses first; this keeps the switch
        // exhaustive and the intent stated).
        return;
      case LayerKind.se:
        _addSeLane(layerId);
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
        // so they never start empty and then have to be filled. (An image
        // row can be EMPTIED afterwards, F-98 — its birth is unchanged:
        // 「생성하면 기본적으로 프레임 생성되는건 그대로」.)
        _layerVerbs.addRow(
          (cut) => bornRowOfKind(
            kind,
            layerId: layerId,
            coveringFrameId: () => _frameIds.mintFrameId(layerId),
            cut: cut,
          ),
          // A cut's conte row is born at the bottom of ACTION, from this
          // door as from the conte's own (F-369, [conteRowPlacement]).
          kind == LayerKind.storyboard
              ? conteRowPlacement
              : _layerVerbs.placementAboveActive,
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
    _standOnTheNewRow();
  }

  /// 「Add layer ▸ SE」, answered with the new lane's id: the recorder opens
  /// a lane through this when the user stands on no SE row (F-178), so the
  /// lane it lands a take on is the one the menu would have made.
  ///
  /// SE rows are TRACK-owned, so a gap takes one too — the recording roll
  /// starts from a gap like from anywhere else on the track.
  LayerId addSeLane() {
    final layerId = _layerIds.mint();
    _addSeLane(layerId);
    _standOnTheNewRow();
    return layerId;
  }

  /// SE rows are track-owned: insert directly above the active SE row in the
  /// TRACK list (the same S1,S3,S2 insertion order the timeline shows — the
  /// single ordering every panel renders).
  void _addSeLane(LayerId layerId) {
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
    if (_project.activeCutOrNull == null) {
      // A gap has no cut row list to make the lane active in; it is stood
      // on the way the storyboard stands on its S rows.
      _standing.standOnRow(
        LayerRowAddress(layerId),
        panel: WorkingPanel.storyboard,
      );
    } else {
      _controllers.layerController.selectLayer(layerId);
    }
  }

  void _standOnTheNewRow() {
    // F-20: the row you just made IS the subject now. Every arm of
    // [addLayerOfKind] seats the controller's active layer directly, so none
    // of them went through [selectLayer].
    _standing.seatVerbRowOnActiveLayer();
    // F-169 ②: you went there, so what the rail's view hides it with opens
    // (a new SE row in a hidden SE section shows the section).
    _standing.keepStandingShown(reveal: true);
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
      //
      // ↩️F-311 (유저 2026-10-06): 「일반 폴더의 블록, 왜 이 경우 일부만
      // 회색인지? 폴더 블록이 그림 없는구간 회색하는건 아이디어 좋다고 하니
      // 개선해서 채용」. It asked each member this very question, whose
      // 「no tint」 for a cell with NO block reads as 「drew there」: where
      // one member's empty block stood beside another's bare cells, the
      // bare cells turned the folder white. Grey is where no member holds a
      // PICTURE ([_blockIsDrawnAt]) — each member read where a drag in
      // flight has it, as the band itself is (`folderBandsFollowing`).
      return _anyMemberOf(
        layer,
        (member) => _blockIsDrawnAt(member, frameIndex) ?? false,
      );
    }
    return _blockIsDrawnAt(layer, frameIndex) ?? true;
  }

  /// Whether the drawing block covering [frameIndex] shows a cel whose
  /// picture data could not be read ([LayerFrameImageCache.unreadable]) —
  /// the block goes red (유저 2026-10-16, frame-picture-indicator-Q1 b: 「a +
  /// 그 셀이 있는 타임라인 칸에도 빨간 표시」). A folder's frame where any
  /// member's does: the band shows what its rows hold, as its grey does
  /// ([celHasContentForLayer]).
  bool celCannotBeReadForLayer(Layer layer, int frameIndex) {
    if (layer.kind.groupsLayers) {
      return _anyMemberOf(
        layer,
        (member) => _blockCannotBeReadAt(member, frameIndex),
      );
    }
    return _blockCannotBeReadAt(layer, frameIndex);
  }

  /// Whether any member of the folder [folder] answers [asks] — each read
  /// where a drag in flight has it, as the band itself is.
  bool _anyMemberOf(Layer folder, bool Function(Layer member) asks) {
    final preview = _dragPreview.value;
    return _folderBands
        .folderBandMembersOf(folder.id)
        .any(
          (member) =>
              asks(timelineDragPreviewLayerFor(preview, member.id) ?? member),
        );
  }

  /// Whether the block [layer] stands at [frameIndex] holds a picture —
  /// null where it stands no block that could: a row that holds no cels, or
  /// a bare cell. The row's own tint reads null as 「nothing to tint」, and a
  /// folder's union as 「nothing drawn」.
  bool? _blockIsDrawnAt(Layer layer, int frameIndex) {
    final cel = _celAt(layer, frameIndex);
    return cel == null
        ? null
        : celHoldsAPicture(cel.cut, layer.id, cel.frameId);
  }

  /// Whether the block [layer] stands at [frameIndex] shows a cel that could
  /// not be read, or carries a sound that cannot be played
  /// ([soundCannotPlayAt]) — false where it stands no block that could hold
  /// either.
  ///
  /// 🗣️유저 2026-10-17 (playback-waits-for-its-sound-Q1 a): a sound a run
  /// plays without goes red on its row as a cel that cannot be read does —
  /// the same red, painted by the same question.
  bool _blockCannotBeReadAt(Layer layer, int frameIndex) {
    if (soundCannotPlayAt(layer, frameIndex) != null) {
      return true;
    }
    final cel = _celAt(layer, frameIndex);
    return cel != null && celCannotBeRead(cel.cut, layer.id, cel.frameId);
  }

  /// Why a sound the block [layer] stands at [frameIndex] carries cannot be
  /// played — null where every one there can, or is on its way, and where
  /// the row carries no sound there.
  SoundCannotPlay? soundCannotPlayAt(Layer layer, int frameIndex) {
    if (layer.audioClips.isEmpty) {
      return null;
    }
    return soundCannotPlayIn(
      _soundSpans[layer] ??= seAudioSpans(layer),
      frameIndex,
      _soundCannotPlay,
    );
  }

  /// The cel the block [layer] stands at [frameIndex] shows: its cut and its
  /// frame — null where it stands no block that could hold a picture.
  ({Cut cut, FrameId frameId})? _celAt(Layer layer, int frameIndex) {
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
      return null;
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null;
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
      // comes from the unworked-cel rule ([_blockIsDrawnAt]), like any empty
      // cel's.
      return null;
    }
    return (cut: cut, frameId: frame.id);
  }

  /// Whether [row]'s cel [cel] in [cut] holds a picture — the fact of the
  /// unworked-block tint (R26 #44), for one cel of any cut: the active
  /// cut's rows ask it through [celHasContentForLayer], and the conte row
  /// the storyboard lays over the whole film asks it of each cut it
  /// crosses (F-357).
  bool celHoldsAPicture(Cut cut, LayerId row, FrameId cel) {
    // A LIVE stroke already counts. The store only learns about pixels at
    // commit (`markCelEdited` on pen-up), so waiting for it left the block
    // grey for the whole stroke — the user asked for it to go white the
    // moment the line starts, which is also when the cel stops being
    // "unworked" in any sense that matters.
    if (_brushInputActive.value &&
        cut.id == _project.activeCutOrNull?.id &&
        _liveStrokeCel == (row, cel)) {
      return true;
    }
    final pixels = _pixelsOf(row, cel);
    return _storeHoldsAPicture(cut, pixels.row, pixels.cel);
  }

  /// Whether [row]'s cel [cel] in [cut] could not be read
  /// ([LayerFrameImageCache.unreadable]) — the fact of the red block, for
  /// one cel of any cut, as [celHoldsAPicture] is the grey's.
  bool celCannotBeRead(Cut cut, LayerId row, FrameId cel) {
    final pixels = _pixelsOf(row, cel);
    return _renderCaches.layerFrameImageCache.unreadable.has(
      _project.brushFrameKeyForCut(cut, pixels.row, pixels.cel),
    );
  }

  /// Where [row]'s cel [cel] has its pixels: a cel a drag carries onto
  /// [row], or a picture it hangs there, is drawn where its pixels still
  /// are ([celPixelsOf]).
  ({LayerId row, FrameId cel}) _pixelsOf(LayerId row, FrameId cel) =>
      celPixelsOf(_dragPreview.value, row, cel);

  /// The cel a live stroke counts as drawn: the active row's selected
  /// frame. Null when there is none, and then no block can be it.
  (LayerId, FrameId)? get _liveStrokeCel {
    final layerId = _selection.activeLayerId;
    final frameId = _selection.selectedFrame?.id;
    return layerId == null || frameId == null ? null : (layerId, frameId);
  }

  bool _storeHoldsAPicture(Cut cut, LayerId layerId, FrameId frameId) =>
      _renderCaches.brushFrameStore.celHasRenderableContent(
        _project.brushFrameKeyForCut(cut, layerId, frameId),
      );

  /// Bumps whenever [celHasContentForLayer] can have changed anywhere: the
  /// store crosses empty↔drawn, or the pen goes down or up on a cel whose
  /// answer the live stroke decides — and whenever [celCannotBeReadForLayer]
  /// can: a cel noted unreadable, or its note taken back.
  ///
  /// The store's own crossing signal (R27 #13) already existed and NOTHING
  /// SUBSCRIBED TO IT — which is the whole bug: the tint is derived state
  /// living outside the immutable Layer, so with no listener it only caught
  /// up when an unrelated edit announced app-wide (switch layers, rename a
  /// frame). This adds the live-stroke half and hands the row painters one
  /// thing to listen to.
  ///
  /// 🚨ONLY WHEN AN ANSWER CAN HAVE CHANGED (F-166, 2026-09-26). Every row
  /// painter, the shared pill and the collapsed rows listen to this one
  /// number, and every row repainting throws the timeline dock's still
  /// image away — measured on the real app: a bump at pen-down painted the
  /// whole timeline again for the stroke's first five frames (16–24 ms of
  /// raster each against 6), and the pen-up bump did it again.
  final ValueNotifier<int> celTintRevision = ValueNotifier<int>(0);

  void _bumpCelTintRevision() => celTintRevision.value += 1;

  /// The pen going down or up flips an answer only where the live stroke
  /// is what makes a cel count as drawn — [_liveStrokeCel], while the store
  /// holds no picture for it. A stroke on a drawn cel changes no block.
  void _bumpWhereTheLiveStrokeDecides() {
    final cut = _project.activeCutOrNull;
    final cel = _liveStrokeCel;
    if (cut == null || cel == null) {
      return;
    }
    final (layerId, frameId) = cel;
    if (_storeHoldsAPicture(cut, layerId, frameId)) {
      return;
    }
    _bumpCelTintRevision();
  }

  /// The store crossing a cel flips its answer — except where the live
  /// stroke gives it already ([celHoldsAPicture]): a first stroke counts
  /// its cel as drawn from pen-down, and its landing crosses the cel in the
  /// store while the pen is still down. No block changes.
  ///
  /// 🔬pen-up-dock-tail (2026-10-24, the home page in a widget test): that
  /// landing repainted every row of the timeline with not one of the
  /// panel's pixels moved, and the dock drew five frames whole after every
  /// first stroke on an empty cel, where a stroke on a drawn cel drew one.
  void _bumpWhereTheStoreCrossed() {
    final crossed = _renderCaches.brushFrameStore.celsLastCrossed;
    if (crossed.isNotEmpty && crossed.every(_theLiveStrokeAnswersFor)) {
      return;
    }
    _bumpCelTintRevision();
  }

  /// Whether [crossed] is the live stroke's cel and no other cel shows its
  /// pixels: a linked row windows the same bank, and a drag in flight hangs
  /// cels where they are not ([celPixelsOf]) — the crossing is THEIR change.
  bool _theLiveStrokeAnswersFor(BrushFrameKey crossed) {
    final cut = _project.activeCutOrNull;
    final cel = _liveStrokeCel;
    if (!_brushInputActive.value ||
        cut == null ||
        cel == null ||
        _dragPreview.value != null) {
      return false;
    }
    final (layerId, frameId) = cel;
    return crossed == _project.brushFrameKeyForCut(cut, layerId, frameId) &&
        !_project.repository.requireProject().linkRegistry.isLinked(
          cutId: cut.id,
          layerId: layerId,
        );
  }

  /// The two events that can flip [celHasContentForLayer]'s answer, and the
  /// two that can flip [celCannotBeReadForLayer]'s: a cel found unreadable,
  /// and a sound's answer moving ([_soundsMoved]).
  ///
  /// ⛔NOT EVERY PIXEL EDIT. A third listener stood here, on the store's
  /// `celPixelRevision`, for 픽셀 비우기: the crossing detector used to ask
  /// whether the store HOLDS a surface for the cel, and a cleared cel keeps
  /// its all-transparent tiles, so it never crossed and the block went on
  /// showing 「그려짐」 (유저 2026-08-27: 「블록도 반영안되는데」). Ninety
  /// minutes later the detector was made to ask
  /// `celHasRenderableContent`, which counts ink (#1280) — so the clear
  /// crosses there, and the per-edit listener only made every row repaint
  /// after every stroke (F-166). The store's detector runs on every surface
  /// it replaces; that is where a new way of emptying a cel has to cross.
  void attach() {
    _renderCaches.brushFrameStore.celContentRevision.addListener(
      _bumpWhereTheStoreCrossed,
    );
    _brushInputActive.addListener(_bumpWhereTheLiveStrokeDecides);
    _renderCaches.layerFrameImageCache.unreadable.revision.addListener(
      _bumpCelTintRevision,
    );
    _soundsMovedHeard = _soundsMoved()..addListener(_bumpCelTintRevision);
  }

  void dispose() {
    _renderCaches.brushFrameStore.celContentRevision.removeListener(
      _bumpWhereTheStoreCrossed,
    );
    _brushInputActive.removeListener(_bumpWhereTheLiveStrokeDecides);
    _renderCaches.layerFrameImageCache.unreadable.revision.removeListener(
      _bumpCelTintRevision,
    );
    _soundsMovedHeard?.removeListener(_bumpCelTintRevision);
    celTintRevision.dispose();
  }
}
