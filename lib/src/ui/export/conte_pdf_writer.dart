import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';

import '../../core/contain_rect.dart';
import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_page_marks.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/conte/conte_words.dart';
import '../../models/sheet_marks.dart';
import '../conte/conte_fonts.dart';
import '../conte/conte_page_painter.dart'
    show ContePagePainter, conteWrappedLines;
import '../sheet_painting.dart' show sheetWordsSize;
import '../theme/app_theme.dart' show AppTypography;

/// The conte sheet as ONE vector PDF.
///
/// It prints the page the panel prints: [contePageMarks], replayed. Rules
/// and fills are PDF vectors at their exact paper geometry, words are
/// embedded-font glyph runs, and only the pictures, the logo and the ink
/// are raster embeds.
///
/// ↩️It used to walk the layout itself — header, grid, frames, cut boxes,
/// cells, footer — beside the painter's own walk, under a heading that
/// called it 「painter mirrors」. Two walks of one page drift; one list of
/// marks cannot.
///
/// Text WRAPS once, in [conteWrappedLines]: the panel lays the paragraph
/// out in the very faces this file embeds, and the PDF prints those lines
/// verbatim. A break on screen IS a break on the page.
///
/// Fonts: the app's bundled faces ([AppTypography.bundledFiles] — BIZ
/// UDPGothic for Latin, kana and kanji; 나눔고딕 behind it for Hangul, the
/// order the app's own text resolves in), both weights, per-run selection
/// by glyph coverage so mixed-script lines print whole. Both are OFL
/// (THIRD_PARTY.md).
class ContePdfFonts {
  ContePdfFonts._({
    required this.regular,
    required this.bold,
    required this.hangul,
    required this.hangulBold,
  });

  final ByteData regular;
  final ByteData bold;
  final ByteData hangul;
  final ByteData hangulBold;

  /// Loads the bundled OFL fonts for EMBEDDING (rootBundle) — the files
  /// `pubspec.yaml` declares as the app's faces, which the engine measures
  /// the wrap in.
  static Future<ContePdfFonts> load() async {
    const face = AppTypography.bundledFiles;
    const behind = AppTypography.bundledFallbackFiles;
    return ContePdfFonts._(
      regular: await rootBundle.load(face.regular),
      bold: await rootBundle.load(face.bold),
      hangul: await rootBundle.load(behind.regular),
      hangulBold: await rootBundle.load(behind.bold),
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

/// Writes [pages] as one PDF document.
///
/// [pictures] maps `(cutId, pictureFrame)` to the pre-rendered cell
/// composites and [images] a media asset path (the logo) to its pixels;
/// absent entries print the page without them, like the panel does while
/// a render is pending. [inkPictures] maps a sheet-ink window's
/// [BrushFrameKey] to its composed raster (R5), drawn over the finished
/// page exactly like the panel (pen over paper).
Future<Uint8List> writeContePdf({
  required ConteSheetSource source,
  required List<ContePageLayout> pages,
  required ContePdfFonts fonts,
  Map<(String, int), ContePdfPicture> pictures = const {},
  Map<String, ContePdfPicture> images = const {},
  Map<BrushFrameKey, ContePdfPicture> inkPictures = const {},
  required ConteWords words,
}) async {
  final document = PdfDocument();
  PdfImage embed(ContePdfPicture picture) => PdfImage(
    document,
    image: picture.rgba,
    width: picture.width,
    height: picture.height,
  );
  final writer = _ContePdfPageWriter(
    document: document,
    regular: PdfTtfFont(document, fonts.regular),
    bold: PdfTtfFont(document, fonts.bold),
    hangul: PdfTtfFont(document, fonts.hangul),
    hangulBold: PdfTtfFont(document, fonts.hangulBold),
    pictures: {
      for (final entry in pictures.entries) entry.key: embed(entry.value),
    },
    images: {
      for (final entry in images.entries) entry.key: embed(entry.value),
    },
    inkPictures: {
      for (final entry in inkPictures.entries) entry.key: embed(entry.value),
    },
  );
  for (final page in pages) {
    writer.writePage(
      contePageMarks(page, source, words: words),
      ui.Size(page.metrics.pageWidth, page.metrics.pageHeight),
    );
  }
  return document.save();
}

class _ContePdfPageWriter {
  _ContePdfPageWriter({
    required this.document,
    required this.regular,
    required this.bold,
    required this.hangul,
    required this.hangulBold,
    required this.pictures,
    required this.images,
    required this.inkPictures,
  });

  final PdfDocument document;
  final PdfTtfFont regular;
  final PdfTtfFont bold;
  final PdfTtfFont hangul;
  final PdfTtfFont hangulBold;
  final Map<(String, int), PdfImage> pictures;
  final Map<String, PdfImage> images;
  final Map<BrushFrameKey, PdfImage> inkPictures;

  /// The painter's line height (TextStyle height: 1.25).
  static const double _lineHeight = 1.25;

  late PdfGraphics _g;
  late double _pageHeight;

  double _y(double top) => _pageHeight - top;

  void writePage(List<SheetMark> marks, ui.Size paper) {
    _pageHeight = paper.height;
    final pdfPage = PdfPage(
      document,
      pageFormat: PdfPageFormat(paper.width, paper.height),
    );
    _g = pdfPage.getGraphics();
    for (final mark in marks) {
      _print(mark);
    }
  }

  void _print(SheetMark mark) {
    switch (mark) {
      case SheetFill(:final rect, :final argb, :final cornerRadius)
          when cornerRadius > 0:
        _g.setFillColor(PdfColor.fromInt(argb));
        _traceRounded(rect, cornerRadius);
        _g.fillPath();
      case SheetFill(:final rect, :final argb):
        _fillRect(rect, PdfColor.fromInt(argb));
      case SheetRule(:final rect, :final argb):
        // What the rule covers — the geometry the screen cuts on its grid,
        // printed exact (vectors need no pixel to hold).
        _fillRect(rect, PdfColor.fromInt(argb));
      case SheetWords():
        _words(mark);
      case SheetPicture(
        :final cutId,
        :final pictureFrame,
        :final slot,
        :final cornerRadius,
      ):
        final image = pictures[(cutId, pictureFrame)];
        if (image != null) {
          _g.saveContext();
          if (cornerRadius > 0) {
            _traceRounded(slot, cornerRadius);
            _g.clipPath();
          }
          _contained(image, slot);
          _g.restoreContext();
        }
      case SheetImage(:final assetPath, :final slot):
        final image = images[assetPath];
        if (image != null) {
          _contained(image, slot);
        }
      case SheetInk(:final key, :final rect):
        final image = inkPictures[key];
        if (image != null) {
          _clippedTo(image, rect);
        }
    }
  }

  void _fillRect(ui.Rect rect, PdfColor color) {
    _g.setFillColor(color);
    _g.drawRect(rect.left, _y(rect.bottom), rect.width, rect.height);
    _g.fillPath();
  }

  /// The app's corner — a superellipse on flat sides — as a path on the
  /// page, TRACED from the engine's own shape, the one the panel draws: a
  /// PDF has no superellipse, and a circle's arc would be a second corner.
  /// Traced every half point; the points a flat side adds say nothing, so
  /// they go.
  void _traceRounded(ui.Rect rect, double radius) {
    final shape = ui.Path()
      ..addRSuperellipse(
        ui.RSuperellipse.fromRectAndRadius(rect, ui.Radius.circular(radius)),
      );
    final points = <ui.Offset>[];
    for (final metric in shape.computeMetrics()) {
      double? heading;
      for (var along = 0.0; along < metric.length; along += 0.5) {
        final tangent = metric.getTangentForOffset(along)!;
        // A flat side keeps one heading: where it starts traces it.
        if (heading != null && (tangent.angle - heading).abs() < 1e-6) {
          continue;
        }
        heading = tangent.angle;
        points.add(tangent.position);
      }
    }
    _g.moveTo(points.first.dx, _y(points.first.dy));
    for (final point in points.skip(1)) {
      _g.lineTo(point.dx, _y(point.dy));
    }
    _g.closePath();
  }

  void _contained(PdfImage image, ui.Rect slot) {
    if (slot.width <= 0 || slot.height <= 0) {
      return;
    }
    final drawn = containRect(
      ui.Size(image.width.toDouble(), image.height.toDouble()),
      slot,
    );
    _g.drawImage(image, drawn.left, _y(drawn.bottom), drawn.width, drawn.height);
  }

  /// An ink raster laid at the ink's own scale from its window's corner and
  /// clipped to the window — the screen's `paintSheetInkWindow`.
  ///
  /// ⛔Not stretched to the window: a cell's surface is the whole BODY's (a
  /// cell that grows over more rows reveals more of the same ink), and its
  /// band shows only the top of it. Stretched whole into a one-row band,
  /// the handwriting printed five times squeezed, on paper only.
  void _clippedTo(PdfImage image, ui.Rect rect) {
    const scale = ContePagePainter.conteInkScale;
    final height = image.height / scale;
    _g.saveContext();
    _g.drawRect(rect.left, _y(rect.bottom), rect.width, rect.height);
    _g.clipPath();
    _g.drawImage(
      image,
      rect.left,
      _y(rect.top + height),
      image.width / scale,
      height,
    );
    _g.restoreContext();
  }

  // ---- text ------------------------------------------------------------

  bool _covers(PdfTtfFont font, int rune) =>
      font.font.charToGlyphIndexMap.containsKey(rune);

  /// Splits [text] into per-font runs, the order the engine resolves the
  /// same line in: the app's face where it has the glyph, 나눔고딕 behind
  /// it where it does not but Hangul does; unknown-to-both stays on the
  /// app's face (its notdef says honestly that the glyph is missing).
  List<({PdfTtfFont font, String text})> _runsFor(
    String text, {
    required bool isBold,
  }) {
    final preferred = isBold ? bold : regular;
    final behind = isBold ? hangulBold : hangul;
    final runs = <({PdfTtfFont font, String text})>[];
    final buffer = StringBuffer();
    PdfTtfFont? current;
    for (final rune in text.runes) {
      final font = _covers(preferred, rune)
          ? preferred
          : _covers(behind, rune)
          ? behind
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

  /// Lays [words] into their slot — the Canvas printer's words in PDF
  /// space: the SHARED lines ([conteWrappedLines], the panel's own layout
  /// read back), clipped to the slot, set where the mark says.
  void _words(SheetWords words) {
    if (words.printsNothing) {
      return;
    }
    final slot = words.slot;
    // The size and the breaks are the ENGINE's — the panel's measurement,
    // printed, never a second one from the embedded glyph runs.
    final size = sheetWordsSize(words, conteTextStyle);
    final lines = words.fit == SheetWordsFit.wrap
        ? conteWrappedLines(
            words.text,
            conteTextStyle(size, bold: words.bold),
            slot.width,
          )
        : [words.text];
    final lineHeight = size * _lineHeight;
    final totalHeight = lines.length * lineHeight;
    final top = words.v.place(slot.top, slot.height, totalHeight);
    final ascent = (words.bold ? bold : regular).ascent * size;

    _g.saveContext();
    _g.drawRect(slot.left, _y(slot.bottom), slot.width, slot.height);
    _g.clipPath();
    _g.setFillColor(PdfColor.fromInt(words.argb));
    for (var index = 0; index < lines.length; index += 1) {
      final runs = _runsFor(lines[index], isBold: words.bold);
      final width = _runsWidth(runs, size);
      var x = words.h.place(slot.left, slot.width, width);
      final baseline = _y(top + index * lineHeight + ascent);
      for (final run in runs) {
        _g.drawString(run.font, size, run.text, x, baseline);
        x += run.font.stringMetrics(run.text).advanceWidth * size;
      }
    }
    _g.restoreContext();
  }
}
