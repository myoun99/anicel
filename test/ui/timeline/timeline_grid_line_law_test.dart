import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart'
    show timelineRulerSecondsLabel;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineBaseGridAlpha;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineFrameStrides;

/// D8/D32/D38 (2026-08-18): THE grid-line law — ink, position, cadence and
/// the over-block treatment stated once, consulted by every drawer (the
/// beat-lines overlay, the frame ruler, the x-sheet rail, the collapsed
/// overlay, and the block seams).
void main() {
  // THE app's scheme, not ColorScheme.dark(): the fallback scheme's
  // outlineVariant is pure white, which multiplies to a no-op and says
  // nothing about the real hairline gray the app draws with.
  final scheme = buildAppTheme().colorScheme;

  test('the dispatcher answers WITH the named inks — no fourth value can '
      'exist', () {
    // A base boundary (cadence 1 at a wide cell, not a 6f multiple).
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 5,
        frameCellExtent: 24,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      timelineGridBaseLineInk(scheme),
    );
    // A 6f boundary that is not a second boundary.
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 6,
        frameCellExtent: 24,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      timelineGridSixLineInk(scheme),
    );
    // A second boundary.
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 24,
        frameCellExtent: 24,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      timelineGridSecondLineInk(),
    );
    expect(
      timelineGridBaseLineInk(scheme).color.a,
      moreOrLessEquals(timelineBaseGridAlpha),
      reason: 'UI-R14 #4: one faint value across all three panels',
    );
  });

  test('the grid rules its second line where the ruler writes a second — a '
      'nonsense rate included', () {
    // One answer to 「does a second begin here」: the ruler reads a nonsense
    // rate as 24, and the grid ruled no second at all for it.
    for (final fps in [24, 30, 0]) {
      for (var frame = 6; frame <= 120; frame += 6) {
        final ruled =
            timelineFrameBoundaryLineInk(
              frameIndex: frame,
              frameCellExtent: 24,
              framesPerSecond: fps,
              colorScheme: scheme,
            ) ==
            timelineGridSecondLineInk();
        final marked = timelineRulerSecondsLabel(
          frameIndex: frame,
          framesPerSecond: fps,
        ).isNotEmpty;
        expect(ruled, marked, reason: 'frame $frame at $fps fps');
      }
    }
  });

  test('the position convention is boundary + the ruler\'s own half-pixel '
      'snap (D8)', () {
    expect(timelineFrameBoundaryLinePosition(0, 24), timelineGridLineSnap);
    expect(timelineFrameBoundaryLinePosition(6, 24), 144 + 0.5);
    expect(timelineFrameBoundaryLinePosition(3, 7.5), 22.5 + 0.5);
  });

  test('cadence thins the base line but never the beats — the one answer '
      'D38 makes every surface share', () {
    // At 10% (2.4px) a line and its ground need three frames, so a plain
    // boundary between them thins out…
    final cadence = timelineGridLineEveryFrames(2.4);
    expect(cadence, greaterThan(1), reason: 'fixture premise');
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 1,
        frameCellExtent: 2.4,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      isNull,
    );
    // …while the 6f beat stays.
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 6,
        frameCellExtent: 2.4,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      isNotNull,
    );
  });

  test('I-22: a base line thins only where it would crowd the next — the '
      'densest rung that holds its stroke and its ground', () {
    const room = timelineGridBaseLineStroke + timelineMarkGap;
    for (final cell in [1.0, 2.4, 3.0, 4.0, 8.0, 12.0, 16.0, 24.0]) {
      final cadence = timelineGridLineEveryFrames(cell);
      expect(cadence * cell, greaterThanOrEqualTo(room), reason: '${cell}px');
      final strides = timelineFrameStrides().take(24).toList();
      final index = strides.indexOf(cadence);
      if (index > 0) {
        expect(
          strides[index - 1] * cell,
          lessThan(room),
          reason: '${cell}px: the denser rung would crowd',
        );
      }
    }
    expect(timelineGridLineEveryFrames(8), 1, reason: '33% keeps every line');
  });

  group('I-22: at the ten-minute floor the marks thin by the same law', () {
    ({Color color, double strokeWidth})? inkAt(
      int frame, {
      required double cell,
      int fps = 24,
    }) => timelineFrameBoundaryLineInk(
      frameIndex: frame,
      frameCellExtent: cell,
      framesPerSecond: fps,
      colorScheme: scheme,
    );

    test('the 6f beats stand down and the seconds step on their ladder', () {
      const cell = 1 / 8; // 24fps: a second is 3px
      expect(timelineSixLinesHold(cell), isFalse);
      expect(
        timelineSecondLineEverySeconds(cell, 24),
        2,
        reason: 'a second line and its ground need 3.5px; two seconds are 6',
      );
      expect(inkAt(48, cell: cell), timelineGridSecondLineInk());
      expect(
        inkAt(24, cell: cell),
        timelineGridBaseLineInk(scheme),
        reason: 'the odd second keeps the faint base line on its cadence',
      );
      expect(inkAt(6, cell: cell), isNull, reason: 'no beat at 0.75px');
    });

    test('at every zoom the old floor allowed, nothing moved', () {
      for (final cell in [2.4, 8.0, 24.0]) {
        expect(timelineSixLinesHold(cell), isTrue, reason: '${cell}px');
        expect(timelineSecondLineEverySeconds(cell, 24), 1);
        expect(inkAt(6, cell: cell), timelineGridSixLineInk(scheme));
        expect(inkAt(24, cell: cell), timelineGridSecondLineInk());
      }
    });

    test('a second is ruled where it begins, whatever the rate', () {
      expect(
        inkAt(25, cell: 24, fps: 25),
        timelineGridSecondLineInk(),
        reason: 'the ruler marks second 1 at frame 25; the grid rules it',
      );
      expect(inkAt(24, cell: 24, fps: 25), timelineGridSixLineInk(scheme));
    });

    test('the step a drawer walks visits every boundary the law rules', () {
      for (final fps in [24, 25, 30, 60]) {
        for (final cell in [1 / 20, 1 / 8, 0.5, 1.0, 2.4, 6.0, 24.0]) {
          final step = timelineFrameLineStep(cell, fps);
          for (var frame = 1; frame < 6000; frame += 1) {
            if (inkAt(frame, cell: cell, fps: fps) != null) {
              expect(
                frame % step,
                0,
                reason: '$fps fps at ${cell}px: frame $frame is ruled but '
                    'the walk steps by $step',
              );
            }
          }
        }
      }
    });
  });

  test('the over-block ink darkens the paper, never glows over it (D32)', () {
    const paper = Color(0xFF5B8DD9); // the blue block of the report
    Color channelFloor(Color a, Color b) => Color.from(
      alpha: 1,
      red: a.r < b.r ? a.r : b.r,
      green: a.g < b.g ? a.g : b.g,
      blue: a.b < b.b ? a.b : b.b,
    );

    for (final ink in [
      timelineGridBaseLineInk(scheme),
      timelineGridSixLineInk(scheme),
      timelineGridSecondLineInk(),
    ]) {
      final onGround = timelineGridLineInkOnGround(ink, paper);
      expect(onGround.a, 1.0, reason: 'baked opaque — no blend op needed');
      final floor = channelFloor(paper, onGround);
      // Multiply can only darken: every channel of the result is at most
      // the paper's own.
      expect(onGround.r, lessThanOrEqualTo(paper.r + 1e-6));
      expect(onGround.g, lessThanOrEqualTo(paper.g + 1e-6));
      expect(onGround.b, lessThanOrEqualTo(paper.b + 1e-6));
      expect(floor, onGround);
    }

    // The line's own alpha is the WEIGHT: the faint base line barely moves
    // the paper, the opaque second line moves it furthest.
    final baseShift =
        paper.r - timelineGridLineInkOnGround(
          timelineGridBaseLineInk(scheme),
          paper,
        ).r;
    final secondShift =
        paper.r - timelineGridLineInkOnGround(
          timelineGridSecondLineInk(),
          paper,
        ).r;
    expect(baseShift, lessThan(secondShift));
    expect(baseShift, greaterThan(0));
  });
}
