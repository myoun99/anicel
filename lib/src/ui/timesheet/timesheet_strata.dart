import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/timesheet_words.dart';
import '../effective_device_pixel_ratio.dart';
import '../sheet/sheet_image_cache.dart' show SheetImageLookup;
import '../sheet/sheet_strata.dart';
import '../text/app_face.dart';
import '../sliced_value_listenable_builder.dart'
    show SlicedValueListenableScope;
import '../timeline/timeline_drag_preview.dart' show TimelineDragPreview;
import 'timesheet_document_painter.dart';
import 'timesheet_ink_layer.dart' show TimesheetInkScreens;

/// The timesheet through the sheets' one shell ([SheetStrata]): the
/// printed form and the values, each baked on its own. Its saved ink is
/// not a stratum: the engine shows it over them ([TimesheetInkScreens]),
/// the brush switch on or off.
///
/// ⛔The sheet once printed no ink of its own: its writing showed only
/// through the brush's windows, so with the switch off it vanished while
/// the conte's and the envelope's stayed (유저 2026-09-26: 「다
/// 통일해줘. 기능은 어차피 생길수있어」).
class TimesheetStrata extends StatelessWidget {
  const TimesheetStrata({
    super.key,
    required this.layout,
    required this.viewport,
    required this.words,
    required this.dragPreview,
    required this.cutId,
    this.imageFor,
    this.imageRepaint,
  });

  final TimesheetDocumentLayout layout;

  /// The panel's pan/zoom.
  final CanvasViewport viewport;

  /// The words the sheet prints, in the NOTATION language (UI-R10 #7).
  final TimesheetWords words;

  /// The session's drag channel: the values follow a drag through it.
  final ValueListenable<TimelineDragPreview?> dragPreview;

  /// Which cut the sheet is printing, so a cut-length drag on it can be
  /// read off the channel: the red cut-end line is DATA, and it was the one
  /// data line still printing the committed length while the cells beside
  /// it already previewed.
  final CutId cutId;

  /// The pool files the sheet's pictures are drawn from — an XDTS sheet's
  /// logo (I-162-Q5) — and what says one has landed.
  final SheetImageLookup? imageFor;
  final Listenable? imageRepaint;

  /// What says a picture the values print has landed: where the sheet
  /// prints a logo ([TimesheetDocument.printedLogo]), the pictures'; where
  /// it prints none, nothing — the values stay baked.
  Listenable? get _valuesHear =>
      layout.document.printedLogo == null ? null : imageRepaint;

  /// What the content stratum PRINTS of a drag over the view of [shown]
  /// ([timesheetDragPrint]).
  Object _printOf(TimelineDragPreview? preview, Rect? shown) =>
      timesheetDragPrint(
        document: layout.document,
        layout: layout,
        shown: shown,
        cutId: cutId,
        preview: preview,
      );

  /// The channel is handed on SLICED to what the values print: the content
  /// painter repaints, and its bake stands down, only while a drag
  /// re-prints something on screen.
  ///
  /// 🚨sheet-prints-only-its-drags: both listened to the channel whole, so
  /// a lane value scrubbed on the timeline repainted the sheet every step —
  /// and being "live" for any drag in flight, the sheet paid a full paint a
  /// step for values it prints the same.
  ///
  /// The print is of the view the strata paint ([timesheetShown] of the
  /// box they fill), so a pan or a resize — a build from above or a new
  /// box — prints afresh.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final shown = timesheetShown(viewport, box.biggest);
      return SlicedValueListenableScope<TimelineDragPreview?, Object>(
        valueListenable: dragPreview,
        slice: (preview) => _printOf(preview, shown),
        builder: (context, printed) {
          final committed = _printOf(null, shown);
          return SheetStrata(
            sheet: 'timesheet',
            painters: _painters(context, printed),
            liveNow: (stratum) =>
                stratum == SheetStratum.content &&
                printed.slice != committed,
            liveChanges: printed,
          );
        },
      );
    },
  );

  Map<SheetStratum, CustomPainter> _painters(
    BuildContext context,
    ValueListenable<TimelineDragPreview?> printed,
  ) {
    final face = appFaceOf(DefaultTextStyle.of(context).style);
    // The per-cell text cutoff is a legibility question, so it counts
    // DEVICE pixels. Raising the interface scale used to erase every text
    // while the sheet stayed exactly the same size on screen.
    final ratio = EffectiveDevicePixelRatio.of(context);
    TimesheetDocumentPainter painterOf(
      SheetStratum stratum, {
      ValueListenable<TimelineDragPreview?>? dragPreview,
      Listenable? imageRepaint,
    }) => TimesheetDocumentPainter(
      document: layout.document,
      layout: layout,
      face: face,
      viewport: viewport,
      effectiveRatio: ratio,
      layers: stratum.layers,
      words: words,
      dragPreview: dragPreview,
      cutId: cutId,
      imageFor: imageFor,
      imageRepaint: imageRepaint,
    );
    return {
      SheetStratum.form: painterOf(SheetStratum.form),
      // The values print a picture too, where the sheet prints a logo.
      SheetStratum.content: painterOf(
        SheetStratum.content,
        dragPreview: printed,
        imageRepaint: _valuesHear,
      ),
    };
  }
}
