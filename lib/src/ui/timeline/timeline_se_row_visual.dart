import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../models/timeline_coverage.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/waveform_painter.dart';
import '../media/media_asset_drag_data.dart';
import '../theme/app_theme.dart';
import 'dialogue_fit_text.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_span_layout.dart';

/// SE rows reuse the drawing rows' white paper frame blocks (the cells
/// themselves paint the paper); this overlay adds the sheet's SE writing on
/// top: the speaker name in an accent box at the block start (only when
/// set) and the dialogue glyphs distributed evenly across the block, with
/// the audio waveform sandwiched between paper and text.

/// Whether rows of [kind] use the sheet-style SE rendering: cell glyphs and
/// X marks stay suppressed — the entry's writing comes from the row-level
/// span overlay instead.
bool layerKindUsesSeSheetCells(LayerKind kind) => kind == LayerKind.se;

/// The name-box + fitted-dialogue overlays for every SE block intersecting
/// the visible window; mirrors [timelineRowBlockEdgeGrips]' windowing math.
List<Widget> timelineRowSeLabelOverlays({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required Axis axis,
  String keyPrefix = 'timeline',
}) {
  final overlays = <Widget>[];
  final blocks = drawingBlocks(layer.timeline);
  for (final block in blocks) {
    if (block.endIndexExclusive <= frameStartIndex ||
        block.startIndex >= frameEndIndexExclusive) {
      continue;
    }
    String? dialogue;
    String? seName;
    for (final frame in layer.frames) {
      if (frame.id == block.frameId) {
        dialogue = frame.name;
        seName = frame.seName;
        break;
      }
    }
    overlays.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: block.startIndex,
          endIndexExclusive: block.endIndexExclusive,
        ),
        child: IgnorePointer(
          key: ValueKey<String>(
            '$keyPrefix-se-label-${layer.id}-${block.startIndex}',
          ),
          child: SeSpanVisual(
            axis: axis,
            dialogue: dialogue ?? '',
            seName: seName,
          ),
        ),
      ),
    );
  }
  return overlays;
}

/// `~` continuation marks on the CUT boundaries an SE block crosses
/// (UI-R7 #6) — this is the cut-scoped view: a block running past the cut
/// end marks the cut end ("something follows"), a block spilling in from
/// an earlier cut marks the cut start ("something precedes"; its start
/// grip stands down — the real start lives in that cut). The storyboard's
/// track-global strip shows the whole flow and carries no marks.
List<Widget> timelineRowSeContinuationMarks({
  required Layer layer,
  required int cutFrameCount,
  required bool spillsInAtStart,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  String keyPrefix = 'timeline',
}) {
  final marks = <Widget>[];
  void mark(int boundaryFrame, String suffix) {
    if (boundaryFrame < frameStartIndex ||
        boundaryFrame > frameEndIndexExclusive) {
      return;
    }
    marks.add(
      TimelineFrameSpan(
        // A fixed 14px glyph straddling the boundary — the one piece of SE
        // chrome that must NOT scale with the zoom.
        placement: TimelineFrameSpanPlacement(
          startIndex: boundaryFrame,
          mainInset: -7,
          mainExtent: 14,
        ),
        child: IgnorePointer(
          key: ValueKey<String>('$keyPrefix-se-crossing-${layer.id}-$suffix'),
          child: const Center(
            child: Text(
              '~',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: timelineDrawingInkColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final block in drawingBlocks(layer.timeline)) {
    if (spillsInAtStart && block.startIndex == 0) {
      mark(0, 'start');
    }
    if (block.startIndex < cutFrameCount &&
        block.endIndexExclusive > cutFrameCount) {
      mark(cutFrameCount, 'end');
    }
  }
  return marks;
}

/// Waveform strips for an SE row's audio, painted ABOVE the paper cells
/// and BELOW the writing overlays (list them between the two in the
/// Stack). Sounds are FRAME-LINKED (block = instance): each carrying block
/// shows the waveform from its own start, clipped to the block AND to the
/// file's length from the extracted peaks; clips whose peaks are still
/// extracting (or failed) draw nothing until the store notifies.
List<Widget> timelineRowAudioOverlays({
  required Layer layer,
  required int frameStartIndex,
  int frameEndIndexExclusive = 1 << 30,
  required Axis axis,
  required ProjectFrameRate frameRate,
  required AudioPeaks? Function(String filePath) audioPeaksFor,
  required Color color,
  String keyPrefix = 'timeline',
}) {
  final overlays = <Widget>[];
  for (final span in seAudioSpans(layer)) {
    // Windowed like every sibling builder: the open-ended SE display
    // clone carries every downstream sound now, and an off-window
    // waveform strip is layout weight nobody can see.
    if (span.startFrame + span.lengthFrames <= frameStartIndex ||
        span.startFrame >= frameEndIndexExclusive) {
      continue;
    }
    final peaks = audioPeaksFor(span.clip.filePath);
    if (peaks == null) {
      continue;
    }
    // The offset trim skips into the file, so the audible tail shrinks by
    // the same amount (a fully skipped-past file falls silent).
    final audibleFrames = math.min(
      span.lengthFrames,
      peaks.durationFrames(frameRate) - span.clip.offsetFrames,
    );
    if (audibleFrames <= 0) {
      continue;
    }
    overlays.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: span.startFrame,
          endIndexExclusive: span.startFrame + audibleFrames,
        ),
        child: KeyedSubtree(
          key: ValueKey<String>(
            '$keyPrefix-audio-clip-${layer.id}-${span.clipIndex}'
            '-b${span.startFrame}',
          ),
          child: _AudioClipStrip(
            peaks: peaks,
            frameRate: frameRate,
            // Frames, not pixels: the strip reads its own box to learn what
            // a frame is worth, so a zoom step repaints it without a rebuild.
            audibleFrames: audibleFrames,
            axis: axis,
            color: color,
            leadingFrames: span.clip.offsetFrames,
            gain: span.clip.gain,
            fadeInFrames: span.clip.fadeInFrames,
            fadeOutFrames: span.clip.fadeOutFrames,
          ),
        ),
      ),
    );
  }
  return overlays;
}

/// Red corner markers for takes that CLIPPED (REC1-D): the carrying
/// block's trailing-top corner, tooltip-explained. Callers mount these
/// only while the clipping notice is enabled — the quiet default stays
/// quiet (user decision: an animator who does not care must not see red
/// corners all day).
List<Widget> timelineRowClipMarkerOverlays({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required double crossAxisExtent,
  required Axis axis,
  required String tooltip,
  required Color color,
  String keyPrefix = 'timeline',
}) {
  const markerSize = 11.0;
  final overlays = <Widget>[];
  for (final span in seAudioSpans(layer)) {
    if (!span.clip.clipped) {
      continue;
    }
    final blockEnd = span.startFrame + span.lengthFrames;
    if (blockEnd <= frameStartIndex ||
        span.startFrame >= frameEndIndexExclusive) {
      continue;
    }
    overlays.add(
      TimelineFrameSpan(
        // The block's top-right corner — beside, never over, the
        // bottom-right duration label (R26 #7). Transposed, it rides the
        // block's top edge on the column's trailing side.
        placement: axis == Axis.horizontal
            ? TimelineFrameSpanPlacement(
                startIndex: blockEnd,
                anchorAtTrailingEdge: true,
                mainExtent: markerSize,
                crossExtent: markerSize,
              )
            : TimelineFrameSpanPlacement(
                startIndex: span.startFrame,
                mainExtent: markerSize,
                crossInset: crossAxisExtent - markerSize,
                crossExtent: markerSize,
              ),
        child: KeyedSubtree(
          key: ValueKey<String>(
            '$keyPrefix-clip-marker-${layer.id}-b${span.startFrame}',
          ),
          child: Tooltip(
            message: tooltip,
            child: CustomPaint(painter: _ClipCornerPainter(color)),
          ),
        ),
      ),
    );
  }
  return overlays;
}

class _ClipCornerPainter extends CustomPainter {
  const _ClipCornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ClipCornerPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Media-browser drop targets over an SE row's blocks: dropping an asset
/// onto a block links the sound to the block's frame (footsteps reuse —
/// the browser's drag-out counterpart to importing at the playhead).
/// DragTargets only participate while a matching drag is in flight, so
/// taps and cell gestures keep falling through; the hovered block shows an
/// accent outline.
List<Widget> timelineRowSeAssetDropTargets({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required void Function(int blockStartFrame, String path) onAssetDropped,
  String keyPrefix = 'timeline',
}) {
  final targets = <Widget>[];
  for (final block in drawingBlocks(layer.timeline)) {
    if (block.endIndexExclusive <= frameStartIndex ||
        block.startIndex >= frameEndIndexExclusive) {
      continue;
    }
    targets.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: block.startIndex,
          endIndexExclusive: block.endIndexExclusive,
        ),
        child: DragTarget<MediaAssetDragData>(
          key: ValueKey<String>(
            '$keyPrefix-se-asset-drop-${layer.id}-${block.startIndex}',
          ),
          onAcceptWithDetails: (details) =>
              onAssetDropped(block.startIndex, details.data.path),
          builder: (context, candidates, _) => candidates.isEmpty
              ? const SizedBox.expand()
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    border: Border.all(color: AppColors.accent, width: 2),
                    color: AppColors.accent.withValues(alpha: 0.12),
                  ),
                ),
        ),
      ),
    );
  }
  return targets;
}

class _AudioClipStrip extends StatelessWidget {
  const _AudioClipStrip({
    required this.peaks,
    required this.frameRate,
    required this.audibleFrames,
    required this.axis,
    required this.color,
    this.leadingFrames = 0,
    this.gain = 1.0,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
  });

  final AudioPeaks peaks;
  final ProjectFrameRate frameRate;

  /// How many FRAMES this strip's box spans; the pixels per frame follow
  /// from the box, so the zoom never reaches this widget as a new value.
  final int audibleFrames;
  final Axis axis;
  final Color color;
  final int leadingFrames;
  final double gain;
  final int fadeInFrames;
  final int fadeOutFrames;

  @override
  Widget build(BuildContext context) {
    final waveform = ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final main = axis == Axis.horizontal
              ? constraints.maxWidth
              : constraints.maxHeight;
          return CustomPaint(
            painter: WaveformPainter(
              peaks: peaks,
              frameRate: frameRate,
              pixelsPerFrame: audibleFrames <= 0 ? 0 : main / audibleFrames,
              color: color,
              axis: axis,
              leadingFrames: leadingFrames,
              gain: gain,
              fadeInFrames: fadeInFrames,
              fadeOutFrames: fadeOutFrames,
            ),
          );
        },
      ),
    );
    // R10 R3: the strip is a pure painter again. Removing a sound lived on
    // its context menu and is waiting on the audio button; taps and double
    // taps always fell through to the cells underneath, and now everything
    // does.
    return IgnorePointer(child: waveform);
  }
}

/// Main-axis extent of the SE name box (the inverted chip hugging a
/// block's start boundary).
const double seNameBoxExtent = 16;

/// The sheet's SE-entry writing, the real Toei way (R4, user-approved
/// mockup v3): a compact INVERTED name chip flush against the block's
/// start boundary (ink fill, paper-light writing), the dialogue fitted
/// over the rest of the span and a short red underline closing the
/// block's end — no duration bar. Shared by the timeline rows, the
/// X-sheet columns and the storyboard's synced SE track; paper comes from
/// the cells underneath (or from [SePaperSpan] where there are none).
class SeSpanVisual extends StatelessWidget {
  const SeSpanVisual({
    super.key,
    required this.axis,
    required this.dialogue,
    this.seName,
  });

  final Axis axis;
  final String dialogue;
  final String? seName;

  @override
  Widget build(BuildContext context) {
    final seName = this.seName ?? '';
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow spans drop the name box instead of overflowing it (the
        // storyboard's zoomed-out blocks can be slimmer than the box —
        // same rule as narrow cut blocks dropping their thumbnail slot).
        final mainExtent = axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final showName = seName.isNotEmpty && mainExtent >= seNameBoxExtent * 2;
        return Stack(
          children: [
            Flex(
              direction: axis,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showName) _SeNameBox(axis: axis, name: seName),
                Expanded(
                  child: DialogueFitText(
                    text: dialogue,
                    axis: axis,
                    color: timelineDrawingInkColor,
                  ),
                ),
              ],
            ),
            // The block's end closes with a short red underline (Toei
            // notation) — perpendicular to the flow, hugging the end edge.
            Positioned(
              right: axis == Axis.horizontal ? 1 : 0,
              bottom: axis == Axis.horizontal ? 0 : 1,
              top: axis == Axis.horizontal ? 0 : null,
              left: axis == Axis.horizontal ? null : 0,
              width: axis == Axis.horizontal ? 2 : null,
              height: axis == Axis.horizontal ? null : 2,
              child: IgnorePointer(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: axis == Axis.horizontal ? null : 0.6,
                    heightFactor: axis == Axis.horizontal ? 0.6 : null,
                    child: const ColoredBox(color: AppColors.danger),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SeNameBox extends StatelessWidget {
  const _SeNameBox({required this.axis, required this.name});

  final Axis axis;
  final String name;

  @override
  Widget build(BuildContext context) {
    // Soft accent chip (R6-② tint over R5-⑦'s full accent): reads as a
    // marker ON the block start instead of an extra cell pushing it, with
    // dark ink writing carrying the contrast. Writing follows the strip:
    // upright glyph stack on the row strip, horizontal on the X-sheet
    // band. Same tint on the printed sheet.
    const style = TextStyle(
      color: timelineDrawingInkColor,
      fontSize: 9,
      fontWeight: FontWeight.bold,
      height: 1.05,
    );
    final writing = axis == Axis.horizontal
        ? Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final glyph in name.characters) Text(glyph, style: style),
            ],
          )
        : Text(name, maxLines: 1, softWrap: false, style: style);
    final box = Semantics(
      label: 'SE name $name',
      // Own node even where an ancestor would merge labels (the dialog
      // preview) — tests and screen readers address the box directly.
      container: true,
      child: Container(
        // R6-②: soft accent tint (the full-strength accent read too loud);
        // dark ink writing carries the contrast — matches the sheet.
        color: AppColors.accent.withValues(alpha: 0.3),
        alignment: Alignment.center,
        // scaleDown: a LONG name shrinks to the box instead of overflowing
        // the row (the striped-error report — R4 improvement 2).
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ExcludeSemantics(child: writing),
          ),
        ),
      ),
    );
    return axis == Axis.horizontal
        ? SizedBox(width: seNameBoxExtent, child: box)
        : SizedBox(height: seNameBoxExtent, child: box);
  }
}

/// The paper frame block for hosts without paper cells underneath (the
/// storyboard's SE track): near-white fill, hairline outline, rounded ends
/// and a cell divider every [frameCellExtent] — visually the drawing rows'
/// block, painted as one span.
class SePaperSpan extends StatelessWidget {
  const SePaperSpan({
    super.key,
    required this.axis,
    required this.frameCellExtent,
  });

  final Axis axis;
  final double frameCellExtent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SePaperPainter(axis: axis, frameCellExtent: frameCellExtent),
      child: const SizedBox.expand(),
    );
  }
}

class _SePaperPainter extends CustomPainter {
  _SePaperPainter({required this.axis, required this.frameCellExtent});

  final Axis axis;
  final double frameCellExtent;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(rrect, Paint()..color = timelineDrawingHeldColor);

    canvas.save();
    canvas.clipRRect(rrect);
    final dividerPaint = Paint()
      ..color = timelineDrawingInkColor.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    if (frameCellExtent > 0) {
      for (
        var x = frameCellExtent;
        x < mainExtent - 0.5;
        x += frameCellExtent
      ) {
        final (from, to) = axis == Axis.horizontal
            ? (Offset(x, 0), Offset(x, size.height))
            : (Offset(0, x), Offset(size.width, x));
        canvas.drawLine(from, to, dividerPaint);
      }
    }
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = timelineDrawingStartBorderColor,
    );
  }

  @override
  bool shouldRepaint(_SePaperPainter oldDelegate) {
    return axis != oldDelegate.axis ||
        frameCellExtent != oldDelegate.frameCellExtent;
  }
}
