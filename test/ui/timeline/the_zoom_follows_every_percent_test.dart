import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart'
    show DragVerbClaim;
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

/// 🗣️F-220 (유저 2026-09-29): 「타임라인/콘티패널 줌, 1.7에서 2.8까지 이동하면
/// 안바뀌고, 2.9까지 이동해야 타임라인 줌 상태가 바뀌는등 … 제대로 퍼센테이지
/// 바뀔때마다 줌 상태가 바뀌지 않음. … 손을 뗄 때 값이 멋대로 살짝 바뀜」.
///
/// The slider and the −/+ buttons ask ONE bound, and any zoom inside it is a
/// zoom: every percent the bar reaches is the zoom, and releasing it leaves
/// it there. ↩️They landed on a grid — whole pixels a frame, whole frames a
/// pixel under one — which had no zoom between 1/2 and 1 pixel a frame
/// (2.1% to 4.2%), and the bar jumped back to the grid on release.
void main() {
  const fps = 24;
  final floor = TimelineZoomLimits.minPixelsPerFrameAt(fps);

  group('TimelineZoomLimits.clamped', () {
    test('🚨any zoom inside the range is itself — the old grid\'s gaps '
        'included', () {
      for (final zoom in <double>[0.41, 0.55, 0.67, 1.3, 9.6, 19.2, 24.5, 30]) {
        expect(TimelineZoomLimits.clamped(zoom, framesPerSecond: fps), zoom);
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
    });
  });

  test('at the widest zoom ten minutes fit 1,800px at every rate', () {
    for (final rate in ProjectFrameRate.presets) {
      final base = rate.countingBase;
      final widest = TimelineZoomLimits.minPixelsPerFrameAt(base);
      final framesPerPixel = 1 / widest;
      expect(
        600 * base * widest,
        lessThanOrEqualTo(1800),
        reason: '$base fps: ten minutes inside 1,800px',
      );
      expect(
        600 * base / (framesPerPixel - 1),
        greaterThan(1800),
        reason: '$base fps: a frame a pixel fewer would not fit — the floor '
            'is the widest the rule needs, not wider',
      );
    }
    expect(TimelineZoomLimits.minPixelsPerFrameAt(24), 1 / 8);
    expect(TimelineZoomLimits.minPixelsPerFrameAt(30), 1 / 10);
    expect(TimelineZoomLimits.minPixelsPerFrameAt(60), 1 / 20);
  });

  test('a −/+ step is ×1.25 from any zoom and stops only at a bound', () {
    for (final zoom in [floor, 0.3, 0.5, 0.8, 1.0, 2.0, 3.0, 24.0, 80.0]) {
      final zoomedIn = TimelineZoomLimits.stepped(
        zoom,
        zoomIn: true,
        framesPerSecond: fps,
      );
      expect(
        zoomedIn,
        closeTo(
          (zoom * 1.25).clamp(floor, TimelineZoomLimits.maxPixelsPerFrame),
          1e-12,
        ),
        reason: '+ from $zoom',
      );
      final zoomedOut = TimelineZoomLimits.stepped(
        zoom,
        zoomIn: false,
        framesPerSecond: fps,
      );
      expect(
        zoomedOut,
        closeTo(
          (zoom / 1.25).clamp(floor, TimelineZoomLimits.maxPixelsPerFrame),
          1e-12,
        ),
        reason: '− from $zoom',
      );
    }
  });

  group('the frame axis\' one law keeps a line on one pixel at any zoom', () {
    test('from a pixel a cell, every boundary is a whole pixel, and a cell '
        'is its zoom give or take one', () {
      for (final zoom in [1.0, 1.3, 2.5, 7.3, 24.6, 95.9]) {
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

    testWidgets('the + and − buttons step ×1.25 exactly', (tester) async {
      expect(await press(tester, from: 3, zoomIn: true), 3.75);
      expect(await press(tester, from: 4, zoomIn: false), 3.2);
      expect(await press(tester, from: 1 / 2, zoomIn: true), 0.625);
    });

    testWidgets('🚨a drag across the old grid\'s gap — 1.7% to 2.8% — zooms '
        'at every step', (tester) async {
      final zooms = await pump(tester, pixelsPerFrame: 24);
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
      // 1.7% and 2.8% of the default 24px frame — the user's own stretch.
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
      final inside = [
        for (final zoom in zooms)
          if (zoom > 0.3 && zoom < 0.9) zoom,
      ];
      expect(inside.length, greaterThanOrEqualTo(moves), reason: 'every move');
      expect(
        inside.toSet().length,
        inside.length,
        reason: 'each move a zoom of its own — ↩️the grid gave every one of '
            'them the same 1/2 pixel a frame',
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
      expect(await press(tester, from: floor + 0.01, zoomIn: false), floor);
    });
  });
}
