import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/timesheet_info.dart' show TimesheetHeaderField;
import '../sheet/sheet_text_edit_layer.dart';
import '../text/app_face.dart';
import 'timesheet_document_painter.dart';

/// Tap-to-edit on the sheet: each page's Direction memo band, and the name
/// box of its header — the timesheet's targets for [SheetTextEditLayer],
/// the one in-place editor the sheets share.
///
/// ⛔The other header boxes are printed, not edited. 유저 09-25: 「작품명/
/// 화수는 이제 타임시트패널같은곳에서 편집안하게. 작업자든 뭐든. 해당 설정은
/// 프로젝트 설정쪽에」 — the title and the episode are the work's, set in its
/// settings; the scene is the pen's until the conte groups cuts into
/// scenes.
///
/// 🗣️I-112 (유저 2026-10-19): 「타임시트 용지패널, 원화 이름 클릭해서
/// 변경가능하게. 변경한게 러프원화 스태프 이름에 연동? 아무튼 결과적으로
/// 그런느낌. 동기화되있는듯한?」 — the name box prints the cut's 러프원화
/// worker (F-291), so what is typed into it is that worker's name on the
/// cut: ONE name, which 컷 설정 shows too. ↩️09-25 printed it unedited.
class TimesheetHeaderEditLayer extends StatelessWidget {
  const TimesheetHeaderEditLayer({
    super.key,
    required this.layout,
    required this.viewport,
    required this.onMemoCommitted,
    required this.onNameCommitted,
  });

  final TimesheetDocumentLayout layout;

  /// The live panel viewport (the same transform the document painter
  /// applies).
  final CanvasViewport viewport;

  /// Commits the Direction memo edited on page [page].
  final void Function(int page, String memo) onMemoCommitted;

  /// Commits the name typed into a header's name box.
  final ValueChanged<String> onNameCommitted;

  @override
  Widget build(BuildContext context) {
    // The face the sheet prints in — the strata's painter reads the same
    // ambient style.
    final face = appFaceOf(DefaultTextStyle.of(context).style);
    // Every paper page has a memo band, and a memo of its own (F-301).
    return SheetTextEditLayer(
      viewport: viewport,
      fieldKey: 'timesheet-header-edit-field',
      barrierKey: 'timesheet-header-edit-barrier',
      targets: [
        for (final page in layout.pageIndexes) ...[
          SheetTextTarget(
            keyValue: 'timesheet-memo-edit-p$page',
            box: layout.memoBandRect(page),
            textRect: TimesheetDocumentPainter.memoTextRect(
              layout.memoBandRect(page),
            ),
            text: layout.document.memoTextOf(page),
            style: TimesheetDocumentPainter.wordsStyle(
              face,
              fontSize: TimesheetDocumentPainter.memoSize,
            ),
            onCommitted: (memo) => onMemoCommitted(page, memo),
          ),
          for (final box in layout.headerFieldBoxes(page))
            if (box.field == TimesheetHeaderField.name)
              SheetTextTarget(
                keyValue: 'timesheet-name-edit-p$page',
                box: box.rect,
                textRect: TimesheetDocumentPainter.headerValueRect(box.rect),
                text: layout.document.artist,
                style: TimesheetDocumentPainter.wordsStyle(
                  face,
                  fontSize: TimesheetDocumentPainter.headerValueSize,
                  bold: true,
                ),
                form: SheetTextForm.centredLine,
                onCommitted: onNameCommitted,
              ),
        ],
      ],
    );
  }
}
