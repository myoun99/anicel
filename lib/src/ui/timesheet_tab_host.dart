import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/timesheet_document.dart';
import '../models/timesheet_info.dart';
import 'brush/brush_canvas_panel.dart';
import 'text/app_strings.dart';
import 'brush/brush_edit_cache_invalidation_sink.dart';
import 'brush/brush_tool_state.dart';
import 'dialogs/timesheet_info_dialog.dart';
import 'editor_session_manager.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/drag_value_label.dart';
import 'timesheet/timesheet_document_painter.dart';
import 'timesheet/timesheet_header_edit_layer.dart';
import 'widgets/static_raster.dart';
import 'timesheet/timesheet_notation.dart';
import 'timesheet/timesheet_ink_controller.dart';
import 'timesheet/timesheet_ink_layer.dart';

/// The Timesheet tab's content: the active cut rendered as a paper
/// timesheet DOCUMENT (not an editing grid) inside the canvas panel shell,
/// so navigation feels exactly like the drawing canvas — wheel zoom,
/// middle-drag/two-finger pan, panbars, Fit. With an [inkController] and
/// [brushToolState] the sheet takes freehand ink memos with the current
/// brush/eraser (S2): frame-anchored strip ink over the column grid,
/// paper-anchored page ink everywhere else.
class TimesheetTabHost extends StatefulWidget {
  const TimesheetTabHost({
    super.key,
    required this.session,
    required this.continuous,
    required this.onContinuousChanged,
    this.page = 0,
    this.onPageChanged,
    this.viewport,
    this.onViewportChanged,
    this.inkController,
    this.brushToolState,
    this.inkEnabled = true,
    this.onInkEnabledChanged,
  });

  final EditorSessionManager session;

  /// Page-split (false, paper default) ⟷ continuous view.
  final bool continuous;
  final ValueChanged<bool> onContinuousChanged;

  /// R26 #41: the sheet of paper on screen in page view — one at a time,
  /// turned by the bottom bar's ◀ / n/N / ▶ cluster (and by playback,
  /// which turns the page as it crosses into it). Owned above the tab
  /// group with the viewport so a tab switch doesn't lose the reader's
  /// place. Ignored in continuous view (one strip).
  final int page;
  final ValueChanged<int>? onPageChanged;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Sheet ink stores, owned above the tab group so annotations survive
  /// tab switches. Null renders the sheet read-only.
  final TimesheetInkController? inkController;

  /// The editor's current brush/eraser LISTENABLE; required for ink
  /// input. A listenable, not a value (R18 UI-3): the sheet layout never
  /// depends on the tool state, so only the ink overlay subscribes —
  /// tool switches and setting tweaks must not rebuild the whole
  /// (keep-alive) document.
  final ValueListenable<BrushToolState>? brushToolState;

  /// The sheet-ink allow toggle (owned above the tab group): blocked ink
  /// protects the sheet from stray pen marks AND turns taps into
  /// header/memo text editing (the edit layer sits under the ink windows).
  final bool inkEnabled;
  final ValueChanged<bool>? onInkEnabledChanged;

  @override
  State<TimesheetTabHost> createState() => _TimesheetTabHostState();
}

class _TimesheetTabHostState extends State<TimesheetTabHost> {
  /// Commit sink required by the panel API; sheet ink invalidations stay
  /// local (synthetic ink keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  // Memoized sheet document + layouts: building them is the expensive part
  // of this host's rebuild, and most session notifies (fx toggles, waveform
  // loads, selections, committed seeks) change none of their inputs — the
  // model objects are immutable, so identity is the staleness check.
  TimesheetDocument? _document;
  TimesheetDocumentLayout? _layout;
  TimesheetDocumentLayout? _pagedLayout;
  Object? _documentCut;
  Object? _documentInfo;
  Object? _documentInstructionSet;
  Object? _documentTrackSe;
  Object? _documentTransition;
  int? _documentCutStartFrame;
  String? _documentProjectName;
  int? _documentFps;
  bool? _documentDataSheet;
  bool? _layoutContinuous;
  int? _layoutPage;

  /// DATA-sheet mode (UI-R24 #1): the sheet prints the EXPORT-SOURCE data
  /// (ghost chains verbatim, the labels XDTS/TDTS write) instead of the
  /// notation shorthand — for auditing exactly what the file will carry.
  /// View state, session-only.
  bool _dataSheet = false;

  /// Null in the GAP state (no active cut, UI-R9 #3): the host renders the
  /// bare sheet background instead of a document.
  TimesheetDocumentLayout? _resolveLayouts(EditorSessionManager session) {
    final cut = session.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    final info = session.timesheetInfo;
    final projectName = session.repository.requireProject().name;
    final instructionSet = session.cameraInstructionSet;
    // Track-owned SE rows join the memo key: their edits change the track
    // list identity, not the cut's.
    final trackSeLayers = session.activeTrack.seLayers;
    // Same story for the transition row: track-owned, so an edit there
    // changes the track's identity rather than the cut's.
    final transitionLayer = session.activeTrack.transitionLayer;
    final cutStartFrame = session.activeCutGlobalStartFrame;
    if (_document == null ||
        !identical(_documentCut, cut) ||
        !identical(_documentInfo, info) ||
        !identical(_documentInstructionSet, instructionSet) ||
        !identical(_documentTrackSe, trackSeLayers) ||
        !identical(_documentTransition, transitionLayer) ||
        _documentCutStartFrame != cutStartFrame ||
        _documentProjectName != projectName ||
        _documentFps != session.projectFps ||
        _documentDataSheet != _dataSheet) {
      _documentCut = cut;
      _documentInfo = info;
      _documentInstructionSet = instructionSet;
      _documentTrackSe = trackSeLayers;
      _documentTransition = transitionLayer;
      _documentCutStartFrame = cutStartFrame;
      _documentProjectName = projectName;
      _documentFps = session.projectFps;
      _documentDataSheet = _dataSheet;
      _document = TimesheetDocument.fromCut(
        cut: cut,
        projectName: projectName,
        fps: session.projectFps,
        info: info,
        instructionDefById: instructionSet.defById,
        trackSeLayers: trackSeLayers,
        cutStartFrame: cutStartFrame,
        transitionSpans: session.activeTrackTransitionSpans,
        // D31: the transition row prints when its own timesheet flag is
        // on — through the SESSION'S cut-view projection (one walk for
        // the sheet and the cut timeline's row; spans re-keyed to this
        // cut's local axis), MINUS the D26-refused crossing fades (the
        // sheet prints only what applies — the row keeps them for the
        // warning to sit on). Off = the slot stays blank form space,
        // the camera column's own precedent.
        transitionLayer: transitionLayer.onTimesheet
            ? session.trackTransitionSheetLayer
            : null,
        dataSheet: _dataSheet,
      );
      _layout = null;
      _pagedLayout = null;
    }
    if (_layout == null ||
        _layoutContinuous != widget.continuous ||
        _layoutPage != widget.page) {
      _layoutContinuous = widget.continuous;
      _layoutPage = widget.page;
      _layout = TimesheetDocumentLayout(
        document: _document!,
        continuous: widget.continuous,
        // R26 #41: page view is ONE sheet of paper at a time.
        singlePage: widget.continuous ? null : widget.page,
      );
      // The ink geometry reference stays the FULL paged form: surfaces are
      // sized per page/band, so turning pages must not resize them.
      _pagedLayout = TimesheetDocumentLayout(document: _document!);
    }
    return _layout!;
  }

  /// The page actually on screen: the stored page, clamped to the document
  /// (a shorter cut must not strand the reader past the last sheet).
  int _visiblePage(TimesheetDocumentLayout layout) =>
      layout.resolvedSinglePage ?? 0;

  void _turnToPage(int page) {
    final onPageChanged = widget.onPageChanged;
    final document = _document;
    if (onPageChanged == null || document == null) {
      return;
    }
    final next = page.clamp(0, document.pages.length - 1);
    if (next != widget.page) {
      onPageChanged(next);
    }
  }

  /// Raised while an ink stroke is in progress so the panel gesture layer
  /// holds navigation.
  final ValueNotifier<bool> _inkStrokeActive = ValueNotifier<bool>(false);

  /// Ink strokes hold the prerender warmer exactly like canvas strokes
  /// (R13-3) — the sheet's drawing plane commits through the same funnel.
  void _syncInkWarmHold() {
    widget.session.setBrushInputActive(_inkStrokeActive.value);
  }

  @override
  void initState() {
    super.initState();
    _inkStrokeActive.addListener(_syncInkWarmHold);
  }

  @override
  void didUpdateWidget(covariant TimesheetTabHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Blocking ink unmounts the windows mid-stroke; clear the hold so the
    // gesture layer never stays pinned on a stroke that can't finish.
    if (!widget.inkEnabled && oldWidget.inkEnabled) {
      _inkStrokeActive.value = false;
    }
  }

  @override
  void dispose() {
    // Never leak an open warm hold through a mid-stroke teardown.
    if (_inkStrokeActive.value) {
      widget.session.setBrushInputActive(false);
    }
    _inkStrokeActive.dispose();
    super.dispose();
  }

  void _commitHeaderField(TimesheetHeaderField field, String text) {
    final info = widget.session.timesheetInfo;
    final next = switch (field) {
      TimesheetHeaderField.title => info.copyWith(title: text),
      TimesheetHeaderField.episode => info.copyWith(episode: text),
      TimesheetHeaderField.scene => info.copyWith(scene: text),
      TimesheetHeaderField.name => info.copyWith(artist: text),
      _ => info,
    };
    widget.session.updateTimesheetInfo(next);
  }

  Future<void> _editSheetInfo() async {
    final session = widget.session;
    final nextInfo = await showDialog(
      context: context,
      builder: (context) =>
          TimesheetInfoDialog(initialInfo: session.timesheetInfo),
    );
    if (!mounted || nextInfo == null) {
      return;
    }
    session.updateTimesheetInfo(nextInfo);
  }

  /// The sheet commands living IN the panel's status strip (UI-R10 #18 —
  /// the old toolbar row above the sheet retired): ink toggle and sheet
  /// info, right-aligned, always visible (the strip's title text
  /// ellipsizes first when the panel narrows).
  ///
  /// The sheet-MODE commands (notation/data, page/continuous) moved out to
  /// the bottom bar with the page navigation (R26 #41), and what stayed
  /// wears the app's standard icon button (R26 #42) instead of the
  /// hand-rolled InkWell this strip used to grow its own.
  /// The sheet's own commands, at the head of the panel's pill.
  ///
  /// They lived in a status strip across the top of the panel until R2 #13
  /// took the strip (and the frame, and the bottom bar) away. A panel has
  /// one pill now and everything it offers is in it.
  List<Widget> _panelActions() {
    return [
      if (widget.onInkEnabledChanged != null)
        AppIconButton(
          keyValue: 'timesheet-ink-toggle-button',
          tooltip: widget.inkEnabled ? 'Block Sheet Ink' : 'Allow Sheet Ink',
          icon: Icon(widget.inkEnabled ? Icons.draw : Icons.edit_off),
          isSelected: widget.inkEnabled,
          size: AppIconButtonSize.strip,
          onPressed: () => widget.onInkEnabledChanged!(!widget.inkEnabled),
        ),
      AppIconButton(
        keyValue: 'timesheet-info-button',
        tooltip: AppText.strings.sheetInfoTitle,
        icon: const Icon(Icons.edit_note),
        size: AppIconButtonSize.strip,
        onPressed: _editSheetInfo,
      ),
    ];
  }

  /// R26 #41 — the sheet's two MODE toggles, at the far left of the pill:
  ///
  ///   [notation/data] [page/continuous] │ ═══ the view controls ═══
  ///
  /// ⛔The page cluster used to follow them here. It moved to the panel's
  /// left edge (유저 확정 ⑥ 2026-08-13, [_pageStrip]) because three controls
  /// at 44px of budget each were most of what the pill had to spend, and a
  /// rail-width sheet was shedding the lot — turning pages and reading the
  /// page competing for the same row.
  List<Widget> _bottomBarLeading(TimesheetDocumentLayout? layout) {
    return [
      // Notation ↔ DATA sheet (UI-R24 #1): data prints the export-source
      // labels (ghost chains verbatim, exactly what XDTS/TDTS write) so
      // the output data can be audited on the sheet itself.
      AppIconButton(
        keyValue: 'timesheet-data-mode-toggle-button',
        tooltip: _dataSheet
            ? 'Notation Sheet (repeat/hold words)'
            : 'Data Sheet (as exported)',
        icon: const Icon(Icons.receipt_long_outlined),
        isSelected: _dataSheet,
        onPressed: () => setState(() => _dataSheet = !_dataSheet),
      ),
      AppIconButton(
        keyValue: 'timesheet-page-mode-toggle-button',
        tooltip: widget.continuous ? 'Page View' : 'Continuous View',
        icon: Icon(
          widget.continuous
              ? Icons.auto_stories_outlined
              : Icons.view_agenda_outlined,
        ),
        isSelected: !widget.continuous,
        onPressed: () => widget.onContinuousChanged(!widget.continuous),
      ),
    ];
  }

  /// Turning the sheet's pages, on the panel's LEFT edge (유저 확정 ⑥
  /// 2026-08-13) rather than in the pill.
  ///
  /// ⚠️It stays MOUNTED-but-disabled in continuous view, as it always has:
  /// a cluster that vanished with the view toggle read as a layout jump.
  /// What it will not do is stand there for a sheet that HAS no second
  /// page — that is not a mode, it is nothing to turn.
  List<Widget> _pageStrip(TimesheetDocumentLayout? layout) {
    final pageCount = layout?.document.pages.length ?? 0;
    if (pageCount <= 1) {
      return const <Widget>[];
    }
    final page = layout == null ? 0 : _visiblePage(layout);
    final paged = !widget.continuous;
    return [
      AppIconButton(
        keyValue: 'timesheet-page-prev-button',
        tooltip: AppText.strings.sheetPreviousPage,
        icon: const Icon(Icons.keyboard_arrow_up),
        size: AppIconButtonSize.strip,
        onPressed: paged && page > 0 ? () => _turnToPage(page - 1) : null,
      ),
      DragValueLabel(
        keyValue: 'timesheet-page-label',
        inputKeyValue: 'timesheet-page-input',
        text: layout?.pageLabel(page) ?? '-',
        tooltip: AppText.strings.sheetPageDrag,
        width: 30,
        textStyle: const TextStyle(fontSize: 9),
        // One page per 8px of drag: a 1px-per-page rate flipped whole
        // documents on a twitch.
        unitsPerPixel: 1 / 8,
        onDragDelta: paged
            ? (units) => _turnToPage(page + units.round())
            : _noDrag,
        onEditSubmit: (text) {
          if (!paged) {
            return;
          }
          // '3' and '3/7' both mean page three (the readout's own
          // spelling round-trips).
          final parsed = int.tryParse(text.split('/').first.trim());
          if (parsed != null) {
            _turnToPage(parsed - 1);
          }
        },
      ),
      AppIconButton(
        keyValue: 'timesheet-page-next-button',
        tooltip: AppText.strings.sheetNextPage,
        icon: const Icon(Icons.keyboard_arrow_down),
        size: AppIconButtonSize.strip,
        onPressed: paged && page < pageCount - 1
            ? () => _turnToPage(page + 1)
            : null,
      ),
    ];
  }

  static void _noDrag(double units) {}

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colorScheme = Theme.of(context).colorScheme;
    final inkController = widget.inkController;
    final brushToolState = widget.brushToolState;

    // Session changes (incl. undo/redo of sheet strokes) rebuild the sheet
    // data and hand the windows fresh ink session surfaces; ink commits
    // notify through the controller. The playhead deliberately does NOT
    // live here (R13-2): cursor moves, committed seeks and playback ticks
    // repaint the thin playhead overlay only — repainting the whole B4
    // sheet per playhead move was the timesheet's share of the frame-flip
    // hitch. Page-granular playhead facts (auto page turn, Fit target,
    // the frame label) rebuild through the token-gated scope below.
    final listenable = Listenable.merge([session, ?inkController]);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final strings = AppStrings.of(
          session.languageSettings.value.programLanguage,
        );
        final layout = _resolveLayouts(session);
        if (layout == null) {
          // The GAP state (UI-R9 #3 + UI-R10 #17): no cut selected, but
          // the PANEL FRAME stays up like the canvas — only the content
          // empties out.
          return BrushCanvasPanel(
            coordinator: null,
            availableFrameKeys: const [],
            cacheInvalidationSink: _cacheInvalidationSink,
            canvasSize: const CanvasSize(width: 780, height: 1080),
            viewport: widget.viewport,
            onViewportChanged: widget.onViewportChanged,
            allowViewRotation: false,
            bottomBarLeading: [
              ..._panelActions(),
              ..._bottomBarLeading(null),
            ],
            pageStrip: _pageStrip(null),
            bottomBarHostToken: (
              widget.continuous,
              _dataSheet,
              widget.inkEnabled,
              0,
              0,
            ),
            contentOverride: (context, viewport) => Container(
              key: const ValueKey<String>('timesheet-empty-no-cut'),
              color: colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Text(
                strings.noCutSelected,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final document = _document!;
        final pagedLayout = _pagedLayout!;
        inkController?.syncGeometry(pagedLayout);
        final documentSize = layout.documentSize;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TimesheetPlayheadScope(
                session: session,
                continuous: widget.continuous,
                pageFrameCount: document.pageFrameCount,
                pageCount: document.pages.length,
                builder: (context, playheadFrame, playbackGlobalFrame) {
                  final playheadPage =
                      (playheadFrame ~/ document.pageFrameCount).clamp(
                        0,
                        document.pages.length - 1,
                      );
                  final visiblePage = _visiblePage(layout);
                  // Playback follows the sheet (③): page view TURNS THE
                  // PAGE to the playhead's (R26 #41 — the paper swaps
                  // under a viewport that never moves, where the pre-#41
                  // sheet scrolled the stack); continuous view scrolls the
                  // playhead row into view without touching the zoom. Idle
                  // keeps both the viewport and the page user-owned.
                  if (playbackGlobalFrame != null &&
                      !widget.continuous &&
                      playheadPage != visiblePage) {
                    // Out of build: the turn writes the page notifier that
                    // this very subtree reads.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _turnToPage(playheadPage);
                      }
                    });
                  }
                  final autoFrame =
                      playbackGlobalFrame == null || !widget.continuous
                      ? null
                      : CanvasAutoFrameRequest(
                          token: (
                            'timesheet-reveal',
                            session.requireActiveCut.id,
                            playheadFrame,
                          ),
                          rect: Rect.fromLTWH(
                            layout.paperLeft,
                            layout.frameRowTop(playheadFrame),
                            layout.paperWidth,
                            TimesheetDocumentLayout.rowHeight,
                          ),
                          panOnly: true,
                        );
                  return BrushCanvasPanel(
                    coordinator: null,
                    availableFrameKeys: const [],
                    cacheInvalidationSink: _cacheInvalidationSink,
                    canvasSize: CanvasSize(
                      width: documentSize.width.ceil(),
                      height: documentSize.height.ceil(),
                    ),
                    viewport: widget.viewport,
                    onViewportChanged: widget.onViewportChanged,
                    bottomBarLeading: [
                      ..._panelActions(),
                      ..._bottomBarLeading(layout),
                    ],
                    pageStrip: _pageStrip(layout),
                    bottomBarHostToken: (
                      widget.continuous,
                      _dataSheet,
                      widget.inkEnabled,
                      visiblePage,
                      document.pages.length,
                    ),
                    // Fit frames the page on screen.
                    fitFocusRect: layout.pageRect(visiblePage),
                    autoFrame: autoFrame,
                    // The sheet's ink/header overlays speak zoom/pan only —
                    // the paper never rotates (P8 is the drawing canvas's).
                    allowViewRotation: false,
                    contentStrokeActive:
                        inkController == null || !widget.inkEnabled
                        ? null
                        : _inkStrokeActive,
                    contentOverride: (context, viewport) => Stack(
                      children: [
                        // The sheet paints in TWO strata (UI-R10 #9, the
                        // PSD layering live): the printed FORM (paper,
                        // grid, labels) below, the CONTENT (cell texts,
                        // values) above — timeline drags re-print just
                        // the content stratum through the drag channel.
                        //
                        // Each stratum is baked rather than merely
                        // boundaried. This panel measured 13.1 ms/frame
                        // of raster — 47% of the whole app's — while
                        // sitting perfectly still, because a boundary
                        // stops the UI thread re-RECORDING and does
                        // nothing about the GPU re-EXECUTING. The form
                        // alone is ~334 lines and ~111 text paragraphs
                        // of B4 sheet at every frame the app happens to
                        // produce.
                        //
                        // Two wrappers and not one, deliberately: the
                        // split above is what keeps a content-only
                        // change off the form, and merging them would
                        // hand the drag channel a re-record of the
                        // whole grid.
                        Positioned.fill(
                          child: StaticRaster(
                            debugLabel: 'timesheet-form',
                            child: CustomPaint(
                              key: const ValueKey<String>(
                                'timesheet-form-paint',
                              ),
                              painter: TimesheetDocumentPainter(
                                document: document,
                                layout: layout,
                                viewport: viewport,
                                layers: const {
                                  SheetPaintLayer.paper,
                                  SheetPaintLayer.form,
                                },
                                // The sheet prints in the NOTATION
                                // language (UI-R10 #7).
                                notation: TimesheetNotation.of(
                                  session
                                      .languageSettings
                                      .value
                                      .notationLanguage,
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: StaticRaster(
                            debugLabel: 'timesheet-content',
                            child: CustomPaint(
                              key: const ValueKey<String>(
                                'timesheet-document-paint',
                              ),
                              painter: TimesheetDocumentPainter(
                                document: document,
                                layout: layout,
                                viewport: viewport,
                                layers: const {SheetPaintLayer.content},
                                dragPreview: session.dragPreview,
                                // Which cut the sheet is printing, so a
                                // cut-length drag on it can be read off the
                                // channel: the red cut-end line is DATA, and
                                // it was the one data line still printing the
                                // committed length while the cells beside it
                                // already previewed.
                                cutId: session.activeCutOrNull?.id,
                                notation: TimesheetNotation.of(
                                  session
                                      .languageSettings
                                      .value
                                      .notationLanguage,
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        // The playhead row highlight repaints ALONE (R13-2):
                        // cursor moves, seeks and playback ticks drive this
                        // thin layer through its repaint listenable — the
                        // sheet painter above never rebuilds for them.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                key: const ValueKey<String>(
                                  'timesheet-playhead-overlay',
                                ),
                                painter: TimesheetPlayheadPainter(
                                  document: document,
                                  layout: layout,
                                  viewport: viewport,
                                  resolvePlayheadFrame: () =>
                                      _resolvePlayheadFrame(session),
                                  repaint: Listenable.merge([
                                    session.editingFrameCursor,
                                    session.frameSeekCommitted,
                                    session.playback.globalFrameIndexListenable,
                                  ]),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        // Under the ink windows: reachable exactly when ink is
                        // blocked (the toggle doubles as the edit-mode switch).
                        Positioned.fill(
                          child: TimesheetHeaderEditLayer(
                            key: const ValueKey<String>(
                              'timesheet-header-edit-layer',
                            ),
                            layout: layout,
                            viewport: viewport,
                            onHeaderFieldCommitted: _commitHeaderField,
                            onMemoCommitted: session.updateActiveCutNote,
                          ),
                        ),
                        if (inkController != null &&
                            brushToolState != null &&
                            widget.inkEnabled)
                          Positioned.fill(
                            // The tool-state boundary (R18 UI-3): only this
                            // small overlay follows the brush/eraser — the
                            // sheet document above never rebuilds for it.
                            child: ValueListenableBuilder<BrushToolState>(
                              valueListenable: brushToolState,
                              builder: (context, toolState, _) =>
                                  TimesheetInkLayer(
                                    key: const ValueKey<String>(
                                      'timesheet-ink-layer',
                                    ),
                                    controller: inkController,
                                    layout: layout,
                                    pagedLayout: pagedLayout,
                                    cutId: session.requireActiveCut.id,
                                    brushToolState: toolState,
                                    historyManager: session.historyManager,
                                    viewport: viewport,
                                    strokeActive: _inkStrokeActive,
                                    cacheInvalidationSink:
                                        _cacheInvalidationSink,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The current sheet playhead frame: the playing local frame during
/// playback, the editing playhead otherwise.
int _resolvePlayheadFrame(EditorSessionManager session) {
  final playbackGlobalFrame = session.playback.globalFrameIndexListenable.value;
  return playbackGlobalFrame == null
      ? session.currentFrameIndex
      : session.playback.position?.localFrameIndex ?? session.currentFrameIndex;
}

/// Token-gated host for the sheet panel's PLAYHEAD-derived facts (R13-2):
/// the auto page turn, the Fit target page and the frame label need the
/// playhead, but rebuilding the whole panel per cursor move was the
/// timesheet's share of the frame-flip hitch. This scope listens to the
/// playhead signals and rebuilds ONLY when its derived token changes —
/// page-granular while editing and in paged playback, per-frame only for
/// the continuous-mode playback reveal (which pans every frame by
/// design).
class _TimesheetPlayheadScope extends StatefulWidget {
  const _TimesheetPlayheadScope({
    required this.session,
    required this.continuous,
    required this.pageFrameCount,
    required this.pageCount,
    required this.builder,
  });

  final EditorSessionManager session;
  final bool continuous;
  final int pageFrameCount;
  final int pageCount;

  /// Builds the panel subtree; [playbackGlobalFrame] is null while not
  /// playing (the auto-frame gate).
  final Widget Function(
    BuildContext context,
    int playheadFrame,
    int? playbackGlobalFrame,
  )
  builder;

  @override
  State<_TimesheetPlayheadScope> createState() =>
      _TimesheetPlayheadScopeState();
}

class _TimesheetPlayheadScopeState extends State<_TimesheetPlayheadScope> {
  late Object _token = _deriveToken();

  Object _deriveToken() {
    final session = widget.session;
    final playbackGlobalFrame =
        session.playback.globalFrameIndexListenable.value;
    final playheadFrame = _resolvePlayheadFrame(session);
    final page = widget.pageFrameCount <= 0
        ? 0
        : (playheadFrame ~/ widget.pageFrameCount).clamp(
            0,
            widget.pageCount - 1,
          );
    // Continuous-mode playback reveals the playhead row per frame; every
    // other mode only cares which PAGE the playhead is on.
    return (
      page,
      playbackGlobalFrame != null,
      playbackGlobalFrame != null && widget.continuous ? playheadFrame : null,
    );
  }

  void _handlePlayheadSignal() {
    final next = _deriveToken();
    if (next == _token) {
      return;
    }
    setState(() => _token = next);
  }

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    session.editingFrameCursor.addListener(_handlePlayheadSignal);
    session.frameSeekCommitted.addListener(_handlePlayheadSignal);
    session.playback.globalFrameIndexListenable.addListener(
      _handlePlayheadSignal,
    );
  }

  @override
  void dispose() {
    final session = widget.session;
    session.editingFrameCursor.removeListener(_handlePlayheadSignal);
    session.frameSeekCommitted.removeListener(_handlePlayheadSignal);
    session.playback.globalFrameIndexListenable.removeListener(
      _handlePlayheadSignal,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return widget.builder(
      context,
      _resolvePlayheadFrame(session),
      session.playback.globalFrameIndexListenable.value,
    );
  }
}
