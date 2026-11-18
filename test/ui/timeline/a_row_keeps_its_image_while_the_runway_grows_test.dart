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
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart'
    show timelineFrameWindowSpanFor;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart'
    show TimelineRowCellsPainter;
import 'package:anicel/src/ui/timeline/timeline_zoom_limits.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/named.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/named_finders.dart';
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
  const sounds = 2;
  const frames = 60;
  const block = 6;

  /// A row of [kind] whose blocks of [block] frames, each named, fill the
  /// cut.
  Layer row(String id, {LayerKind kind = LayerKind.animation}) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [
      for (var i = 0; i < frames ~/ block; i += 1)
        Frame(
          id: FrameId('$id-$i'),
          duration: 1,
          strokes: const [],
          name: '${i + 1}',
        ),
    ],
    timeline: {
      for (var i = 0; i < frames ~/ block; i += 1)
        i * block: TimelineExposure.drawing(FrameId('$id-$i'), length: block),
    },
  );

  /// A row whose lanes are twirled open, its Transform with them, and
  /// whose rotation turns from its first frame to its last — lane rows,
  /// their keys and the line between them.
  Layer keyed(String id) => row(id).copyWith(
    lanesExpanded: true,
    expandedLaneGroups: {transformGroupHeaderLane.laneId},
    transformTrack: TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(frames ~/ 2, 90),
    ),
  );

  // The S rows write their blocks' names through a span layout of their
  // own, laid by the frames' edges — a row's pieces as well as its box.
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
              keyed('k0'),
              for (var r = 0; r < layers; r += 1) row('r$r'),
            ],
          ),
        ],
        seLayers: [
          for (var s = 0; s < sounds; s += 1) row('s$s', kind: LayerKind.se),
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

  test('a row with a window draws its bucket\'s whole, wherever the axis '
      'ends — and repaints for no end alone', () {
    final bucket = ValueNotifier<int>(3);
    addTearDown(bucket.dispose);
    TimelineFrameGeometry endingAt(int end) => TimelineFrameGeometry(
      frameCellExtent: 12,
      frameStartIndex: 0,
      frameEndIndexExclusive: end,
      viewExtentPx: 600,
    ).windowed(originPx: 3 * 516.0 - 1024, extentPx: 600 + 2048);
    final short = endingAt(170);
    final long = endingAt(400);
    expect(
      short.rowDrawnFrames(bucket),
      long.rowDrawnFrames(bucket),
      reason: 'the axis\' end does not cut what the row draws',
    );
    expect(
      short.rowDrawnFrames(bucket).endIndexExclusive,
      greaterThan(170),
      reason: '⛔premise: the window reaches past the shorter end',
    );
    expect(short.drawsAs(long), isTrue);

    // A row with no window draws every frame of the axis, so its end is
    // what it draws to.
    const unwindowed = TimelineFrameGeometry(
      frameCellExtent: 12,
      frameStartIndex: 0,
      frameEndIndexExclusive: 170,
      viewExtentPx: 600,
    );
    expect(unwindowed.rowDrawnFrames(null).endIndexExclusive, 170);
    expect(
      unwindowed.drawsAs(
        const TimelineFrameGeometry(
          frameCellExtent: 12,
          frameStartIndex: 0,
          frameEndIndexExclusive: 400,
          viewExtentPx: 600,
        ),
      ),
      isFalse,
    );
  });

  // A lane's controls row — its name, keys and value — on the rail, and
  // turned on its side over the sheet's columns: the host builds both again
  // at every pass, and each keeps its image while its lane holds
  // (card a-rail-lane-row-is-drawn-again-on-every-host-pass).
  for (final (orientation, strip, scroll, controls) in [
    (
      TimelineOrientation.horizontal,
      'timeline-frame-ruler-scrub-area',
      'timeline-frame-scroll-viewport',
      'timeline-rail-row-',
    ),
    (
      TimelineOrientation.vertical,
      'xsheet-frame-rail-scrub-area',
      'xsheet-frame-vertical-viewport',
      'xsheet-header-',
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

      // The window reaches past the axis' end, and no tile is asked for
      // there: nothing a row draws stands past the end.
      final cells = [
        for (final paint in tester.widgetList<CustomPaint>(
          find.byType(CustomPaint),
        ))
          if (paint.painter case final TimelineRowCellsPainter painter)
            painter,
      ];
      expect(
        cells.where(
          (painter) =>
              painter.visibleFrameWindow().endIndexExclusive >
              painter.frameEndIndexExclusive,
        ),
        isNotEmpty,
        reason: '⛔premise: a row\'s window reaches past the end',
      );
      final pastTheEnd = [
        for (final painter in cells)
          for (final (start, end) in [
            ...painter.tileSpans.shown,
            ...painter.tileSpans.ahead,
          ])
            if (start >= painter.frameEndIndexExclusive)
              '($start, $end) past ${painter.frameEndIndexExclusive}',
      ];
      expect(pastTheEnd, isEmpty, reason: 'a tile past the axis\' end');

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
      // ⚠️Taken once the press has stood the playhead under the hand: a
      // keyed lane's row shows its value there — a change of its own, not
      // the growth's.
      final before = await untilEveryRowIsAnImage(tester);
      final taken = {
        for (final MapEntry(key: name, value: region) in before.entries)
          name: region.debugCaptureCount,
      };
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
      final stayed = [
        for (final MapEntry(key: name, value: region) in before.entries)
          if (region.attached) name,
      ];
      expect(
        stayed.where((name) => name.endsWith('-s0')),
        isNotEmpty,
        reason: '⛔premise: an S row stayed, as well as the drawings\'',
      );
      expect(
        stayed.where((name) => name.endsWith('-k0-rotation')),
        isNotEmpty,
        reason: '⛔premise: a lane row stayed, its keys with it',
      );
      expect(
        stayed.where(
          (name) => name.startsWith(controls) && name.endsWith('-k0-rotation'),
        ),
        isNotEmpty,
        reason: '⛔premise: a lane\'s controls row stayed, its value with it',
      );
      expect(live, isEmpty, reason: 'the runway grew under them');
      await hand.up();
      await tester.pumpAndSettle();
    });

    // 🔬The Surface's verify, 11-08: a pick of another layer moves the
    // current row, which only the two rows it leaves and lands on show —
    // and every lane row of the rail and the sheet drew itself again and
    // let its image go, their layout builders laid out again by a cell
    // built again at every move.
    testWidgets('the ${orientation.name} grid\'s rows keep their images '
        'through a pick of another layer, but the two it moves between', (
      tester,
    ) async {
      await pumpTimelineHost(tester, project(), orientation: orientation);
      final before = await untilEveryRowIsAnImage(tester);
      final taken = {
        for (final MapEntry(key: name, value: region) in before.entries)
          name: region.debugCaptureCount,
      };
      expect(
        before.keys.where(
          (name) => name.startsWith(controls) && name.endsWith('-k0-rotation'),
        ),
        isNotEmpty,
        reason: '⛔premise: a lane\'s controls row stands',
      );
      final prefix = orientation == TimelineOrientation.horizontal
          ? 'timeline'
          : 'xsheet';
      await tester.tap(
        find.named('$prefix-layer-name-r3').first,
        warnIfMissed: false,
      );
      await tester.pump();
      await frame(tester);

      final drawnAgain = [
        for (final MapEntry(key: name, value: region) in before.entries)
          if (!region.debugDrawnFromImage ||
              region.debugCaptureCount != taken[name])
            name,
      ];
      expect(
        drawnAgain,
        unorderedEquals(['${controls}k0-row', '${controls}r3-row']),
        reason: 'the current row moved from k0 to r3, and no other row '
            'shows it',
      );
      await tester.pumpAndSettle();
    });
  }
}
