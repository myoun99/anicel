import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_ink_layer.dart' show SheetInkWindow;
import '../sheet/sheet_strata.dart';
import '../text/app_face.dart';
import '../timeline/timeline_drag_preview.dart' show TimelineDragPreview;
import 'timesheet_document_painter.dart';
import 'timesheet_ink_controller.dart';
import 'timesheet_ink_layer.dart' show timesheetInkWindows;
import 'timesheet_notation.dart';

/// The timesheet through the sheets' one shell ([SheetStrata]): the
/// printed form, the values and the saved ink, each baked on its own.
///
/// The saved ink prints whatever the brush switch says — but for the
/// windows a live brush view is showing ([ink]'s `live`), which stand down
/// so translucent ink never composites twice. ⛔The sheet printed no ink
/// of its own: its writing showed only through the brush's windows, so
/// with the switch off it vanished while the conte's and the envelope's
/// stayed (유저 2026-09-26: 「다 통일해줘. 기능은 어차피 생길수있어」).
class TimesheetStrata extends StatelessWidget {
  const TimesheetStrata({
    super.key,
    required this.layout,
    required this.pagedLayout,
    required this.viewport,
    required this.notation,
    required this.dragPreview,
    required this.cutId,
    required this.stroking,
    this.ink,
  });

  final TimesheetDocumentLayout layout;
  final TimesheetDocumentLayout pagedLayout;

  /// The panel's pan/zoom.
  final CanvasViewport viewport;

  /// The sheet prints in the NOTATION language (UI-R10 #7).
  final TimesheetNotation notation;

  /// The session's drag channel: the values follow a drag through it.
  final ValueListenable<TimelineDragPreview?> dragPreview;

  /// Which cut the sheet is printing, so a cut-length drag on it can be
  /// read off the channel: the red cut-end line is DATA, and it was the one
  /// data line still printing the committed length while the cells beside
  /// it already previewed.
  final CutId cutId;

  /// Raised while a stroke is in progress on the sheet.
  final ValueListenable<bool> stroking;

  /// The saved ink, and whether the live brush layer is showing its
  /// windows; null prints none.
  final ({TimesheetInkController controller, bool live})? ink;

  @override
  Widget build(BuildContext context) => SheetStrata(
    sheet: 'timesheet',
    painters: _painters(context),
    liveNow: (stratum) => switch (stratum) {
      SheetStratum.content => dragPreview.value != null,
      SheetStratum.ink => stroking.value,
      SheetStratum.form || SheetStratum.picture => false,
    },
    liveChanges: Listenable.merge([dragPreview, stroking]),
  );

  Map<SheetStratum, CustomPainter> _painters(BuildContext context) {
    final face = appFaceOf(DefaultTextStyle.of(context).style);
    // The per-cell text cutoff is a legibility question, so it counts
    // DEVICE pixels. Raising the interface scale used to erase every text
    // while the sheet stayed exactly the same size on screen.
    final ratio = EffectiveDevicePixelRatio.of(context);
    TimesheetDocumentPainter painterOf(
      SheetStratum stratum, {
      ValueListenable<TimelineDragPreview?>? dragPreview,
      List<SheetInkWindow> ink = const [],
      ui.Image? Function(BrushFrameKey key)? inkImageFor,
      Set<BrushFrameKey> liveInkKeys = const {},
      Listenable? inkRepaint,
    }) => TimesheetDocumentPainter(
      document: layout.document,
      layout: layout,
      face: face,
      viewport: viewport,
      effectiveRatio: ratio,
      layers: stratum.layers,
      notation: notation,
      dragPreview: dragPreview,
      cutId: cutId,
      ink: [for (final window in ink) window.mark],
      inkImageFor: inkImageFor,
      liveInkKeys: liveInkKeys,
      inkRepaint: inkRepaint,
    );
    final ink = this.ink;
    // The walk the live brush layer mounts its windows from.
    final windows = ink == null
        ? const <SheetInkWindow>[]
        : timesheetInkWindows(
            layout: layout,
            pagedLayout: pagedLayout,
            cutId: cutId,
          );
    return {
      SheetStratum.form: painterOf(SheetStratum.form),
      SheetStratum.content: painterOf(
        SheetStratum.content,
        dragPreview: dragPreview,
      ),
      if (ink != null)
        SheetStratum.ink: painterOf(
          SheetStratum.ink,
          ink: windows,
          inkImageFor: (key) =>
              ink.controller.displayImageFor(TimesheetInkPlane.of(key), key),
          liveInkKeys: ink.live
              ? {for (final window in windows) window.key}
              : const {},
          inkRepaint: ink.controller,
        ),
    };
  }
}
