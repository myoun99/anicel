import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../repaint_props.dart';
import 'memo_token.dart';
import 'timeline_frame_ruler_painter.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';

/// Where a ruler strip writes at one frame — the strip's OWN layout
/// (`TimelineFrameRulerPainter.glyphsAt` across, `XSheetFrameRailPainter
/// .glyphsAt` down); [current] asks for the playhead's pair.
typedef TimelineRulerGlyphLayout =
    List<TimelineGlyphPlacement> Function(
      TimelineRulerScale scale,
      int frameIndex, {
      required bool current,
    });

/// The playhead's own writing on a ruler strip, and what of the strip's
/// writing it stands on (I-16).
///
/// 🗣️유저 2026-09-11: 「타임라인 플레이헤드쪽에 현재 코마랑 초수 텍스트 항상
/// 표시하도록. 현재 인덱스에만. 볼드체로. 초수는 초수 열에서 뜨고 코마는 코마
/// 열에서 뜨도록. 즉 기존 초수랑 코마 텍스트 그대로 두고, 현재 인덱스 부분에
/// 초수랑 코마 텍스트 추가. 겹쳐지는부분있으면 안겹쳐지도록 기존에 있던 텍스트
/// 사라지도록. 현재 인덱스 텍스트를 우선으로 표시」.
///
/// [pair] is the number and the second at [frame], written where the strip
/// writes that frame's own, in the playhead's ink. [covered] is every glyph
/// of the strip's writing the pair touches — WHOLE glyphs: the strip's text
/// there stands down, and the pair wins. [standing] is the rest of the
/// window's writing, which an uncovering must not cut into.
///
/// The walk is the painted window's, like the cursor overlay's ready runs.
({
  List<TimelineGlyphPlacement> pair,
  List<Rect> covered,
  List<TimelineGlyphPlacement> standing,
})
timelineRulerPlayheadWriting({
  required TimelineRulerScale scale,
  required int frame,
  required TimelineRulerGlyphLayout layout,
}) {
  final pair = layout(scale, frame, current: true);
  final covered = <Rect>[];
  final standing = <TimelineGlyphPlacement>[];
  final window = scale.visibleWindow();
  for (
    var frameIndex = window.startIndex;
    frameIndex < window.endIndexExclusive;
    frameIndex += 1
  ) {
    for (final glyph in layout(scale, frameIndex, current: false)) {
      final rect = glyph.rect;
      if (pair.any((mine) => mine.rect.overlaps(rect))) {
        covered.add(rect);
      } else {
        standing.add(glyph);
      }
    }
  }
  return (pair: pair, covered: covered, standing: standing);
}

/// A ruler strip as mounted: [strip], its static paint, and — with a
/// [playhead] — the playhead's pair over it, painted by [writing] on a
/// layer of its OWN (I-16). The ruler across and the X-sheet rail down both
/// mount their strip here, so the two cannot disagree about where the
/// writing sits or what its repaints touch.
Widget timelineRulerStripWithWriting({
  required Widget strip,
  required Key writingKey,
  required ValueListenable<int?>? playhead,
  required TimelineRulerPlayheadWritingPainter Function(
    ValueListenable<int?> playhead,
  )
  writing,
}) {
  final held = playhead;
  return Stack(
    children: [
      strip,
      if (held != null)
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(key: writingKey, painter: writing(held)),
          ),
        ),
    ],
  );
}

/// The playhead's writing over a ruler strip (I-16), on its OWN raster
/// layer: it repaints with the playhead while the strip under it stays
/// recorded — the split the cursor tint made (the storyboard's
/// cheap-playhead pattern), which is why the strips themselves are handed
/// no current frame.
///
/// Uncovering lays the strip's own paper back under each covered glyph,
/// clipped to it, and rewrites whatever standing writing reaches in there
/// — so what stands down goes whole and nothing beside it is cut.
class TimelineRulerPlayheadWritingPainter extends CustomPainter
    with RepaintOnProps {
  TimelineRulerPlayheadWritingPainter({
    required this.scale,
    required this.playhead,
    required this.layout,
  }) : super(repaint: Listenable.merge([playhead, ?scale.windowBucket]));

  final TimelineRulerScale scale;

  /// The frame the pair follows; a null VALUE writes nothing (the
  /// storyboard's "no playhead" state).
  final ValueListenable<int?> playhead;

  final TimelineRulerGlyphLayout layout;

  /// The frame the pair is written at — null with no playhead, or with one
  /// off the painted window (the probe surface).
  int? writtenFrame() {
    final frame = playhead.value;
    if (frame == null) {
      return null;
    }
    return frameWindowContains(scale.visibleWindow(), frame) ? frame : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = writtenFrame();
    if (frame == null) {
      return;
    }
    final writing = timelineRulerPlayheadWriting(
      scale: scale,
      frame: frame,
      layout: layout,
    );
    final window = scale.visibleWindow();
    final fill = Paint();
    final line = Paint();
    for (final rect in writing.covered) {
      canvas.save();
      canvas.clipRect(rect);
      for (
        var frameIndex = window.startIndex;
        frameIndex < window.endIndexExclusive;
        frameIndex += 1
      ) {
        // Inflated: a neighbour's boundary line strokes over the edge.
        if (scale.cellRectFor(frameIndex).inflate(1).overlaps(rect)) {
          scale.paintCellPaper(canvas, frameIndex, fill: fill, line: line);
        }
      }
      for (final glyph in writing.standing) {
        if (glyph.rect.overlaps(rect)) {
          glyph.paint(canvas);
        }
      }
      canvas.restore();
    }
    for (final glyph in writing.pair) {
      glyph.paint(canvas);
    }
  }

  @override
  Object get props => (scale, ByIdentity(playhead), layout);
}
