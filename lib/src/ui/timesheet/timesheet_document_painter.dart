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
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_instruction_row_visual.dart'
    show instructionLabelInset;
import '../timeline/timeline_cut_end_handle.dart'
    show timelineCutEndPreviewFrameCount;
import '../timeline/timeline_drag_preview.dart';
import 'timesheet_notation.dart';

export '../../models/sheet_paint_layer.dart' show SheetPaintLayer;

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
  }) : super(repaint: dragPreview);

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

  static const Color _paper = Color(0xFFF6F4F0);
  static const Color _ink = Color(0xFF33322F);
  static const Color _gridLight = Color(0xFFCFC9BF);
  static const Color _gridMedium = Color(0xFFA9A296);
  static const Color _gridBold = Color(0xFF6E6759);

  /// Below this zoom the per-cell texts stop painting (paper overview).
  static const double _textZoomThreshold = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final resolvedViewport = viewport;
    if (resolvedViewport != null) {
      canvas.translate(resolvedViewport.panX, resolvedViewport.panY);
      canvas.scale(resolvedViewport.zoom, resolvedViewport.zoom);
    }
    final drawTexts = (resolvedViewport?.zoom ?? 1.0) >= _textZoomThreshold;

    if (layout.continuous) {
      _paintPaper(canvas, 0);
      _paintHeaderBand(canvas, 0, drawTexts: drawTexts);
      if (_drawContent) {
        _paintMemoBand(canvas, 0, drawTexts: drawTexts);
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
        _paintPaper(canvas, page.index);
        _paintHeaderBand(canvas, page.index, drawTexts: drawTexts);
        if (_drawContent) {
          _paintMemoBand(canvas, page.index, drawTexts: drawTexts);
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
      _paintCutEndLine(canvas);
      // A text glyph: it honors the same zoom threshold every per-cell
      // text does (the paper-overview zoom hides the writing).
      if (drawTexts) {
        _paintSeCrossingMarks(canvas);
      }
    }

    canvas.restore();
  }

  /// The sheet of paper, and the printed edge around it — two strata that
  /// used to be one call: the fill is PAPER, the border is FORM.
  void _paintPaper(Canvas canvas, int pageIndex) {
    final rect = layout.pageRect(pageIndex);
    if (_drawPaper) {
      canvas.drawRect(rect, Paint()..color = _paper);
    }
    if (_drawForm) {
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _gridBold,
      );
    }
  }

  /// The header band: labeled boxes like the paper form —
  /// Ep.no | Title | Scene | Cut.no | Duration | Name | Page, minus hidden
  /// boxes. Reference-sheet layout (R7-⑥): the small gray label centers at
  /// the box top, the bold value centers underneath.
  void _paintHeaderBand(
    Canvas canvas,
    int pageIndex, {
    required bool drawTexts,
  }) {
    final band = layout.headerBandRect(pageIndex);
    if (_drawForm) {
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _gridBold;
      canvas.drawRect(band, boxPaint);
      for (final box in layout.headerFieldBoxes(pageIndex)) {
        canvas.drawRect(box.rect, boxPaint);
      }
    }
    if (!drawTexts) {
      return;
    }
    for (final box in layout.headerFieldBoxes(pageIndex)) {
      // The printed labels belong to the FORM; the user's values are
      // CONTENT (UI-R10 #9 — the PSD layer split, live).
      if (_drawForm) {
        _text(
          canvas,
          headerFieldLabel(box.field, notation),
          Offset(box.rect.center.dx, box.rect.top + 5),
          fontSize: 8,
          color: _gridMedium,
          centeredAtX: true,
        );
      }
      if (_drawContent) {
        _text(
          canvas,
          _headerFieldValue(box.field, pageIndex),
          Offset(box.rect.center.dx, box.rect.top + 26),
          fontSize: 14,
          bold: true,
          centeredAtX: true,
          maxWidth: box.rect.width - 12,
        );
      }
    }
  }

  /// The printed box label in the sheet's notation language (UI-R10 #7).
  static String headerFieldLabel(
    TimesheetHeaderField field, [
    TimesheetNotation notation = TimesheetNotation.english,
  ]) {
    return switch (field) {
      TimesheetHeaderField.episode => notation.episode,
      TimesheetHeaderField.title => notation.title,
      TimesheetHeaderField.scene => notation.scene,
      TimesheetHeaderField.cut => notation.cut,
      TimesheetHeaderField.time => notation.duration,
      TimesheetHeaderField.name => notation.name,
      TimesheetHeaderField.sheet => notation.page,
    };
  }

  String _headerFieldValue(TimesheetHeaderField field, int pageIndex) {
    return switch (field) {
      TimesheetHeaderField.episode => document.episode,
      TimesheetHeaderField.title => document.title,
      TimesheetHeaderField.scene => document.scene,
      TimesheetHeaderField.cut => document.cutName,
      // The sheet's 秒+コマ notation prints spaced ('2 + 6') like the
      // reference forms; the model label stays compact for row labels.
      TimesheetHeaderField.time => document.durationLabel.replaceAll(
        '+',
        ' + ',
      ),
      TimesheetHeaderField.name => document.artist,
      TimesheetHeaderField.sheet => layout.pageLabel(pageIndex),
    };
  }

  /// The Direction memo band under the header: COMPLETELY open handwriting
  /// space, exactly like the reference forms (R7-⑥ — the band outline and
  /// the top-right memo box frame are both retired). The cut's Direction
  /// memo (cut note) types into its top left, spanning the full width.
  void _paintMemoBand(Canvas canvas, int pageIndex, {required bool drawTexts}) {
    if (!drawTexts) {
      return;
    }
    final band = layout.memoBandRect(pageIndex);
    if (document.memoText.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: document.memoText,
          style: const TextStyle(color: _ink, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 8,
        ellipsis: '…',
      )..layout(maxWidth: band.width - 16);
      painter.paint(canvas, Offset(band.left + 8, band.top + 6));
    }
    // NO derived instruction lines here anymore (R5-⑥): the shorthand
    // ('A→B PAN …') writes itself INTO the cut note once when the
    // instruction is created, so it prints above as ordinary — editable —
    // note text.
  }

  /// The cut-end strikethrough at the bottom edge of the last playback
  /// frame row — DATA rendering (S2-0), the same visual language as the
  /// timeline's cut-end boundary, never ink.
  void _paintCutEndLine(Canvas canvas) {
    final frameCount = livePlaybackFrameCount;
    if (frameCount < 1 || frameCount > document.rowCount) {
      return;
    }
    final line = layout.cutEndLineFor(frameCount);
    // In page view the cut may end on a page that isn't on screen (R26
    // #41) — its row geometry belongs to another sheet, so nothing prints.
    if (!layout.visiblePageIndexes.contains(line.page)) {
      return;
    }
    final left = layout.halfLeft(line.page, line.half);
    canvas.drawLine(
      Offset(left, line.y),
      Offset(left + layout.halfWidth, line.y),
      Paint()
        ..color = AppColors.danger
        ..strokeWidth = 2.4,
    );
  }

  /// The timeline's `~` continuation marks, printed (SE globalization
  /// round: "타임시트에도 동일하게 추가"). END: a sound starting inside
  /// this cut runs past its end — the mark straddles the red cut-end
  /// line, centred on its SE column. START: a sound from an earlier cut
  /// spills into row 0 — the mark sits on the column's first row edge.
  /// Pure display, exactly the timeline rows' meaning.
  void _paintSeCrossingMarks(Canvas canvas) {
    // The `~` straddles the red line, so it follows the same live length —
    // otherwise a drag leaves the mark hanging where the line used to be.
    final frameCount = livePlaybackFrameCount;
    final endLine = layout.cutEndLineFor(frameCount);
    final startTop = layout.frameRowTop(0);
    final startPosition = layout.positionOfFrame(0);
    for (var column = 0; column < document.columns.length; column += 1) {
      final spec = document.columns[column];
      if (spec.kind != TimesheetColumnKind.se ||
          (!spec.crossesCutEnd && !spec.spillsInAtStart)) {
        continue;
      }
      final columnWidth = layout.columnWidthFor(spec.kind);
      if (spec.crossesCutEnd &&
          frameCount >= 1 &&
          frameCount <= document.rowCount &&
          layout.visiblePageIndexes.contains(endLine.page)) {
        final left =
            layout.halfLeft(endLine.page, endLine.half) +
            layout.columnLeftInHalf(column);
        _text(
          canvas,
          '~',
          Offset(left + columnWidth / 2, endLine.y - 5),
          fontSize: 10,
          bold: true,
          centeredAtX: true,
        );
      }
      if (spec.spillsInAtStart &&
          layout.visiblePageIndexes.contains(startPosition.page)) {
        final left =
            layout.halfLeft(startPosition.page, startPosition.half) +
            layout.columnLeftInHalf(column);
        _text(
          canvas,
          '~',
          Offset(left + columnWidth / 2, startTop - 5),
          fontSize: 10,
          bold: true,
          centeredAtX: true,
        );
      }
    }
  }

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
      _paintGroupTitles(canvas, left, columnsTop);
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
    for (var row = 0; row <= rowCount; row += 1) {
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
      for (var row = 0; row < rowCount; row += 1) {
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
      for (var row = 0; row < rowCount; row += 1) {
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
            _paintSeEmptyRow(
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
                _paintSeEntryStart(
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
                _paintSeRedBar(
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
            _paintInstructionRow(
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

  /// One row of an instruction span, in the X-sheet's exact visual
  /// language (R4): the bar mark is ONE unadorned continuous line between
  /// the endpoint rows' centers — no end ticks, never broken for text —
  /// and FI/FO/O.L marks are light-gray filled wedges owning the full
  /// column width; the A/B names center in the start/end cells like frame
  /// names and the writing centers on the SPAN's true center, drawn over
  /// the mark.
  void _paintInstructionRow(
    Canvas canvas, {
    required TimesheetCell cell,
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
    required bool drawTexts,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final cellBottom = cellTop + rowHeight;
    final spanLength = cell.spanLength ?? 1;
    final offset = cell.spanOffset ?? 0;
    final isFirst = offset == 0;
    final isLast = offset == spanLength - 1;

    if ((cell.markType ?? CameraInstructionMarkType.bar) ==
        CameraInstructionMarkType.bar) {
      // R5-⑤: the endpoint cells carry NO line — the names own them. Each
      // row between draws edge to edge (R6-①a: the per-cell padding made
      // the bar read as broken dashes), thin like a ruled sheet line. A
      // NAMELESS endpoint carries the solid triangle cap instead (real
      // sheets, R7-①) and the line runs through its row to meet it.
      final linePaint = Paint()
        ..color = _ink
        ..strokeWidth = 0.9;
      final hasA = (cell.valueA ?? '').isNotEmpty;
      final hasB = (cell.valueB ?? '').isNotEmpty;
      final triangleLength = math.min(
        7.0,
        TimesheetDocumentLayout.rowHeight - 4,
      );
      if (!isFirst && !isLast) {
        canvas.drawLine(
          Offset(centerX, cellTop),
          Offset(centerX, cellBottom),
          linePaint,
        );
      } else if (isFirst && isLast) {
        if (!hasA && !hasB) {
          // Single-row nameless span: both caps in the one cell (▼ over ▲).
          _paintBarEndpointTriangle(
            canvas,
            centerX: centerX,
            columnWidth: columnWidth,
            baseY: cellTop,
            apexDown: true,
          );
          _paintBarEndpointTriangle(
            canvas,
            centerX: centerX,
            columnWidth: columnWidth,
            baseY: cellBottom,
            apexDown: false,
          );
        }
      } else if (isFirst) {
        if (!hasA) {
          _paintBarEndpointTriangle(
            canvas,
            centerX: centerX,
            columnWidth: columnWidth,
            baseY: cellTop,
            apexDown: true,
          );
          canvas.drawLine(
            Offset(centerX, cellTop + triangleLength),
            Offset(centerX, cellBottom),
            linePaint,
          );
        }
      } else if (!hasB) {
        _paintBarEndpointTriangle(
          canvas,
          centerX: centerX,
          columnWidth: columnWidth,
          baseY: cellBottom,
          apexDown: false,
        );
        canvas.drawLine(
          Offset(centerX, cellTop),
          Offset(centerX, cellBottom - triangleLength),
          linePaint,
        );
      }
    } else {
      _paintInstructionMarkSlice(
        canvas,
        cell: cell,
        centerX: centerX,
        halfWidth: columnWidth / 2 - 1,
        cellTop: cellTop,
      );
    }

    if (!drawTexts) {
      return;
    }
    // Writing goes BOLD (R6-①a): it sits directly on the bar/mark and has
    // to stay readable over it.
    if (isFirst && (cell.valueA ?? '').isNotEmpty) {
      _text(
        canvas,
        cell.valueA!,
        Offset(centerX, cellTop + 3),
        fontSize: 10,
        bold: true,
        color: _ink,
        centeredAtX: true,
        maxWidth: columnWidth - 2,
      );
    }
    if (isLast && !isFirst && (cell.valueB ?? '').isNotEmpty) {
      _text(
        canvas,
        cell.valueB!,
        Offset(centerX, cellTop + 3),
        fontSize: 10,
        bold: true,
        color: _ink,
        centeredAtX: true,
        maxWidth: columnWidth - 2,
      );
    }
    if (isFirst && isLast && (cell.valueB ?? '').isNotEmpty) {
      // Single-row span: B shares the row under A.
      _text(
        canvas,
        cell.valueB!,
        Offset(centerX, cellBottom - 9),
        fontSize: 7,
        bold: true,
        color: _ink,
        centeredAtX: true,
        maxWidth: columnWidth - 2,
      );
    }
    if (offset == (spanLength - 1) ~/ 2 && (cell.label ?? '').isNotEmpty) {
      _paintInstructionLabel(
        canvas,
        cell.label!,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        spanTop: cellTop - offset * rowHeight,
        spanLength: spanLength,
      );
    }
  }

  /// The instruction's NAME, written DOWN the column beside its mark — the
  /// x-sheet's treatment, in print (user, 2026-08-08).
  ///
  /// Two things were wrong with the horizontal line it replaces. It was
  /// centred on `centerX`, which is where the duration bar is drawn, so
  /// the two were printed through each other. And it ran ACROSS, so
  /// `FOLLOW PAN` reached well past a 36px CAM column into whatever was
  /// beside it.
  ///
  /// It hangs off the column's RIGHT wall now, one glyph wide, centred on
  /// the span along the frame axis. Long names SPILL past their span
  /// rather than pack: the sheet's usual squeeze would put ten letters in
  /// a three-row span at 2.4pt, which is the very failure sideways Latin
  /// was invented to avoid. Writing that runs past its span is what a hand
  /// does on paper anyway.
  void _paintInstructionLabel(
    Canvas canvas,
    String label, {
    required double columnLeft,
    required double columnWidth,
    required double spanTop,
    required int spanLength,
  }) {
    const fontSize = 9.0;
    const lineHeight = 1.15;
    const naturalCellExtent = fontSize * lineHeight;
    // The right HALF of the column, inside its wall: the mark owns the
    // centre line and the writing may never cross back over it.
    final room = columnWidth / 2 - instructionLabelInset;
    if (room <= 0) {
      return;
    }
    final glyphWidth = math.min(fontSize, room);
    final cellCount = verticalTextSpanCount(
      verticalTextCells(label, latinForm: VerticalLatinForm.upright),
    );
    // The extent the column ACTUALLY needs, handed in as the span: with
    // supply equal to demand the shrink rule is a no-op, which is how
    // "spill, never pack" is stated to a painter that only knows how to
    // pack.
    final needed = cellCount * naturalCellExtent;
    paintVerticalText(
      canvas,
      label,
      style: const TextStyle(
        color: _ink,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
      centerX:
          columnLeft + columnWidth - instructionLabelInset - glyphWidth / 2,
      top: spanTop + spanLength * TimesheetDocumentLayout.rowHeight / 2 -
          needed / 2,
      mainExtent: needed,
      naturalCellExtent: naturalCellExtent,
      cellPadding: fontSize * (lineHeight - 1),
      maxCellWidth: glyphWidth,
      latinForm: VerticalLatinForm.upright,
    );
  }

  /// The solid triangle capping a NAMELESS bar endpoint (R7-①, real-sheet
  /// convention), APEX pointing INTO the span (R8-① direction fix): the
  /// start cap reads ▼ from the span's top edge, the end cap ▲ from its
  /// bottom edge — both bases sit FLUSH on the cell edge (compact, no
  /// inset). The duration line meets the apex. Mirrors the X-sheet
  /// overlay's mark.
  void _paintBarEndpointTriangle(
    Canvas canvas, {
    required double centerX,
    required double columnWidth,
    required double baseY,
    required bool apexDown,
  }) {
    final length = math.min(7.0, TimesheetDocumentLayout.rowHeight - 4);
    final halfWidth = math.min(4.0, columnWidth / 2 - 2);
    final apexY = apexDown ? baseY + length : baseY - length;
    canvas.drawPath(
      Path()..addPolygon([
        Offset(centerX - halfWidth, baseY),
        Offset(centerX, apexY),
        Offset(centerX + halfWidth, baseY),
      ], true),
      Paint()..color = _ink,
    );
  }

  /// One row's slice of an instruction span's FI/FO wedge or O.L bowtie:
  /// the mark geometry derives span-globally from the cell's
  /// spanOffset/spanLength and clips to this row, so spans crossing page
  /// halves paint seamlessly (each half paints only its own rows). The
  /// mark owns the column's full width ([halfWidth] from the caller),
  /// exactly like the X-sheet overlay.
  void _paintInstructionMarkSlice(
    Canvas canvas, {
    required TimesheetCell cell,
    required double centerX,
    required double halfWidth,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final shaftX = centerX;
    final spanTop = cellTop - (cell.spanOffset ?? 0) * rowHeight;
    final spanBottom = spanTop + (cell.spanLength ?? 1) * rowHeight;
    final mid = (spanTop + spanBottom) / 2;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        shaftX - halfWidth - 1,
        cellTop,
        (halfWidth + 1) * 2,
        rowHeight,
      ),
    );
    // R4: dedicated marks are plain LIGHT-GRAY FILLS laid under the grid
    // and the writing — no hatching, no outline (user sketch).
    final fill = Paint()..color = _ink.withValues(alpha: 0.15);
    switch (cell.markType ?? CameraInstructionMarkType.bar) {
      case CameraInstructionMarkType.ol:
        canvas.drawPath(
          Path()..addPolygon([
            Offset(shaftX - halfWidth, spanTop),
            Offset(shaftX + halfWidth, spanTop),
            Offset(shaftX, mid),
          ], true),
          fill,
        );
        canvas.drawPath(
          Path()..addPolygon([
            Offset(shaftX - halfWidth, spanBottom),
            Offset(shaftX + halfWidth, spanBottom),
            Offset(shaftX, mid),
          ], true),
          fill,
        );
      case CameraInstructionMarkType.fi:
      case CameraInstructionMarkType.fo:
        // The fade wedge follows the light: FI opens narrow → wide (the
        // picture grows in), FO wide → narrow (R4 orientation fix).
        final fadeIn = cell.markType == CameraInstructionMarkType.fi;
        final wideY = fadeIn ? spanBottom - 1 : spanTop + 1;
        final pointY = fadeIn ? spanTop + 1 : spanBottom - 1;
        canvas.drawPath(
          Path()..addPolygon([
            Offset(shaftX - halfWidth, wideY),
            Offset(shaftX, pointY),
            Offset(shaftX + halfWidth, wideY),
          ], true),
          fill,
        );
      case CameraInstructionMarkType.bar:
        // Dispatched to the straight-line path before reaching here.
        break;
    }
    canvas.restore();
  }

  void _paintGroupTitles(Canvas canvas, double halfLeft, double groupTop) {
    // Contiguous kind runs become group headers (ACTION / SE / CELL / CAM).
    var runStart = 0;
    while (runStart < document.columns.length) {
      final kind = document.columns[runStart].kind;
      var runEnd = runStart;
      while (runEnd + 1 < document.columns.length &&
          document.columns[runEnd + 1].kind == kind) {
        runEnd += 1;
      }
      final leftX = halfLeft + layout.columnLeftInHalf(runStart);
      final rightX =
          halfLeft +
          layout.columnLeftInHalf(runEnd) +
          layout.columnWidthFor(kind);
      final title = switch (kind) {
        TimesheetColumnKind.action => 'ACTION',
        TimesheetColumnKind.se => 'SE',
        TimesheetColumnKind.cel => 'CELL',
        TimesheetColumnKind.camera => 'CAM',
      };
      _text(
        canvas,
        title,
        Offset((leftX + rightX) / 2, groupTop + 2),
        fontSize: 9,
        bold: true,
        color: _ink,
        centeredAtX: true,
      );
      runStart = runEnd + 1;
    }
  }

  /// An SE entry's start cell (R5-⑦, user-approved mockup v4): a full-width
  /// thin red bar RIGHT BEFORE the block start, a compact ACCENT name box
  /// (the app's shared accent — same chip as the timeline/X-sheet rows)
  /// hugging the boundary, the dialogue distributed vertically over the
  /// REST of the span — no duration bar. Single-row entries close with the
  /// red end bar right here; longer ones close from their last held row.
  void _paintSeEntryStart(
    Canvas canvas, {
    required TimesheetCell cell,
    required int row,
    required int rowCount,
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    const nameBoxHeight = 12.0;
    final spanLength = cell.spanLength ?? 1;
    final rowsHere = spanLength.clamp(1, rowCount - row);
    final spanBottom = cellTop + rowsHere * rowHeight;
    final seName = cell.seName ?? '';

    // The opening red bar sits ON the start boundary only when this row
    // really is the span's first (page-half continuations skip it).
    if ((cell.spanOffset ?? 0) == 0) {
      _paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: cellTop + 1,
      );
    }

    var dialogueTop = cellTop + 3;
    if (seName.isNotEmpty) {
      // R6-②: a soft accent tint with dark ink writing — the full-strength
      // accent read too loud against the paper. FULL column width (R7-②:
      // the name box, the red bars and the SE column must share ONE exact
      // width — the old 1px inset read as a mismatched overlay).
      canvas.drawRect(
        Rect.fromLTWH(columnLeft, cellTop + 2, columnWidth, nameBoxHeight),
        Paint()..color = AppColors.accent.withValues(alpha: 0.3),
      );
      _text(
        canvas,
        seName,
        Offset(centerX, cellTop + 4),
        fontSize: 7,
        bold: true,
        color: _ink,
        centeredAtX: true,
        maxWidth: columnWidth - 4,
      );
      dialogueTop = cellTop + nameBoxHeight + 4;
    }

    final dialogueExtent = spanBottom - 2 - dialogueTop;
    if (dialogueExtent > 4 && (cell.label ?? '').isNotEmpty) {
      _fitVerticalText(
        canvas,
        cell.label!,
        topCenter: Offset(centerX, dialogueTop),
        fontSize: 9,
        extent: dialogueExtent,
      );
    }

    if (spanLength == 1) {
      _paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: spanBottom - 1,
      );
    }
  }

  /// The full-width thin red bar closing an SE block (and mirrored before
  /// its start) — Toei notation, R5-⑦: frame-width, not a short tick. ONE
  /// geometry with the name box and the SE column itself (R7-②).
  void _paintSeRedBar(
    Canvas canvas, {
    required double columnLeft,
    required double columnWidth,
    required double y,
  }) {
    canvas.drawLine(
      Offset(columnLeft, y),
      Offset(columnLeft + columnWidth, y),
      Paint()
        ..color = AppColors.danger
        ..strokeWidth = 2,
    );
  }

  /// An SE column's empty row: the light-gray "no SE here" wash (project
  /// toggle). Print-sheet only — the timeline/X-sheet's dark uncovered
  /// cells already read as empty, and the dotted center guide is retired
  /// everywhere (R5-②).
  void _paintSeEmptyRow(
    Canvas canvas, {
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    if (document.seEmptyFill) {
      canvas.drawRect(
        Rect.fromLTWH(columnLeft, cellTop, columnWidth, rowHeight),
        Paint()..color = _ink.withValues(alpha: 0.05),
      );
    }
  }

  /// SE dialogue distributed evenly over the covered rows — the sheet's
  /// "fit" rule, sharing [dialogueGlyphCenters] with the timeline overlay
  /// so screen and print place glyphs identically. Never truncates: the
  /// dialogue owns its whole block, exactly like the paper column.
  ///
  /// The FORMS come from the app's one vertical-writing table, like every
  /// other column on this sheet. They used not to — this placer stacked
  /// every glyph upright, so a `ー` inside dialogue lay across the column
  /// while the notation word two columns over rotated it.
  void _fitVerticalText(
    Canvas canvas,
    String text, {
    required Offset topCenter,
    required double fontSize,
    required double extent,
    Color color = _ink,
  }) {
    final glyphs = text.characters.toList(growable: false);
    final centers = dialogueGlyphCenters(
      glyphCount: glyphs.length,
      mainExtent: extent,
    );
    for (var index = 0; index < glyphs.length; index += 1) {
      final painter = TextPainter(
        text: TextSpan(
          text: glyphs[index],
          style: TextStyle(color: color, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      paintVerticalTextCell(
        canvas,
        verticalGlyphCell(glyphs[index]),
        painter: painter,
        center: Offset(topCenter.dx, topCenter.dy + centers[index]),
        fontSize: fontSize,
      );
    }
  }

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
    super.repaint,
  });

  final TimesheetDocument document;
  final TimesheetDocumentLayout layout;

  /// Reads the CURRENT playhead frame at paint time (the repaint
  /// listenable drives when that happens).
  final int? Function() resolvePlayheadFrame;
  final CanvasViewport? viewport;

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
      canvas.translate(resolvedViewport.panX, resolvedViewport.panY);
      canvas.scale(resolvedViewport.zoom, resolvedViewport.zoom);
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
        oldDelegate.viewport != viewport;
  }
}
