import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_presets.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../brush/brush_canvas_panel.dart';
import '../brush/brush_edit_cache_invalidation_sink.dart';
import '../brush/brush_tool_state.dart';
import '../editor_session_manager.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/static_raster.dart';
import 'cut_envelope_builder.dart';
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
    this.onViewportChanged,
    this.inkController,
    this.brushToolState,
    this.inkEnabled = false,
    this.onInkEnabledChanged,
    this.imageFor,
  });

  final EditorSessionManager session;

  /// Which bundled form to print. Owned above the tab group, like the
  /// viewport; a project-level choice (and a form EDITOR) come with the
  /// preset round.
  final String formId;
  final ValueChanged<String>? onFormIdChanged;

  /// Owned above the tab group so zoom/pan survive tab switches.
  final CanvasViewport? viewport;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Envelope ink store, owned above the tab group so annotations survive
  /// tab switches. Null renders the sheet read-only.
  final CutEnvelopeInkController? inkController;

  /// The editor's current brush/eraser: only the ink overlay subscribes,
  /// so tool switches never rebuild the sheet.
  final ValueListenable<BrushToolState>? brushToolState;

  /// The ink allow toggle. Off by default — an envelope is read before it
  /// is written on, and blocked ink protects it from stray pen marks.
  final bool inkEnabled;
  final ValueChanged<bool>? onInkEnabledChanged;

  /// Resolves a media asset path (logo, 도장) to a decoded image.
  final ui.Image? Function(String assetPath)? imageFor;

  // No shrink floor of its own: the envelope is a PAGE that scales into
  // whatever it is given, and unlike the conte it mounts no chrome row
  // under the shell — so the panel's own floor is the whole story. Stating
  // a larger number here would only raise the bottom dock's minimum for
  // every tab beside it.

  @override
  State<CutEnvelopeTabHost> createState() => _CutEnvelopeTabHostState();
}

class _CutEnvelopeTabHostState extends State<CutEnvelopeTabHost> {
  final ValueNotifier<bool> _strokeActive = ValueNotifier<bool>(false);

  /// Commit sink required by the panel API; envelope ink invalidations stay
  /// local (its synthetic keys never reach the playback caches).
  final BrushEditCacheInvalidationSink _cacheInvalidationSink =
      BrushEditCacheInvalidationSink();

  @override
  void dispose() {
    _strokeActive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final cut = session.activeCutOrNull;
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
        ? const <EnvelopeInkWindow>[]
        : envelopeInkWindows(layout, owner);
    final brushToolState = widget.brushToolState;
    final inking =
        inkController != null && brushToolState != null && widget.inkEnabled;

    return BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: paper,
      viewport: widget.viewport,
      onViewportChanged: widget.onViewportChanged,
      // The paper never rotates (the timesheet's rule).
      allowViewRotation: false,
      bottomBarLeading: _panelActions(),
      fitFocusRect: Rect.fromLTWH(
        0,
        0,
        paper.width.toDouble(),
        paper.height.toDouble(),
      ),
      contentStrokeActive: inking ? _strokeActive : null,
      contentOverride: (context, viewport) => LayoutBuilder(
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
              : const <EnvelopeInkWindow>[];
          return Stack(
            children: [
              Positioned.fill(
                // Baked, not merely isolated — see the note on the conte
                // page. `StaticRaster` is a repaint boundary itself, so
                // this keeps what the `RepaintBoundary` bought and stops
                // the raster thread replaying the page every frame the
                // app happens to produce. It stands down while the pen is
                // down, when the page changes on every sample.
                child: ValueListenableBuilder<bool>(
                  valueListenable: _strokeActive,
                  builder: (context, stroking, child) => StaticRaster(
                    debugLabel: 'envelope-page',
                    enabled: !stroking,
                    child: child!,
                  ),
                  child: CustomPaint(
                    key: const ValueKey<String>('cut-envelope-page'),
                    painter: CutEnvelopePainter(
                      layout: layout,
                      source: source,
                      viewport: viewport,
                      imageFor: widget.imageFor,
                      inkKeyFor: owner == null
                          ? null
                          : (boxId) => envelopeInkBoxKey(owner, boxId),
                      inkImageFor: inkController?.displayImageFor,
                      liveInkKeys: {for (final window in mounted) window.key},
                      repaint: inkController,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              if (inking)
                Positioned.fill(
                  // The tool-state boundary: only this overlay follows the
                  // brush/eraser, so a tool switch never reprints the sheet.
                  child: ValueListenableBuilder<BrushToolState>(
                    valueListenable: brushToolState,
                    builder: (context, toolState, _) => CutEnvelopeInkOverlay(
                      key: const ValueKey<String>('cut-envelope-ink-layer'),
                      controller: inkController,
                      windows: mounted,
                      brushToolState: toolState,
                      historyManager: session.historyManager,
                      viewport: viewport,
                      strokeActive: _strokeActive,
                      cacheInvalidationSink: _cacheInvalidationSink,
                    ),
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
    final onChanged = widget.onInkEnabledChanged;
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
      if (onChanged != null && widget.inkController != null)
        AppIconButton(
          keyValue: 'envelope-ink-toggle-button',
          tooltip: widget.inkEnabled ? 'Block Sheet Ink' : 'Allow Sheet Ink',
          icon: Icon(widget.inkEnabled ? Icons.draw : Icons.edit_off),
          isSelected: widget.inkEnabled,
          size: AppIconButtonSize.strip,
          onPressed: () => onChanged(!widget.inkEnabled),
        ),
    ];
  }
}
