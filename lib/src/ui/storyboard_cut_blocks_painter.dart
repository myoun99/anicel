import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../models/cut.dart';
import '../models/cut_id.dart';
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
    required this.thumbnail,
  });

  final CutId cutId;

  /// The block's box in ROW-local coordinates.
  final Rect rect;

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

  /// The picture the block draws, or null while the render is pending (the
  /// block shows its placeholder then). Owned by the thumbnail store.
  final ui.Image? thumbnail;
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
    required this.geometry,
    required this.crossAxisExtent,
    required this.minBlockWidth,
    required this.activeCutId,
    required this.selectedCutIds,
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
           ?selectedCutIds,
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

  /// The LIVE frame-axis geometry: a zoom step repaints instead of
  /// rebuilding the row that built this.
  final TimelineFrameGeometryHandle geometry;

  final double crossAxisExtent;

  /// Blocks never draw narrower than this, however short the cut — the
  /// `TimelineScale` rule the widget blocks were sized by.
  final double minBlockWidth;

  final CutId? activeCutId;
  final ValueListenable<List<CutId>?>? selectedCutIds;
  final ValueListenable<CutId?> hoveredCutId;

  final ColorScheme colorScheme;
  final Brightness brightness;
  final TextStyle baseTextStyle;
  final bool showSeconds;
  final int countingBase;

  /// Painted, never disposed here: the thumbnail store owns the image.
  /// Asked ONLY for blocks inside the window, which is the point.
  final ui.Image? Function(Cut cut)? thumbnailFor;
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

  /// Every block this row would draw, in track order — THE probe surface.
  ///
  /// Off-window cuts are absent by construction, which is also what keeps
  /// [thumbnailFor] from being asked for pictures nobody can see.
  List<StoryboardCutBlockVisual> blocks() {
    final window = visibleFrameWindow();
    final selected = selectedCutIds?.value;
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
      visuals.add(
        StoryboardCutBlockVisual(
          cutId: entry.cutId,
          rect: Rect.fromLTWH(left, 0, width, crossAxisExtent),
          isActive: entry.cutId == activeCutId,
          isRangeSelected: selected?.contains(entry.cutId) ?? false,
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
          // request every cut's picture on every build.
          thumbnail: showThumbnails ? thumbnailFor?.call(entry.cut) : null,
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

  TextStyle get _layerNameStyle =>
      _labelStyle.copyWith(color: colorScheme.onPrimaryContainer);

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
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = storyboardCutBlockBackgroundColor(
          colorScheme,
          active: block.isActive,
          hovered: block.isHovered,
          rangeSelected: block.isRangeSelected,
        ),
    );

    final inner = block.rect.deflate(_padding);
    if (showThumbnails && inner.width > 0 && inner.height > 0) {
      canvas.save();
      canvas.clipRRect(rrect);
      _paintThumbnail(canvas, block, inner);
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
    if (block.hasStoryboardLayer) {
      _paintLayerChip(canvas, block, inner);
    } else {
      _paintScrimmed(
        canvas,
        text: block.layerLabel,
        style: _emptyLayerStyle,
        maxWidth: math.max(0, inner.width * 0.6),
        anchor: inner.bottomLeft,
        alignRight: false,
        alignBottom: true,
      );
    }
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
  }

  void _paintThumbnail(
    Canvas canvas,
    StoryboardCutBlockVisual block,
    Rect inner,
  ) {
    final image = block.thumbnail;
    if (image == null) {
      // The pending placeholder the empty thumbnail slot used to be.
      canvas.drawRect(
        block.rect,
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
    // BoxFit.contain, centred — the picture keeps the camera's ratio.
    final scale = math.min(
      block.rect.width / source.width,
      block.rect.height / source.height,
    );
    final drawn = Size(source.width * scale, source.height * scale);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(
        block.rect.left + (block.rect.width - drawn.width) / 2,
        block.rect.top + (block.rect.height - drawn.height) / 2,
        drawn.width,
        drawn.height,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  void _paintLayerChip(
    Canvas canvas,
    StoryboardCutBlockVisual block,
    Rect inner,
  ) {
    const chipPadding = EdgeInsets.symmetric(horizontal: 4);
    final maxWidth = math.max(0.0, inner.width * 0.6 - chipPadding.horizontal);
    final glyph = timelineGlyphPainter(
      block.layerLabel,
      _layerNameStyle,
      maxWidth: maxWidth,
    );
    final chip = Rect.fromLTWH(
      inner.left,
      inner.bottom - glyph.height,
      glyph.width + chipPadding.horizontal,
      glyph.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(4)),
      Paint()..color = colorScheme.primaryContainer,
    );
    glyph.paint(canvas, Offset(chip.left + chipPadding.left, chip.top));
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
