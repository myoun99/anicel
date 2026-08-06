import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut_id.dart';
import '../../models/sheet_paint_layer.dart';
import 'conte_fonts.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

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
  ContePagePainter({
    required this.page,
    required this.source,
    this.pictureFor,
    this.selectedCell,
    this.showPaper = true,
    this.viewport,
    this.layers,
    this.inkImageFor,
    this.liveInkKeys = const {},
    // The thumbnail store (async pictures): a landed render must repaint
    // this painter even though none of the compared fields changed —
    // without it the cells stayed blank until the next pan/zoom.
    super.repaint,
  });

  final ContePageLayout page;
  final ConteSheetSource source;

  /// The panel's pan/zoom (the canvas-shell mount, #16): document space IS
  /// page space and this transform places it, exactly like the timesheet
  /// painter. Null keeps the legacy fit-to-size scaling (export paths).
  final CanvasViewport? viewport;

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

  /// Which strata to draw; null draws all four (the panel, and any export
  /// that wants one flat page). The envelope's rule, said of the conte —
  /// [SheetPaintLayer] is the shared vocabulary.
  final Set<SheetPaintLayer>? layers;

  bool _draws(SheetPaintLayer layer) =>
      layers == null || layers!.contains(layer);

  /// The sheet ink's display raster for one window key (R5) — the page's
  /// surface and each cell's row-band surface, at [conteInkScale] over
  /// document points. Null (the resolver or the image) draws no ink.
  /// The PNG export inherits the ink through this exactly like the panel.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// Keys whose ink a LIVE input window is already showing (the ink-mode
  /// overlay): the painter skips them so translucent ink never composites
  /// twice.
  final Set<BrushFrameKey> liveInkKeys;

  /// [ConteInkController.inkScale] without importing the UI controller.
  static const int conteInkScale = 4;

  ConteSheetMetrics get metrics => page.metrics;

  static const Color _ink = Color(0xFF101010);
  static const Color _rule = Color(0xFF404040);

  /// The tone inside a printed picture frame — the well a panel is drawn
  /// into. Light enough that a drawing over it still reads as the drawing.
  static const Color _pictureWell = Color(0xFFEDEDED);

  /// The picture cell's heavy silhouette border — the Ghibli-conte look the
  /// design asks for, and the thing that makes the picture read as a frame
  /// rather than as a table cell.
  static const double _pictureBorderWidth = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    final resolvedViewport = viewport;
    canvas.save();
    if (resolvedViewport != null) {
      // The canvas shell: crisp vector redraw at any zoom, no raster
      // cache — the timesheet painter's transform.
      canvas.clipRect(Offset.zero & size);
      canvas.translate(resolvedViewport.panX, resolvedViewport.panY);
      canvas.scale(resolvedViewport.zoom, resolvedViewport.zoom);
    } else {
      final scale = math.min(
        size.width / metrics.pageWidth,
        size.height / metrics.pageHeight,
      );
      canvas.scale(scale);
    }
    _paintPage(canvas);
    canvas.restore();
  }

  void _paintPage(Canvas canvas) {
    if (showPaper && _draws(SheetPaintLayer.paper)) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    if (_draws(SheetPaintLayer.form)) {
      _paintForm(canvas);
    }
    if (_draws(SheetPaintLayer.content)) {
      _paintHeaderValues(canvas);
      for (final band in page.cutBands) {
        _paintCutBandValues(canvas, band);
      }
      for (final cell in page.cells) {
        _paintCell(canvas, cell);
      }
      _paintFooterValues(canvas);
    }
    if (_draws(SheetPaintLayer.ink)) {
      _paintInk(canvas);
    }
  }

  /// Everything the blank sheet prints — and nothing else.
  ///
  /// The form reads the page's SHAPE (its metrics) and never the film:
  /// an empty page draws the same rules, the same columns and the same
  /// picture frames as a full one. That is what a printed conte pad is,
  /// and it is why the old "X across the empty rows", the heavier box
  /// redrawn wherever a cut happened to start, and the picture border
  /// that only existed where a cell did are all gone (user, 2026-08-06:
  /// *"너무 번잡해보여"*).
  /// (The header carries no printed labels of its own yet — the title and
  /// the page number are both values, so they are content.)
  void _paintForm(Canvas canvas) {
    _paintGrid(canvas);
    _paintPictureFrames(canvas);
  }

  /// The picture window of EVERY row: the frame is printed on the sheet,
  /// and its inside is toned so an empty one still reads as the place a
  /// panel goes (user: *"서식에 픽처 프레임이 항상 존재하고 그 안쪽을
  /// 진하게 칠하는 것이 기본. 그림은 그 위에 얹힐 뿐"*).
  void _paintPictureFrames(Canvas canvas) {
    final fill = Paint()..color = _pictureWell;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _pictureBorderWidth
      ..color = _ink;
    for (var row = 0; row < metrics.rowsPerPage; row += 1) {
      final frame = Rect.fromLTRB(
        metrics.pictureLeft,
        metrics.rowTop(row),
        metrics.actionLeft,
        metrics.rowTop(row + 1),
      );
      canvas.drawRect(frame.deflate(_pictureBorderWidth), fill);
      canvas.drawRect(frame.deflate(_pictureBorderWidth / 2), border);
    }
  }

  /// The sheet ink, above everything the page prints (it was drawn over
  /// the finished sheet — pen over paper): the page plane first, then each
  /// cell's row band, each clipped to its own window so a band's strokes
  /// never bleed onto a neighbour.
  void _paintInk(Canvas canvas) {
    final resolve = inkImageFor;
    if (resolve == null) {
      return;
    }
    void draw(BrushFrameKey key, Rect windowRect) {
      if (liveInkKeys.contains(key)) {
        return;
      }
      final image = resolve(key);
      if (image == null) {
        return;
      }
      canvas.save();
      canvas.clipRect(windowRect);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          windowRect.width * conteInkScale,
          windowRect.height * conteInkScale,
        ),
        windowRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }

    draw(
      conteInkPageKey(page.pageIndex),
      Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
    );
    for (final cell in page.cells) {
      final frameId = cell.source.frameId;
      if (frameId == null) {
        continue;
      }
      draw(
        conteInkRowKey(CutId(cell.cutId), frameId),
        cell.rowBandRect(metrics),
      );
    }
  }

  // ---- header / footer -------------------------------------------------

  void _paintHeaderValues(Canvas canvas) {
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

  void _paintFooterValues(Canvas canvas) {
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

  /// The cut number and its length, written into the boxes the FORM
  /// already printed.
  ///
  /// Nothing is drawn over the form here any more. It used to fill the
  /// cut and time boxes white and re-stroke them heavier — a merged box
  /// per cut, which erased the row rules inside it — and that is the
  /// clutter the user asked to be rid of: *"컷/패널이 있을 때 서식 위에
  /// 덧그리는 사각형 삭제 … 너무 번잡해보여"*. A box that appears because
  /// a cut exists is content pretending to be form.
  void _paintCutBandValues(Canvas canvas, ContePlacedCutBand band) {
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

  /// A cell's picture and its texts — laid ON the frame the form printed.
  ///
  /// The border is the form's now, so nothing is stroked here. A cell that
  /// spans rows or reaches into the action column (camera work) still
  /// draws its picture at its own size: the panel overflows its printed
  /// window exactly the way a pan drawn on paper does.
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
    _text(
      canvas,
      contePrintedDialogueFor(source, cell),
      cell.dialogueRect.deflate(4),
      _style(9),
    );
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

  // The big X across the rows a page break left empty is gone (user,
  // 2026-08-06). A blank row on a printed sheet is just a blank row — the
  // form is always fully there, so nothing has to say "deliberately
  // empty". [ContePageLayout.emptyRowsFrom] still records the hole for
  // whoever needs to know it; the sheet simply no longer marks it.

  // ---- text ------------------------------------------------------------

  TextStyle _style(double size, {bool bold = false}) =>
      conteTextStyle(size, bold: bold, color: _ink);

  /// Lays text into [slot], shrinking a step at a time before it clips.
  ///
  /// [TextPainter] is the panel's layout truth — set in the EMBEDDED
  /// faces now ([conteTextStyle]), the same files the PDF embeds. The
  /// writer prints [conteWrappedLines]'s lines verbatim, so the panel's
  /// break positions ARE the page's (the old "each side wraps
  /// self-consistently" deviation is retired).
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
      // pictureFor/inkImageFor are deliberately absent: fresh closures
      // every build, and comparing them made every rebuild a full-page
      // repaint. Ink content changes repaint through `repaint` (the ink
      // controller notifies per stroke/undo).
      oldDelegate.page != page ||
      oldDelegate.source != source ||
      oldDelegate.selectedCell != selectedCell ||
      oldDelegate.viewport != viewport ||
      !setEquals(oldDelegate.liveInkKeys, liveInkKeys);
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

/// The conte's LINE BREAKS — one source for the panel and the PDF.
///
/// The panel lays the paragraph out with its own [TextPainter]; this
/// reads that layout back line by line, and the PDF prints exactly these
/// lines with NO second wrap. Sharing the faces ([conteTextStyle]) makes
/// the measurement identical, sharing the lines makes disagreement
/// structurally impossible — the ICU niceties (no line opening with 。」,
/// space-eating breaks) ride along into the PDF for free.
///
/// Trailing whitespace at a break is trimmed (the break ate it — the old
/// greedy wrap's rule), and a hard `\n` never rides at a line's end.
List<String> conteWrappedLines(String text, TextStyle style, double maxWidth) {
  if (text.isEmpty) {
    return const [];
  }
  final painter = conteTextPainter(text, style, maxWidth);
  final lines = <String>[];
  var index = 0;
  while (index < text.length) {
    final range = painter.getLineBoundary(TextPosition(offset: index));
    var end = range.isValid && range.end > index ? range.end : index + 1;
    if (end > text.length) {
      end = text.length;
    }
    var line = text.substring(index, end);
    if (line.endsWith('\n')) {
      line = line.substring(0, line.length - 1);
    }
    lines.add(line.trimRight());
    // A boundary that stops ON the newline would re-answer the same line
    // forever; step over it so the next line begins past the break.
    if (end < text.length && text.codeUnitAt(end) == 0x0A) {
      end += 1;
    }
    index = end;
  }
  return lines;
}
