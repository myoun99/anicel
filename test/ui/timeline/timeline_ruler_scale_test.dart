import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/word_condensation.dart' show wordFitsAsItIs;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineFrameBoundaryLineInk, timelineGridLineSnap, timelineMarkGap;
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_second.dart'
    show timelineSecondStrideLadder;
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
    secondsFontSize: axis == Axis.horizontal ? 9 : 8,
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
          bool fits(int stride) {
            final type = ruler.numberTypeAt(everyFrame: stride == 1);
            final width = widest(type, digits);
            // A number in a cell of its own narrows into it — as far as
            // half-width (ruler-digits-in-the-app-face-Q1).
            final needs = stride == 1
                ? math.min(
                    width,
                    digits * type.fontSize! * timelineNumberNarrowestEm,
                  )
                : width;
            return needs + timelineMarkGap <= stride * cell;
          }
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
      // Past every frame a number is written at its own width, so its face
      // picks the rung: the cell three of which hold one `000` in the app's
      // face — and not in the test font's, whose every digit is an em wide.
      // A measure that left the face out would thin, or crowd, numbers the
      // strip sets in another width than it measured.
      double widestIn(TextStyle face) => [
        for (var digit = 0; digit <= 9; digit += 1)
          (TextPainter(
            text: TextSpan(
              text: '$digit' * 3,
              style: face.copyWith(fontSize: 10),
            ),
            textDirection: TextDirection.ltr,
          )..layout()).width,
      ].reduce(math.max);
      final cell = (widestIn(biz) + timelineMarkGap) / 3;
      expect(
        widestIn(const TextStyle()) + timelineMarkGap,
        greaterThan(3 * cell),
        reason: 'the premise: the test font needs a sparser rung here',
      );
      TimelineRulerScale hundredFrames(TextStyle face) => scale(
        face: face,
        frameEndIndexExclusive: 100,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
      );
      expect(hundredFrames(biz).labelEveryFrames, 3);
      expect(hundredFrames(const TextStyle()).labelEveryFrames, greaterThan(3));
    });
  });

  group('a number written in a cell of its own narrows into it — as far as '
      'half-width (ruler-digits-in-the-app-face-Q1)', () {
    test('three digits hold every frame at 24px, each inside its own cell', () {
      // In the test font `100` set at 11 is 33px: too wide for its 24px
      // cell as it is set, not at half-width.
      final ruler = scale(frameEndIndexExclusive: 144, playbackFrameCount: 144);
      expect(ruler.labelEveryFrames, 1);
      for (final frame in [99, 100, 143]) {
        final number = TimelineFrameRulerPainter.glyphsAt(
          ruler,
          frame,
          current: false,
        ).first;
        final cell = ruler.cellRectFor(frame);
        expect(number.painter.plainText, '${frame + 1}');
        expect(number.fit.x, lessThan(1), reason: 'frame ${frame + 1}');
        expect(number.fit.y, 1, reason: 'its height never');
        expect(
          number.rect.width,
          lessThanOrEqualTo(cell.width - timelineMarkGap + 1e-9),
          reason: 'frame ${frame + 1} stays off its neighbours',
        );
        expect(number.rect.center.dx, closeTo(cell.center.dx, 1e-9));
      }
    });

    test('the number the ruler PAINTS is the narrowed one', () {
      // A placement that says narrow and a paint that draws wide would pass
      // every test that reads the placement.
      final ruler = scale(frameEndIndexExclusive: 144, playbackFrameCount: 144);
      final drawn = _DrawnWidths();
      TimelineFrameRulerPainter(scale: ruler).paint(drawn, const Size(3456, 28));
      final numbers = drawn.widths.where((width) => width > 12).toList();
      expect(numbers, isNotEmpty, reason: 'the premise: three digits drawn');
      for (final width in numbers) {
        expect(width, lessThanOrEqualTo(24 - timelineMarkGap + 1e-9));
      }
    });

    test('a number that fits its cell keeps its width', () {
      final ruler = scale();
      final number = TimelineFrameRulerPainter.glyphsAt(
        ruler,
        29,
        current: false,
      ).first;
      expect(number.painter.plainText, '30');
      expect(number.fit, wordFitsAsItIs);
    });

    test('the rail narrows a number wider than itself, and centres it', () {
      final rail = scale(
        axis: Axis.vertical,
        numberType: XSheetFrameRailPainter.numberType,
        frameEndIndexExclusive: 1200,
        playbackFrameCount: 1200,
      );
      final number = XSheetFrameRailPainter.glyphsAt(
        rail,
        999,
        current: false,
      ).last;
      final row = rail.cellRectFor(999);
      expect(number.painter.plainText, '1000');
      expect(number.fit.x, lessThan(1));
      expect(
        number.rect.width,
        lessThanOrEqualTo(row.width - timelineMarkGap + 1e-9),
      );
      expect(number.rect.center.dx, closeTo(row.center.dx, 1e-9));
    });
  });

  group('I-22: at the ten-minute floor the strip writes and papers in '
      'stretches', () {
    const cell = 1 / 8;
    TimelineRulerScale wide({
      Axis axis = Axis.horizontal,
      double cellExtent = cell,
      int frameStartIndex = 0,
    }) => scale(
      axis: axis,
      metrics: TimelineGridMetrics.defaults.copyWith(
        frameCellWidth: cellExtent,
      ),
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: 14400,
      playbackFrameCount: 14400,
      numberType: axis == Axis.horizontal
          ? TimelineFrameRulerPainter.numberType
          : XSheetFrameRailPainter.numberType,
    );
    TimelineRulerGlyphLayout layoutOf(Axis axis) => axis == Axis.horizontal
        ? TimelineFrameRulerPainter.glyphsAt
        : XSheetFrameRailPainter.glyphsAt;

    test('the seconds thin on their ladder where a second cannot hold its '
        'mark', () {
      final strip = wide();
      final every = strip.secondsLabelEverySeconds;
      expect(every, greaterThan(1));
      expect(timelineSecondStrideLadder, contains(every));
      expect(strip.modelAt(0).secondsLabel, '0');
      expect(strip.modelAt(24 * every).secondsLabel, '$every');
      expect(
        strip.modelAt(24).secondsLabel,
        isEmpty,
        reason: 'second 1 is off the rung',
      );
    });

    test('every second still writes at every zoom the old floor allowed', () {
      for (final atLeast in [2.4, 24.0]) {
        expect(
          scale(
            metrics: TimelineGridMetrics.defaults.copyWith(
              frameCellWidth: atLeast,
            ),
            frameEndIndexExclusive: 14400,
          ).secondsLabelEverySeconds,
          1,
          reason: '${atLeast}px',
        );
      }
    });

    test('every frame a strip writes at is on its writing step', () {
      for (final axis in Axis.values) {
        final strip = wide(axis: axis);
        final step = strip.writingStep;
        for (var frame = 0; frame < 14400; frame += 1) {
          final writing = strip.writingAt(frame, current: false);
          if (writing.number.isNotEmpty || writing.second.isNotEmpty) {
            expect(frame % step, 0, reason: '$axis frame $frame');
          }
        }
      }
    });

    test('no two seconds a strip writes stand closer than the mark gap', () {
      // A sweep, not the floor alone: the gap decides the rung only in the
      // band where a second holds its widest mark but not the gap as well.
      for (final axis in Axis.values) {
        for (var step = 10; step <= 500; step += 1) {
          final strip = wide(axis: axis, cellExtent: step / 200);
          Rect? previous;
          var closest = double.infinity;
          for (var second = 100; second < 300; second += 1) {
            final text = strip.writingAt(second * 24, current: false).second;
            if (text.isEmpty) {
              continue;
            }
            final rect = layoutOf(axis)(strip, second * 24, current: false)
                .singleWhere((glyph) => glyph.painter.plainText == text)
                .rect;
            if (previous != null) {
              closest = math.min(
                closest,
                axis == Axis.horizontal
                    ? rect.left - previous.right
                    : rect.top - previous.bottom,
              );
            }
            previous = rect;
          }
          expect(
            closest,
            greaterThanOrEqualTo(timelineMarkGap - 1e-9),
            reason: '$axis at ${step / 200}px',
          );
        }
      }
    });

    test('a strip paints every mark its window holds, whatever frame the '
        'window starts on', () {
      for (final axis in Axis.values) {
        final strip = wide(axis: axis, frameStartIndex: 7);
        final drawn = _DrawnWidths();
        (axis == Axis.horizontal
                ? TimelineFrameRulerPainter(scale: strip)
                : XSheetFrameRailPainter(scale: strip))
            .paint(drawn, const Size(1800, 28));
        var written = 0;
        for (var frame = 7; frame < 14400; frame += 1) {
          written += layoutOf(axis)(strip, frame, current: false).length;
        }
        expect(written, greaterThan(0), reason: 'the premise: $axis writes');
        expect(drawn.widths, hasLength(written), reason: '$axis');
      }
    });

    test('both strips give a node where they write a number and nowhere '
        'else — the rail\'s every row went with its every-row numbers', () {
      for (final axis in Axis.values) {
        final strip = wide(axis: axis, frameStartIndex: 7);
        final nodes =
            (axis == Axis.horizontal
                    ? TimelineFrameRulerPainter(scale: strip)
                    : XSheetFrameRailPainter(scale: strip))
                .semanticsBuilder!(const Size(1800, 28));
        final numbered = [
          for (var frame = 7; frame < 14400; frame += 1)
            if (strip.modelAt(frame).label.isNotEmpty) 'frame ${frame + 1}',
        ];
        expect(numbered, isNotEmpty, reason: 'the premise: $axis numbers');
        expect(
          nodes.map((node) => node.properties.label),
          numbered,
          reason: '$axis',
        );
      }
    });

    test('the paper is one rect per ground: the selected cell and the '
        'playback end are its only edges', () {
      final strip = scale(
        axis: Axis.vertical,
        currentFrameIndex: 10,
        playbackFrameCount: 50,
        frameEndIndexExclusive: 100,
        pastPlaybackWash: const Color(0xFF123456),
      );
      final canvas = _Rects();
      strip.paintPaperIn(canvas, (startIndex: 0, endIndexExclusive: 100));

      expect(canvas.rects.map((rect) => rect.color.toARGB32()), [
        strip.modelAt(0).background.toARGB32(),
        strip.modelAt(10).background.toARGB32(),
        strip.modelAt(11).background.toARGB32(),
        strip.modelAt(50).background.toARGB32(),
      ]);
      expect(canvas.rects.first.rect, strip.cellRectFor(0).expandToInclude(
        strip.cellRectFor(9),
      ));
      expect(canvas.rects.last.rect, strip.cellRectFor(50).expandToInclude(
        strip.cellRectFor(99),
      ));
    });

    test('the paper rules every line the law rules, whatever frame a '
        'stretch starts on', () {
      for (final axis in Axis.values) {
        // The selected cell and the playback end cut the paper at 10, 11
        // and 50 — none of them on the lines' step at this zoom.
        final strip = scale(
          axis: axis,
          metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
          currentFrameIndex: 10,
          playbackFrameCount: 50,
          frameEndIndexExclusive: 1000,
        );
        final lines = _Lines();
        strip.paintPaperIn(lines, (startIndex: 0, endIndexExclusive: 1000));

        double edgeOf(int frame) {
          final rect = strip.cellRectFor(frame);
          return (axis == Axis.horizontal ? rect.left : rect.top) +
              timelineGridLineSnap;
        }

        final ruled = [
          for (var frame = 0; frame < 1000; frame += 1)
            if (timelineFrameBoundaryLineInk(
                  frameIndex: frame,
                  frameCellExtent: cell,
                  framesPerSecond: 24,
                  colorScheme: strip.colorScheme,
                ) !=
                null)
              edgeOf(frame),
        ];
        double along(Offset start) =>
            axis == Axis.horizontal ? start.dx : start.dy;
        expect(ruled.length, greaterThan(2), reason: 'the premise');
        expect(lines.starts.map(along), ruled, reason: '$axis');
      }
    });
  });
}

/// Every line drawn, by where it starts.
class _Lines implements Canvas {
  final starts = <Offset>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => starts.add(p1);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Every rect laid, with the colour it was laid in.
class _Rects implements Canvas {
  final rects = <({Rect rect, Color color})>[];

  @override
  void drawRect(Rect rect, Paint paint) =>
      rects.add((rect: rect, color: paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The width every paragraph is DRAWN at — through the canvas's scale, since
/// a narrowed number is drawn at the origin of a scaled canvas.
class _DrawnWidths implements Canvas {
  final widths = <double>[];
  final _saved = <double>[];
  var _scaleX = 1.0;

  @override
  void save() => _saved.add(_scaleX);

  @override
  void restore() => _scaleX = _saved.removeLast();

  @override
  void scale(double sx, [double? sy]) => _scaleX *= sx;

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      widths.add(paragraph.maxIntrinsicWidth * _scaleX);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
