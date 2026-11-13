import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../repaint_props.dart';
import '../text/word_bake.dart' show RepaintOnWordBakes;
import '../widgets/tick_layer.dart';
import 'axis_turn.dart' show endAlong, extentAlong, startAlong;
import '../../models/ruler_marker.dart' show RulerMarker;
import '../theme/ruler_marker_palette.dart' show rulerMarkerInk;
import 'memo_token.dart';
import 'ruler_marker_layer.dart';
import 'timeline_drag_preview.dart' show rulerMarkersUnder;
import 'timeline_frame_ruler_painter.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';

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
/// ↩️I-22 ②: narrowed to the part of the window whose writing can reach the
/// pair ([_writingReach]) — [covered] is exactly what the whole window gives,
/// and [standing] still holds every glyph an uncovering could cut into.
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
  final pair = scale.writtenAt(layout, frame, current: true);
  final pairRects = [for (final mine in pair) mine.rect];
  final covered = <Rect>[];
  final standing = <TimelineGlyphPlacement>[];
  final reach = pair.isEmpty
      ? scale.visibleWindow()
      : _writingReach(
          scale: scale,
          layout: layout,
          under: (startIndex: frame, endIndexExclusive: frame + 1),
          extent: _widestAlong(scale, pair),
        );
  // The frames the strip writes at, walked as the strip walks them
  // ([TimelineRulerScale.paintWindow]): I-22 ③ — the neighbourhood is
  // ~1,200 frames at 0.16px, and a frame off the stride holds no writing.
  for (final frameIndex in scale.framesWrittenIn(reach)) {
    for (final glyph in scale.writtenAt(layout, frameIndex, current: false)) {
      final rect = glyph.rect;
      if (timelineMarkStandsDownFor(rect, pairRects)) {
        covered.add(rect);
      } else {
        standing.add(glyph);
      }
    }
  }
  return (pair: pair, covered: covered, standing: standing);
}

/// Whether the strip's writing at [mark] stands down for the playhead's own
/// writing over [pair]: it touches one of the pair's glyphs, and stands
/// down WHOLE — the pair wins (I-16 「겹쳐지는부분있으면 안겹쳐지도록 기존에
/// 있던 텍스트 사라지도록」). A ruler's, and a sound face's (F-71).
bool timelineMarkStandsDownFor(Rect mark, List<Rect> pair) =>
    pair.any((mine) => mine.overlaps(mark));

/// The frames of the painted window whose writing can reach what stands
/// over the frames [under] and [extent] out of them along the strip — the
/// playhead's pair over its frame, as far as its widest glyph runs; a
/// marker's ribbon over its own, and no further (I-169).
///
/// 🚨I-22 ②: the writing is worked out on every playback tick, and walking
/// the whole window laid out a thousand frames at today's 2.4px floor and
/// fifteen thousand at a ten-minute zoom — a timeline tick measured 3.5×
/// dearer at 0.16px than at 2.4px. A glyph stands in its own cell and reaches
/// at most its own width out of it, so a glyph further from the pair than
/// the pair's extent and two widest glyphs (a standing glyph matters when it
/// reaches into a covered one) cannot touch it.
///
/// The widest glyph is read off the pair written where the window's writing
/// runs longest — its last frame, and where the count starts again (the
/// seconds display, the page view) the last frame whose number is the
/// longest ([TimelineRulerScale.widestNumberFrameBefore]) — in the
/// playhead's bold, never narrower than the strip's own ink at the same
/// size. Four pixels of slack cover the strip's insets.
({int startIndex, int endIndexExclusive}) _writingReach({
  required TimelineRulerScale scale,
  required TimelineRulerGlyphLayout layout,
  required ({int startIndex, int endIndexExclusive}) under,
  required double extent,
}) {
  final window = scale.visibleWindow();
  final cell = scale.metrics.frameCellWidth;
  if (cell <= 0 || window.endIndexExclusive <= window.startIndex) {
    return window;
  }
  final widestNumber = scale.widestNumberFrameBefore(
    window.endIndexExclusive,
  );
  var widest = 0.0;
  for (final probe in {
    window.endIndexExclusive - 1,
    if (widestNumber >= window.startIndex) widestNumber,
  }) {
    final written = _widestAlong(
      scale,
      scale.writtenAt(layout, probe, current: true),
    );
    widest = written > widest ? written : widest;
  }
  // ⛔No probe of the page view's marks (`17 p3`, I-81-Q4): a mark is its
  // second and a page beside it, wider than any glyph a pair writes but
  // narrower than the pair and the two widest the reach already allows.
  // A probe for it survived its own mutant (10-30); the pin a hundred
  // pages in is what keeps that true.
  final cells = ((extent + 2 * widest + 4) / cell).ceil() + 1;
  final start = under.startIndex - cells;
  final end = under.endIndexExclusive + cells;
  return (
    startIndex: start > window.startIndex ? start : window.startIndex,
    endIndexExclusive: end < window.endIndexExclusive
        ? end
        : window.endIndexExclusive,
  );
}

/// The strip's writing that [markers]' ribbons stand on, as it is written
/// again OVER them: each glyph of the strip that reaches into a ribbon, set
/// in the markers' ink ([rulerMarkerInk]) where the strip set it. What the
/// playhead's [pair] covers stays down (I-16) — the pair is written there.
///
/// 🗣️I-169-Q1 (유저 2026-11-13 took 「A · 룰러 안의 깃발」, whose own
/// words were): 「초가 서는 칸에서는 초 글자가 깃발 위에 그대로 보인다」 — and
/// I-169-Q4: 「겹치는거 전혀문제없음. 재생헤드 숫자 텍스트가 마커보다 위
/// 층이면 됨」. So a ribbon hides none of the ruler's own writing: the
/// second on the ruler across, and on the rail down the frame's number too,
/// which stands across the rail's whole breadth.
///
/// The walk is each ribbon's own neighbourhood ([_writingReach]), as the
/// pair's is — a tick of a playing run asks this once more, of the markers
/// that stand in the painted window
/// ([TimelineRulerPlayheadWritingPainter.markersShown]).
List<TimelineGlyphPlacement> timelineRulerWritingOverMarkers({
  required TimelineRulerScale scale,
  required TimelineRulerGlyphLayout layout,
  required List<RulerMarker> markers,
  required List<Rect> pair,
}) {
  final ribbons = [
    for (final marker in markers) rulerMarkerRect(scale, marker),
  ];
  final frames = <int>{
    for (final marker in markers)
      ...scale.framesWrittenIn(
        _writingReach(
          scale: scale,
          layout: layout,
          under: (
            startIndex: marker.start,
            endIndexExclusive: marker.endExclusive,
          ),
          extent: 0,
        ),
      ),
  };
  return [
    for (final frameIndex in frames)
      for (final glyph in scale.writtenAt(layout, frameIndex, current: false))
        if (ribbons.any(glyph.rect.overlaps) &&
            !timelineMarkStandsDownFor(glyph.rect, pair))
          glyph.inInk(rulerMarkerInk),
  ];
}

/// Whether [marker] stands over a frame of [window].
bool _standsIn(
  ({int startIndex, int endIndexExclusive}) window,
  RulerMarker marker,
) =>
    marker.endExclusive > window.startIndex &&
    marker.start < window.endIndexExclusive;

/// The longest any of [glyphs] runs along [scale]'s strip.
double _widestAlong(
  TimelineRulerScale scale,
  Iterable<TimelineGlyphPlacement> glyphs,
) {
  var widest = 0.0;
  for (final glyph in glyphs) {
    final extent = extentAlong(scale.axis, glyph.rect.size);
    widest = extent > widest ? extent : widest;
  }
  return widest;
}

/// A ruler strip as mounted: [strip], its static paint, and — with a
/// playhead — the playhead's pair over it, painted by [writing] on a
/// layer of its OWN (I-16). The ruler across and the X-sheet rail down both
/// mount their strip here, so the two cannot disagree about where the
/// writing sits or what its repaints touch.
///
/// A ruler's markers stand BETWEEN the two (I-169) — 🗣️유저 2026-11-13
/// (I-169-Q4): 「마커랑 재생헤드쪽의 초/프레임 숫자 겹칠텐데 겹치는거
/// 전혀문제없음. 재생헤드 숫자 텍스트가 마커보다 위 층이면 됨」. So the
/// writing is mounted for a ruler that has markers too, playhead or none:
/// it is where the strip's own writing shows over a ribbon. It takes no
/// press — what is pressed there is the marker under it, or the strip.
///
/// The ribbons are mounted HERE, off [writing]'s own markers and scale: the
/// writing clips what it writes again to the ribbons' outlines, so the two
/// are of one ruler or the ink stands beside its ribbon.
Widget timelineRulerStripWithWriting({
  required Widget strip,
  required Key writingKey,
  required Key markersKey,
  required TimelineRulerPlayheadWritingPainter writing,
}) {
  final markers = writing.markers;
  return Stack(
    children: [
      strip,
      if (markers != null)
        Positioned.fill(
          child: RulerMarkerLayer(
            key: markersKey,
            hooks: markers,
            scale: writing.scale,
          ),
        ),
      if (writing.playhead != null || markers != null)
        Positioned.fill(
          child: IgnorePointer(
            // What a tick moves, on the one layer every tick rides (I-22 ③).
            child: TickLayer(
              child: CustomPaint(key: writingKey, painter: writing),
            ),
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
///
/// It is also where the strip's writing shows OVER a marker's ribbon
/// (I-169): the ribbons stand between the strip and this layer, and what a
/// ribbon hides of the strip's seconds and numbers is written again on it,
/// in the markers' ink. 🗣️The question's own words for the flag the user
/// took (I-169-Q1, 「A · 룰러 안의 깃발」): 「초가 서는 칸에서는 초 글자가
/// 깃발 위에 그대로 보인다」 — and the rail's numbers, which stand across
/// its whole breadth, the same way.
class TimelineRulerPlayheadWritingPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes {
  TimelineRulerPlayheadWritingPainter({
    required this.scale,
    required this.playhead,
    required this.layout,
    this.markers,
  }) : super(
         repaint: Listenable.merge([
           ?playhead,
           ?scale.windowBucket,
           ?markers?.dragPreview,
         ]),
       );

  final TimelineRulerScale scale;

  /// The ruler's markers, which stand between the strip and this writing
  /// (I-169). Heard while one is dragged: what the strip writes under a
  /// ribbon moves with it.
  final RulerMarkerHooks? markers;

  /// The frame the pair follows; a null VALUE writes nothing (the
  /// storyboard's "no playhead" state), and so does a ruler handed none —
  /// one mounted for its markers alone.
  final ValueListenable<int?>? playhead;

  final TimelineRulerGlyphLayout layout;

  /// The frame the pair is written at — null with no playhead, or with one
  /// off the painted window (the probe surface).
  int? writtenFrame() {
    final frame = playhead?.value;
    if (frame == null) {
      return null;
    }
    return frameWindowContains(scale.visibleWindow(), frame) ? frame : null;
  }

  @override
  void paintWords(Canvas canvas, Size size) {
    final frame = writtenFrame();
    final writing = frame == null
        ? null
        : timelineRulerPlayheadWriting(
            scale: scale,
            frame: frame,
            layout: layout,
          );
    final window = scale.visibleWindow();
    final shown = markersShown();
    final ribbons = [
      for (final marker in shown) rulerMarkerRect(scale, marker),
    ];
    final pair = writing?.pair ?? const <TimelineGlyphPlacement>[];
    for (final rect in writing?.covered ?? const <Rect>[]) {
      canvas.save();
      _clipClearOfRibbons(canvas, rect, ribbons);
      // The paper laid the way the strip lays it — a stretch of one ground
      // at a time ([TimelineRulerScale.paintPaperIn]), under the clip. I-22
      // ③: a cell at a time was hundreds of sixth-of-a-pixel rects under one
      // glyph at the ten-minute floor, on every playback tick.
      scale.paintPaperIn(canvas, _cellsUnder(rect, window));
      for (final glyph in writing!.standing) {
        if (glyph.rect.overlaps(rect)) {
          glyph.paint(canvas);
        }
      }
      canvas.restore();
    }
    if (ribbons.isNotEmpty) {
      // As far as each ribbon runs: beside it the strip's own writing shows
      // as it was, in its own ink.
      final outlines = Path();
      for (final ribbon in ribbons) {
        outlines.addPath(rulerMarkerOutline(scale.axis, ribbon), Offset.zero);
      }
      canvas.save();
      canvas.clipPath(outlines);
      for (final glyph in _writtenOver(shown, [
        for (final mine in pair) mine.rect,
      ])) {
        glyph.paint(canvas);
      }
      canvas.restore();
    }
    for (final glyph in pair) {
      glyph.paint(canvas);
    }
  }

  /// The ruler's markers that stand in the painted window, as they are
  /// shown — a drag in flight's where one is (the probe surface). A marker
  /// off the window is no work of a tick's: there is no ribbon of it to
  /// clip by and no neighbourhood of it to walk.
  List<RulerMarker> markersShown() {
    final markers = this.markers;
    if (markers == null) {
      return const [];
    }
    final window = scale.visibleWindow();
    return [
      for (final marker in rulerMarkersUnder(
        markers.dragPreview.value,
        markers.holder,
        markers.markers,
      ).inOrder)
        if (_standsIn(window, marker)) marker,
    ];
  }

  /// What is written over the ruler's ribbons ([timelineRulerWritingOverMarkers])
  /// with the playhead where it is — the probe surface.
  List<TimelineGlyphPlacement> writtenOverMarkers() {
    final frame = writtenFrame();
    return _writtenOver(markersShown(), [
      if (frame != null)
        for (final mine in scale.writtenAt(layout, frame, current: true))
          mine.rect,
    ]);
  }

  List<TimelineGlyphPlacement> _writtenOver(
    List<RulerMarker> shown,
    List<Rect> pair,
  ) => timelineRulerWritingOverMarkers(
    scale: scale,
    layout: layout,
    markers: shown,
    pair: pair,
  );

  /// Clips to [rect] where no ribbon stands. A ribbon is over the strip
  /// already — the glyph the pair covers is hidden there — and paper laid
  /// back on it would cut a hole in the ribbon beside the pair.
  void _clipClearOfRibbons(Canvas canvas, Rect rect, List<Rect> ribbons) {
    Path? clear;
    for (final ribbon in ribbons) {
      if (ribbon.overlaps(rect)) {
        clear = Path.combine(
          PathOperation.difference,
          clear ?? (Path()..addRect(rect)),
          rulerMarkerOutline(scale.axis, ribbon),
        );
      }
    }
    if (clear == null) {
      canvas.clipRect(rect);
    } else {
      canvas.clipPath(clear);
    }
  }

  /// The frames of [window] whose cell, inflated by a pixel, can touch
  /// [rect] — the paper an uncovering lays back under one covered glyph.
  /// I-22 ②: each covered glyph used to walk the whole window for it.
  ({int startIndex, int endIndexExclusive}) _cellsUnder(
    Rect rect,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final cell = scale.metrics.frameCellWidth;
    if (cell <= 0) {
      return window;
    }
    final from = startAlong(scale.axis, rect) - 1 - scale.leadingFrameSpacer;
    final to = endAlong(scale.axis, rect) + 1 - scale.leadingFrameSpacer;
    final first = scale.frameStartIndex + (from / cell).floor() - 1;
    final past = scale.frameStartIndex + (to / cell).ceil() + 1;
    return (
      startIndex: first > window.startIndex ? first : window.startIndex,
      endIndexExclusive: past < window.endIndexExclusive
          ? past
          : window.endIndexExclusive,
    );
  }

  @override
  Object get props => (
    scale,
    ByIdentity(playhead),
    layout,
    markers?.holder,
    markers?.markers,
    ByIdentity(markers?.dragPreview),
  );
}
