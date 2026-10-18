import 'package:flutter/material.dart';

import '../../models/se_name_tag.dart';
import '../../models/text_cel_style.dart';
import 'axis_turn.dart'
    show extentAcross, extentAlong, readableText, rectAlong;

/// The name tag's live PREVIEW on its group header (R5 #7): the box, and
/// the dialogue beside it, in miniature.
///
/// It shows the LOOK, never the content — the strings are fixed (`名前` /
/// `セリフ`, localized), so the preview says the same thing wherever the
/// playhead parks and never asks what a block happens to contain. The user
/// settled that: "프리뷰는 그냥 어떤식으로 될지 확인만 하는거니까".
class SeNameTagLanePreview extends StatelessWidget {
  const SeNameTagLanePreview({
    super.key,
    required this.name,
    required this.line,
    this.tag = const SeNameTag(),
    this.axis = Axis.horizontal,
  });

  final String name;

  /// The dialogue sample; empty draws none, which is what the Show
  /// Dialogue member turning off looks like.
  final String line;

  /// The RESOLVED tag whose look is being previewed.
  final SeNameTag tag;

  /// The way the preview reads: along the rail's row, or DOWN the sheet's
  /// column, where it is written as the sheet's other words are
  /// ([readableText]) — 🗣️xsheet-s-row-name-tag-overflow-Q1 (유저
  /// 2026-09-29): 「세로쓰기 — 시트의 다른 글자처럼」. ↩️It stayed one line
  /// across the sheet's 23px column and ran 27px past it.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final box = tag.style.backgroundColor;
    final horizontal = axis == Axis.horizontal;
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // The box keeps its shape at every size: the rail row is 24px tall
        // and the tag's real fontSize is 34, so this is a SILHOUETTE, not a
        // scaled render — matching the on-canvas metrics here would just
        // clip.
        DecoratedBox(
          decoration: BoxDecoration(
            color: box == null ? null : Color(box),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Padding(
            // 3 along the writing, 1 across it.
            padding: horizontal
                ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1)
                : const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
            child: _lined(
              tag.style,
              horizontal
                  ? Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: _styleOf(tag.style),
                    )
                  : readableText(axis, name, style: _styleOf(tag.style)),
            ),
          ),
        ),
        if (line.isNotEmpty) ...[
          if (horizontal)
            const SizedBox(width: 3)
          else
            const SizedBox(height: 3),
          Flexible(
            child: _lined(
              tag.lineStyle,
              horizontal
                  ? Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _styleOf(tag.lineStyle),
                    )
                  : readableText(axis, line, style: _styleOf(tag.lineStyle)),
            ),
          ),
        ],
      ],
    );
  }

  /// [run], a run of the preview's letters in [style], with the lines they
  /// wear drawn over it ([SeNameTagPreviewLines]).
  Widget _lined(TextCelStyle style, Widget run) => CustomPaint(
    foregroundPainter: SeNameTagPreviewLines(style: style, axis: axis),
    child: run,
  );

  /// [style]'s look at the rail's type size.
  static TextStyle _styleOf(TextCelStyle style) => TextStyle(
    fontSize: 10,
    height: 1.1,
    fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: style.letterSpacing == 0 ? null : style.letterSpacing / 4,
    color: Color(style.color),
  );
}

/// The lines a run of the preview's letters wears — under them, or beside
/// them down a column, and through them — over the run's own box.
///
/// A SILHOUETTE's lines, as its letters are one: where the canvas puts them
/// — under a line of letters, on a column's RIGHT (傍線, as
/// `cel_text_columns.dart` sets it), and through the middle — a pixel
/// thick, not at the face's own numbers.
class SeNameTagPreviewLines extends CustomPainter {
  const SeNameTagPreviewLines({required this.style, required this.axis});

  final TextCelStyle style;
  final Axis axis;

  static const double _thickness = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Color(style.color);
    final room = extentAcross(axis, size) - _thickness;
    // A line all along the run, [share] of the way across it.
    void lineAt(double share) => canvas.drawRect(
      rectAlong(
        axis,
        along: (from: 0, to: extentAlong(axis, size)),
        across: (from: room * share, to: room * share + _thickness),
      ),
      paint,
    );
    if (style.underline) {
      lineAt(1);
    }
    if (style.strikethrough) {
      lineAt(0.5);
    }
  }

  @override
  bool shouldRepaint(SeNameTagPreviewLines oldDelegate) =>
      oldDelegate.style != style || oldDelegate.axis != axis;
}
