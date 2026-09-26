import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/identity_memo.dart';
import '../../models/app_input_settings.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart' show conteInkRowIdOf;
import '../../models/conte/conte_page_marks.dart'
    show conteCellTextSize, conteInkArgb;
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import '../brush/brush_canvas_panel.dart' show BrushCanvasPanel;
import '../brush/sheet_canvas_panel.dart';
import '../effective_device_pixel_ratio.dart';
import '../input/control_press_claim.dart';
import '../sheet/sheet_ink_layer.dart' show SheetPictureWindow, SheetWindow;
import '../sheet/sheet_text_edit_layer.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../canvas/active_stroke_overlay.dart';
import '../editor_session_manager.dart';
import '../storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailTier, StoryboardThumbnails;
import '../timeline/timeline_drag_preview.dart'
    show CutTrimDragPreview, TimelineDragPreview;
import '../text/app_strings.dart';
import '../widgets/page_turn_strip.dart';
import '../sheet/sheet_strata.dart';
import 'conte_fonts.dart';
import 'conte_ink.dart';
import 'conte_page_painter.dart';
import 'conte_picture_ink.dart';
import 'conte_picture_live.dart';
import 'conte_sheet_builder.dart';
import 'conte_words_in.dart';

/// The conte PANEL: the sheet as paper inside the canvas panel shell —
/// the timesheet's architecture with conte content (#16, "콘티 패널 =
/// 타임시트 패널과 통일 — 캔버스 베이스, 그리기 가능").
///
/// It draws the very renderer the export does ([ContePagePainter]), so
/// what is on screen is the page. Navigation is the drawing canvas's:
/// wheel zoom, middle-drag/two-finger pan, panbars, Fit. With an
/// [inkController] and [brushToolState] the sheet takes freehand ink with
/// the current brush/eraser; brush off, clicking a cell selects that
/// cut, its storyboard row and the cell's frame, which is how the other
/// panels follow along.
class ConteTabHost extends StatefulWidget {
  const ConteTabHost({
    super.key,
    required this.session,
    required this.thumbnails,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.inkController,
    this.pictures,
    this.brushToolState,
    this.brushAllowed = false,
    this.onBrushAllowedChanged,
    this.imageFor,
    this.imageRepaint,
  });

  final EditorSessionManager session;

  /// A media image by its asset path — the company logo each body page
  /// prints top-right, the cover's picture. The workspace's decode cache,
  /// the one the envelope prints its logo from.
  final ui.Image? Function(String assetPath)? imageFor;

  /// Notifies when an image [imageFor] answered null for has landed — the
  /// page's inputs do not change for it, so this is what repaints it.
  final Listenable? imageRepaint;

  /// The panels' pictures — the SAME store the storyboard strip draws
  /// from, so a cell and its strip panel are one render. A landed one must
  /// REPAINT the page (the painter's compared fields don't change when an
  /// async picture arrives), which is what its `landed` is for.
  final StoryboardThumbnails? thumbnails;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Conte ink store, owned above the tab group so annotations survive
  /// tab switches. Null renders the sheet read-only.
  final ConteInkController? inkController;

  /// The cels the cells' pictures draw into — the canvas's own. Null
  /// leaves the pictures read-only while the sheet takes ink.
  final ContePictureInkController? pictures;

  /// The editor's current brush/eraser LISTENABLE (R18 UI-3): only the
  /// ink overlay subscribes — tool switches never rebuild the document.
  final ValueListenable<BrushToolState>? brushToolState;

  /// The sheet's brush switch (브러시 허용): off protects the page from
  /// stray pen marks AND turns taps back into cell selection (the tap layer
  /// sits under the ink window). Off by default — the conte's first verb
  /// is reading and selecting, not annotating.
  final bool brushAllowed;
  final ValueChanged<bool>? onBrushAllowedChanged;

  // No shrink floor of its own: the conte is a PAGE that scales into
  // whatever it is given. ↩️It had one — the ACTION field that mounted
  // under the page when a cell was selected, a row that did not flex. The
  // ACTION is edited on the page now, and the panel mounts nothing under
  // the shell (the envelope's case).

  @override
  State<ConteTabHost> createState() => _ConteTabHostState();
}

/// What the ink windows are mounted with: the sheet's ink, the brush in
/// hand, and the page on screen.
typedef _InkMount = ({
  ConteInkController controller,
  ValueListenable<BrushToolState> tool,
  ContePageLayout page,
});

class _ConteTabHostState extends State<ConteTabHost> {
  EditorSessionManager get _session => widget.session;

  /// Commit sink required by the panel API; conte ink invalidations stay
  /// local (synthetic ink keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  /// The page on screen; null until turned — the body's first page, the
  /// cover and its blank back a turn away (the conte is worked on in its
  /// body; the book's order is kept for turning and printing).
  int? _page;

  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => _session.setBrushInputActive(live),
  );

  // Memoized sheet source + pages: the source reads the WHOLE project, so
  // it is rebuilt only when the project object (or the camera aspect that
  // shapes the cells) actually changes — the immutable repository makes
  // identity the staleness check, the timesheet host's pattern.
  final _sheet = IdentityMemo<(ConteSheetSource, List<ContePageLayout>)>();

  /// Each picture's live stroke, by picture — the one its pen draws and its
  /// composite paints. Held HERE, above both: they are let go when this is,
  /// after every view that draws into them. ↩️The pictures' controller held
  /// them, and outlived nothing: let go with a project going off screen, it
  /// left the views still on screen drawing into what it had disposed.
  final Map<String, ActiveStrokeOverlayModel> _strokes = {};

  ActiveStrokeOverlayModel _strokeOf(String picture) =>
      _strokes.putIfAbsent(picture, ActiveStrokeOverlayModel.new);

  // The cells with no block — picture and band — take the pen or refuse it
  // as the canvas's 「프레임 자동 생성」 says, so the page is laid again when
  // it flips.
  @override
  void initState() {
    super.initState();
    AppInput.settings.addListener(_onInputSettings);
  }

  void _onInputSettings() => setState(() {});

  @override
  void dispose() {
    AppInput.settings.removeListener(_onInputSettings);
    _strokeHold.dispose();
    for (final stroke in _strokes.values) {
      stroke.dispose();
    }
    super.dispose();
  }

  (ConteSheetSource, List<ContePageLayout>) _resolveSheet() {
    final project = _session.repository.requireProject();
    final aspect = _session.camera.cameraFrameAspect;
    return _sheet.resolve(
      identity: project,
      key: aspect,
      build: () {
        final source = buildConteSheetSource(project);
        return (
          source,
          layoutConteBook(
            source,
            metrics: ConteSheetMetrics(cameraAspect: aspect),
          ),
        );
      },
    );
  }

  /// A cell press: the cut, its storyboard row and the frame — the
  /// design's "칸 클릭 = selectCut + selectLayer + selectFrameIndex".
  void _selectCell(ContePlacedCell cell) {
    final cutId = CutId(cell.cutId);
    if (_session.activeCutOrNull?.id != cutId) {
      _session.selectCut(cutId);
    }
    // 🚨T4 — 「여기 서라」 IS the verb, on this panel too. 유저 2026-08-13:
    // 「어떤 행이든 액티브 바꾸면 풀리도록」. Pressing a conte cell moves you
    // to another cut's storyboard row, which is moving, so it lets a live
    // selection go exactly as a row click and an arrow step do.
    //
    // ⚠️The frame is passed IN rather than seeked afterwards: the standing
    // law asks whether you are landing inside the current selection, and
    // asking that about the frame you are LEAVING answers the wrong
    // question.
    var stood = false;
    for (final layer in _session.layers) {
      if (layer.kind == LayerKind.storyboard) {
        _session.standOnRow(
          LayerRowAddress(layer.id),
          frameIndex: cell.source.startFrame,
        );
        stood = true;
        break;
      }
    }
    if (!stood) {
      _session.selectFrameIndex(cell.source.startFrame);
    }
  }

  /// The ACTION column's in-place targets: a tap on a cell's ACTION edits it
  /// on the paper (유저 2026-09-25: 「액션은 콘티프리뷰에서 해당 칸 누르면
  /// 텍스트 편집할수있게하고, 데이터는 … 해당 콘티블록에 저장」).
  ///
  /// The words land on the exposure that opens the cell — the memo is
  /// block-owned, so it travels with every move and copy, and a linked or
  /// same-named block keeps its own (「같은 이름의 콘티블록이랑 링크된다고
  /// 해도 내용물은 독립」: a link shares the drawing, never the timeline's
  /// entries). A cell with no block has nowhere to keep them and offers no
  /// target.
  List<SheetTextTarget> _actionTargets(ContePageLayout page) {
    final m = page.metrics;
    return [
      for (final cell in page.cells)
        if (cell.source.frameId != null)
          SheetTextTarget(
            keyValue: 'conte-action-edit-${cell.cutId}-${cell.cellIndex}',
            // The cell's own rows of the column — its words flow past them
            // on paper, but a tap below belongs to the cell there.
            box: Rect.fromLTRB(
              cell.actionRect.left,
              m.rowTop(cell.rowOnPage),
              cell.actionRect.right,
              m.rowTop(cell.rowOnPage + cell.source.rowSpan),
            ),
            textRect: Rect.fromLTRB(
              cell.actionRect.left + 4,
              m.rowTop(cell.rowOnPage) + 4,
              cell.actionRect.right - 4,
              m.rowTop(cell.rowOnPage + cell.source.rowSpan) - 4,
            ),
            text: cell.source.action,
            style: conteTextStyle(
              conteCellTextSize,
              color: const Color(conteInkArgb),
            ),
            onCommitted: (text) =>
                _session.storyboardCursor.setStoryboardCellAction(
                  cutId: CutId(cell.cutId),
                  cellIndex: cell.cellIndex,
                  action: text,
                ),
          ),
    ];
  }

  ui.Image? _pictureFor(String cutId, int frame) {
    final resolver = widget.thumbnails?.resolve;
    if (resolver == null) {
      return null;
    }
    for (final track in _session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id.value == cutId) {
          // The SHEET tier: a conte cell is a printed frame that also
          // exports, not a strip block, and asking for the strip's 128px
          // is what made the pictures look quarter-resolution.
          return resolver(cut, frame, tier: StoryboardThumbnailTier.sheet);
        }
      }
    }
    return null;
  }

  void _turnToPage(int page, int pageCount) {
    final next = pageCount <= 0 ? 0 : page.clamp(0, pageCount - 1);
    if (next != _page) {
      setState(() => _page = next);
    }
  }

  /// What the ink windows are mounted with — or null while the sheet's
  /// drawing is off. ONE gate: the ink layer, the panel's [drawingOn] and
  /// the painter's live keys all ask this, so none can say 「drawing」
  /// while another says not.
  _InkMount? _inkMount(ContePageLayout? page) {
    final controller = widget.inkController;
    final tool = widget.brushToolState;
    if (page == null ||
        controller == null ||
        tool == null ||
        !widget.brushAllowed) {
      return null;
    }
    return (controller: controller, tool: tool, page: page);
  }

  @override
  Widget build(BuildContext context) {
    final (source, pages) = _resolveSheet();
    final pageCount = pages.length;
    // The page INDEX is clamped everywhere it is read (readout included):
    // deleting cuts can shrink the count under a stored _page, and an
    // unclamped readout printed "5 / 2" with no way back.
    final firstBody = pages.indexWhere(
      (page) => page.kind == ContePageKind.body,
    );
    final pageIndex = pageCount == 0
        ? 0
        : (_page ?? math.max(firstBody, 0)).clamp(0, pageCount - 1);
    final page = pageCount == 0 ? null : pages[pageIndex];
    final inkController = widget.inkController;
    final onBrushAllowedChanged = widget.onBrushAllowedChanged;
    final metrics = page?.metrics;
    if (inkController != null && metrics != null) {
      inkController.syncGeometry(metrics);
    }
    final ink = _inkMount(page);
    final pictures = ink == null
        ? const <ContePicture>[]
        : _picturesOf(ink.page);

    final panel = SheetCanvasPanel(
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: metrics == null
          // The empty-project stand-in matches the real page's PORTRAIT
          // A4 so the stage geometry holds when pages appear.
          ? const CanvasSize(width: 596, height: 842)
          : CanvasSize(
              width: metrics.pageWidth.ceil(),
              height: metrics.pageHeight.ceil(),
            ),
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      brushSwitch: onBrushAllowedChanged == null
          ? null
          : (
              allowed: widget.brushAllowed,
              onChanged: onBrushAllowedChanged,
              keyPrefix: 'conte',
            ),
      // The page cluster, on the panel's LEFT edge (유저 확정 ⑥ 2026-08-13).
      pageStrip: pageTurnStrip(
        keyPrefix: 'conte',
        page: viewerPage(pageIndex, pageCount),
        onTurnTo: (page) => _turnToPage(page, pageCount),
      ),
      bottomBarHostToken: (pageIndex, pageCount),
      fitFocusRect: metrics == null
          ? null
          : Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
      drawingOn: ink != null,
      strokeHold: _strokeHold,
      content: (context, viewport) {
        // F-179: off the paper is the canvas panel's backdrop — no fill of
        // the sheet's own here.
        return Stack(
          children: [
            if (page != null)
              _pageLayer(page, source, viewport, context, inkController),
            // Under the ink window: reachable exactly when the brush is off
            // (the switch doubles as the edit-mode switch, the timesheet's
            // header-edit rule).
            if (page != null) _cellTapLayer(viewport, page),
            if (page != null)
              Positioned.fill(
                child: SheetTextEditLayer(
                  targets: _actionTargets(page),
                  viewport: viewport,
                  fieldKey: 'conte-action-field',
                  barrierKey: 'conte-action-edit-barrier',
                ),
              ),
            // Under the pen, over the page: the pictures the brush draws
            // into, composited live while it is on.
            if (ink != null && pictures.isNotEmpty)
              Positioned.fill(
                child: ContePictureLive(
                  // A picture that refuses the pen shows what it prints.
                  pictures: [
                    for (final picture in pictures)
                      if (picture.window.refusal == null) picture,
                  ],
                  session: _session,
                  surfaceOf: (picture) => widget.pictures!
                      .sessionStateFor(
                        picture.window.plane! as CanvasSize,
                        picture.window.key,
                      )
                      .canvasState
                      .currentSurface,
                  viewport: viewport,
                  effectiveRatio: EffectiveDevicePixelRatio.of(context),
                  paper: Size(
                    ink.page.metrics.pageWidth,
                    ink.page.metrics.pageHeight,
                  ),
                ),
              ),
            if (ink != null) _inkLayer(ink, viewport, pictures),
          ],
        );
      },
    );

    return KeyedSubtree(
      key: const ValueKey<String>('conte-panel'),
      child: panel,
    );
  }

  /// The pictures [page]'s brush draws into — none without the cels'
  /// controller.
  List<ContePicture> _picturesOf(ContePageLayout page) {
    if (widget.pictures == null) {
      return const [];
    }
    final autoFrame = _session.autoFrame;
    return contePictures(page, (
      cutOf: _session.cutById,
      celKeyOf: _session.brushFrameKeyForCut,
      cameraPoseOf: _session.camera.cameraPoseForCut,
      cameraFrameSize: _session.camera.cameraFrameSize,
      conteCelOf: autoFrame.conteCelFor,
      rowRefusal: _rowRefusal,
    ), _strokeOf);
  }

  /// Why a cell with no block takes no ink, picture and band alike — the
  /// canvas's notice, word for word, for a press on a cell it may not fill
  /// (`EditorCanvasArea._drawRefusalFor`); null while its 「프레임 자동
  /// 생성」 is on and the stroke makes the block.
  String? get _rowRefusal => _session.autoFrame.autoCreates
      ? null
      : AppStrings.of(
          _session.languageSettings.value.programLanguage,
        ).noticeNoFrameHere;

  /// A piece of a stroke landing makes what it was drawn into, in the
  /// stroke's own undo step: a cell with no block the block — its picture
  /// and its band alike (유저 답 conte-drawing-target-Q3 「그림 칸과 같이
  /// (토글을 따른다)」) — and a block's first handwriting the block's id.
  void _makeWhatTheStrokeLandsIn(SheetWindow window) {
    final inkId = conteInkRowIdOf(window.key);
    if (window is! SheetPictureWindow && inkId == null) {
      return;
    }
    final cut = _session.cutById(window.key.cutId);
    if (cut == null) {
      return;
    }
    _session.autoFrame.addConteCel(cut);
    if (inkId != null) {
      _session.storyboardCursor.writeConteBlockInk(cut.id, inkId);
    }
  }

  /// The name the pen writes a block not yet written on under
  /// (`StoryboardCursor.conteInkIdFor`).
  String _unwrittenInkIdOf(ContePlacedCell cell) => _session.storyboardCursor
      .conteInkIdFor(CutId(cell.cutId), cell.source.startFrame);

  Positioned _inkLayer(
    _InkMount ink,
    CanvasViewport viewport,
    List<ContePicture> pictures,
  ) {
    return Positioned.fill(
      // The tool-state boundary (R18 UI-3) went one step further down (H40
      // ②, 2026-09-24): the overlay no longer rebuilds for the brush at all —
      // its windows read it when a stroke starts.
      child: ConteInkLayer(
        key: const ValueKey<String>('conte-ink-layer'),
        controller: ink.controller,
        page: ink.page,
        brushToolState: ink.tool,
        historyManager: _session.historyManager,
        viewport: viewport,
        strokeActive: _strokeHold,
        cacheInvalidationSink: _cacheInvalidationSink,
        pictures: widget.pictures,
        pictureWindows: [for (final picture in pictures) picture.window],
        pictureInvalidationSink: _session.renderCaches.cacheInvalidationHub,
        unwrittenInkIdOf: _unwrittenInkIdOf,
        rowRefusal: _rowRefusal,
        beforeLanding: _makeWhatTheStrokeLandsIn,
      ),
    );
  }

  /// Each cell's picture, a claimed press of its own.
  ///
  /// 🚨H24 (2026-09-15): the canvas surface under the sheet takes the arena
  /// on the first movement, and one tap recogniser over the whole page lost
  /// its tap to it the moment a finger wobbled. A cell fires from its claim
  /// instead — the timesheet's header boxes' law — and not for a press the
  /// canvas turned into a pan or a pinch.
  ///
  /// ⚠️REVERSED, so where two pictures overlap (a cell that encroaches with a
  /// horizontal camera move) the EARLIER cell is on top and takes the press,
  /// as the page-wide layer's first-match loop gave it.
  Positioned _cellTapLayer(CanvasViewport viewport, ContePageLayout page) {
    return Positioned.fill(
      child: Stack(
        key: const ValueKey<String>('conte-cell-tap-layer'),
        children: [
          for (final cell in page.cells.reversed)
            Positioned.fromRect(
              rect: _onScreen(viewport, cell.pictureRect),
              child: ControlPressClaim(
                onPressed: () => _selectCell(cell),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: silentPress(() => _selectCell(cell)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [documentRect] where [viewport] puts it on screen.
  Rect _onScreen(CanvasViewport viewport, Rect documentRect) {
    final topLeft = viewport.canvasToViewport(
      CanvasPoint(x: documentRect.left, y: documentRect.top),
    );
    final bottomRight = viewport.canvasToViewport(
      CanvasPoint(x: documentRect.right, y: documentRect.bottom),
    );
    return Rect.fromPoints(
      Offset(topLeft.x, topLeft.y),
      Offset(bottomRight.x, bottomRight.y),
    );
  }

  Positioned _pageLayer(
    ContePageLayout page,
    ConteSheetSource source,
    CanvasViewport viewport,
    BuildContext context,
    ConteInkController? inkController,
  ) {
    ContePagePainter painterOf(
      SheetStratum stratum, {
      ValueListenable<TimelineDragPreview?>? dragPreview,
      Set<BrushFrameKey> liveInkKeys = const {},
      List<Listenable?> repaint = const [],
    }) => ContePagePainter(
      page: page,
      source: source,
      // The printed words follow the notation language, as the timesheet's
      // do.
      words: conteWordsIn(_session.languageSettings.value.notationLanguage),
      // No outline marks the cell being worked on (유저 2026-09-25:
      // 「포커스기능 없애자 … 해당 칸 강조색 실루엣한다던가」) — the sheet
      // is paper, and paper shows no focus.
      pictureFor: _pictureFor,
      imageFor: widget.imageFor,
      viewport: viewport,
      effectiveRatio: EffectiveDevicePixelRatio.of(context),
      layers: stratum.layers,
      // Saved sheet ink shows whatever the ink mode says (R5); a live input
      // window's key stands down so translucent ink never composites twice.
      inkImageFor: inkController == null
          ? null
          : (key) =>
                inkController.displayImageFor(ConteInkPlane.of(key), key),
      liveInkKeys: liveInkKeys,
      dragPreview: dragPreview,
      repaint: repaint.isEmpty ? null : Listenable.merge(repaint),
    );
    return Positioned.fill(
      // The sheet page is the timesheet's answer applied to its sibling. A
      // `RepaintBoundary` here stopped the page being re-RECORDED, which was
      // never the cost — the raster thread still replayed the whole display
      // list every frame the app produced, for any reason, including the pen
      // moving over the canvas in another panel.
      //
      // The surrounding `Stack` already clips `Clip.hardEdge`, so each bake's
      // own clip is a no-op and the pixels do not move.
      child: SheetStrata(
        sheet: 'conte',
        painters: {
          SheetStratum.form: painterOf(SheetStratum.form),
          // F-88: the numbers this page prints follow a cut-length drag, so
          // the channel is both a VALUE the paint reads and a reason to
          // repaint. A landed logo — nothing the painter compares changes
          // for it.
          SheetStratum.content: painterOf(
            SheetStratum.content,
            dragPreview: _session.dragPreview,
            repaint: [_session.dragPreview, widget.imageRepaint],
          ),
          // A landed thumbnail or cover picture, likewise.
          SheetStratum.picture: painterOf(
            SheetStratum.picture,
            repaint: [widget.thumbnails?.landed, widget.imageRepaint],
          ),
          if (inkController != null)
            SheetStratum.ink: painterOf(
              SheetStratum.ink,
              liveInkKeys: _inkMount(page) == null
                  ? const {}
                  : {for (final window in conteInkWindows(page)) window.key},
              repaint: [inkController],
            ),
        },
        // ⚠️A stratum stands down while it changes on every step — the ink
        // while the pen is down, the numbers while a cut-length drag
        // re-prints them (F-88): capturing costs a full paint PLUS a full
        // copy a step.
        liveNow: (stratum) => switch (stratum) {
          SheetStratum.ink => _strokeHold.value,
          SheetStratum.content =>
            _session.dragPreview.value is CutTrimDragPreview,
          SheetStratum.form || SheetStratum.picture => false,
        },
        liveChanges: Listenable.merge([_strokeHold, _session.dragPreview]),
      ),
    );
  }
}
