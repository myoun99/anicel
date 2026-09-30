import '../../models/attached_layer_resolve.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/cut_piece.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/pixel_clipboard_verb.dart';
import '../../models/pixel_verb_subject.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/cel_pixel_overwrite.dart';
import '../../services/cel_pixel_region.dart';
import '../../services/command.dart';
import '../../services/cut_frame_composite_plan.dart' show layerPlacementAt;
import '../../services/cut_piece_lift.dart' show buildCutPiece;
import '../../services/cut_piece_stamp.dart' show buildCutPasteDab;
import '../../services/layer_pose_matrix.dart' show LayerPoseSample;
import '../../services/commands/brush_lift_move_history_command.dart';
import '../../services/commands/cel_pixel_overwrite_command.dart';
import 'render_caches.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import '../../services/canvas_selection.dart'
    show
        SelectionMaskOptions,
        SelectionMaskReading,
        selectionMaskOnPasteboard;
import '../../services/canvas_selection_paint_clip.dart'
    show clipStampDabToSelectionMask;
import '../../services/canvas_selection_region.dart';
import '../../services/canvas_selection_shape.dart';
import 'lane_verbs.dart';
import 'pixel_board.dart';
import 'pixel_editing.dart';
import 'range_selections.dart';
import 'frame_clipboard.dart';
import 'transition_range_hold.dart';
import 'transitions.dart';

/// The canvas-side facts a PIXEL VERB press needs, read together at the
/// moment of the press.
///
/// 🚨★★★**ONE MEMBER, NOT THREE.** They were three fields on
/// `SessionInternals`, published by one method and read by one collaborator
/// — and the comment over the publisher already called them 「the canvas-side
/// facts the PIXEL verbs need」, which is a name. Adding the mask as a fourth
/// field would have widened the seam that ratchet was closing; folding them
/// narrowed it by two. ↪ The member then moved here, into the one
/// collaborator that reads it ([CellVerbs.pixelVerbCanvas]).
///
/// ⚠️Read at the PRESS, all three at once: the marquee survives tool
/// switches, the colour changes under the pointer, and the tool settings
/// panel can move the mask while the popover is open, so a value captured
/// when the editor opened would be none of them.
typedef PixelVerbCanvas = ({
  CanvasSelectionRegion? region,
  int argb,
  SelectionMaskOptions mask,
});

/// The CELL VERBS — deleting the cell under the cursor or the selection,
/// the status text a cell shows, and the pixel verbs (the keys they act
/// on, whether one may run, running it) — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class CellVerbs {
  CellVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required PixelEditing pixelEditing,
    required RenderCaches renderCaches,
    required LaneVerbs laneVerbs,
    required RangeSelections rangeSelections,
    required FrameClipboard clipboard,
    required Transitions transitions,
    required PixelBoard pixelBoard,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _pixelEditing = pixelEditing,
       _renderCaches = renderCaches,
       _laneVerbs = laneVerbs,
       _rangeSelections = rangeSelections,
       _clipboard = clipboard,
       _transitions = transitions,
       _pixelBoard = pixelBoard;

  final FrameClipboard _clipboard;

  /// 픽셀 복사's board — the app clipboard's, one for every open project.
  final PixelBoard _pixelBoard;
  final Transitions _transitions;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final PixelEditing _pixelEditing;
  final RenderCaches _renderCaches;
  final LaneVerbs _laneVerbs;
  final RangeSelections _rangeSelections;

  /// The canvas-side facts a pixel-verb press needs, published by whoever
  /// owns them — see [PixelVerbCanvas].
  ///
  /// ⛔A getter, not a copy. The marquee is a document-level fact that
  /// survives tool switches (`CanvasSelectionCommands.region`), the colour
  /// changes under the pointer, and the mask moves with the tool settings
  /// panel — so a snapshot taken when the toolbar was built would act on a
  /// selection the user has since redrawn, in a colour they have left.
  ///
  /// 🚨The colour's ALPHA is ignored downstream — RGB only (유저 확정).
  PixelVerbCanvas Function()? pixelVerbCanvas;

  /// WHICH cels the two PIXEL verbs would act on — see [PixelVerbSubject].
  PixelVerbSubject get pixelVerbSubject {
    if (pixelVerbCellKeys().isEmpty) {
      return PixelVerbSubject.nothing;
    }
    return _selection.frameRangeSelection.value == null
        ? PixelVerbSubject.standing
        : PixelVerbSubject.range;
  }

  /// The cels a pixel verb would touch: a live frame range's whole block, or
  /// the one cel you are standing on — each with a drawing in it.
  List<BrushFrameKey> pixelVerbCellKeys() => [
    for (final key in _cellsTheLadderNames())
      if (_holdsADrawing(key)) key,
  ];

  /// 🚨A PIXEL VERB NEEDS A DRAWING TO ACT ON. 유저 2026-08-27: 「색변환은
  /// 레이어에 그림이 존재 해야 활성화시키는게 맞고. 픽셀삭제는 그림이
  /// 있어야 활성화시키는게 맞고」.
  ///
  /// ⛔A frame EXISTING is not a drawing existing, and that gap is the
  /// whole bug: 픽셀 비우기 leaves the frame and its tiles in place with
  /// every alpha at zero, so the walk kept naming a cel with nothing in
  /// it and the buttons stayed lit over an empty block. This is the same
  /// question the block's tint asks, which is why it is that call and not
  /// a second rule of its own.
  ///
  /// ⛔A PASTE does not ask it (I-55): a blank cel is exactly where a paste
  /// goes — which is why this is the verb's filter over the ladder and not
  /// a rung of the ladder itself.
  bool _holdsADrawing(BrushFrameKey key) =>
      _renderCaches.brushFrameStore.celHasRenderableContent(key);

  /// The cels the ladder names, before a verb asks what is in them.
  ///
  /// ⛔No row-selection rung. Selecting rows says which rows are selected, not
  /// 「recolour all of their drawings」 — 유저 2026-08-26: 「내가 비슷한얘기
  /// 옛날에 했다가 폐기했어」. A frame range is different in kind: it is drawn
  /// across the cels themselves.
  ///
  /// ⛔NO DEDUPE HERE. Whatever lands on the cels skips one it has done,
  /// keyed by `frameStore.canonicalKeyOf` — `CelPixelOverwriteCommand`, a
  /// transform's landings, the paste — which is the RIGHT key, because it
  /// resolves links, and mine could only compare (layer, frame) ids. Two
  /// mechanisms for one invariant is the shape the F-20 bug came in; the one
  /// that owns the surfaces owns this.
  List<BrushFrameKey> _cellsTheLadderNames() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    final range = _selection.frameRangeSelection.value;
    if (range == null) {
      final standing = _standingCel(cut);
      return standing == null ? const [] : [standing];
    }
    final byId = {for (final layer in _project.layers) layer.id: layer};
    final rows = range.layerIds.isEmpty ? [range.layerId] : range.layerIds;
    return [
      for (final layerId in rows)
        if (byId[layerId] case final layer?)
          for (var i = range.startIndex; i < range.endIndexExclusive; i++)
            ?_celOf(cut, layer, i),
    ];
  }

  /// The cel you are standing on: the ACTIVE layer's, at the playhead.
  ///
  /// The playhead rung reads the ACTIVE layer, which F-20 (#1216) made the
  /// one answer — a stored verb row naming a different layer is stale.
  BrushFrameKey? _standingCel(Cut cut) {
    final activeId = _selection.activeLayerId;
    if (activeId == null) {
      return null;
    }
    for (final layer in _project.layers) {
      if (layer.id == activeId) {
        return _celOf(cut, layer, null);
      }
    }
    return null;
  }

  /// [layer]'s cel at [frameIndex] (the playhead when null), if a pixel verb
  /// may reach it.
  BrushFrameKey? _celOf(Cut cut, Layer layer, int? frameIndex) {
    // 🚨HIDDEN ROWS ARE NOT TOUCHED. 유저 2026-08-27: 「해당 두 버튼은
    // 비지블이 on인 레이어만 활성화되야함. **기본적으로 그림 조작하는건
    // 그런느낌인거지**」 — the reason is general, so it is stated as the
    // general thing: a pixel verb acts on what you can see.
    //
    // ⛔The row's own eye flag is NOT that question. It is half of it; the
    // other half is whether a folder above the row is switched off, and
    // `rowVisible` is the one door that folds both. Ratcheted by
    // `hidden_folder_is_hidden_test`, which caught this line reading the
    // raw flag — ⚠️and counts it in COMMENTS too, so the flag's name
    // cannot be written here even to say not to use it.
    if (!layerAcceptsBrushInput(layer) || !cut.layers.rowVisible(layer)) {
      return null;
    }
    final frame = _controllers.timelineController.resolveFrameForLayer(
      layer: layer,
      frameIndex: frameIndex,
    );
    if (frame == null) {
      return null;
    }
    return _project.brushFrameKeyForCut(cut, layer.id, frame.id);
  }

  /// Whether a pixel verb has anything to do — the buttons' gate, and the
  /// same question the press runs (T25: one answer behind both).
  bool get canRunPixelVerb =>
      _pixelEditing.coordinator != null &&
      pixelVerbSubject != PixelVerbSubject.nothing;

  /// Whether the 색 편집 list has a row that can run — its head's gate.
  ///
  /// ⛔The head RUNS NOTHING (I-8-Q3/Q4), so it opens when any of its rows
  /// could. Since I-55 the list holds two kinds of verb, and a head that
  /// read the four overwrite verbs alone would lock the clipboard rows out
  /// of a blank cel — which is exactly where a paste goes.
  bool get canOpenColourEdit =>
      canRunPixelVerb || _standingDrawing() != null || _canPastePixels;

  /// 색 변환 (`CelPixelChannel.colour`) and 픽셀 비우기 (`.alpha`) — one
  /// operation with the channel swapped, which is why they are one method.
  ///
  /// 🚨The colour's ALPHA is ignored, RGB only (유저 확정): 「알파만 남기고
  /// 색을 그대로 바꿔버리는거야. 그냥 진짜 색을 변환. 해당색으로. **문답무용**」.
  /// ⛔Do not ask whether turning a painted cel into a silhouette is alright —
  /// that IS the wanted behaviour, and the user said so having used it in
  /// TVPaint for years.
  ///
  /// One undo step across every cel, however many the ladder named.
  void runPixelVerb(CelPixelVerb verb) {
    final coordinator = _pixelEditing.coordinator;
    if (coordinator == null) {
      return;
    }
    final keys = pixelVerbCellKeys();
    if (keys.isEmpty) {
      return;
    }
    // Read ONCE, at the moment of the press — see [PixelVerbCanvas].
    final canvas = pixelVerbCanvas?.call();
    _project.historyManager.execute(
      CelPixelOverwriteCommand.forVerb(
        coordinator: coordinator,
        targets: _targetsFor(keys, canvas?.region),
        verb: verb,
        // 🚨WITHOUT THIS THE CANVAS DOES NOT REDRAW. The sink is optional on
        // `restoreSurfaceSnapshot`, and omitting it silently falls to a
        // no-op — the pixels change, every cache keeps serving the old
        // composite, and the edit appears only after leaving the frame and
        // coming back. 유저 2026-08-27: 「버튼 누르면 작동은하는데 캔버스쪽에서
        // 라이브로 갱신안되서 다른 프레임 갔다가 와야 반영되있어. 이런 캔버스
        // 조작은 바로바로 반영되야지」.
        cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
        // Read at the MOMENT OF THE PRESS — the bar does not hold the brush
        // colour, it asks for it. ⛔The fallback is the brush's own default,
        // not white or transparent: a press with no publisher wired must
        // still do the thing the user asked for, in the colour they would
        // have got.
        argb: canvas?.argb ?? 0xFF000000,
        // 🚨THE SELECTION'S SOFTNESS TRAVELS WITH IT. A Ctrl+T lift on the
        // same marquee already honoured 확장·페더·AA and these four verbs
        // did not, so one outline meant two things. Read at the press for
        // the same reason the colour is (the panel can change it while the
        // popover is open). ⛔The fallback is `none`, which is also every
        // option's own default — a host with nothing wired behaves exactly
        // as it did. 유저 확정 2026-09-09 (`pixel-verbs-mask-options` = 가).
        options:
            canvas?.mask ?? SelectionMaskOptions.none,
      ),
    );
  }

  /// Where [key]'s row stands on the canvas at the frame you stand on — the
  /// placement the stack PAINTS it with ([layerPlacementAt]) — or null for
  /// an unplaced row, or a key on no row of the open cut.
  ///
  /// ⛔ONE ANSWER for every verb that restates a canvas outline on the cels a
  /// range names: the pixel verbs ([_targetsFor]) and the other cels a
  /// transform's confirm lands on (a-marquee-on-a-posed-row ④ — each cel
  /// crosses through its OWN row's placement, not the standing row's). The
  /// raw track value read before missed the anchor, the fx switch and every
  /// folder above the row.
  LayerPoseSample? placementOf(BrushFrameKey key) {
    final cut = _project.activeCutOrNull;
    final layer = cut?.layers.byId(key.layerId);
    if (cut == null || layer == null) {
      return null;
    }
    return layerPlacementAt(
      cut: cut,
      layer: layer,
      frameIndex: _selection.currentFrameIndex,
    );
  }

  /// The cels a press names, each carrying the marquee restated in its own
  /// layer's artwork space.
  ///
  /// 🚨THE SPACE AXIS, and it is one law for every cel the ladder named:
  /// 「선택 있으면 그 영역, 없으면 전체(페이스트보드 포함)」 — said three
  /// times now across ③·⑤·색 변환, so it is a law and not a preference.
  List<CelPixelTarget> _targetsFor(
    List<BrushFrameKey> keys,
    CanvasSelectionRegion? region,
  ) => [
    for (final key in keys)
      CelPixelTarget(
        key: key,
        region: region == null ? null : _onTheRow(key, region),
      ),
  ];

  /// [region] — drawn on the canvas — restated in [key]'s row's artwork.
  ///
  /// ⚠️Mapped into each layer's OWN artwork space: a posed layer draws its
  /// pixels somewhere else than the marquee was drawn, and the region has
  /// to follow. An unposed layer — the overwhelming majority — gets it
  /// back unchanged (the same object, which the paste leans on to read one
  /// outline once). Null when the row's pose is singular.
  CanvasSelectionRegion? _onTheRow(
    BrushFrameKey key,
    CanvasSelectionRegion region,
  ) {
    final placement = placementOf(key);
    return regionInArtworkSpace(
      region: region,
      pose: placement?.pose,
      anchorPoint: placement?.anchorPoint,
      canvasSize: _project.requireActiveCut.canvasSize,
    );
  }

  // --- 픽셀 복사 · 붙여넣기 (I-55) · 전체 잘라내기 (I-28) ---------------------

  /// The cel 픽셀 복사 and 전체 잘라내기 read — the one you stand on, with a
  /// drawing in it — or null.
  BrushFrameKey? _standingDrawing() {
    final cut = _project.activeCutOrNull;
    if (cut == null || _pixelEditing.coordinator == null) {
      return null;
    }
    final key = _standingCel(cut);
    return key != null && _holdsADrawing(key) ? key : null;
  }

  /// The standing cel's pixels as a piece — what 픽셀 복사 (I-55) puts on the
  /// pixel board and 전체 잘라내기 (I-28) puts in the cut tool's hand.
  ///
  /// 🗣️유저 2026-10-01: 「픽셀복사는 화면 전체(현재 셀의 그림 존재하는것들.
  /// 잘라내기도구의 전체 잘라내기랑 정확히 동일 …), 다만 선택도구로 선택한게
  /// 있으면 선택된곳만 복사」 · 「로직적으론 비슷한거 사용할지라도 다른
  /// 버튼인건 인지」 — ONE read behind two buttons, which keep what it returns
  /// in two different holders.
  ///
  /// Through [selection] restated on the row, at the selection's [options];
  /// else the cel's WHOLE picture — the box the transform frames with
  /// nothing selected ([CanvasSelectionShape.wholePicture]). Raw cel
  /// pixels, no layer transform (유저 08-12 C1), in cel coordinates (C10).
  ///
  /// ⛔A frame range is not read: 「복사는 여러프레임 선택해도 무시. 현재
  /// 그림만 복사임」.
  ///
  /// Null when there is nothing to read, and a holder then keeps what it
  /// held (the cut's law — `buildCutPiece`).
  CutPiece? standingPiece({
    CanvasSelectionRegion? selection,
    SelectionMaskOptions options = SelectionMaskOptions.none,
  }) {
    final key = _standingDrawing();
    final coordinator = _pixelEditing.coordinator;
    if (key == null || coordinator == null) {
      return null;
    }
    final surface = coordinator.currentSurfaceOf(key);
    final region = selection == null
        ? CanvasSelectionRegion.shape(
            CanvasSelectionShape.wholePicture(
              surface.canvasSize,
              bitmapSurfaceContentBounds(surface),
            ),
          )
        : _onTheRow(key, selection);
    if (region == null) {
      return null;
    }
    return buildCutPiece(
      region: region,
      surface: surface,
      // The softness is the SELECTION's: a whole picture has none.
      options: selection == null ? SelectionMaskOptions.none : options,
    );
  }

  /// Where 전체 잘라내기 puts what it cuts: the cut tool's slot, published by
  /// the workspace that owns it — the session asks, the workspace holds.
  /// Null while no workspace is up, and the press then cuts nothing.
  void Function(CutPiece piece)? cutToolHand;

  /// 전체 잘라내기 (I-28): the standing cel's whole picture into the cut
  /// tool's hand — the read 픽셀 복사 makes, into the other holder.
  ///
  /// ⛔The marquee is not read. The cut tool cuts through its own outline,
  /// never the selection's, and 「전체」 is that outline opened to the whole
  /// picture (I-28-Q1 「지금 서 있는 셀의 그림 전체」).
  void cutWhole() {
    final hand = cutToolHand;
    if (hand == null) {
      return;
    }
    final piece = standingPiece();
    if (piece != null) {
      hand(piece);
    }
  }

  /// Whether the 색 편집 list's clipboard row [verb] has anything to do —
  /// its gate, and the question its press asks (T25: one answer behind both).
  bool canRunPixelClipboardVerb(PixelClipboardVerb verb) => switch (verb) {
    PixelClipboardVerb.copy => _standingDrawing() != null,
    PixelClipboardVerb.pasteAbove ||
    PixelClipboardVerb.pasteBelow => _canPastePixels,
  };

  /// Both pastes' one gate: something on the board, and a cel the ladder
  /// names — a blank one will do.
  bool get _canPastePixels =>
      _pixelBoard.piece != null &&
      _pixelEditing.coordinator != null &&
      _cellsTheLadderNames().isNotEmpty;

  /// The 색 편집 list's clipboard row [verb], pressed.
  void runPixelClipboardVerb(PixelClipboardVerb verb) {
    switch (verb) {
      case PixelClipboardVerb.copy:
        _copyPixels();
      case PixelClipboardVerb.pasteAbove:
        _pastePixels(BrushBlendMode.color);
      case PixelClipboardVerb.pasteBelow:
        _pastePixels(BrushBlendMode.behind);
    }
  }

  /// 픽셀 복사: the standing cel onto the pixel board — through the marquee
  /// the user drew, at its softness, both read at the press.
  ///
  /// ⛔Not the cursor: 「이렇게 복사한건 커서 프리뷰로 등록하는게아니야」 — the
  /// board holds it and nothing shows it.
  void _copyPixels() {
    final canvas = pixelVerbCanvas?.call();
    final piece = standingPiece(
      selection: canvas?.region,
      options: canvas?.mask ?? SelectionMaskOptions.none,
    );
    if (piece != null) {
      _pixelBoard.hold(piece);
    }
  }

  /// 픽셀 위 / 아래 붙여넣기: the pixel board, back at the cel coordinates it
  /// was read from (유저 08-12 C9·C10), on every cel the ladder names — a
  /// frame range's whole block, or the cel you stand on (「변형도구처럼 여러
  /// 프레임 선택해서 동시 붙여넣기 가능」).
  ///
  /// [blend] is the ORDER: `color` lays it over, `behind` under (위/아래 =
  /// 합성순서, 유저 08-10). ONE landing per physical cel (C5: 「같은게 두개인곳에
  /// 붙여넣으면 한번만 발리도록」), and no cel is made (C6). Through the
  /// selection when there is one — each cel reading it on its own row —
  /// else the whole board (「선택도구 있으면 선택부분에만, 없으면 기억된
  /// 전체」). At 100%: a paste puts the pixels back, it does not press them.
  ///
  /// ★The landing is the transform's multi-cel door
  /// ([BrushLiftMoveHistoryCommand] folded by `executeAsOneStep`): one cel
  /// or a whole range, the same code answers (절대명령 2) — one undo.
  void _pastePixels(BrushBlendMode blend) {
    final coordinator = _pixelEditing.coordinator;
    final piece = _pixelBoard.piece;
    if (coordinator == null || piece == null) {
      return;
    }
    final canvas = pixelVerbCanvas?.call();
    final selection = canvas?.region;
    final options = canvas?.mask ?? SelectionMaskOptions.none;
    final canvasSize = _project.requireActiveCut.canvasSize;
    // One reading per distinct outline: an unposed row gets the selection
    // back as the same object, so a range over plain rows reads it once.
    final readings =
        Map<CanvasSelectionRegion, SelectionMaskReading?>.identity();
    final store = coordinator.frameStore;
    final landed = <BrushFrameKey>{};
    final landings = <Command>[];
    for (final key in _cellsTheLadderNames()) {
      if (!landed.add(store.canonicalKeyOf(key))) {
        continue;
      }
      var dab = buildCutPasteDab(piece);
      if (selection != null) {
        final onTheRow = _onTheRow(key, selection);
        final reading = onTheRow == null
            ? null
            : readings.putIfAbsent(
                onTheRow,
                () => selectionMaskOnPasteboard(
                  onTheRow,
                  canvasSize: canvasSize,
                  options: options,
                ),
              );
        final clipped = reading == null
            ? null
            : clipStampDabToSelectionMask(
                dab,
                mask: reading.mask,
                box: reading.box,
              );
        if (clipped == null) {
          continue;
        }
        dab = clipped;
      }
      landings.add(
        BrushLiftMoveHistoryCommand(
          coordinator: coordinator,
          frameKey: key,
          preLiftSurface: coordinator.currentSurfaceOf(key),
          landingDabs: [dab],
          blendMode: blend,
          description: 'Paste pixels',
          // Without the hub the canvas keeps the old composite until you
          // leave the frame (see [runPixelVerb]).
          cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
        ),
      );
    }
    _project.historyManager.executeAsOneStep('Paste pixels', landings);
  }

  bool get hasActiveNonNegativeCell {
    return _selection.activeLayer != null &&
        _controllers.timelineController.currentFrameIndex >= 0;
  }

  /// The SELECTION-borne rungs of the cell delete, alone (B8): lane keys
  /// under the lane-verb context, or a live selection's real blocks —
  /// either axis. [deleteCellAtCurrentFrame] dispatches both before it ever
  /// asks the active layer, so a caller gated on THIS can hand the press to
  /// that verb without the active-layer rung becoming reachable.
  bool get canDeleteCellForSelection =>
      // R10 #19: the same rule Add follows — when the subject is a PROPERTY
      // row, Delete removes its keys, not a cel. It also closes a gap the
      // other way round: a live LANE span used to fall through to the cell
      // path and delete the active layer's cel instead of the keys under it.
      // F-87: keys, or a live range naming an fx header (which removes the
      // effect).
      _laneVerbs.laneVerbRangeHasSomethingToDelete ||
      // A live selection is deletable wherever the playhead stands (UI-R17
      // #2) — its blocks, and the transition spans it holds
      // (transition-row-range-in-the-cut).
      _rangeSelections.selectionBlockStartsByLayer() != null ||
      _selectionTransitionStarts != null;

  /// The transition spans THE live selection holds, either axis.
  Map<LayerId, Set<int>>? get _selectionTransitionStarts =>
      _transitions.transitionStartsHeldBy(
        inCut: _selection.frameRangeSelection.value,
        onTrack: _selection.trackFrameRangeSelection.value,
      );

  /// Whether a live CELL band owns the next cell-verb press.
  ///
  /// A band is a subject claim, not a hint: the row the user swept is the
  /// row the verb acts on, and a band holding nothing this verb may touch
  /// makes the press a NO-OP — never a redirect onto whatever row happens
  /// to be active (a cell drag never moves the active layer, so those are
  /// routinely different rows).
  ///
  /// This is what keeps the collector's `null` from meaning two things.
  /// It answers "no band at all"; the collector answers "nothing in the
  /// band is editable". Reading only the collector let a refused band
  /// fall through and delete an unselected row's drawing.
  bool get cellSelectionClaimsSubject =>
      _selection.frameRangeSelection.value != null;

  bool get canDeleteCellAtCurrentFrame {
    if (canDeleteCellForSelection) {
      return true;
    }
    // 🚨F-87 (유저 2026-09-12: 「트랜스폼 헤더에 서있으면 … 키가 없을때
    // 삭제하면 레이어의 프레임이 삭제됨. 이런거 없도록」): a LANE row claims
    // the press the way a cell band does — with nothing on it this press may
    // take, the answer is nothing, never the cel of the layer the lane
    // belongs to (R10 #19 made the row its own subject; this rung had not
    // heard).
    if (_laneVerbs.laneVerbRange != null) {
      return false;
    }
    if (cellSelectionClaimsSubject) {
      return false;
    }
    final layer = _selection.activeLayer;
    // The transition row deletes the span its mark SHOWS, on the global row
    // (transition-row-open-in-the-cut) — its cells are a projection, which
    // no cut-local cel verb may read as its own. An O.L's mark is not the
    // cut's to delete (유저 2026-09-26).
    if (layer?.kind == LayerKind.transition) {
      return _transitions.transitionSpanStartEditableInCutAt(
            _controllers.timelineController.currentFrameIndex,
          ) !=
          null;
    }
    // SYNCED attach rows: cel removal is out of v1 scope (delete the row
    // or undo the creation) — cells are display material there. Free
    // attach rows delete cells like normal (UI-R21 #3).
    //
    // SINGLE-CEL (image) rows: the one picture IS the row (its cel is
    // born with it and there is no empty state in its world), so the row
    // is what you delete. Without this the button lit and did nothing —
    // the covering normalization rebuilt the cel from the same write, so
    // the press only cost a phantom undo entry (D22).
    if (layer == null ||
        isSyncedAttachedLayer(layer) ||
        layer.kind.holdsSingleCel) {
      return false;
    }

    return _controllers.timelineController.canDeleteCellAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    );
  }

  void deleteCellAtCurrentFrame() {
    // R10 #19: a property row is its own subject — see
    // [canDeleteCellAtCurrentFrame].
    final lane = _laneVerbs.laneVerbRange;
    // F-87: the lane row takes the whole press — an fx header's range removes
    // the effect, other lanes lose their keys, and nothing falls through to
    // the cel below when there is nothing to take.
    if (lane != null) {
      _laneVerbs.deleteForLaneSelection(lane);
      return;
    }
    // A live selection routes the delete to EVERY selected block on
    // EVERY spanned layer (UI-R17 #2/#8) and to the transition spans it
    // holds, in one composite undo; the leftover selection covers empty
    // cells so it clears with the delete.
    final selectionTargets = _rangeSelections.selectionBlockStartsByLayer();
    final transitionTargets = _selectionTransitionStarts;
    if (selectionTargets != null || transitionTargets != null) {
      _project.historyManager.runAsOneStep('Delete selected cells', () {
        if (selectionTargets != null) {
          _controllers.timelineController.deleteBlocksForLayers(
            selectionTargets,
          );
        }
        if (transitionTargets != null) {
          _transitions.removeTransitionSpans(transitionTargets);
        }
      });
      // Whichever axis answered: the leftover span covers empty cells now.
      _selection.clearFrameRangeSelection();
      _selection.clearStoryboardCutSelection();
      _changes.notifyChanged();
      return;
    }
    if (cellSelectionClaimsSubject) {
      // The band holds nothing this verb may delete — that is a no-op,
      // not a licence to edit whatever row is active.
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canDeleteCellAtCurrentFrame) {
      return;
    }
    if (layer.kind == LayerKind.transition) {
      final start = _transitions.transitionSpanStartEditableInCutAt(
        _controllers.timelineController.currentFrameIndex,
      );
      if (start != null) {
        _transitions.removeTransitionSpanAt(start);
      }
      return;
    }

    _controllers.timelineController.deleteCellForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  // --- 링크 독립 (I-45): the frame-axis rung --------------------------------

  /// The runs a frame-axis 링크 독립 press means, one per row.
  ///
  /// ★DELETE'S TARGETS from the same press, read through the same claims
  /// (유저 2026-09-23: 「다른 편집버튼등의 로직 그대로 … 선택안하면
  /// 현재프레임, 선택하면 해당 선택한 소재가 기준」): a LANE row claims the
  /// press and has no cels (F-87); a band means every block it touches on
  /// every row it spans ([RangeSelections.selectionBlockStartsByLayer]); a
  /// band that touches none claims the press with nothing in it; with no
  /// band, the block under the playhead on the active row.
  ///
  /// ⚠️A row's blocks become ONE run, first start to last end — the band is
  /// contiguous, so everything between them is the band's too.
  List<UnlinkRun> _unlinkRuns() {
    if (_laneVerbs.laneVerbRange != null) {
      return const [];
    }
    final byLayer = _rangeSelections.selectionBlockStartsByLayer();
    if (byLayer == null) {
      if (cellSelectionClaimsSubject) {
        return const [];
      }
      final layer = _selection.activeLayer;
      if (layer == null || !rowHoldsLinks(layer)) {
        return const [];
      }
      final run = _controllers.timelineController.runAtPlayheadForLayer(
        layer.id,
      );
      return [(layer: layer, index: run.index, count: run.count)];
    }
    final runs = <UnlinkRun>[];
    for (final MapEntry(key: layerId, value: starts) in byLayer.entries) {
      final layer = _project.rangeLayerById(layerId);
      if (layer == null || !rowHoldsLinks(layer) || starts.isEmpty) {
        continue;
      }
      final first = starts.reduce((a, b) => a < b ? a : b);
      final last = starts.reduce((a, b) => a > b ? a : b);
      final end = last + (layer.timeline[last]?.length ?? 1);
      runs.add((layer: layer, index: first, count: end - first));
    }
    return runs;
  }

  /// Whether the frame axis holds a cel this press would give a copy of its
  /// own — the rung's gate, from the same runs its press takes.
  bool get canUnlinkCells =>
      _clipboard.sharedCelsIn(_unlinkRuns()).isNotEmpty;

  /// 링크 독립 on the frame axis ([FrameClipboard.unlinkRuns]).
  void unlinkCells() => _clipboard.unlinkRuns(_unlinkRuns());
}
