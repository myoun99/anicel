import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../sheet/sheet_text_edit_layer.dart';
import '../text/app_face.dart';
import 'timesheet_document_painter.dart';

/// Tap-to-edit for the sheet's Direction memo band (the per-cut note) —
/// the timesheet's target for [SheetTextEditLayer], the one in-place
/// editor the sheets share.
///
/// ⛔The header boxes are printed, not edited. 유저 09-25: 「작품명/화수는
/// 이제 타임시트패널같은곳에서 편집안하게. 작업자든 뭐든. 해당 설정은
/// 프로젝트 설정쪽에」 — the title and the episode are the work's, set in
/// its settings; the 作業者 is the cut's 원화 worker; the scene is the
/// pen's until the conte groups cuts into scenes.
class TimesheetHeaderEditLayer extends StatelessWidget {
  const TimesheetHeaderEditLayer({
    super.key,
    required this.layout,
    required this.viewport,
    required this.onMemoCommitted,
  });

  final TimesheetDocumentLayout layout;

  /// The live panel viewport (the same transform the document painter
  /// applies).
  final CanvasViewport viewport;

  /// Commits the edited Direction memo (the cut note).
  final ValueChanged<String> onMemoCommitted;

  @override
  Widget build(BuildContext context) {
    // The face the sheet prints in — the strata's painter reads the same
    // ambient style.
    final face = appFaceOf(DefaultTextStyle.of(context).style);
    // The memo band repeats on every paper page; the continuous strip has
    // one, and page view (R26 #41) shows one at a time.
    return SheetTextEditLayer(
      viewport: viewport,
      fieldKey: 'timesheet-header-edit-field',
      barrierKey: 'timesheet-header-edit-barrier',
      targets: [
        for (final page in layout.visiblePageIndexes)
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
            onCommitted: onMemoCommitted,
          ),
      ],
    );
  }
}
