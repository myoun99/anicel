import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/camera_instruction.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart' show InbetweenMark;
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/timesheet_document.dart';
import '../../models/timesheet_info.dart';
import '../text/dialogue_fit_layout.dart' show dialogueGlyphCenters;
import '../text/dialogue_fit_paint.dart';
import '../text/vertical_writing.dart'
    show verticalTextCells, verticalTextSpanCount;
import '../canvas/viewport_canvas_transform.dart';
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import '../timeline/inbetween_mark_painter.dart';
import '../timeline/timeline_instruction_row_visual.dart'
    show instructionLabelInset;
import '../timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount, timelineDrawnEndPreviewFrameCount;
import '../timeline/timeline_drag_preview.dart';
import 'timesheet_notation.dart';
import '../repaint_props.dart';
import '../sheet_painting.dart' show paintSheetInkWindow, paintSheetPaper;
import '../timeline/memo_token.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

part 'document_painter/timesheet_instruction_pass.dart';
part 'document_painter/timesheet_se_pass.dart';
part 'document_painter/timesheet_bands_pass.dart';
part 'document_painter/timesheet_cells_pass.dart';

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

  /// Which halves of a page actually carry rows, in print order.
  ///
  /// The layout's own fact, asked by both consumers — the painter's cell
  /// pass and the ink windows, which must cover exactly the strips the
  /// painter prints. They used to walk `half 0..1, skip halfRowCount <= 0`
  /// each for themselves.
  List<({int half, int rowCount})> get halfStrips => [
    for (var half = 0; half < 2; half += 1)
      if (halfRowCount(half) > 0) (half: half, rowCount: halfRowCount(half)),
  ];

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
  /// [pageCount] overrides the document's sheet count for a paint that is
  /// following a cut-length drag (F-88) — the paper itself still re-flows
  /// on the release.
  String pageLabel(int pageIndex, {int? pageCount}) => continuous
      ? '1/1'
      : '${pageIndex + 1}/${pageCount ?? document.pages.length}';

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

/// Clips to the panel and enters DOCUMENT SPACE — the prologue every
/// painter over this sheet shares, so the paper and the overlays on it
/// cannot land on different grids. The caller owns the matching
/// `canvas.restore()`.
///
/// P8's ONE transform. ⛔The snap already happened at the host, so
/// this, the playhead overlay and the ink windows all share one
/// value; passing the ratio keeps the helper's own snap idempotent
/// rather than a second, coarser rounding.
void _enterDocumentSpace(
  Canvas canvas,
  Size size,
  CanvasViewport? viewport,
  double effectiveRatio,
) {
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  if (viewport != null) {
    applyViewportTransform(canvas, viewport, devicePixelRatio: effectiveRatio);
  }
}

/// Paints the sheet document — the paper form (header band, Direction memo
/// band, group/letter rows, second-heavy grid), cel numbers, holds,
/// in-between marks, X cells, camera keys, the data-driven cut-end
/// strikethrough and the playhead row — under the panel viewport transform
/// (the same
/// inside-the-picture transform the brush canvas uses, crisp at any zoom).
class TimesheetDocumentPainter extends CustomPainter with RepaintOnProps {
  TimesheetDocumentPainter({
    required this.document,
    required this.layout,
    required this.face,
    this.viewport,
    this.notation = TimesheetNotation.english,
    this.layers,
    this.dragPreview,
    this.cutId,
    this.effectiveRatio = 1.0,
    this.ink = const [],
    this.inkImageFor,
    this.liveInkKeys = const {},
    Listenable? inkRepaint,
  }) : accent = AppColors.accent,
       super(repaint: Listenable.merge([dragPreview, inkRepaint]));

  /// The windows the sheet's ink shows through — the walk the brush writes
  /// through too (`timesheetInkWindows`), handed in by whoever built it.
  final List<SheetInk> ink;

  /// A window's baked ink raster, or null to print none there.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// Keys a LIVE brush window is already showing: skipped here, so
  /// translucent ink never composites twice.
  final Set<BrushFrameKey> liveInkKeys;

  /// Device pixels per LOGICAL pixel — monitor ratio × UI scale; the
  /// viewport transform lands the paper on the device grid with it.
  /// Defaulting to 1.0 keeps every focused test and the PSD export path
  /// unchanged.
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

  /// The app's face (`appFaceOf`) every word on the sheet is set in — the
  /// panel's and the export window's ambient style. 🗣️유저 2026-09-24
  /// (documents-in-which-face-Q1: 「둘다 앱글꼴로 통일」): the sheet named
  /// no face and printed in the OS's, so one project exported from two
  /// machines came out in two hands.
  final TextStyle face;

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

  /// The DRAWN length this paint should print by — the live cut end plus
  /// the のりしろ handle, the same law the blue line reads.
  int get liveDrawnFrameCount => timelineDrawnEndPreviewFrameCount(
    preview: dragPreview?.value,
    cutId: cutId,
    playbackFrameCount: document.playbackFrameCount,
    drawnFrameCount: document.drawnFrameCount,
  );

  /// How many sheets the cut fills as this paint should print it — the
  /// header's ページ readout follows a cut-length drag (F-88, 유저:
  /// 「타임라인 엔드라인 조절할때 타임시트헤더의 초수랑 페이지수같은것도
  /// 갱신」).
  ///
  /// ⚠️The NUMBER follows; the paper does not. The document is memoized
  /// against the committed cut, so the sheets themselves re-flow on the
  /// release and a drag step stays one text repaint — the split the
  /// content stratum exists for.
  int get livePageCount =>
      timesheetPageCount(liveDrawnFrameCount, document.pageFrameCount);

  // ── the cells pass: its own object, in its own file ─────────────────
  //
  // A collaborator (timesheet/document_painter/timesheet_cells_pass.dart, a part of this
  // library). The painter keeps the passes its paint() calls.
  late final _TimesheetCellsPass _cells = _TimesheetCellsPass(this);

  List<TimesheetCell> displayCellsFor(TimesheetColumn column) =>
      _cells.displayCellsFor(column);

  /// The text a header box prints on [pageIndex] — the same call the
  /// content stratum paints with, so what a test reads is what the sheet
  /// says (the length and the sheet count follow a drag live, F-88).
  String headerValueFor(TimesheetHeaderField field, int pageIndex) =>
      _bands.headerFieldValue(field, pageIndex);

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

  // ↩️THE WRITING NEVER DROPS OUT (tiny-glyphs-shrink-not-vanish). Below
  // 35% device zoom every header, memo and cell text used to stop painting
  // — a cutoff the sheet's first commit put in 「for overview panning」
  // (f3dd6f6f, 2026-07-07) with no user behind it, against the user's own
  // rule for the sheet's glyphs: 「엄청 작아지는 한이 있어도 절대 안
  // 사라지도록」 (timeline_cell_style.dart). Measured before it went
  // (2026-09-23, 144 frames × 5 rows, debug): 1.5 → 5.2 ms a paint at an
  // overview zoom — well inside a frame. The type now shrinks with the
  // paper at every zoom, as the timeline's does.

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

  /// Whether anything between [top] and [bottom] can be seen.
  bool _bandVisible(double top, double bottom) {
    final cull = _cull;
    return cull == null || (bottom >= cull.top && top <= cull.bottom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final resolvedViewport = viewport;
    _enterDocumentSpace(canvas, size, resolvedViewport, effectiveRatio);
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

    if (layout.continuous) {
      _bands.paintPaper(canvas, 0);
      _bands.paintHeaderBand(canvas, 0);
      if (_drawContent) {
        _bands.paintMemoBand(canvas, 0);
      }
      _cells.paintHalf(
        canvas,
        pageIndex: 0,
        half: 0,
        startFrame: 0,
        rowCount: document.rowCount,
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
        _bands.paintHeaderBand(canvas, page.index);
        if (_drawContent) {
          _bands.paintMemoBand(canvas, page.index);
        }
        for (final strip in layout.halfStrips) {
          _cells.paintHalf(
            canvas,
            pageIndex: page.index,
            half: strip.half,
            startFrame:
                page.startFrame +
                (strip.half == 0 ? 0 : document.halfFrameCount),
            rowCount: strip.rowCount,
          );
        }
      }
    }
    if (_drawContent) {
      _bands.paintCutEndLine(canvas);
      _se.paintSeCrossingMarks(canvas);
    }
    if (_draws(SheetPaintLayer.ink)) {
      _paintInk(canvas);
    }

    canvas.restore();
  }

  /// The handwriting, pen over paper: each window's surface where its
  /// placement lays it, but for the windows a live brush view is showing.
  ///
  /// ⛔The sheet printed no ink of its own: the writing showed only through
  /// the brush's windows, which mount with the brush switch on — so with
  /// the switch off (every sheet's default since 09-25) the timesheet's
  /// writing vanished while the conte's and the envelope's stayed (유저
  /// 2026-09-26: 「다 통일해줘. 기능은 어차피 생길수있어」).
  void _paintInk(Canvas canvas) {
    final imageFor = inkImageFor;
    if (imageFor == null) {
      return;
    }
    for (final window in ink) {
      if (liveInkKeys.contains(window.key)) {
        continue;
      }
      final image = imageFor(window.key);
      if (image != null) {
        paintSheetInkWindow(canvas, image, window.placement);
      }
    }
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
      style: face.copyWith(color: _ink, fontSize: 10),
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
        style: face.copyWith(
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
  Object get props => (
    layout.continuous,
    layout.resolvedSinglePage,
    viewport,
    face,
    // Null means ALL strata, which is a different input from an empty set,
    // so the null is carried instead of folded into one.
    layers == null ? null : BySet(layers!),
    // 🐛SAME LAW, AND IT WAS ALREADY BROKEN before this line existed:
    // `paint` reads this for the text-zoom threshold (and now for the
    // transform), so a monitor or UI-scale change has to reach the
    // sheet. It did not — the threshold kept the old value until
    // something else happened to repaint.
    effectiveRatio,
    // Each stratum compares what IT reads, and nothing another stratum
    // reads (유저 2026-09-25: 「그림 수정하거나 텍스트 바뀌거나 하는데
    // 용지 리빌드하면 너무 비효율적이잖아」): the paper and the form the
    // sheet's shape, the values the document, the ink its windows — so a
    // typed value re-records the values alone.
    _drawPaper || _drawForm ? _formShape : null,
    _drawContent ? _contentInputs : null,
    _draws(SheetPaintLayer.ink) ? _inkInputs : null,
  );

  /// What the paper and the form print from — the sheet's SHAPE: the
  /// columns and the letter over each, the pages, the header boxes, the
  /// frame rate and the notation. A value typed on the sheet is not in it.
  Object get _formShape => (
    ByList([
      for (final column in document.columns) (column.kind, column.label),
    ]),
    ByList([
      for (final page in document.pages)
        (page.index, page.startFrame, page.frameCount),
    ]),
    document.pageFrameCount,
    document.fps,
    ByList(document.visibleHeaderFields),
    ByIdentity(notation),
  );

  /// What the values print from.
  ///
  /// Everything `paint` reads has to be compared here or the sheet keeps
  /// printing the old value. `accent` tints the SE name boxes and `cutId`
  /// decides which cut's end line is data — the latter was masked only
  /// because `document` identity happens to change with the active cut,
  /// which is a coincidence and not a contract.
  Object get _contentInputs => (
    ByIdentity(document),
    ByIdentity(notation),
    accent,
    cutId,
    ByIdentity(dragPreview),
  );

  /// The ink's windows by value — the walk is rebuilt every build — and
  /// which of them a live brush view shows: mounting a window HIDES that
  /// key's baked ink here, unmounting shows it again.
  Object get _inkInputs => (
    ByList([for (final window in ink) (window.key, window.placement)]),
    BySet(liveInkKeys),
  );
}

/// The sheet's PLAYHEAD row highlight as its own repaint-only layer
/// (R13-2: the cursor-layer discipline, timesheet edition). The playhead
/// used to be a parameter of [TimesheetDocumentPainter], so every cursor
/// move, committed seek and playback tick re-recorded the ENTIRE B4 sheet
/// — with the timesheet docked visible that repaint was the biggest
/// single share of the frame-flip hitch. This painter repaints one rect
/// through [CustomPainter.repaint]; the sheet above never hears about the
/// playhead at all.
class TimesheetPlayheadPainter extends CustomPainter with RepaintOnProps {
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
    // 🚨THE SAME TRANSFORM THE DOCUMENT TOOK, from the same host-snapped
    // viewport — this overlay highlights the rows that painter drew, so
    // a different grid would put the playhead a sub-pixel off them. It is
    // the same CODE now, not a second copy kept in step by hand.
    _enterDocumentSpace(canvas, size, viewport, effectiveRatio);
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
  Object get props => (
    ByIdentity(document),
    layout.continuous,
    layout.resolvedSinglePage,
    viewport,
    effectiveRatio,
  );
}
