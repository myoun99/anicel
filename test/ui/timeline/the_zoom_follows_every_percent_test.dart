import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart'
    show DragVerbClaim;
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
///
/// The slider and the −/+ buttons ask ONE bound, and the zooms inside it are
/// the numbers the bar writes — a step of 0.1%: every number the bar
/// reaches is a zoom, and no zoom lies between two numbers. ↩️They landed
/// on a grid — whole pixels a frame, whole frames a pixel under one — which
/// had no zoom between 1/2 and 1 pixel a frame (2.1% to 4.2%), and the bar
/// jumped back to the grid on release (F-220); then any zoom was one, and
/// two zooms could write one number (F-403).
void main() {
  const fps = 24;
  final floor = TimelineZoomLimits.minPixelsPerFrameAt(fps);
  const reference = TimelineZoomLimits.referencePixelsPerFrame;
  const step = reference / 1000;

  /// The number the bar writes for [zoom].
  String shown(double zoom) => (zoom * 100 / reference).toStringAsFixed(1);

  group('TimelineZoomLimits.clamped', () {
    test('🚨a zoom lands on its nearest 0.1% — the old grid\'s gaps '
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

    test('🚨「소수점 두번째부터는 작동안하도록」: two zooms the bar writes as one '
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
      // Past 156 fps — a rate the custom field takes — ten minutes would
      // ask for less than a step; the floor stays a step.
      expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(240)), '0.1');
    });
  });

  test('「200%까지만」 · 「80%를 100%로」: the closest zoom is 200% of the old '
      '24-pixel 100% — 250% now — and 80% of it reads 100%', () {
    expect(TimelineZoomLimits.maxPixelsPerFrame, 2 * 24);
    expect(shown(TimelineZoomLimits.maxPixelsPerFrame), '250.0');
    expect(reference, closeTo(0.8 * 24, 1e-9));
    expect(shown(reference), '100.0');
    expect(
      shown(PanelViewMemory.defaultStoryboardPixelsPerFrame),
      '40.0',
      reason: 'the conte opens at 40%, a number the bar writes',
    );
  });

  test('at the widest zoom ten minutes fit 1,800px at every rate, and a '
      'step closer would not', () {
    for (final rate in ProjectFrameRate.presets) {
      final base = rate.countingBase;
      final widest = TimelineZoomLimits.minPixelsPerFrameAt(base);
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
      expect(
        TimelineZoomLimits.clamped(widest, framesPerSecond: base),
        widest,
        reason: '$base fps: the floor is a step',
      );
    }
    expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(24)), '0.6');
    expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(30)), '0.5');
    expect(shown(TimelineZoomLimits.minPixelsPerFrameAt(60)), '0.2');
  });

  test('a −/+ step is ×1.25 to the nearest step, moves at least one, and '
      'stops only at a bound', () {
    const ceiling = TimelineZoomLimits.maxPixelsPerFrame;
    for (final zoom in [floor, 0.3, 0.5, 0.8, 1.0, 2.0, 3.0, 24.0, 40.0]) {
      double near(double target) =>
          TimelineZoomLimits.clamped(target, framesPerSecond: fps);
      final zoomedIn = TimelineZoomLimits.stepped(
        zoom,
        zoomIn: true,
        framesPerSecond: fps,
      );
      expect(zoomedIn, near(zoom * 1.25), reason: '+ from $zoom');
      expect(zoomedIn, greaterThan(near(zoom)), reason: '+ from $zoom moves');
      final zoomedOut = TimelineZoomLimits.stepped(
        zoom,
        zoomIn: false,
        framesPerSecond: fps,
      );
      expect(zoomedOut, near(zoom / 1.25), reason: '− from $zoom');
      expect(
        zoomedOut,
        zoom <= floor ? floor : lessThan(near(zoom)),
        reason: '− from $zoom',
      );
    }
    expect(
      TimelineZoomLimits.stepped(ceiling, zoomIn: true, framesPerSecond: fps),
      ceiling,
    );
    // Where ×1.25 rounds back onto the step it left, a press still moves
    // one: the widest zoom of a 120fps count is a single step.
    final single = TimelineZoomLimits.minPixelsPerFrameAt(120);
    expect(shown(single), '0.1', reason: 'fixture: one step');
    expect(
      shown(
        TimelineZoomLimits.stepped(single, zoomIn: true, framesPerSecond: 120),
      ),
      '0.2',
    );
    expect(
      shown(
        TimelineZoomLimits.stepped(
          2 * single,
          zoomIn: false,
          framesPerSecond: 120,
        ),
      ),
      '0.1',
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

  group('the controls emit every zoom they reach', () {
    Future<List<double>> pump(
      WidgetTester tester, {
      required double pixelsPerFrame,
    }) async {
      final zooms = <double>[];
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                TimelineViewCluster(
                  frameCursor: cursor,
                  projectFrameRate: ProjectFrameRate.fps24,
                  showSeconds: false,
                  pixelsPerFrame: pixelsPerFrame,
                  onPixelsPerFrameChanged: zooms.add,
                ),
              ],
            ),
          ),
        ),
      );
      return zooms;
    }

    Future<double> press(
      WidgetTester tester, {
      required double from,
      required bool zoomIn,
    }) async {
      final zooms = await pump(tester, pixelsPerFrame: from);
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            zoomIn ? 'timeline-zoom-in-button' : 'timeline-zoom-out-button',
          ),
        ),
      );
      return zooms.last;
    }

    testWidgets('the bar writes the zoom to work at as 100%', (tester) async {
      await pump(tester, pixelsPerFrame: reference);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-zoom-slider')),
          matching: find.text('100.0%'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the + and − buttons step ×1.25 onto the bar\'s numbers', (
      tester,
    ) async {
      Future<String> pressed(double from, {required bool zoomIn}) async =>
          shown(await press(tester, from: from, zoomIn: zoomIn));
      expect(await pressed(reference, zoomIn: true), '125.0');
      expect(await pressed(reference, zoomIn: false), '80.0');
      expect(await pressed(3.84, zoomIn: true), '25.0');
    });

    testWidgets('🚨a drag across the old grid\'s gap — 2.1% to 3.5% — zooms '
        'at every number it writes, and writes every zoom', (tester) async {
      final zooms = await pump(tester, pixelsPerFrame: reference);
      final track = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-zoom-slider')),
          matching: find.byType(DragVerbClaim),
        ),
      );
      // The track is multiplicative: where a zoom sits along it.
      double xFor(double zoom) =>
          track.left +
          track.width *
              math.log(zoom / floor) /
              math.log(TimelineZoomLimits.maxPixelsPerFrame / floor);
      // The user's own stretch of F-220, 1.7% to 2.8% of the 24-pixel frame
      // then.
      final from = xFor(0.41);
      final to = xFor(0.67);
      final gesture = await tester.startGesture(
        Offset(from, track.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      var moves = 0;
      for (var x = from + 1; x <= to; x += 1) {
        await gesture.moveTo(Offset(x, track.center.dy));
        await tester.pump();
        moves += 1;
      }
      await gesture.up();
      await tester.pump();

      expect(moves, greaterThanOrEqualTo(8), reason: 'fixture: the stretch');
      final inside = {
        for (final zoom in zooms)
          if (zoom > 0.3 && zoom < 0.9) zoom,
      };
      expect(
        inside.length,
        greaterThan(5),
        reason: '↩️the grid gave every move the same 1/2 pixel a frame',
      );
      expect(
        {for (final zoom in inside) shown(zoom)}.length,
        inside.length,
        reason: '「숫자 안바뀌는데 줌이 바뀌는」 — each zoom a number of its own',
      );
    });

    testWidgets('at the floor the − button stands down', (tester) async {
      final zooms = await pump(tester, pixelsPerFrame: floor);
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-zoom-out-button')),
      );
      expect(zooms, isEmpty, reason: 'nothing wider to go to');
    });

    testWidgets('a step never leaves the range', (tester) async {
      expect(await press(tester, from: floor + step, zoomIn: false), floor);
    });
  });
}
