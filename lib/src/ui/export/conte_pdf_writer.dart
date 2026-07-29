import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../conte/conte_fonts.dart';
import '../conte/conte_page_painter.dart' show conteWrappedLines;

/// The conte sheet as ONE vector PDF.
///
/// The GEOMETRY is [ContePageLayout] — the very numbers the panel paints
/// (the layout model was designed in points because "that is what a PDF
/// wants natively"). Rules and boxes are PDF vectors, text is embedded-
/// font glyph runs, and only the cell pictures are raster embeds.
///
/// Text WRAPS once, in [conteWrappedLines]: the panel lays the paragraph
/// out in the very faces this file embeds (the screen adopted them —
/// user 2026-07-29), and the PDF prints those lines verbatim. The old
/// "each side wraps self-consistently" deviation is retired; a break on
/// screen IS a break on the page.
///
/// Fonts: M PLUS 1p (Latin + kana + kanji, regular/bold) with IBM Plex
/// Sans KR as the Hangul fallback — per-run font selection by glyph
/// coverage, so mixed-script lines print whole. All three are OFL
/// (THIRD_PARTY.md).
class ContePdfFonts {
  ContePdfFonts._(this.regular, this.bold, this.korean);

  final ByteData regular;
  final ByteData bold;
  final ByteData korean;

  static const String regularAsset = conteJpRegularAsset;
  static const String boldAsset = conteJpBoldAsset;
  static const String koreanAsset = conteKrRegularAsset;

  /// Loads the bundled OFL fonts for EMBEDDING (rootBundle); the same
  /// files are registered into the engine by [ensureConteFontsLoaded],
  /// which is what lets the wrap be computed panel-side.
  static Future<ContePdfFonts> load() async {
    return ContePdfFonts._(
      await rootBundle.load(regularAsset),
      await rootBundle.load(boldAsset),
      await rootBundle.load(koreanAsset),
    );
  }
}

/// A cell picture for the PDF: raw straight-alpha RGBA (what [PdfImage]
/// expects — premultiplied bytes would darken translucent edges).
class ContePdfPicture {
  const ContePdfPicture({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;

  static Future<ContePdfPicture?> fromImage(ui.Image? image) async {
    if (image == null) {
      return null;
    }
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      return null;
    }
    return ContePdfPicture(
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  }
}

/// Writes [pages] as one PDF document. [pictures] maps
/// `(cutId, pictureFrame)` to the pre-rendered cell composites; absent
/// entries print the empty framed cell, like the panel does while a
/// render is pending.
Future<Uint8List> writeContePdf({
  required ConteSheetSource source,
  required List<ContePageLayout> pages,
  required ContePdfFonts fonts,
  Map<(String, int), ContePdfPicture> pictures = const {},
}) async {
  // The wrap is measured by the ENGINE's registration of these faces
  // (conteWrappedLines) — make sure a headless export path cannot measure
  // in a fallback face while embedding the real one.
  await ensureConteFontsLoaded();
  final document = PdfDocument();
  final writer = _ContePdfPageWriter(
    document: document,
    source: source,
    regular: PdfTtfFont(document, fonts.regular),
    bold: PdfTtfFont(document, fonts.bold),
    korean: PdfTtfFont(document, fonts.korean),
    pictures: {
      for (final entry in pictures.entries)
        entry.key: PdfImage(
          document,
          image: entry.value.rgba,
          width: entry.value.width,
          height: entry.value.height,
        ),
    },
  );
  for (final page in pages) {
    writer.writePage(page);
  }
  return document.save();
}

class _ContePdfPageWriter {
  _ContePdfPageWriter({
    required this.document,
    required this.source,
    required this.regular,
    required this.bold,
    required this.korean,
    required this.pictures,
  });

  final PdfDocument document;
  final ConteSheetSource source;
  final PdfTtfFont regular;
  final PdfTtfFont bold;
  final PdfTtfFont korean;
  final Map<(String, int), PdfImage> pictures;

  static final PdfColor _ink = PdfColor.fromInt(0xFF101010);
  static final PdfColor _rule = PdfColor.fromInt(0xFF404040);
  static final PdfColor _paper = PdfColor.fromInt(0xFFFFFFFF);

  /// The painter's line height (TextStyle height: 1.25).
  static const double _lineHeight = 1.25;
  static const double _pictureBorderWidth = 2.4;

  late PdfGraphics _g;
  late double _pageHeight;
  late ContePageLayout _page;

  ConteSheetMetrics get _metrics => _page.metrics;

  double _y(double top) => _pageHeight - top;

  void writePage(ContePageLayout page) {
    _page = page;
    _pageHeight = page.metrics.pageHeight;
    final pdfPage = PdfPage(
      document,
      pageFormat: PdfPageFormat(page.metrics.pageWidth, _pageHeight),
    );
    _g = pdfPage.getGraphics();
    // The PDF's own page is the paper (the painter's showPaper:false
    // case) — no fill needed, but a white ground keeps viewers that
    // default to transparent honest.
    _fillRect(
      ui.Rect.fromLTWH(0, 0, page.metrics.pageWidth, _pageHeight),
      _paper,
    );
    _header();
    _grid();
    for (final band in page.cutBands) {
      _cutBand(band);
    }
    for (final cell in page.cells) {
      _cell(cell);
    }
    _hole();
    _footer();
  }

  // ---- primitives ------------------------------------------------------

  void _fillRect(ui.Rect rect, PdfColor color) {
    _g.setFillColor(color);
    _g.drawRect(rect.left, _y(rect.bottom), rect.width, rect.height);
    _g.fillPath();
  }

  void _strokeRect(ui.Rect rect, double width, PdfColor color) {
    _g.setStrokeColor(color);
    _g.setLineWidth(width);
    _g.drawRect(rect.left, _y(rect.bottom), rect.width, rect.height);
    _g.strokePath();
  }

  void _line(ui.Offset a, ui.Offset b, double width, PdfColor color) {
    _g.setStrokeColor(color);
    _g.setLineWidth(width);
    _g.drawLine(a.dx, _y(a.dy), b.dx, _y(b.dy));
    _g.strokePath();
  }

  // ---- painter mirrors -------------------------------------------------

  void _header() {
    final left = [
      if (source.title.isNotEmpty) source.title,
      if (source.episode.isNotEmpty) source.episode,
    ].join('  ');
    _text(
      left,
      ui.Rect.fromLTRB(
        _metrics.bodyLeft,
        _metrics.margin,
        _metrics.bodyRight - 80,
        _metrics.bodyTop,
      ),
      12,
      isBold: true,
    );
    _text(
      '${_page.pageIndex + 1}',
      ui.Rect.fromLTRB(
        _metrics.bodyRight - 80,
        _metrics.margin,
        _metrics.bodyRight,
        _metrics.bodyTop,
      ),
      12,
      alignRight: true,
    );
  }

  void _footer() {
    _text(
      _page.pageTotalLabel,
      ui.Rect.fromLTRB(
        _metrics.timeLeft,
        _metrics.bodyBottom,
        _metrics.bodyRight,
        _metrics.pageHeight - _metrics.margin / 2,
      ),
      9,
      isBold: true,
      alignRight: true,
    );
  }

  void _grid() {
    final body = ui.Rect.fromLTRB(
      _metrics.bodyLeft,
      _metrics.bodyTop,
      _metrics.bodyRight,
      _metrics.bodyBottom,
    );
    _strokeRect(body, 0.8, _rule);
    for (final x in [
      _metrics.pictureLeft,
      _metrics.actionLeft,
      _metrics.dialogueLeft,
      _metrics.timeLeft,
    ]) {
      _line(
        ui.Offset(x, _metrics.bodyTop),
        ui.Offset(x, _metrics.bodyBottom),
        0.8,
        _rule,
      );
    }
    for (var row = 1; row < _metrics.rowsPerPage; row += 1) {
      final y = _metrics.rowTop(row);
      _line(
        ui.Offset(_metrics.cutColumnLeft, y),
        ui.Offset(_metrics.pictureLeft, y),
        0.8,
        _rule,
      );
      _line(
        ui.Offset(_metrics.timeLeft, y),
        ui.Offset(_metrics.bodyRight, y),
        0.8,
        _rule,
      );
    }
  }

  void _cutBand(ContePlacedCutBand band) {
    _fillRect(band.cutRect, _paper);
    _fillRect(band.timeRect, _paper);
    _strokeRect(band.cutRect, 1.4, _ink);
    _strokeRect(band.timeRect, 1.4, _ink);
    if (band.showsNumber) {
      _text(band.cutName, band.cutRect.deflate(3), 10, isBold: true);
    }
    if (band.showsLength) {
      _text(
        band.lengthLabel,
        band.timeRect.deflate(3),
        10,
        alignRight: true,
        alignBottom: true,
      );
    }
  }

  void _cell(ContePlacedCell cell) {
    final picture = cell.pictureRect;
    if (picture.width > 0 && picture.height > 0) {
      final image = pictures[(cell.cutId, cell.source.pictureFrame)];
      if (image != null) {
        _picture(image, picture.deflate(_pictureBorderWidth));
      }
      _strokeRect(
        picture.deflate(_pictureBorderWidth / 2),
        _pictureBorderWidth,
        _ink,
      );
      final labels = cell.source.cameraLabels;
      if (labels.isNotEmpty) {
        _text(labels.first, picture.deflate(5), 8, isBold: true);
        if (labels.length > 1) {
          _text(
            labels.last,
            picture.deflate(5),
            8,
            isBold: true,
            alignRight: true,
            alignBottom: true,
          );
        }
      }
    }
    _text(cell.source.action, cell.actionRect.deflate(4), 9);
    _text(contePrintedDialogueFor(source, cell), cell.dialogueRect.deflate(4), 9);
  }

  void _picture(PdfImage image, ui.Rect slot) {
    if (slot.width <= 0 || slot.height <= 0) {
      return;
    }
    final scale = (slot.width / image.width) < (slot.height / image.height)
        ? slot.width / image.width
        : slot.height / image.height;
    final width = image.width * scale;
    final height = image.height * scale;
    final left = slot.left + (slot.width - width) / 2;
    final top = slot.top + (slot.height - height) / 2;
    _g.drawImage(image, left, _y(top + height), width, height);
  }

  void _hole() {
    final from = _page.emptyRowsFrom;
    if (from == null || from >= _metrics.rowsPerPage) {
      return;
    }
    final hole = ui.Rect.fromLTRB(
      _metrics.pictureLeft,
      _metrics.rowTop(from),
      _metrics.timeLeft,
      _metrics.bodyBottom,
    );
    _line(hole.topLeft, hole.bottomRight, 1, _rule);
    _line(hole.topRight, hole.bottomLeft, 1, _rule);
  }

  // ---- text ------------------------------------------------------------

  bool _covers(PdfTtfFont font, int rune) =>
      font.font.charToGlyphIndexMap.containsKey(rune);

  /// Splits [text] into per-font runs: the preferred (JP) font where it
  /// has the glyph, the Korean fallback where it does not but Korean
  /// does; unknown-to-both stays on the preferred font (its notdef says
  /// honestly that the glyph is missing).
  List<({PdfTtfFont font, String text})> _runsFor(
    String text, {
    required bool isBold,
  }) {
    final preferred = isBold ? bold : regular;
    final runs = <({PdfTtfFont font, String text})>[];
    final buffer = StringBuffer();
    PdfTtfFont? current;
    for (final rune in text.runes) {
      final font = _covers(preferred, rune)
          ? preferred
          : _covers(korean, rune)
          ? korean
          : preferred;
      if (current != null && font != current && buffer.isNotEmpty) {
        runs.add((font: current, text: buffer.toString()));
        buffer.clear();
      }
      current = font;
      buffer.writeCharCode(rune);
    }
    if (current != null && buffer.isNotEmpty) {
      runs.add((font: current, text: buffer.toString()));
    }
    return runs;
  }

  double _runsWidth(List<({PdfTtfFont font, String text})> runs, double size) {
    var width = 0.0;
    for (final run in runs) {
      width += run.font.stringMetrics(run.text).advanceWidth * size;
    }
    return width;
  }

  /// Lays text into [slot] — the painter's `_text` in PDF space: the
  /// SHARED lines ([conteWrappedLines], the panel's own layout read back),
  /// clipped to the slot, aligned the same way.
  void _text(
    String text,
    ui.Rect slot,
    double size, {
    bool isBold = false,
    bool alignRight = false,
    bool alignBottom = false,
  }) {
    if (text.isEmpty || slot.width <= 0 || slot.height <= 0) {
      return;
    }
    final lines = conteWrappedLines(
      text,
      conteTextStyle(size, bold: isBold),
      slot.width,
    );
    final lineHeight = size * _lineHeight;
    final totalHeight = lines.length * lineHeight;
    final top = alignBottom ? slot.bottom - totalHeight : slot.top;
    final ascent = (isBold ? bold : regular).ascent * size;

    _g.saveContext();
    _g.drawRect(slot.left, _y(slot.bottom), slot.width, slot.height);
    _g.clipPath();
    _g.setFillColor(_ink);
    for (var index = 0; index < lines.length; index += 1) {
      final runs = _runsFor(lines[index], isBold: isBold);
      final lineTop = top + index * lineHeight;
      var x = alignRight
          ? slot.right - _runsWidth(runs, size)
          : slot.left;
      final baseline = _y(lineTop + ascent);
      for (final run in runs) {
        _g.drawString(run.font, size, run.text, x, baseline);
        x += run.font.stringMetrics(run.text).advanceWidth * size;
      }
    }
    _g.restoreContext();
  }
}
