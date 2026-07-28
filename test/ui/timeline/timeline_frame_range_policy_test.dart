import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/timeline/timeline_defaults.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_policy.dart';

void main() {
  group('TimelineFrameRange', () {
    test('defines default cut and safety frame counts (the safety tail is '
        'RETIRED to zero — UI-R10 #23, the endless axis owns the past-cut '
        'frames)', () {
      expect(defaultCutDurationFrames, 24);
      expect(defaultTimelineSafetyFrameCount, 0);
    });

    test('computes visible range from playback plus safety frames', () {
      final range = TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: 24,
        safetyFrameCount: 24,
      );

      expect(range.playbackFrameCount, 24);
      expect(range.safetyFrameCount, 24);
      expect(range.visibleFrameCount, 48);
      expect(range.playbackEndFrameIndexExclusive, 24);
      expect(range.visibleEndFrameIndexExclusive, 48);
      expect(range.isOutsidePlaybackRange(23), isFalse);
      expect(range.isOutsidePlaybackRange(24), isTrue);
      expect(range.isOutsidePlaybackRange(45), isTrue);
    });

    test('minimum visible cells can exceed playback plus safety frames', () {
      final range = TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: 1,
        safetyFrameCount: 0,
        minimumVisibleFrameCells: 24,
      );

      expect(range.visibleFrameCount, 24);
    });
  });

  group('endlessTrailingFrames', () {
    test('materializes exactly what the scrolled view needs — ZERO runway '
        'ahead (UI-R12 #16: cells exist because they are visible)', () {
      // View edge at frame (960+480)/48 = 30 — target covers it exactly:
      // no frames beyond the edge, so the scrollbar walls right there.
      expect(
        endlessTrailingFrames(
          baseFrameCount: 20,
          currentTrailingFrames: 0,
          scrollOffset: 960,
          viewportExtent: 480,
          frameCellExtent: 48,
        ),
        10,
      );
    });

    test('an in-range view adds nothing (scroll gestures and the '
        'scrollbar cannot grow the axis)', () {
      // View edge frame 30 ≤ base 48 → target 0.
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 0,
          scrollOffset: 960,
          viewportExtent: 480,
          frameCellExtent: 48,
        ),
        0,
      );
    });

    test('a ruler edge-drag OVERSHOOT past the built extent grows it to '
        'cover the overshot view (the one growth path)', () {
      // Built extent 48+0; the pan jumped the offset so the view edge sits
      // at frame (2400+480)/48 = 60 → 12 trailing frames materialize.
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 0,
          scrollOffset: 2400,
          viewportExtent: 480,
          frameCellExtent: 48,
        ),
        12,
      );
    });

    test('never shrinks MID-GESTURE (allowShrink false)', () {
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 200,
          scrollOffset: 0,
          viewportExtent: 480,
          frameCellExtent: 48,
        ),
        200,
      );
    });

    test('shrinks back once scrolling settles (UI-R9 #11 → UI-R12 #16): '
        'past-content cells vanish once out of view', () {
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 200,
          scrollOffset: 0,
          viewportExtent: 480,
          frameCellExtent: 48,
          allowShrink: true,
        ),
        // Scrolled home: the view (10 cells) sits inside the base 48 →
        // every materialized trailing cell releases.
        0,
      );
    });

    test('shrink hysteresis: a release smaller than one viewport of frames '
        'keeps the current extent (no thumb jitter)', () {
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 6,
          scrollOffset: 0,
          viewportExtent: 480,
          frameCellExtent: 48,
          allowShrink: true,
        ),
        // Target 0; release 6 < 10 (one viewport) → hold.
        6,
      );
    });

    test('the hysteresis caps at 24 frames (UI-R13 #6): wide viewports '
        'still release their materialized tail', () {
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 30,
          scrollOffset: 0,
          viewportExtent: 4800, // 100 cells — the old threshold never fired.
          frameCellExtent: 48,
          allowShrink: true,
        ),
        // Target 100-48=52... the view itself needs the fill; with the
        // viewport wider than base the target EXCEEDS current — grow.
        52,
      );
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 30,
          scrollOffset: 0,
          viewportExtent: 1200, // 25 cells < base: pure release territory.
          frameCellExtent: 48,
          allowShrink: true,
        ),
        // Target 0; release 30 ≥ capped hysteresis 24 → shrink (the old
        // one-viewport threshold 25 would have held).
        0,
      );
    });

    test('the shrunken extent always covers the current viewport edge', () {
      final trailing = endlessTrailingFrames(
        baseFrameCount: 48,
        currentTrailingFrames: 500,
        scrollOffset: 4800,
        viewportExtent: 480,
        frameCellExtent: 48,
        allowShrink: true,
      );
      // Edge frame = (4800+480)/48 = 110; extent 48+trailing must cover it.
      expect(48 + trailing, greaterThanOrEqualTo(110));
    });

    test('zero cell extent is a no-op', () {
      expect(
        endlessTrailingFrames(
          baseFrameCount: 48,
          currentTrailingFrames: 7,
          scrollOffset: 5000,
          viewportExtent: 480,
          frameCellExtent: 0,
        ),
        7,
      );
    });
  });

  group('endlessViewportFillFrames', () {
    test('papers the viewport: however wide the cell area, cells run to '
        'its edge (UI-R12 #16)', () {
      expect(
        endlessViewportFillFrames(viewportExtent: 500, frameCellExtent: 48),
        11,
      );
      expect(
        endlessViewportFillFrames(viewportExtent: 0, frameCellExtent: 48),
        0,
      );
      expect(
        endlessViewportFillFrames(viewportExtent: 500, frameCellExtent: 0),
        0,
      );
    });
  });
}
