import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_playhead_writing.dart';

/// I-22 ②: the playhead's writing (I-16) is worked out on every playback
/// tick, and it used to lay out the strip's writing at EVERY frame of the
/// painted window to find what the pair stands on — a thousand frames at
/// today's 2.4px floor, fifteen thousand at a ten-minute zoom (measured on
/// the timeline: a tick at 0.16px cost 3.5× a tick at 2.4px).
///
/// A glyph can only reach the pair from as far as the widest thing the
/// strip writes, so the walk reads that neighbourhood — and finds exactly
/// what the whole window would have.
void main() {
  Future<TimelineRulerScale> rulerOf(
    WidgetTester tester, {
    required double cell,
    required int frames,
    bool showSeconds = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineFrameHeaderRow(
              frameStartIndex: 0,
              frameEndIndexExclusive: frames,
              currentFrameIndex: -1,
              playbackFrameCount: frames,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: TimelineGridMetrics.defaults.copyWith(
                frameCellWidth: cell,
              ),
              onSelectFrame: (_) {},
              showSeconds: showSeconds,
            ),
          ),
        ),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('timeline-frame-ruler-paint')),
    );
    return (paint.painter! as TimelineFrameRulerPainter).scale;
  }

  testWidgets('a tick reads only the writing that can reach the pair', (
    tester,
  ) async {
    final scale = await rulerOf(tester, cell: 1, frames: 3000);
    final window = scale.visibleWindow();
    expect(
      window.endIndexExclusive - window.startIndex,
      3000,
      reason: 'fixture: the whole strip is the painted window',
    );
    var laidOut = 0;
    List<TimelineGlyphPlacement> counting(
      TimelineRulerScale scale,
      int frameIndex, {
      required bool current,
    }) {
      laidOut += 1;
      return TimelineFrameRulerPainter.glyphsAt(
        scale,
        frameIndex,
        current: current,
      );
    }

    timelineRulerPlayheadWriting(
      scale: scale,
      frame: 1500,
      layout: counting,
    );
    expect(
      laidOut,
      lessThan(400),
      reason: 'a tick lays out the neighbourhood of the pair, not all 3000 '
          'frames of the window',
    );
  });

  testWidgets('what the neighbourhood finds is what the whole window would '
      'find', (tester) async {
    for (final showSeconds in [false, true]) {
      for (final frames in [120, 3000]) {
        for (final cell in [0.5, 1.0, 2.4, 8.0, 24.0]) {
          final scale = await rulerOf(
            tester,
            cell: cell,
            frames: frames,
            showSeconds: showSeconds,
          );
          final window = scale.visibleWindow();
          for (final frame in [0, frames ~/ 2, frames - 1]) {
            final where =
                '${showSeconds ? 'seconds' : 'frames'} · $frames frames · '
                '${cell}px · playhead $frame';
            final writing = timelineRulerPlayheadWriting(
              scale: scale,
              frame: frame,
              layout: TimelineFrameRulerPainter.glyphsAt,
            );
            final pair = writing.pair.map((glyph) => glyph.rect).toList();
            final covered = <Rect>[];
            final standing = <TimelineGlyphPlacement>[];
            for (
              var frameIndex = window.startIndex;
              frameIndex < window.endIndexExclusive;
              frameIndex += 1
            ) {
              for (final glyph in TimelineFrameRulerPainter.glyphsAt(
                scale,
                frameIndex,
                current: false,
              )) {
                if (pair.any((rect) => rect.overlaps(glyph.rect))) {
                  covered.add(glyph.rect);
                } else {
                  standing.add(glyph);
                }
              }
            }
            expect(writing.covered, covered, reason: where);
            final kept = writing.standing.map((glyph) => glyph.rect).toSet();
            for (final glyph in standing) {
              if (covered.any((rect) => rect.overlaps(glyph.rect))) {
                expect(
                  kept,
                  contains(glyph.rect),
                  reason: '$where: a standing glyph that reaches into what '
                      'stands down is rewritten after the uncovering',
                );
              }
            }
          }
        }
      }
    }
  });
}
