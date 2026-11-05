part of '../timesheet_document_painter.dart';

/// How a word is set in its box: [size] large in [color], [across] the box
/// — and on its middle, or from its top.
typedef _XdtsWordsSet = ({
  double size,
  Color color,
  TextAlign across,
  bool middle,
});

/// AN XDTS SHEET'S PAGE IN THE VIEWER'S OWN PIXELS (I-162, 유저 2026-11-05:
/// 「서식 바꾸면 xdts의 해당 서식에서 보는거랑 똑같은 화면」) — where its form
/// ([_XdtsFormPass]), the values the viewer writes into it
/// ([_XdtsCountsPass]), the O.L it draws ([_XdtsOverlapPass]) and the
/// logo it prints ([_XdtsLogoPass]) are drawn, and how the words are set
/// there.
///
/// 🚨Everything drawn on it is measured in the 250dpi whole pixels
/// [XdtsSheetForm] lays the page in, and the page is scaled to the sheet's
/// units once ([_XdtsSheetForm.unit]) — so a line lands where the viewer's
/// does, its pens two and five pixels wide.
///
/// ⛔The viewer's code is not ours to copy (BSD-3): what is kept is where
/// it draws and how large, read off its form; the drawing is our own.
///
/// ⚠️Mine: the form's words are the viewer's Japanese — its own language
/// by default, and the one these four sheets are made in (Ponoc's is a
/// Japanese studio's). Our notation language has no XDTS form to print in:
/// the viewer has Japanese and English only. Every word is set in the
/// app's face (documents-in-which-face-Q1), not the viewer's MS Gothic.
class _XdtsPage {
  _XdtsPage(this._painter, this.sheet);

  final TimesheetDocumentPainter _painter;
  final _XdtsSheetForm sheet;

  XdtsSheetForm get form => sheet.form;

  late final _XdtsFormPass formPass = _XdtsFormPass(this);
  late final _XdtsCountsPass counts = _XdtsCountsPass(this);
  late final _XdtsOverlapPass overlaps = _XdtsOverlapPass(this);
  late final _XdtsLogoPass logo = _XdtsLogoPass(this);
  late final _XdtsNotationPass notation = _XdtsNotationPass(this);

  /// The viewer's line colour, which its form's words are printed in too.
  static const Color line = Color(0xFF9CC862);

  static int px(double mm) => XdtsSheetForm.px(mm);

  /// Runs [draw] in page [pageIndex]'s pixels.
  void on(Canvas canvas, int pageIndex, void Function() draw) {
    final page = _painter.layout.pageRect(pageIndex);
    canvas
      ..save()
      ..translate(page.left, page.top)
      ..scale(sheet.unit);
    draw();
    canvas.restore();
  }

  /// The row a header box's value is written in, under its label.
  XdtsPixelRect valueBox(XdtsInfoPlace place) => (
    left: place.left,
    top: form.infoTitleBottom,
    width: place.width,
    height: form.infoBottom - form.infoTitleBottom,
  );

  /// The largest size up to [start] that sets [text] within [room] across
  /// — the sheet's one shrinking law ([sheetWordsSize]).
  double shrunk(String text, {required double start, required double room}) =>
      sheetWordsSize(
        SheetWords(
          SheetPaintLayer.form,
          text: text,
          slot: Rect.fromLTWH(0, 0, room, start),
          size: start,
          argb: line.toARGB32(),
          fit: SheetWordsFit.shrink,
        ),
        (size, {required bold, required color}) =>
            TimesheetDocumentPainter.wordsStyle(
              _painter.face,
              fontSize: size,
              color: color,
              bold: bold,
            ),
      );

  /// [shrunk], but never below the viewer's floor for a box's words.
  double fitSize(String text, {required double start, required double room}) =>
      math.max(shrunk(text, start: start, room: room), px(2).toDouble());

  /// The size a header box's marks are set at — the length's 秒 · コマ · ＋,
  /// the sheet count's 枚 · 枚目: from half the box's height less a
  /// millimetre, down until [word] stands within a [share]th of its width.
  double markSize(XdtsPixelRect box, String word, int share) => fitSize(
    word,
    start: (box.height ~/ 2 - px(1)).toDouble(),
    room: box.width / share,
  );

  /// A value as the viewer fits it: from its box's height down, until it
  /// stands within the box less a margin — on the box's middle.
  void fitted(Canvas canvas, String text, Rect box, TextAlign across) => words(
    canvas,
    text,
    box,
    (
      size: fitSize(text, start: box.height - px(0.5), room: box.width - px(1)),
      color: TimesheetDocumentPainter._ink,
      across: across,
      middle: true,
    ),
  );

  /// [text] set in [box] as [set] says.
  void words(Canvas canvas, String text, Rect box, _XdtsWordsSet set) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TimesheetDocumentPainter.wordsStyle(
          _painter.face,
          fontSize: set.size,
          color: set.color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final x = switch (set.across) {
      TextAlign.right || TextAlign.end => box.right - painter.width,
      TextAlign.center => box.center.dx - painter.width / 2,
      _ => box.left,
    };
    final y = set.middle ? box.center.dy - painter.height / 2 : box.top;
    painter
      ..paint(canvas, Offset(x, y))
      ..dispose();
  }

  /// A block's or a box's name spread over [box] as the viewer spreads it:
  /// its letters a letter's width apart — or two, where the box has room —
  /// centred; too tight for either, set as it is.
  void spread(Canvas canvas, String text, Rect box, {required double size}) {
    final style = TimesheetDocumentPainter.wordsStyle(
      _painter.face,
      fontSize: size,
      color: line,
    );
    TextPainter set(String letters) => TextPainter(
      text: TextSpan(text: letters, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final glyphs = [for (final letter in text.characters) set(letter)];
    final step = set('A');
    final gap = step.width;
    step.dispose();
    var natural = 0.0;
    for (final glyph in glyphs) {
      natural += glyph.width;
    }
    final gaps = glyphs.length - 1;
    final once = natural + gap * gaps;
    final twice = natural + 2 * gap * gaps;
    final spread = gaps <= 0 || box.width - 2 * gap <= once
        ? natural
        : box.width - 4 * gap > twice
        ? twice
        : once;
    final between = gaps <= 0 ? 0.0 : (spread - natural) / gaps;
    var x = box.center.dx - spread / 2;
    for (final glyph in glyphs) {
      glyph.paint(canvas, Offset(x, box.center.dy - glyph.height / 2));
      x += glyph.width + between;
      glyph.dispose();
    }
  }
}
