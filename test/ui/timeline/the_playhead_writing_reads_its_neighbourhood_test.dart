import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_playhead_writing.dart';

import '../../helpers/recording_ruler_layout.dart';

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
    FrameRulerView rulerView = FrameRulerView.frames,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimelineFrameHeaderRow(
              frameStartIndex: 0,
              frameEndIndexExclusive: frames,
              playbackFrameCount: frames,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              metrics: TimelineGridMetrics.defaults.copyWith(
                frameCellWidth: cell,
              ),
              onSelectFrame: (_) {},
              rulerView: rulerView,
              pageFrames: 144,
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
    final recorded = recordingRulerLayout();
    timelineRulerPlayheadWriting(
      scale: scale,
      frame: 1500,
      layout: recorded.layout,
    );
    expect(
      recorded.asked,
      hasLength(lessThan(400)),
      reason: 'a tick lays out the neighbourhood of the pair, not all 3000 '
          'frames of the window',
    );
  });

  // 🚨I-22 ③ (09-27): the neighbourhood is ~1,200 frames at 0.16px, and the
  // walk laid out every one of them to find the few the strip writes at —
  // the storyboard's heaviest cost on a ten-minute playback tick. The strip
  // walks its own stride ([TimelineRulerScale.writingStep]); so does this.
  testWidgets('at the ten-minute floor a tick lays out the frames the strip '
      'writes at, and no other', (tester) async {
    final scale = await rulerOf(tester, cell: 0.16, frames: 3000);
    final step = scale.writingStep;
    expect(step, greaterThan(1), reason: 'fixture: the strip thins its marks');
    final recorded = recordingRulerLayout();
    timelineRulerPlayheadWriting(
      scale: scale,
      frame: 1500,
      layout: recorded.layout,
    );
    final visited = [
      for (final ask in recorded.asked)
        if (!ask.current) ask.frame,
    ];
    expect(visited, isNotEmpty, reason: 'premise: the neighbourhood was read');
    expect(
      visited.where((frame) => frame % step != 0),
      isEmpty,
      reason: 'only the frames the strip itself writes at',
    );
  });

  // 🚨I-57 (10-15, profile, the user's project): every tick of a run laid
  // its whole neighbourhood out again — a dozen layouts at 12µs, the dearest
  // paint of a playing frame — though the next tick's neighbourhood is the
  // last one's moved a frame ([TimelineRulerScale.writtenAt]).
  testWidgets('a tick lays out only what no tick before it did', (
    tester,
  ) async {
    final scale = await rulerOf(tester, cell: 24, frames: 3000);
    final recorded = recordingRulerLayout();
    void tick(int frame) => timelineRulerPlayheadWriting(
      scale: scale,
      frame: frame,
      layout: recorded.layout,
    );

    tick(1500);
    final first = recorded.asked.toSet();
    expect(
      first,
      hasLength(greaterThan(3)),
      reason: 'premise: a tick reads a neighbourhood round the pair',
    );
    recorded.asked.clear();
    tick(1501);
    expect(
      recorded.asked,
      isNotEmpty,
      reason: 'premise: the pair moved to a frame not yet written',
    );
    expect(recorded.asked.where(first.contains), isEmpty);
    recorded.asked.clear();
    tick(1500);
    expect(recorded.asked, isEmpty, reason: 'a loop come back round');
  });

  // I-22 ②: an uncovering laid the paper back under a covered glyph from a
  // walk of the whole window. The paper it lays is the cells round that
  // glyph, along the strip, and no further.
  testWidgets('an uncovering lays paper under the cells round its glyph, not '
      'from the window\'s start', (tester) async {
    const cell = 8.0;
    final scale = await rulerOf(tester, cell: cell, frames: 300);
    final playhead = ValueNotifier<int?>(150);
    addTearDown(playhead.dispose);
    final canvas = TestRecordingCanvas();
    TimelineRulerPlayheadWritingPainter(
      scale: scale,
      playhead: playhead,
      layout: TimelineFrameRulerPainter.glyphsAt,
    ).paint(canvas, Size.zero);

    // The paper an uncovering lays: what is filled inside a glyph's clip.
    final laid = <(Rect clip, Rect paper)>[];
    Rect? clip;
    for (final call in canvas.invocations) {
      final invocation = call.invocation;
      switch (invocation.memberName) {
        case #clipRect:
          clip = invocation.positionalArguments[0] as Rect;
        case #restore:
          clip = null;
        case #drawRect:
          if (clip case final inside?) {
            laid.add((inside, invocation.positionalArguments[0] as Rect));
          }
      }
    }
    expect(laid, isNotEmpty, reason: 'premise: the pair covers a glyph');
    for (final (clip, paper) in laid) {
      expect(
        paper.left,
        greaterThanOrEqualTo(clip.left - 3 * cell),
        reason: 'paper from the cells under $clip, not from the window',
      );
      expect(paper.right, lessThanOrEqualTo(clip.right + 3 * cell));
    }
  });

  testWidgets('what the neighbourhood finds is what the whole window would '
      'find', (tester) async {
    // I-81: a page of 6 seconds — the X-sheet a cut of 24fps prints.
    for (final view in FrameRulerView.values) {
      for (final frames in [120, 3000]) {
        for (final cell in [0.16, 0.5, 1.0, 2.4, 8.0, 24.0]) {
          final scale = await rulerOf(
            tester,
            cell: cell,
            frames: frames,
            rulerView: view,
          );
          final window = scale.visibleWindow();
          for (final frame in [0, frames ~/ 2, frames - 1]) {
            final where =
                '${view.name} · $frames frames · '
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
