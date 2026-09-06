import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// The frame SCALE the ruler and the X-sheet's rail both draw, as one value
/// object (the audit's clone scan, 2026-09-06): the eleven inputs, their
/// equality (the painters' shouldRepaint), the visible window and the
/// frame-number label used to live on each painter separately.
void main() {
  final light = ThemeData.light().colorScheme;
  final dark = ThemeData.dark().colorScheme;

  TimelineRulerScale scale({
    int frameStartIndex = 0,
    int frameEndIndexExclusive = 30,
    int currentFrameIndex = -1,
    int playbackFrameCount = 30,
    double leadingFrameSpacer = 0,
    TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
    ColorScheme? colorScheme,
    int framesPerSecond = 24,
    bool showSeconds = false,
    ValueNotifier<int>? windowBucket,
    double viewportMainExtent = 0,
  }) => TimelineRulerScale(
    frameStartIndex: frameStartIndex,
    frameEndIndexExclusive: frameEndIndexExclusive,
    currentFrameIndex: currentFrameIndex,
    playbackFrameCount: playbackFrameCount,
    leadingFrameSpacer: leadingFrameSpacer,
    metrics: metrics,
    colorScheme: colorScheme ?? light,
    framesPerSecond: framesPerSecond,
    showSeconds: showSeconds,
    windowBucket: windowBucket,
    viewportMainExtent: viewportMainExtent,
  );

  group('equality is the repaint gate', () {
    test('the same inputs compare equal and hash equal', () {
      expect(scale(), scale());
      expect(scale().hashCode, scale().hashCode);
    });

    test('every value field takes part', () {
      final base = scale();
      for (final other in [
        scale(frameStartIndex: 1),
        scale(frameEndIndexExclusive: 31),
        scale(currentFrameIndex: 3),
        scale(playbackFrameCount: 12),
        scale(leadingFrameSpacer: 96),
        scale(
          metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 12),
        ),
        scale(colorScheme: dark),
        scale(framesPerSecond: 30),
        scale(showSeconds: true),
        scale(viewportMainExtent: 400),
      ]) {
        expect(other, isNot(base), reason: '$other');
      }
    });

    test('the colour scheme is value-compared, never identical: a fresh '
        'instance of the same scheme does not repaint the strip', () {
      final fresh = light.copyWith();
      expect(identical(fresh, light), isFalse, reason: 'fixture premise');
      expect(scale(colorScheme: fresh), scale(colorScheme: light));
    });

    test('the window bucket is compared by identity — the painter is '
        'subscribed to that one notifier', () {
      final bucket = ValueNotifier<int>(0);
      final twin = ValueNotifier<int>(0);
      expect(scale(windowBucket: bucket), scale(windowBucket: bucket));
      expect(scale(windowBucket: bucket), isNot(scale(windowBucket: twin)));
      expect(scale(windowBucket: bucket), isNot(scale()));
    });
  });

  group('visibleWindow', () {
    test('without a bucket it is the full bounds', () {
      final window = scale(
        frameStartIndex: 2,
        frameEndIndexExclusive: 9,
      ).visibleWindow();
      expect(window.startIndex, 2);
      expect(window.endIndexExclusive, 9);
    });

    test('with a bucket it clips the bucket window to the bounds', () {
      final window = scale(
        frameEndIndexExclusive: 1000,
        windowBucket: ValueNotifier<int>(3),
        viewportMainExtent: 240,
      ).visibleWindow();
      expect(window.startIndex, greaterThan(0));
      expect(window.endIndexExclusive, lessThan(1000));
      expect(window.startIndex, lessThan(window.endIndexExclusive));
    });
  });

  group('frameNumberLabel', () {
    test('counts absolute 1-based frames', () {
      expect(scale().frameNumberLabel(0), '1');
      expect(scale().frameNumberLabel(24), '25');
    });

    test('in seconds mode it repeats 1..fps per second', () {
      final seconds = scale(showSeconds: true);
      expect(seconds.frameNumberLabel(0), '1');
      expect(seconds.frameNumberLabel(23), '24');
      expect(seconds.frameNumberLabel(24), '1');
    });

    test('a non-positive fps falls back to 24', () {
      expect(
        scale(showSeconds: true, framesPerSecond: 0).frameNumberLabel(25),
        '2',
      );
    });
  });
}
