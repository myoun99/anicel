import 'widgets/empty_state_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_frame_grid_settings.dart';
import '../models/canvas_viewport.dart';
import '../models/cut.dart';
import '../models/inbetween_mark.dart';
import '../models/sheet_paper.dart';
import '../models/sheet_sources.dart';
import '../models/timesheet_document.dart';
import 'brush/brush_canvas_panel.dart'
    show BrushCanvasPanel, CanvasTransportBand;
import 'brush/sheet_canvas_panel.dart';
import 'text/app_strings.dart';
import 'brush/brush_edit_cache_invalidation_sink.dart';
import 'brush/brush_tool_state.dart';
import 'brush/canvas_book.dart';
import 'dialogs/dialog_verb.dart';
import 'dialogs/timesheet_format_window.dart';
import 'editor_session_manager.dart';
import 'widgets/app_icon_button.dart';
import 'shortcuts/editor_action_registry.dart' show EditorActionIds;
import 'shortcuts/panel_keys.dart';
import 'sliced_value_listenable_builder.dart' show SlicedListenable;
import 'timeline/memo_token.dart' show ByIdentity;
import 'timesheet/cut_sheet_document.dart';
import 'timesheet/timesheet_document_painter.dart';
import 'effective_device_pixel_ratio.dart';
import 'timesheet/timesheet_ink_controller.dart';
import 'timesheet/timesheet_paper.dart';
import 'sheet/sheet_image_cache.dart' show SheetImageLookup;

/// The Timesheet tab's content: the active cut rendered as a paper
/// timesheet DOCUMENT (not an editing grid) inside the canvas panel shell,
/// so navigation feels exactly like the drawing canvas — wheel zoom,
/// middle-drag/two-finger pan, panbars, Fit. With an [inkController] and
/// [brushToolState] the sheet takes freehand ink memos with the current
/// brush/eraser (S2): ink on the paper, one surface per page (F-252).
class TimesheetTabHost extends StatefulWidget {
  const TimesheetTabHost({
    super.key,
    required this.session,
    this.reading,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.inkController,
    this.brushToolState,
    this.brushAllowed = false,
    this.onBrushAllowedChanged,
    this.dataSheet = false,
    this.onDataSheetChanged,
    this.imageFor,
    this.imageRepaint,
  });

  final EditorSessionManager session;

  /// The page the reader is on, the sheets lying one under another
  /// (F-201) — owned above the tab group with the viewport, so a tab
  /// switch doesn't lose the reader's place. The panel keeps it true to the
  /// view ([CanvasBook]); a write to it is a turn — the page turner's ◀ ▶,
  /// and playback crossing into a page. Null keeps one of the host's own.
  final ValueNotifier<int>? reading;

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
  /// tool switches and setting tweaks must not rebuild the whole document.
  final ValueListenable<BrushToolState>? brushToolState;

  /// The sheet's brush switch (브러시 허용, owned above the tab group): off
  /// protects the sheet from stray pen marks AND turns taps into
  /// header/memo text editing (the edit layer sits under the ink windows).
  /// Off by default, like every sheet's.
  final bool brushAllowed;
  final ValueChanged<bool>? onBrushAllowedChanged;

  /// DATA-sheet mode (UI-R24 #1): the sheet prints the EXPORT-SOURCE data
  /// (ghost chains verbatim, the labels XDTS/TDTS write) instead of the
  /// notation shorthand — for auditing exactly what the file will carry.
  /// View state, session-only, owned above the tab group like the brush
  /// switch beside it.
  final bool dataSheet;
  final ValueChanged<bool>? onDataSheetChanged;

  /// The pool files the ink's photos are drawn from (I-97), from the decode
  /// cache the conte and the envelope print from — and what says one has
  /// landed.
  final SheetImageLookup? imageFor;
  final Listenable? imageRepaint;

  @override
  State<TimesheetTabHost> createState() => _TimesheetTabHostState();
}

/// What a sheet prints of the session ([_TimesheetTabHostState._printedBy]),
/// each model object by IDENTITY — they are immutable, so a new one is the
/// only way any of them changes.
typedef _Printed = ({
  ByIdentity<Cut> cut,
  int cutStartFrame,
  ByIdentity<Object> info,
  String projectName,
  ByIdentity<Object> instructionSet,
  ByIdentity<Object> trackSe,
  ByIdentity<Object> transition,
  int fps,
  InbetweenMark unnamedMark,
});

class _TimesheetTabHostState extends State<TimesheetTabHost> {
  /// Commit sink required by the panel API; sheet ink invalidations stay
  /// local (synthetic ink keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  // Memoized sheet document + layout: building them is the expensive part
  // of this host's rebuild, and most session notifies (fx toggles, waveform
  // loads, selections, committed seeks) change none of their inputs — the
  // model objects are immutable, so identity is the staleness check.
  TimesheetDocument? _document;
  TimesheetDocumentLayout? _layout;
  _Printed? _documentPrinted;
  bool? _documentDataSheet;

  Cut? get _documentCut => _documentPrinted?.cut.value;

  bool get _dataSheet => widget.dataSheet;

  /// What the sheet prints of the session: the cut under the playhead and
  /// everything else its document is made of — null in the GAP state (no
  /// active cut, UI-R9 #3), where the host renders the bare sheet
  /// background instead of a document.
  ///
  /// F-90: the cut it prints is the cut UNDER THE PLAYHEAD — the one being
  /// played or dragged over, which a scrub keeps apart from the cut open for
  /// editing — so a drag over a gap prints that bare background too.
  ///
  /// ONE answer to whether the document is made again ([_resolveLayouts])
  /// and to whether the session's news reaches this host at all
  /// ([_printedNews]): the sheet shows nothing else of the session, so a
  /// notify that leaves this alone has nothing to show.
  static _Printed? _printedBy(EditorSessionManager session) {
    final at = session.cutUnderPlayhead.resolve();
    if (at == null) {
      return null;
    }
    return (
      cut: ByIdentity(at.cut),
      cutStartFrame: at.startFrame,
      info: ByIdentity(session.timesheetInfo),
      projectName: session.repository.requireProject().name,
      instructionSet: ByIdentity(session.camera.cameraInstructionSet),
      // Track-owned SE rows join the memo key: their edits change the track
      // list identity, not the cut's.
      trackSe: ByIdentity(session.activeTrack.seLayers),
      // Same story for the transition row: track-owned, so an edit there
      // changes the track's identity rather than the cut's. It is keyed as
      // it PRINTS (F-229): an O.L writes the cuts it joins and the word of
      // the sheet's language, so a rename next door or a language switch
      // reprints.
      transition: ByIdentity(
        session.transitions.names.rowNamed(
          session.activeTrack,
          session.activeTrack.transitionLayer,
          olWord: sheetOlWord(session),
        ),
      ),
      fps: session.projectSettings.projectFps,
      // An app preference, not the session's (F-489): a pick reprints.
      unnamedMark: AppFrameGridSettings.settings.value.unnamedMark,
    );
  }

  TimesheetDocumentLayout? _resolveLayouts(EditorSessionManager session) {
    final printed = _printedBy(session);
    if (printed == null) {
      return null;
    }
    if (_document == null ||
        _documentPrinted != printed ||
        _documentDataSheet != _dataSheet) {
      _documentPrinted = printed;
      _documentDataSheet = _dataSheet;
      _document = cutSheetDocument(
        session,
        cut: printed.cut.value,
        cutStartFrame: printed.cutStartFrame,
        dataSheet: _dataSheet,
      );
      _layout = null;
    }
    return _layout ??= TimesheetDocumentLayout(document: _document!);
  }

  /// The session's news — and the app's pick of the unnamed mark — as this
  /// sheet hears it: only a change to what it prints ([_printedBy]).
  ///
  /// 🔬Every notify used to rebuild the sheet's shell — 50 elements, the
  /// panel's pill and layers round a document the memo then handed back
  /// unchanged — for a guide picked on the canvas or the onion switched on
  /// (session-news-rebuilds-unsliced, 2026-10-20).
  late final SlicedListenable<_Printed?> _printedNews = SlicedListenable(
    Listenable.merge([widget.session, AppFrameGridSettings.settings]),
    () => _printedBy(widget.session),
  );

  late final ValueNotifier<int> _ownReading = ValueNotifier(0);

  /// [TimesheetTabHost.reading], or the host's own.
  ValueNotifier<int> get _reading => widget.reading ?? _ownReading;

  /// The sheet's book (F-201): the sheets one under another and the page
  /// the reader is on.
  CanvasBook _bookOf(TimesheetDocumentLayout layout) =>
      CanvasBook(pages: layout.pageStack, reading: _reading);

  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => widget.session.setBrushInputActive(live),
  );

  @override
  void dispose() {
    _printedNews.dispose();
    _strokeHold.dispose();
    _ownReading.dispose();
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

  /// The sheet's format, and the paper of the cut it shows — the cut
  /// under the playhead the sheet prints ([_resolveLayouts]).
  Future<void> _editSheetFormat() {
    final session = widget.session;
    final cut = session.cutUnderPlayhead.resolve()?.cut;
    return askThenCommit<TimesheetFormat>(
      context,
      dialog: (_) => TimesheetFormatWindow(
        initialInfo: session.timesheetInfo,
        sheet: cut == null
            ? null
            : (
                kind: cut.metadata.sheetKind,
                celColumns: SheetSources.of(cut: cut).celColumnsAcross,
              ),
      ),
      commit: (format) => session.updateTimesheetFormat(
        info: format.info,
        cutId: cut?.id,
        kind: format.kind,
      ),
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
        keyValue: 'timesheet-format-button',
        tooltip: AppText.strings.sheetFormatTitle,
        shortcuts: const [EditorActionIds.timesheetFormat],
        icon: const Icon(Icons.edit_note),
        size: AppIconButtonSize.strip,
        onPressed: _editSheetFormat,
      ),
    ];
  }

  /// R26 #41 — the sheet's MODE toggle, at the far left of the pill:
  ///
  ///   [notation/data] │ ═══ the view controls ═══
  ///
  /// ↩️[page/continuous] stood beside it until the continuous view was
  /// deleted (F-252-Q1, 2026-10-08).
  ///
  /// ⛔The page cluster used to follow them here. It moved to the panel's
  /// left edge (유저 확정 ⑥ 2026-08-13) because three controls at 44px of
  /// budget each were most of what the pill had to spend, and a rail-width
  /// sheet was shedding the lot — turning pages and reading the page
  /// competing for the same row. It stands under the sheet now
  /// ([_pageTurner], F-383).
  List<Widget> _bottomBarLeading() {
    return [
      // Notation ↔ DATA sheet (UI-R24 #1): data prints the export-source
      // labels (ghost chains verbatim, exactly what XDTS/TDTS write) so
      // the output data can be audited on the sheet itself.
      AppIconButton(
        keyValue: 'timesheet-data-mode-toggle-button',
        tooltip: _dataSheet
            ? AppText.strings.sheetModeNotation
            : AppText.strings.sheetModeData,
        shortcuts: const [EditorActionIds.timesheetDataMode],
        icon: const Icon(Icons.receipt_long_outlined),
        isSelected: _dataSheet,
        onPressed: _toggleDataSheet,
      ),
    ];
  }

  /// Notation ⇄ data — the switch's press, and its key's (I-40).
  void _toggleDataSheet() => widget.onDataSheetChanged?.call(!_dataSheet);

  /// Turning the sheet's pages, in the band under it (F-383) rather than in
  /// the pill.
  CanvasTransportBand? _pageTurner(
    BuildContext context,
    TimesheetDocumentLayout layout,
  ) {
    final book = _bookOf(layout);
    return CanvasTransportBand.ofPages(
      context,
      keyPrefix: 'timesheet',
      page: (
        index: book.page,
        count: layout.document.pages.length,
        // '1/2' — the spelling shared with the printed ページ header (R26 #41).
        spell: layout.pageLabel,
      ),
      onTurnTo: book.turnTo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final inkController = widget.inkController;
    final ink = _inkMount();

    // A change to what the sheet prints ([_printedNews]) rebuilds the sheet
    // data and hands the windows fresh ink session surfaces; the ink — a
    // stroke, an undo, a redo — notifies through the controller (F-80 ②).
    // The playhead deliberately does NOT
    // live here (R13-2): cursor moves, committed seeks and playback ticks
    // repaint the thin playhead overlay only — repainting the whole B4
    // sheet per playhead move was the timesheet's share of the frame-flip
    // hitch. Page-granular playhead facts (auto page turn, Fit target,
    // the frame label) rebuild through the token-gated scope below.
    // And the page read, which the panel moves as the view scrolls.
    final listenable = Listenable.merge([
      _printedNews,
      ?inkController,
      _reading,
    ]);

    final sheet = ListenableBuilder(
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
            // The stage a sheet will stand on: its paper, bare.
            sheetSize: SheetPaper.timesheet.extent,
            // The GAP state has no cut, so there is no ink and no tool to
            // run: a press moves the page (F-80), which is what this panel
            // already did.
            drawingOn: false,
            viewport: widget.viewport,
            viewportController: widget.viewportController,
            onViewportChanged: widget.onViewportChanged,
            brushSwitch: _brushSwitch(),
            bottomBarLeading: [..._panelActions(), ..._bottomBarLeading()],
            bottomBarHostToken: (_dataSheet, 0, 0),
            // No cut, no paper: nothing for the view to stop at.
            viewLimit: null,
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
        inkController?.syncGeometry(layout);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TimesheetPlayheadScope(
                session: session,
                pageFrameCount: document.pageFrameCount,
                pageCount: document.pages.length,
                builder: (context, playheadFrame, playbackGlobalFrame) {
                  final playheadPage =
                      (playheadFrame ~/ document.pageFrameCount).clamp(
                        0,
                        document.pages.length - 1,
                      );
                  final book = _bookOf(layout);
                  final visiblePage = book.page;
                  // Playback follows the sheet (③): the sheet TURNS TO the
                  // playhead's page — the view moves to it, the sheets
                  // lying one under another (F-201; ↩️R26 #41 swapped the
                  // paper under a view that never moved). Idle keeps the
                  // viewport and the page user-owned.
                  if (playbackGlobalFrame != null &&
                      playheadPage != visiblePage) {
                    // Out of build: the turn writes the page notifier that
                    // this very subtree reads.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        book.turnTo(playheadPage);
                      }
                    });
                  }
                  return SheetCanvasPanel(
                    cacheInvalidationSink: _cacheInvalidationSink,
                    sheetSize: layout.documentSize,
                    paperScale: layout.paperScale,
                    viewport: widget.viewport,
                    viewportController: widget.viewportController,
                    onViewportChanged: widget.onViewportChanged,
                    brushSwitch: _brushSwitch(),
                    bottomBarLeading: [
                      ..._panelActions(),
                      ..._bottomBarLeading(),
                    ],
                    transport: _pageTurner(context, layout),
                    bottomBarHostToken: (
                      _dataSheet,
                      visiblePage,
                      document.pages.length,
                    ),
                    viewLimit: layout.paper,
                    book: book,
                    drawingOn: ink != null,
                    brushToolState: widget.brushToolState,
                    strokeHold: _strokeHold,
                    content: (context, viewport) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: TimesheetPaper(
                              session: session,
                              layout: layout,
                              cutId: _documentCut!.id,
                              viewport: viewport,
                              strokeHold: _strokeHold,
                              cacheInvalidationSink: _cacheInvalidationSink,
                              inkController: inkController,
                              inkTool: ink?.tool,
                              imageFor: widget.imageFor,
                              imageRepaint: widget.imageRepaint,
                            ),
                          ),
                          // The playhead row highlight repaints ALONE (R13-2):
                          // cursor moves, seeks and playback ticks drive this
                          // thin layer through its repaint listenable — the
                          // sheet painter above never rebuilds for them.
                          //
                          // 🚨OVER EVERYTHING, the live ink windows included
                          // (board: timesheet-playhead-row-over-ink). It lay
                          // over the printed ink and under the live windows,
                          // so writing on the playhead's row was tinted with
                          // the brush off and not with it on — and the brush
                          // switch changes nothing on a sheet (F-215, 유저
                          // 2026-09-28: 「on하든off하든 바뀌는게 없어야」). It
                          // takes no input, so the pen goes through it.
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
                                      session
                                          .editingSession
                                          .gapParkingListenable,
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
    // A key presses the format window and the notation ⇄ data switch —
    // the timesheet is one panel, whatever is in hand (I-40).
    return PanelKeysBinding(
      buttons: {
        EditorActionIds.timesheetFormat: _editSheetFormat,
        EditorActionIds.timesheetDataMode: _toggleDataSheet,
      },
      child: sheet,
    );
  }
}

/// The current sheet playhead frame: the playing local frame during
/// playback, the editing playhead otherwise — and, since F-90, a live
/// scrub's parked frame inside the cut the sheet prints.
int _resolvePlayheadFrame(EditorSessionManager session) =>
    session.cutUnderPlayhead.localFrame;

/// Token-gated host for the sheet panel's PLAYHEAD-derived fact (R13-2):
/// the auto page turn needs the playhead, but rebuilding the whole panel
/// per cursor move was the timesheet's share of the frame-flip hitch. This
/// scope listens to the playhead signals and rebuilds ONLY when its derived
/// token changes — the playhead's page, and whether playback runs.
class _TimesheetPlayheadScope extends StatefulWidget {
  const _TimesheetPlayheadScope({
    required this.session,
    required this.pageFrameCount,
    required this.pageCount,
    required this.builder,
  });

  final EditorSessionManager session;
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
  /// 🚨Taken at MOUNT ([initState]). It was a lazy `late` initializer, so
  /// the first signal derived the token it was compared against from the
  /// state that signal brought — equal by construction, and swallowed:
  /// playback started on another sheet turned nothing until the playhead
  /// crossed a page.
  late Object _token;

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
    return (page, playbackGlobalFrame != null);
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
    _token = _deriveToken();
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
