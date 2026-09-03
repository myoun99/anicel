part of '../editor_workspace.dart';

/// THE DOCUMENT VIEWS' STATE — what each document panel shows and how:
/// the timesheet's page, continuity, viewport and ink; the conte's and
/// the cut envelope's viewport, ink and images; the camera view; and the
/// tool options the canvas reads (fill, selection mask, transform,
/// eyedropper source). Notifiers, so the panels subscribe rather than
/// the workspace rebuilding.
///
/// 🚨A collaborator carved out of `_EditorWorkspaceState` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: nineteen fields the
/// workspace held only to hand to its tabs and dispose. It reaches the
/// workspace through `_state`.
class _WorkspaceDocumentViews {
  _WorkspaceDocumentViews(this._state);

  final _EditorWorkspaceState _state;

  /// The fill tool's flood options (Tool Settings knobs).
  final ValueNotifier<FloodFillOptions> _fillOptions = ValueNotifier(
    const FloodFillOptions(),
  );

  /// The Select tool's lift-time mask knobs (R26): grow/shrink, inward
  /// feather, edge AA. Defaults keep the lift byte-preserving.
  final ValueNotifier<SelectionMaskOptions> _selectionMaskOptions =
      ValueNotifier(SelectionMaskOptions.none);

  /// P3a: which resampler a transform commit runs through. Session state
  /// like its three neighbours here, deliberately NOT a [BrushToolState]
  /// field — everything there other than the tool itself forwards into
  /// [BrushShape], which is what a saved brush preset serialises, so the
  /// bit would follow every preset around for no reason.
  ///
  /// Blend is the default: smoothing is what a transform is expected to do
  /// everywhere else in the industry, and the argmax is the deliberate
  /// choice for two-value work.
  final ValueNotifier<TransformToolOptions> _transformOptions = ValueNotifier(
    TransformToolOptions.defaults,
  );

  /// R28 #6: the eyedropper's reference source (Tool Settings knob). The
  /// user's default is "pick what you SEE".
  final ValueNotifier<CanvasColorSampleSource> _eyedropperSource =
      ValueNotifier(CanvasColorSampleSource.display);

  /// Camera view mode: overlay shown with the outside dimmed.
  final ValueNotifier<bool> _cameraViewEnabled = ValueNotifier(false);

  final ValueNotifier<double> _cameraDimOpacity = ValueNotifier(0.5);

  /// Timesheet tab view state: paper page-split ⟷ continuous, the sheet
  /// on screen in page view (R26 #41), the sheet viewport (zoom/pan) and
  /// the sheet-ink allow toggle — owned here so they survive tab switches.
  final ValueNotifier<bool> _timesheetContinuous = ValueNotifier(false);

  final ValueNotifier<int> _timesheetPage = ValueNotifier(0);

  final ValueNotifier<CanvasViewport?> _timesheetViewport = ValueNotifier(null);

  final ValueNotifier<bool> _timesheetInkEnabled = ValueNotifier(true);

  /// Sheet ink stores (S2 annotations) — owned here so freehand memos
  /// survive tab switches; separate from the session's cel stroke store.
  final TimesheetInkController _timesheetInk = TimesheetInkController();

  /// Conte tab view state (#16 — the conte rides the same canvas shell):
  /// the sheet viewport and its ink toggle, owned here like the
  /// timesheet's. Ink starts BLOCKED: the conte's first verb is reading
  /// and selecting cells.
  final ValueNotifier<CanvasViewport?> _conteViewport = ValueNotifier(null);

  final ValueNotifier<bool> _conteInkEnabled = ValueNotifier(false);

  /// Cut-envelope tab view state — the conte's pair, said of the 봉투.
  /// Ink starts BLOCKED here too: the envelope is read (and printed)
  /// before anybody writes on it.
  final ValueNotifier<CanvasViewport?> _envelopeViewport = ValueNotifier(null);

  final ValueNotifier<bool> _envelopeInkEnabled = ValueNotifier(false);

  /// The logo and 도장 the envelope prints, decoded once each.
  ///
  /// A repaint is all a landed decode needs, and the envelope tab is the
  /// only thing that reads it — but the cache lives HERE because that tab is
  /// rebuilt on every panel switch and would drop its images each time.
  late final EnvelopeImageCache _envelopeImages = EnvelopeImageCache(
    onLoaded: () {
      if (_state.mounted) {
        _state._rebuild(() {});
      }
    },
  );

  /// Which bundled 봉투 form the panel prints. Session-scoped for now: the
  /// project-level choice arrives with the form editor, and until there is
  /// a place to store one, remembering it here beats hard-coding it.
  final ValueNotifier<String> _envelopeFormId = ValueNotifier(
    CutEnvelopePresets.analogId,
  );

  /// The cel stores are the SESSION's (R5): the archive saves and loads
  /// them with the project; this controller owns only the edit sessions.
  late final ConteInkController _conteInk = ConteInkController(
    rowStore: _state.widget.session.conteInkRowStore,
    pageStore: _state.widget.session.conteInkPageStore,
  );

  late final CutEnvelopeInkController _envelopeInk = CutEnvelopeInkController(
    store: _state.widget.session.envelopeInkStore,
  );

  /// Disposes every notifier and controller the views own; the workspace's
  /// `dispose` calls this once. (`_selectionMaskOptions` was never disposed
  /// while it lived on the workspace — it is now.)
  void dispose() {
    _fillOptions.dispose();
    _selectionMaskOptions.dispose();
    _transformOptions.dispose();
    _eyedropperSource.dispose();
    _cameraViewEnabled.dispose();
    _cameraDimOpacity.dispose();
    _timesheetContinuous.dispose();
    _timesheetPage.dispose();
    _timesheetViewport.dispose();
    _timesheetInkEnabled.dispose();
    _timesheetInk.dispose();
    _conteViewport.dispose();
    _conteInkEnabled.dispose();
    _conteInk.dispose();
    _envelopeViewport.dispose();
    _envelopeInkEnabled.dispose();
    _envelopeImages.dispose();
    _envelopeFormId.dispose();
    _envelopeInk.dispose();
  }
}
