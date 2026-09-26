import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';

/// I-22: the slider and the −/+ buttons ask ONE quantizer — whole pixels per
/// frame from one pixel up, whole FRAMES per pixel under it — and it lands on
/// the grid before it clamps, so no control writes a zoom off the grid or
/// outside the range. The floor is a second's width, so ten minutes fit.
void main() {
  const fps = 24;

  group('TimelineZoomLimits.quantize', () {
    test('rounds to whole pixels per frame from one pixel up', () {
      expect(TimelineZoomLimits.quantize(9.6, framesPerSecond: fps), 10);
      expect(TimelineZoomLimits.quantize(19.2, framesPerSecond: fps), 19);
      expect(TimelineZoomLimits.quantize(30, framesPerSecond: fps), 30);
      expect(TimelineZoomLimits.quantize(1.3, framesPerSecond: fps), 1);
    });

    test('under one pixel it rounds to whole FRAMES per pixel', () {
      expect(TimelineZoomLimits.quantize(0.8, framesPerSecond: fps), 1);
      expect(TimelineZoomLimits.quantize(0.55, framesPerSecond: fps), 1 / 2);
      expect(TimelineZoomLimits.quantize(0.45, framesPerSecond: fps), 1 / 2);
      expect(TimelineZoomLimits.quantize(0.3, framesPerSecond: fps), 1 / 3);
      expect(TimelineZoomLimits.quantize(0.16, framesPerSecond: fps), 1 / 6);
    });

    test('🚨lands on the grid BEFORE it clamps, so the bounds hold', () {
      expect(
        TimelineZoomLimits.quantize(0.01, framesPerSecond: fps),
        TimelineZoomLimits.minPixelsPerFrameAt(fps),
      );
      expect(
        TimelineZoomLimits.quantize(0, framesPerSecond: fps),
        TimelineZoomLimits.minPixelsPerFrameAt(fps),
        reason: 'a zero cell trips the grid assert and the anchor division',
      );
      expect(
        TimelineZoomLimits.quantize(400, framesPerSecond: fps),
        TimelineZoomLimits.maxPixelsPerFrame,
      );
    });
  });

  test('at the widest zoom ten minutes fit 1,800px at every rate, on the '
      'grid', () {
    for (final rate in ProjectFrameRate.presets) {
      final base = rate.countingBase;
      final floor = TimelineZoomLimits.minPixelsPerFrameAt(base);
      final framesPerPixel = 1 / floor;
      expect(
        framesPerPixel,
        closeTo(framesPerPixel.roundToDouble(), 1e-9),
        reason: '$base fps: the floor is a grid value',
      );
      expect(
        600 * base * floor,
        lessThanOrEqualTo(1800),
        reason: '$base fps: ten minutes inside 1,800px',
      );
      expect(
        600 * base / (framesPerPixel - 1),
        greaterThan(1800),
        reason: '$base fps: the next grid value in would not fit — the '
            'floor is the widest the rule needs, not wider',
      );
    }
    expect(TimelineZoomLimits.minPixelsPerFrameAt(24), 1 / 8);
    expect(TimelineZoomLimits.minPixelsPerFrameAt(30), 1 / 10);
    expect(TimelineZoomLimits.minPixelsPerFrameAt(60), 1 / 20);
  });

  test('a −/+ step always moves, across the whole grid, and stays on it', () {
    final floor = TimelineZoomLimits.minPixelsPerFrameAt(fps);
    final grid = <double>[
      for (var n = (1 / floor).round(); n >= 2; n -= 1) 1 / n,
      for (var px = 1; px <= TimelineZoomLimits.maxPixelsPerFrame; px += 1)
        px.toDouble(),
    ];
    for (final zoom in grid) {
      for (final zoomIn in [true, false]) {
        final next = TimelineZoomLimits.stepped(
          zoom,
          zoomIn: zoomIn,
          framesPerSecond: fps,
        );
        final atBound = zoomIn
            ? zoom == TimelineZoomLimits.maxPixelsPerFrame
            : zoom == floor;
        expect(
          atBound ? next == zoom : (zoomIn ? next > zoom : next < zoom),
          isTrue,
          reason: '${zoomIn ? '+' : '−'} from $zoom went to $next',
        );
        expect(grid, contains(next), reason: '$next is on the grid');
      }
    }
  });

  group('the −/+ buttons ask the same grid', () {
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

    // ↩️These used to be ONE case called 「a step that ×1.25 cannot move
    // takes one whole pixel」, and its comment promised a ROUND TRIP — but
    // the fixture hands the cluster a fixed zoom and only collects what it
    // asks for, so nothing round-tripped and only the + button was pressed.
    // One case per button, each starting where that button has somewhere
    // to go.
    testWidgets('the + button lands on the ×1.25 neighbour on the grid', (
      tester,
    ) async {
      // 3 × 1.25 = 3.75 → 4.
      expect(await press(tester, from: 3, zoomIn: true), 4);
    });

    testWidgets('the − button lands on the ÷1.25 neighbour on the grid', (
      tester,
    ) async {
      // 4 ÷ 1.25 = 3.2 → 3. ⛔It must not multiply: 4 × 1.25 would read 5.
      expect(await press(tester, from: 4, zoomIn: false), 3);
    });

    testWidgets('where ×1.25 rounds back onto the zoom it left, the button '
        'takes the next grid value', (tester) async {
      expect(await press(tester, from: 2, zoomIn: false), 1);
      expect(await press(tester, from: 1, zoomIn: false), 1 / 2);
      expect(await press(tester, from: 1 / 2, zoomIn: true), 1);
      expect(await press(tester, from: 1, zoomIn: true), 2);
    });

    testWidgets('at the floor the − button stands down', (tester) async {
      final floor = TimelineZoomLimits.minPixelsPerFrameAt(fps);
      final zooms = await pump(tester, pixelsPerFrame: floor);
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-zoom-out-button')),
      );
      expect(zooms, isEmpty, reason: 'nothing wider to go to');
    });

    testWidgets('a step never leaves the range', (tester) async {
      final floor = TimelineZoomLimits.minPixelsPerFrameAt(fps);
      expect(await press(tester, from: floor + 0.01, zoomIn: false), floor);
    });
  });
}
