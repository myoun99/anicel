import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_page_marks.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/conte/conte_words.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../repaint_props.dart';
import '../sheet_painting.dart';
import '../timeline/memo_token.dart';
import '../timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount;
import '../timeline/timeline_drag_preview.dart' show TimelineDragPreview;
import 'conte_fonts.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

/// The conte page on a Canvas — the panel's and the PNG export's printer.
///
/// It decides nothing: the page is [contePageMarks], the one walk the PDF
/// replays too, and this prints those marks ([SheetCanvasPrinter]). What it
/// adds is what only a live panel has — the images it finds by name and the
/// drag a cut's length is following.
///
/// The paper is WHITE and the ink is black whatever the app theme is: this
/// is a printed page shown on a screen, not a panel.
class ContePagePainter extends CustomPainter with RepaintOnProps {
  ContePagePainter({
    required this.page,
    required this.source,
    this.pictureFor,
    this.imageFor,
    this.viewport,
    this.effectiveRatio = 1.0,
    this.layers,
    this.inkImageFor,
    this.liveInkKeys = const {},
    this.dragPreview,
    required this.words,
    // The thumbnail store (async pictures): a landed render must repaint
    // this painter even though none of the compared fields changed —
    // without it the cells stayed blank until the next pan/zoom.
    super.repaint,
  });

  final ContePageLayout page;
  final ConteSheetSource source;

  /// The words the page prints, in the notation language.
  final ConteWords words;

  /// The session's drag channel, or null where nothing can be in flight
  /// (the exports and focused tests, which print the built lengths).
  ///
  /// The sheet's NUMBERS follow a cut-length drag through it (F-88); the
  /// page geometry does not — the paper re-flows when the drag lands, so a
  /// step costs one text repaint rather than a re-layout.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// The panel's pan/zoom (the canvas-shell mount, #16). Null fits the page
  /// into the size it is given (the export paths).
  final CanvasViewport? viewport;

  /// The view's DPR — the SAME one the host snapped with.
  final double effectiveRatio;

  /// The finished composite for a cell, or null while it renders (the cell
  /// prints its form and text either way — a conte with no pictures yet is
  /// still a conte).
  final ui.Image? Function(String cutId, int pictureFrame)? pictureFor;

  /// A media image by its asset path — the company logo.
  final ui.Image? Function(String assetPath)? imageFor;

  /// Which strata to draw; null draws every one. [SheetPaintLayer] is the
  /// three sheets' shared vocabulary.
  final Set<SheetPaintLayer>? layers;

  /// The sheet ink's display raster for one window key (R5) — the page's
  /// surface and each cell's row-band surface, at [conteInkScale] over
  /// document points. Null (the resolver or the image) draws no ink.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// Keys whose ink a LIVE input window is already showing: skipped, so
  /// translucent ink never composites twice.
  final Set<BrushFrameKey> liveInkKeys;

  ConteSheetMetrics get metrics => page.metrics;

  /// What this page prints, with the drag's lengths where one is in flight.
  List<SheetMark> marks() =>
      contePageMarks(
        page,
        source,
        liveFramesOf: _liveFramesOf,
        words: words,
      );

  @override
  void paint(Canvas canvas, Size size) {
    SheetCanvasPrinter(
      style: conteTextStyle,
      layers: layers,
      images: SheetMarkImages(
        pictureFor: pictureFor,
        imageFor: imageFor,
        inkImageFor: inkImageFor,
        liveInkKeys: liveInkKeys,
        inkScale: conteInkScale.toDouble(),
      ),
    ).paint(
      canvas,
      size,
      (
        viewport: viewport,
        devicePixelRatio: effectiveRatio,
        paper: Size(metrics.pageWidth, metrics.pageHeight),
      ),
      marks(),
    );
  }

  /// The live length of the cut [cutId] names, or null with no drag
  /// channel.
  ///
  /// 🚨The SAME law the timeline's end line and the timesheet read
  /// ([timelineCutEndPreviewFrameCount]) — a second answer here is how two
  /// panels print one number differently for the length of a drag (F-88,
  /// 유저: 「콘티패널의 초수도 똑같이」).
  int? _liveFramesOf(String cutId) {
    final channel = dragPreview;
    if (channel == null) {
      return null;
    }
    final cut = source.cutById(cutId);
    return timelineCutEndPreviewFrameCount(
      preview: channel.value,
      cutId: cut.cutId,
      playbackFrameCount: cut.durationFrames,
    );
  }

  @override
  // pictureFor/imageFor/inkImageFor are deliberately absent: fresh closures
  // every build, and comparing them made every rebuild a full-page
  // repaint. Ink content changes repaint through `repaint` (the ink
  // controller notifies per stroke/undo).
  Object get props => (
    page,
    source,
    words,
    viewport,
    effectiveRatio,
    BySet(liveInkKeys),
    dragPreview,
  );
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
