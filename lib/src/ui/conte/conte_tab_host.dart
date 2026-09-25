import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/identity_memo.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import '../brush/brush_canvas_panel.dart' show BrushCanvasPanel;
import '../brush/sheet_canvas_panel.dart';
import '../effective_device_pixel_ratio.dart';
import '../input/control_press_claim.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../editor_session_manager.dart';
import '../storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailResolver, StoryboardThumbnailTier;
import '../text/app_strings.dart';
import '../timeline/timeline_drag_preview.dart'
    show CutTrimDragPreview, TimelineDragPreview;
import '../widgets/page_turn_strip.dart';
import '../widgets/static_raster.dart';
import 'conte_fonts.dart';
import 'conte_ink.dart';
import 'conte_page_painter.dart';
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
    required this.thumbnailFor,
    this.thumbnailRepaint,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.inkController,
    this.brushToolState,
    this.brushAllowed = false,
    this.onBrushAllowedChanged,
  });

  final EditorSessionManager session;

  /// The panels' picture resolver — the SAME store the storyboard strip
  /// draws from, so a cell and its strip panel are one render.
  final StoryboardThumbnailResolver? thumbnailFor;

  /// The picture store's change signal: a landed thumbnail render must
  /// REPAINT the page (the painter's compared fields don't change when an
  /// async picture arrives). Usually the thumbnail store itself.
  final Listenable? thumbnailRepaint;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Conte ink store, owned above the tab group so annotations survive
  /// tab switches. Null renders the sheet read-only.
  final ConteInkController? inkController;

  /// The editor's current brush/eraser LISTENABLE (R18 UI-3): only the
  /// ink overlay subscribes — tool switches never rebuild the document.
  final ValueListenable<BrushToolState>? brushToolState;

  /// The sheet's brush switch (브러시 허용): off protects the page from
  /// stray pen marks AND turns taps back into cell selection (the tap layer
  /// sits under the ink window). Off by default — the conte's first verb
  /// is reading and selecting, not annotating.
  final bool brushAllowed;
  final ValueChanged<bool>? onBrushAllowedChanged;

  /// The shortest this tab is laid out at.
  ///
  /// The conte has no fixed rows to protect — it is a PAGE that scales into
  /// whatever it is given, and a height sweep finds no size at which the
  /// page itself overflows. So unlike the timeline and the storyboard its
  /// floor is not "chrome plus two rows"; it is chrome alone.
  ///
  /// The chrome is one row and it is conditional: the ACTION field that
  /// mounts under the page when a cell is selected. It is a plain (not
  /// flexible) child of the column, so it takes its height whether or not
  /// there is room — a 32px dense field inside 4+8 of padding, measured.
  /// Below that the page gets zero and the column overflows.
  static const double _actionEditorExtent = 32 + 4 + 8;
  static const double minPanelHeight = _actionEditorExtent;

  @override
  State<ConteTabHost> createState() => _ConteTabHostState();
}

class _ConteTabHostState extends State<ConteTabHost> {
  EditorSessionManager get _session => widget.session;

  /// Commit sink required by the panel API; conte ink invalidations stay
  /// local (synthetic ink keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  int _page = 0;
  final TextEditingController _action = TextEditingController();

  /// The cell under edit, as `(cutId, cellIndex)`.
  (String, int)? _selected;

  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => _session.setBrushInputActive(live),
  );

  // Memoized sheet source + pages: the source reads the WHOLE project, so
  // it is rebuilt only when the project object (or the camera aspect that
  // shapes the cells) actually changes — the immutable repository makes
  // identity the staleness check, the timesheet host's pattern.
  final _sheet = IdentityMemo<(ConteSheetSource, List<ContePageLayout>)>();

  @override
  void initState() {
    super.initState();
    // The sheet sets its type in the embedded faces (conte_fonts). The
    // workspace warms them at startup, so this await is normally a no-op;
    // on a cold open the one rebuild below reflows the text out of the
    // fallback face the first frames measured in.
    unawaited(
      ensureConteFontsLoaded().then((_) {
        if (mounted) {
          setState(() {});
        }
      }),
    );
  }

  @override
  void dispose() {
    _strokeHold.dispose();
    _action.dispose();
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
          layoutConteSheet(
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
    setState(() {
      _selected = (cell.cutId, cell.cellIndex);
      _action.text = cell.source.action;
    });
  }

  /// ACTION text lands on the exposure that opens the cell — the memo is
  /// block-owned, so it travels with every move and copy for free.
  void _commitAction() {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    _session.storyboardCursor.setStoryboardCellAction(
      cutId: CutId(selected.$1),
      cellIndex: selected.$2,
      action: _action.text,
    );
  }

  ui.Image? _pictureFor(String cutId, int frame) {
    final resolver = widget.thumbnailFor;
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
  ({
    ConteInkController controller,
    ValueListenable<BrushToolState> tool,
    ContePageLayout page,
  })?
  _inkMount(ContePageLayout? page) {
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
    final pageIndex = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final page = pageCount == 0 ? null : pages[pageIndex];
    final inkController = widget.inkController;
    final onBrushAllowedChanged = widget.onBrushAllowedChanged;
    final metrics = page?.metrics;
    if (inkController != null && metrics != null) {
      inkController.syncGeometry(metrics);
    }
    // The ink windows go with the last page too — the panel lets go of a
    // stroke left on them, as it does when the brush goes off.
    final ink = _inkMount(page);

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
        page: (
          index: pageIndex,
          count: pageCount,
          readout: '${pageIndex + 1} / $pageCount',
        ),
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
            if (ink != null)
              _inkLayer(ink.tool, ink.controller, ink.page, viewport),
          ],
        );
      },
    );

    return ColoredBox(
      key: const ValueKey<String>('conte-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: panel),
          if (_selected != null) _actionEditor(context),
        ],
      ),
    );
  }

  Positioned _inkLayer(
    ValueListenable<BrushToolState> brushToolState,
    ConteInkController inkController,
    ContePageLayout page,
    CanvasViewport viewport,
  ) {
    return Positioned.fill(
      // The tool-state boundary (R18 UI-3) went one step further down (H40
      // ②, 2026-09-24): the overlay no longer rebuilds for the brush at all —
      // its windows read it when a stroke starts.
      child: ConteInkLayer(
        key: const ValueKey<String>('conte-ink-layer'),
        controller: inkController,
        page: page,
        brushToolState: brushToolState,
        historyManager: _session.historyManager,
        viewport: viewport,
        strokeActive: _strokeHold,
        cacheInvalidationSink: _cacheInvalidationSink,
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
    return Positioned.fill(
      // The sheet page is the timesheet's answer applied to its
      // sibling. A `RepaintBoundary` here stopped the page being
      // re-RECORDED, which was never the cost — the raster thread
      // still replayed the whole display list every frame the app
      // produced, for any reason, including the pen moving over
      // the canvas in another panel.
      //
      // `StaticRaster` is itself a repaint boundary, so the
      // isolation this had is kept and the bake is added on top.
      // The surrounding `Stack` already clips `Clip.hardEdge`, so
      // the bake's own clip is a no-op and the pixels do not move.
      //
      // ⚠️ It stands down while the pen is down: capturing costs a
      // full paint PLUS a full-page copy, and a stroke dirties the
      // page on every sample.
      child: ValueListenableBuilder<bool>(
        valueListenable: _strokeHold,
        builder: (context, stroking, child) =>
            ValueListenableBuilder<TimelineDragPreview?>(
              valueListenable: _session.dragPreview,
              // F-88: a cut-length drag re-prints the page's numbers on
              // every step, so the bake stands down for it exactly as it
              // does for a pen — capturing costs a full page copy a step.
              builder: (context, preview, baked) => StaticRaster(
                debugLabel: 'conte-page',
                enabled: !stroking && preview is! CutTrimDragPreview,
                child: baked!,
              ),
              child: child,
            ),
        child: CustomPaint(
          key: const ValueKey<String>('conte-page'),
          painter: ContePagePainter(
            page: page,
            source: source,
            selectedCell: _selected,
            pictureFor: _pictureFor,
            viewport: viewport,
            effectiveRatio: EffectiveDevicePixelRatio.of(context),
            // Saved sheet ink shows whatever the ink mode says
            // (R5); a live input window's key stands down so
            // translucent ink never composites twice.
            inkImageFor: inkController == null
                ? null
                : (key) => inkController.displayImageFor(
                    key.layerId == conteInkRowLayerId
                        ? ConteInkPlane.row
                        : ConteInkPlane.page,
                    key,
                  ),
            liveInkKeys: _inkMount(page) == null
                ? const {}
                : {for (final window in conteInkWindows(page)) window.key},
            // F-88: the numbers this page prints follow a cut-length drag,
            // so the channel is both a VALUE the paint reads and a reason
            // to repaint.
            dragPreview: _session.dragPreview,
            repaint: Listenable.merge([
              if (widget.thumbnailRepaint != null) widget.thumbnailRepaint!,
              ?inkController,
              _session.dragPreview,
            ]),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _actionEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TextField(
        key: const ValueKey<String>('conte-action-field'),
        controller: _action,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          labelText: AppText.strings.cnActionColumn,
        ),
        onSubmitted: (_) => _commitAction(),
        onTapOutside: (_) => _commitAction(),
      ),
    );
  }
}
