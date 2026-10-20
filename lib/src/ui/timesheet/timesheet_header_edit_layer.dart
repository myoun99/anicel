import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/timesheet_info.dart' show TimesheetHeaderField;
import '../sheet/sheet_text_edit_layer.dart';
import '../text/app_face.dart';
import 'timesheet_document_painter.dart';

/// Tap-to-edit on the sheet: each page's Direction memo band, and every
/// header box [headerCommits] gives a road — the timesheet's targets for
/// [SheetTextEditLayer], the one in-place editor the sheets share.
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
///
/// 🗣️I-112 (유저 2026-10-21): 「추가로 화수,타이틀,신,이름 등 다른
/// 변경가능한것도 변경가능하게. 타임은 안하는게 나을듯. 페이지도 자동이고.
/// 타이틀 바꾸면 다른곳에도 반영되는거 인지하고있음. 화수도 마찬가지.」 —
/// the episode and the title are typed into the work's own values, the
/// ones its settings show and every paper prints; the cut box is the cut's
/// name. The length and the page stay counted. ↩️09-25 kept the work's
/// two in its settings alone.
class TimesheetHeaderEditLayer extends StatelessWidget {
  const TimesheetHeaderEditLayer({
    super.key,
    required this.layout,
    required this.viewport,
    required this.onMemoCommitted,
    required this.headerCommits,
  });

  final TimesheetDocumentLayout layout;

  /// The live panel viewport (the same transform the document painter
  /// applies).
  final CanvasViewport viewport;

  /// Commits the Direction memo edited on page [page].
  final void Function(int page, String memo) onMemoCommitted;

  /// Where the words typed into a header box land, by its field. A box
  /// with no road here prints only.
  final Map<TimesheetHeaderField, ValueChanged<String>> headerCommits;

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
            if ((
                  headerCommits[box.field],
                  layout.typedHeaderValue(box.field),
                )
                case (final commit?, final printed?))
              SheetTextTarget(
                keyValue: 'timesheet-${box.field.name}-edit-p$page',
                box: box.rect,
                textRect: TimesheetDocumentPainter.headerValueRect(box.rect),
                text: printed,
                style: TimesheetDocumentPainter.wordsStyle(
                  face,
                  fontSize: TimesheetDocumentPainter.headerValueSize,
                  bold: true,
                ),
                form: SheetTextForm.centredLine,
                onCommitted: commit,
              ),
        ],
      ],
    );
  }
}
