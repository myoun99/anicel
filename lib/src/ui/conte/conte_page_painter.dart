import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';

/// The conte sheet's ONE renderer.
///
/// The panel draws it, the PNG export draws it into a recorder and the PDF
/// export walks the same layout for its vectors and text runs. There is no
/// second sheet layout anywhere — the timesheet export settled that
/// argument ("the output is the panel's picture") and the conte inherits
/// it, which is also why the page geometry lives in a pure model.
///
/// The paper is WHITE and the ink is black whatever the app theme is: this
/// is a printed page shown on a screen, not a panel.
class ContePagePainter extends CustomPainter {
  const ContePagePainter({
    required this.page,
    required this.source,
    this.pictureFor,
    this.selectedCell,
    this.showPaper = true,
  });

  final ContePageLayout page;
  final ConteSheetSource source;

  /// The finished composite for a cell, or null while it renders (the cell
  /// prints its rules and text either way — a conte with no pictures yet is
  /// still a conte).
  final ui.Image? Function(String cutId, int pictureFrame)? pictureFor;

  /// `(cutId, cellIndex)` of the cell under edit, for the panel's outline.
  /// Null in an export, which has nothing selected.
  final (String, int)? selectedCell;

  /// False when the page is drawn onto paper that already exists (the PDF's
  /// own page), so the white fill is not painted twice.
  final bool showPaper;

  ConteSheetMetrics get metrics => page.metrics;

  static const Color _ink = Color(0xFF101010);
  static const Color _rule = Color(0xFF404040);

  /// The picture cell's heavy silhouette border — the Ghibli-conte look the
  /// design asks for, and the thing that makes the picture read as a frame
  /// rather than as a table cell.
  static const double _pictureBorderWidth = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / metrics.pageWidth,
      size.height / metrics.pageHeight,
    );
    canvas.save();
    canvas.scale(scale);
    _paintPage(canvas);
    canvas.restore();
  }

  void _paintPage(Canvas canvas) {
    if (showPaper) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    _paintHeader(canvas);
    _paintGrid(canvas);
    for (final band in page.cutBands) {
      _paintCutBand(canvas, band);
    }
    for (final cell in page.cells) {
      _paintCell(canvas, cell);
    }
    _paintHole(canvas);
    _paintFooter(canvas);
  }

  // ---- header / footer -------------------------------------------------

  void _paintHeader(Canvas canvas) {
    final left = [
      if (source.title.isNotEmpty) source.title,
      if (source.episode.isNotEmpty) source.episode,
    ].join('  ');
    _text(
      canvas,
      left,
      Rect.fromLTRB(
        metrics.bodyLeft,
        metrics.margin,
        metrics.bodyRight - 80,
        metrics.bodyTop,
      ),
      _style(12, bold: true),
    );
    _text(
      canvas,
      '${page.pageIndex + 1}',
      Rect.fromLTRB(
        metrics.bodyRight - 80,
        metrics.margin,
        metrics.bodyRight,
        metrics.bodyTop,
      ),
      _style(12),
      alignRight: true,
    );
  }

  void _paintFooter(Canvas canvas) {
    _text(
      canvas,
      page.pageTotalLabel,
      Rect.fromLTRB(
        metrics.timeLeft,
        metrics.bodyBottom,
        metrics.bodyRight,
        metrics.pageHeight - metrics.margin / 2,
      ),
      _style(9, bold: true),
      alignRight: true,
    );
  }

  // ---- rules -----------------------------------------------------------

  void _paintGrid(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _rule;
    final body = Rect.fromLTRB(
      metrics.bodyLeft,
      metrics.bodyTop,
      metrics.bodyRight,
      metrics.bodyBottom,
    );
    canvas.drawRect(body, paint);
    for (final x in [
      metrics.pictureLeft,
      metrics.actionLeft,
      metrics.dialogueLeft,
      metrics.timeLeft,
    ]) {
      canvas.drawLine(
        Offset(x, metrics.bodyTop),
        Offset(x, metrics.bodyBottom),
        paint,
      );
    }
    // Horizontal rules run through the CUT and TIME columns only — never
    // through the text ones, which are a continuous band by design, and
    // never through the PICTURE column, whose cells draw their own heavy
    // border wherever they actually start.
    for (var row = 1; row < metrics.rowsPerPage; row += 1) {
      final y = metrics.rowTop(row);
      canvas.drawLine(
        Offset(metrics.cutColumnLeft, y),
        Offset(metrics.pictureLeft, y),
        paint,
      );
      canvas.drawLine(
        Offset(metrics.timeLeft, y),
        Offset(metrics.bodyRight, y),
        paint,
      );
    }
  }

  void _paintCutBand(Canvas canvas, ContePlacedCutBand band) {
    final heavy = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = _ink;
    // The merge is what the box says: one cut, one box, however many cells
    // it holds. Drawing it OVER the row rules is what erases them inside.
    canvas.drawRect(band.cutRect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(band.timeRect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(band.cutRect, heavy);
    canvas.drawRect(band.timeRect, heavy);
    if (band.showsNumber) {
      // Number TOP-LEFT, length BOTTOM-RIGHT: the diagonal the paper sheet
      // uses, and the same one the panel's cut block copies in its bands.
      _text(
        canvas,
        band.cutName,
        band.cutRect.deflate(3),
        _style(10, bold: true),
      );
    }
    if (band.showsLength) {
      _text(
        canvas,
        band.lengthLabel,
        band.timeRect.deflate(3),
        _style(10),
        alignRight: true,
        alignBottom: true,
      );
    }
  }

  // ---- cells -----------------------------------------------------------

  void _paintCell(Canvas canvas, ContePlacedCell cell) {
    final picture = cell.pictureRect;
    if (picture.width > 0 && picture.height > 0) {
      canvas.save();
      canvas.clipRect(picture);
      final image = pictureFor?.call(cell.cutId, cell.source.pictureFrame);
      if (image != null) {
        _paintPicture(canvas, image, picture.deflate(_pictureBorderWidth));
      }
      canvas.restore();
      canvas.drawRect(
        picture.deflate(_pictureBorderWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _pictureBorderWidth
          ..color = _ink,
      );
      _paintCameraLabels(canvas, cell, picture);
      if (selectedCell == (cell.cutId, cell.cellIndex)) {
        canvas.drawRect(
          picture.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF2A6FF0),
        );
      }
    }
    _text(canvas, cell.source.action, cell.actionRect.deflate(4), _style(9));
    _text(canvas, _dialogueFor(cell), cell.dialogueRect.deflate(4), _style(9));
  }

  /// The lines that START in this cell's span. Dialogue is the SE blocks'
  /// (design G), so a cell prints whatever was said while it was on screen.
  String _dialogueFor(ContePlacedCell cell) {
    for (final cut in source.cuts) {
      if (cut.cutId.value != cell.cutId) {
        continue;
      }
      return [
        for (final line in cut.dialogue)
          if (line.startFrame >= cell.source.startFrame &&
              line.startFrame < cell.source.endFrameExclusive)
            line.printed,
      ].join('\n');
    }
    return '';
  }

  void _paintPicture(Canvas canvas, ui.Image image, Rect slot) {
    if (slot.width <= 0 || slot.height <= 0) {
      return;
    }
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final scale = math.min(
      slot.width / source.width,
      slot.height / source.height,
    );
    final drawn = Size(source.width * scale, source.height * scale);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(
        slot.left + (slot.width - drawn.width) / 2,
        slot.top + (slot.height - drawn.height) / 2,
        drawn.width,
        drawn.height,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// The camera's frame labels, printed at the picture's corners. The
  /// keyframe NAMES are the truth (design); IN/OUT is what the source hands
  /// over when a key has no name of its own.
  void _paintCameraLabels(Canvas canvas, ContePlacedCell cell, Rect picture) {
    final labels = cell.source.cameraLabels;
    if (labels.isEmpty) {
      return;
    }
    _text(canvas, labels.first, picture.deflate(5), _style(8, bold: true));
    if (labels.length > 1) {
      _text(
        canvas,
        labels.last,
        picture.deflate(5),
        _style(8, bold: true),
        alignRight: true,
        alignBottom: true,
      );
    }
  }

  /// The hole a page break leaves: ONE big X across the rows nothing could
  /// be placed on. Paper says "deliberately empty" with a stroke.
  void _paintHole(Canvas canvas) {
    final from = page.emptyRowsFrom;
    if (from == null || from >= metrics.rowsPerPage) {
      return;
    }
    final hole = Rect.fromLTRB(
      metrics.pictureLeft,
      metrics.rowTop(from),
      metrics.timeLeft,
      metrics.bodyBottom,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _rule;
    canvas.drawLine(hole.topLeft, hole.bottomRight, paint);
    canvas.drawLine(hole.topRight, hole.bottomLeft, paint);
  }

  // ---- text ------------------------------------------------------------

  TextStyle _style(double size, {bool bold = false}) => TextStyle(
    color: _ink,
    fontSize: size,
    height: 1.25,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  );

  /// Lays text into [slot], shrinking a step at a time before it clips.
  ///
  /// [TextPainter] is the layout TRUTH here (design): the PDF emits the
  /// LINES this produces rather than re-wrapping, so the screen and the
  /// page can never disagree about where a line broke.
  void _text(
    Canvas canvas,
    String text,
    Rect slot,
    TextStyle style, {
    bool alignRight = false,
    bool alignBottom = false,
  }) {
    if (text.isEmpty || slot.width <= 0 || slot.height <= 0) {
      return;
    }
    final painter = conteTextPainter(text, style, slot.width);
    canvas.save();
    canvas.clipRect(slot);
    painter.paint(
      canvas,
      Offset(
        alignRight ? slot.right - painter.width : slot.left,
        alignBottom ? slot.bottom - painter.height : slot.top,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ContePagePainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.source != source ||
      oldDelegate.selectedCell != selectedCell ||
      oldDelegate.pictureFor != pictureFor;
}

/// The conte's text measurement, shared by the painter and the PDF writer.
///
/// Fonts shrink a STEP at a time and then clip (design): a column that
/// silently reflows to nothing is worse than one that admits it ran out.
TextPainter conteTextPainter(String text, TextStyle style, double maxWidth) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  return painter;
}
