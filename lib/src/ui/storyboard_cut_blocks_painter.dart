import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../models/cut_id.dart';
import '../models/storyboard_coverage.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import '../models/timeline_row_address.dart';
import '../models/track_frame_range.dart';
import 'storyboard_layer_policy.dart';
import 'storyboard_timeline_layout.dart';
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
  /// Resolved by the row at build time rather than here: [storyboardLayerForCut]
  /// throws when a cut somehow holds two storyboard layers, and a painter that
  /// throws takes the whole frame down instead of the widget that asked.
  final Map<CutId, String> storyboardLayerNames;

  /// Each cut's panels (the coverage rule's cells), resolved by the row for
  /// the same reason. A cut always has at least one.
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
      visuals.add(
        StoryboardCutBlockVisual(
          cutId: entry.cutId,
          rect: rect,
          topBand: bands.top,
          strip: bands.strip,
          bottomBand: bands.bottom,
          cells: cells,
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

  TextStyle get _titleStyle => _labelStyle;

  TextStyle get _emptyLayerStyle =>
      _labelStyle.copyWith(color: colorScheme.onSurfaceVariant);

  TextStyle get _totalStyle => _labelStyle.copyWith(
    color: colorScheme.onSurfaceVariant,
    // R27 #3: bold — the readout was too easy to miss.
    fontWeight: FontWeight.w700,
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
    if (!block.bandsFolded) {
      canvas.save();
      canvas.clipRRect(rrect);
      _paintCellDivisions(canvas, block);
      canvas.restore();
    }

    canvas.drawRRect(
      rrect.deflate(block.isActive ? 1 : 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = block.isActive ? 2 : 1
        ..color = storyboardCutBlockEdgeColor(
          colorScheme,
          brightness,
          active: block.isActive,
          hovered: block.isHovered,
        ),
    );

    if (inner.width <= 0 || inner.height <= 0) {
      return;
    }
    if (block.bandsFolded) {
      // FOLDED: nowhere to put the writing but over the picture, so the
      // scrim comes back for exactly this case.
      canvas.save();
      canvas.clipRect(inner);
      _paintScrimmed(
        canvas,
        text: block.title,
        style: _titleStyle,
        maxWidth: inner.width,
        anchor: inner.topLeft,
        alignRight: false,
        alignBottom: false,
      );
      final total = block.total;
      if (total != null) {
        _paintScrimmed(
          canvas,
          text: total,
          style: _totalStyle,
          maxWidth: inner.width,
          anchor: inner.bottomRight,
          alignRight: true,
          alignBottom: true,
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
    canvas.save();
    canvas.clipRect(block.topBand);
    _paintBandText(
      canvas,
      text: block.title,
      style: _titleStyle,
      band: block.topBand,
      alignRight: false,
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
      );
    }
    canvas.restore();
  }

  /// The divisions between the cut's panels, drawn ON the strip: the strip
  /// fills the block's width edge to edge, so a division's x IS its frame's
  /// x — the ruler, the playhead and the SE rows all line up with it.
  void _paintCellDivisions(Canvas canvas, StoryboardCutBlockVisual block) {
    if (block.cells.length < 2 || _cellExtent <= 0) {
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = storyboardCutBlockEdgeColor(
        colorScheme,
        brightness,
        active: block.isActive,
        hovered: block.isHovered,
      );
    final entryStart = block.rect.left;
    for (final cell in block.cells.skip(1)) {
      final x = entryStart + cell.startIndex * _cellExtent;
      if (x <= block.rect.left || x >= block.rect.right) {
        continue;
      }
      canvas.drawLine(
        Offset(x, block.strip.top),
        Offset(x, block.strip.bottom),
        paint,
      );
    }
  }

  void _paintBandText(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required Rect band,
    required bool alignRight,
  }) {
    if (text.isEmpty || band.width <= 0) {
      return;
    }
    final glyph = timelineGlyphPainter(
      text,
      style,
      maxWidth: math.max(0, band.width - _padding * 2),
    );
    final dx = alignRight
        ? band.right - _padding - glyph.width
        : band.left + _padding;
    canvas.save();
    glyph.paint(
      canvas,
      Offset(dx, band.top + (band.height - glyph.height) / 2),
    );
    canvas.restore();
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
      // slot, and the placeholder covers it.
      canvas.drawRect(
        block.rect,
        Paint()..color = colorScheme.surfaceContainerHighest,
      );
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
      canvas.restore();
    }
  }

  void _paintPanelPicture(Canvas canvas, ui.Image? image, Rect slot) {
    if (image == null) {
      // The pending placeholder the empty thumbnail slot used to be.
      canvas.drawRect(
        slot,
        Paint()..color = colorScheme.surfaceContainerHighest,
      );
      return;
    }
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // The picture keeps the CAMERA's ratio and is sized to the strip's
    // height, LEFT-aligned in its own slot: a wide panel leaves the right
    // of its slice empty, which is the information "this panel holds a long
    // time". Stretching it or cropping to fill would spend that width
    // saying nothing.
    final scale = math.min(
      slot.width / source.width,
      slot.height / source.height,
    );
    final drawn = Size(source.width * scale, source.height * scale);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(
        slot.left,
        slot.top + (slot.height - drawn.height) / 2,
        drawn.width,
        drawn.height,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  /// A label on the translucent strip that keeps it readable over the
  /// picture (the widget scrim, painted).
  void _paintScrimmed(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required double maxWidth,
    required Offset anchor,
    required bool alignRight,
    required bool alignBottom,
  }) {
    if (text.isEmpty || maxWidth <= 0) {
      return;
    }
    const scrimPadding = EdgeInsets.symmetric(horizontal: 3, vertical: 1);
    final glyph = timelineGlyphPainter(
      text,
      style,
      maxWidth: math.max(0, maxWidth - scrimPadding.horizontal),
    );
    final width = glyph.width + scrimPadding.horizontal;
    final height = glyph.height + scrimPadding.vertical;
    final left = alignRight ? anchor.dx - width : anchor.dx;
    final top = alignBottom ? anchor.dy - height : anchor.dy;
    final scrim = Rect.fromLTWH(left, top, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scrim, const Radius.circular(3)),
      Paint()..color = colorScheme.surface.withValues(alpha: 0.65),
    );
    glyph.paint(
      canvas,
      Offset(scrim.left + scrimPadding.left, scrim.top + scrimPadding.top),
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
