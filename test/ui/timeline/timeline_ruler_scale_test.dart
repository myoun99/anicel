import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/word_condensation.dart' show wordFitsAsItIs;
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineFrameBoundaryLineInk, timelineGridLineSnap, timelineMarkGap;
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/text/laid_out_glyph.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_second.dart'
    show timelineLadderRung, timelineSecondStrideLadder;
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart'
    show XSheetFrameRailPainter;

import '../../helpers/app_faces.dart';
import '../../helpers/recording_ruler_layout.dart';

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
    int playbackFrameCount = 30,
    double leadingFrameSpacer = 0,
    double crossExtent = 28,
    TimelineGridMetrics metrics = TimelineGridMetrics.defaults,
    ColorScheme? colorScheme,
    int framesPerSecond = 24,
    FrameRulerView rulerView = FrameRulerView.frames,
    int? pageFrames,
    TimelineRulerPages? pages,
    ValueNotifier<int>? windowBucket,
    double viewportMainExtent = 0,
    Color? pastPlaybackWash,
    TimelineRulerNumberType numberType = TimelineFrameRulerPainter.numberType,
    TextStyle face = const TextStyle(),
  }) => TimelineRulerScale(
    axis: axis,
    frameStartIndex: frameStartIndex,
    frameEndIndexExclusive: frameEndIndexExclusive,
    playbackFrameCount: playbackFrameCount,
    leadingFrameSpacer: leadingFrameSpacer,
    crossExtent: crossExtent,
    metrics: metrics,
    colorScheme: colorScheme ?? light,
    face: face,
    numberType: numberType,
    secondsFontSize: axis == Axis.horizontal ? 9 : 8,
    framesPerSecond: framesPerSecond,
    rulerView: rulerView,
    pages:
        pages ??
        (pageFrames == null ? null : TimelineRulerPages.every(pageFrames)),
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
        scale(playbackFrameCount: 12),
        scale(leadingFrameSpacer: 96),
        scale(
          metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 12),
        ),
        scale(colorScheme: dark),
        scale(framesPerSecond: 30),
        scale(rulerView: FrameRulerView.secondsPlusFrames),
        scale(pageFrames: 144),
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
        laidOutGlyph('$digit' * digits, type).width,
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
          // The rungs a number climbs (I-102): the ladder's that divide a
          // second, then the seconds' marks, every one, two, three …
          final marks = 24 * ruler.secondsLabelEverySeconds;
          final rungs = [
            for (final stride in timelineFrameStrideLadder)
              if (stride < 24 && 24 % stride == 0) stride,
            for (var times = 1; times <= frames; times += 1) marks * times,
          ];
          final every = ruler.labelEveryFrames;
          final where = '$frames frames at ${cell}px';
          expect(rungs, contains(every), reason: '$where: a rung');
          expect(fits(every), isTrue, reason: '$where: the rung holds it');
          final index = rungs.indexOf(every);
          if (index > 0) {
            expect(
              fits(rungs[index - 1]),
              isFalse,
              reason: '$where: the denser rung would touch',
            );
          }
        }
      }
    });

    test('F-385: both displays thin on the frame numbers — the seconds '
        'display squeezes no number into a cell the other thins out of', () {
      for (final frames in [30, 120, 1200, 14400]) {
        for (final cell in [1.0, 4.0, 8.0, 12.0, 16.0, 24.0, 36.0]) {
          TimelineRulerScale at({required bool seconds}) => scale(
            frameEndIndexExclusive: frames,
            playbackFrameCount: frames,
            rulerView: seconds
                ? FrameRulerView.secondsPlusFrames
                : FrameRulerView.frames,
            metrics: TimelineGridMetrics.defaults.copyWith(
              frameCellWidth: cell,
            ),
          );
          expect(
            at(seconds: true).labelEveryFrames,
            at(seconds: false).labelEveryFrames,
            reason: '$frames frames at ${cell}px',
          );
        }
      }
    });

    test('I-102: inside a second every second\'s head carries a number, and '
        'past one the numbers stand under the seconds\' marks', () {
      for (final fps in [12, 24, 25, 30]) {
        for (var sixteenths = 1; sixteenths <= 400; sixteenths += 3) {
          final ruler = scale(
            framesPerSecond: fps,
            frameEndIndexExclusive: 14400,
            playbackFrameCount: 14400,
            metrics: TimelineGridMetrics.defaults.copyWith(
              frameCellWidth: sixteenths / 16,
            ),
          );
          final every = ruler.labelEveryFrames;
          final marks = fps * ruler.secondsLabelEverySeconds;
          final where = '$fps fps at ${sixteenths / 16}px: every $every';
          if (every < fps) {
            expect(fps % every, 0, reason: where);
          } else {
            expect(every % marks, 0, reason: '$where, marks every $marks');
          }
        }
      }
    });

    test('I-102: with the seconds written five apart, the number under 5 is '
        'the frame beneath it — 121, never 97', () {
      final fiveApart = [
        for (var sixteenths = 1; sixteenths <= 400; sixteenths += 1)
          scale(
            frameEndIndexExclusive: 1200,
            playbackFrameCount: 1200,
            metrics: TimelineGridMetrics.defaults.copyWith(
              frameCellWidth: sixteenths / 16,
            ),
          ),
      ].where((ruler) => ruler.secondsLabelEverySeconds == 5);
      expect(fiveApart, isNotEmpty, reason: 'the premise: a zoom writes so');
      for (final ruler in fiveApart) {
        final cell = ruler.metrics.frameCellWidth;
        expect(ruler.writingAt(120, current: false).second, '5');
        expect(ruler.writingAt(96, current: false).number, '', reason: '$cell');
        if (ruler.labelEveryFrames == 120) {
          expect(ruler.writingAt(120, current: false).number, '121');
        }
      }
    });
  });

  group('I-102: the seconds line grows into minutes and hours as far as the '
      'count needs', () {
    test('the count alone below a minute, then m:ss, then h:mm:ss', () {
      expect(timelineSecondsMark(0), '0');
      expect(timelineSecondsMark(59), '59');
      expect(timelineSecondsMark(60), '1:00');
      expect(timelineSecondsMark(61), '1:01');
      expect(timelineSecondsMark(600), '10:00');
      expect(timelineSecondsMark(3599), '59:59');
      expect(timelineSecondsMark(3661), '1:01:01');
    });

    test('the strip writes it, and measures the widest it writes', () {
      final ruler = scale(
        frameEndIndexExclusive: 24 * 3600,
        playbackFrameCount: 24 * 3600,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 24),
      );
      expect(ruler.secondsLabelEverySeconds, 1, reason: 'fixture premise');
      expect(ruler.writingAt(24 * 61, current: false).second, '1:01');
      expect(ruler.modelAt(24 * 61).secondsLabel, '1:01');
      // Two digits hold a second at this zoom; the minutes' marks do not.
      double second(int frames) => scale(
        frameEndIndexExclusive: frames,
        playbackFrameCount: frames,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 0.6),
      ).secondsLabelEverySeconds.toDouble();
      expect(second(24 * 3600), greaterThan(second(24 * 59)));
    });
  });

  group('frameNumberLabel', () {
    test('counts absolute 1-based frames', () {
      expect(scale().frameNumberLabel(0), '1');
      expect(scale().frameNumberLabel(24), '25');
    });

    test('in seconds mode it repeats 1..fps per second', () {
      final seconds = scale(rulerView: FrameRulerView.secondsPlusFrames);
      expect(seconds.frameNumberLabel(0), '1');
      expect(seconds.frameNumberLabel(23), '24');
      expect(seconds.frameNumberLabel(24), '1');
    });

    test('a non-positive fps falls back to 24', () {
      expect(
        scale(
          rulerView: FrameRulerView.secondsPlusFrames,
          framesPerSecond: 0,
        ).frameNumberLabel(25),
        '2',
      );
    });
  });

  // I-81 (유저 2026-10-06, I-81-Q1 10-30): the page view counts the way the
  // cut's X-sheet does — again from each page's head, which writes the page.
  group('I-81: the page view', () {
    TimelineRulerScale paged({
      double cell = 48,
      int frames = 432,
      int page = 144,
    }) => scale(
      rulerView: FrameRulerView.pages,
      pages: TimelineRulerPages.every(page),
      frameEndIndexExclusive: frames,
      playbackFrameCount: frames,
      metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
    );

    test('the numbers count 1..a page, again from each page', () {
      final strip = paged();
      expect(strip.frameNumberLabel(143), '144');
      expect(strip.frameNumberLabel(144), '1');
      expect(strip.modelAt(145).label, '2');
    });

    // 🗣️I-81-Q4 (유저 2026-10-30): 「페이지뷰는 초 옆에 페이지 넘어가는곳마다
    // p1 p2라고 쓸뿐임 그 외는 프레임뷰랑 똑같음. 프레임숫자가 페이지마다
    // 초기화되는정도」. ↩️The seconds counted again from each page's head,
    // which wrote its page instead.
    test('a page\'s head writes its page beside its second, and the seconds '
        'are the frames view\'s', () {
      final strip = paged();
      expect(strip.secondsLabelEverySeconds, 1, reason: 'the premise');
      expect(strip.modelAt(0).secondsLabel, '0 p1');
      expect(strip.modelAt(24).secondsLabel, '1');
      expect(strip.modelAt(144).secondsLabel, '6 p2');
      expect(strip.modelAt(168).secondsLabel, '7');
      expect(strip.modelAt(264).secondsLabel, '11');
    });

    test('a second that would run into a page\'s mark writes nothing — '
        'within a rung before it, within its clear frames after', () {
      String at(
        int frame, {
        int every = 1,
        int everyPages = 1,
        int clear = 1,
      }) => timelineRulerSecondsLabel(
        frameIndex: frame,
        framesPerSecond: 24,
        everySeconds: every,
        pages: (
          heads: [for (var head = 0; head < 1440; head += 144) head],
          everyPages: everyPages,
          clearFrames: clear,
        ),
      );
      expect(at(96, every: 2), '4');
      expect(at(120), '5');
      expect(
        at(120, every: 5),
        '',
        reason: 'p2 stands a second on, and a rung is five',
      );
      expect(at(168, clear: 24), '7');
      expect(at(168, clear: 25), '', reason: 'p2 takes more than a second');
      expect(at(144, every: 5), 'p2', reason: 'a head off the rung');
      expect(at(144, everyPages: 2), '6', reason: 'a page left unwritten');
      expect(at(288, everyPages: 2), '12 p3');
    });

    test('past where a page holds its mark, every Nth page writes it; the '
        'numbers stand where the frames view\'s do, each its page\'s', () {
      final strip = paged(cell: 1 / 8, frames: 14400, page: 72);
      final every = strip.pagesLabelEvery;
      expect(every, greaterThan(1), reason: 'the premise');
      expect(timelineSecondStrideLadder, contains(every));
      expect(strip.modelAt(0).secondsLabel, endsWith('p1'));
      expect(
        strip.modelAt(72 * every).secondsLabel,
        endsWith('p${every + 1}'),
      );
      expect(strip.modelAt(72).secondsLabel, isNot(contains('p')));
      final framesView = scale(
        frameEndIndexExclusive: 14400,
        playbackFrameCount: 14400,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 1 / 8),
      );
      var written = 0;
      for (var frame = 0; frame < 14400; frame += 1) {
        final there = framesView.modelAt(frame).label;
        expect(
          strip.modelAt(frame).label,
          there.isEmpty ? isEmpty : '${frame % 72 + 1}',
          reason: 'frame $frame',
        );
        written += there.isEmpty ? 0 : 1;
      }
      expect(written, greaterThan(1), reason: 'the premise');
    });

    test('the widest number stands at the end of the last whole run — of a '
        'second, of a page — and at the last frame where nothing restarts',
        () {
      expect(scale().widestNumberFrameBefore(200), 199);
      final seconds = scale(rulerView: FrameRulerView.secondsPlusFrames);
      expect(seconds.widestNumberFrameBefore(200), 191);
      expect(seconds.frameNumberLabel(191), '24');
      final pages = paged();
      expect(pages.widestNumberFrameBefore(200), 143);
      expect(pages.frameNumberLabel(143), '144');
    });

    group('I-81-Q3: a book\'s pages, of many lengths', () {
      TimelineRulerScale book({
        double cell = 48,
        int frames = 432,
        List<int> heads = const [0, 100, 130, 300],
      }) => scale(
        rulerView: FrameRulerView.pages,
        pages: TimelineRulerPages.startingAt(heads),
        frameEndIndexExclusive: frames,
        playbackFrameCount: frames,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
      );

      test('the numbers start again at each page\'s head', () {
        final strip = book();
        expect(
          [for (final at in [0, 99, 100, 129, 130, 299, 300, 431])
            strip.frameNumberLabel(at)],
          ['1', '100', '1', '30', '1', '170', '1', '132'],
        );
      });

      test('each head writes its page, beside the second where it stands '
          'on one; a second that would run into a mark stands down', () {
        final strip = book();
        expect(strip.modelAt(0).secondsLabel, '0 p1');
        expect(strip.modelAt(100).secondsLabel, 'p2');
        expect(strip.modelAt(130).secondsLabel, 'p3');
        expect(strip.modelAt(72).secondsLabel, '3');
        expect(strip.modelAt(96).secondsLabel, '', reason: 'before p2');
        expect(strip.modelAt(120).secondsLabel, '', reason: 'before p3');
        expect(strip.modelAt(144).secondsLabel, '6');
        final onASecond = book(heads: const [0, 120]);
        expect(onASecond.modelAt(120).secondsLabel, '5 p2');
      });

      test('marks thin by the closest two they would stand apart', () {
        const heads = [0, 10, 20, 400, 410, 800];
        final strip = book(cell: 1, frames: 900, heads: heads);
        expect(strip.pagesLabelEvery, 5, reason: 'two pages are 20px');
        expect(strip.modelAt(0).secondsLabel, endsWith('p1'));
        expect(strip.modelAt(800).secondsLabel, endsWith('p6'));
        expect(strip.modelAt(400).secondsLabel, isNot(contains('p')));
        expect(
          book(cell: 1, frames: 900, heads: const [0, 400, 800])
              .pagesLabelEvery,
          1,
          reason: 'pages that hold their marks each write one',
        );
        expect(
          book(cell: 1, frames: 1300, heads: const [0, 400, 800, 810, 1200])
              .pagesLabelEvery,
          2,
          reason: 'the two that touch stand late in the book',
        );
      });

      test('past the ladder\'s top the rung doubles on', () {
        expect(timelineLadderRung((rung) => rung >= 600), 600);
        expect(timelineLadderRung((rung) => rung >= 1000), 1200);
      });

      test('the walk visits the marks too, in order, and nothing twice', () {
        final strip = book(cell: 4, heads: const [0, 100, 130, 288, 300]);
        final walked = strip
            .framesWrittenIn((startIndex: 90, endIndexExclusive: 305))
            .toList();
        expect(strip.writingStep, greaterThan(1), reason: 'premise');
        expect(walked, [...walked.toSet().toList()..sort()]);
        expect(walked, containsAll(const [100, 130, 288, 300]));
        expect(walked.first, greaterThanOrEqualTo(90));
        expect(walked.last, lessThan(305));
        expect(
          walked.where((frame) => frame % strip.writingStep != 0).toList(),
          const [100, 130],
          reason: 'off the stride, only the heads',
        );
        expect(
          strip.framesWrittenIn((startIndex: 301, endIndexExclusive: 302)),
          isEmpty,
        );
      });

      test('the walk leaves a thinned page out', () {
        const heads = [0, 10, 20, 400, 410, 800];
        final strip = book(cell: 1, frames: 900, heads: heads);
        final walked = strip.framesWrittenIn((
          startIndex: 1,
          endIndexExclusive: 900,
        ));
        final step = strip.writingStep;
        expect(
          walked.where((frame) => frame % step != 0),
          step.gcd(800) == step ? isEmpty : const [800],
        );
        expect(walked, isNot(contains(10)));
      });

      test('the widest number stands at the end of the longest page', () {
        final strip = book();
        expect(strip.widestNumberFrameBefore(432), 299);
        expect(strip.frameNumberLabel(299), '170');
        expect(strip.widestNumberFrameBefore(200), 99);
        expect(strip.widestNumberFrameBefore(50), 49);
        expect(
          book(heads: const [0, 100]).widestNumberFrameBefore(200),
          199,
          reason: 'two alike: the later',
        );
      });

      test('pages compare by where they begin', () {
        expect(book(), book());
        expect(book(), isNot(book(heads: const [0, 100, 130, 301])));
        expect(
          const TimelineRulerPages.every(144),
          isNot(const TimelineRulerPages.every(72)),
        );
      });

      test('a strip takes the pages that begin on it, and never none', () {
        const sheet = TimelineRulerPages.every(144);
        expect(sheet.headsBefore(300), [0, 144, 288]);
        expect(sheet.headsBefore(288), [0, 144]);
        expect(sheet.headsBefore(0), [0]);
        const pages = TimelineRulerPages.startingAt([0, 100, 200]);
        expect(pages.headsBefore(150), [0, 100]);
        expect(pages.headsBefore(0), [0]);
      });

      test('a page is the last head at or before its frame', () {
        const heads = [0, 100, 130];
        expect(
          [for (final at in [0, 99, 100, 129, 130, 9999])
            timelinePageAt(heads, at)],
          [0, 0, 1, 1, 2, 2],
        );
      });
    });

    test('off the page view a strip writes every page it would have', () {
      expect(scale(pageFrames: 72).pagesLabelEvery, 1);
    });
  });

  // F-284 (유저 2026-10-04): 「S1의 15. 이런식으로 15번 인덱스나. 이런
  // 표기는 초+코마 표기로 바꾼거에 대응하도록 법 통일」 — a list names a
  // frame by what the ruler writes over it, so the two are compared here
  // and not each to a number.
  group('a frame\'s place is what the ruler writes over it', () {
    test('its number, as the ruler counts it', () {
      for (final frame in [0, 14, 23, 24, 100]) {
        expect(
          timelineFramePlaceLabel(
            frameIndex: frame,
            framesPerSecond: 24,
            showSeconds: false,
          ),
          scale().frameNumberLabel(frame),
        );
      }
      expect(
        timelineFramePlaceLabel(
          frameIndex: 14,
          framesPerSecond: 24,
          showSeconds: false,
        ),
        '15',
      );
    });

    test('under the seconds display: the second it lies in, then the number '
        'the ruler writes there', () {
      for (final fps in [24, 12, 30]) {
        final seconds = scale(
          rulerView: FrameRulerView.secondsPlusFrames,
          framesPerSecond: fps,
        );
        for (final frame in [0, 14, fps - 1, fps, 3 * fps + 5]) {
          final second = timelineRulerSecondOf(
            frameIndex: frame,
            framesPerSecond: fps,
          );
          expect(
            timelineFramePlaceLabel(
              frameIndex: frame,
              framesPerSecond: fps,
              showSeconds: true,
            ),
            '$second+${seconds.frameNumberLabel(frame)}',
            reason: 'frame $frame at $fps',
          );
        }
      }
      String place(int frame, {int fps = 24}) => timelineFramePlaceLabel(
        frameIndex: frame,
        framesPerSecond: fps,
        showSeconds: true,
      );
      expect(place(14), '0+15');
      expect(place(24), '1+1');
      expect(
        place(23),
        '0+24',
        reason: 'a place, not a length: 24 frames LONG is 1+0',
      );
      expect(place(14, fps: 12), '1+3');
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
        final across = scale().modelAt(frame);
        final down = scale(axis: Axis.vertical).modelAt(frame);
        expect(down.label, across.label, reason: 'frame $frame');
        expect(down.secondsLabel, across.secondsLabel, reason: 'frame $frame');
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
      FrameRulerView rulerView = FrameRulerView.frames,
      int? pageFrames,
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
      rulerView: rulerView,
      pages: pageFrames == null ? null : TimelineRulerPages.every(pageFrames),
    );
    // I-81: the page view of a 6-second sheet and of a 3-second one.
    const views = <(FrameRulerView, int?)>[
      (FrameRulerView.frames, null),
      (FrameRulerView.pages, 144),
      (FrameRulerView.pages, 72),
    ];
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

    test('every frame a strip writes at is one it walks', () {
      for (final axis in Axis.values) {
        for (final (view, page) in views) {
          final strip = wide(axis: axis, rulerView: view, pageFrames: page);
          final walked = strip
              .framesWrittenIn((startIndex: 0, endIndexExclusive: 14400))
              .toSet();
          for (var frame = 0; frame < 14400; frame += 1) {
            final writing = strip.writingAt(frame, current: false);
            if (writing.number.isNotEmpty || writing.second.isNotEmpty) {
              expect(walked, contains(frame), reason: '$axis $view $frame');
            }
          }
        }
      }
    });

    test('no two seconds a strip writes stand closer than the mark gap', () {
      // A sweep, not the floor alone: the gap decides the rung only in the
      // band where a second holds its widest mark but not the gap as well.
      for (final axis in Axis.values) {
        for (final (view, page) in views) {
          for (var step = 10; step <= 500; step += 1) {
            final strip = wide(
              axis: axis,
              cellExtent: step / 200,
              rulerView: view,
              pageFrames: page,
            );
            Rect? previous;
            var closest = double.infinity;
            for (var second = 100; second < 300; second += 1) {
              final frame = second * 24;
              final text = strip.writingAt(frame, current: false).second;
              if (text.isEmpty) {
                continue;
              }
              final rect = layoutOf(axis)(strip, frame, current: false)
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
              reason: '$axis $view $page at ${step / 200}px',
            );
          }
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

    test('the paper is one rect per ground: the playback end is its only '
        'edge', () {
      final strip = scale(
        axis: Axis.vertical,
        playbackFrameCount: 50,
        frameEndIndexExclusive: 100,
        pastPlaybackWash: const Color(0xFF123456),
      );
      final canvas = _Rects();
      strip.paintPaperIn(canvas, (startIndex: 0, endIndexExclusive: 100));

      expect(canvas.rects.map((rect) => rect.color.toARGB32()), [
        strip.modelAt(0).background.toARGB32(),
        strip.modelAt(50).background.toARGB32(),
      ]);
      expect(canvas.rects.first.rect, strip.cellRectFor(0).expandToInclude(
        strip.cellRectFor(49),
      ));
      expect(canvas.rects.last.rect, strip.cellRectFor(50).expandToInclude(
        strip.cellRectFor(99),
      ));
    });

    test('the paper rules every line the law rules, whatever frame a '
        'stretch starts on', () {
      for (final axis in Axis.values) {
        // The playback end cuts the paper at 50 — not on the lines' step
        // at this zoom.
        final strip = scale(
          axis: axis,
          metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
          playbackFrameCount: 50,
          frameEndIndexExclusive: 1000,
        );
        final lines = _Lines();
        strip.paintPaperIn(lines, (startIndex: 0, endIndexExclusive: 1000));

        double edgeOf(int frame) =>
            startAlong(axis, strip.cellRectFor(frame)) + timelineGridLineSnap;

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
        expect(ruled.length, greaterThan(2), reason: 'the premise');
        expect(
          lines.starts.map((start) => partAlong(axis, start)),
          ruled,
          reason: '$axis',
        );
      }
    });
  });

  // 🚨I-57 (10-15, profile, the user's project): the strip laid every
  // frame's writing out again at each repaint, and the playhead's writing
  // over it on every tick of a run ([TimelineRulerScale.writtenAt]).
  group('a scale lays a frame\'s writing out once', () {
    test('a window painted again lays nothing out', () {
      final strip = scale();
      final recorded = recordingRulerLayout();
      strip.paintWindow(_Rects(), recorded.layout);
      expect(recorded.asked, isNotEmpty, reason: 'premise: the window wrote');
      recorded.asked.clear();
      strip.paintWindow(_Rects(), recorded.layout);
      expect(recorded.asked, isEmpty);
    });

    test('a run down a long cut does not hold every frame it passed', () {
      final strip = scale(
        frameEndIndexExclusive: 2000,
        playbackFrameCount: 2000,
      );
      final recorded = recordingRulerLayout();
      for (var frame = 0; frame < 2000; frame += 1) {
        strip.writtenAt(recorded.layout, frame, current: false);
      }
      recorded.asked.clear();
      strip.writtenAt(recorded.layout, 0, current: false);
      expect(recorded.asked, [(frame: 0, current: false)]);
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
