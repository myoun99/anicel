import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/timesheet_info.dart';
import '../sheet/sheet_text_edit_layer.dart';
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

  /// The sheet's ink (`TimesheetDocumentPainter`'s).
  static const Color _ink = Color(0xFF33322F);

  @override
  Widget build(BuildContext context) {
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
                // Header values print CENTERED at y top+26 @14 w600 (R7-⑥
                // reference layout) — the field lands on those glyphs.
                textRect: Rect.fromLTRB(
                  box.rect.left + 6,
                  box.rect.top + 26,
                  box.rect.right - 6,
                  box.rect.bottom - 4,
                ),
                text: text,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                centred: true,
                onCommitted: (text) => onHeaderFieldCommitted(box.field, text),
              ),
          SheetTextTarget(
            keyValue: 'timesheet-memo-edit-p$page',
            box: layout.memoBandRect(page),
            // The memo prints top-left at (left+8, top+6) @11 over the full
            // open band (the framed memo box is retired — R7-⑥).
            textRect: Rect.fromLTRB(
              layout.memoBandRect(page).left + 8,
              layout.memoBandRect(page).top + 6,
              layout.memoBandRect(page).right - 8,
              layout.memoBandRect(page).bottom - 6,
            ),
            text: layout.document.memoText,
            style: const TextStyle(color: _ink, fontSize: 11),
            multiline: true,
            onCommitted: onMemoCommitted,
          ),
        ],
      ],
    );
  }
}
