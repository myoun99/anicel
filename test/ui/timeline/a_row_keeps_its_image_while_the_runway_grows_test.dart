import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart'
    show timelineFrameWindowSpanFor;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/widgets/named.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/timeline_host.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q8 (유저 2026-11-07, 「한다 — 행
/// 그림 영역을 창 상자로」): a row's still region is its WINDOW, and its
/// pieces draw what the window holds — not what the axis' end clips. So the
/// runway a drag past the end grows keeps every row's image: nothing a row
/// draws stood past the end, and its region is the same pixels wide.
/// ↩️The region was the row's box, which reaches the axis' end: each growth
/// widened every row's region and painted every row again.
///
/// ⚠️Not a crossing of the window's span, which moves what the window
/// holds — the growth alone, in a frame that crosses none.
void main() {
  const layers = 8;
  const frames = 60;
  const block = 6;

  Project project() => Project(
    id: const ProjectId('runway-rows'),
    name: 'Runway rows',
    createdAt: DateTime.utc(2026, 11, 7),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: frames,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (var r = 0; r < layers; r += 1)
                Layer(
                  id: LayerId('r$r'),
                  name: 'R$r',
                  frames: [
                    for (var i = 0; i < frames ~/ block; i += 1)
                      Frame(
                        id: FrameId('r$r-$i'),
                        duration: 1,
                        strokes: const [],
                        name: '${i + 1}',
                      ),
                  ],
                  timeline: {
                    for (var i = 0; i < frames ~/ block; i += 1)
                      i * block: TimelineExposure.drawing(
                        FrameId('r$r-$i'),
                        length: block,
                      ),
                  },
                ),
            ],
          ),
        ],
      ),
    ],
  );

  setUp(() {
    StillRaster.debugCachePaysOverride = true;
    StaticRaster.debugCapturePaysOverride = false;
  });
  tearDown(() {
    StillRaster.debugCachePaysOverride = null;
    StaticRaster.debugCapturePaysOverride = null;
  });

  Future<void> frame(WidgetTester tester) async {
    tester.binding.scheduleFrame();
    await tester.pump();
  }

  /// The name of the row [element] stands in ([Named]).
  String rowNameOf(Element element) {
    String? name;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget case Named(name: final named?)) {
        name = named;
        return false;
      }
      return true;
    });
    return name ?? '${element.widget}';
  }

  /// Every row's still region the grid built, by the row it stands in.
  Map<String, RenderStillRaster> rowsOf(WidgetTester tester) => {
    for (final element in find.byType(StillRaster).evaluate())
      if (element.renderObject case final RenderStillRaster region
          when region.debugLabel == 'row')
        rowNameOf(element): region,
  };

  Future<Map<String, RenderStillRaster>> untilEveryRowIsAnImage(
    WidgetTester tester,
  ) async {
    for (var i = 0; i < 600; i += 1) {
      final rows = rowsOf(tester);
      if (rows.values.every((region) => region.debugDrawnFromImage)) {
        return rows;
      }
      await frame(tester);
    }
    final live = [
      for (final MapEntry(key: name, value: region) in rowsOf(tester).entries)
        if (!region.debugDrawnFromImage) '$name ${region.standDown.name}',
    ];
    fail('rows still drawn live after 600 frames: $live');
  }

  for (final (orientation, strip, scroll) in [
    (
      TimelineOrientation.horizontal,
      'timeline-frame-ruler-scrub-area',
      'timeline-frame-scroll-viewport',
    ),
    (
      TimelineOrientation.vertical,
      'xsheet-frame-rail-scrub-area',
      'xsheet-frame-vertical-viewport',
    ),
  ]) {
    testWidgets('the ${orientation.name} grid\'s rows keep their images '
        'through a growth of the runway', (tester) async {
      await pumpTimelineHost(tester, project(), orientation: orientation);
      final axis = orientation == TimelineOrientation.horizontal
          ? Axis.horizontal
          : Axis.vertical;
      final position = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byKey(ValueKey<String>(scroll)),
              matching: find.byType(Scrollable),
              matchRoot: true,
            ),
          )
          .firstWhere((state) => state.position.axis == axis)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final before = await untilEveryRowIsAnImage(tester);
      final taken = {
        for (final MapEntry(key: name, value: region) in before.entries)
          name: region.debugCaptureCount,
      };

      const cell = TimelineZoomLimits.referencePixelsPerFrame;
      final spanPx = timelineFrameWindowSpanFor(cell) * cell;
      int bucket() => (position.pixels / spanPx).floor();
      final area = tester.getRect(find.byKey(ValueKey<String>(strip)));
      Offset at(double along) => offsetAlong(
        axis,
        along: startAlong(axis, area) + along,
        across: partAcross(axis, area.center),
      );
      final hand = await tester.startGesture(
        at(extentAlong(axis, area.size) - 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final built = position.maxScrollExtent;
      var stood = bucket();
      var past = extentAlong(axis, area.size) + 4;
      for (var move = 0; position.maxScrollExtent <= built; move += 1) {
        expect(move, lessThan(400), reason: '⛔premise: the runway grew');
        stood = bucket();
        past += 0.5;
        await hand.moveTo(at(past));
        await tester.pump();
      }
      expect(bucket(), stood, reason: '⛔premise: the growth crossed no span');

      final live = [
        for (final MapEntry(key: name, value: region) in before.entries)
          if (region.attached &&
              (!region.debugDrawnFromImage ||
                  region.debugCaptureCount != taken[name]))
            '$name (${region.standDown.name}, took '
                '${region.debugCaptureCount - taken[name]!})',
      ];
      expect(
        before.values.where((region) => region.attached),
        isNotEmpty,
        reason: '⛔premise: rows stayed',
      );
      expect(live, isEmpty, reason: 'the runway grew under them');
      await hand.up();
      await tester.pumpAndSettle();
    });
  }
}
