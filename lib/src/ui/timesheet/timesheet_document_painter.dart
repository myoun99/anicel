import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, setEquals;
import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/timesheet_document.dart';
import '../../models/timesheet_info.dart';
import '../text/dialogue_fit_layout.dart';
import '../text/vertical_writing.dart'
    show verticalTextCells, verticalTextSpanCount;
import '../canvas/viewport_canvas_transform.dart';
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_instruction_row_visual.dart'
    show instructionLabelInset;
import '../timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount;
import '../timeline/timeline_drag_preview.dart';
import 'timesheet_notation.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

part 'document_painter/timesheet_instruction_pass.dart';
part 'document_painter/timesheet_se_pass.dart';
part 'document_painter/timesheet_bands_pass.dart';

/// Geometry of the rendered sheet document in canvas (document) space,
/// modeled on the Japanese paper form (A-1/IG style): a B4-portrait page
/// whose body splits into two side-by-side halves of
/// [TimesheetDocument.halfFrameCount] rows; each half reads
/// frame-number gutter | ACTION block (animation layers) | S1·S2 |
/// CELL block | CAM. The gutter is bare numbers on paper (user direction —
/// no boxed rail, no grid), printed left of each half.
///
/// The continuous mode keeps the SAME paper width and header band as the
/// paged form (the paper size never changes with the view toggle — user
/// rule) and swaps only the body below: ONE half-structure strip with every
/// row in sequence (global frame numbers) growing downward, in page half
/// 0's exact geometry so ink coordinates stay stable across the toggle.
class TimesheetDocumentLayout {
  const TimesheetDocumentLayout({
    required this.document,
    this.continuous = false,
    this.singlePage,
  });

  final TimesheetDocument document;
  final bool continuous;

  /// R26 #41 — PAGE VIEW shows ONE sheet of paper at a time.
  ///
  /// Non-null (paged mode only) makes the document exactly one page tall
  /// with that page printed alone at the top margin; the bottom bar's
  /// ◀ / n/N / ▶ cluster moves the index. Null keeps the pre-#41 stack of
  /// every page (still what exports and focused tests build).
  ///
  /// Every geometry accessor already routes through [pageTop], so the
  /// painter, the ink windows and the header/memo tap zones follow just by
  /// iterating [visiblePageIndexes] instead of `document.pages`.
  final int? singlePage;

  /// The single page actually on screen, clamped into range; null when the
  /// whole document prints (continuous view, exports, tests).
  int? get resolvedSinglePage {
    final page = singlePage;
    if (page == null || continuous || document.pages.isEmpty) {
      return null;
    }
    return page.clamp(0, document.pages.length - 1);
  }

  /// Page indexes this layout prints, in order. One entry in continuous
  /// view (the single strip) and in single-page mode; every page
  /// otherwise.
  List<int> get visiblePageIndexes {
    if (continuous) {
      return const [0];
    }
    final page = resolvedSinglePage;
    if (page != null) {
      return [page];
    }
    return [for (final page in document.pages) page.index];
  }

  static const double rowHeight = 18;
  static const double actionColumnWidth = 24;
  static const double seColumnWidth = 20;
  static const double celColumnWidth = 24;
  static const double cameraColumnWidth = 36;

  /// The CAM group's FIXED total width — the B4 paper must never widen
  /// when a cut carries more instruction rows (user rule): extra CAM
  /// columns split this allotment into narrower cells instead.
  static const double cameraGroupWidth = cameraColumnWidth * 2;

  /// R27 #32: the SE group's FIXED total width, the CAM rule applied to
  /// the sound columns — adding SE tracks must not lengthen the B4 paper
  /// either. Past the base two slots the extra columns split this
  /// allotment into narrower cells.
  static const double seGroupWidth = seColumnWidth * 2;

  /// Bare frame numbers print in this space LEFT of each half — no boxed
  /// rail inside the columns (removed by user direction).
  static const double frameNumberGutterWidth = 24;
  static const double groupRowHeight = 16;
  static const double letterRowHeight = 16;
  static const double headerBandHeight = 64;

  /// The Direction handwriting space under the header band (real-sheet
  /// reference ~140px) — completely open, no frames (R7-⑥). Printed on
  /// every page; page ink (S2) anchors on it.
  static const double memoBandHeight = 140;
  static const double headerGap = 10;
  static const double pagePadding = 16;
  static const double halfGap = 24;
  static const double pageGap = 32;
  static const double documentMargin = 24;

  int _columnCountOf(TimesheetColumnKind kind) {
    var count = 0;
    for (final column in document.columns) {
      if (column.kind == kind) {
        count += 1;
      }
    }
    return count;
  }

  int get _cameraColumnCount => _columnCountOf(TimesheetColumnKind.camera);

  int get _seColumnCount => _columnCountOf(TimesheetColumnKind.se);

  /// Per-column width. Instance-level because the CAM and SE cells share
  /// a fixed group allotment ([cameraGroupWidth] / [seGroupWidth]): past
  /// the base two slots each column in that group narrows so the paper
  /// width stays put.
  double columnWidthFor(TimesheetColumnKind kind) {
    if (kind == TimesheetColumnKind.camera && _cameraColumnCount > 2) {
      return cameraGroupWidth / _cameraColumnCount;
    }
    if (kind == TimesheetColumnKind.se && _seColumnCount > 2) {
      return seGroupWidth / _seColumnCount;
    }
    return switch (kind) {
      TimesheetColumnKind.action => actionColumnWidth,
      TimesheetColumnKind.se => seColumnWidth,
      TimesheetColumnKind.cel => celColumnWidth,
      TimesheetColumnKind.camera => cameraColumnWidth,
    };
  }

  double get columnsHeaderHeight => groupRowHeight + letterRowHeight;

  /// x of a column within its half (a plain prefix sum — frame numbers
  /// live in the gutter left of the half, not between columns).
  double columnLeftInHalf(int columnIndex) {
    var x = 0.0;
    for (var index = 0; index < columnIndex; index += 1) {
      x += columnWidthFor(document.columns[index].kind);
    }
    return x;
  }

  /// Width of a half's column area (the number gutter sits outside it).
  double get halfWidth {
    var width = 0.0;
    for (final column in document.columns) {
      width += columnWidthFor(column.kind);
    }
    return width;
  }

  /// One fixed paper width in BOTH modes — the view toggle never resizes
  /// the paper (or the header band that spans it).
  double get paperWidth =>
      pagePadding * 2 + (frameNumberGutterWidth + halfWidth) * 2 + halfGap;

  /// Rows in the given half of a page (the second half takes the odd
  /// remainder).
  int halfRowCount(int half) => half == 0
      ? document.halfFrameCount
      : document.pageFrameCount - document.halfFrameCount;

  int get _maxHalfRows =>
      halfRowCount(0) > halfRowCount(1) ? halfRowCount(0) : halfRowCount(1);

  double get _pagedBodyHeight => columnsHeaderHeight + _maxHalfRows * rowHeight;

  double get paperHeight => continuous
      ? pagePadding * 2 +
            headerBandHeight +
            memoBandHeight +
            headerGap +
            columnsHeaderHeight +
            document.rowCount * rowHeight
      : pagePadding * 2 +
            headerBandHeight +
            memoBandHeight +
            headerGap +
            _pagedBodyHeight;

  double get paperLeft => documentMargin;

  /// Top of a page's paper. In single-page mode the visible page is the
  /// only paper in the document, so it sits at the top margin — the page
  /// turn is a document swap, not a scroll (R26 #41).
  double pageTop(int pageIndex) => continuous || resolvedSinglePage != null
      ? documentMargin
      : documentMargin + pageIndex * (paperHeight + pageGap);

  /// The paper rect of a page (the whole strip in continuous mode).
  Rect pageRect(int pageIndex) {
    if (continuous) {
      return Rect.fromLTWH(paperLeft, documentMargin, paperWidth, paperHeight);
    }
    return Rect.fromLTWH(
      paperLeft,
      pageTop(pageIndex),
      paperWidth,
      paperHeight,
    );
  }

  /// Left edge of a half's column area (past its number gutter).
  double halfLeft(int pageIndex, int half) {
    if (continuous) {
      return paperLeft + pagePadding + frameNumberGutterWidth;
    }
    return paperLeft +
        pagePadding +
        frameNumberGutterWidth +
        half * (frameNumberGutterWidth + halfWidth + halfGap);
  }

  /// Top of a half's first row.
  double halfRowsTop(int pageIndex) =>
      pageTop(pageIndex) +
      pagePadding +
      headerBandHeight +
      memoBandHeight +
      headerGap +
      columnsHeaderHeight;

  /// Width fractions of the header boxes when all print; hiding boxes
  /// renormalizes the rest over the band. Proportions follow the user's
  /// reference sheets (R7-⑥): a slim Ep.no box, the Title clearly widest,
  /// then compact Cut/Duration/Name/Page boxes.
  static const Map<TimesheetHeaderField, double> _headerFieldFractions = {
    TimesheetHeaderField.episode: 0.08,
    TimesheetHeaderField.title: 0.32,
    TimesheetHeaderField.scene: 0.10,
    TimesheetHeaderField.cut: 0.11,
    TimesheetHeaderField.time: 0.12,
    TimesheetHeaderField.name: 0.17,
    TimesheetHeaderField.sheet: 0.10,
  };

  /// The header band rect of a page — its LEFT edge sits on the grid's
  /// left bold line (the paper form's header table left-aligns with the
  /// ACTION block; the number gutter stays outside both — user fix), its
  /// right edge on half 1's right bold line.
  Rect headerBandRect(int pageIndex) {
    final page = pageRect(pageIndex);
    final left = page.left + pagePadding + frameNumberGutterWidth;
    return Rect.fromLTWH(
      left,
      page.top + pagePadding,
      page.right - pagePadding - left,
      headerBandHeight,
    );
  }

  /// The visible header boxes of a page, in printing order — shared by the
  /// painter and the tap-to-edit layer.
  List<({TimesheetHeaderField field, Rect rect})> headerFieldBoxes(
    int pageIndex,
  ) {
    final fields = document.visibleHeaderFields;
    if (fields.isEmpty) {
      return const [];
    }
    final band = headerBandRect(pageIndex);
    var total = 0.0;
    for (final field in fields) {
      total += _headerFieldFractions[field]!;
    }
    final boxes = <({TimesheetHeaderField field, Rect rect})>[];
    var x = band.left;
    for (var index = 0; index < fields.length; index += 1) {
      // The last box closes exactly on the band edge (no rounding drift).
      final right = index == fields.length - 1
          ? band.right
          : x + band.width * (_headerFieldFractions[fields[index]]! / total);
      boxes.add((
        field: fields[index],
        rect: Rect.fromLTRB(x, band.top, right, band.bottom),
      ));
      x = right;
    }
    return boxes;
  }

  /// The memo band rect of a page — directly under the header band, same
  /// grid-aligned edges.
  Rect memoBandRect(int pageIndex) {
    final band = headerBandRect(pageIndex);
    return Rect.fromLTWH(band.left, band.bottom, band.width, memoBandHeight);
  }

  /// Where a global frame lands: page, half and row within the half. The
  /// continuous strip is a single half per "page block".
  ({int page, int half, int row}) positionOfFrame(int frameIndex) {
    if (continuous) {
      return (page: 0, half: 0, row: frameIndex);
    }
    final page = frameIndex ~/ document.pageFrameCount;
    final local = frameIndex % document.pageFrameCount;
    final half = local < document.halfFrameCount ? 0 : 1;
    return (
      page: page,
      half: half,
      row: half == 0 ? local : local - document.halfFrameCount,
    );
  }

  /// Top edge of a global frame row.
  double frameRowTop(int frameIndex) {
    final position = positionOfFrame(frameIndex);
    return halfRowsTop(position.page) + position.row * rowHeight;
  }

  /// The data-driven cut-end line (the paper's horizontal strikethrough,
  /// S2-0): the bottom edge of the LAST playback frame row, spanning its
  /// half — not ink, same concept as the timeline's cut-end boundary.
  ({int page, int half, double y}) get cutEndLine =>
      cutEndLineFor(document.playbackFrameCount);

  /// The same line for a length the document does not carry — what a
  /// cut-length drag is previewing. The geometry is pure arithmetic over
  /// the sheet's rows, so it answers for any count without the document
  /// having to be rebuilt (which is the whole reason the sheet stays
  /// memoized against the committed cut).
  ({int page, int half, double y}) cutEndLineFor(int playbackFrameCount) {
    final lastFrame = playbackFrameCount - 1;
    final position = positionOfFrame(lastFrame);
    return (
      page: position.page,
      half: position.half,
      y: frameRowTop(lastFrame) + rowHeight,
    );
  }

  /// The sheet's page notation ('1/2'). The printed ページ header box and
  /// the panel's page readout (R26 #41) share this one spelling so they
  /// can never drift apart.
  String pageLabel(int pageIndex) =>
      continuous ? '1/1' : '${pageIndex + 1}/${document.pages.length}';

  /// Logical size of the whole document — one paper in continuous and
  /// single-page (R26 #41) modes, the stack otherwise.
  Size get documentSize {
    final pageCount = document.pages.length;
    final height = continuous || resolvedSinglePage != null
        ? documentMargin * 2 + paperHeight
        : documentMargin * 2 +
              pageCount * paperHeight +
              (pageCount - 1) * pageGap;
    return Size(documentMargin * 2 + paperWidth, height);
  }
}

/// Paints the sheet document — the paper form (header band, Direction memo
/// band, group/letter rows, second-heavy grid), cel numbers, holds, ○
/// marks, X cells, camera keys, the data-driven cut-end strikethrough and
/// the playhead row — under the panel viewport transform (the same
/// inside-the-picture transform the brush canvas uses, crisp at any zoom).
class TimesheetDocumentPainter extends CustomPainter {
  TimesheetDocumentPainter({
    required this.document,
    required this.layout,
    this.viewport,
    this.notation = TimesheetNotation.english,
    this.layers,
    this.dragPreview,
    this.cutId,
    this.effectiveRatio = 1.0,
  }) : accent = AppColors.accent,
       super(repaint: dragPreview);

  /// Device pixels per LOGICAL pixel — monitor ratio × UI scale.
  ///
  /// Only [_textZoomThreshold] uses it, and only because that threshold is
  /// a legibility question and therefore a device-pixel one. Defaulting to
  /// 1.0 keeps every focused test and the PSD export path unchanged.
  final double effectiveRatio;

  /// The accent at the moment this painter was BUILT.
  ///
  /// The sheet tints its SE name boxes with the live accent
  /// (`AppColors.accent` is a notifier-backed getter), and reading a live
  /// value inside `paint` while `shouldRepaint` does not compare it is
  /// how a picture goes stale: the colour is baked into the recorded
  /// `Paint` at record time, the retained layer is reused, and changing
  /// the accent leaves the old tint on the sheet.
  ///
  /// Capturing it here turns it into ordinary painter state that
  /// `shouldRepaint` can see. (This predates the panel-bake round — a
  /// plain `RepaintBoundary` froze it exactly the same way.)
  final Color accent;

  final TimesheetDocument document;
  final TimesheetDocumentLayout layout;
  final CanvasViewport? viewport;

  /// The NOTATION-language vocabulary the sheet prints in (UI-R10 #7);
  /// focused tests keep the pre-R10 English default.
  final TimesheetNotation notation;

  /// Which strata to draw; null = all of them (the pre-split single
  /// painter, which exports and focused tests still want).
  ///
  /// UI-R10 #9 gave the sheet the FORM/CONTENT split for the PSD export;
  /// it speaks [SheetPaintLayer] now, the vocabulary the conte and the cut
  /// envelope share. The printed form (grid, boxes, printed labels) is
  /// static per document STRUCTURE; the content (cell texts, header
  /// values, memo, data lines) is what edits and drag previews re-print;
  /// the paper is the sheet under both.
  final Set<SheetPaintLayer>? layers;

  /// The session's scoped drag channel (UI-R10 #9, replacing the UI-R9
  /// patch overlay): while a timeline drag targets an ACTION column's
  /// layer, THAT column's cells re-derive from the preview layer at paint
  /// time — the content stratum repaints per step (texts only, the form
  /// underneath never re-records), the document stays stale until the
  /// release commits.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// Which cut this sheet is printing, so a cut-length drag can be read off
  /// [dragPreview]. Null in exports and focused tests — the sheet then
  /// prints the committed length, which is what those want anyway.
  final CutId? cutId;

  bool _draws(SheetPaintLayer layer) =>
      layers == null || layers!.contains(layer);

  bool get _drawPaper => _draws(SheetPaintLayer.paper);
  bool get _drawForm => _draws(SheetPaintLayer.form);
  bool get _drawContent => _draws(SheetPaintLayer.content);

  /// The cut's length as this PAINT should print it: the in-flight drag's
  /// duration while one is targeting this cut, the document's otherwise.
  ///
  /// Read LIVE at paint time, never captured — the same discipline
  /// [displayCellsFor] already follows one method below. The document stays
  /// stale on purpose (it is memoized against the committed cut); only the
  /// things a drag actually moves ask this.
  int get livePlaybackFrameCount => timelineCutEndPreviewFrameCount(
    preview: dragPreview?.value,
    cutId: cutId,
    playbackFrameCount: document.playbackFrameCount,
  );

  /// The column's display cells, with an in-flight drag preview
  /// substituted for its layer. Every layer-backed column kind previews
  /// (UI-R18 #7 — action, SE, camera instruction): the column's own baked
  /// [TimesheetColumn.previewCellsBuilder] re-derives the cells, so the
  /// painter never learns each kind's recipe. SE previews arrive as
  /// DISPLAY clones under the same id (the timeline's seam), so the SE
  /// windowing stays the document's job.
  List<TimesheetCell> displayCellsFor(TimesheetColumn column) {
    final preview = dragPreview?.value;
    final layerId = column.layerId;
    final rebuild = column.previewCellsBuilder;
    if (preview == null || layerId == null || rebuild == null) {
      return column.cells;
    }
    final previewLayer = timelineDragPreviewLayerFor(preview, layerId);
    if (previewLayer == null) {
      return column.cells;
    }
    return rebuild(previewLayer);
  }

  /// H4 (유저 2026-08-21): 「타임시트패널의 타임시트 바탕 용지색, 애매한
  /// 회색인데 **완전한 흰색으로**」.
  ///
  /// ⛔It was `0xFFF6F4F0`, a warm off-white chosen to read as paper stock.
  /// The sheet is a document of dense small type, so that tint spent
  /// contrast against the ink to suggest something nobody asked for — and
  /// 「애매한 회색」 is exactly how an unasked-for tint reads.
  static const Color _paper = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF33322F);
  static const Color _gridLight = Color(0xFFCFC9BF);
  static const Color _gridMedium = Color(0xFFA9A296);
  static const Color _gridBold = Color(0xFF6E6759);

  /// Below this many DEVICE pixels per document pixel the per-cell texts
  /// stop painting (paper overview).
  ///
  /// 🚨Compared against `zoom × effectiveRatio`, NOT against the render
  /// zoom alone. The timesheet is a document view, so R11 excludes it from
  /// the UI scale by DIVIDING its render zoom when the scale goes up —
  /// which meant a raw comparison moved the cutoff with the chrome:
  /// raising the interface to 150% held the sheet at exactly the same
  /// physical size and made every cell text vanish, with the readout still
  /// saying 45%. On a 2× tablet at 150% the cutoff sat at a readout of
  /// 105%, i.e. textless at every zoom anyone works at.
  ///
  /// ⚠️This also moves the cutoff on high-DPR displays (render 0.175 on a
  /// 2× screen). That is the physically correct reading — the question is
  /// whether the glyphs are legible, which is a device-pixel question —
  /// and it is what the canvas layer stack already does.
  static const double _textZoomThreshold = 0.35;

  /// Turns the culling off, so a test can prove it changes no pixel.
  ///
  /// Culling may only ever remove work the clip would have thrown away,
  /// so "same bytes with it on and off" is the whole contract and is
  /// worth a real rendered comparison rather than an assertion about
  /// row indices.
  @visibleForTesting
  static bool debugDisableCulling = false;

  /// The document-space rectangle the panel can actually show, or null
  /// when culling is off. Set once at the top of [paint], read by the
  /// three row loops and the page/half skips.
  Rect? _cull;

  /// The rows of a half starting at [rowsTop] that [_cull] can reach.
  ///
  /// This is OpenToonz's move — it turns the damage rect into a CELL
  /// INDEX RANGE (`xyRectToRange` → `r0..r1`) and iterates only those,
  /// with no offscreen cache for the grid at all. That is the shape of
  /// the finding that sent us here: a sheet grid is not expensive, and
  /// ours only looked expensive because it was drawing a whole B4
  /// document — ~334 lines and ~111 paragraphs — to fill a dock a few
  /// hundred pixels tall.
  ///
  /// A row of slack each side, because a row's ink is allowed to reach a
  /// little past its own band (text baselines, the SE dotted guide).
  (int, int) _rowRange(double rowsTop, int rowCount) {
    final cull = _cull;
    if (cull == null) {
      return (0, rowCount);
    }
    const height = TimesheetDocumentLayout.rowHeight;
    final first = ((cull.top - rowsTop) / height).floor() - 1;
    final last = ((cull.bottom - rowsTop) / height).ceil() + 1;
    return (first.clamp(0, rowCount), last.clamp(0, rowCount));
  }

  /// Whether anything between [top] and [bottom] can be seen.
  bool _bandVisible(double top, double bottom) {
    final cull = _cull;
    return cull == null || (bottom >= cull.top && top <= cull.bottom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final resolvedViewport = viewport;
    if (resolvedViewport != null) {
      // P8's ONE transform. ⛔The snap already happened at the host, so
      // this, the playhead overlay and the ink windows all share one
      // value; passing the ratio keeps the helper's own snap idempotent
      // rather than a second, coarser rounding.
      applyViewportTransform(
        canvas,
        resolvedViewport,
        devicePixelRatio: effectiveRatio,
      );
    }
    // The clip above, carried back through the viewport transform into
    // document space. Everything outside it is already invisible; the
    // only question is whether we spend the ops finding that out.
    _cull = debugDisableCulling || resolvedViewport == null
        ? null
        : (resolvedViewport.zoom <= 0
              ? null
              : Rect.fromLTWH(
                  -resolvedViewport.panX / resolvedViewport.zoom,
                  -resolvedViewport.panY / resolvedViewport.zoom,
                  size.width / resolvedViewport.zoom,
                  size.height / resolvedViewport.zoom,
                ));
    // DEVICE pixels per document pixel — see [_textZoomThreshold].
    final drawTexts =
        (resolvedViewport?.zoom ?? 1.0) * effectiveRatio >= _textZoomThreshold;

    if (layout.continuous) {
      _bands.paintPaper(canvas, 0);
      _bands.paintHeaderBand(canvas, 0, drawTexts: drawTexts);
      if (_drawContent) {
        _bands.paintMemoBand(canvas, 0, drawTexts: drawTexts);
      }
      _paintHalf(
        canvas,
        pageIndex: 0,
        half: 0,
        startFrame: 0,
        rowCount: document.rowCount,
        drawTexts: drawTexts,
      );
    } else {
      // Page view prints only the page on screen (R26 #41); the stacked
      // document prints them all.
      for (final pageIndex in layout.visiblePageIndexes) {
        final page = document.pages[pageIndex];
        // A whole page off screen costs nothing at all — this is where
        // the stacked multi-page document stops being O(document).
        final pageBounds = layout.pageRect(page.index);
        if (!_bandVisible(pageBounds.top, pageBounds.bottom)) {
          continue;
        }
        _bands.paintPaper(canvas, page.index);
        _bands.paintHeaderBand(canvas, page.index, drawTexts: drawTexts);
        if (_drawContent) {
          _bands.paintMemoBand(canvas, page.index, drawTexts: drawTexts);
        }
        for (var half = 0; half < 2; half += 1) {
          final rowCount = layout.halfRowCount(half);
          if (rowCount <= 0) {
            continue;
          }
          _paintHalf(
            canvas,
            pageIndex: page.index,
            half: half,
            startFrame:
                page.startFrame + (half == 0 ? 0 : document.halfFrameCount),
            rowCount: rowCount,
            drawTexts: drawTexts,
          );
        }
      }
    }
    if (_drawContent) {
      _bands.paintCutEndLine(canvas);
      // A text glyph: it honors the same zoom threshold every per-cell
      // text does (the paper-overview zoom hides the writing).
      if (drawTexts) {
        _se.paintSeCrossingMarks(canvas);
      }
    }

    canvas.restore();
  }

  // ── the bands: their own object, in their own file ──────────────────
  //
  // A collaborator (timesheet/document_painter/timesheet_bands_pass.dart, a part of this
  // library). The painter keeps the passes its paint() calls.
  late final _TimesheetBandsPass _bands = _TimesheetBandsPass(this);

  static String headerFieldLabel(
    TimesheetHeaderField field, [
    TimesheetNotation notation = TimesheetNotation.english,
  ]) => _TimesheetBandsPass.headerFieldLabel(field, notation);

  // ── the SE pass: its own object, in its own file ────────────────────
  //
  // A collaborator (timesheet/document_painter/timesheet_se_pass.dart, a part of this
  // library). The painter keeps the passes its paint() calls.
  late final _TimesheetSePass _se = _TimesheetSePass(this);

  void _paintHalf(
    Canvas canvas, {
    required int pageIndex,
    required int half,
    required int startFrame,
    required int rowCount,
    required bool drawTexts,
  }) {
    final left = layout.halfLeft(pageIndex, half);
    final rowsTop = layout.halfRowsTop(pageIndex);
    final rowsBottom = rowsTop + rowCount * TimesheetDocumentLayout.rowHeight;
    final right = left + layout.halfWidth;
    final columnsTop = rowsTop - layout.columnsHeaderHeight;
    final lettersTop = rowsTop - TimesheetDocumentLayout.letterRowHeight;

    final lightPaint = Paint()
      ..color = _gridLight
      ..strokeWidth = 0.6;
    final mediumPaint = Paint()
      ..color = _gridMedium
      ..strokeWidth = 1.0;
    final boldPaint = Paint()
      ..color = _gridBold
      ..strokeWidth = 1.6;

    // Group titles + letter row (printed form).
    if (drawTexts && _drawForm) {
      _bands.paintGroupTitles(canvas, left, columnsTop);
      for (var column = 0; column < document.columns.length; column += 1) {
        // Unbacked slots print nothing — no placeholder letters.
        if (document.columns[column].label.isEmpty) {
          continue;
        }
        final columnLeft = left + layout.columnLeftInHalf(column);
        final columnWidth = layout.columnWidthFor(
          document.columns[column].kind,
        );
        _text(
          canvas,
          document.columns[column].label,
          Offset(columnLeft + columnWidth / 2, lettersTop + 2),
          fontSize: 9,
          color: _ink,
          centeredAtX: true,
          maxWidth: columnWidth - 2,
        );
      }
    }
    if (_drawForm) {
      canvas.drawLine(
        Offset(left, columnsTop),
        Offset(right, columnsTop),
        mediumPaint,
      );
      canvas.drawLine(
        Offset(left, lettersTop),
        Offset(right, lettersTop),
        lightPaint,
      );
    }

    // Row lines: light per frame, medium every 6 frames, bold on second
    // boundaries. SE columns print NO interior frame rules (R6-② — the
    // real Toei sheet leaves the S strip clean; its vertical borders and
    // the table's outer edges stay), so interior lines draw in segments
    // skipping the SE ranges.
    if (!_drawForm) {
      // Content-only: skip the grid entirely and print the cells.
      _paintHalfCells(
        canvas,
        left: left,
        rowsTop: rowsTop,
        startFrame: startFrame,
        rowCount: rowCount,
        drawTexts: drawTexts,
      );
      return;
    }
    final seRanges = <(double, double)>[];
    for (var column = 0; column < document.columns.length; column += 1) {
      if (document.columns[column].kind != TimesheetColumnKind.se) {
        continue;
      }
      final seLeft = left + layout.columnLeftInHalf(column);
      final seRight = seLeft + layout.columnWidthFor(TimesheetColumnKind.se);
      if (seRanges.isNotEmpty && seRanges.last.$2 >= seLeft) {
        seRanges[seRanges.length - 1] = (seRanges.last.$1, seRight);
      } else {
        seRanges.add((seLeft, seRight));
      }
    }
    final numbersRight = left - 4;
    final (firstRow, lastRow) = _rowRange(rowsTop, rowCount);
    for (var row = firstRow; row <= lastRow; row += 1) {
      final frame = startFrame + row;
      final y = rowsTop + row * TimesheetDocumentLayout.rowHeight;
      final Paint paint;
      if (frame % document.fps == 0 || row == rowCount) {
        paint = boldPaint;
      } else if (frame % 6 == 0) {
        paint = mediumPaint;
      } else {
        paint = lightPaint;
      }
      if (row == 0 || row == rowCount || seRanges.isEmpty) {
        // The table's outer edges close full width.
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
        continue;
      }
      var segmentStart = left;
      for (final (seLeft, seRight) in seRanges) {
        if (seLeft > segmentStart) {
          canvas.drawLine(Offset(segmentStart, y), Offset(seLeft, y), paint);
        }
        segmentStart = seRight;
      }
      if (segmentStart < right) {
        canvas.drawLine(Offset(segmentStart, y), Offset(right, y), paint);
      }
    }

    // Vertical lines: half edges + column separators (bold at section
    // changes). The number gutter draws NO lines — bare numbers on paper.
    canvas.drawLine(
      Offset(left, columnsTop),
      Offset(left, rowsBottom),
      boldPaint,
    );
    canvas.drawLine(
      Offset(right, columnsTop),
      Offset(right, rowsBottom),
      boldPaint,
    );
    for (var column = 1; column < document.columns.length; column += 1) {
      final x = left + layout.columnLeftInHalf(column);
      final sectionEdge =
          document.columns[column].kind != document.columns[column - 1].kind;
      canvas.drawLine(
        Offset(x, sectionEdge ? columnsTop : lettersTop),
        Offset(x, rowsBottom),
        sectionEdge ? boldPaint : lightPaint,
      );
    }

    // Gutter frame numbers on even frames, bare on the paper left of the
    // half — page-local on paper, global in the continuous strip. On each
    // second's LAST frame row (24, 48, …) the second index prints BOLD in
    // place of the frame number — the paper convention (A-1 form).
    if (drawTexts) {
      for (var row = firstRow; row < lastRow; row += 1) {
        final frame = startFrame + row;
        final printed = layout.continuous
            ? frame + 1
            : frame % document.pageFrameCount + 1;
        final rowTop = rowsTop + row * TimesheetDocumentLayout.rowHeight;
        if (printed % document.fps == 0) {
          _text(
            canvas,
            '${printed ~/ document.fps}',
            Offset(numbersRight, rowTop + 3),
            fontSize: 10,
            bold: true,
            color: _gridBold,
            rightAlignedAtX: true,
          );
          continue;
        }
        if (printed.isOdd) {
          continue;
        }
        _text(
          canvas,
          '$printed',
          Offset(numbersRight, rowTop + 4),
          fontSize: 8,
          color: _gridMedium,
          rightAlignedAtX: true,
        );
      }
    }

    if (_drawContent) {
      _paintHalfCells(
        canvas,
        left: left,
        rowsTop: rowsTop,
        startFrame: startFrame,
        rowCount: rowCount,
        drawTexts: drawTexts,
      );
    }
  }

  /// The CONTENT stratum of one half (UI-R10 #9): every column's cell
  /// texts/marks/lines, with in-flight drag previews substituted per
  /// column — this is what re-prints per drag step while the form
  /// underneath never re-records.
  void _paintHalfCells(
    Canvas canvas, {
    required double left,
    required double rowsTop,
    required int startFrame,
    required int rowCount,
    required bool drawTexts,
  }) {
    for (var column = 0; column < document.columns.length; column += 1) {
      final spec = document.columns[column];
      final cells = displayCellsFor(spec);
      final columnLeft = left + layout.columnLeftInHalf(column);
      final columnWidth = layout.columnWidthFor(spec.kind);
      final centerX = columnLeft + columnWidth / 2;
      final (firstRow, lastRow) = _rowRange(rowsTop, rowCount);
      for (var row = firstRow; row < lastRow; row += 1) {
        final frame = startFrame + row;
        if (frame >= cells.length) {
          break;
        }
        final cell = cells[frame];
        final seColumn = spec.kind == TimesheetColumnKind.se;
        final cellTop = rowsTop + row * TimesheetDocumentLayout.rowHeight;
        final cellBottom = cellTop + TimesheetDocumentLayout.rowHeight;
        final cellCenterY = cellTop + TimesheetDocumentLayout.rowHeight / 2;
        if (cell.kind == TimesheetCellKind.empty) {
          // SE columns mark their empty stretches the print-sheet way: a
          // dotted center guide, washed light gray while the toggle is on.
          if (seColumn && frame < document.playbackFrameCount) {
            _se.paintSeEmptyRow(
              canvas,
              columnLeft: columnLeft,
              columnWidth: columnWidth,
              centerX: centerX,
              cellTop: cellTop,
            );
          }
          continue;
        }
        switch (cell.kind) {
          case TimesheetCellKind.drawing:
            if (drawTexts) {
              if (seColumn) {
                _se.paintSeEntryStart(
                  canvas,
                  cell: cell,
                  row: row,
                  rowCount: rowCount,
                  columnLeft: columnLeft,
                  columnWidth: columnWidth,
                  centerX: centerX,
                  cellTop: cellTop,
                );
              } else {
                _text(
                  canvas,
                  cell.label ?? '',
                  Offset(centerX, cellTop + 3),
                  fontSize: 10,
                  color: _ink,
                  centeredAtX: true,
                );
              }
            }
          case TimesheetCellKind.held:
            if (seColumn) {
              // Toei SE notation: no hold line down the dialogue; the
              // block's END closes with the full-width red bar instead.
              if ((cell.spanOffset ?? 0) == (cell.spanLength ?? 1) - 1) {
                _se.paintSeRedBar(
                  canvas,
                  columnLeft: columnLeft,
                  columnWidth: columnWidth,
                  y: cellBottom - 1,
                );
              }
              break;
            }
            // ACTION hold bar: off by default; with a threshold N it runs
            // from the (N+1)th comma of N+ holds only (industry N=3).
            final threshold = document.exposureBarThreshold;
            if (threshold != null && (cell.spanOffset ?? 0) >= threshold) {
              canvas.drawLine(
                Offset(centerX, cellTop),
                Offset(centerX, cellBottom),
                Paint()
                  ..color = _ink
                  ..strokeWidth = 1.0,
              );
            }
          case TimesheetCellKind.cameraSpan:
            canvas.drawLine(
              Offset(centerX, cellTop),
              Offset(centerX, cellBottom),
              Paint()
                ..color = _ink
                ..strokeWidth = 1.6,
            );
          case TimesheetCellKind.mark:
            // Block-owned inbetween dot: FILLED ● (same glyph as the
            // timeline cells), not the legacy hollow ○.
            canvas.drawCircle(
              Offset(centerX, cellCenterY),
              2.8,
              Paint()..color = _ink,
            );
          case TimesheetCellKind.repeatStart:
            // A repeat ghost chain prints the sheet CONVENTION (UI-R13
            // #4): its first row writes the cel it restarts on, and the
            // NOTATION-language repeat word runs VERTICALLY from the
            // next row (UI-R11 #14) — the expanded cel numbers live in
            // the timeline for exporters, never here. No guide line.
            if (drawTexts) {
              _text(
                canvas,
                cell.label ?? '',
                Offset(centerX, cellTop + 3),
                fontSize: 10,
                color: _ink,
                centeredAtX: true,
              );
              final wordRows = (cell.spanLength ?? 1) - 1;
              if (wordRows > 0) {
                _paintVerticalWord(
                  canvas,
                  notation.repeat,
                  centerX: centerX,
                  top: cellTop + TimesheetDocumentLayout.rowHeight,
                  rows: wordRows,
                  columnWidth: columnWidth,
                );
              }
            }
          case TimesheetCellKind.repeatSpan:
            break; // The word above covers the chain (UI-R11 #14).
          case TimesheetCellKind.holdStart:
            // One cel held from row 1: the rear hold chain prints the
            // notation hold word (止め) vertically (UI-R11 #15).
            if (drawTexts) {
              _paintVerticalWord(
                canvas,
                notation.hold,
                centerX: centerX,
                top: cellTop,
                rows: cell.spanLength ?? 1,
                columnWidth: columnWidth,
              );
            }
          case TimesheetCellKind.emptyRunStart:
            if (drawTexts) {
              _text(
                canvas,
                '×',
                Offset(centerX, cellTop + 2),
                fontSize: 11,
                color: _gridMedium,
                centeredAtX: true,
              );
            }
          case TimesheetCellKind.cameraKey:
            canvas.drawCircle(
              Offset(centerX, cellCenterY),
              3.4,
              Paint()..color = _ink,
            );
          case TimesheetCellKind.instructionStart:
          case TimesheetCellKind.instructionSpan:
          case TimesheetCellKind.instructionEnd:
            // One shared per-row renderer — the printed sheet mirrors the
            // X-sheet column verbatim: the mark owns the whole cell width,
            // A/B center in their endpoint cells (frame-name style) and
            // the writing centers on the span's middle row.
            _instructions.paintInstructionRow(
              canvas,
              cell: cell,
              columnLeft: columnLeft,
              columnWidth: columnWidth,
              centerX: centerX,
              cellTop: cellTop,
              drawTexts: drawTexts,
            );
          case TimesheetCellKind.empty:
            break;
        }
      }
    }
  }

  // ── the instruction pass: its own object, in its own file ───────────
  //
  // A collaborator (timesheet/document_painter/timesheet_instruction_pass.dart, a part of this
  // library). The painter keeps the passes its paint() calls.
  late final _TimesheetInstructionPass _instructions =
      _TimesheetInstructionPass(this);

  /// A notation word written VERTICALLY down a chain of rows (UI-R11
  /// #14/#15 — リ/ピ/ー/ト one per row): with fewer rows than characters
  /// the glyphs shrink and pack so the whole word still fits the span.
  ///
  /// R10 R6: the rotation table and the shrink rule moved to
  /// `ui/text/vertical_writing.dart` and the drawing to [paintVerticalText],
  /// so the widget tree's section band writes vertically the same way this
  /// sheet does — it used to stack every glyph upright and leave `ー` lying
  /// on its side.
  void _paintVerticalWord(
    Canvas canvas,
    String word, {
    required double centerX,
    required double top,
    required int rows,
    required double columnWidth,
  }) {
    if (word.isEmpty || rows <= 0) {
      return;
    }
    paintVerticalText(
      canvas,
      word,
      style: const TextStyle(color: _ink, fontSize: 10),
      centerX: centerX,
      top: top,
      mainExtent: rows * TimesheetDocumentLayout.rowHeight,
      naturalCellExtent: TimesheetDocumentLayout.rowHeight,
      maxCellWidth: columnWidth - 2,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    required double fontSize,
    Color color = _ink,
    bool bold = false,
    bool centeredAtX = false,
    bool rightAlignedAtX = false,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final offset = centeredAtX
        ? anchor - Offset(painter.width / 2, 0)
        : rightAlignedAtX
        ? anchor - Offset(painter.width, 0)
        : anchor;
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant TimesheetDocumentPainter oldDelegate) {
    return !identical(oldDelegate.document, document) ||
        oldDelegate.layout.continuous != layout.continuous ||
        oldDelegate.layout.resolvedSinglePage != layout.resolvedSinglePage ||
        oldDelegate.viewport != viewport ||
        !identical(oldDelegate.notation, notation) ||
        !setEquals(oldDelegate.layers, layers) ||
        // Everything `paint` reads has to be compared here or the sheet
        // keeps printing the old value. `accent` tints the SE name boxes
        // and `cutId` decides which cut's end line is data — the latter
        // was masked only because `document` identity happens to change
        // with the active cut, which is a coincidence and not a contract.
        oldDelegate.accent != accent ||
        oldDelegate.cutId != cutId ||
        // 🐛SAME LAW, AND IT WAS ALREADY BROKEN before this line existed:
        // `paint` reads this for the text-zoom threshold (and now for the
        // transform), so a monitor or UI-scale change has to reach the
        // sheet. It did not — the threshold kept the old value until
        // something else happened to repaint.
        oldDelegate.effectiveRatio != effectiveRatio ||
        !identical(oldDelegate.dragPreview, dragPreview);
  }
}

/// The sheet's PLAYHEAD row highlight as its own repaint-only layer
/// (R13-2: the cursor-layer discipline, timesheet edition). The playhead
/// used to be a parameter of [TimesheetDocumentPainter], so every cursor
/// move, committed seek and playback tick re-recorded the ENTIRE B4 sheet
/// — with the timesheet docked visible that repaint was the biggest
/// single share of the frame-flip hitch. This painter repaints one rect
/// through [CustomPainter.repaint]; the sheet above never hears about the
/// playhead at all.
class TimesheetPlayheadPainter extends CustomPainter {
  TimesheetPlayheadPainter({
    required this.document,
    required this.layout,
    required this.resolvePlayheadFrame,
    this.viewport,
    this.effectiveRatio = 1.0,
    super.repaint,
  });

  final TimesheetDocument document;
  final TimesheetDocumentLayout layout;

  /// Reads the CURRENT playhead frame at paint time (the repaint
  /// listenable drives when that happens).
  final int? Function() resolvePlayheadFrame;
  final CanvasViewport? viewport;

  /// 🚨THE SAME RATIO THE DOCUMENT PAINTER GETS. This overlay sits ON the
  /// rows that painter drew; a different snap grid puts it a sub-pixel off
  /// them.
  final double effectiveRatio;

  static const Color _playhead = Color(0x334FA8A0);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = resolvePlayheadFrame();
    if (frame == null || frame < 0 || frame >= document.rowCount) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final resolvedViewport = viewport;
    if (resolvedViewport != null) {
      // 🚨THE SAME TRANSFORM THE DOCUMENT TOOK, from the same host-snapped
      // viewport — this overlay highlights the rows that painter drew, so
      // a different grid would put the playhead a sub-pixel off them.
      applyViewportTransform(
        canvas,
        resolvedViewport,
        devicePixelRatio: effectiveRatio,
      );
    }
    final position = layout.positionOfFrame(frame);
    // Page view (R26 #41): the playhead highlights nothing while the user
    // is looking at another page.
    if (!layout.visiblePageIndexes.contains(position.page)) {
      canvas.restore();
      return;
    }
    final left = layout.halfLeft(position.page, position.half);
    canvas.drawRect(
      Rect.fromLTWH(
        left,
        layout.frameRowTop(frame),
        layout.halfWidth,
        TimesheetDocumentLayout.rowHeight,
      ),
      Paint()..color = _playhead,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TimesheetPlayheadPainter oldDelegate) {
    return !identical(oldDelegate.document, document) ||
        oldDelegate.layout.continuous != layout.continuous ||
        oldDelegate.layout.resolvedSinglePage != layout.resolvedSinglePage ||
        oldDelegate.viewport != viewport ||
        oldDelegate.effectiveRatio != effectiveRatio;
  }
}
