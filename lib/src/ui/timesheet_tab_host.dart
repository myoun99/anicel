import 'widgets/empty_state_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/cut.dart';
import '../models/timesheet_document.dart';
import '../models/timesheet_info.dart';
import 'brush/brush_canvas_panel.dart'
    show BrushCanvasPanel, CanvasAutoFrameRequest;
import 'brush/sheet_canvas_panel.dart';
import 'text/app_strings.dart';
import 'brush/brush_edit_cache_invalidation_sink.dart';
import 'brush/brush_tool_state.dart';
import 'dialogs/dialog_verb.dart';
import 'dialogs/timesheet_info_dialog.dart';
import 'editor_session_manager.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/page_turn_strip.dart';
import 'timesheet/timesheet_document_painter.dart';
import 'timesheet/timesheet_header_edit_layer.dart';
import 'effective_device_pixel_ratio.dart';
import 'timesheet/timesheet_words_in.dart';
import 'timesheet/timesheet_ink_controller.dart';
import 'timesheet/timesheet_ink_layer.dart';
import 'timesheet/timesheet_strata.dart';

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
    this.viewportController,
    this.onViewportChanged,
    this.inkController,
    this.brushToolState,
    this.brushAllowed = false,
    this.onBrushAllowedChanged,
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

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;
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

  /// The sheet's brush switch (브러시 허용, owned above the tab group): off
  /// protects the sheet from stray pen marks AND turns taps into
  /// header/memo text editing (the edit layer sits under the ink windows).
  /// Off by default, like every sheet's.
  final bool brushAllowed;
  final ValueChanged<bool>? onBrushAllowedChanged;

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
  Cut? _documentCut;
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
  ///
  /// F-90: the cut it prints is the cut UNDER THE PLAYHEAD — the one being
  /// played or dragged over, which a scrub keeps apart from the cut open for
  /// editing — so a drag over a gap prints that bare background too.
  TimesheetDocumentLayout? _resolveLayouts(EditorSessionManager session) {
    final at = session.cutUnderPlayhead.resolve();
    if (at == null) {
      return null;
    }
    final cut = at.cut;
    final info = session.timesheetInfo;
    final projectName = session.repository.requireProject().name;
    final instructionSet = session.camera.cameraInstructionSet;
    // Track-owned SE rows join the memo key: their edits change the track
    // list identity, not the cut's.
    final trackSeLayers = session.activeTrack.seLayers;
    // Same story for the transition row: track-owned, so an edit there
    // changes the track's identity rather than the cut's.
    final transitionLayer = session.activeTrack.transitionLayer;
    final cutStartFrame = at.startFrame;
    if (_document == null ||
        !identical(_documentCut, cut) ||
        !identical(_documentInfo, info) ||
        !identical(_documentInstructionSet, instructionSet) ||
        !identical(_documentTrackSe, trackSeLayers) ||
        !identical(_documentTransition, transitionLayer) ||
        _documentCutStartFrame != cutStartFrame ||
        _documentProjectName != projectName ||
        _documentFps != session.projectSettings.projectFps ||
        _documentDataSheet != _dataSheet) {
      _documentCut = cut;
      _documentInfo = info;
      _documentInstructionSet = instructionSet;
      _documentTrackSe = trackSeLayers;
      _documentTransition = transitionLayer;
      _documentCutStartFrame = cutStartFrame;
      _documentProjectName = projectName;
      _documentFps = session.projectSettings.projectFps;
      _documentDataSheet = _dataSheet;
      _document = TimesheetDocument.fromCut(
        cut: cut,
        projectName: projectName,
        fps: session.projectSettings.projectFps,
        info: info,
        instructionDefById: instructionSet.defById,
        trackSeLayers: trackSeLayers,
        cutStartFrame: cutStartFrame,
        transitionSpans: session.transitions.activeTrackTransitionSpans,
        // D31: the transition row prints when its own timesheet flag is
        // on — through the SESSION'S cut-view projection (one walk for
        // the sheet and the cut timeline's row; spans re-keyed to this
        // cut's local axis), MINUS the D26-refused crossing fades (the
        // sheet prints only what applies — the row keeps them for the
        // warning to sit on). Off = the slot stays blank form space,
        // the camera column's own precedent.
        transitionLayer: transitionLayer.onTimesheet
            ? session.transitions.trackTransitionSheetLayerFor(
                cutStart: cutStartFrame,
                duration: cut.duration,
              )
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

  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => widget.session.setBrushInputActive(live),
  );

  @override
  void dispose() {
    _strokeHold.dispose();
    super.dispose();
  }

  /// What the ink windows are mounted with — or null while the sheet's
  /// drawing is off. ONE gate for the ink layer and the panel's
  /// [SheetCanvasPanel.drawingOn].
  ({TimesheetInkController controller, ValueListenable<BrushToolState> tool})?
  _inkMount() {
    final controller = widget.inkController;
    final tool = widget.brushToolState;
    if (controller == null || tool == null || !widget.brushAllowed) {
      return null;
    }
    return (controller: controller, tool: tool);
  }

  /// The brush switch both of this sheet's panels carry — the gap panel
  /// too, so the switch keeps its place when a cut is selected.
  ({bool allowed, ValueChanged<bool> onChanged, String keyPrefix})?
  _brushSwitch() {
    final onChanged = widget.onBrushAllowedChanged;
    return onChanged == null
        ? null
        : (
            allowed: widget.brushAllowed,
            onChanged: onChanged,
            keyPrefix: 'timesheet',
          );
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

  Future<void> _editSheetInfo() {
    final session = widget.session;
    return askThenCommit<TimesheetInfo>(
      context,
      dialog: (_) => TimesheetInfoDialog(initialInfo: session.timesheetInfo),
      commit: session.updateTimesheetInfo,
    );
  }

  /// The sheet's own commands, at the head of the panel's pill — after the
  /// brush switch, which the sheet shell puts first on every sheet.
  ///
  /// They lived in a status strip across the top of the panel until R2 #13
  /// took the strip (and the frame, and the bottom bar) away. A panel has
  /// one pill now and everything it offers is in it, each on the app's
  /// standard icon button (R26 #42) rather than a hand-rolled InkWell.
  List<Widget> _panelActions() {
    return [
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
            ? AppText.strings.sheetModeNotation
            : AppText.strings.sheetModeData,
        icon: const Icon(Icons.receipt_long_outlined),
        isSelected: _dataSheet,
        onPressed: () => setState(() => _dataSheet = !_dataSheet),
      ),
      AppIconButton(
        keyValue: 'timesheet-page-mode-toggle-button',
        tooltip: widget.continuous
            ? AppText.strings.sheetViewPage
            : AppText.strings.sheetViewContinuous,
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
    final page = layout == null ? 0 : _visiblePage(layout);
    return pageTurnStrip(
      keyPrefix: 'timesheet',
      page: (
        index: page,
        count: pageCount,
        // '1/2' — the spelling shared with the printed ページ header (R26 #41).
        readout: layout?.pageLabel(page) ?? '-',
      ),
      onTurnTo: widget.continuous ? null : _turnToPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final inkController = widget.inkController;
    final ink = _inkMount();

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
          return SheetCanvasPanel(
            cacheInvalidationSink: _cacheInvalidationSink,
            canvasSize: const CanvasSize(width: 780, height: 1080),
            // The GAP state has no cut, so there is no ink and no tool to
            // run: a press moves the page (F-80), which is what this panel
            // already did.
            drawingOn: false,
            viewport: widget.viewport,
            viewportController: widget.viewportController,
            onViewportChanged: widget.onViewportChanged,
            brushSwitch: _brushSwitch(),
            bottomBarLeading: [..._panelActions(), ..._bottomBarLeading(null)],
            pageStrip: _pageStrip(null),
            bottomBarHostToken: (widget.continuous, _dataSheet, 0, 0),
            // F-179: the backdrop shows through — no fill of the sheet's own.
            content: (context, viewport) => SizedBox.expand(
              key: const ValueKey<String>('timesheet-empty-no-cut'),
              child: EmptyStateText(
                strings.noCutSelected,
                place: EmptyStatePlace.stage,
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
                            _documentCut!.id,
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
                  return SheetCanvasPanel(
                    cacheInvalidationSink: _cacheInvalidationSink,
                    canvasSize: CanvasSize(
                      width: documentSize.width.ceil(),
                      height: documentSize.height.ceil(),
                    ),
                    viewport: widget.viewport,
                    viewportController: widget.viewportController,
                    onViewportChanged: widget.onViewportChanged,
                    brushSwitch: _brushSwitch(),
                    bottomBarLeading: [
                      ..._panelActions(),
                      ..._bottomBarLeading(layout),
                    ],
                    pageStrip: _pageStrip(layout),
                    bottomBarHostToken: (
                      widget.continuous,
                      _dataSheet,
                      visiblePage,
                      document.pages.length,
                    ),
                    // Fit frames the page on screen.
                    fitFocusRect: layout.pageRect(visiblePage),
                    autoFrame: autoFrame,
                    drawingOn: ink != null,
                    strokeHold: _strokeHold,
                    content: (context, viewport) {
                      return Stack(
                        children: [
                          // The sheet paints in strata (UI-R10 #9, the PSD
                          // layering live): the printed FORM below, the
                          // CONTENT above, the saved INK over both — each
                          // re-recorded only when what it prints changes.
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
                          Positioned.fill(
                            child: TimesheetStrata(
                              layout: layout,
                              pagedLayout: pagedLayout,
                              viewport: viewport,
                              words: timesheetWordsIn(
                                session.languageSettings.value.notationLanguage,
                              ),
                              dragPreview: session.dragPreview,
                              cutId: _documentCut!.id,
                              stroking: _strokeHold,
                              ink: inkController == null
                                  ? null
                                  : (
                                      controller: inkController,
                                      live: ink != null,
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
                                    effectiveRatio:
                                        EffectiveDevicePixelRatio.of(context),
                                    document: document,
                                    layout: layout,
                                    viewport: viewport,
                                    resolvePlayheadFrame: () =>
                                        _resolvePlayheadFrame(session),
                                    repaint: Listenable.merge([
                                      session.editingFrameCursor,
                                      session.frameSeekCommitted,
                                      session.gapParkingListenable,
                                      session
                                          .playbackRig
                                          .playback
                                          .globalFrameIndexListenable,
                                    ]),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                          // Under the ink windows: reachable exactly when the
                          // brush is off (the switch doubles as the edit-mode
                          // switch).
                          Positioned.fill(
                            child: TimesheetHeaderEditLayer(
                              key: const ValueKey<String>(
                                'timesheet-header-edit-layer',
                              ),
                              layout: layout,
                              viewport: viewport,
                              onHeaderFieldCommitted: _commitHeaderField,
                              onMemoCommitted:
                                  session.cutVerbs.updateActiveCutNote,
                            ),
                          ),
                          if (ink != null)
                            Positioned.fill(
                              // The tool-state boundary (R18 UI-3): the brush
                              // reaches only this small overlay — the sheet
                              // document above never rebuilds for it — and
                              // since H40 ② (2026-09-24) not even the overlay
                              // does: its windows read the brush when a
                              // stroke starts.
                              child: TimesheetInkLayer(
                                key: const ValueKey<String>(
                                  'timesheet-ink-layer',
                                ),
                                controller: ink.controller,
                                layout: layout,
                                pagedLayout: pagedLayout,
                                cutId: _documentCut!.id,
                                brushToolState: ink.tool,
                                historyManager: session.historyManager,
                                viewport: viewport,
                                strokeActive: _strokeHold,
                                cacheInvalidationSink: _cacheInvalidationSink,
                              ),
                            ),
                        ],
                      );
                    },
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
/// playback, the editing playhead otherwise — and, since F-90, a live
/// scrub's parked frame inside the cut the sheet prints.
int _resolvePlayheadFrame(EditorSessionManager session) =>
    session.cutUnderPlayhead.localFrame;

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
        session.playbackRig.playback.globalFrameIndexListenable.value;
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
    session.playbackRig.playback.globalFrameIndexListenable.addListener(
      _handlePlayheadSignal,
    );
  }

  @override
  void dispose() {
    final session = widget.session;
    session.editingFrameCursor.removeListener(_handlePlayheadSignal);
    session.frameSeekCommitted.removeListener(_handlePlayheadSignal);
    session.playbackRig.playback.globalFrameIndexListenable.removeListener(
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
      session.playbackRig.playback.globalFrameIndexListenable.value,
    );
  }
}
