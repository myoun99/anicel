import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut_id.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/viewport_point.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../editor_session_manager.dart';
import '../storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailResolver, StoryboardThumbnailTier;
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/drag_value_label.dart';
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
/// the current brush/eraser; ink blocked, clicking a cell selects that
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
    this.inkEnabled = false,
    this.onInkEnabledChanged,
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

  /// The sheet-ink allow toggle: blocked ink protects the page from stray
  /// pen marks AND turns taps back into cell selection (the tap layer
  /// sits under the ink window). Off by default — the conte's first verb
  /// is reading and selecting, not annotating.
  final bool inkEnabled;
  final ValueChanged<bool>? onInkEnabledChanged;

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

  /// Raised while an ink stroke is in progress so the panel gesture layer
  /// holds navigation.
  final ValueNotifier<bool> _inkStrokeActive = ValueNotifier<bool>(false);

  // Memoized sheet source + pages: the source reads the WHOLE project, so
  // it is rebuilt only when the project object (or the camera aspect that
  // shapes the cells) actually changes — the immutable repository makes
  // identity the staleness check, the timesheet host's pattern.
  ConteSheetSource? _source;
  List<ContePageLayout>? _pages;
  Object? _sourceProject;
  double? _sourceCameraAspect;

  /// Ink strokes hold the prerender warmer exactly like canvas strokes.
  void _syncInkWarmHold() {
    _session.setBrushInputActive(_inkStrokeActive.value);
  }

  @override
  void initState() {
    super.initState();
    _inkStrokeActive.addListener(_syncInkWarmHold);
    // The sheet sets its type in the embedded faces (conte_fonts). The
    // workspace warms them at startup, so this await is normally a no-op;
    // on a cold open the one rebuild below reflows the text out of the
    // fallback face the first frames measured in.
    ensureConteFontsLoaded().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant ConteTabHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Blocking ink unmounts the window mid-stroke; clear the hold so the
    // gesture layer never stays pinned on a stroke that can't finish.
    if (!widget.inkEnabled && oldWidget.inkEnabled) {
      _inkStrokeActive.value = false;
    }
  }

  @override
  void dispose() {
    if (_inkStrokeActive.value) {
      _session.setBrushInputActive(false);
    }
    _inkStrokeActive.dispose();
    _action.dispose();
    super.dispose();
  }

  (ConteSheetSource, List<ContePageLayout>) _resolveSheet() {
    final Project project = _session.repository.requireProject();
    final aspect = _session.cameraFrameAspect;
    if (_source == null ||
        !identical(project, _sourceProject) ||
        aspect != _sourceCameraAspect) {
      _sourceProject = project;
      _sourceCameraAspect = aspect;
      _source = buildConteSheetSource(project);
      _pages = layoutConteSheet(
        _source!,
        metrics: ConteSheetMetrics(cameraAspect: aspect),
      );
    }
    return (_source!, _pages!);
  }

  /// A cell press: the cut, its storyboard row and the frame — the
  /// design's "칸 클릭 = selectCut + selectLayer + selectFrameIndex".
  void _selectCell(ContePlacedCell cell) {
    final cutId = CutId(cell.cutId);
    if (_session.activeCutOrNull?.id != cutId) {
      _session.selectCut(cutId);
    }
    for (final layer in _session.layers) {
      if (layer.kind == LayerKind.storyboard) {
        _session.selectLayer(layer.id);
        break;
      }
    }
    _session.selectFrameIndex(cell.source.startFrame);
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
    _session.setStoryboardCellAction(
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

  /// The conte's own commands, at the head of the panel's pill (R2 #13 —
  /// the status strip they lived in is gone with the rest of the frame).
  List<Widget> _panelActions() {
    return [
      if (widget.onInkEnabledChanged != null && widget.inkController != null)
        AppIconButton(
          keyValue: 'conte-ink-toggle-button',
          tooltip: widget.inkEnabled ? 'Block Sheet Ink' : 'Allow Sheet Ink',
          icon: Icon(widget.inkEnabled ? Icons.draw : Icons.edit_off),
          isSelected: widget.inkEnabled,
          size: AppIconButtonSize.strip,
          onPressed: () => widget.onInkEnabledChanged!(!widget.inkEnabled),
        ),
    ];
  }

  /// The page cluster, on the panel's LEFT edge (유저 확정 ⑥ 2026-08-13) —
  /// the timesheet's ◀ n/N ▶ grammar stood upright, drag/type on the
  /// readout included. Empty below two pages: nothing to turn.
  List<Widget> _pageStrip(int pageIndex, int pageCount) {
    if (pageCount <= 1) {
      return const <Widget>[];
    }
    return [
      AppIconButton(
        keyValue: 'conte-previous-page-button',
        tooltip: AppText.strings.cnPreviousPage,
        icon: const Icon(Icons.keyboard_arrow_up),
        size: AppIconButtonSize.strip,
        onPressed: pageIndex > 0
            ? () => _turnToPage(pageIndex - 1, pageCount)
            : null,
      ),
      DragValueLabel(
        keyValue: 'conte-page-readout',
        inputKeyValue: 'conte-page-input',
        text: '${pageIndex + 1} / $pageCount',
        tooltip: AppText.strings.sheetPageDrag,
        width: 30,
        textStyle: const TextStyle(fontSize: 9),
        unitsPerPixel: 1 / 8,
        onDragDelta: (units) =>
            _turnToPage(pageIndex + units.round(), pageCount),
        onEditSubmit: (text) {
          final parsed = int.tryParse(text.split('/').first.trim());
          if (parsed != null) {
            _turnToPage(parsed - 1, pageCount);
          }
        },
      ),
      AppIconButton(
        keyValue: 'conte-next-page-button',
        tooltip: AppText.strings.cnNextPage,
        icon: const Icon(Icons.keyboard_arrow_down),
        size: AppIconButtonSize.strip,
        onPressed: pageIndex < pageCount - 1
            ? () => _turnToPage(pageIndex + 1, pageCount)
            : null,
      ),
    ];
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
    final brushToolState = widget.brushToolState;
    final metrics = page?.metrics;
    if (inkController != null && metrics != null) {
      inkController.syncGeometry(metrics);
    }
    // The ink view unmounts with the last page — nothing is left to
    // finish a stroke, so the nav/warm hold must not stay pinned.
    if (page == null && _inkStrokeActive.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inkStrokeActive.value) {
          _inkStrokeActive.value = false;
        }
      });
    }

    final panel = BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
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
      // The paper never rotates (the timesheet's rule).
      allowViewRotation: false,
      bottomBarLeading: _panelActions(),
      pageStrip: _pageStrip(pageIndex, pageCount),
      bottomBarHostToken: (pageIndex, pageCount, widget.inkEnabled),
      fitFocusRect: metrics == null
          ? null
          : Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
      contentStrokeActive: inkController == null || !widget.inkEnabled
          ? null
          : _inkStrokeActive,
      contentOverride: (context, viewport) => Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          if (page != null)
            Positioned.fill(
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
                valueListenable: _inkStrokeActive,
                builder: (context, stroking, child) => StaticRaster(
                  debugLabel: 'conte-page',
                  enabled: !stroking,
                  child: child!,
                ),
                child: CustomPaint(
                  key: const ValueKey<String>('conte-page'),
                  painter: ContePagePainter(
                    page: page,
                    source: source,
                    selectedCell: _selected,
                    pictureFor: _pictureFor,
                    viewport: viewport,
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
                    liveInkKeys: !widget.inkEnabled || inkController == null
                        ? const {}
                        : {
                            for (final window in conteInkWindows(page))
                              window.key,
                          },
                    repaint: inkController == null
                        ? widget.thumbnailRepaint
                        : Listenable.merge([
                            if (widget.thumbnailRepaint != null)
                              widget.thumbnailRepaint!,
                            inkController,
                          ]),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          // Under the ink window: reachable exactly when ink is blocked
          // (the toggle doubles as the edit-mode switch, the timesheet's
          // header-edit rule).
          if (page != null)
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey<String>('conte-cell-tap-layer'),
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  final canvasPoint = viewport.viewportToCanvas(
                    ViewportPoint(
                      x: details.localPosition.dx,
                      y: details.localPosition.dy,
                    ),
                  );
                  final point = Offset(canvasPoint.x, canvasPoint.y);
                  for (final cell in page.cells) {
                    if (cell.pictureRect.contains(point)) {
                      _selectCell(cell);
                      return;
                    }
                  }
                },
              ),
            ),
          if (page != null &&
              inkController != null &&
              brushToolState != null &&
              widget.inkEnabled)
            Positioned.fill(
              // The tool-state boundary (R18 UI-3): only this overlay
              // follows the brush/eraser.
              child: ValueListenableBuilder<BrushToolState>(
                valueListenable: brushToolState,
                builder: (context, toolState, _) => ConteInkLayer(
                  key: const ValueKey<String>('conte-ink-layer'),
                  controller: inkController,
                  page: page,
                  brushToolState: toolState,
                  historyManager: _session.historyManager,
                  viewport: viewport,
                  strokeActive: _inkStrokeActive,
                  cacheInvalidationSink: _cacheInvalidationSink,
                ),
              ),
            ),
        ],
      ),
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
