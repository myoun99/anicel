import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// D43 (유저, 2026-08-21: 「그리드 오버레이랑 블록 내부 이음매같은게 색이나
/// 생긴게 달라서 통일하고싶다」).
///
/// The ink, the position and the cadence were already one law
/// ([timeline_grid_line_law_test]); the COMPOSITE was the last thing that
/// was not. Over empty ground the overlay and the ruler laid their lines
/// source-over — lighter than the ground in a dark theme — while inside a
/// block the baked tile multiplied, always darker. One grid therefore
/// changed character wherever paper began.
///
/// These pin the missing half: every surface that knows its ground puts
/// its line through [timelineGridLineInkOnGround], the block seams' own
/// function (pinned against real seams in [timeline_block_seam_test]).
class _LineSpy implements Canvas {
  final List<({Offset from, Offset to, Color color, double strokeWidth})>
  lines = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    // The paint OBJECT is reused and mutated between draws (the ruler
    // keeps one `linePaint` for the whole pass), so the values have to be
    // read here rather than held by reference.
    lines.add((
      from: p1,
      to: p2,
      color: paint.color,
      strokeWidth: paint.strokeWidth,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final scheme = buildAppTheme().colorScheme;

  ({Offset from, Offset to, Color color, double strokeWidth}) lineAtX(
    _LineSpy spy,
    double x,
  ) => spy.lines.singleWhere((line) => line.from.dx == x && line.to.dx == x);

  // Colours are compared as the 32-bit pixels they land as: a `Paint`
  // round-trips its colour through float32, so the recomputed float64
  // expectation is never `==` even when the two print identically.
  Matcher paintsAs(Color expected) => predicate<Color>(
    (actual) => actual.toARGB32() == expected.toARGB32(),
    'paints as ${expected.toARGB32().toRadixString(16)}',
  );

  group('the beat-lines overlay composites onto its host surface', () {
    _LineSpy paintOverlay({required Color? ground}) {
      final spy = _LineSpy();
      TimelineBeatLinesPainter(
        frameCellExtent: 24,
        framesPerSecond: 24,
        colorScheme: scheme,
        ground: ground,
      ).paint(spy, const Size(24 * 30, 100));
      return spy;
    }

    test('base, 6f and second lines all land as the block-seam ink would', () {
      const ground = Color(0xFF2A2A2E);
      final spy = paintOverlay(ground: ground);

      for (final probe in [
        (frame: 5, ink: timelineGridBaseLineInk(scheme)),
        (frame: 6, ink: timelineGridSixLineInk(scheme)),
        (frame: 24, ink: timelineGridSecondLineInk()),
      ]) {
        final line = lineAtX(
          spy,
          timelineFrameBoundaryLinePosition(probe.frame, 24),
        );
        expect(
          line.color,
          paintsAs(timelineGridLineInkOnGround(probe.ink, ground)),
          reason:
              'frame ${probe.frame}: the law\'s over-ground treatment, the '
              'same one a block interior gets',
        );
        expect(line.strokeWidth, probe.ink.strokeWidth);
        expect(
          line.color,
          isNot(paintsAs(probe.ink.color)),
          reason: 'fixture premise: the composite actually moves the colour',
        );
      }
    });

    test('a multiplied line can only DARKEN the ground — never the glow '
        'source-over gave it', () {
      const ground = Color(0xFF2A2A2E);
      final spy = paintOverlay(ground: ground);
      expect(spy.lines, isNotEmpty);
      for (final line in spy.lines) {
        expect(line.color.r, lessThanOrEqualTo(ground.r + 1e-6));
        expect(line.color.g, lessThanOrEqualTo(ground.g + 1e-6));
        expect(line.color.b, lessThanOrEqualTo(ground.b + 1e-6));
        expect(line.color.a, 1.0, reason: 'the composite is resolved here');
      }
    });

    test('the ROW seam takes the same treatment — it is a grid line too', () {
      const ground = Color(0xFF2A2A2E);
      final spy = _LineSpy();
      TimelineBeatLinesPainter(
        frameCellExtent: 24,
        framesPerSecond: 24,
        colorScheme: scheme,
        ground: ground,
        crossCellExtent: 40,
      ).paint(spy, const Size(240, 100));

      final seam = spy.lines.singleWhere(
        (line) => line.from.dy == 40 && line.to.dy == 40,
      );
      expect(
        seam.color,
        paintsAs(
          timelineGridLineInkOnGround((
            color: scheme.outlineVariant,
            strokeWidth: 1.0,
          ), ground),
        ),
      );
    });

    test('a null ground keeps the raw ink — the folded row\'s overlay lies '
        'over ARTWORK, which is no single colour to multiply against', () {
      final spy = paintOverlay(ground: null);
      expect(
        lineAtX(spy, timelineFrameBoundaryLinePosition(6, 24)).color,
        paintsAs(timelineGridSixLineInk(scheme).color),
      );
    });
  });

  group('the frame ruler composites onto the header it just filled', () {
    _LineSpy paintRuler({int currentFrameIndex = -1}) {
      final spy = _LineSpy();
      TimelineFrameRulerPainter(
        frameStartIndex: 0,
        frameEndIndexExclusive: 30,
        currentFrameIndex: currentFrameIndex,
        playbackFrameCount: 30,
        leadingFrameSpacerWidth: 0,
        metrics: const TimelineGridMetrics(frameCellWidth: 24),
        colorScheme: scheme,
      ).paint(spy, const Size(24 * 30, 28));
      return spy;
    }

    test('the ruler\'s grid lines stop being lighter than the body\'s', () {
      final spy = paintRuler();
      final ink = timelineGridSixLineInk(scheme);
      final line = lineAtX(spy, timelineFrameBoundaryLinePosition(6, 24));
      expect(
        line.color,
        paintsAs(timelineGridLineInkOnGround(ink, scheme.surface)),
        reason: 'PASS 1 filled this header with surface — that is the ground',
      );
      expect(line.color, isNot(paintsAs(ink.color)));
    });

    test('the SELECTED header\'s line multiplies onto ITS tint, not onto the '
        'plain surface beside it', () {
      final spy = paintRuler(currentFrameIndex: 6);
      final selectedGround = TimelineFrameRulerPainter(
        frameStartIndex: 0,
        frameEndIndexExclusive: 30,
        currentFrameIndex: 6,
        playbackFrameCount: 30,
        leadingFrameSpacerWidth: 0,
        metrics: const TimelineGridMetrics(frameCellWidth: 24),
        colorScheme: scheme,
      ).headerModelAt(6).background;
      expect(
        selectedGround,
        isNot(scheme.surface),
        reason: 'fixture premise: the current frame\'s header is tinted',
      );
      expect(
        lineAtX(spy, timelineFrameBoundaryLinePosition(6, 24)).color,
        paintsAs(
          timelineGridLineInkOnGround(
            timelineGridSixLineInk(scheme),
            selectedGround,
          ),
        ),
      );
    });
  });

  test('the two surfaces answer a shared boundary with the SAME pixel when '
      'they share a ground', () {
    // The point of the round, stated as one comparison: overlay and ruler
    // over the same paper, same boundary, same colour and width.
    final overlay = _LineSpy();
    TimelineBeatLinesPainter(
      frameCellExtent: 24,
      framesPerSecond: 24,
      colorScheme: scheme,
      ground: scheme.surface,
    ).paint(overlay, const Size(24 * 30, 100));

    final ruler = _LineSpy();
    TimelineFrameRulerPainter(
      frameStartIndex: 0,
      frameEndIndexExclusive: 30,
      currentFrameIndex: -1,
      playbackFrameCount: 30,
      leadingFrameSpacerWidth: 0,
      metrics: const TimelineGridMetrics(frameCellWidth: 24),
      colorScheme: scheme,
    ).paint(ruler, const Size(24 * 30, 28));

    for (final frame in [5, 6, 24]) {
      final x = timelineFrameBoundaryLinePosition(frame, 24);
      expect(lineAtX(overlay, x).color, paintsAs(lineAtX(ruler, x).color));
      expect(lineAtX(overlay, x).strokeWidth, lineAtX(ruler, x).strokeWidth);
    }
  });
}
