import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_presets.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/sheet_paper.dart';
import '../brush/brush_canvas_panel.dart' show BrushCanvasPanel;
import '../brush/sheet_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../dialogs/dialog_verb.dart';
import '../dialogs/envelope_format_window.dart';
import '../editor_session_manager.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/panel_keys.dart';
import '../text/app_face.dart';
import '../text/app_strings.dart';
import '../timeline/memo_token.dart' show ByIdentity;
import '../widgets/app_icon_button.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_image_cache.dart' show SheetImageLookup;
import '../sheet/sheet_strata.dart';
import 'cut_envelope_builder.dart';
import '../sheet/sheet_ink_layer.dart';
import '../sheet/sheet_photo_drop.dart';
import 'cut_envelope_ink.dart';
import 'cut_envelope_overlay.dart';
import 'cut_envelope_painter.dart';

/// The cut-envelope PANEL: the 봉투 as paper inside the canvas panel shell
/// — the timesheet's and conte's architecture with envelope content.
///
/// It draws the very painter the export does, so what is on screen is the
/// sheet. Navigation is the drawing canvas's: wheel zoom, middle-drag pan,
/// panbars, Fit. With an [inkController] and [brushToolState] the sheet
/// takes freehand ink in whichever box a stroke starts in.
class CutEnvelopeTabHost extends StatefulWidget {
  const CutEnvelopeTabHost({
    super.key,
    required this.session,
    this.formId = CutEnvelopePresets.analogId,
    this.onFormIdChanged,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.inkController,
    this.brushToolState,
    this.brushAllowed = false,
    this.onBrushAllowedChanged,
    this.imageFor,
    this.imageRepaint,
  });

  final EditorSessionManager session;

  /// Which bundled form to print — the work's choice
  /// (`TimesheetInfo.envelopeFormId`), chosen here and kept with the work.
  final String formId;
  final ValueChanged<String>? onFormIdChanged;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Envelope ink store, owned above the tab group so annotations survive
  /// tab switches. Null renders the sheet read-only.
  final CutEnvelopeInkController? inkController;

  /// The editor's current brush/eraser: only the ink overlay subscribes,
  /// so tool switches never rebuild the sheet.
  final ValueListenable<BrushToolState>? brushToolState;

  /// The sheet's brush switch (브러시 허용). Off by default — an envelope is
  /// read before it is written on, and the brush off protects it from stray
  /// pen marks.
  final bool brushAllowed;
  final ValueChanged<bool>? onBrushAllowedChanged;

  /// Resolves a media asset path (the logo) to a decoded image.
  final SheetImageLookup? imageFor;

  /// Notifies when an image [imageFor] answered null for has landed — the
  /// page's inputs do not change for it, so this is what repaints it.
  final Listenable? imageRepaint;

  // No shrink floor of its own: the envelope is a PAGE that scales into
  // whatever it is given and mounts no chrome row under the shell — the
  // conte's case too — so the panel's own floor is the whole story. Stating
  // a larger number here would only raise the bottom dock's minimum for
  // every tab beside it.

  /// What the envelope prints of [session], to the panel host that hears
  /// the session through it: the project — the cut it is the envelope of
  /// and the work's form among it. The model is immutable, so a new one is
  /// the only way it moves. Which cut that is, the one under the playhead
  /// (F-90), turns it over through the host's own listenable.
  static Object printedBy(EditorSessionManager session) =>
      ByIdentity(session.repository.requireProject());

  @override
  State<CutEnvelopeTabHost> createState() => _CutEnvelopeTabHostState();
}

class _CutEnvelopeTabHostState extends State<CutEnvelopeTabHost> {
  late final SheetStrokeHold _strokeHold = SheetStrokeHold(
    brushInput: (live) => widget.session.setBrushInputActive(live),
  );

  /// Commit sink required by the panel API; envelope ink invalidations stay
  /// local (its synthetic keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  @override
  void dispose() {
    _strokeHold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A key presses the format window — the envelope is one panel,
    // whatever is in hand (I-40).
    return PanelKeysBinding(
      buttons: {EditorActionIds.envelopeFormat: _formatEditor},
      child: _sheet(),
    );
  }

  Widget _sheet() {
    final session = widget.session;
    // F-90: the cut under the playhead, like the sheet beside it.
    final cut = session.cutUnderPlayhead.resolve()?.cut;
    final form = CutEnvelopePresets.byId(widget.formId);

    // The panel shows the envelope's OWN paper — A4 on its side at 300dpi
    // (F-294, 유저 2026-10-05: 「콘티패널이랑 컷봉투패널의 용지는 300dpi」 ·
    // 「컷봉투 가로a4 수용할게」), whatever cut it is the envelope of. Ink is
    // measured against the FORM, not this, so a paper of another size —
    // an export's — never moves what is already written.
    //
    // ↩️It showed the CUT-fitted paper, the size the export drops into a
    // working file at (「what is on screen is what ships」): a paper that
    // changed with the cut under the playhead, and 1920 across with none.
    // The export still chooses its own paper (`CutEnvelopePaperMode`).
    final paper = SheetPaper.envelope.pixelSize;
    final layout = CutEnvelopeLayout.fit(
      form: form,
      paperWidth: paper.width.toDouble(),
      paperHeight: paper.height.toDouble(),
    );
    final source = cut == null
        ? const CutEnvelopeSource()
        : buildCutEnvelopeSource(
            project: session.repository.requireProject(),
            cut: cut,
          );

    final inkController = widget.inkController;
    inkController?.syncGeometry(aspectRatio: form.aspectRatio);
    final owner = cut == null
        ? null
        : cutEnvelopeInkOwner(session.repository.requireProject(), cut.id);
    final windows = owner == null || inkController == null
        ? const <SheetInkWindow>[]
        : envelopeInkWindows(layout, owner);
    final brushToolState = widget.brushToolState;
    final inking =
        inkController != null && brushToolState != null && widget.brushAllowed;
    final onBrushAllowedChanged = widget.onBrushAllowedChanged;

    return SheetCanvasPanel(
      cacheInvalidationSink: _cacheInvalidationSink,
      // The form is ruled straight onto the paper's pixels (its layout
      // scales with the paper it is given), so a unit here IS a pixel.
      sheetSize: SheetPaper.envelope.extent,
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      brushSwitch: onBrushAllowedChanged == null
          ? null
          : (
              allowed: widget.brushAllowed,
              onChanged: onBrushAllowedChanged,
              keyPrefix: 'envelope',
            ),
      bottomBarLeading: _panelActions(),
      fitFocusRect: paper.canvasRect,
      viewLimit: paper.canvasRect,
      drawingOn: inking,
      brushToolState: brushToolState,
      strokeHold: _strokeHold,
      content: (context, viewport) => LayoutBuilder(
        builder: (context, constraints) {
          // ONE gate, read by both the input layer and the painter: a box
          // whose window is mounted draws itself, and every other box's
          // saved ink is baked by the painter.
          final mounted = inking
              ? mountedEnvelopeInkWindows(
                  windows,
                  viewport,
                  constraints.biggest,
                )
              : const <SheetInkWindow>[];
          CutEnvelopePainter painterOf(
            SheetStratum stratum, {
            Listenable? repaint,
          }) => CutEnvelopePainter(
            layout: layout,
            source: source,
            face: appFaceOf(DefaultTextStyle.of(context).style),
            viewport: viewport,
            effectiveRatio: EffectiveDevicePixelRatio.of(context),
            layers: stratum.layers,
            imageFor: widget.imageFor,
            inkOwner: owner,
            inkSurfaceFor: inkController == null
                ? null
                : (key) => inkController.surfaceFor(null, key),
            liveInkKeys: {for (final window in mounted) window.key},
            repaint: repaint,
          );
          return Stack(
            children: [
              Positioned.fill(
                // Baked, not merely isolated — see the note on the conte
                // page. The ink stands down while the pen is down, when it
                // changes on every sample.
                child: SheetStrata(
                  sheet: 'envelope',
                  painters: {
                    SheetStratum.form: painterOf(SheetStratum.form),
                    // A landed logo — nothing the painter compares
                    // changes for it.
                    SheetStratum.content: painterOf(
                      SheetStratum.content,
                      repaint: widget.imageRepaint,
                    ),
                    // The ink, and a landed decode of a photo it holds
                    // (I-97).
                    if (inkController != null)
                      SheetStratum.ink: painterOf(
                        SheetStratum.ink,
                        repaint: Listenable.merge([
                          inkController,
                          widget.imageRepaint,
                        ]),
                      ),
                  },
                  liveNow: (stratum) =>
                      stratum == SheetStratum.ink && _strokeHold.value,
                  liveChanges: _strokeHold,
                ),
              ),
              if (inking)
                Positioned.fill(
                  // The tool-state boundary: the brush reaches only this
                  // overlay, so a tool switch never reprints the sheet — and
                  // since H40 ② (2026-09-24) not even the overlay rebuilds
                  // for it: its windows read the brush when a stroke starts.
                  child: CutEnvelopeInkOverlay(
                    key: const ValueKey<String>('cut-envelope-ink-layer'),
                    controller: inkController,
                    windows: mounted,
                    brushToolState: brushToolState,
                    historyManager: session.historyManager,
                    viewport: viewport,
                    strokeActive: _strokeHold,
                    cacheInvalidationSink: _cacheInvalidationSink,
                    imageFor: widget.imageFor,
                    imageRepaint: widget.imageRepaint,
                    photoHold: session.sheetPhotoHold,
                  ),
                ),
              // A pool picture dropped on a box is its photo (I-97).
              if (inkController != null && owner != null)
                Positioned.fill(
                  child: SheetPhotoDrop(
                    session: session,
                    ink: inkController,
                    windows: () => windows,
                    viewport: viewport,
                    cacheInvalidationSink: _cacheInvalidationSink,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The envelope's own command, at the head of the panel's pill (R2 #13
  /// — the status strip it lived in is gone with the rest of the frame), as
  /// the timesheet's format button stands. Off with nothing to write the
  /// form back to.
  List<Widget> _panelActions() => [
    AppIconButton(
      keyValue: 'envelope-format-button',
      tooltip: AppText.strings.envelopeFormatTitle,
      shortcuts: const [EditorActionIds.envelopeFormat],
      icon: const Icon(Icons.edit_note),
      size: AppIconButtonSize.strip,
      onPressed: _formatEditor,
    ),
  ];

  /// The envelope's format window — which form it is printed on, the work's
  /// choice (`TimesheetInfo.envelopeFormId`) — or null where there is
  /// nowhere to write it back.
  VoidCallback? get _formatEditor {
    final onFormChanged = widget.onFormIdChanged;
    if (onFormChanged == null) {
      return null;
    }
    return () => askThenCommit<String>(
      context,
      dialog: (_) => EnvelopeFormatWindow(initialFormId: widget.formId),
      commit: onFormChanged,
    );
  }
}
