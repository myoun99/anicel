part of '../timesheet_document_painter.dart';

/// THE BOOKS PASS — the tags a sheet marks its books with (D24 후반): one
/// over each boundary of the cel columns a book lies at, on every half the
/// page prints, a leader line down to the grid.
///
/// 🗣️유저 2026-09-25 (사진 셋, TOEI_book · TOEI_book_all · TOEI_3sec):
/// 「북은 … 해당 위치에 해당하는 북(우리로 치면 이미지레이어)을 셀 사이에
/// 끼워넣는거야. 형식은 지금 우리가 만든 형식」. Where the tags stand is the
/// layout's ([TimesheetDocumentLayout.bookTags]).
class _TimesheetBooksPass {
  _TimesheetBooksPass(this._painter);

  final TimesheetDocumentPainter _painter;

  /// The tag's fill: the reference sheets' blue, measured off the user's
  /// photo — the tag's dominant colour in TOEI_book.jpg averages
  /// 65·105·227, royal blue — under white words.
  static const Color _fill = Color(0xFF4169E1);
  static const Color _words = Color(0xFFFFFFFF);

  /// The run from the leader line into the tag, and the tag's side padding.
  static const double _tick = 4;
  static const double _padding = 3;

  void paintHalf(Canvas canvas, {required int pageIndex, required int half}) {
    final layout = _painter.layout;
    final tags = layout.bookTags(pageIndex, half);
    if (tags.isEmpty) {
      return;
    }
    const height = TimesheetDocumentLayout.bookTagHeight;
    final gridTop = layout.gridTop(pageIndex);
    final line = Paint()
      ..color = TimesheetDocumentPainter._ink
      ..strokeWidth = 0.8;
    final fill = Paint()..color = _fill;
    for (final tag in tags) {
      final words = TextPainter(
        text: TextSpan(
          text: tag.label,
          style: TimesheetDocumentPainter.wordsStyle(
            _painter.face,
            fontSize: TimesheetDocumentLayout.bookTagFontSize,
            color: _words,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final top = tag.bottom - height;
      final middle = top + height / 2;
      final box = Rect.fromLTWH(
        tag.x + _tick,
        top,
        words.width + _padding * 2,
        height,
      );
      canvas.drawLine(Offset(tag.x, middle), Offset(tag.x, gridTop), line);
      canvas.drawLine(Offset(tag.x, middle), Offset(box.left, middle), line);
      canvas.drawRect(box, fill);
      words.paint(
        canvas,
        Offset(box.left + _padding, top + (height - words.height) / 2),
      );
    }
  }
}
