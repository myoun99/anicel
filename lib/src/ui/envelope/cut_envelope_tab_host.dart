import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_presets.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../brush/brush_canvas_panel.dart' show BrushCanvasPanel;
import '../brush/sheet_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../editor_session_manager.dart';
import '../text/app_face.dart';
import '../widgets/app_icon_button.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_strata.dart';
import 'cut_envelope_builder.dart';
import '../sheet/sheet_ink_layer.dart';
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

  /// Resolves a media asset path (logo, 도장) to a decoded image.
  final ui.Image? Function(String assetPath)? imageFor;

  /// Notifies when an image [imageFor] answered null for has landed — the
  /// page's inputs do not change for it, so this is what repaints it.
  final Listenable? imageRepaint;

  // No shrink floor of its own: the envelope is a PAGE that scales into
  // whatever it is given and mounts no chrome row under the shell — the
  // conte's case too — so the panel's own floor is the whole story. Stating
  // a larger number here would only raise the bottom dock's minimum for
  // every tab beside it.

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
    final session = widget.session;
    // F-90: the cut under the playhead, like the sheet beside it.
    final cut = session.cutUnderPlayhead.resolve()?.cut;
    final form = CutEnvelopePresets.byId(widget.formId);

    // The panel shows the CUT-fitted paper: that is the size the export
    // drops into a working file at, so what is on screen is what ships.
    // Ink is measured against the FORM, not this, so a cut with a bigger
    // canvas never moves what is already written.
    final paper = cut == null
        ? CanvasSize(width: 1920, height: (1920 / form.aspectRatio).round())
        : CanvasSize(
            width: cut.canvasSize.width,
            height: cut.canvasSize.height,
          );
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
      canvasSize: paper,
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
      fitFocusRect: Rect.fromLTWH(
        0,
        0,
        paper.width.toDouble(),
        paper.height.toDouble(),
      ),
      drawingOn: inking,
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
            inkImageFor: inkController == null
                ? null
                : (key) => inkController.displayImageFor(null, key),
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
                    // A landed logo or 도장 — nothing the painter compares
                    // changes for it.
                    SheetStratum.content: painterOf(
                      SheetStratum.content,
                      repaint: widget.imageRepaint,
                    ),
                    if (inkController != null)
                      SheetStratum.ink: painterOf(
                        SheetStratum.ink,
                        repaint: inkController,
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
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The envelope's own commands, at the head of the panel's pill (R2 #13
  /// — the status strip they lived in is gone with the rest of the frame).
  List<Widget> _panelActions() {
    final onFormChanged = widget.onFormIdChanged;
    return [
      // Which 봉투 this is. Two bundled forms today, so the toggle is the
      // whole picker; a longer list becomes a menu when the form editor
      // lands.
      if (onFormChanged != null)
        for (final form in CutEnvelopePresets.all)
          AppIconButton(
            keyValue: 'envelope-form-${form.id}',
            tooltip: form.name,
            icon: Icon(
              form.id == CutEnvelopePresets.analogId
                  ? Icons.drafts_outlined
                  : Icons.fact_check_outlined,
            ),
            isSelected: widget.formId == form.id,
            size: AppIconButtonSize.strip,
            onPressed: () => onFormChanged(form.id),
          ),
    ];
  }
}
