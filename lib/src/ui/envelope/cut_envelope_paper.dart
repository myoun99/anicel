import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/envelope/cut_envelope_source.dart';
import '../../services/cache_invalidation_executor.dart';
import '../brush/brush_tool_state.dart';
import '../brush/sheet_canvas_panel.dart' show SheetStrokeHold;
import '../editor_session_manager.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_image_cache.dart' show SheetImageLookup;
import '../sheet/sheet_ink_layer.dart';
import '../sheet/sheet_photo_drop.dart';
import '../sheet/sheet_strata.dart';
import '../text/app_face.dart';
import 'cut_envelope_edit_layer.dart';
import 'cut_envelope_ink.dart';
import 'cut_envelope_overlay.dart';
import 'cut_envelope_painter.dart';

/// A CUT'S ENVELOPE AS IT IS EDITED, over a snapped view: the strata, the
/// ink windows of the boxes on screen while the sheet draws, and the photo
/// drop — on whatever paper [layout] rules the form onto.
///
/// 🗣️ONE stack for the envelope panel and the cel export's envelope
/// (I-127, 유저 2026-10-25: 「셀 출력의 타임시트나 컷봉투에도 … 동등하게
/// 가능하도록. 법 통일하면서」). Ink is measured against the FORM, so the
/// export's paper — another size than the panel's — writes where the
/// panel does. ↩️The panel's host wrote it inline, and the export showed
/// the envelope as a picture.
class CutEnvelopePaper extends StatelessWidget {
  const CutEnvelopePaper({
    super.key,
    required this.session,
    required this.layout,
    required this.source,
    required this.owner,
    required this.viewport,
    required this.strokeHold,
    required this.cacheInvalidationSink,
    this.inkController,
    this.inkTool,
    this.imageFor,
    this.imageRepaint,
  });

  final EditorSessionManager session;

  /// The form ruled onto the paper shown.
  final CutEnvelopeLayout layout;

  /// What the envelope prints of its cut.
  final CutEnvelopeSource source;

  /// The cut whose envelope's ink this is (`cutEnvelopeInkOwner`), or null
  /// with no cut — a bare form, which takes no ink.
  final CutId? owner;

  /// The view as the sheet's units read it ([SheetCanvasPanel.content]).
  final CanvasViewport viewport;

  /// The sheet's live-stroke hold ([SheetCanvasPanel.strokeHold]).
  final SheetStrokeHold strokeHold;

  final CacheInvalidationSink cacheInvalidationSink;

  /// The envelope's ink; null prints none and takes none.
  final CutEnvelopeInkController? inkController;

  /// The tool in hand while the sheet DRAWS ([SheetCanvasPanel.drawingOn]);
  /// null while it does not.
  final ValueListenable<BrushToolState>? inkTool;

  /// Resolves a media asset path (the logo) to a decoded image, and says
  /// when one it answered null for has landed.
  final SheetImageLookup? imageFor;
  final Listenable? imageRepaint;

  @override
  Widget build(BuildContext context) {
    final inkController = this.inkController;
    final inkTool = this.inkTool;
    final owner = this.owner;
    final windows = owner == null || inkController == null
        ? const <SheetInkWindow>[]
        : envelopeInkWindows(layout, owner);
    final inking = inkController != null && inkTool != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        // ONE gate, read by both the input layer and the painter: a box
        // whose window is mounted draws itself, and every other box's
        // saved ink is baked by the painter.
        final mounted = inking
            ? mountedEnvelopeInkWindows(windows, viewport, constraints.biggest)
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
          imageFor: imageFor,
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
                  // A landed logo — nothing the painter compares changes
                  // for it.
                  SheetStratum.content: painterOf(
                    SheetStratum.content,
                    repaint: imageRepaint,
                  ),
                  // The ink, and a landed decode of a photo it holds
                  // (I-97).
                  if (inkController != null)
                    SheetStratum.ink: painterOf(
                      SheetStratum.ink,
                      repaint: Listenable.merge([inkController, imageRepaint]),
                    ),
                },
                liveNow: (stratum) =>
                    stratum == SheetStratum.ink && strokeHold.value,
                liveChanges: strokeHold,
              ),
            ),
            // Under the ink windows: reachable exactly when the brush is off
            // (the switch doubles as the edit-mode switch), as on the
            // timesheet. A bare form has no cut to name a worker on.
            if (owner != null)
              Positioned.fill(
                child: CutEnvelopeEditLayer(
                  key: const ValueKey<String>('cut-envelope-edit-layer'),
                  layout: layout,
                  source: source,
                  viewport: viewport,
                  onStaffNamed: (stage, name) =>
                      session.cutVerbs.setCutStaffName(owner, stage, name),
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
                  brushToolState: inkTool,
                  historyManager: session.historyManager,
                  viewport: viewport,
                  strokeActive: strokeHold,
                  cacheInvalidationSink: cacheInvalidationSink,
                  imageFor: imageFor,
                  imageRepaint: imageRepaint,
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
                  cacheInvalidationSink: cacheInvalidationSink,
                ),
              ),
          ],
        );
      },
    );
  }
}
