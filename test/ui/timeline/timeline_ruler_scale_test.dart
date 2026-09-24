import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineMarkGap;
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart'
    show XSheetFrameRailPainter;

import '../../helpers/app_faces.dart';

/// The frame SCALE the ruler and the X-sheet's rail both draw, as one value
/// object (the audit's clone scan, 2026-09-06): the eleven inputs, their
/// equality (the painters' shouldRepaint), the visible window and the
/// frame-number label used to live on each painter separately.
void main() {
  final light = ThemeData.light().colorScheme;
  final dark = ThemeData.dark().colorScheme;

  TimelineRulerScale scale({
    Axis axis = Axis.horizontal,
    int frameStartIndex = 0,
    int frameEndIndexExclusive = 30,
    int currentFrameIndex = -1,
    int playbackFrameCount = 30,
    double leadingFrameSpacer = 0,
    double crossExtent = 28,
    TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
    ColorScheme? colorScheme,
    int framesPerSecond = 24,
    bool showSeconds = false,
    ValueNotifier<int>? windowBucket,
    double viewportMainExtent = 0,
    Color? pastPlaybackWash,
    TimelineRulerNumberType numberType = TimelineFrameRulerPainter.numberType,
    TextStyle face = const TextStyle(),
  }) => TimelineRulerScale(
    axis: axis,
    frameStartIndex: frameStartIndex,
    frameEndIndexExclusive: frameEndIndexExclusive,
    currentFrameIndex: currentFrameIndex,
    playbackFrameCount: playbackFrameCount,
    leadingFrameSpacer: leadingFrameSpacer,
    crossExtent: crossExtent,
    metrics: metrics,
    colorScheme: colorScheme ?? light,
    face: face,
    numberType: numberType,
    framesPerSecond: framesPerSecond,
    showSeconds: showSeconds,
    windowBucket: windowBucket,
    viewportMainExtent: viewportMainExtent,
    pastPlaybackWash: pastPlaybackWash,
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
        scale(axis: Axis.vertical),
        scale(crossExtent: 72),
        scale(pastPlaybackWash: const Color(0xFF123456)),
        scale(numberType: XSheetFrameRailPainter.numberType),
        scale(face: const TextStyle(fontFamily: 'Face')),
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

  group('modelAt — the model the ruler and the rail both read', () {
    test('the label follows the cadence, and the seconds line the second '
        'boundaries', () {
      // 8px cells: two digits fit three of them, so every third frame
      // carries its number (I-22 — the numbers are measured, not the cell).
      final wide = scale(
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 8),
      );
      expect(wide.labelEveryFrames, 3, reason: 'fixture premise');
      expect(wide.modelAt(0).label, '1');
      expect(wide.modelAt(6).label, '7');
      expect(wide.modelAt(7).label, '');
      expect(wide.modelAt(24).secondsLabel, '1');
      expect(wide.modelAt(25).secondsLabel, '');
    });

    test('the current frame is selected and takes the tint, wash or no '
        'wash', () {
      final ruler = scale(currentFrameIndex: 6);
      expect(ruler.modelAt(6).selected, isTrue);
      expect(ruler.modelAt(5).selected, isFalse);
      expect(ruler.modelAt(6).background, isNot(light.surface));
      // Selection outranks the wash: a selected frame past the playback
      // range still reads as the one you are standing on.
      expect(
        scale(
          currentFrameIndex: 40,
          playbackFrameCount: 30,
          pastPlaybackWash: const Color(0xFF00FF00),
        ).modelAt(40).background,
        isNot(const Color(0xFF00FF00)),
      );
    });

    test('⛔the RULER takes no past-playback wash (UI-R18 #9) while the '
        'RAIL does — that is the whole difference between them', () {
      final past = scale(playbackFrameCount: 30);
      expect(past.modelAt(31).outsidePlaybackRange, isTrue);
      // No wash on the scale: the strip stays plain, which is the ruler.
      expect(past.modelAt(31).background, light.surface);
      // A wash on the scale: the row grays, which is the rail.
      const wash = Color(0xFF00FF00);
      final washed = scale(playbackFrameCount: 30, pastPlaybackWash: wash);
      expect(washed.modelAt(31).background, wash);
      // And the wash reaches ONLY the frames past the range.
      expect(washed.modelAt(29).background, light.surface);
    });
  });

  group('labelEveryFrames — a number thins only where it would touch the '
      'next (I-22)', () {
    double widest(TextStyle type, int digits) => [
      for (var digit = 0; digit <= 9; digit += 1)
        timelineGlyphPainter('$digit' * digits, type).width,
    ].reduce(math.max);

    test('the densest rung the widest number fits, with its gap', () {
      for (final frames in [9, 30, 120, 1200]) {
        for (final cell in [4.0, 6.0, 8.0, 12.0, 16.0, 20.0, 23.0, 24.0, 36.0]) {
          final ruler = scale(
            frameEndIndexExclusive: frames,
            playbackFrameCount: frames,
            metrics: TimelineGridMetrics.defaults.copyWith(
              frameCellWidth: cell,
            ),
          );
          final digits = '$frames'.length;
          bool fits(int stride) =>
              widest(ruler.numberTypeAt(everyFrame: stride == 1), digits) +
                  timelineMarkGap <=
              stride * cell;
          final every = ruler.labelEveryFrames;
          final where = '$frames frames at ${cell}px';
          expect(fits(every), isTrue, reason: '$where: the rung holds it');
          final index = timelineFrameStrideLadder.indexOf(every);
          if (index > 0) {
            expect(
              fits(timelineFrameStrideLadder[index - 1]),
              isFalse,
              reason: '$where: the denser rung would touch',
            );
          }
        }
      }
    });

    test('in seconds mode the longest number is the fps, not the frame '
        'count', () {
      TimelineRulerScale at8({required bool seconds}) => scale(
        frameEndIndexExclusive: 1200,
        playbackFrameCount: 1200,
        showSeconds: seconds,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 8),
      );
      expect(
        at8(seconds: true).labelEveryFrames,
        lessThan(at8(seconds: false).labelEveryFrames),
      );
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

  // The ruler and the rail wrote the same two sentences, one with the frame
  // axis across and one with it down. They live on the scale now, so these
  // ask the transposed question and demand the transposed answer.
  group('cellRectFor turns with the axis', () {
    const cell = TimelineGridMetrics.defaults;

    test('the horizontal strip lays cells across and fills its height', () {
      final rect = scale(
        leadingFrameSpacer: 10,
        frameStartIndex: 2,
        crossExtent: 28,
      ).cellRectFor(5);
      expect(rect.left, 10 + 3 * cell.frameCellWidth);
      expect(rect.width, cell.frameCellWidth);
      expect(rect.top, 0);
      expect(rect.height, 28);
    });

    test('the vertical strip is that rect transposed, exactly', () {
      final across = scale(
        leadingFrameSpacer: 10,
        frameStartIndex: 2,
        crossExtent: 28,
      ).cellRectFor(5);
      final down = scale(
        axis: Axis.vertical,
        leadingFrameSpacer: 10,
        frameStartIndex: 2,
        crossExtent: 28,
      ).cellRectFor(5);
      expect(down.top, across.left);
      expect(down.height, across.width);
      expect(down.left, across.top);
      expect(down.width, across.height);
    });

    test('a strip with a different thickness keeps the same cells', () {
      final thin = scale(crossExtent: 28).cellRectFor(9);
      final thick = scale(crossExtent: 72).cellRectFor(9);
      expect(thick.left, thin.left);
      expect(thick.width, thin.width);
      expect(thick.height, 72);
    });
  });

  group('modelAt is one law, and the wash is a value', () {
    test('label, seconds line and states do not know the axis', () {
      // At 24px both strips write every frame, so the labels agree across
      // and down; the cadence is measured ALONG the axis (I-22), the one
      // thing the axis may change about a label.
      for (final frame in [0, 1, 24, 25]) {
        final across = scale(currentFrameIndex: 24).modelAt(frame);
        final down = scale(
          axis: Axis.vertical,
          currentFrameIndex: 24,
        ).modelAt(frame);
        expect(down.label, across.label, reason: 'frame $frame');
        expect(down.secondsLabel, across.secondsLabel, reason: 'frame $frame');
        expect(down.selected, across.selected, reason: 'frame $frame');
        expect(
          down.outsidePlaybackRange,
          across.outsidePlaybackRange,
          reason: 'frame $frame',
        );
        expect(down.background, across.background, reason: 'frame $frame');
      }
    });

    test('⛔with no wash the tail is the strip\'s own paper (UI-R18 #9)', () {
      final model = scale(playbackFrameCount: 10).modelAt(20);
      expect(model.outsidePlaybackRange, isTrue, reason: 'fixture premise');
      expect(model.background, light.surface);
    });

    test('with a wash the tail takes it — the same code, a different '
        'value', () {
      const wash = Color(0xFF123456);
      final model = scale(
        playbackFrameCount: 10,
        pastPlaybackWash: wash,
      ).modelAt(20);
      expect(model.background, wash);
    });

    test('and the wash reaches ONLY the tail: a cell inside the playback '
        'range keeps the paper', () {
      const wash = Color(0xFF123456);
      final model = scale(
        playbackFrameCount: 10,
        pastPlaybackWash: wash,
      ).modelAt(3);
      expect(model.outsidePlaybackRange, isFalse, reason: 'fixture premise');
      expect(model.background, light.surface);
    });

    test('the CURRENT frame outranks the wash: it is tinted, not washed', () {
      const wash = Color(0xFF123456);
      final model = scale(
        playbackFrameCount: 10,
        currentFrameIndex: 20,
        pastPlaybackWash: wash,
      ).modelAt(20);
      expect(model.selected, isTrue);
      expect(model.background, isNot(wash));
      expect(model.background, isNot(light.surface));
    });
  });

  group('both strips write in the app\'s face (「앱은 한 글꼴」, 08-28)', () {
    const biz = TextStyle(fontFamily: 'BIZ UDPGothic');

    test('every number and second either strip writes is in its face', () {
      for (final (strip, numberType, glyphsAt) in [
        (
          'ruler',
          TimelineFrameRulerPainter.numberType,
          TimelineFrameRulerPainter.glyphsAt,
        ),
        (
          'rail',
          XSheetFrameRailPainter.numberType,
          XSheetFrameRailPainter.glyphsAt,
        ),
      ]) {
        final written = scale(face: biz, numberType: numberType);
        for (final current in [false, true]) {
          // Frame 25 starts the second second: a number and a second.
          final glyphs = glyphsAt(written, 24, current: current);
          expect(glyphs, hasLength(2), reason: '$strip: the premise');
          for (final glyph in glyphs) {
            expect(
              glyph.painter.text!.style!.fontFamily,
              'BIZ UDPGothic',
              reason:
                  '$strip (playhead: $current) — a type set from scratch '
                  'names no face and writes in the OS\'s',
            );
          }
        }
      }
    });

    testWidgets('the cadence measures in the face it paints', (tester) async {
      await loadTheAppFaces();
      // The cell that holds a three-digit number a frame in the app's face
      // — and not in the test font's, whose every digit is an em wide. A
      // measure that left the face out would thin, or crowd, numbers the
      // strip sets in another width than it measured.
      double widestIn(TextStyle face) => [
        for (var digit = 0; digit <= 9; digit += 1)
          (TextPainter(
            text: TextSpan(
              text: '$digit' * 3,
              style: face.copyWith(fontSize: 11),
            ),
            textDirection: TextDirection.ltr,
          )..layout()).width,
      ].reduce(math.max);
      final cell = (widestIn(biz) + timelineMarkGap).ceilToDouble();
      expect(
        widestIn(const TextStyle()) + timelineMarkGap,
        greaterThan(cell),
        reason: 'the premise: the test font cannot write every frame here',
      );
      TimelineRulerScale hundredFrames(TextStyle face) => scale(
        face: face,
        frameEndIndexExclusive: 100,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
      );
      expect(hundredFrames(const TextStyle()).labelEveryFrames, greaterThan(1));
      expect(hundredFrames(biz).labelEveryFrames, 1);
    });
  });
}
