import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/waveform_painter.dart';
import '../../models/media_asset.dart' show MediaAssetKind, mediaAssetKindForPath;
import '../media/media_asset_drop_target.dart';
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import 'dialogue_fit_text.dart';
import 'timeline_cell_style.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_span_layout.dart';
import 'axis_turn.dart';
import '../repaint_props.dart';

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
    if (!frameRangesOverlap(
      block.startIndex,
      block.endIndexExclusive,
      frameStartIndex,
      frameEndIndexExclusive,
    )) {
      continue;
    }
    final frame = layer.frameById(block.frameId);
    final dialogue = frame?.name;
    final seName = frame?.seName;
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
///
/// [leadInAtStart]: how far into its sound the block at frame 0 already is
/// — the row spills in from an earlier cut (F-113). That block's strip is
/// drawn from there, where the storyboard and playback place the sound.
List<Widget> timelineRowAudioOverlays({
  required Layer layer,
  required int frameStartIndex,
  int frameEndIndexExclusive = 1 << 30,
  required Axis axis,
  required ProjectFrameRate frameRate,
  required AudioPeaks? Function(String filePath) audioPeaksFor,
  required Color color,
  int leadInAtStart = 0,
  String keyPrefix = 'timeline',
}) {
  final overlays = <Widget>[];
  for (final span in seAudioSpans(layer, leadInAtStart: leadInAtStart)) {
    // Windowed like every sibling builder: the open-ended SE display
    // clone carries every downstream sound now, and an off-window
    // waveform strip is layout weight nobody can see.
    if (!frameRangesOverlap(
      span.startFrame,
      span.startFrame + span.lengthFrames,
      frameStartIndex,
      frameEndIndexExclusive,
    )) {
      continue;
    }
    final peaks = audioPeaksFor(span.clip.filePath);
    if (peaks == null) {
      continue;
    }
    // The offset trim — and a spill-in's lead — skip into the file, so the
    // audible tail shrinks by the same amount (a fully skipped-past file
    // falls silent).
    final audibleFrames = math.min(
      span.lengthFrames,
      peaks.durationFrames(frameRate) - span.leadingFrames,
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
            leadingFrames: span.leadingFrames,
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

/// Red warning lines for takes that CLIPPED (REC1-D), tooltip-explained.
/// Callers mount these only while the clipping notice is enabled — the
/// quiet default stays quiet (user decision: an animator who does not care
/// must not see red marks all day).
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
  final overlays = <Widget>[];
  for (final span in seAudioSpans(layer)) {
    if (!span.clip.clipped) {
      continue;
    }
    final blockEnd = span.startFrame + span.lengthFrames;
    if (!frameRangesOverlap(
      span.startFrame,
      blockEnd,
      frameStartIndex,
      frameEndIndexExclusive,
    )) {
      continue;
    }
    overlays.add(
      timelineBlockWarningBar(
        blockStart: span.startFrame,
        blockEndExclusive: blockEnd,
        crossAxisExtent: crossAxisExtent,
        axis: axis,
        tooltip: tooltip,
        color: color,
        markerKey: ValueKey<String>(
          '$keyPrefix-clip-marker-${layer.id}-b${span.startFrame}',
        ),
      ),
    );
  }
  return overlays;
}

/// How thick a block's warning line is, across the row.
const double timelineBlockWarningBarThickness = 2;

/// ONE block-warning unit — the red mark + hover tooltip the SE clipped-take
/// marker introduced (REC1-D). Shared (extracted, never copied — the
/// unification absolute rule) with the D26 crossing-fade marker: a block
/// warning is one thing, whoever warns.
///
/// 🚨I-43 (유저 답 2026-09-23, 「(나) 윗변 줄」): a red line along the block's
/// NEAR long edge, end to end — the timeline's top, the X-sheet's left.
/// ↩️It was an 11px red triangle in the block's top-right corner, which is
/// where the end edge's own triangle sits now (and, on the X-sheet, the start
/// edge's): two marks in one corner.
Widget timelineBlockWarningBar({
  required int blockStart,
  required int blockEndExclusive,
  required double crossAxisExtent,
  required Axis axis,
  required String tooltip,
  required Color color,
  required Key markerKey,
}) {
  return TimelineFrameSpan(
    placement: TimelineFrameSpanPlacement(
      startIndex: blockStart,
      endIndexExclusive: blockEndExclusive,
      crossExtent: timelineBlockWarningBarThickness,
    ),
    child: KeyedSubtree(
      key: markerKey,
      child: Tooltip(
        message: tooltip,
        child: CustomPaint(
          painter: _WarningBarPainter(
            color: color,
            axis: axis,
            frameCount: blockEndExclusive - blockStart,
            crossAxisExtent: crossAxisExtent,
          ),
        ),
      ),
    ),
  );
}

class _WarningBarPainter extends CustomPainter with RepaintOnProps {
  const _WarningBarPainter({
    required this.color,
    required this.axis,
    required this.frameCount,
    required this.crossAxisExtent,
  });

  final Color color;
  final Axis axis;

  /// The block's length in frames: the line spans exactly the block, so its
  /// own extent over this is the live cell — what the block's corner reads.
  final int frameCount;
  final double crossAxisExtent;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = axis == Axis.horizontal;
    final along = extentAlong(axis, size);
    final across = extentAcross(axis, size);
    final corner = frameCount <= 0
        ? Radius.zero
        : timelineBlockCornerRadiusAt(
            cellExtent: along / frameCount,
            crossExtent: crossAxisExtent,
          );
    // The line follows the paper's own rounding at both ends: the block's
    // corners, a full corner deep across, clip it.
    final depth = math.max(corner.x, across);
    final paper = horizontal
        ? RRect.fromLTRBAndCorners(
            0,
            0,
            size.width,
            depth,
            topLeft: corner,
            topRight: corner,
          )
        : RRect.fromLTRBAndCorners(
            0,
            0,
            depth,
            size.height,
            topLeft: corner,
            bottomLeft: corner,
          );
    canvas
      ..save()
      ..clipRRect(paper)
      ..drawRect(Offset.zero & size, Paint()..color = color)
      ..restore();
  }

  @override
  Object get props => (color, axis, frameCount, crossAxisExtent);
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
    if (!frameRangesOverlap(
      block.startIndex,
      block.endIndexExclusive,
      frameStartIndex,
      frameEndIndexExclusive,
    )) {
      continue;
    }
    targets.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: block.startIndex,
          endIndexExclusive: block.endIndexExclusive,
        ),
        // The shared entrance, lit by its own frame (「블록이 외곽선으로
        // 켜진다」) — and a SOUND only: an SE row holds sounds, so a picture
        // let go on a block is a no. The chip says so, and nothing links.
        child: MediaAssetDropTarget(
          key: ValueKey<String>(
            '$keyPrefix-se-asset-drop-${layer.id}-${block.startIndex}',
          ),
          accepts: (data, _) =>
              mediaAssetKindForPath(data.path) == MediaAssetKind.audio,
          onDrop: (data, _) => onAssetDropped(block.startIndex, data.path),
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
/// start boundary (ink fill, paper-light writing) and the dialogue fitted
/// over the rest of the span — no duration bar. Shared by the timeline rows,
/// the X-sheet columns and the storyboard's synced SE track; paper comes from
/// the cells underneath (or from [SePaperSpan] where there are none).
///
/// 🚨I-43 (유저 2026-09-23): 「se는 왜 제안에서 엣지가 빨간색 남아있지? 그부분만
/// 혹시모르니 잘 통일해주고」. v3 also closed the block's end with a short red
/// line, perpendicular to the flow and hugging the end edge — exactly where
/// every block's edge used to stand, so beside the new corner triangles it
/// read as an SE block keeping a red EDGE. ⇒ The block views close an SE
/// block the way they close every block. The timesheet keeps its red bars:
/// that is the paper's notation, drawn by the sheet, not by this widget.
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
        // ↩️Narrow spans USED to DROP the name box instead of overflowing
        // it (the storyboard's zoomed-out blocks can be slimmer than the
        // box — same rule as narrow cut blocks dropping their thumbnail
        // slot).
        //
        // 🚨★★★F-93 (유저 2026-09-16): 「이름 상자를 버리는게아니야.
        // 유지한채로 가로 길이만 작게하란거야」 — the chip STAYS and narrows,
        // the way the dialogue glyphs beside it narrow rather than vanish
        // ([dialogueGlyphCondensation]). ⛔The half-span ceiling is not a new
        // number: the old threshold `>= seNameBoxExtent * 2` already said the
        // box may never take more than half the span, and that stands. The
        // two meet at 32 — `32 / 2 == seNameBoxExtent` — so the chip narrows
        // continuously instead of stepping.
        final mainExtent = axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final nameExtent = mainExtent >= seNameBoxExtent * 2
            ? seNameBoxExtent
            : mainExtent / 2;
        return Flex(
          direction: axis,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (seName.isNotEmpty)
              _SeNameBox(axis: axis, name: seName, extent: nameExtent),
            Expanded(
              child: DialogueFitText(
                text: dialogue,
                axis: axis,
                color: timelineDrawingInkColor,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SeNameBox extends StatelessWidget {
  const _SeNameBox({
    required this.axis,
    required this.name,
    required this.extent,
  });

  final Axis axis;
  final String name;

  /// How far the chip runs ALONG the block: [seNameBoxExtent] where the span
  /// can afford it, half the span where it cannot (F-93). ⛔Never the whole
  /// span — the dialogue keeps the rest.
  final double extent;

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
    // R10 R6: the vertical arm was its own glyph stack, so an SE name with
    // a long vowel or a bracket — `ドアー`, `[SE]` — kept those glyphs lying
    // the wrong way while the timesheet beside it rotated them. It reads
    // the one shared table now.
    //
    // 유저 2026-08-24 (F-27): 「se블록의 이름이 세로쓰기세로표기 인거같은데,
    // 가로쓰기 세로표기가 되도록. x시트는 그대로 냅둠」 — the two readings
    // the user named on 2026-08-08 ([VerticalLatinForm]): the SCREEN block
    // stands its Latin up, and the PRINT timesheet keeps the Japanese
    // typesetting default. The X-sheet arm below is the `Text` branch, so
    // it is untouched by construction rather than by an exception.
    final writing = axis == Axis.horizontal
        ? VerticalWritingText(
            text: name,
            style: style,
            lineHeight: 1.05,
            latinForm: VerticalLatinForm.upright,
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
    return alongBox(axis, extent, child: box);
  }
}

/// The paper frame block for hosts without paper cells underneath (the
/// storyboard's SE track): near-white fill, hairline outline, rounded ends
/// and the frame grid's own lines across it — visually the drawing rows'
/// block, painted as one span.
class SePaperSpan extends StatelessWidget {
  const SePaperSpan({
    super.key,
    required this.axis,
    required this.frameCellExtent,
    required this.startFrame,
    this.paper = timelineDrawingHeldColor,
  });

  final Axis axis;
  final double frameCellExtent;

  /// The frame the span starts on, on its host's frame axis. The grid thins
  /// and weights a line by the FRAME its boundary starts, so a span that did
  /// not know where it stands would draw a grid of its own.
  final int startFrame;

  /// The block's own colour — its layer's mark (⑲). Defaulted, so a host
  /// with no layer in hand still gets the paper.
  final Color paper;

  @override
  Widget build(BuildContext context) {
    final law = TimelineGridLaw.maybeOf(context);
    return CustomPaint(
      painter: _SePaperPainter(
        axis: axis,
        frameCellExtent: frameCellExtent,
        startFrame: startFrame,
        paper: paper,
        ground: law?.ground,
        framesPerSecond: law?.framesPerSecond ?? 0,
        colorScheme: Theme.of(context).colorScheme,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SePaperPainter extends CustomPainter with RepaintOnProps {
  _SePaperPainter({
    required this.axis,
    required this.frameCellExtent,
    required this.startFrame,
    required this.paper,
    required this.ground,
    required this.framesPerSecond,
    required this.colorScheme,
  });

  final Axis axis;
  final double frameCellExtent;
  final int startFrame;
  final Color paper;
  final Color? ground;
  final int framesPerSecond;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    // THE block corner (F-79's one function) — this span is "visually the
    // drawing rows' block", and it rounded by a 4px of its own since the
    // first SE paper (07-09), so it never matched the blocks it mirrors.
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      timelineBlockCornerRadiusAt(
        cellExtent: frameCellExtent,
        crossExtent: extentAcross(axis, size),
      ),
    );
    canvas.drawRRect(rrect, Paint()..color = paper);

    canvas.save();
    canvas.clipRRect(rrect);
    final mainExtent = extentAlong(axis, size);
    final crossExtent = extentAcross(axis, size);
    if (frameCellExtent > 0) {
      // 🚨F-92 (유저 2026-09-12): 「스토리보드패널의 프레임셀 그리드,
      // 타임라인패널이랑 다름 … 줌 축소해도 1f마다 블록에 세로선이있음.
      // 타임라인이랑 다른 법 절대로 두지말고 관련 로직 싹 다 통일」. This drew
      // a line at EVERY frame in a faint ink of its own. Which boundaries show
      // at this zoom, where they sit and in what ink over this paper are the
      // timeline cells' answers now: the one grid law
      // ([timelineFrameBoundaryLineInk]) and the ground rule the cells
      // painter resolves it on.
      final seen = timelineGridGroundOver(under: ground, painted: paper);
      final frames = (mainExtent / frameCellExtent).round();
      for (var offset = 1; offset < frames; offset += 1) {
        final ink = timelineFrameBoundaryLineInk(
          frameIndex: startFrame + offset,
          frameCellExtent: frameCellExtent,
          framesPerSecond: framesPerSecond,
          colorScheme: colorScheme,
        );
        if (ink == null) {
          continue;
        }
        final along = timelineFrameBoundaryLinePosition(
          offset,
          frameCellExtent,
        );
        canvas.drawLine(
          offsetAlong(axis, along: along, across: 0),
          offsetAlong(axis, along: along, across: crossExtent),
          Paint()
            ..color = seen == null
                ? ink.color
                : timelineGridLineInkOnGround(ink, seen)
            ..strokeWidth = ink.strokeWidth,
        );
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
  Object get props => (
    axis,
    frameCellExtent,
    startFrame,
    // A mark change repaints the block (⑲) — without this the row would
    // keep the colour it was first painted with.
    paper,
    ground,
    framesPerSecond,
    colorScheme,
  );
}
