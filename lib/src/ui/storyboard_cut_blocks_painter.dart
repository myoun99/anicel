import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/storyboard_coverage.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import '../models/timeline_row_address.dart';
import '../models/track_frame_range.dart';
import 'storyboard_layer_policy.dart';
import 'storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/timeline_cell_style.dart';
import 'timeline/timeline_frame_geometry.dart';
import 'timeline/timeline_frame_range_policy.dart' show timelineDurationLabel;
import 'timeline/timeline_frame_window.dart';
import 'timeline/timeline_glyph_cache.dart';

/// One cut block as the painter draws it — THE probe surface, in place of
/// the widget keys the blocks used to carry.
class StoryboardCutBlockVisual {
  const StoryboardCutBlockVisual({
    required this.cutId,
    required this.rect,
    required this.isActive,
    required this.isRangeSelected,
    required this.isHovered,
    required this.title,
    required this.layerLabel,
    required this.hasStoryboardLayer,
    required this.total,
    required this.thumbnails,
    required this.cells,
    this.cellNames = const [],
    this.cellCommaLabels = const [],
    required Rect topBand,
    required Rect strip,
    required Rect bottomBand,
  }) : _topBand = topBand,
       _strip = strip,
       _bottomBand = bottomBand;

  final CutId cutId;

  /// The block's box in ROW-local coordinates.
  final Rect rect;

  /// The three bands, in row-local coordinates. The STRIP is the picture:
  /// the cut's panels live there and nothing is written over them. The two
  /// thin bands carry the writing instead — the cut's number at the left
  /// end of the top one, its length at the right end of the bottom one,
  /// which is the conte sheet's CUT and TIME columns laid on their side.
  ///
  /// When the row is too short for three of anything the bands FOLD: both
  /// are [Rect.zero] and the strip takes the whole block, with the writing
  /// falling back over the picture the way it used to sit.
  Rect get topBand => _topBand;
  Rect get strip => _strip;
  Rect get bottomBand => _bottomBand;

  final Rect _topBand;
  final Rect _strip;
  final Rect _bottomBand;

  /// Whether the bands folded away (a short row).
  bool get bandsFolded => _topBand.height <= 0;

  /// The cut's panels — the divisions the strip draws, under the coverage
  /// rule. Never empty: a cut with no storyboard row still has one cell.
  final List<StoryboardCoverageCell> cells;

  /// Each panel's frame NAME (#15: the timeline convention — the name, or
  /// `○` when unnamed; `●` stays the inbetween mark's), parallel to
  /// [cells]; empty string on the no-row placeholder cell. EMPTY LISTS
  /// when the bands fold — folding that far means watching the cuts, not
  /// the panels, so the writing is omitted at the source (probe-visible).
  final List<String> cellNames;

  /// Each panel's printed length (#15: the timeline's comma count, at the
  /// panel's last cell bottom-centre), parallel to [cells]; empty on the
  /// no-row placeholder cell, EMPTY LISTS when the bands fold.
  final List<String> cellCommaLabels;

  final bool isActive;
  final bool isRangeSelected;
  final bool isHovered;

  /// The cut's name, drawn top-left.
  final String title;

  /// The storyboard layer's name, or the empty-state wording when the cut
  /// has no storyboard layer.
  final String layerLabel;
  final bool hasStoryboardLayer;

  /// The cumulative time at the cut's end (the conte sheet's TIME column),
  /// or null when the block is too narrow to print it.
  final String? total;

  /// One picture per [cells] entry, in the same order — null while a
  /// render is pending (that cell shows its placeholder then). Owned by the
  /// thumbnail store.
  final List<ui.Image?> thumbnails;
}

/// The cut row's blocks, PAINTED (the storyboard's half of the timeline's
/// row painterization).
///
/// The row used to be three widgets a cut — the block, plus a grip at each
/// edge — laid into one `Stack` for the whole track, so a zoom step relaid
/// out every cut on the film and every build asked the thumbnail store for
/// every cut's picture. The timeline solved this years of rounds ago: cells
/// are canvas work and only the sparse interactive chrome stays widgets.
/// This is the same treatment for cuts, which lets the row take the shared
/// frame WINDOW as well — off-screen cuts cost nothing, thumbnails included.
///
/// Only the drawing lives here. Selecting, sliding and reordering are the
/// shared range gesture's, mounted above.
class StoryboardCutBlocksPainter extends CustomPainter {
  StoryboardCutBlocksPainter({
    required this.entries,
    required this.storyboardLayerNames,
    required this.storyboardCellsByCut,
    required this.geometry,
    required this.crossAxisExtent,
    required this.minBlockWidth,
    required this.activeCutId,
    required this.selectedRange,
    required this.rowAddress,
    required this.hoveredCutId,
    required this.colorScheme,
    required this.brightness,
    required this.baseTextStyle,
    required this.showSeconds,
    required this.countingBase,
    this.thumbnailFor,
    this.showThumbnails = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?selectedRange,
           hoveredCutId,
           ?windowBucket,
         ]),
       );

  final List<StoryboardTimelineLayoutEntry> entries;

  /// Each cut's storyboard layer NAME, or absent when the cut has none.
  ///
  /// Resolved by the row at build time as shared inputs (the grips read
  /// the same cells). [storyboardLayerForCut] stopped throwing on
  /// duplicate rows (#760) — "the first one is the row" — so the painter
  /// may also call it directly where it needs more than these carry (the
  /// per-panel frame names).
  final Map<CutId, String> storyboardLayerNames;

  /// Each cut's panels (the coverage rule's cells), resolved by the row —
  /// the strip's content AND its grip material, one resolution for both.
  /// A cut always has at least one.
  final Map<CutId, List<StoryboardCoverageCell>> storyboardCellsByCut;

  /// The LIVE frame-axis geometry: a zoom step repaints instead of
  /// rebuilding the row that built this.
  final TimelineFrameGeometryHandle geometry;

  final double crossAxisExtent;

  /// Blocks never draw narrower than this, however short the cut — the
  /// `TimelineScale` rule the widget blocks were sized by.
  final double minBlockWidth;

  final CutId? activeCutId;

  /// The live frame RANGE on this track's global axis. A block is selected
  /// when the range COVERS it — the cut row is a frame-axis row and a cut
  /// is a long block on it, so there is no list of selected cuts to carry.
  final ValueListenable<TrackFrameRangeSelection?>? selectedRange;

  /// This row's address, so a selection anchored on another row (an S row,
  /// once those select too) does not tint these blocks.
  final TimelineRowAddress rowAddress;
  final ValueListenable<CutId?> hoveredCutId;

  final ColorScheme colorScheme;
  final Brightness brightness;
  final TextStyle baseTextStyle;
  final bool showSeconds;
  final int countingBase;

  /// Painted, never disposed here: the thumbnail store owns the image.
  /// Asked ONLY for blocks inside the window, which is the point.
  final StoryboardThumbnailResolver? thumbnailFor;
  final bool showThumbnails;

  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  static const double _padding = 4;
  static const double _radius = 8;

  /// The narrowest block that still prints its total (the widget rule).
  static const double totalLabelMinWidth = 48;

  double get _cellExtent => geometry.value.frameCellExtent;

  double _left(int frame) => frame * _cellExtent;

  double _widthFor(int duration) {
    final width = duration * _cellExtent;
    return width < minBlockWidth ? minBlockWidth : width;
  }

  /// The frame span worth drawing — the full track under the classic
  /// contract, the bucket-derived window (shared policy) when the row is
  /// self-windowing.
  ({int startIndex, int endIndexExclusive}) visibleFrameWindow() {
    final bucket = windowBucket;
    if (bucket == null || viewportMainExtent <= 0 || _cellExtent <= 0) {
      return (startIndex: 0, endIndexExclusive: 1 << 30);
    }
    return timelineFrameWindowFor(
      bucket: bucket.value,
      cellExtent: _cellExtent,
      viewportExtent: viewportMainExtent,
    );
  }

  /// The thin bands' height, and the shortest block that still gets them.
  /// Below that the row has no room for three of anything, so they fold and
  /// the writing falls back over the picture (the same grammar the
  /// thumbnail's own fallbacks use).
  static const double bandHeight = 13;
  static const double bandsMinBlockHeight = 44;

  /// The STRIP's vertical slot in a row this tall, row-local. The panels
  /// are drawn there, so the panel gestures and the panel EDGES are mounted
  /// there too — one definition, or the picture and the pointer disagree.
  /// A folded row has no bands, so the strip is the whole row.
  static ({double top, double height}) stripBandOf(double rowHeight) =>
      rowHeight < bandsMinBlockHeight
      ? (top: 0, height: rowHeight)
      : (top: bandHeight, height: rowHeight - bandHeight * 2);

  /// A block's three bands. Folded (both bands [Rect.zero], the strip
  /// taking everything) when the row is too short — which is [stripBandOf]
  /// answering with the whole row, so the fold is decided in one place.
  ({Rect top, Rect strip, Rect bottom}) _bandsOf(Rect rect) {
    final band = stripBandOf(rect.height);
    final strip = Rect.fromLTWH(
      rect.left,
      rect.top + band.top,
      rect.width,
      band.height,
    );
    if (band.top <= 0) {
      return (top: Rect.zero, strip: strip, bottom: Rect.zero);
    }
    return (
      top: Rect.fromLTWH(rect.left, rect.top, rect.width, bandHeight),
      strip: strip,
      bottom: Rect.fromLTWH(
        rect.left,
        rect.bottom - bandHeight,
        rect.width,
        bandHeight,
      ),
    );
  }

  /// Every block this row would draw, in track order — THE probe surface.
  ///
  /// Off-window cuts are absent by construction, which is also what keeps
  /// [thumbnailFor] from being asked for pictures nobody can see.
  List<StoryboardCutBlockVisual> blocks() {
    final window = visibleFrameWindow();
    final selectionValue = selectedRange?.value;
    final selection =
        selectionValue != null && selectionValue.coversRow(rowAddress)
        ? selectionValue
        : null;
    final hovered = hoveredCutId.value;
    final visuals = <StoryboardCutBlockVisual>[];
    for (final entry in entries) {
      final left = _left(entry.startFrame);
      final width = _widthFor(entry.duration);
      // A block reaches at least [minBlockWidth], so its visible end is
      // measured in pixels, not in the cut's own frames.
      final endFrame = _cellExtent <= 0
          ? entry.endFrame
          : entry.startFrame + (width / _cellExtent).ceil();
      if (endFrame <= window.startIndex ||
          entry.startFrame >= window.endIndexExclusive) {
        continue;
      }
      final layerName = storyboardLayerNames[entry.cutId];
      final rect = Rect.fromLTWH(left, 0, width, crossAxisExtent);
      final bands = _bandsOf(rect);
      final cells = storyboardCellsByCut[entry.cutId] ?? const [];
      // The panels' writing (#15): frame name + comma count per cell, the
      // timeline row's conventions (`○` unnamed head — `●` would read as
      // an inbetween mark). Safe to resolve here — the row lookup no
      // longer throws on duplicates (#760). A folded block carries no
      // writing at all: folding that far means watching the cuts.
      final folded = bands.top.height <= 0;
      final frameNames = <FrameId, String?>{
        if (!folded)
          for (final frame
              in storyboardLayerForCut(entry.cut)?.frames ?? const <Frame>[])
            frame.id: frame.name,
      };
      visuals.add(
        StoryboardCutBlockVisual(
          cutId: entry.cutId,
          rect: rect,
          topBand: bands.top,
          strip: bands.strip,
          bottomBand: bands.bottom,
          cells: cells,
          cellNames: [
            if (!folded)
              for (final cell in cells)
                cell.frameId == null
                    ? ''
                    : ((frameNames[cell.frameId] ?? '').isEmpty
                          ? '○'
                          : frameNames[cell.frameId]!),
          ],
          cellCommaLabels: [
            if (!folded)
              for (final cell in cells)
                cell.frameId == null
                    ? ''
                    : timelineDurationLabel(
                        cell.endIndexExclusive - cell.startIndex,
                        showSeconds: showSeconds,
                        countingBase: countingBase,
                      ),
          ],
          isActive: entry.cutId == activeCutId,
          isRangeSelected:
              selection?.overlaps(entry.startFrame, entry.endFrame) ?? false,
          isHovered: entry.cutId == hovered,
          title: entry.cut.name,
          layerLabel: layerName ?? storyboardCutBlockNoLayerLabel,
          hasStoryboardLayer: layerName != null,
          total: width >= totalLabelMinWidth
              ? timelineDurationLabel(
                  entry.endFrame,
                  showSeconds: showSeconds,
                  countingBase: countingBase,
                )
              : null,
          // Asked ONLY here, for blocks the window keeps: the row used to
          // request every cut's picture on every build. One per PANEL now,
          // each at the frame that panel is about.
          thumbnails: [
            if (showThumbnails && thumbnailFor != null)
              for (final cell in cells)
                thumbnailFor!(
                  entry.cut,
                  storyboardCellPictureFrame(
                    cell,
                    pinnedFrameIndex: entry.cut.metadata.thumbnailFrameIndex,
                  ),
                ),
          ],
        ),
      );
    }
    return visuals;
  }

  /// The block covering row-local [position], or null between blocks.
  StoryboardCutBlockVisual? blockAt(Offset position) {
    for (final block in blocks()) {
      if (block.rect.contains(position)) {
        return block;
      }
    }
    return null;
  }

  StoryboardCutBlockVisual? blockForCut(CutId cutId) {
    for (final block in blocks()) {
      if (block.cutId == cutId) {
        return block;
      }
    }
    return null;
  }

  TextStyle get _labelStyle =>
      baseTextStyle.merge(const TextStyle(fontSize: 11));

  // The CELLS' writing convention on every cut-block label too (user
  // 2026-07-29, "cut blocks and storyboard blocks read as one"): panel ink
  // carried by the shared GROUND LAW (2026-08-17, the difference blend's
  // successor) — one solid, black or white by the luminance of the fill
  // each label sits on, in place of scrims, halos and per-surface colours.
  // The styles' colors are layout/cache identity; the paint resolves the
  // real ink through [paintTimelineGlyphOnGround].
  TextStyle get _titleStyle => _labelStyle.copyWith(
    color: timelineDrawingInkColor,
    fontWeight: FontWeight.bold,
  );

  TextStyle get _emptyLayerStyle => _labelStyle.copyWith(
    color: timelineDrawingInkColor.withValues(alpha: 0.72),
  );

  TextStyle get _totalStyle => _labelStyle.copyWith(
    color: timelineDrawingInkColor.withValues(alpha: 0.72),
    // R27 #3: bold — the readout was too easy to miss.
    fontWeight: FontWeight.w700,
  );

  /// The BANDS' composited fill — the ground their writing sits on. Bands
  /// wear the range tint whenever the block is range-selected (folded
  /// blocks tint whole, unfolded ones tint exactly the bands), so this is
  /// one expression of the same fills [_paintBlock] lays down.
  Color _bandGround(StoryboardCutBlockVisual block) =>
      storyboardCutBlockBackgroundColor(
        colorScheme,
        active: block.isActive,
        hovered: block.isHovered,
        rangeSelected: block.isRangeSelected,
      );

  /// The STRIP's underlay — the ground for writing that rides the picture
  /// area (panel names and commas, the folded block's labels). A range
  /// selection only reaches the strip when the bands folded (design: the
  /// selection colours what is NOT the picture). The thumbnails above it
  /// are unknowable pixels; the deterministic plate beneath them (also the
  /// pending placeholder's shade) is the honest ground.
  Color _stripGround(StoryboardCutBlockVisual block) =>
      storyboardCutBlockBackgroundColor(
        colorScheme,
        active: block.isActive,
        hovered: block.isHovered,
        rangeSelected: block.isRangeSelected && block.bandsFolded,
      );

  @override
  void paint(Canvas canvas, Size size) {
    for (final block in blocks()) {
      _paintBlock(canvas, block);
    }
  }

  void _paintBlock(Canvas canvas, StoryboardCutBlockVisual block) {
    final rrect = RRect.fromRectAndRadius(
      block.rect,
      const Radius.circular(_radius),
    );
    // The BACKGROUND carries the cut's own states. A range selection tints
    // only what is NOT the picture (design: "a cut selection colours the
    // area that is not a storyboard block") — the bands, when there are
    // bands to tint. With none the block is all there is, so it all tints,
    // which is one sentence with two results rather than two rules.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = storyboardCutBlockBackgroundColor(
          colorScheme,
          active: block.isActive,
          hovered: block.isHovered,
          rangeSelected: block.isRangeSelected && block.bandsFolded,
        ),
    );
    if (block.isRangeSelected && !block.bandsFolded) {
      final tint = Paint()
        ..color = storyboardCutBlockBackgroundColor(
          colorScheme,
          active: block.isActive,
          hovered: block.isHovered,
          rangeSelected: true,
        );
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(block.topBand, tint);
      canvas.drawRect(block.bottomBand, tint);
      canvas.restore();
    }

    final inner = block.bandsFolded
        ? block.rect.deflate(_padding)
        : block.strip;
    if (showThumbnails && inner.width > 0 && inner.height > 0) {
      canvas.save();
      canvas.clipRRect(rrect);
      _paintPanelPictures(canvas, block, inner);
      canvas.restore();
    }
    // The panels separate through their own SILHOUETTE borders (#15,
    // painted per slot above) — the divider question #760 left open is
    // closed by those, not by a rule of their own.

    // ONE border for every cut block. The active cut used to wear a 2px
    // accent one here — this rail's own way of saying "the block you are
    // standing on", invented because the storyboard was never unified with
    // the timeline. The standing outline says it now, in the timeline's
    // words and on every row kind, so a second sentence in the same place
    // is just two borders on one rectangle. Which cut is ACTIVE still
    // reads from the BACKGROUND: a different statement, a different
    // channel, and the one that survives standing somewhere else.
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = storyboardCutBlockEdgeColor(
          colorScheme,
          brightness,
          active: false,
          hovered: block.isHovered,
        ),
    );

    if (inner.width <= 0 || inner.height <= 0) {
      return;
    }
    if (block.bandsFolded) {
      // FOLDED: nowhere to put the writing but over the picture — the
      // shared ground law keeps it readable there against the strip's
      // plate, exactly as it does on every panel cell (the scrim this
      // replaced was a second answer to the same question).
      final ground = _stripGround(block);
      canvas.save();
      canvas.clipRect(inner);
      _paintAnchoredLabel(
        canvas,
        text: block.title,
        style: _titleStyle,
        maxWidth: inner.width,
        anchor: inner.topLeft,
        alignRight: false,
        alignBottom: false,
        ground: ground,
      );
      final total = block.total;
      if (total != null) {
        _paintAnchoredLabel(
          canvas,
          text: total,
          style: _totalStyle,
          maxWidth: inner.width,
          anchor: inner.bottomRight,
          alignRight: true,
          alignBottom: true,
          ground: ground,
        );
      }
      canvas.restore();
      return;
    }

    // THE BANDS carry the writing, so nothing is drawn over the picture and
    // no scrim is needed. Number at the top band's left end, length at the
    // bottom band's right end: the conte sheet's CUT and TIME columns sit
    // outside the picture cell exactly this way, one above and one below,
    // and this is that sheet turned on its side.
    final bandGround = _bandGround(block);
    canvas.save();
    canvas.clipRect(block.topBand);
    _paintBandText(
      canvas,
      text: block.title,
      style: _titleStyle,
      band: block.topBand,
      alignRight: false,
      ground: bandGround,
    );
    canvas.restore();

    canvas.save();
    canvas.clipRect(block.bottomBand);
    if (!block.hasStoryboardLayer) {
      _paintBandText(
        canvas,
        text: block.layerLabel,
        style: _emptyLayerStyle,
        band: block.bottomBand,
        alignRight: false,
        ground: bandGround,
      );
    }
    final total = block.total;
    if (total != null) {
      _paintBandText(
        canvas,
        text: total,
        style: _totalStyle,
        band: block.bottomBand,
        alignRight: true,
        ground: bandGround,
      );
    }
    canvas.restore();
  }

  void _paintBandText(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required Rect band,
    required bool alignRight,
    required Color ground,
  }) {
    if (text.isEmpty || band.width <= 0) {
      return;
    }
    final maxWidth = math.max(0.0, band.width - _padding * 2);
    final glyph = timelineGlyphPainter(text, style, maxWidth: maxWidth);
    final dx = alignRight
        ? band.right - _padding - glyph.width
        : band.left + _padding;
    paintTimelineGlyphOnGround(
      canvas,
      Offset(dx, band.top + (band.height - glyph.height) / 2),
      text,
      style,
      ground: ground,
      maxWidth: maxWidth,
    );
  }

  /// A corner-anchored ground-law label — the folded block's writing (and
  /// nothing else's: band text centres itself vertically instead).
  void _paintAnchoredLabel(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required double maxWidth,
    required Offset anchor,
    required bool alignRight,
    required bool alignBottom,
    required Color ground,
  }) {
    if (text.isEmpty || maxWidth <= 0) {
      return;
    }
    final glyph = timelineGlyphPainter(text, style, maxWidth: maxWidth);
    final left = alignRight ? anchor.dx - glyph.width : anchor.dx;
    final top = alignBottom ? anchor.dy - glyph.height : anchor.dy;
    paintTimelineGlyphOnGround(
      canvas,
      Offset(left, top),
      text,
      style,
      ground: ground,
      maxWidth: maxWidth,
    );
  }

  /// One picture per PANEL, each in its own slice of the strip.
  ///
  /// The slice is measured in FRAMES, like every other x on this row: a
  /// panel's picture starts where its division does, so it lines up with
  /// the ruler, the playhead and the SE rows. A block drawn at
  /// [minBlockWidth] is wider than its frames, and its panels simply clip.
  void _paintPanelPictures(
    Canvas canvas,
    StoryboardCutBlockVisual block,
    Rect inner,
  ) {
    if (block.cells.isEmpty || block.thumbnails.length != block.cells.length) {
      // No coverage reading (or a mid-rebuild mismatch): the block is one
      // slot, and the placeholder covers it. It is a plate on the rows body,
      // so it wears the shade rather than a chrome fill.
      canvas.drawRect(block.rect, Paint()..color = AppColors.washUp);
      return;
    }
    for (var index = 0; index < block.cells.length; index += 1) {
      final cell = block.cells[index];
      final left = _cellExtent <= 0
          ? inner.left
          : inner.left + cell.startIndex * _cellExtent;
      final right = _cellExtent <= 0
          ? inner.right
          : inner.left + cell.endIndexExclusive * _cellExtent;
      final slot = Rect.fromLTRB(
        math.max(left, inner.left),
        inner.top,
        math.min(right, inner.right),
        inner.bottom,
      );
      if (slot.width <= 0) {
        continue;
      }
      canvas.save();
      canvas.clipRect(slot);
      _paintPanelPicture(canvas, block.thumbnails[index], slot);
      if (!block.bandsFolded) {
        _paintPanelWriting(canvas, block, index, slot);
      }
      canvas.restore();
      if (block.hasStoryboardLayer && !block.bandsFolded) {
        // The panel's SILHOUETTE (#15): each block outlines itself, which
        // is what separates two touching panels — the seam the removed
        // division rules used to draw, without a rule of its own. Folded
        // rows omit it with the rest of the panel info: their slots ride
        // the 4px-deflated inner rect, so a border there would sit off
        // the true frame edges the grips are mounted on.
        canvas.drawRect(
          slot.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = storyboardCutBlockEdgeColor(
              colorScheme,
              brightness,
              active: false,
              hovered: false,
            ),
        );
      }
    }
  }

  /// A panel's own writing (#15, the timeline row's conventions carried
  /// over): the frame NAME centred in the panel's first frame cell, the
  /// COMMA COUNT bottom-centred in its last — both through the ground law,
  /// against the strip's plate. Folded bands omit all of it (the caller's
  /// gate): folding that far means watching the cuts, not the panels.
  void _paintPanelWriting(
    Canvas canvas,
    StoryboardCutBlockVisual block,
    int index,
    Rect slot,
  ) {
    if (index >= block.cellNames.length ||
        index >= block.cellCommaLabels.length ||
        _cellExtent <= 0) {
      return;
    }
    final name = block.cellNames[index];
    if (name.isNotEmpty) {
      final nameStyle = baseTextStyle.copyWith(
        color: timelineDrawingInkColor,
        fontWeight: FontWeight.bold,
        fontSize: timelineFittedGlyphFontSize(
          baseTextStyle.fontSize ?? 12,
          _cellExtent,
          crossExtent: slot.height,
        ),
      );
      // TOP-LEFT, the cut block title's own anchor (user 2026-07-29):
      // thumbnail-display writing sits where the sheet's cut number does,
      // not centred the way block-display glyphs are — the two thumbnail
      // surfaces read as one.
      paintTimelineGlyphOnGround(
        canvas,
        Offset(slot.left + _padding / 2, slot.top + 1),
        name,
        nameStyle,
        ground: _stripGround(block),
      );
    }
    final comma = block.cellCommaLabels[index];
    if (comma.isNotEmpty) {
      final commaStyle = TextStyle(
        fontSize: timelineFittedGlyphFontSize(
          9,
          _cellExtent,
          crossExtent: slot.height,
        ),
        fontWeight: FontWeight.w700,
        color: timelineDrawingInkColor.withValues(alpha: 0.72),
      );
      final glyph = timelineGlyphPainter(comma, commaStyle);
      // The block's LAST cell, bottom-centre, 1px inset — the timeline
      // run label's anchor, in the panel's own coordinates (the slot's
      // edges ARE the cell edges: panels tile the strip).
      final lastCellCentre = slot.right - _cellExtent / 2;
      paintTimelineGlyphOnGround(
        canvas,
        Offset(
          lastCellCentre - glyph.width / 2,
          slot.bottom - glyph.height - 1,
        ),
        comma,
        commaStyle,
        ground: _stripGround(block),
      );
    }
  }

  void _paintPanelPicture(Canvas canvas, ui.Image? image, Rect slot) {
    if (image == null) {
      // The pending placeholder the empty thumbnail slot used to be.
      canvas.drawRect(slot, Paint()..color = AppColors.washUp);
      return;
    }
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // The picture is sized by the ROW's height alone and LEFT-aligned: a
    // shorter comma shows LESS of it, never a smaller copy of it (user,
    // 2026-07-28). Fitting the width instead made the picture shrink as
    // the block narrowed, so a row of short holds read as a row of tiny
    // thumbnails rather than as short holds. The caller clips to the slot,
    // which is what turns "less width" into "less picture".
    final scale = slot.height / source.height;
    final drawn = Size(source.width * scale, source.height * scale);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(slot.left, slot.top, drawn.width, drawn.height),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant StoryboardCutBlocksPainter oldDelegate) =>
      // Geometry, selection and hover are absent on purpose — they arrive
      // through `repaint`.
      !identical(oldDelegate.entries, entries) ||
      !mapEquals(oldDelegate.storyboardLayerNames, storyboardLayerNames) ||
      oldDelegate.crossAxisExtent != crossAxisExtent ||
      oldDelegate.minBlockWidth != minBlockWidth ||
      oldDelegate.activeCutId != activeCutId ||
      oldDelegate.rowAddress != rowAddress ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.brightness != brightness ||
      oldDelegate.baseTextStyle != baseTextStyle ||
      oldDelegate.showSeconds != showSeconds ||
      oldDelegate.countingBase != countingBase ||
      oldDelegate.showThumbnails != showThumbnails ||
      oldDelegate.viewportMainExtent != viewportMainExtent;

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        // One node per block: the `Text` widgets these replaced carried their
        // own, and dropping them would take the row away from screen readers.
        for (final block in blocks())
          CustomPainterSemantics(
            rect: block.rect,
            properties: SemanticsProperties(
              label:
                  '${block.title} ${block.layerLabel}'
                  '${block.total == null ? '' : ' ${block.total}'}',
              textDirection: TextDirection.ltr,
            ),
          ),
      ];
}
