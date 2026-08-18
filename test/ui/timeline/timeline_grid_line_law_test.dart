import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineBaseGridAlpha, timelineGridLineEveryFrames;

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

  test('the position convention is boundary + the ruler\'s own half-pixel '
      'snap (D8)', () {
    expect(timelineFrameBoundaryLinePosition(0, 24), timelineGridLineSnap);
    expect(timelineFrameBoundaryLinePosition(6, 24), 144 + 0.5);
    expect(timelineFrameBoundaryLinePosition(3, 7.5), 22.5 + 0.5);
  });

  test('cadence thins the base line but never the beats — the one answer '
      'D38 makes every surface share', () {
    // At an 8px cell the cadence is > 1, so a plain boundary thins out…
    final cadence = timelineGridLineEveryFrames(8);
    expect(cadence, greaterThan(1), reason: 'fixture premise');
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 1,
        frameCellExtent: 8,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      isNull,
    );
    // …while the 6f beat stays.
    expect(
      timelineFrameBoundaryLineInk(
        frameIndex: 6,
        frameCellExtent: 8,
        framesPerSecond: 24,
        colorScheme: scheme,
      ),
      isNotNull,
    );
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
