import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/page_stack.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/camera_instruction.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart' show InbetweenMark;
import '../../models/se_line_type.dart' show SeLineType;
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/timesheet_document.dart';
import '../../models/timesheet_info.dart';
import '../../models/timesheet_sheet_kind.dart';
import '../../models/timesheet_words.dart';
import '../../models/transition_geometry.dart'
    show TransitionSides, transitionSidesOf;
import '../text/dialogue_fit_layout.dart' show dialogueGlyphCenters;
import '../text/dialogue_fit_paint.dart';
import '../text/vertical_writing.dart'
    show verticalTextCells, verticalTextSpanCount;
import '../canvas/viewport_canvas_transform.dart';
import '../text/vertical_writing_text.dart';
import '../text/word_condensation.dart' show paintScaledText;
import '../theme/app_theme.dart';
import '../timeline/inbetween_mark_painter.dart';
import '../timeline/timeline_instruction_row_visual.dart'
    show instructionLabelInset;
import '../timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount, timelineDrawnEndPreviewFrameCount;
import '../timeline/timeline_drag_preview.dart';
import '../repaint_props.dart';
import '../sheet/sheet_ink_layer.dart' show SheetInkOnScreen;
import '../sheet_painting.dart' show paintSheetInkWindow, paintSheetPaper;
import '../timeline/memo_token.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

part 'document_painter/timesheet_instruction_pass.dart';
part 'document_painter/timesheet_se_pass.dart';
part 'document_painter/timesheet_bands_pass.dart';
part 'document_painter/timesheet_cells_pass.dart';
part 'document_painter/timesheet_books_pass.dart';

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
  TimesheetDocumentLayout({
    required this.document,
    this.continuous = false,
  });

  final TimesheetDocument document;
  final bool continuous;

  /// Page indexes this layout prints, in order: the single strip in
  /// continuous view, every page one under another otherwise.
  ///
  /// ↩️R26 #41 (07-23) printed ONE sheet at a time in page view and turned
  /// the page by swapping the paper under a view that never moved. F-201
  /// (유저 2026-09-27, F-201-timesheet-pages-Q1: 「타임시트 페이지 보기도
  /// 쌓는다」) lays them one under another again, as the conte's and the
  /// viewer's: a turn scrolls to the page (`CanvasBook`).
  List<int> get visiblePageIndexes => continuous
      ? const [0]
      : [for (final page in document.pages) page.index];

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

  /// The margin round the document, one sheet or many: the stack's.
  static const double documentMargin = PageStack.defaultMargin;

  /// The pages one under another — what the exports print and the page
  /// view shows.
  late final PageStack _stack = PageStack([
    for (final _ in document.pages) Size(paperWidth, paperHeight),
  ]);

  /// [_stack], for the panel's book: which page the reader is on and
  /// where a turn takes the view.
  PageStack get pageStack => _stack;

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

  /// The strips a page lays side by side ([TimesheetSheetKind.strips]).
  int get _strips => document.sheetKind.strips;

  /// A strip's width at its sheet's own column counts, before any scale:
  /// the ACTION and CELL blocks and the two fixed group allotments.
  static double _baseStripWidth(TimesheetSheetKind kind) =>
      kind.celColumns * (actionColumnWidth + celColumnWidth) +
      seGroupWidth +
      cameraGroupWidth;

  /// What the strips of [kind] span inside the paper's padding, their
  /// columns printed [scale] times as wide.
  static double _stripsSpan(TimesheetSheetKind kind, double scale) =>
      kind.strips * (frameNumberGutterWidth + _baseStripWidth(kind) * scale) +
      (kind.strips - 1) * halfGap;

  /// How much wider [kind]'s columns print than the 6-second sheet's: what
  /// spreads its strips across the SAME paper — 1 on the 6-second sheet,
  /// about 1.5 on the 3-second one, whose single strip spans what the two
  /// halves and the gap between them do (the reference sheet's wider
  /// columns, TOEI_3sec; 유저 2026-09-25: 「형식은 지금 우리가 만든 형식.
  /// 규격이나 사이즈나 그런거」).
  static double columnScaleOf(TimesheetSheetKind kind) {
    final span = _stripsSpan(TimesheetSheetKind.sixSeconds, 1);
    final fixed = _stripsSpan(kind, 0);
    return (span - fixed) / (kind.strips * _baseStripWidth(kind));
  }

  int get _seColumnCount => _columnCountOf(TimesheetColumnKind.se);

  /// Per-column width. Instance-level because the CAM and SE cells share
  /// a fixed group allotment ([cameraGroupWidth] / [seGroupWidth]): past
  /// the base two slots each column in that group narrows so the paper
  /// width stays put.
  double columnWidthFor(TimesheetColumnKind kind) =>
      _baseColumnWidthFor(kind) * columnScaleOf(document.sheetKind);

  /// [columnWidthFor] on the 6-second sheet's scale.
  double _baseColumnWidthFor(TimesheetColumnKind kind) {
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
      pagePadding * 2 +
      (frameNumberGutterWidth + halfWidth) * _strips +
      halfGap * (_strips - 1);

  /// Rows in the given half of a page (the second half takes the odd
  /// remainder).
  int halfRowCount(int half) => half < _strips - 1
      ? document.halfFrameCount
      : document.pageFrameCount - document.halfFrameCount * (_strips - 1);

  /// Which halves of a page actually carry rows, in print order.
  ///
  /// The layout's own fact, asked by both consumers — the painter's cell
  /// pass and the ink windows, which must cover exactly the strips the
  /// painter prints. They used to walk `half 0..1, skip halfRowCount <= 0`
  /// each for themselves.
  List<({int half, int rowCount})> get halfStrips => [
    for (var half = 0; half < _strips; half += 1)
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

  /// Top of a page's paper — the strip's in continuous view.
  double pageTop(int pageIndex) =>
      continuous ? documentMargin : _stack.pageRect(pageIndex).top;

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

  /// Top of the grid — its column header's top edge.
  double gridTop(int pageIndex) =>
      halfRowsTop(pageIndex) - columnsHeaderHeight;

  /// A book's tag (D24): its height, the step between two stacked, the size
  /// its words print at, and what it keeps clear of the memo band's bottom.
  static const double bookTagHeight = 13;
  static const double bookTagStep = 15;
  static const double bookTagFontSize = 9;
  static const double bookTagFloorGap = 2;

  /// Where each book's tag stands over the ACTION block of [half] of
  /// [pageIndex]: the x of its boundary and the tag's bottom edge. The last
  /// book's tag sits on the memo band's bottom and each before it a step
  /// higher — the reference sheets' diagonal (유저 2026-09-25, 사진 셋),
  /// stacked up from the band because our form has no empty band over the
  /// grid (timesheet-book-tag-place-Q1: 「메모 띠 아래쪽에 겹쳐 쌓는다
  /// (크기 그대로)」).
  List<({String label, double x, double bottom})> bookTags(
    int pageIndex,
    int half,
  ) {
    final books = document.books;
    final left = halfLeft(pageIndex, half);
    final floor = memoBandRect(pageIndex).bottom - bookTagFloorGap;
    return [
      for (var index = 0; index < books.length; index += 1)
        (
          label: books[index].label,
          x: left + columnLeftInHalf(books[index].boundary),
          bottom: floor - (books.length - 1 - index) * bookTagStep,
        ),
    ];
  }

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
    final half = math.min(local ~/ document.halfFrameCount, _strips - 1);
    return (
      page: page,
      half: half,
      row: local - half * document.halfFrameCount,
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

  /// The paper the document lays out — every page and the gaps between
  /// them, inside the margin round the whole: where the panel's view stops
  /// (F-201).
  Rect get paper => continuous ? pageRect(0) : _stack.paper;

  /// Logical size of the whole document — the one strip in continuous
  /// view, the stack otherwise.
  Size get documentSize => continuous
      ? Size(documentMargin * 2 + paperWidth, documentMargin * 2 + paperHeight)
      : _stack.size;
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

/// [column]'s cells as [preview] shows them. Every layer-backed column kind
/// previews (UI-R18 #7 — action, SE, camera instruction): the column's own
/// baked [TimesheetColumn.previewCellsBuilder] re-derives the cells on the
/// row the drag previews, so the painter never learns each kind's recipe.
/// SE previews arrive as DISPLAY clones under the same id (the timeline's
/// seam), so the SE windowing stays the document's job. The document's own
/// cells where the drag previews no row of this column.
List<TimesheetCell> timesheetColumnCellsShowing(
  TimesheetColumn column,
  TimelineDragPreview? preview,
) {
  final layerId = column.layerId;
  final rebuild = column.previewCellsBuilder;
  if (preview == null || layerId == null || rebuild == null) {
    return column.cells;
  }
  final previewLayer = timelineDragPreviewLayerFor(preview, layerId);
  return previewLayer == null ? column.cells : rebuild(previewLayer);
}

/// What the content stratum PRINTS from the drag channel — every column's
/// cells as the drag shows them, the cut's live end and its live drawn end,
/// the three things [TimesheetDocumentPainter] reads off its `dragPreview` —
/// compared by value.
///
/// 🚨sheet-prints-only-its-drags: a drag that moves nothing the sheet prints
/// — a lane value scrubbed, a canvas handle, a key range (F-195) — prints
/// the same, and the sheet neither repaints nor stands its bake down for it.
Object timesheetDragPrint({
  required TimesheetDocument document,
  required CutId? cutId,
  required TimelineDragPreview? preview,
}) => (
  ByList([
    for (final column in document.columns)
      ByList(timesheetColumnCellsShowing(column, preview)),
  ]),
  timelineCutEndPreviewFrameCount(
    preview: preview,
    cutId: cutId,
    playbackFrameCount: document.playbackFrameCount,
  ),
  timelineDrawnEndPreviewFrameCount(
    preview: preview,
    cutId: cutId,
    playbackFrameCount: document.playbackFrameCount,
    drawnFrameCount: document.drawnFrameCount,
  ),
);

/// Paints the sheet document — the paper form (header band, Direction memo
/// band, group/letter rows, second-heavy grid), cel numbers, holds,
/// in-between marks, X cells, camera keys, the data-driven cut-end
/// strikethrough and the playhead row — under the panel viewport transform
/// (the same
/// inside-the-picture transform the brush canvas uses, crisp at any zoom).
class TimesheetDocumentPainter extends CustomPainter
    with RepaintOnProps, SheetInkOnScreen {
  TimesheetDocumentPainter({
    required this.document,
    required this.layout,
    required this.face,
    this.viewport,
    required this.words,
    this.layers,
    this.dragPreview,
    this.cutId,
    this.effectiveRatio = 1.0,
    this.ink = const [],
    this.inkImageFor,
    this.inkSurfaceFor,
    this.liveInkKeys = const {},
    Listenable? inkRepaint,
  }) : accent = AppColors.accent,
       super(repaint: Listenable.merge([dragPreview, inkRepaint]));

  /// The windows the sheet's ink shows through — the walk the brush writes
  /// through too (`timesheetInkWindows`), handed in by whoever built it.
  final List<SheetInk> ink;

  /// A window's baked ink raster, or null to print none there — for an
  /// EXPORT, which has no view to draw it through.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// A window's ink surface ON SCREEN, printed as the brush's live window
  /// paints it ([SheetInkOnScreen], F-215).
  @override
  final BitmapSurface? Function(BrushFrameKey key)? inkSurfaceFor;

  /// Keys a LIVE brush window is already showing: skipped here, so
  /// translucent ink never composites twice.
  @override
  final Set<BrushFrameKey> liveInkKeys;

  /// Device pixels per LOGICAL pixel — monitor ratio × UI scale; the
  /// viewport transform lands the paper on the device grid with it.
  /// Defaulting to 1.0 keeps every focused test and the PSD export path
  /// unchanged.
  @override
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
  @override
  final CanvasViewport? viewport;

  /// The words the sheet prints, in the NOTATION language (UI-R10 #7) —
  /// the caller's table (`timesheetWordsIn`). ⛔No default: an English one
  /// stood here for focused tests, the painter's own copy of a table.
  final TimesheetWords words;

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
        : canvasRectShown(resolvedViewport, size);

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
      if (_drawContent) {
        _books.paintHalf(canvas, pageIndex: 0, half: 0);
      }
    } else {
      // Every page, one under another.
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
          if (_drawContent) {
            _books.paintHalf(canvas, pageIndex: page.index, half: strip.half);
          }
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
    // On screen the ink is the stratum's last, and drawn out of document
    // space: as the live windows draw it (F-215).
    if (_draws(SheetPaintLayer.ink)) {
      printInkAsLive(canvas, size, ink);
    }
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
    TimesheetHeaderField field,
    TimesheetWords words,
  ) => _TimesheetBandsPass.headerFieldLabel(field, words);

  // ── the SE pass: its own object, in its own file ────────────────────
  //
  // A collaborator (timesheet/document_painter/timesheet_se_pass.dart, a part of this
  // library). The painter keeps the passes its paint() calls.
  late final _TimesheetSePass _se = _TimesheetSePass(this);

  // ── the books pass: its own object, in its own file ─────────────────
  //
  // A collaborator (timesheet/document_painter/timesheet_books_pass.dart, a part of this
  // library). The painter keeps the passes its paint() calls.
  late final _TimesheetBooksPass _books = _TimesheetBooksPass(this);

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
      setWord: paintScaledText,
      maxCellWidth: columnWidth - 2,
    );
  }

  /// The style the sheet sets its words in: [face] at [fontSize], in
  /// [color], bold or not.
  ///
  /// ONE spelling for the printer and the header's editor (F-188, 유저
  /// 2026-09-26: 「최대한 안움직이게」): the editor types a box's words in
  /// the style they were printed in, so opening it moves no glyph. ↩️The
  /// editor had its own copy, and named no face — it typed in another font.
  static TextStyle wordsStyle(
    TextStyle face, {
    required double fontSize,
    Color color = _ink,
    bool bold = false,
  }) => face.copyWith(
    color: color,
    fontSize: fontSize,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
  );

  /// A header box's value: set this size, bold, centred on the box, in
  /// [headerValueRect] (R7-⑥ reference layout).
  static const double headerValueSize = 14;

  /// The duration box's second, parenthesised length — the drawn one
  /// ([_TimesheetBandsPass._paintDrawnLength]) — set small under the value.
  static const double headerDrawnLengthSize = 9;

  /// Where a header box's value is set: its top this far down the box, no
  /// wider than the box less its margins.
  static Rect headerValueRect(Rect box) => Rect.fromLTRB(
    box.left + 6,
    box.top + 26,
    box.right - 6,
    box.bottom - 4,
  );

  /// The Direction memo: set this size, from the top left of
  /// [memoTextRect], wrapped at its width.
  static const double memoSize = 11;

  /// Where the memo is set in its band.
  static Rect memoTextRect(Rect band) => Rect.fromLTRB(
    band.left + 8,
    band.top + 6,
    band.right - 8,
    band.bottom - 6,
  );

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
        style: wordsStyle(face, fontSize: fontSize, color: color, bold: bold),
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
    words,
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
    words,
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
    viewport,
    effectiveRatio,
  );
}
