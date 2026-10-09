import 'package:flutter/widgets.dart';

import '../../models/camera_instruction.dart' show CameraInstructionDef;
import '../text/vertical_writing_text.dart' show VerticalLatinForm;
import 'timeline_block_word.dart';
import 'timeline_cell_style.dart';

/// The ink a term's span is drawn in — its mark and its name: the colour
/// its [def] carries, or the timeline's drawing ink.
Color timelineInstructionInk(CameraInstructionDef? def) {
  final value = def?.colorValue;
  return value == null ? timelineDrawingInkColor : Color(value);
}

/// How far a span's NAME sits from the wall it aligns to — the top of the
/// row on the timeline, the right of the column on the sheet and in print.
/// Shared so the three surfaces cannot drift apart by a pixel.
const double instructionLabelInset = 1;

/// A word of a span on the CAM rows as a BLOCK word ([TimelineBlockText],
/// [TimelineBlockColumn]): its block is the span, split into the cells
/// [place] names, and the word stays inside it.
///
/// ↩️The writing used to run past the span onto the neighbours' cells
/// (「paper writing spills over neighbours freely」 — mine, 2026-07-09, the
/// paper-block slice) out of a slot that was a FRACTION of the span, so
/// that the span needed nothing from the zoom. It still needs nothing: the
/// block word reads its own box. What changed is the law — 「이름은
/// 블록안에서만」 and 「컷블록의 텍스트든 se텍스트든 뭐든」 (유저
/// 2026-09-24): the writing keeps its type and narrows into the span.
///
/// The writing follows the surface: across the row on the timeline, DOWN
/// the column on the sheet.
///
/// The sheet used to get horizontal text too, and that is what made
/// `FOLLOW PAN` 112px wide in a 28px column — three clip opt-outs above
/// then let it paint straight over the neighbouring layer's cells. A name
/// written down its own column cannot reach the neighbour at all, which is
/// the fix at the root rather than a clip on top.
///
/// Down the column its LETTERS stand up (user, 2026-08-08): writing beside
/// a duration bar is read at a glance, and the printed sheet is set the
/// same way for the same reason.
Widget timelineSpanWord(
  Axis axis,
  String text,
  TextStyle style,
  TimelineBlockWordCells place,
) => ExcludeSemantics(
  child: axis == Axis.horizontal
      ? TimelineBlockText(text: text, style: style, place: place)
      : TimelineBlockColumn(
          text: text,
          style: style,
          latinForm: VerticalLatinForm.upright,
          place: place,
        ),
);

/// THE NAME OF A SPAN — over the span's middle along the frame axis and
/// stepped OFF its line across it (user, 2026-08-08): up on the timeline,
/// right on the sheet. It fills the box it is given, the span.
///
/// An instruction span's name, and the name of the camera's move between
/// two of its keys (I-73 ⑤: 「그림은 지시 행의 구간과 같은 그림」) — one
/// drawing.
///
/// Both used to be dead centre — which is exactly where the mark is, since
/// the instruction mark is drawn about the middle across the row. So a
/// duration line and the word naming it were drawn through each other. The
/// MARK keeps the centre and the writing is what moves, because only one of
/// the two can say where the middle of the span is.
class TimelineSpanName extends StatelessWidget {
  const TimelineSpanName({
    super.key,
    required this.axis,
    required this.text,
    required this.ink,
  });

  final Axis axis;
  final String text;

  /// The span's mark colour — the term's own, or the ink.
  final Color ink;

  @override
  Widget build(BuildContext context) => Padding(
    // A hair off the wall, so the glyphs never sit on the cell border they
    // have just moved next to.
    padding: axis == Axis.horizontal
        ? const EdgeInsets.only(top: instructionLabelInset)
        : const EdgeInsets.only(right: instructionLabelInset),
    child: timelineSpanWord(
      axis,
      text,
      timelineBlockWordStyle(
        DefaultTextStyle.of(context).style,
        ink: ink,
        fontSize: 11,
        bold: true,
      ),
      (
        axis: axis,
        cells: 1,
        cellIndex: 0,
        growth: TimelineBlockWordGrowth.towardBlockEnd,
        acrossAlignment: axis == Axis.horizontal ? -1 : 1,
      ),
    ),
  );
}
