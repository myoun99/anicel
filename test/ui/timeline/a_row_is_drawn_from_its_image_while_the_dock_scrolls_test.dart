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
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q1 (유저 2026-11-07: 「스크롤하는
/// 동안에도 행은 그림으로」): every row of the timeline's dock — the frame
/// cells and the rail's controls, on both grids — is a still region of its
/// own (`stillRow`). A scroll moves the rows' images; a row whose content
/// changes is drawn live in that frame, and it alone.
void main() {
  const layers = 40;
  // Long enough to scroll along the frames too.
  const frames = 240;
  const block = 12;

  Project project() => Project(
    id: const ProjectId('still-rows'),
    name: 'Still rows',
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

  /// Every row the grid built, by its name, with the still regions inside
  /// it — the frame cells' rows and the rail's.
  Map<String, List<RenderStillRaster>> rowsOf(WidgetTester tester) => {
    for (final row in find
        .namedWhere(
          (name) =>
              (name.startsWith('timeline-row-') &&
                  !name.startsWith('timeline-row-cells-')) ||
              name.startsWith('timeline-rail-row-'),
        )
        .evaluate())
      nameOf(row)!: tester.renderObjectList<RenderStillRaster>(
        find.descendant(
          of: find.byElementPredicate((element) => identical(element, row)),
          matching: find.byType(StillRaster),
        ),
      ).toList(),
  };

  /// The layer a row's name stands for: `timeline-row-r5-cells`,
  /// `timeline-rail-row-r5-row`.
  String layerOf(String row) =>
      row.substring(row.indexOf('row-') + 'row-'.length).split('-').first;

  /// Frames until every row the grid built is drawn from its image — one
  /// image a frame, across all of them.
  Future<Map<String, RenderStillRaster>> untilEveryRowIsAnImage(
    WidgetTester tester,
  ) async {
    for (var i = 0; i < 600; i += 1) {
      final rows = rowsOf(tester);
      if (rows.values.every(
        (regions) =>
            regions.length == 1 && regions.single.debugDrawnFromImage,
      )) {
        return {
          for (final MapEntry(key: name, value: regions) in rows.entries)
            name: regions.single,
        };
      }
      await frame(tester);
    }
    final live = [
      for (final MapEntry(key: name, value: regions) in rowsOf(tester).entries)
        if (regions.length != 1)
          '$name on ${regions.length} regions'
        else if (!regions.single.debugDrawnFromImage)
          '$name ${regions.single.standDown.name}',
    ];
    fail('rows still drawn live after 600 frames: $live');
  }

  List<ScrollPosition> scrollsAlong(WidgetTester tester, Axis axis) => [
    for (final element in find.byType(Scrollable).evaluate())
      if (element case StatefulElement(:final ScrollableState state))
        if (state.position.axis == axis &&
            state.position.hasContentDimensions &&
            state.position.maxScrollExtent > 0)
          state.position,
  ];

  for (final orientation in TimelineOrientation.values) {
    testWidgets('every row of the ${orientation.name} grid — its cells, its '
        'lanes and its rail — is a still region of its own', (tester) async {
      final session = await pumpTimelineHost(
        tester,
        project(),
        orientation: orientation,
      );
      final horizontal = orientation == TimelineOrientation.horizontal;
      // The rail lists the stack from its top; the sheet, raw.
      final shown = [
        for (var i = 0; i < 6; i += 1) 'r${horizontal ? layers - 1 - i : i}',
      ];
      session.layerSwitches.toggleLayerLanes(LayerId(shown.first));
      await tester.pumpAndSettle();
      final prefix = horizontal ? 'timeline' : 'xsheet';
      final axisWord = horizontal ? 'row' : 'column';
      final lanes = find.namedWhere(
        (name) =>
            name.startsWith('$prefix-$axisWord-${shown.first}-') &&
            !name.endsWith('-cells'),
      );
      expect(lanes, findsWidgets, reason: '⛔premise: its lanes are shown');

      for (final id in shown) {
        // The cells: one region, and it is the row's box.
        final cells = find.named(
          horizontal
              ? 'timeline-row-$id-cells'
              : 'xsheet-column-$id-cells',
        );
        expect(cells, findsOneWidget, reason: '⛔premise: $id is built');
        final region = tester.renderObject<RenderStillRaster>(
          find.descendant(of: cells, matching: find.byType(StillRaster)),
        );
        expect(
          region.size,
          tester.getSize(cells),
          reason: '$id\'s cells are the region\'s box',
        );
        // The rail's row (the sheet's header): one region over its name.
        expect(
          find.ancestor(
            of: find.named('$prefix-layer-name-$id'),
            matching: find.byType(StillRaster),
          ),
          findsOneWidget,
          reason: '$id\'s controls stand on a region of their own',
        );
      }
      for (final lane in lanes.evaluate()) {
        expect(
          find.descendant(
            of: find.byElementPredicate((element) => identical(element, lane)),
            matching: find.byType(StillRaster),
          ),
          findsOneWidget,
          reason: '${nameOf(lane)} is a region of its own',
        );
      }
      if (horizontal) {
        final railLanes = find.namedWhere(
          (name) =>
              name.startsWith('timeline-rail-row-${shown.first}-') &&
              !name.endsWith('-row'),
        );
        expect(railLanes, findsWidgets, reason: '⛔premise');
        for (final lane in railLanes.evaluate()) {
          expect(
            find.descendant(
              of: find.byElementPredicate(
                (element) => identical(element, lane),
              ),
              matching: find.byType(StillRaster),
            ),
            findsOneWidget,
            reason: '${nameOf(lane)} is a region of its own',
          );
        }
      }
    });
  }

  for (final axis in Axis.values) {
    testWidgets('a scroll by whole pixels ${axis.name}ly moves every row\'s '
        'image, and takes none again', (tester) async {
      await pumpTimelineHost(tester, project());
      final scrolls = scrollsAlong(tester, axis);
      expect(scrolls, isNotEmpty, reason: '⛔premise: the rows scroll');
      final before = await untilEveryRowIsAnImage(tester);
      final taken = {
        for (final MapEntry(key: name, value: region) in before.entries)
          name: region.debugCaptureCount,
      };

      // Within the frame axis' window: a scroll that crosses no bucket
      // moves the rows and repaints none of them.
      final by = axis == Axis.vertical ? 14.0 : 3.0;
      for (final scroll in scrolls) {
        scroll.jumpTo(scroll.pixels + by);
      }
      for (var i = 0; i < StillRaster.stillFrames; i += 1) {
        await frame(tester);
        for (final MapEntry(key: name, value: region) in before.entries) {
          if (!region.attached) {
            continue;
          }
          expect(
            region.debugDrawnFromImage,
            isTrue,
            reason: '$name is drawn from its image ${i + 1} frame(s) on',
          );
          expect(
            region.debugCaptureCount,
            taken[name],
            reason: '$name took no image again',
          );
        }
      }
      expect(
        before.values.where((region) => region.attached),
        isNotEmpty,
        reason: '⛔premise: rows stayed',
      );
    });
  }

  testWidgets('a row whose content changes is drawn live in that frame, and '
      'it alone', (tester) async {
    final session = await pumpTimelineHost(tester, project());
    final rows = await untilEveryRowIsAnImage(tester);

    session.layerSwitches.toggleLayerVisibility(const LayerId('r36'));
    await tester.pump();

    final live = [
      for (final MapEntry(key: name, value: region) in rows.entries)
        if (region.attached && !region.debugDrawnFromImage) name,
    ];
    expect(live, isNotEmpty, reason: 'r36 shows it is hidden');
    expect(
      live.map(layerOf).toSet(),
      {'r36'},
      reason: 'only r36 changed: $live',
    );
  });

  testWidgets('a row drag\'s caret stands outside every row\'s region, and '
      'what a row lays out stays across inside it', (tester) async {
    await pumpTimelineHost(tester, project());
    final grip = find.named('timeline-layer-name-r36');
    await tester.drag(grip, const Offset(30, 0));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -42));
    await tester.pump();

    final caret = find.byWidgetPredicate(
      (widget) => switch (widget.key) {
        ValueKey<String>(:final value) => value.startsWith(
          'timeline-row-caret-',
        ),
        _ => false,
      },
    );
    expect(caret, findsOneWidget, reason: '⛔premise: the caret is drawn');
    expect(
      find.ancestor(of: caret, matching: find.byType(StillRaster)),
      findsNothing,
      reason: 'the caret hangs across a row\'s boundary',
    );

    for (final MapEntry(key: name, value: regions) in rowsOf(tester).entries) {
      final region = regions.single;
      final box = Offset.zero & region.size;
      void visit(RenderObject child) {
        if (child case RenderBox(:final size) when child.hasSize) {
          final at = MatrixUtils.transformRect(
            child.getTransformTo(region),
            Offset.zero & size,
          );
          if (!at.isEmpty) {
            expect(
              at.top >= box.top - 0.01 && at.bottom <= box.bottom + 0.01,
              isTrue,
              reason: '$name lays ${child.runtimeType} out at $at, '
                  'across past its box $box',
            );
          }
        }
        child.visitChildren(visit);
      }

      region.visitChildren(visit);
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
