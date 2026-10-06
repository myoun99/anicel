import '../../models/brush_blend_mode.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cut.dart';
import '../../models/cut_piece.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/pixel_clipboard_verb.dart';
import '../../models/pixel_verb_subject.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/canvas_selection.dart' show SelectionMaskOptions;
import '../../services/canvas_selection_region.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/cel_pixel_overwrite.dart';
import '../../services/cel_pixel_region.dart';
import '../../services/commands/cel_pixel_overwrite_command.dart';
import '../../services/cut_frame_composite_plan.dart' show layerPlacementAt;
import '../../services/cut_piece_lift.dart' show buildCutPiece;
import '../../services/cut_piece_stamp.dart' show buildCutPasteDab;
import '../../services/layer_pose_matrix.dart' show LayerPoseSample;
import '../../services/piece_landing.dart';
import '../text/app_strings.dart';
import '../widgets/cursor_notice.dart';
import 'active_cut_controllers.dart';
import 'pixel_board.dart';
import 'pixel_editing.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// The canvas-side facts a PIXEL VERB press needs, read together at the
/// moment of the press.
///
/// 🚨★★★**ONE MEMBER, NOT THREE.** They were three fields on
/// `SessionInternals`, published by one method and read by one collaborator
/// — and the comment over the publisher already called them 「the canvas-side
/// facts the PIXEL verbs need」, which is a name. Adding the mask as a fourth
/// field would have widened the seam that ratchet was closing; folding them
/// narrowed it by two. ↪ The member then moved into the one collaborator
/// that reads it — `CellVerbs`, whose pixel half is now
/// [PixelVerbs.pixelVerbCanvas].
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

/// The PIXEL VERBS — what the 색 편집 list does to the pixels of the cels
/// (색 변환, 픽셀 비우기, 픽셀 복사, 위 · 아래 붙여넣기) and 전체 잘라내기 —
/// with the cels they act on, as their own object.
///
/// 🚨Carved out of `CellVerbs` (2026-10-01) when I-55 doubled the family
/// and pushed that class past the long-class line. The cell verbs delete
/// and unlink cels and never read a pixel; these never delete a cel — and
/// the two halves shared no member, so the cut moved no rule.
class PixelVerbs {
  PixelVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ActiveCutControllers controllers,
    required PixelEditing pixelEditing,
    required RenderCaches renderCaches,
    required PixelBoard pixelBoard,
  }) : _project = project,
       _selection = selection,
       _controllers = controllers,
       _pixelEditing = pixelEditing,
       _renderCaches = renderCaches,
       _pixelBoard = pixelBoard;

  /// 픽셀 복사's board — the app clipboard's, one for every open project.
  final PixelBoard _pixelBoard;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ActiveCutControllers _controllers;
  final PixelEditing _pixelEditing;
  final RenderCaches _renderCaches;

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
  /// back unchanged. Null when the row's pose is singular.
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
  ///
  /// 🗣️유저 2026-10-01 (F-254): 「전체 잘라내기, 지금 작동안하는 그림없는
  /// 곳에선 아무메시지 안뜨는데 뜨도록. 내용은 잘라낼 대상이 존재하지
  /// 않습니다.」 — a press that found no picture says so where the user is
  /// looking. The hand keeps what it held either way.
  void cutWhole() {
    final hand = cutToolHand;
    if (hand == null) {
      return;
    }
    final piece = standingPiece();
    if (piece == null) {
      cursorNotices.show(AppText.strings.noticeNothingToCut);
      return;
    }
    hand(piece);
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
  /// ★The landing is the piece door ([pieceLandings]) — the one the cut
  /// tool's stamp lands through too (F-293): one cel or a whole range, the
  /// same code answers (절대명령 2) — one undo.
  void _pastePixels(BrushBlendMode blend) {
    final coordinator = _pixelEditing.coordinator;
    final piece = _pixelBoard.piece;
    if (coordinator == null || piece == null) {
      return;
    }
    // ONE dab for every row: the board goes back where it was read from,
    // whichever row takes it.
    final dab = buildCutPasteDab(piece);
    final landed = pieceLandings(
      coordinator: coordinator,
      ground: pieceGround(),
      stamp: PieceStamp(
        onTheRow: (_) => dab,
        blend: blend,
        description: 'Paste pixels',
      ),
      // Without the hub the canvas keeps the old composite until you leave
      // the frame (see [runPixelVerb]).
      cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
    );
    _project.historyManager.executeAsOneStep('Paste pixels', [
      for (final cel in landed.values) cel.landing,
    ]);
  }

  /// WHERE a held picture lands, read at the press — 픽셀 붙여넣기's ground
  /// and, handed to the canvas, the cut tool's stamp's (F-293: 「색편집의
  /// 픽셀붙여넣기랑 법 통일」).
  ///
  /// ⛔ONE reading for both. The canvas could assemble the same four facts
  /// from what it holds — and then a range, a row's placement or a marquee's
  /// softness could come to mean two things, by which button held the
  /// picture.
  ///
  /// The cels are the LADDER's, before a verb asks what is in them: a blank
  /// cel is exactly where a paste goes ([_holdsADrawing]).
  PieceGround pieceGround() {
    // Read ONCE, at the moment of the press — see [PixelVerbCanvas].
    final canvas = pixelVerbCanvas?.call();
    return PieceGround(
      cels: _cellsTheLadderNames(),
      placementOf: placementOf,
      selection: canvas?.region,
      options: canvas?.mask ?? SelectionMaskOptions.none,
    );
  }
}
