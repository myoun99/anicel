import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/page_stack.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/camera_instruction.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cel_photo.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart' show InbetweenMark;
import '../../models/se_dialogue_spacing.dart';
import '../../models/se_line_type.dart' show SeLineType;
import '../../models/sheet_marks.dart';
import '../../models/sheet_memo_side.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/sheet_paper.dart';
import '../../models/timesheet_document.dart';
import '../../models/timesheet_info.dart';
import '../../models/timesheet_sheet_kind.dart';
import '../../models/timesheet_words.dart';
import '../../models/transition_geometry.dart'
    show TransitionSides, transitionSidesOf;
import '../../models/xdts_sheet_form.dart';
import '../../models/xdts_viewer_sheet.dart' show xdtsViewerOverlaps;
import '../text/dialogue_fit_paint.dart';
import '../text/vertical_writing.dart'
    show verticalTextCells, verticalTextSpanCount;
import '../canvas/display_resample.dart' show displayScaleOf;
import '../canvas/viewport_canvas_transform.dart';
import '../text/vertical_writing_text.dart';
import '../text/word_condensation.dart'
    show WordFit, paintScaledText, wordCondensation;
import '../theme/app_theme.dart';
import '../timeline/inbetween_mark_painter.dart';
import '../timeline/se_crossing_mark_painter.dart';
import '../timeline/timeline_span_name.dart' show instructionLabelInset;
import '../timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount, timelineDrawnEndPreviewFrameCount;
import '../timeline/timeline_drag_preview.dart';
import '../timeline/timeline_frame_ruler_painter.dart'
    show timelineRulerSecondsLabel;
import '../timeline/timeline_glyph_cache.dart' show timelineWordSetOnto;
import '../repaint_props.dart';
import '../sheet/sheet_image_cache.dart' show SheetImageLookup;
import '../sheet/sheet_ink_layer.dart' show SheetInkOnScreen;
import '../sheet/sheet_line.dart';
import '../sheet_painting.dart'
    show paintSheetInkWindow, paintSheetPaper, sheetWordsSize;
import '../timeline/memo_token.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

part 'document_painter/timesheet_instruction_pass.dart';
part 'document_painter/timesheet_se_pass.dart';
part 'document_painter/timesheet_bands_pass.dart';
part 'document_painter/timesheet_cells_pass.dart';
part 'document_painter/timesheet_books_pass.dart';
part 'document_painter/timesheet_sheet_forms.dart';
part 'document_painter/timesheet_xdts_page.dart';
part 'document_painter/timesheet_xdts_form_pass.dart';
part 'document_painter/timesheet_xdts_counts_pass.dart';
part 'document_painter/timesheet_xdts_overlap_pass.dart';

/// Geometry of the rendered sheet document in canvas (document) space,
/// modeled on the Japanese paper form (A-1/IG style): a portrait page
/// whose body splits into two side-by-side halves of
/// [TimesheetDocument.halfFrameCount] rows; each half reads
/// frame-number gutter | ACTION block (animation layers) | S1·S2 |
/// CELL block | CAM. The gutter is bare numbers on paper (user direction —
/// no boxed rail, no grid), printed left of each half.
///
/// 🚨THE FORM IS LAID ON A SHEET OF PAPER (F-294, 유저 2026-10-05:
/// 「타임시트 용지패널 용지크기 너무 작음 … 1754x2480을 기본으로 할것」). The
/// form above is measured in units of its own (a frame row is 18); its paper
/// is `SheetPaper.timesheet`, a size in pixels, and the form lies on it as
/// large as fits, centred ([_onPaper]) — [paperScale] pixels a unit. Every
/// measure here stays in the form's units: [paperWidth] and [paperHeight]
/// are the SHEET as those units measure it, [formRect] is the form on it.
/// ↩️The form WAS the paper — B4's shape, 1096×1574 of its own units on a
/// 24fps sheet, shown a unit a pixel.
///
/// ↩️There was a CONTINUOUS view beside the pages — one strip of every row
/// on the page's paper width. The user had it deleted with every trace of
/// it (2026-10-08, F-252-Q1: 「이어보기를 분명 삭제하라 했던거같은데 …
/// 삭제. 잔재 싹 삭제」): the sheet is its pages.
class TimesheetDocumentLayout {
  TimesheetDocumentLayout({required this.document});

  final TimesheetDocument document;

  /// Page indexes this layout prints, in order: every page one under
  /// another.
  ///
  /// ↩️R26 #41 (07-23) printed ONE sheet at a time in page view and turned
  /// the page by swapping the paper under a view that never moved. F-201
  /// (유저 2026-09-27, F-201-timesheet-pages-Q1: 「타임시트 페이지 보기도
  /// 쌓는다」) lays them one under another again, as the conte's and the
  /// viewer's: a turn scrolls to the page (`CanvasBook`).
  List<int> get pageIndexes => [
    for (final page in document.pages) page.index,
  ];

  static const double rowHeight = 18;
  static const double actionColumnWidth = 24;
  static const double seColumnWidth = 20;
  static const double celColumnWidth = 24;
  static const double cameraColumnWidth = 36;

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

  /// The strips a page lays side by side ([TimesheetSheetKind.strips]).
  int get _strips => document.sheetKind.strips;

  /// The form the rows are laid on: the cut's sheet kind's — our own, or
  /// the XDTS Viewer's ([TimesheetDocument.xdtsForm]).
  late final _SheetForm _form = switch (document.xdtsForm) {
    final xdts? => _XdtsSheetForm(xdts),
    null => _OurSheetForm(this),
  };

  /// Per-column width — the same on either of our sheets: the 3-second
  /// sheet prints more cells, not wider ones (F-252, 유저 2026-10-08).
  /// ↩️Its columns printed about half again as wide (`columnScaleOf`).
  ///
  /// The SE and the CAM columns share a FIXED group allotment — the slots
  /// the sheet prints with none behind them ([TimesheetSheetKind.seColumns]
  /// · [TimesheetSheetKind.cameraColumns]) — and past them each narrows,
  /// so the paper keeps its width: a cut carrying more instruction rows
  /// must never widen it (user rule), nor more SE tracks lengthen it (R27
  /// #32, the CAM rule applied to the sound columns). On an XDTS sheet the
  /// dialogue column and the camera block keep the template's widths so.
  double columnWidthFor(TimesheetColumnKind kind) {
    final width = _form.columnWidth(kind);
    final slots = switch (kind) {
      TimesheetColumnKind.se => document.sheetKind.seColumns,
      TimesheetColumnKind.camera => document.sheetKind.cameraColumns,
      TimesheetColumnKind.action || TimesheetColumnKind.cel => null,
    };
    final count = _columnCountOf(kind);
    return slots != null && count > slots ? width * slots / count : width;
  }

  /// The head over a half's rows: our group and letter rows, or an XDTS
  /// sheet's block heads.
  double get columnsHeaderHeight => _form.headHeight;

  /// x of a column within its half: a prefix sum — and past the ACTION
  /// block, the frame numbers' column an XDTS sheet keeps there (ours
  /// print theirs in the gutter left of the half).
  double columnLeftInHalf(int columnIndex) {
    var x = 0.0;
    for (var index = 0; index < columnIndex; index += 1) {
      x += columnWidthFor(document.columns[index].kind);
    }
    return columnIndex < _columnCountOf(TimesheetColumnKind.action)
        ? x
        : x + _form.numbersColumnWidth;
  }

  /// Width of a half's column area (our number gutter sits outside it).
  double get halfWidth {
    var width = _form.numbersColumnWidth;
    for (final column in document.columns) {
      width += columnWidthFor(column.kind);
    }
    return width;
  }

  /// The printed form's width and height.
  double get formWidth => _form.size.width;
  double get formHeight => _form.size.height;

  /// The form on its paper.
  SheetPaperFit get _onPaper => _form.onPaper;

  /// THE PAPER'S PIXELS A SHEET UNIT TAKES (F-294) — what the panel shows
  /// the sheet at (`SheetCanvasPanel.paperScale`) and the grade its
  /// handwriting is kept at: a pixel of the ink is a pixel of the paper, so
  /// a brush of a size at 100% draws on the sheet as wide as on the canvas.
  ///
  /// ↩️It was `timesheetInkScale`, a number of the ink's own: ONE, the
  /// canvas's grade — the conte's reason (유저 2026-09-26,
  /// one-paper-brush-width-Q2: 「해상도를 캔버스처럼 낮추기」), and 4 before
  /// that. One pixel a unit kept the brush as wide as on the canvas only
  /// because the paper itself was a unit a pixel; the paper has a resolution
  /// of its own now, and the ink is kept at that.
  double get paperScale => _onPaper.scale;

  /// The paper of one page, in pixels — what a page's handwriting is kept
  /// on, pixel for pixel.
  CanvasSize get paperPixelSize => _form.paperPixelSize;

  /// The paper's width: the sheet's.
  double get paperWidth => _onPaper.sheet.width;

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

  /// The paper's height: the sheet's.
  double get paperHeight => _onPaper.sheet.height;

  double get paperLeft => documentMargin;

  /// The form on the paper of a page.
  Rect formRect(int pageIndex) =>
      (pageRect(pageIndex).topLeft + _onPaper.inset) &
      Size(formWidth, formHeight);

  /// Top of a page's paper.
  double pageTop(int pageIndex) => _stack.pageRect(pageIndex).top;

  /// The paper rect of a page.
  Rect pageRect(int pageIndex) =>
      Rect.fromLTWH(paperLeft, pageTop(pageIndex), paperWidth, paperHeight);

  /// Left edge of a half's column area (past our number gutter).
  double halfLeft(int pageIndex, int half) =>
      paperLeft + _onPaper.inset.dx + _form.halfLeft(half, halfWidth);

  /// Top of a half's first row.
  double halfRowsTop(int pageIndex) =>
      pageTop(pageIndex) + _onPaper.inset.dy + _form.rowsTop;

  /// Top of the grid — its column header's top edge.
  double gridTop(int pageIndex) =>
      halfRowsTop(pageIndex) - columnsHeaderHeight;

  /// Top of the row the columns' titles print on, at the head's foot.
  double lettersTop(int pageIndex) =>
      halfRowsTop(pageIndex) - _form.titleRowHeight;

  /// A book's tag (D24): its height, the step between two stacked, the size
  /// its words print at, and what it keeps clear of the memo band's bottom.
  static const double bookTagHeight = 13;
  static const double bookTagStep = 15;
  static const double bookTagFontSize = 9;
  static const double bookTagFloorGap = 2;

  /// Where each book's tag stands over its block of [half] of
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

  /// The header band rect of a page ([_SheetForm.headerBand]).
  Rect headerBandRect(int pageIndex) =>
      _form.headerBand.shift(formRect(pageIndex).topLeft);

  /// The visible header boxes of a page, in printing order — shared by the
  /// painter and the tap-to-edit layer.
  List<TimesheetHeaderBox> headerFieldBoxes(int pageIndex) {
    final fields = document.visibleHeaderFields;
    if (fields.isEmpty) {
      return const [];
    }
    final corner = formRect(pageIndex).topLeft;
    return [
      for (final box in _form.headerBoxes(fields))
        (
          field: box.field,
          rect: box.rect.shift(corner),
          value: box.value.shift(corner),
        ),
    ];
  }

  /// What a header box prints that someone TYPED — the work's title and
  /// episode, the cut's name and scene, its sheet worker — or null for a
  /// box the sheet counts itself (the length, the page). Shared by the
  /// painter and the tap-to-edit layer, so the field opens on the printed
  /// words.
  String? typedHeaderValue(TimesheetHeaderField field) => switch (field) {
    TimesheetHeaderField.episode => document.episode,
    TimesheetHeaderField.title => document.title,
    // The cut's own (유저 2026-10-28, F-291: 「즉 컷마다 개별적임」), not the
    // work's (유저 09-25). ↩️It printed blank, written by hand.
    TimesheetHeaderField.scene => document.scene,
    TimesheetHeaderField.cut => document.cutName,
    TimesheetHeaderField.name => document.artist,
    TimesheetHeaderField.time || TimesheetHeaderField.sheet => null,
  };

  /// The memo band rect of a page ([_SheetForm.memoBand]).
  Rect memoBandRect(int pageIndex) =>
      _form.memoBand.shift(formRect(pageIndex).topLeft);

  /// The text space of [side] of page [pageIndex]'s memo band: half of the
  /// band's, a memo of its own on each side ([SheetMemoSide]).
  Rect memoSideRect(int pageIndex, SheetMemoSide side) {
    final room = TimesheetDocumentPainter.memoTextRect(
      memoBandRect(pageIndex),
    );
    const gap = TimesheetDocumentPainter.memoColumnGap / 2;
    return switch (side) {
      SheetMemoSide.left => Rect.fromLTRB(
        room.left,
        room.top,
        room.center.dx - gap,
        room.bottom,
      ),
      SheetMemoSide.right => Rect.fromLTRB(
        room.center.dx + gap,
        room.top,
        room.right,
        room.bottom,
      ),
    };
  }

  /// The fixed lines on [side] of page [pageIndex]: down the left memo, and
  /// on down the right where the left runs out (F-542-Q1).
  ///
  /// ⚠️Mine: each side keeps its last line for the words typed there, so a
  /// memo written before the lines grew still prints. Lines past the two
  /// sides are not written, as the conte's past its column.
  List<String> fixedLinesOn(int pageIndex, SheetMemoSide side) {
    final lines = document.fixedLinesOf(pageIndex);
    final height = memoSideRect(pageIndex, side).height;
    final room = height ~/ TimesheetDocumentPainter.memoLine - 1;
    return switch (side) {
      SheetMemoSide.left => lines.take(room).toList(),
      SheetMemoSide.right => lines.skip(room).take(room).toList(),
    };
  }

  /// Where the memo on [side] of page [pageIndex] is set: under the fixed
  /// lines written there, a [TimesheetDocumentPainter.memoLine] each, the
  /// conte's way (`conteActionWordsDrop`). The ONE rect the page prints the
  /// memo in and the field types it at.
  Rect memoWordsRect(int pageIndex, SheetMemoSide side) {
    final room = memoSideRect(pageIndex, side);
    final lines = fixedLinesOn(pageIndex, side).length;
    return Rect.fromLTRB(
      room.left,
      room.top + lines * TimesheetDocumentPainter.memoLine,
      room.right,
      room.bottom,
    );
  }

  /// What the memo field on [side] of page [pageIndex] opens over: its half
  /// of the band, under the fixed lines written there, so no one types into
  /// them (유저 2026-10-12, I-93: 「이 고정텍스트는 지울수없도록?」).
  Rect memoEditBox(int pageIndex, SheetMemoSide side) {
    final band = memoBandRect(pageIndex);
    final top = fixedLinesOn(pageIndex, side).isEmpty
        ? band.top
        : memoWordsRect(pageIndex, side).top;
    return switch (side) {
      SheetMemoSide.left => Rect.fromLTRB(
        band.left,
        top,
        band.center.dx,
        band.bottom,
      ),
      SheetMemoSide.right => Rect.fromLTRB(
        band.center.dx,
        top,
        band.right,
        band.bottom,
      ),
    };
  }

  /// Where a global frame lands: page, half and row within the half.
  ({int page, int half, int row}) positionOfFrame(int frameIndex) {
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
    return halfRows(position.page).topOf(position.row);
  }

  /// Bottom edge of a global frame row.
  double frameRowBottom(int frameIndex) {
    final position = positionOfFrame(frameIndex);
    return halfRows(position.page).bottomOf(position.row);
  }

  /// The rows of a half page of [pageIndex] — every half of a page lays
  /// its rows level with the others'.
  TimesheetRows halfRows(int pageIndex) =>
      TimesheetRows._(halfRowsTop(pageIndex), this);

  /// The top of row [row] of a half page, below the top of its first row
  /// — of any row, before the first or past the last as well: where a span
  /// that began in an earlier half began.
  double _rowTopIn(int row) => _form.rowTopIn(row);

  /// The bottom of row [row] of a half page, below the top of its first.
  double _rowBottomIn(int row) => _form.rowBottomIn(row);

  /// How many rows of a half page lie above [offset] below its first
  /// row's top, a part of a row counted as such.
  double _rowsAbove(double offset) => _form.rowsAbove(offset);

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
      y: frameRowBottom(lastFrame),
    );
  }

  /// The sheet's page notation ('1/2'). The printed ページ header box and
  /// the panel's page readout (R26 #41) share this one spelling so they
  /// can never drift apart.
  /// [pageCount] overrides the document's sheet count for a paint that is
  /// following a cut-length drag (F-88) — the paper itself still re-flows
  /// on the release.
  String pageLabel(int pageIndex, {int? pageCount}) =>
      '${pageIndex + 1}/${pageCount ?? document.pages.length}';

  /// The paper the document lays out — every page and the gaps between
  /// them, inside the margin round the whole: where the panel's view stops
  /// (F-201).
  Rect get paper => _stack.paper;

  /// Logical size of the whole document: the stack of its pages.
  Size get documentSize => _stack.size;
}

/// Where the rows of a half page lie on the document — the ONE answer the
/// form's rules, the values in the cells, the spans run down them and the
/// playhead read, so none of them counts rows down by a height of its own.
class TimesheetRows {
  const TimesheetRows._(this.top, this._layout);

  /// The top of the half's first row.
  final double top;
  final TimesheetDocumentLayout _layout;

  /// The top of [row] — any row, before the first or past the last as
  /// well ([TimesheetDocumentLayout._rowTopIn]).
  double topOf(int row) => top + _layout._rowTopIn(row);

  /// The bottom of [row].
  double bottomOf(int row) => top + _layout._rowBottomIn(row);

  /// The rows of [rowCount] that a view of [shown] can reach — every row
  /// when [shown] is null.
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
  (int, int) reached(Rect? shown, int rowCount) {
    if (shown == null) {
      return (0, rowCount);
    }
    final first = _layout._rowsAbove(shown.top - top).floor() - 1;
    final last = _layout._rowsAbove(shown.bottom - top).ceil() + 1;
    return (first.clamp(0, rowCount), last.clamp(0, rowCount));
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

/// What the content stratum PRINTS from the drag channel over the view of
/// [shown] ([timesheetShown]) — each column's cells as the drag shows them
/// on the rows a paint of that view reaches, the cut's live end and its
/// live drawn end, the three things [TimesheetDocumentPainter] reads off
/// its `dragPreview` — compared by value.
///
/// 🚨sheet-prints-only-its-drags: a drag that moves nothing the sheet prints
/// — a lane value scrubbed, a canvas handle, a key range (F-195) — prints
/// the same, and the sheet neither repaints nor stands its bake down for it.
///
/// ⛔The rows a paint does not reach print nothing (F-244-sheet-print): the
/// whole document's cells — 11,520 of them on a 480-frame cut of 24 rows,
/// compared every step — made a block dragged off screen re-print the
/// sheet at each step, its bake standing down for a picture that stayed the
/// same. The rows are the paint's own walk ([_cellsShown]), so the print
/// cannot reach fewer than the paint reads.
Object timesheetDragPrint({
  required TimesheetDocument document,
  required TimesheetDocumentLayout layout,
  required Rect? shown,
  required CutId? cutId,
  required TimelineDragPreview? preview,
}) {
  final drawnEnd = timelineDrawnEndPreviewFrameCount(
    preview: preview,
    cutId: cutId,
    playbackFrameCount: document.playbackFrameCount,
    drawnFrameCount: document.drawnFrameCount,
  );
  return (
    ByList([
      for (final column in document.columns)
        ByList(
          _cellsShown(
            document,
            layout,
            column.kind,
            timesheetColumnCellsShowing(column, preview),
            shown: shown,
            drawnFrameCount: drawnEnd,
          ),
        ),
    ]),
    timelineCutEndPreviewFrameCount(
      preview: preview,
      cutId: cutId,
      playbackFrameCount: document.playbackFrameCount,
    ),
    drawnEnd,
  );
}

/// The document-space rectangle a paint of [size] under [viewport] can
/// show, or null to reach the whole sheet (culling off, or no view): what
/// the painter culls to and what a drag print reads ([timesheetDragPrint]).
Rect? timesheetShown(CanvasViewport? viewport, Size size) =>
    TimesheetDocumentPainter.debugDisableCulling || viewport == null
    ? null
    : canvasRectShown(viewport, size);

/// The pages of [document] a view of [shown] reaches any of, top to bottom
/// — every page when [shown] is null.
///
/// A whole page off screen costs nothing at all — this is where the
/// stacked multi-page document stops being O(document).
Iterable<TimesheetPage> _pagesShown(
  TimesheetDocument document,
  TimesheetDocumentLayout layout,
  Rect? shown,
) => document.pages.where((page) {
  final bounds = layout.pageRect(page.index);
  return shown == null ||
      (bounds.bottom >= shown.top && bounds.top <= shown.bottom);
});

/// The frame the first row of [half] of [page] prints.
int _halfStartFrame(TimesheetDocument document, TimesheetPage page, int half) =>
    page.startFrame + (half == 0 ? 0 : document.halfFrameCount);

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
    this.contentParts,
    this.dragPreview,
    this.cutId,
    this.effectiveRatio = 1.0,
    this.ink = const [],
    this.inkImageFor,
    this.inkPhotosFor,
    this.inkSurfaceFor,
    this.liveInkKeys = const {},
    this.imageFor,
    Listenable? inkRepaint,
    Listenable? imageRepaint,
  }) : accent = AppColors.accent,
       super(
         repaint: Listenable.merge([dragPreview, inkRepaint, imageRepaint]),
       );

  /// The windows the sheet's ink shows through — the walk the brush writes
  /// through too (`timesheetInkWindows`), handed in by whoever built it.
  final List<SheetInk> ink;

  /// A window's baked ink raster, or null to print none there — for an
  /// EXPORT, which has no view to draw it through.
  final ui.Image? Function(BrushFrameKey key)? inkImageFor;

  /// The photos laid on a window's ink (I-97), for an export, beside its
  /// raster — each drawn from its file by [imageFor].
  final List<CelPhoto> Function(BrushFrameKey key)? inkPhotosFor;

  /// A window's ink surface ON SCREEN, printed as the brush's live window
  /// paints it ([SheetInkOnScreen], F-215).
  @override
  final BitmapSurface? Function(BrushFrameKey key)? inkSurfaceFor;

  /// Keys a LIVE brush window is already showing: skipped here, so
  /// translucent ink never composites twice.
  @override
  final Set<BrushFrameKey> liveInkKeys;

  /// The pool files the ink's photos are drawn from (I-97); a landed decode
  /// repaints through `imageRepaint`.
  @override
  final SheetImageLookup? imageFor;

  /// Device pixels per LOGICAL pixel — monitor ratio × UI scale; the
  /// viewport transform lands the paper on the device grid with it. An
  /// export, which has no viewport, says here how many of its pixels a
  /// unit of the sheet is — what its photos are sampled for (I-97).
  /// Defaulting to 1.0 keeps every focused test unchanged.
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

  /// Which parts of the values the content stratum prints; null = all of
  /// them — the panel, and every export but the XDTS viewer's ink pages
  /// ([TimesheetContentPart]).
  final Set<TimesheetContentPart>? contentParts;

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
      drawsSheetLayer(layers, layer);

  bool get _drawPaper => _draws(SheetPaintLayer.paper);
  bool get _drawForm => _draws(SheetPaintLayer.form);
  bool get _drawContent => _draws(SheetPaintLayer.content);

  /// The XDTS Viewer's page, where the sheet prints on one (I-162) — null
  /// on our own, whose form the bands and the cells passes draw.
  late final _XdtsPage? _xdts = switch (layout._form) {
    final _XdtsSheetForm sheet => _XdtsPage(this, sheet),
    _OurSheetForm() => null,
  };

  /// Whether this paint draws OUR form — the stratum, on one of our sheets.
  bool get _drawsOurForm => _drawForm && _xdts == null;

  /// Whether this paint prints [part]'s values: the content stratum's, as
  /// [contentParts] names them.
  bool _drawsPart(TimesheetContentPart part) =>
      _drawContent && drawsAmong(contentParts, part);

  /// Whether this paint prints the title of a column of [kind]: with its
  /// stratum ([TimesheetColumnKind.titleLayer]) — with its part too, where
  /// that is the values'.
  bool _drawsTitleOf(TimesheetColumnKind kind) =>
      kind.titleLayer == SheetPaintLayer.content
      ? _drawsPart(kind.contentPart)
      : _draws(kind.titleLayer);

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
  /// when culling is off ([timesheetShown]). Set once at the top of
  /// [paint], read by the three row loops and the page skip.
  Rect? _cull;

  @override
  void paint(Canvas canvas, Size size) {
    _enterDocumentSpace(canvas, size, viewport, effectiveRatio);
    // The clip above, carried back through the viewport transform into
    // document space. Everything outside it is already invisible; the
    // only question is whether we spend the ops finding that out.
    _cull = timesheetShown(viewport, size);

    // Every page on screen, one under another.
    for (final page in _pagesShown(document, layout, _cull)) {
      _bands.paintPaper(canvas, page.index);
      if (_drawForm) {
        _xdts?.formPass.paintPage(canvas, page.index);
      }
      _bands.paintHeaderBand(canvas, page.index);
      if (_drawsPart(TimesheetContentPart.memo)) {
        _bands.paintMemoBand(canvas, page.index);
      }
      for (final strip in layout.halfStrips) {
        _cells.paintHalf(
          canvas,
          pageIndex: page.index,
          half: strip.half,
          startFrame: _halfStartFrame(document, page, strip.half),
          rowCount: strip.rowCount,
        );
        if (_drawsPart(TimesheetContentPart.books)) {
          _books.paintHalf(canvas, pageIndex: page.index, half: strip.half);
        }
      }
      if (_drawsPart(TimesheetContentPart.overlaps)) {
        _xdts?.overlaps.paintPage(canvas, page.index);
      }
    }
    if (_drawsPart(TimesheetContentPart.cutEnd)) {
      _bands.paintCutEndLine(canvas);
    }
    if (_drawsPart(TimesheetContentPart.se)) {
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
  ///
  /// A window's photos (I-97) lie under its handwriting, sampled for the
  /// device pixels a unit of the sheet is ([effectiveRatio]).
  void _paintInk(Canvas canvas) {
    final rasterFor = inkImageFor;
    final photosFor = inkPhotosFor;
    if (rasterFor == null && photosFor == null) {
      return;
    }
    for (final window in ink) {
      if (liveInkKeys.contains(window.key)) {
        continue;
      }
      paintSheetInkWindow(
        canvas,
        rasterFor?.call(window.key),
        window.placement,
        photos: photosFor?.call(window.key) ?? const [],
        photoFiles: imageFor,
        displayScale: displayScaleOf(viewport?.zoom ?? 1, effectiveRatio),
      );
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
    required double bottom,
    required double columnWidth,
  }) {
    if (word.isEmpty || bottom <= top) {
      return;
    }
    paintVerticalText(
      canvas,
      word,
      style: face.copyWith(color: _ink, fontSize: 10),
      centerX: centerX,
      top: top,
      mainExtent: bottom - top,
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

  /// What a header box sets small under its value: the duration box's
  /// drawn length ([_TimesheetBandsPass._paintDrawnLength]), the cut box's
  /// 겸용 cuts ([_TimesheetBandsPass._paintLinkedCuts]).
  static const double headerUnderSize = 9;

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

  /// What a fixed line stands in, in the memo band, and what a memo counts
  /// the lines it has room for by.
  static const double memoLine = 16;

  /// The white between the band's two memos ([memoSideRect]).
  static const double memoColumnGap = 16;

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
    bool centeredAtY = false,
    double? maxWidth,
  }) {
    // A word's room is its column's less a margin, and the S group's
    // columns share the form's fixed width: past twenty of them that room
    // went below zero and stopped the sheet on an assertion (2026-10-21,
    // 26 S rows). No room at all is the least a word is laid in.
    final room = math.max(0.0, maxWidth ?? double.infinity);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: wordsStyle(face, fontSize: fontSize, color: color, bold: bold),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: room);
    final across = centeredAtX
        ? anchor - Offset(painter.width / 2, 0)
        : rightAlignedAtX
        ? anchor - Offset(painter.width, 0)
        : anchor;
    painter.paint(
      canvas,
      centeredAtY ? across - Offset(0, painter.height / 2) : across,
    );
  }

  @override
  Object get props => (
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
  /// columns and the letters the form prints over them
  /// ([TimesheetColumnKind.titleLayer]), the pages, the header boxes, the
  /// frame rate, the sheet's kind (our form or the XDTS Viewer's) and the
  /// notation. A value typed on the sheet is not in it,
  /// nor a cel row's name.
  Object get _formShape => (
    ByList([
      for (final column in document.columns)
        (
          column.kind,
          column.kind.titleLayer == SheetPaintLayer.form ? column.label : null,
        ),
    ]),
    ByList([
      for (final page in document.pages)
        (page.index, page.startFrame, page.frameCount),
    ]),
    document.pageFrameCount,
    document.fps,
    document.sheetKind,
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
    contentParts == null ? null : BySet(contentParts!),
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
    final left = layout.halfLeft(position.page, position.half);
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        layout.frameRowTop(frame),
        left + layout.halfWidth,
        layout.frameRowBottom(frame),
      ),
      Paint()..color = _playhead,
    );
    canvas.restore();
  }

  @override
  Object get props => (
    ByIdentity(document),
    viewport,
    effectiveRatio,
  );
}

/// A column's title — its row's name — in [style] set onto [room], the
/// column's width less its margin, by the block word's law
/// ([timelineWordSetOnto]): its letter gaps give way first, then it
/// narrows — and where it would narrow past [columnTitleNarrowest], it is
/// cut short with 「…」 to as much of it as narrows no further.
///
/// 🗣️F-500 (유저 2026-10-29): 「이름칸에서 글자 2개까지만 보이고 넘어가면
/// ...이렇게 생략되는데, 전각 기준 3글자까지 보이도록. 그 후론 글자수
/// 작게하면서 버티다가 임계점넘어가면 ...으로 생략」 — Q2 b 「블록 글자의 법으로
/// — 크기는 그대로, 가로만 좁힌다」. ↩️It was cut short at its size as it ran
/// past the column, so three full-width letters showed two.
({TextPainter glyph, WordFit fit}) columnTitleSetOnto(
  String label,
  TextStyle style,
  double room,
) {
  ({TextPainter glyph, WordFit fit}) setOnto(String text) {
    final glyph = timelineWordSetOnto(text, style, room).glyph;
    return (
      glyph: glyph,
      fit: (x: wordCondensation(extent: glyph.width, room: room), y: 1.0),
    );
  }

  final whole = setOnto(label);
  if (whole.fit.x >= columnTitleNarrowest) {
    return whole;
  }
  final letters = label.runes.toList();
  for (var kept = letters.length - 1; kept > 0; kept -= 1) {
    final short = setOnto('${String.fromCharCodes(letters.take(kept))}…');
    if (short.fit.x >= columnTitleNarrowest) {
      return short;
    }
  }
  return setOnto('…');
}

/// How far a column's title narrows before it is cut short
/// ([columnTitleSetOnto]): to half — the mark the question put
/// (🗣️F-500-Q2 b: 「좁힘이 절반(50%)보다 더 가야 하면 「…」 — 절반은 내
/// 제안이고 숫자는 바꿔도 된다」), answered as it was put. Only a column's
/// title stops there: a block's word narrows on and is never cut.
const double columnTitleNarrowest = 0.5;
