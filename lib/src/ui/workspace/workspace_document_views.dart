part of '../editor_workspace.dart';

/// THE DOCUMENT VIEWS' STATE — what each document panel shows and how:
/// the timesheet's page, continuity, viewport and ink; the conte's and
/// the cut envelope's viewport, ink and images; and the tool options the
/// canvas reads (fill, selection mask, eyedropper source —
/// the transform's are the shell's, beside the tool, because a shortcut
/// presses a transform mode). Notifiers, so the panels subscribe rather than
/// the workspace rebuilding.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: nineteen fields the
/// workspace held only to hand to its tabs and dispose.
class _WorkspaceDocumentViews {
  _WorkspaceDocumentViews();

  /// The fill tool's flood options (Tool Settings knobs).
  final ValueNotifier<FloodFillOptions> _fillOptions = ValueNotifier(
    const FloodFillOptions(),
  );

  /// The Select tool's lift-time mask knobs (R26): grow/shrink, inward
  /// feather, edge AA. Defaults keep the lift byte-preserving.
  final ValueNotifier<SelectionMaskOptions> _selectionMaskOptions =
      ValueNotifier(SelectionMaskOptions.none);

  /// What the next text set with the text tool starts as (R9-rest) — the
  /// tool settings write it, the canvas reads it when a text is begun.
  final ValueNotifier<TextToolOptions> _textToolOptions = ValueNotifier(
    TextToolOptions.defaults,
  );

  /// R28 #6: the eyedropper's reference source (Tool Settings knob). The
  /// user's default is "pick what you SEE".
  final ValueNotifier<CanvasReadSource> _eyedropperSource =
      ValueNotifier(CanvasReadSource.display);

  // ↩️The camera view stood here — the overlay's switch and its dim, the
  // window's — until they became the project's camera row's eye and opacity
  // (F-363, `CameraViewMode`): a project opened in the window came up in the
  // view the one before it was left in.

  /// Timesheet tab view state: the page read (F-201), the sheet viewport
  /// (zoom/pan) and the brush switch — owned here so they survive tab
  /// switches.
  final ValueNotifier<int> _timesheetPage = ValueNotifier(0);

  final ValueNotifier<CanvasViewport?> _timesheetViewport = ValueNotifier(null);

  /// Every sheet's brush switch starts OFF (유저 2026-09-25: 「브러시
  /// 허용으로 바꾸고, 버튼 법 통일하고, 기본값 off로」). ↩️The timesheet's
  /// alone used to start on.
  final ValueNotifier<bool> _timesheetBrushAllowed = ValueNotifier(false);

  /// Whether the timesheet prints its DATA sheet (UI-R24 #1). ↩️The host
  /// kept it, held only by the panel being kept alive; a panel is built only
  /// while it shows now (유저 2026-10-14).
  final ValueNotifier<bool> _timesheetDataSheet = ValueNotifier(false);

  /// Conte tab view state (#16 — the conte rides the same canvas shell):
  /// the sheet viewport and its brush switch, owned here like the
  /// timesheet's. The brush starts OFF: the conte's first verb is reading
  /// and selecting cells.
  final ValueNotifier<CanvasViewport?> _conteViewport = ValueNotifier(null);

  final ValueNotifier<bool> _conteBrushAllowed = ValueNotifier(false);

  /// Cut-envelope tab view state — the conte's pair, said of the 봉투.
  /// The brush starts OFF here too: the envelope is read (and printed)
  /// before anybody writes on it.
  final ValueNotifier<CanvasViewport?> _envelopeViewport = ValueNotifier(null);

  final ValueNotifier<bool> _envelopeBrushAllowed = ValueNotifier(false);

  /// The media images the sheets print — the logo, the cover picture, the
  /// photos on their ink (I-97) — for the three sheets alike, read through
  /// the project on screen ([bindSession]): the copies it carries are its
  /// own.
  ///
  /// A repaint is all a landed read needs — the painters listen to it —
  /// but the cache lives HERE because the tabs are rebuilt on every panel
  /// switch and would drop their images each time.
  late SheetImageCache _sheetImages;

  /// The three sheets' ink — each controller over the project on screen's
  /// stores, made again for each project that comes on screen
  /// ([bindSession]).
  ///
  /// The cel stores are the SESSION's (R5): the archive saves and loads
  /// them with the project; a controller owns only the edit sessions. The
  /// timesheet's joined them with I-7 — its controller made its own, so its
  /// memos were the window's and showed on every project's sheet.
  late TimesheetInkController _timesheetInk;

  late ConteInkController _conteInk;

  /// The conte's pictures draw into the canvas's own cels — the session's
  /// cel store, beside the sheet's ink.
  late ContePictureInkController _contePictures;

  late CutEnvelopeInkController _envelopeInk;

  /// The ink both viewers write on the files the project carries (I-114).
  late ViewerInkController _viewerInk;

  /// Makes the ink controllers over [session]'s stores, and the sheets'
  /// images over its media — the workspace's door for the project coming
  /// on screen.
  void bindSession(EditorSessionManager session) {
    final caches = session.renderCaches;
    _timesheetInk = TimesheetInkController(store: caches.timesheetInkStore);
    _conteInk = ConteInkController(rowStore: caches.conteInkRowStore);
    _contePictures = ContePictureInkController(cels: caches.brushFrameStore);
    _envelopeInk = CutEnvelopeInkController(store: caches.envelopeInkStore);
    _viewerInk = ViewerInkController(store: caches.viewerInkStore);
    final hold = session.projectFile.holdMediaBytes;
    _sheetImages = SheetImageCache(
      read: (path, width) => readSheetImage(hold, path, width),
      // The census cannot reach the workspace; the session can be reached.
      onHeldBytesChanged: (bytes) => caches.sheetImageBytes = bytes,
    );
    session.memoryPressureTicks.addListener(
      _sheetImages.respondToMemoryPressure,
    );
  }

  /// Lets the ink controllers and [session]'s images go — the stores stay
  /// with their project.
  void unbindSession(EditorSessionManager session) {
    _timesheetInk.dispose();
    _conteInk.dispose();
    _contePictures.dispose();
    _envelopeInk.dispose();
    _viewerInk.dispose();
    session.memoryPressureTicks.removeListener(
      _sheetImages.respondToMemoryPressure,
    );
    // The cache reports the zero to [session].
    _sheetImages.dispose();
  }

  /// Disposes every notifier the views own; the workspace's `dispose` calls
  /// this once, after [unbindSession]. (`_selectionMaskOptions` was never
  /// disposed while it lived on the workspace — it is now.)
  void dispose() {
    _fillOptions.dispose();
    _selectionMaskOptions.dispose();
    _textToolOptions.dispose();
    _eyedropperSource.dispose();
    _timesheetPage.dispose();
    _timesheetViewport.dispose();
    _timesheetBrushAllowed.dispose();
    _timesheetDataSheet.dispose();
    _conteViewport.dispose();
    _conteBrushAllowed.dispose();
    _envelopeViewport.dispose();
    _envelopeBrushAllowed.dispose();
  }
}
