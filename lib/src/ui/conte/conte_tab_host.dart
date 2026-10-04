import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/identity_memo.dart';
import '../../core/page_stack.dart';
import '../../models/app_input_settings.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart' show conteInkRowIdOf;
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/sheet_marks.dart' show SheetPicture;
import '../../models/timeline_row_address.dart';
import '../../models/track_id.dart';
import '../../services/project_lookup.dart'
    show brushFrameKeyIn, cutPositionOf;
import '../brush/brush_canvas_panel.dart' show BrushCanvasPanel;
import '../brush/sheet_canvas_panel.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_ink_layer.dart' show SheetPictureWindow, SheetWindow;
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../brush/canvas_book.dart';
import '../canvas/active_stroke_overlay.dart';
import '../canvas/viewport_canvas_transform.dart' show canvasRectShown;
import '../editor_session_manager.dart';
import '../storyboard_cut_thumbnail_store.dart' show StoryboardThumbnails;
import '../storyboard_layer_policy.dart' show storyboardLayerForCut;
import '../text/app_strings.dart';
import '../widgets/page_turn_strip.dart';
import 'conte_book_page.dart';
import 'conte_ink.dart';
import 'conte_page_painter.dart';
import 'conte_picture_ink.dart';
import 'conte_sheet_builder.dart';

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
/// hand, the pages on screen as the brush draws on them — each where it
/// lies in the stack — and the project those pages are laid from
/// (`_brushPageOf`).
typedef _InkMount = ({
  ConteInkController controller,
  ValueListenable<BrushToolState> tool,
  List<ConteShownPage> pages,
  Project project,
});

class _ConteTabHostState extends State<ConteTabHost> {
  EditorSessionManager get _session => widget.session;

  /// Commit sink required by the panel API; conte ink invalidations stay
  /// local (synthetic ink keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  /// The page the reader is on (F-201) — a write is a turn, and the panel
  /// keeps it true to the view ([CanvasBook]). A view nobody has moved yet
  /// is fitted to it.
  late final ValueNotifier<int> _reading = ValueNotifier(_openingPage());

  /// Where the reader opens: on the body's first page — the cover and its
  /// blank back lie above it (the conte is worked on in its body; the
  /// book's order is kept for turning and printing) — or, when the view
  /// was left somewhere, on the page it was left at, as [pageReadAt]
  /// reads it from the stored view alone. The panel reads it again once
  /// it has laid out the window.
  int _openingPage() {
    final pages = _resolveSheet().$2;
    final firstBody = math.max(
      0,
      pages.indexWhere((page) => page.kind == ContePageKind.body),
    );
    final kept = _view.value;
    if (kept == null) {
      return firstBody;
    }
    // The view is kept in the paper's pixels; the book is laid in points.
    final view = sheetUnitsView(kept, _metricsOf(pages).paperScale);
    final top = -view.panY / view.zoom;
    return pageReadAt(
      _stackOf(pages),
      current: firstBody,
      top: top,
      bottom: top,
    );
  }

  /// The measurements [pages] are laid by — every page shares one — or,
  /// for a book with no page yet, the ones its pages will have.
  static ConteSheetMetrics _metricsOf(List<ContePageLayout> pages) =>
      pages.isEmpty ? const ConteSheetMetrics() : pages.first.metrics;

  // The book one page under another (F-201), memoized with the pages it
  // lays.
  final _stack = IdentityMemo<PageStack>();

  PageStack _stackOf(List<ContePageLayout> pages) => _stack.resolve(
    identity: pages,
    build: () => PageStack([
      for (final page in pages)
        ui.Size(page.metrics.pageWidth, page.metrics.pageHeight),
    ]),
  );

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
    // The page strip reads the view; a caller's own view rebuilds this from
    // above, this one from here.
    _ownView.addListener(_onInputSettings);
    // And the reader's page, which the panel moves.
    _reading.addListener(_onInputSettings);
  }

  void _onInputSettings() => setState(() {});

  /// The view when the caller keeps none, seeded from
  /// [ConteTabHost.viewport] — so a turn always has a view to scroll.
  late final ValueNotifier<CanvasViewport?> _ownView = ValueNotifier(
    widget.viewport,
  );

  /// The one view the panel shows and a turn scrolls, in DEVICE units.
  ValueNotifier<CanvasViewport?> get _view =>
      widget.viewportController ?? _ownView;

  @override
  void didUpdateWidget(covariant ConteTabHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewport != oldWidget.viewport) {
      _ownView.value = widget.viewport;
    }
    if (_drawingIn(oldWidget) && !_drawing) {
      _awaitingPrints = true;
    }
  }

  /// 🗣️F-215 (유저 2026-09-28): 「on하든off하든 바뀌는게 없어야
  /// 구조적으로 맞는거아닌가?」 Switched off, the pictures the brush drew
  /// into stay live until the prints under them have caught up: a stroke
  /// raised its cut's signature, each of its prints renders again, and
  /// standing down at once showed the picture from before the stroke until
  /// the new one landed. The pen goes with the switch; the pictures stay
  /// until [_PrintsCaughtUp] says the store owes none.
  bool _awaitingPrints = false;

  @override
  void dispose() {
    AppInput.settings.removeListener(_onInputSettings);
    _ownView.dispose();
    _reading.dispose();
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
      build: () => _laidOut(project, aspect),
    );
  }

  /// [project] as the conte prints it, cells shaped by the camera's
  /// [aspect]: the source it reads, and the book it lays.
  static (ConteSheetSource, List<ContePageLayout>) _laidOut(
    Project project,
    double aspect,
  ) {
    final source = buildConteSheetSource(project);
    return (
      source,
      layoutConteBook(source, metrics: ConteSheetMetrics(cameraAspect: aspect)),
    );
  }

  /// A cell press: the cut, its storyboard row and the frame — the
  /// design's "칸 클릭 = selectCut + selectLayer + selectFrameIndex".
  ///
  /// ↩️F-187 (유저 2026-09-26): the row is what every door that stands on a
  /// cut seats ([Standing.layerACutStandSeats]) — its storyboard row, or,
  /// when it has none, the layer you stood on if the cut shows it
  /// (「컷에설때 콘티레이어가 없다면 마지막에 선 레이어 그냥 그대로둠」).
  void _selectCell(ContePlacedCell cell) {
    final cutId = CutId(cell.cutId);
    final before = _session.activeLayerId;
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
    final seat = _session.standing.layerACutStandSeats(before: before);
    if (seat != null) {
      _session.standOnRow(
        LayerRowAddress(seat),
        frameIndex: cell.source.startFrame,
      );
    } else {
      _session.selectFrameIndex(cell.source.startFrame);
    }
  }

  /// A cell's picture at the size its window shows it — the zoom and the
  /// screen's density decide, not a size of the conte's own (유저
  /// 2026-09-25: 「화면이 필요한 만큼(최대 원본)」). ↩️It asked one fixed
  /// 640px picture, which a cell zoomed past about 2.4× stretched. A cell
  /// whose camera moves asks for the canvas that camera sweeps
  /// ([SheetPicture.canvasRegion]).
  ui.Image? _pictureFor(SheetPicture picture, double shownHeight) {
    final resolver = widget.thumbnails?.resolve;
    if (resolver == null) {
      return null;
    }
    for (final track in _session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id.value == picture.cutId) {
          return resolver(
            cut,
            picture.pictureFrame,
            shownHeight: shownHeight,
            region: picture.canvasRegion,
          );
        }
      }
    }
    return null;
  }

  /// Whether the sheet takes ink now. ONE gate: the ink layer, the panel's
  /// [SheetCanvasPanel.drawingOn] and the painter's live keys all ask this,
  /// so none can say 「drawing」 while another says not.
  bool get _drawing => _drawingIn(widget);

  static bool _drawingIn(ConteTabHost host) =>
      host.inkController != null &&
      host.brushToolState != null &&
      host.brushAllowed;

  /// What the ink windows are mounted with for the pages on screen — or
  /// null while the sheet's drawing is off.
  _InkMount? _inkMount(List<ConteShownPage> shown) {
    final controller = widget.inkController;
    final tool = widget.brushToolState;
    if (shown.isEmpty || !_drawing || controller == null || tool == null) {
      return null;
    }
    final drawn = [for (final (:page, :at) in shown) (_brushPageOf(page), at)];
    return (
      controller: controller,
      tool: tool,
      pages: [for (final (brush, at) in drawn) (page: brush.page, at: at)],
      project: drawn.first.$1.project,
    );
  }

  // The sheet laid with the conte's next cut in it, memoized as [_sheet]
  // is — plus what the cut is planned from that the project is not: the
  // active cut's canvas, which a new cut takes.
  final _nextSheet =
      IdentityMemo<({Project project, List<ContePageLayout> pages})?>();

  /// [page] as the brush draws on it, and the project it is laid from: the
  /// sheet with the cut a stroke past its last cell makes (H44, 유저 09-26:
  /// 「자동프레임생성 켜져있으면 다음컷이나 다음 열에 그리면 컷 만들도록」) —
  /// that cut put in the project (`AutoFrameForStroke.nextConteCut`) and laid
  /// by the engine that lays the sheet. Every cell before it lies where it
  /// lay, and its own takes the first free row after the last cell: its
  /// picture and band take the pen as a cell with no block does — a stroke
  /// there makes the cut, its conte row and block in the stroke's own undo
  /// step, or, with the canvas's 「프레임 자동 생성」 off, nothing.
  ///
  /// ⛔That row and no other: a stroke further down would make a cut whose
  /// cell is not where it was drawn. With the last page full, the cell falls
  /// on a page the sheet does not have, and no row takes it.
  ({ContePageLayout page, Project project}) _brushPageOf(
    ContePageLayout page,
  ) {
    final project = _session.repository.requireProject();
    final aspect = _session.camera.cameraFrameAspect;
    final next = _nextSheet.resolve(
      identity: project,
      key: (aspect, _session.activeCutOrNull?.canvasSize),
      build: () {
        final next = _session.autoFrame.nextConteCut();
        if (next == null) {
          return null;
        }
        final withNext = _withCutAtTheEnd(project, next.trackId, next.cut);
        return (project: withNext, pages: _laidOut(withNext, aspect).$2);
      },
    );
    return next == null
        ? (page: page, project: project)
        : (page: next.pages[page.pageIndex], project: next.project);
  }

  @override
  Widget build(BuildContext context) {
    final (source, pages) = _resolveSheet();
    final inkController = widget.inkController;
    if (inkController != null && pages.isNotEmpty) {
      // Every page shares one metrics.
      inkController.syncGeometry(pages.first.metrics);
    }
    return KeyedSubtree(
      key: const ValueKey<String>('conte-panel'),
      child: _panel(source, pages),
    );
  }

  /// The book on the canvas panel, every page one under another (F-201),
  /// the page strip reading and turning the page the view is on.
  Widget _panel(ConteSheetSource source, List<ContePageLayout> pages) {
    final stack = _stackOf(pages);
    final book = CanvasBook(pages: stack, reading: _reading);
    final pageIndex = book.page;
    final onBrushAllowedChanged = widget.onBrushAllowedChanged;
    final metrics = _metricsOf(pages);
    return SheetCanvasPanel(
      cacheInvalidationSink: _cacheInvalidationSink,
      sheetSize: pages.isEmpty
          // The empty-project stand-in is the real page — PORTRAIT A4 — so
          // the stage geometry holds when pages appear.
          ? ui.Size(metrics.pageWidth, metrics.pageHeight)
          : stack.size,
      paperScale: metrics.paperScale,
      viewport: null,
      viewportController: _view,
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
        page: viewerPage(pageIndex, pages.length),
        onTurnTo: book.turnTo,
      ),
      bottomBarHostToken: (pageIndex, pages.length),
      unframedFit: pages.isEmpty ? null : stack.pageRect(pageIndex),
      // The book's paper: where the view stops (F-201).
      viewLimit: pages.isEmpty ? null : stack.paper,
      book: pages.isEmpty ? null : book,
      drawingOn: _drawing && pages.isNotEmpty,
      strokeHold: _strokeHold,
      content: (context, viewport) => LayoutBuilder(
        builder: (context, box) =>
            _book(context, viewport, box.biggest),
      ),
    );
  }

  /// The pages the view shows, each drawn through the view moved to where
  /// it lies in the stack — and ONE ink layer over them all, its windows in
  /// the stack's own space, so the pen is heard on every page on screen.
  Widget _book(BuildContext context, CanvasViewport viewport, Size box) {
    final (source, pages) = _resolveSheet();
    final stack = _stackOf(pages);
    final ratio = EffectiveDevicePixelRatio.of(context);
    final shown = [
      for (final index in stack.pagesMeeting(
        canvasRectShown(viewport, box),
      ))
        (
          page: pages[index],
          at: _onDevicePixels(stack.pageRect(index).topLeft, viewport, ratio),
        ),
    ];
    final ink = _inkMount(shown);
    final awaited = _awaitingPrints ? widget.thumbnails : null;
    final pictures = ink != null
        ? _picturesOf(ink.pages, ink.project)
        : awaited != null
        ? _picturesOf(shown, _session.repository.requireProject())
        : null;
    return Stack(
      children: [
        for (var index = 0; index < shown.length; index += 1)
          Positioned.fill(
            child: ConteBookPage(
              key: ValueKey<String>(
                'conte-page-${shown[index].page.pageIndex}',
              ),
              page: shown[index].page,
              source: source,
              viewport: viewport.translated(
                dx: viewport.zoom * shown[index].at.dx,
                dy: viewport.zoom * shown[index].at.dy,
              ),
              session: _session,
              pictureFor: _pictureFor,
              onSelectCell: _selectCell,
              drawing: _drawing,
              strokeHold: _strokeHold,
              imageFor: widget.imageFor,
              imageRepaint: widget.imageRepaint,
              picturesLanded: widget.thumbnails?.landed,
              inkController: widget.inkController,
              pictures: pictures?[index] ?? const [],
              cels: widget.pictures,
              picturesOverInk: contePicturesOverInkIn(
                _session,
                shown[index].page,
              ),
            ),
          ),
        if (ink != null) _inkLayer(ink, viewport, pictures!),
        if (awaited != null) _waitFor(awaited),
      ],
    );
  }

  /// What stands the pictures down once [prints] owes none
  /// ([_awaitingPrints]).
  Positioned _waitFor(StoryboardThumbnails prints) => Positioned.fill(
    child: _PrintsCaughtUp(
      prints: prints,
      onCaughtUp: () => setState(() => _awaitingPrints = false),
    ),
  );

  /// The pictures the brush draws into on each of [pages], in their order
  /// and each in its page's own space — none without the cels' controller.
  /// Their cuts and cel keys are [project]'s, the project the pages are
  /// laid from: the next cut is drawn into on the track it will be made on.
  List<List<ContePicture>> _picturesOf(
    List<ConteShownPage> pages,
    Project project,
  ) {
    if (widget.pictures == null) {
      return [for (final _ in pages) const []];
    }
    final cels = _celsOf(project);
    return [
      for (final (:page, at: _) in pages) contePictures(page, cels, _strokeOf),
    ];
  }

  /// Where the pictures of a sheet laid from [project] find their cuts,
  /// cels and camera.
  ContePictureProject _celsOf(Project project) => (
    cutOf: (cutId) => cutPositionOf(project, cutId)?.cut,
    celKeyOf: (cut, layerId, frameId) =>
        brushFrameKeyIn(project, cut, layerId, frameId),
    cameraPoseOf: _session.camera.cameraPoseForCut,
    cameraFrameSize: _session.camera.cameraFrameSize,
    conteCelOf: _session.autoFrame.conteCelFor,
    refusalOf: _refusalFor,
  );

  /// Why a cell of [cutId] with no block takes no ink, picture and band
  /// alike — the canvas's notice for a press on a cell it may not fill
  /// (`EditorCanvasArea._drawRefusalFor`), naming what the cut lacks: its
  /// conte row itself, or a block on it (유저 2026-09-30, H51: 「콘티레이어
  /// 없으면 프레임이 없다고뜨는데 이런 메시지 제대로 표시. 콘티레이어가
  /// 없다고」). Null while its 「프레임 자동 생성」 is on and the stroke makes
  /// what is missing.
  String? _refusalFor(CutId cutId) {
    if (_session.autoFrame.autoCreates) {
      return null;
    }
    final strings = AppStrings.of(
      _session.languageSettings.value.programLanguage,
    );
    final cut = _session.cutById(cutId);
    return cut != null && storyboardLayerForCut(cut) == null
        ? strings.noticeNoConteLayer
        : strings.noticeNoFrameHere;
  }

  /// A piece of a stroke landing makes what it was drawn into, in the
  /// stroke's own undo step: the next cut's slot the cut (H44), a cell with
  /// no block the block — its picture and its band alike (유저 답
  /// conte-drawing-target-Q3 「그림 칸과 같이 (토글을 따른다)」) — and a
  /// block's first handwriting the block's id.
  void _makeWhatTheStrokeLandsIn(SheetWindow window) {
    final inkId = conteInkRowIdOf(window.key);
    if (window is! SheetPictureWindow && inkId == null) {
      return;
    }
    final autoFrame = _session.autoFrame;
    if (_session.cutById(window.key.cutId) == null) {
      autoFrame.addConteCut(window.key.cutId);
    }
    final cut = _session.cutById(window.key.cutId);
    if (cut == null) {
      return;
    }
    autoFrame.addConteCel(cut);
    if (inkId != null) {
      _session.storyboardCursor.writeConteBlockInk(cut.id, inkId);
    }
  }

  /// The name the pen writes a block not yet written on under
  /// (`StoryboardCursor.conteInkIdFor`).
  String _unwrittenInkIdOf(ContePlacedCell cell) => _session.storyboardCursor
      .conteInkIdFor(CutId(cell.cutId), cell.source.startFrame);

  /// The one ink layer over the pages on screen: their bands' windows and
  /// their pictures' windows, each moved to where its page lies.
  Positioned _inkLayer(
    _InkMount ink,
    CanvasViewport viewport,
    List<List<ContePicture>> pictures,
  ) {
    return Positioned.fill(
      // The tool-state boundary (R18 UI-3) went one step further down (H40
      // ②, 2026-09-24): the overlay no longer rebuilds for the brush at all —
      // its windows read it when a stroke starts.
      child: ConteInkLayer(
        key: const ValueKey<String>('conte-ink-layer'),
        controller: ink.controller,
        pages: ink.pages,
        brushToolState: ink.tool,
        historyManager: _session.historyManager,
        viewport: viewport,
        strokeActive: _strokeHold,
        cacheInvalidationSink: _cacheInvalidationSink,
        pictures: widget.pictures,
        pictureWindows: [
          for (var index = 0; index < ink.pages.length; index += 1)
            for (final picture in pictures[index])
              picture.window.shiftedBy(ink.pages[index].at),
        ],
        pictureInvalidationSink: _session.renderCaches.cacheInvalidationHub,
        unwrittenInkIdOf: _unwrittenInkIdOf,
        refusalOf: (cell) => _refusalFor(CutId(cell.cutId)),
        beforeLanding: _makeWhatTheStrokeLandsIn,
      ),
    );
  }
}

/// [project] as it stands once [cut] is made after the last cut of
/// [trackId] — where a new cut at a track's end goes, taking no room from
/// a cut behind it (there is none).
Project _withCutAtTheEnd(Project project, TrackId trackId, Cut cut) =>
    project.copyWith(
      tracks: [
        for (final track in project.tracks)
          if (track.id == trackId)
            track.copyWith(cuts: [...track.cuts, cut])
          else
            track,
      ],
    );

/// Where a page lies, moved onto whole device pixels at [viewport]: the
/// page's printers cut its view on the device grid again, and the ink
/// layer places its windows by this same offset — so the printed page
/// and the pen's windows over it land on the same pixels.
Offset _onDevicePixels(Offset at, CanvasViewport viewport, double ratio) {
  final perUnit = viewport.zoom * ratio;
  return Offset(
    (at.dx * perUnit).roundToDouble() / perUnit,
    (at.dy * perUnit).roundToDouble() / perUnit,
  );
}

/// Says when [prints] owes no picture any more: the store is asked once the
/// frame this mounts in has painted, and again once each frame a landing
/// sets off has — a page asks for its prints as it PAINTS, so a stroke no
/// paint has reached yet owes a print nobody has asked for, and a landing
/// empties what was asked until the repaint asks again
/// ([StoryboardThumbnails.pending]).
class _PrintsCaughtUp extends StatefulWidget {
  const _PrintsCaughtUp({required this.prints, required this.onCaughtUp});

  final StoryboardThumbnails prints;
  final VoidCallback onCaughtUp;

  @override
  State<_PrintsCaughtUp> createState() => _PrintsCaughtUpState();
}

class _PrintsCaughtUpState extends State<_PrintsCaughtUp> {
  // Heard once: the conte is made again for each project
  // (`EditorPanelTab.builtFor`), and its store is the project's — a wait
  // never meets another store's landings.
  late final Listenable _landings = widget.prints.landed;

  @override
  void initState() {
    super.initState();
    _landings.addListener(_askOnceItHasPainted);
    _askOnceItHasPainted();
  }

  @override
  void dispose() {
    _landings.removeListener(_askOnceItHasPainted);
    super.dispose();
  }

  void _askOnceItHasPainted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.prints.pending()) {
        widget.onCaughtUp();
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
