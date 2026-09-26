import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/timesheet_info.dart';
import '../sheet/sheet_text_edit_layer.dart';
import '../text/app_face.dart';
import 'timesheet_document_painter.dart';

/// Tap-to-edit for the sheet's typed header text: the TimesheetInfo-backed
/// header boxes (Ep.no / Title / Scene / Name) and the Direction memo band
/// (the per-cut note) — the timesheet's targets for [SheetTextEditLayer],
/// the one in-place editor the sheets share.
///
/// Derived boxes (CUT / TIME / SHEET) stay read-only.
class TimesheetHeaderEditLayer extends StatelessWidget {
  const TimesheetHeaderEditLayer({
    super.key,
    required this.layout,
    required this.viewport,
    required this.onHeaderFieldCommitted,
    required this.onMemoCommitted,
  });

  final TimesheetDocumentLayout layout;

  /// The live panel viewport (the same transform the document painter
  /// applies).
  final CanvasViewport viewport;

  /// Commits an edited header box (editable fields only) — only when the
  /// text changed.
  final void Function(TimesheetHeaderField field, String text)
  onHeaderFieldCommitted;

  /// Commits the edited Direction memo (the cut note).
  final ValueChanged<String> onMemoCommitted;

  @override
  Widget build(BuildContext context) {
    // The face the sheet prints in — the strata's painter reads the same
    // ambient style.
    final face = appFaceOf(DefaultTextStyle.of(context).style);
    // The header repeats on every paper page; the continuous strip has
    // one, and page view (R26 #41) shows one at a time.
    return SheetTextEditLayer(
      viewport: viewport,
      fieldKey: 'timesheet-header-edit-field',
      barrierKey: 'timesheet-header-edit-barrier',
      targets: [
        for (final page in layout.visiblePageIndexes) ...[
          for (final box in layout.headerFieldBoxes(page))
            // A typed box is the one a tap edits: its text lives on
            // [TimesheetInfo].
            if (layout.document.typedHeaderValue(box.field) case final text?)
              SheetTextTarget(
                keyValue: 'timesheet-header-edit-${box.field.name}-p$page',
                box: box.rect,
                textRect: TimesheetDocumentPainter.headerValueRect(box.rect),
                text: text,
                style: TimesheetDocumentPainter.wordsStyle(
                  face,
                  fontSize: TimesheetDocumentPainter.headerValueSize,
                  bold: true,
                ),
                centred: true,
                onCommitted: (text) => onHeaderFieldCommitted(box.field, text),
              ),
          SheetTextTarget(
            keyValue: 'timesheet-memo-edit-p$page',
            box: layout.memoBandRect(page),
            textRect: TimesheetDocumentPainter.memoTextRect(
              layout.memoBandRect(page),
            ),
            text: layout.document.memoText,
            style: TimesheetDocumentPainter.wordsStyle(
              face,
              fontSize: TimesheetDocumentPainter.memoSize,
            ),
            multiline: true,
            onCommitted: onMemoCommitted,
          ),
        ],
      ],
    );
  }
}
