import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/session/panel_view_memory.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

/// 🗣️F-220 (유저 2026-09-29): 「타임라인/콘티패널 줌, 1.7에서 2.8까지 이동하면
/// 안바뀌고, 2.9까지 이동해야 타임라인 줌 상태가 바뀌는등 … 제대로 퍼센테이지
/// 바뀔때마다 줌 상태가 바뀌지 않음. … 손을 뗄 때 값이 멋대로 살짝 바뀜」.
///
/// 🗣️F-403 (유저 2026-10-19): 「0.9%에서 숫자 안바뀌는데 줌이 바뀌는걸
/// 발견. 내가 분명 이런 슬라이더에서 조절되는 숫자까지 다 슬라이더에
/// 보여주라고 하지않았나? … 소수점 두번째부터는 작동안하도록」.
/// 🗣️F-491 (유저 2026-10-27): 「타임라인 줌, 소수점대도 움직여지는데
/// 필요없어지니 그냥 소수점대 안움직이게. 즉 소수점값 없는 정수로. 대신
/// 지금의 0.6%정도? 만큼 보이는건 유지하고싶음. 그러니 지금의 0.5%를 1%로
/// 두도록 기준 개편」.
///
/// The zoom readout and the zoom keys ask ONE bound, and the zooms inside
/// it are the numbers the bar writes — a step of 1%: every number the bar
/// reaches is a zoom, and no zoom lies between two numbers. ↩️They landed
/// on a grid — whole pixels a frame, whole frames a pixel under one — which
/// had no zoom between 1/2 and 1 pixel a frame (2.1% to 4.2% as the bar
/// read then), and the bar jumped back to the grid on release (F-220); then
/// any zoom was one, and two zooms could write one number (F-403); then a
/// step was 0.1% (F-403 to F-491).
void main() {
  const fps = 24;
  final floor = TimelineZoomLimits.minPixelsPerFrameAt(fps);
  const reference = TimelineZoomLimits.referencePixelsPerFrame;

  /// The zoom the bar reads as 100% — 「지금의 0.5%를 1%로」: half the one it
  /// read as 100% before F-491.
  const hundred = reference / 2;
  const step = hundred / 100;

  /// The number the bar writes for [zoom].
  String shown(double zoom) => (zoom * 100 / hundred).toStringAsFixed(0);

  group('TimelineZoomLimits.clamped', () {
    test('🚨a zoom lands on its nearest 1% — the old grid\'s gaps '
        'included — and a step is itself', () {
      for (final zoom in <double>[0.41, 0.55, 0.67, 1.3, 9.6, 19.2, 24.5, 30]) {
        final landed = TimelineZoomLimits.clamped(zoom, framesPerSecond: fps);
        expect(landed, closeTo(zoom, step / 2), reason: '$zoom');
        expect(
          TimelineZoomLimits.clamped(landed, framesPerSecond: fps),
          landed,
          reason: '$zoom: on a step',
        );
      }
    });

    test('🚨「소수점값 없는 정수로」: two zooms the bar writes as one '
        'number are one zoom', () {
      for (final zoom in <double>[0.1728, 0.5, 4.8, 19.2, 33.3]) {
        final landed = TimelineZoomLimits.clamped(zoom, framesPerSecond: fps);
        for (final nudge in [for (final k in [-4, -1, 1, 4]) k * step / 10]) {
          expect(
            TimelineZoomLimits.clamped(landed + nudge, framesPerSecond: fps),
            landed,
            reason: '$zoom nudged by $nudge, still 「${shown(landed)}%」',
          );
        }
      }
    });

    test('🚨the bounds hold, so nothing reaches a zero cell', () {
      expect(TimelineZoomLimits.clamped(0.01, framesPerSecond: fps), floor);
      expect(
        TimelineZoomLimits.clamped(0, framesPerSecond: fps),
        floor,
        reason: 'a zero cell trips the grid assert and the anchor division',
      );
      expect(
        TimelineZoomLimits.clamped(400, framesPerSecond: fps),
        TimelineZoomLimits.maxPixelsPerFrame,
      );
      // From 48 fps ten minutes would ask for less than a step; the floor
      // stays a step (F-491-Q1).
      expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(240)), '1');
    });
  });

  test('「지금의 0.5%를 1%로」: what the bar read as 0.5% it reads as 1%, and '
      'no zoom moved — a cut opens at 80% of the old 24-pixel frame, now '
      '200%, and the closest zoom is twice that, now 400%', () {
    expect(
      shown(0.005 * TimelineZoomLimits.referencePixelsPerFrame),
      '1',
      reason: 'the bar\'s 100% was the zoom a cut opens at (F-403)',
    );
    expect(reference, closeTo(0.8 * 24, 1e-9));
    expect(shown(reference), '200');
    expect(TimelineZoomLimits.maxPixelsPerFrame, closeTo(0.8 * 24 * 2, 1e-9));
    expect(shown(TimelineZoomLimits.maxPixelsPerFrame), '400');
    expect(
      shown(PanelViewMemory.defaultStoryboardPixelsPerFrame),
      '80',
      reason: 'the conte opens at 80%, a number the bar writes',
    );
    expect(
      TimelineZoomLimits.clamped(
        PanelViewMemory.defaultStoryboardPixelsPerFrame,
        framesPerSecond: fps,
      ),
      PanelViewMemory.defaultStoryboardPixelsPerFrame,
      reason: 'on a step',
    );
  });

  test('at the widest zoom ten minutes fit 1,800px at every rate up to 30, '
      'and a step closer would not; above it the widest is one step', () {
    for (final rate in ProjectFrameRate.presets) {
      final base = rate.countingBase;
      final widest = TimelineZoomLimits.minPixelsPerFrameAt(base);
      expect(
        TimelineZoomLimits.clamped(widest, framesPerSecond: base),
        widest,
        reason: '$base fps: the floor is a step',
      );
      if (base > 30) {
        expect(shown(widest), '1', reason: '$base fps (F-491-Q1)');
        continue;
      }
      expect(
        600 * base * widest,
        lessThanOrEqualTo(1800),
        reason: '$base fps: ten minutes inside 1,800px',
      );
      expect(
        600 * base * (widest + step),
        greaterThan(1800),
        reason: '$base fps: the floor is the widest the rule needs, not wider',
      );
    }
    expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(8)), '3');
    expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(15)), '2');
    expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(24)), '1');
    expect(
      TimelineZoomLimits.minPixelsPerFrameAt(24),
      lessThanOrEqualTo(0.006 * reference),
      reason: '「지금의 0.6%정도? 만큼 보이는건 유지」: at 24 fps the widest shows '
          'as much as the old 0.6% did, or more',
    );
  });

  test('a zoom key\'s step is ×1.25 to the nearest step, moves at least one, '
      'and stops only at a bound', () {
    const ceiling = TimelineZoomLimits.maxPixelsPerFrame;
    for (final percent in [3, 8, 20, 100, 240, 360]) {
      final zoom = percent * step;
      double near(double target) =>
          TimelineZoomLimits.clamped(target, framesPerSecond: fps);
      final zoomedIn = TimelineZoomLimits.stepped(
        zoom,
        zoomIn: true,
        framesPerSecond: fps,
      );
      expect(zoomedIn, near(zoom * 1.25), reason: '+ from $percent%');
      expect(zoomedIn, greaterThan(near(zoom)), reason: '+ from $percent%');
      final zoomedOut = TimelineZoomLimits.stepped(
        zoom,
        zoomIn: false,
        framesPerSecond: fps,
      );
      expect(zoomedOut, near(zoom / 1.25), reason: '− from $percent%');
      expect(zoomedOut, lessThan(near(zoom)), reason: '− from $percent%');
    }
    expect(
      TimelineZoomLimits.stepped(ceiling, zoomIn: true, framesPerSecond: fps),
      ceiling,
    );
    expect(
      TimelineZoomLimits.stepped(floor, zoomIn: false, framesPerSecond: fps),
      floor,
    );
    // Where ×1.25 rounds back onto the step it left, a press still moves
    // one: the widest zoom of a 24fps count is a single step.
    expect(shown(floor), '1', reason: 'fixture: one step');
    expect(
      shown(
        TimelineZoomLimits.stepped(floor, zoomIn: true, framesPerSecond: fps),
      ),
      '2',
    );
    expect(
      shown(
        TimelineZoomLimits.stepped(
          2 * floor,
          zoomIn: false,
          framesPerSecond: fps,
        ),
      ),
      '1',
      reason: '÷1.25 rounds back onto the second step, and − still moves',
    );
  });

  group('the frame axis\' one law keeps a line on one pixel at any zoom', () {
    test('from a pixel a cell, every boundary is a whole pixel, and a cell '
        'is its zoom give or take one', () {
      for (final zoom in [1.0, 1.3, 2.5, 7.3, 24.6, 47.9]) {
        for (var frame = 0; frame < 200; frame += 1) {
          final edge = timelineFrameEdge(frame, zoom);
          expect(edge, edge.roundToDouble(), reason: '$zoom: frame $frame');
          expect((edge - frame * zoom).abs(), lessThanOrEqualTo(0.5));
          final cell = timelineFrameEdge(frame + 1, zoom) - edge;
          expect(cell, greaterThanOrEqualTo(zoom.floorToDouble()));
          expect(cell, lessThanOrEqualTo(zoom.ceilToDouble()));
        }
      }
    });

    test('under a pixel a cell is left where it falls — rounding would give '
        'a one-frame block no width', () {
      for (final zoom in [0.125, 0.41, 0.67, 0.99]) {
        for (var frame = 0; frame < 50; frame += 1) {
          expect(timelineFrameEdge(frame, zoom), frame * zoom);
        }
      }
    });

    test('timelineFrameAt reads the boundaries back at every zoom', () {
      for (final zoom in [0.125, 0.67, 1.3, 7.3, 24.6]) {
        for (var frame = 0; frame < 120; frame += 1) {
          final edge = timelineFrameEdge(frame, zoom);
          final next = timelineFrameEdge(frame + 1, zoom);
          expect(timelineFrameAt(edge, zoom), frame, reason: '$zoom@$frame');
          expect(
            timelineFrameAt(edge + (next - edge) / 2, zoom),
            frame,
            reason: '$zoom: mid-cell $frame',
          );
        }
      }
    });
  });

  group('the readout emits every zoom it reaches', () {
    final readout = find.byKey(
      const ValueKey<String>('timeline-zoom-readout'),
    );

    /// The cluster at [pixelsPerFrame], fed back what it emits, as a host
    /// does — and every zoom it emitted.
    Future<List<double>> pump(
      WidgetTester tester, {
      required double pixelsPerFrame,
    }) async {
      final zooms = <double>[];
      final zoom = ValueNotifier<double>(pixelsPerFrame);
      addTearDown(zoom.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: zoom,
                  builder: (context, pixelsPerFrame, _) => TimelineViewCluster(
                    projectFrameRate: ProjectFrameRate.fps24,
                    pixelsPerFrame: pixelsPerFrame,
                    onPixelsPerFrameChanged: (value) {
                      zooms.add(value);
                      zoom.value = value;
                    },
                    cutName: const AlwaysStoppedAnimation<String>(''),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return zooms;
    }

    /// A mouse along the readout, a pixel a move.
    Future<void> sweep(WidgetTester tester, int pixels) async {
      final at = tester.getCenter(readout);
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var x = 1; x <= pixels.abs(); x += 1) {
        await gesture.moveTo(at + Offset(x * pixels.sign.toDouble(), 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets('the readout writes the zoom to work at as 200%, with no '
        'digit after the point', (tester) async {
      await pump(tester, pixelsPerFrame: reference);
      expect(
        find.descendant(of: readout, matching: find.text('200%')),
        findsOneWidget,
      );
    });

    testWidgets('🚨a drag out of the widest zoom zooms at every pixel, and '
        'each zoom is a number of its own', (tester) async {
      final zooms = await pump(tester, pixelsPerFrame: floor);
      await sweep(tester, 9);
      expect(zooms, hasLength(9), reason: 'a zoom at every pixel: $zooms');
      expect(
        {for (final zoom in zooms) shown(zoom)}.length,
        zooms.length,
        reason: '「숫자 안바뀌는데 줌이 바뀌는」 — each zoom a number of its own',
      );
      for (final zoom in zooms) {
        expect(
          zoom,
          TimelineZoomLimits.clamped(zoom, framesPerSecond: fps),
          reason: 'on a step: $zoom',
        );
      }
    });

    testWidgets('at the widest zoom a drag wider moves nothing', (
      tester,
    ) async {
      final zooms = await pump(tester, pixelsPerFrame: floor);
      await sweep(tester, -5);
      expect(zooms, isEmpty, reason: 'nothing wider to go to');
    });

    testWidgets('a drag never leaves the range', (tester) async {
      final zooms = await pump(tester, pixelsPerFrame: floor + step);
      await sweep(tester, -1);
      expect(zooms, [floor]);
    });
  });
}
