import '../widgets/app_tooltip.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../../models/se_audio_spans.dart';
import '../../models/se_dialogue_spacing.dart';
import '../../models/se_line_type.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import '../../models/track_se_window.dart' show seSoundRunsPast;
import '../../services/audio/audio_peaks_extractor.dart';
import '../audio/sound_cannot_play.dart';
import '../audio/waveform_painter.dart';
import '../../models/media_asset.dart' show MediaAssetKind, mediaAssetKindForPath;
import '../media/media_asset_drop_target.dart';
import '../text/dialogue_fit_layout.dart'
    show dialogueGlyphSlots, dialogueGlyphsShownIn;
import '../text/dialogue_fit_paint.dart' show dialogueLongestGlyph;
import '../text/app_strings.dart' show AppText;
import '../text/vertical_writing_text.dart';
import '../theme/app_theme.dart';
import '../theme/text_on_ground.dart' show textOnColor;
import 'dialogue_fit_text.dart';
import 'se_crossing_mark_painter.dart';
import 'timeline_block_look.dart' show timelineRowLookOf;
import 'timeline_block_word.dart';
import 'timeline_cell_style.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_coordinate_policy.dart'
    show timelineFrameAt, timelineFrameEdge;
import 'timeline_frame_span_layout.dart';
import 'timeline_grid_metrics.dart' show timelineFirstOnStride;
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
///
/// [spillInLeadFrames]: how far into its block the cut's frame 0 already
/// is — a sound spilling in from an earlier cut. That block is laid out
/// from where it really starts and seen from frame 0 on
/// ([SeSpanVisual.shownFrom]), so its words stand where the track's own
/// row has them (F-358). Each chip reads the frames free before its block
/// on the row, the room it may stand in outside it ([seFramesFreeBefore]).
///
/// [cutId] is the cut whose delivery each line wears beside its name
/// ([SeLineTypes.inCut]) — the cut a cut's view shows; null for a strip of
/// the whole track, where each line wears the one its head's cut has.
List<Widget> timelineRowSeLabelOverlays({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required Axis axis,
  int? spillInLeadFrames,
  CutId? cutId,
  String keyPrefix = 'timeline',
}) {
  final overlays = <Widget>[];
  final blocks = drawingBlocks(layer.timeline);
  for (final (index, block) in blocks.indexed) {
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
    final lead = block.startIndex == 0 ? spillInLeadFrames ?? 0 : 0;
    overlays.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: block.startIndex - lead,
          endIndexExclusive: block.endIndexExclusive,
        ),
        child: IgnorePointer(
          key: ValueKey<String>(
            '$keyPrefix-se-label-${layer.id}-${block.startIndex}',
          ),
          child: SeSpanVisual(
            axis: axis,
            layer: layer,
            frames: block.length + lead,
            dialogue: dialogue ?? '',
            seName: seName,
            delivery: frame?.seTypes.inCut(cutId),
            spacing: frame?.seSpacing ?? SeDialogueSpacing.standard,
            shownFrom: lead,
            framesFreeBefore: seFramesFreeBefore(blocks, index),
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
///
/// The cut's end is the line it is DRAWN to — its 尺 plus the のりしろ a
/// transition asks ([drawnFrameCount], the timeline's blue line and the
/// sheet's end line). 🗣️F-358 (유저 2026-10-17): 「컷 엔드라인(OL여백이든
/// 뭐든 총합적인 엔드라인)」. ↩️It stood on the 尺, short of the margin.
///
/// Each mark straddles its boundary, centred across the row, and runs along
/// the [axis] ([paintSeCrossingMark]) — so at the cut's start only its back
/// half is the cut's (유저: 「물론 끝에만 보이게 되겟지」).
List<Widget> timelineRowSeContinuationMarks({
  required Layer layer,
  required int drawnFrameCount,
  required bool spillsInAtStart,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required Axis axis,
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
        placement: TimelineFrameSpanPlacement(
          startIndex: boundaryFrame,
          mainInset: -seCrossingMarkLength / 2,
          mainExtent: seCrossingMarkLength,
        ),
        child: IgnorePointer(
          key: ValueKey<String>('$keyPrefix-se-crossing-${layer.id}-$suffix'),
          child: CustomPaint(painter: _SeCrossingMarkPainter(axis)),
        ),
      ),
    );
  }

  if (spillsInAtStart) {
    mark(0, 'start');
  }
  if (seSoundRunsPast(layer, drawnFrameCount)) {
    mark(drawnFrameCount, 'end');
  }
  return marks;
}

/// One `~`, in the middle of the strip it stands in.
class _SeCrossingMarkPainter extends CustomPainter with RepaintOnProps {
  const _SeCrossingMarkPainter(this.axis);

  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) =>
      paintSeCrossingMark(canvas, size.center(Offset.zero), axis);

  @override
  Object get props => axis;
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
///
/// The strips are ink on the block ([timelineSeWaveformInk]), so they wear
/// its look as its words do ([timelineRowLookOf], I-129) — the timeline's
/// SE rows and the storyboard's S rows alike.
List<Widget> timelineRowAudioOverlays(
  BuildContext context, {
  required Layer layer,
  required int frameStartIndex,
  int frameEndIndexExclusive = 1 << 30,
  required Axis axis,
  required ProjectFrameRate frameRate,
  required AudioPeaks? Function(String filePath) audioPeaksFor,
  int leadInAtStart = 0,
  String keyPrefix = 'timeline',
}) {
  final color = timelineRowLookOf(
    context,
    layer,
    ink: timelineSeWaveformInk,
  ).ink;
  return [
    for (final strip in seRowAudioStrips(
      layer,
      window: (
        startIndex: frameStartIndex,
        endIndexExclusive: frameEndIndexExclusive,
      ),
      ink: (
        axis: axis,
        frameRate: frameRate,
        audioPeaksFor: audioPeaksFor,
        color: color,
      ),
      leadInAtStart: leadInAtStart,
    ))
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: strip.startFrame,
          endIndexExclusive: strip.endFrameExclusive,
        ),
        child: KeyedSubtree(
          key: ValueKey<String>('$keyPrefix-audio-clip-${strip.keyName}'),
          child: strip.strip,
        ),
      ),
  ];
}

/// The ink an SE block's waveform is drawn in on its paper.
final Color timelineSeWaveformInk = timelineDrawingInkColor.withValues(
  alpha: 0.22,
);

/// One sound's waveform strip on an SE row ([seRowAudioStrips]): the frames
/// it covers, the name it is keyed by, and the strip.
typedef SeRowAudioStrip = ({
  int startFrame,
  int endFrameExclusive,
  String keyName,
  Widget strip,
});

/// How an SE row draws its sounds ([seRowAudioStrips]): the axis it lays
/// them along, the rate its frames are counted at, each file's peaks, and
/// the ink.
typedef SeRowSoundInk = ({
  Axis axis,
  ProjectFrameRate frameRate,
  AudioPeaks? Function(String filePath) audioPeaksFor,
  Color color,
});

/// An SE row's waveform strips with the frames each covers and the name it
/// is keyed by — what [timelineRowAudioOverlays] places on a cut's cells
/// and on the storyboard's S row, the track's axis. One reading of a sound
/// for both: where it starts, how much of it is heard, and its gain drawn
/// on it. Only the sounds over [window] when one is given —
/// the whole row when none is.
///
/// ↩️The storyboard's S row read them on its own, and drew no gain and no
/// fade (I-89 ① ⓕ, 2026-10-20).
List<SeRowAudioStrip> seRowAudioStrips(
  Layer layer, {
  ({int startIndex, int endIndexExclusive})? window,
  required SeRowSoundInk ink,
  int leadInAtStart = 0,
}) {
  final (:axis, :frameRate, :audioPeaksFor, :color) = ink;
  final strips = <SeRowAudioStrip>[];
  for (final span in seAudioSpans(layer, leadInAtStart: leadInAtStart)) {
    // Windowed like every sibling builder: the open-ended SE display
    // clone carries every downstream sound now, and an off-window
    // waveform strip is layout weight nobody can see.
    if (window != null &&
        !frameRangesOverlap(
          span.startFrame,
          span.startFrame + span.lengthFrames,
          window.startIndex,
          window.endIndexExclusive,
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
    strips.add((
      startFrame: span.startFrame,
      endFrameExclusive: span.startFrame + audibleFrames,
      keyName: '${layer.id}-${span.clipIndex}-b${span.startFrame}',
      strip: _AudioClipStrip(
        peaks: peaks,
        frameRate: frameRate,
        // Frames, not pixels: the strip reads its own box to learn what a
        // frame is worth, so a zoom step repaints it without a rebuild.
        audibleFrames: audibleFrames,
        axis: axis,
        color: color,
        leadingFrames: span.leadingFrames,
        gain: span.clip.gain,
      ),
    ));
  }
  return strips;
}

/// What an SE row warns of on its blocks: a take that CLIPPED (REC1-D) —
/// [clipped] its tooltip, null while the clipping notice is off, so the
/// quiet default stays quiet (user decision: an animator who does not care
/// must not see red marks all day) — and a sound a run plays without, by
/// [cannotPlay]'s answer, always (playback-says-the-sound-it-cannot-play,
/// 유저 2026-10-17: 「재생하지 않을 때도 늘」).
typedef SeSoundWarnings = ({
  String? clipped,
  SoundCannotPlay? Function(String filePath)? cannotPlay,
});

/// The tooltip [span]'s block warns with — a line per warning — or null
/// where it warns of nothing ([SeSoundWarnings]).
String? seSoundWarningsOf(SeAudioSpan span, SeSoundWarnings warnings) {
  final why = warnings.cannotPlay?.call(span.clip.filePath);
  final clipped = span.clip.clipped ? warnings.clipped : null;
  final lines = [
    if (why != null) AppText.strings.soundCannotPlay(why),
    ?clipped,
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// Red warning lines on an SE row's blocks, tooltip-explained — one per
/// block that has anything to warn of ([seSoundWarningsOf]).
List<Widget> timelineRowSoundWarningOverlays({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required double crossAxisExtent,
  required Axis axis,
  required SeSoundWarnings warnings,
  required Color color,
  String keyPrefix = 'timeline',
}) {
  final overlays = <Widget>[];
  for (final span in seAudioSpans(layer)) {
    final tooltip = seSoundWarningsOf(span, warnings);
    if (tooltip == null) {
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
          '$keyPrefix-block-warning-${layer.id}-b${span.startFrame}',
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
///
/// 🗣️F-495 (유저 2026-10-28: 「이유가 뭔지 모르겠으니 블록에 호버하면 툴팁
/// 띄우도록」): the hover that says why is the WHOLE BLOCK's — the line only
/// shows it. ↩️The tooltip was the line's own box, 2px across, which no
/// pointer finds. It summons on the hover alone: a long press on a block is
/// the block's drag, and a tooltip's recognizer would take that press from
/// it in the arena (the panel tabs' tooltip, for the same reason).
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
    ),
    child: KeyedSubtree(
      key: markerKey,
      child: AppTooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.manual,
        child: Align(
          alignment: Alignment.topLeft,
          child: sizedAlong(
            axis,
            along: double.infinity,
            across: timelineBlockWarningBarThickness,
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
    // The line follows the paper's own rounding at both ends: the block's
    // PAPER clips it (I-44: the block stops short of the row seam, and its
    // corner is measured on what it covers). ↩️It built the two near corners
    // again in a box of its own, a corner deep; the paper's whole shape says
    // the same on this line and cannot say otherwise (F-270).
    canvas
      ..save()
      ..clipRRect(
        timelineBlockPaperShapeOver(
          axis: axis,
          along: extentAlong(axis, size),
          rowExtent: crossAxisExtent,
          frames: frameCount,
        ),
      )
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

  @override
  Widget build(BuildContext context) {
    final waveform = ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final main = extentAlong(axis, constraints.biggest);
          return CustomPaint(
            painter: WaveformPainter(
              peaks: peaks,
              frameRate: frameRate,
              pixelsPerFrame: audibleFrames <= 0 ? 0 : main / audibleFrames,
              color: color,
              axis: axis,
              leadingFrames: leadingFrames,
              gain: gain,
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

/// Where an SE span's name chip stands along a block [mainExtent] long,
/// whose dialogue's longest glyph runs [longestGlyph] at its natural size
/// ([dialogueLongestGlyph]) in a room [glyphRoom] long
/// ([dialogueGlyphSlots]), with [roomBefore] free on its row before it
/// ([seFramesFreeBefore]): [chip] long, and [outside] the block — just
/// before its start — when that room holds it whole; over the block's
/// head, on its words, when it does not.
///
/// 🗣️F-358 (유저 2026-10-19): 「블록안에 이름있어서 대사가 1코마부터
/// 시작하게 하고싶은데 방해되. 그래서 업계에서 실제로 하는데로 대사영역
/// 바로앞. 즉 블록 앞부분 왼쪽에 이름두자. 블록 밖으로 나가게되는거지. s행
/// 해당블록이 타임라인에서 맨 처음이거나해서 공간없으면 지금처럼 블록안에
/// 넣는데 대사랑 완전겹치는거 감수」. The words run the block edge to edge
/// from its first frame, named or not, and the name keeps out of their way.
/// ↩️The chip took the block's head and the words began where it ended — a
/// different frame at each zoom — and F-358-Q1 (10-18) made the head one
/// frame, so the words began on the second.
///
/// 🗣️F-224 (유저 2026-09-29): 「줌에 맞춰서 se블록의 대사 좌우 줄일때,
/// 대사는 줄어들어가는데 이름칸은 줄어들기 시작하는게 늦어서 15%정도에서
/// 이름칸만 100%랑 거의 비슷한 크기인데 대사만 줄어들고있음. 대사랑 이름칸이랑
/// 동일하게 줄어들기시작하도록」: the chip narrows by the very ratio the
/// words do, from the zoom their longest glyph gets longer than its room
/// (F-496 ③). ↩️From the zoom the block got shorter than the whole line,
/// when the line spread over the block; and before that the chip kept its
/// 16 until the block was under 32 and then took half of it — a ceiling
/// read off an old threshold, not anyone's rule — while the dialogue beside
/// it had been narrowing since the block got shorter than the two of them.
({double chip, bool outside}) seNameChipPlace(
  double mainExtent, {
  required double longestGlyph,
  required double glyphRoom,
  required double roomBefore,
}) {
  final narrowed = longestGlyph <= glyphRoom ? 1.0 : glyphRoom / longestGlyph;
  final chip = seNameBoxExtent * narrowed;
  return roomBefore >= chip
      ? (chip: chip, outside: true)
      : (chip: math.min(chip, mainExtent), outside: false);
}

/// How many frames lie free on a row before [blocks]' block at [index]:
/// back to the end of the block before it, or to the row's frame 0 — the
/// room its name chip may stand in, outside it ([seNameChipPlace]).
int seFramesFreeBefore(List<TimelineDrawingBlock> blocks, int index) =>
    blocks[index].startIndex -
    (index == 0 ? 0 : blocks[index - 1].endIndexExclusive);

/// The sheet's SE-entry writing, the real Toei way (R4, user-approved
/// mockup v3): a compact name chip at the block's start boundary and the
/// dialogue fitted over the span — no duration bar. Where the chip stands
/// is [seNameChipPlace]'s to say: just before the block, or over its head.
/// Shared by the timeline rows, the X-sheet columns and the storyboard's
/// synced SE track; paper comes from the cells underneath (or from
/// [SePaperSpan] where there are none).
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
    required this.layer,
    required this.frames,
    required this.dialogue,
    this.seName,
    this.delivery,
    this.spacing = SeDialogueSpacing.standard,
    this.shownFrom = 0,
    this.framesFreeBefore = 0,
  });

  final Axis axis;

  /// The row the block stands on: the words on the block wear its look, as
  /// a cel name on a drawing block does ([timelineRowLookOf], I-129).
  final Layer layer;

  /// How many frames the block runs. The box over this is the live cell —
  /// what the block's corner reads — so the name's ground is cut to the
  /// PAPER it lies on at every zoom ([_SeNameGroundPainter], F-270).
  final int frames;
  final String dialogue;
  final String? seName;

  /// The line's delivery where the span is seen — written beside its name,
  /// in the name's type and by its law, where it says something
  /// ([SeLineType.writtenOut]); in the name's place where it has none.
  ///
  /// 🗣️F-496 (유저 2026-10-28): 「OFF랑 MONO도 se블록에 표시. 타임시트
  /// 용지패널처럼 이름 앞이니까 이름 왼쪽에. 이름이랑 같은텍스트/규칙.
  /// 공간없으면 이름이 블록안에 첫부분에 들어가니까, 그 경우 이름 오른쪽에
  /// 검정색으로. 대사랑 겹쳐도 문제없음」 — [_SeSpanFit.headIn].
  final SeLineType? delivery;

  /// Where the dialogue's glyphs stand on the block (F-496 ③,
  /// [dialogueGlyphSlots]).
  final SeDialogueSpacing spacing;

  /// How many of [frames] run before the window the span is seen through:
  /// the cut a sound spilled into sees its block from its own frame 0 on,
  /// the block laid out from where it really starts (F-358,
  /// [dialogueGlyphsShownIn]). Zero shows the whole span.
  final int shownFrom;

  /// The frames free on the row before the block ([seFramesFreeBefore]):
  /// the room the name chip may stand in, outside it ([seNameChipPlace]).
  final int framesFreeBefore;

  /// 🚨A ZOOM LAYS THE SPAN OUT AGAIN; IT DOES NOT BUILD IT AGAIN
  /// (zoom-step-lays-out-five-times-the-07-25-count, 10-12): how far the
  /// chip runs is the BOX's question, so it is asked where the box is known
  /// — by the layout that places the chip and by the paint that tints its
  /// ground ([_SeSpanFit]). ↩️A `LayoutBuilder` asked it here, so every SE
  /// span built its chip, its dialogue and the flex between them again on
  /// every zoom step: 100 of each in the 07-25 harness, the most of a step's
  /// 498 rebuilds.
  @override
  Widget build(BuildContext context) {
    final seName = this.seName ?? '';
    final said = delivery?.writtenOut == true ? delivery!.label : null;
    final ink = timelineRowLookOf(
      context,
      layer,
      ink: timelineDrawingInkColor,
    ).ink;
    // The name stands at the head the span is SEEN from: a sound spilled
    // in from an earlier cut wears it at this cut's frame 0 (F-496).
    // ↩️The chip was the head frame's alone, so the cut a line ran into
    // never named it (F-358-Q1).
    final chipShown = seName.isNotEmpty;
    final fit = _SeSpanFit(
      axis: axis,
      frames: frames,
      framesFreeBefore: framesFreeBefore,
      shownFrom: shownFrom,
      named: chipShown,
      dialogue: dialogue,
      spacing: spacing,
      style: dialogueFitStyle(context, color: ink),
    );
    return CustomPaint(
      painter: chipShown || said != null ? _SeNameGroundPainter(fit) : null,
      child: CustomMultiChildLayout(
        delegate: _SeSpanLayout(fit),
        children: [
          LayoutId(
            id: _SeSpanSlot.dialogue,
            child: DialogueFitText(
              text: dialogue,
              axis: axis,
              color: ink,
              frames: frames,
              spacing: spacing,
              shownFromPart: shownFrom <= 0 || frames <= 0
                  ? 0
                  : shownFrom / frames,
            ),
          ),
          // Over the words where it has no room before the block: the name
          // is what stays legible (F-358-Q1 「이름은 최대한 지금처럼 잘
          // 보이고」).
          if (chipShown)
            _headWord(_SeSpanSlot.chip, seName, fit.nameInk, 'SE name'),
          if (said != null)
            _headWord(
              _SeSpanSlot.delivery,
              said,
              fit.deliveryInk,
              'SE delivery',
            ),
        ],
      ),
    );
  }

  /// [word] in its head chip at [slot], read out as `<role> <word>`.
  LayoutId _headWord(
    _SeSpanSlot slot,
    String word,
    BuiltWordInk ink,
    String role,
  ) => LayoutId(
    id: slot,
    child: _SeHeadWord(
      axis: axis,
      word: word,
      ink: ink,
      semanticsLabel: '$role $word',
    ),
  );
}

/// Where an SE span's chip stands along the box the span lies in
/// ([seNameChipPlace]), against the dialogue's longest glyph at its natural
/// size across that box — measured once for each width across, not once
/// for each zoom step.
///
/// ↩️Narrow spans USED to DROP the name box instead of overflowing it (the
/// storyboard's zoomed-out blocks can be slimmer than the box — same rule
/// as narrow cut blocks dropping their thumbnail slot).
///
/// 🚨★★★F-93 (유저 2026-09-16): 「이름 상자를 버리는게아니야. 유지한채로 가로
/// 길이만 작게하란거야」 — the chip STAYS and narrows, the way the dialogue
/// glyphs narrow rather than vanish (`wordCondensation`).
final class _SeSpanFit {
  _SeSpanFit({
    required this.axis,
    required this.frames,
    required this.framesFreeBefore,
    required this.shownFrom,
    required this.named,
    required this.dialogue,
    required this.spacing,
    required this.style,
  }) : _glyphCount = dialogue.characters.length;

  final Axis axis;

  /// How many frames the block runs: the box over this is the live cell.
  final int frames;

  /// The frames free before the block on its row, which a box turns into
  /// the chip's room ([SeSpanVisual.framesFreeBefore]).
  final int framesFreeBefore;

  /// How many of [frames] run before the window the span is seen through
  /// ([SeSpanVisual.shownFrom]): where its head's words stand.
  final int shownFrom;

  /// Whether the span shows its name's chip — where its delivery stands
  /// beside it rather than in its place.
  final bool named;
  final String dialogue;

  /// Where the dialogue's glyphs stand: the room each has, which the chip
  /// narrows against.
  final SeDialogueSpacing spacing;
  final TextStyle style;
  final int _glyphCount;

  double? _measuredAcross;
  double _longestGlyph = 0;

  /// Where the box the span was last asked about put the head's words
  /// ([headIn]) — what each one's ink is read off at paint ([nameInk],
  /// [deliveryInk]). ⚠️Fresh at that paint by construction: a shown word
  /// is always under its ground's painter ([_SeNameGroundPainter]), which
  /// asks [headIn] of the very box and paints first — a `CustomPaint`
  /// paints its painter under its child. So a span built again with what it
  /// had, and not laid again, still writes each word in the ink of where it
  /// stands.
  _SeHead _head = (chip: 0, nameFrom: 0, deliveryFrom: 0);

  /// The chip's name's ink where it stands ([headIn]).
  ///
  /// 🗣️F-444 (유저 2026-10-23): 「지금 이름칸마저 블록으로 보여서, 어차피
  /// 뒤에 배경 어두운색이니까, 배경 바탕색 삭제하고, 심플하게 하얀색 텍스트
  /// 고정으로 텍스트만 두도록 … 만약 공간 부족해서 이름이 블록안으로 들어가는
  /// 상황에선 지금이랑 변함없이」 — before the block, white over the row; on
  /// its head, the block's ink over the tint, as it was. ⚠️The timesheet's
  /// own writing stays as it is: 「타임시트랑 달라지지만 변경하고싶음」. On
  /// its head it is the block's word, in the block's look ([style], I-129).
  Color nameInk() => _inkAt(_head.nameFrom);

  /// The delivery's ink where it stands ([headIn]) — the name's law: white
  /// before the block, the block's ink on it (F-496: 「이름이랑 같은
  /// 텍스트/규칙 … 이름 오른쪽에 검정색으로」).
  Color deliveryInk() => _inkAt(_head.deliveryFrom);

  // The white before the block is the ink the row's chrome takes — black
  // on the light palette (I-143).
  Color _inkAt(double from) =>
      from < 0 ? textOnColor(AppColors.surface) : style.color!;

  /// Where the head's words stand along [size]: the name's chip where
  /// [seNameChipPlace] says — just before the block, or at the head the
  /// span is seen from — and the delivery in a chip of its length beside
  /// it: before it where the room before the block holds both, after it
  /// where it does not, and in its place on a nameless span (F-496).
  _SeHead headIn(Size size) {
    final across = extentAcross(axis, size);
    if (_measuredAcross != across) {
      _measuredAcross = across;
      _longestGlyph = dialogueLongestGlyph(
        dialogue,
        axis: axis,
        style: style,
        maxCrossExtent: across,
      );
    }
    final along = extentAlong(axis, size);
    final frame = frames <= 0 ? 0.0 : along / frames;
    final room = framesFreeBefore * frame;
    final glyphs = dialogueGlyphSlots(
      glyphCount: _glyphCount,
      frames: frames,
      mainExtent: along,
      spacing: spacing,
    );
    final place = seNameChipPlace(
      along,
      longestGlyph: _longestGlyph,
      glyphRoom: glyphs.firstOrNull?.roomExtent ?? double.infinity,
      roomBefore: room,
    );
    final chip = place.chip;
    final nameFrom = place.outside ? -chip : shownFrom * frame;
    return _head = (
      chip: chip,
      nameFrom: nameFrom,
      deliveryFrom: switch ((named, place.outside)) {
        (false, _) => nameFrom,
        (true, true) => room >= 2 * chip ? -2 * chip : 0,
        (true, false) => nameFrom + chip,
      },
    );
  }

  /// Whether [other] answers as this does for every box.
  bool answersAs(_SeSpanFit other) =>
      axis == other.axis &&
      frames == other.frames &&
      framesFreeBefore == other.framesFreeBefore &&
      shownFrom == other.shownFrom &&
      named == other.named &&
      dialogue == other.dialogue &&
      spacing == other.spacing &&
      style == other.style;
}

/// Where a span's head words stand along its box ([_SeSpanFit.headIn]):
/// each in a chip [chip] long, the name's from [nameFrom] and the
/// delivery's from [deliveryFrom] — before the block where negative.
typedef _SeHead = ({double chip, double nameFrom, double deliveryFrom});

enum _SeSpanSlot { chip, delivery, dialogue }

/// The words over the whole span and the head's words where
/// [_SeSpanFit.headIn] says — just before the span, or at its head — each
/// centred across, as the flex that laid them did.
class _SeSpanLayout extends MultiChildLayoutDelegate {
  _SeSpanLayout(this.fit);

  final _SeSpanFit fit;

  @override
  void performLayout(Size size) {
    final axis = fit.axis;
    final across = extentAcross(axis, size);
    void lay(_SeSpanSlot slot, double from, double extent) {
      final laid = layoutChild(
        slot,
        axis == Axis.horizontal
            ? BoxConstraints.tightFor(width: extent).copyWith(maxHeight: across)
            : BoxConstraints.tightFor(height: extent).copyWith(maxWidth: across),
      );
      positionChild(
        slot,
        offsetAlong(
          axis,
          along: from,
          across: (across - extentAcross(axis, laid)) / 2,
        ),
      );
    }

    lay(_SeSpanSlot.dialogue, 0, extentAlong(axis, size));
    final head = fit.headIn(size);
    if (hasChild(_SeSpanSlot.chip)) {
      lay(_SeSpanSlot.chip, head.nameFrom, head.chip);
    }
    if (hasChild(_SeSpanSlot.delivery)) {
      lay(_SeSpanSlot.delivery, head.deliveryFrom, head.chip);
    }
  }

  @override
  bool shouldRelayout(_SeSpanLayout oldDelegate) =>
      !fit.answersAs(oldDelegate.fit);
}

/// The name chip's GROUND: over the block's head, the block's own paper
/// tinted over the chip's stretch; just before the block, none — the row
/// shows through, and the name is written white on it ([_SeSpanFit.nameInk]).
///
/// 🗣️F-270 (유저 2026-10-03): 「se블록의 이름칸의 강조색으로 되어있는 바탕색,
/// 바탕색 실루엣이 블록이랑 딱 맞춰서 꼭짓점이 동그랗게 되지않아서 바탕색
/// 오버레이만 사각형 실루엣임. 근본/구조적으로 해결」. ↩️The chip was a
/// `ColoredBox` over the block's start: square where the paper under it is
/// round, and a seam's width past the paper across the row. It is painted in
/// the BLOCK's box now and the paper's shape clips it
/// ([timelineBlockPaperShape]) — so a short block the chip takes whole is
/// round at its far end too, with nobody having to think of that case.
///
/// 🗣️F-444 (유저 2026-10-23): 「지금 이름칸마저 블록으로 보여서, 어차피 뒤에
/// 배경 어두운색이니까, 배경 바탕색 삭제하고 … 뒤에는 투명해서 배경이 비치고,
/// 하얀 텍스트만 위에 존재」. ↩️F-358 (10-19: 「이름칸 색, 뒤가 밝은걸 기준으로
/// 정한색이니까 그부분 잘 해결해주고」) had laid, just before the block, a paper
/// of its own in the block's shape, the colour the tint gives the block's
/// paper — so the name read the same on either side of the block's start,
/// and read as a block of its own.
///
/// The delivery beside the name lays no ground: the timesheet writes it 「배경
/// 색없이 텍스트만」 (I-20), and F-496 has the name's text law carried over —
/// so a span that writes only its delivery is still painted here, for the
/// box it asks of [_SeSpanFit.headIn] to keep its ink fresh.
class _SeNameGroundPainter extends CustomPainter with RepaintOnProps {
  const _SeNameGroundPainter(this.fit);

  /// Where the chip stands and how far it runs, for the box it is painted
  /// in.
  final _SeSpanFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final head = fit.headIn(size);
    if (!fit.named || head.nameFrom < 0) {
      return;
    }
    final axis = fit.axis;
    final across = extentAcross(axis, size);
    final along = extentAlong(axis, size);
    // R6-②: soft accent tint (the full-strength accent read too loud);
    // dark ink writing carries the contrast — matches the sheet.
    final tint = AppColors.accent.withValues(alpha: 0.3);
    canvas
      ..save()
      ..clipRRect(
        timelineBlockPaperShapeOver(
          axis: axis,
          along: along,
          rowExtent: across,
          frames: fit.frames,
        ),
      )
      ..drawRect(
        Rect.fromPoints(
          offsetAlong(axis, along: head.nameFrom, across: 0),
          offsetAlong(axis, along: head.nameFrom + head.chip, across: across),
        ),
        Paint()..color = tint,
      )
      ..restore();
  }

  /// The accent is LIVE (UI-R22 #5): read here rather than taken, so it is
  /// named here for a change of it to repaint. The chip's length is the
  /// box's: a box of a new size is painted again whatever these say.
  @override
  Object get props => (
    fit.axis,
    fit.frames,
    fit.framesFreeBefore,
    fit.shownFrom,
    fit.named,
    fit.dialogue,
    fit.spacing,
    fit.style,
    AppColors.accent,
  );
}

/// A chip's room and the word in it — the name, or the delivery beside it.
/// Where it stands and how far it runs ALONG the block are the layout's to
/// say ([_SeSpanLayout], [_SeSpanFit.headIn]): its [seNameBoxExtent],
/// narrowed with the words (F-224).
class _SeHeadWord extends StatelessWidget {
  const _SeHeadWord({
    required this.axis,
    required this.word,
    required this.ink,
    required this.semanticsLabel,
  });

  final Axis axis;
  final String word;

  /// The word's ink, asked at paint: where the chip stands is the layout's
  /// to say, and a zoom lays it out again without building it
  /// ([_SeSpanFit.nameInk]).
  final BuiltWordInk ink;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // Soft accent chip (R6-② tint over R5-⑦'s full accent): reads as a
    // marker ON the block start instead of an extra cell pushing it, with
    // dark ink writing carrying the contrast. Writing follows the strip:
    // upright glyph stack on the row strip, horizontal on the X-sheet
    // band. Same tint on the printed sheet.
    //
    // The tint itself is the BLOCK's to lay ([_SeNameGroundPainter], F-270):
    // this box is the chip's room and its name. Just before the block there
    // is no tint, and the name is white on the row (F-444).
    return Semantics(
      label: semanticsLabel,
      // Own node even where an ancestor would merge labels (the dialog
      // preview) — tests and screen readers address the box directly.
      container: true,
      child: _word(),
    );
  }

  /// The word written in the chip: down it on the row strip, along it on
  /// the X-sheet band.
  ///
  /// R10 R6: the vertical arm was its own glyph stack, so an SE name with a
  /// long vowel or a bracket — `ドアー`, `[SE]` — kept those glyphs lying the
  /// wrong way while the timesheet beside it rotated them. It reads the one
  /// shared table now.
  ///
  /// 유저 2026-08-24 (F-27): 「se블록의 이름이 세로쓰기세로표기 인거같은데,
  /// 가로쓰기 세로표기가 되도록. x시트는 그대로 냅둠」 — the two readings the
  /// user named on 2026-08-08 ([VerticalLatinForm]): the SCREEN block stands
  /// its Latin up, and the PRINT timesheet keeps the Japanese typesetting
  /// default. The X-sheet arm is the line branch, so it is untouched by
  /// construction rather than by an exception.
  ///
  /// A LONG name stays inside the chip instead of overflowing the row (the
  /// striped-error report — R4 improvement 2) — by the block-word law now
  /// (B, 유저 2026-09-24: 「se텍스트든 뭐든」): it keeps its type and narrows,
  /// each axis on its own, into the chip. ↩️It shrank WHOLE into the chip
  /// (`FittedBox.scaleDown`), height with width.
  Widget _word() {
    const style = TextStyle(
      color: timelineDrawingInkColor,
      fontSize: 9,
      fontWeight: FontWeight.bold,
      height: 1.05,
    );
    final place = (
      axis: axis,
      cells: 1,
      cellIndex: 0,
      growth: TimelineBlockWordGrowth.towardBlockEnd,
      acrossAlignment: 0.0,
    );
    return ExcludeSemantics(
      child: axis == Axis.horizontal
          ? TimelineBlockColumn(
              text: word,
              style: style,
              lineHeight: 1.05,
              latinForm: VerticalLatinForm.upright,
              place: place,
              ink: ink,
            )
          : TimelineBlockText(
              text: word,
              style: style,
              place: place,
              ink: ink,
            ),
    );
  }
}

/// The paper frame block for hosts without paper cells underneath (the
/// storyboard's SE track): near-white fill, hairline outline, rounded ends —
/// visually the drawing rows' block, painted as one span.
///
/// 🚨I-44: no line crossed it. It drew the frame grid's own lines across
/// itself (F-92 made them the timeline's law); 「블록에 존재하는 그리드선만
/// 싹 삭제」 took them off every block, and the grid sheet under the row
/// ruled frames alone. Its paper stops short of the row seam that sheet
/// draws ([timelineRowPaperExtent]), as a drawing row's does.
///
/// 🗣️유저 2026-09-24 made the lines a switch (on by default) — so they are
/// back where the user shows them, asked of the same function every block
/// asks ([timelineBlockFrameLine]).
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
        blockFrameLines: law?.blockFrameLines ?? false,
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
    required this.blockFrameLines,
    required this.colorScheme,
  });

  final Axis axis;
  final double frameCellExtent;
  final int startFrame;
  final Color paper;
  final Color? ground;
  final int framesPerSecond;
  final bool blockFrameLines;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    // THE block corner (F-79's one function) — this span is "visually the
    // drawing rows' block", and it rounded by a 4px of its own since the
    // first SE paper (07-09), so it never matched the blocks it mirrors.
    final rrect = timelineBlockPaperShape(
      axis: axis,
      along: extentAlong(axis, size),
      rowExtent: extentAcross(axis, size),
      frameCellExtent: frameCellExtent,
    );
    final cross = extentAcross(axis, rrect.outerRect.size);
    canvas.drawRRect(rrect, Paint()..color = paper);
    final seen = timelineGridGroundOver(under: ground, painted: paper);
    if (blockFrameLines && seen != null && frameCellExtent > 0) {
      _paintFrameLines(canvas, extentAlong(axis, size), cross, seen);
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = timelineDrawingStartBorderColor,
    );
  }

  /// The block's own frame lines over [seen] paper, [along] long.
  void _paintFrameLines(
    Canvas canvas,
    double along,
    double cross,
    Color seen,
  ) {
    final origin = timelineFrameEdge(startFrame, frameCellExtent);
    // The frame at the span's far edge, by the law read backwards — a
    // quotient of pixels drifts a frame once cells are not whole pixels.
    final end = timelineFrameAt(origin + along, frameCellExtent);
    // Only the boundaries a line can stand on ([timelineFrameLineStep]) —
    // the sheet's and the rows' walk. It asked every frame of the block,
    // and at I-22's floor a ten-minute sound is 14,400 of them.
    final step = timelineFrameLineStep(frameCellExtent, framesPerSecond);
    for (
      var frame = timelineFirstOnStride(startFrame + 1, step);
      frame < end;
      frame += step
    ) {
      final line = timelineBlockFrameLine(
        axis: axis,
        frameIndex: frame,
        boundary: timelineFrameEdge(frame, frameCellExtent) - origin,
        across: (from: 0, to: cross),
        frameCellExtent: frameCellExtent,
        framesPerSecond: framesPerSecond,
        colorScheme: colorScheme,
        paper: seen,
      );
      if (line != null) {
        canvas.drawRect(line.rect, Paint()..color = line.color);
      }
    }
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
    blockFrameLines,
    colorScheme,
  );
}
