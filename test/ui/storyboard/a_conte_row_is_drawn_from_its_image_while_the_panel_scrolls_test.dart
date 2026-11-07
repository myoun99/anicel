import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowDragTarget;
import 'package:anicel/src/ui/widgets/instant_tap_region.dart'
    show InstantTapRegion;
import 'package:anicel/src/ui/widgets/static_raster.dart';
import 'package:anicel/src/ui/widgets/still_raster.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q2 (유저 2026-11-07: 「콘티 행도
/// 그림으로(타임라인과 같은 법)」): every row of the conte — its rail's labels
/// and its strips, row for row — is a still region of its own (`stillRow`),
/// as the timeline's rows are. A scroll moves the rows' images; a row whose
/// content changes is drawn live in that frame.
void main() {
  const tracks = 6;

  Track track(int t) => Track(
    id: TrackId('t$t'),
    name: 'T$t',
    cuts: [
      Cut(
        id: CutId('t$t-cut'),
        name: 't$t cut',
        duration: 48,
        canvasSize: const CanvasSize(width: 1280, height: 720),
        camera: CutCamera.empty(),
        layers: [
          Layer(
            id: LayerId('t$t-conte'),
            name: 't$t conte',
            kind: LayerKind.storyboard,
            frames: const [],
          ),
        ],
      ),
    ],
    seLayers: [
      for (final s in ['S1', 'S2'])
        Layer(
          id: LayerId('t$t-$s'),
          name: 't$t $s',
          kind: LayerKind.se,
          frames: const [],
          // A chain of two on S1: its headers are lanes a carry re-orders,
          // each on a target of its own.
          effects: [
            if (s == 'S1')
              for (final e in ['e1', 'e2'])
                LayerEffect(
                  id: EffectId(e),
                  kind: EffectKind.brightnessContrast,
                  parameters: {'brightness': EffectParameter(value: 0.4)},
                ),
          ],
        ),
    ],
  );

  /// [count] tracks, on a surface short enough for their rows to scroll
  /// unless [tall].
  Future<EditorSessionManager> open(
    WidgetTester tester, {
    int count = tracks,
    bool tall = false,
  }) => pumpStoryboardHost(
    tester,
    Project(
      id: const ProjectId('still-conte-rows'),
      name: 'Still conte rows',
      createdAt: DateTime.utc(2026, 11, 7),
      tracks: [for (var t = 0; t < count; t += 1) track(t)],
    ),
    surface: Size(1400, tall ? 1100 : 520),
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

  final rail = find.byKey(
    const ValueKey<String>('storyboard-track-label-rail'),
  );

  bool onTheRail(Element element) {
    var found = false;
    element.visitAncestorElements((up) {
      found = up.widget.key == const ValueKey<String>(
        'storyboard-track-label-rail',
      );
      return !found;
    });
    return found;
  }

  /// Every row region the conte built, the rail's and the strips', where it
  /// stands.
  List<({RenderStillRaster region, Rect at, bool rail})> regionsOf(
    WidgetTester tester,
  ) => [
    for (final element in find.byType(StillRaster).evaluate())
      if (element.renderObject case final RenderStillRaster region
          when region.debugLabel == 'row')
        (
          region: region,
          at: tester.getRect(
            find.byElementPredicate((each) => identical(each, element)),
          ),
          rail: onTheRail(element),
        ),
  ];

  /// Where a row stands down the panel: its top and its height.
  String rowOf(Rect at) =>
      '${at.top.toStringAsFixed(1)}+${at.height.toStringAsFixed(1)}';

  Future<List<RenderStillRaster>> untilEveryRowIsAnImage(
    WidgetTester tester,
  ) async {
    for (var i = 0; i < 600; i += 1) {
      final regions = regionsOf(tester);
      if (regions.isNotEmpty &&
          regions.every((r) => r.region.debugDrawnFromImage)) {
        return [for (final r in regions) r.region];
      }
      await frame(tester);
    }
    fail('rows still drawn live after 600 frames: ${[
      for (final r in regionsOf(tester))
        if (!r.region.debugDrawnFromImage)
          '${rowOf(r.at)} ${r.region.standDown.name}',
    ]}');
  }

  ScrollPosition rowsScroll(WidgetTester tester) => [
    for (final element in find.byType(Scrollable).evaluate())
      if (element case StatefulElement(:final ScrollableState state))
        if (state.position.axis == Axis.vertical &&
            state.position.hasContentDimensions &&
            state.position.maxScrollExtent > 0)
          state.position,
  ].first;

  testWidgets('every row of the conte — its rail\'s labels and its strips, '
      'row for row — is a still region of its own', (tester) async {
    final session = await open(tester);
    session.layerSwitches.toggleLayerLanes(const LayerId('t0-S1'));
    await tester.pumpAndSettle();
    expect(rail, findsOneWidget, reason: '⛔premise: the rail is built');

    final regions = regionsOf(tester);
    final onRail = [for (final r in regions) if (r.rail) rowOf(r.at)];
    final onStrips = [for (final r in regions) if (!r.rail) rowOf(r.at)];
    expect(onRail, isNotEmpty, reason: '⛔premise: rows are built');
    expect(
      onRail.toSet(),
      hasLength(onRail.length),
      reason: 'one region a rail row',
    );
    expect(
      onStrips.toSet(),
      hasLength(onStrips.length),
      reason: 'one region a strip row',
    );
    expect(
      onStrips.toSet(),
      onRail.toSet(),
      reason: 'the strips\' regions stand row for row with the rail\'s',
    );
    // The rows themselves: an S row, its lanes, the conte row.
    for (final name in ['storyboard-layer-row-t0-S1', 'storyboard-layer-row-'
        't0-S2']) {
      final label = tester.getRect(find.named(name));
      expect(
        regions.where((r) => r.rail && r.at == label),
        hasLength(1),
        reason: '$name stands on a region of its own',
      );
    }
    for (final r in regions) {
      for (final other in regions) {
        if (!identical(r, other) && r.rail == other.rail) {
          expect(
            r.at.intersect(other.at).height > 0.01 &&
                r.at.intersect(other.at).width > 0.01,
            isFalse,
            reason: 'rows ${rowOf(r.at)} and ${rowOf(other.at)} overlap',
          );
        }
      }
    }
  });

  testWidgets('a scroll by whole pixels moves every row\'s image, and takes '
      'none again', (tester) async {
    await open(tester);
    final before = await untilEveryRowIsAnImage(tester);
    final taken = [for (final region in before) region.debugCaptureCount];

    final scroll = rowsScroll(tester);
    scroll.jumpTo(scroll.pixels + 14);
    for (var i = 0; i < StillRaster.stillFrames; i += 1) {
      await frame(tester);
      for (final (index, region) in before.indexed) {
        if (!region.attached) {
          continue;
        }
        expect(
          region.debugDrawnFromImage,
          isTrue,
          reason: 'row $index is drawn from its image ${i + 1} frame(s) on',
        );
        expect(
          region.debugCaptureCount,
          taken[index],
          reason: 'row $index took no image again',
        );
      }
    }
    expect(
      before.where((region) => region.attached),
      isNotEmpty,
      reason: '⛔premise: rows stayed',
    );
  });

  // 🚨IT ALONE, as the timeline's test has it (card conte-one-eye-repaints-
  // every-track, 11-08). ↩️Every track's V and conte rows were drawn live
  // with it: one S row's eye made every track and every cut of the project
  // anew (`project_tree_editor.dart`), and those rows are kept while their
  // cuts are the same objects.
  testWidgets('a row whose content changes is drawn live in that frame, and '
      'it alone', (tester) async {
    final session = await open(tester);
    await untilEveryRowIsAnImage(tester);
    final changed = rowOf(
      tester.getRect(find.named('storyboard-layer-row-t0-S2')),
    );

    session.layerSwitches.toggleLayerVisibility(const LayerId('t0-S2'));
    await tester.pump();

    final live = {
      for (final r in regionsOf(tester))
        if (r.region.debugDrawnFrom == null) rowOf(r.at),
    };
    expect(live, {changed}, reason: 't0-S2 shows it is hidden, and no row '
        'else changed');
  });

  testWidgets('a row drag\'s caret stands outside every row\'s region, and '
      'what a row lays out stays across inside it', (tester) async {
    // The scene the conte's carry test draws its lines in: one track, its
    // S1's lanes open.
    final session = await open(tester, count: 1, tall: true);
    session.layerSwitches.toggleLayerLanes(const LayerId('t0-S1'));
    await tester.pumpAndSettle();
    // As the conte's carry test drags (`a_conte_row_draws_its_lines_past_
    // what_it_owns_test.dart`): the first drag selects the row, a drag
    // inside the selection carries it.
    final grip = find.descendant(of: rail, matching: find.text('t0 S2')).first;
    await tester.dragFrom(
      tester.getCenter(grip),
      const Offset(InstantTapRegion.travelSlop + 2, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final start = tester.getCenter(grip);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    final caret = find.byWidgetPredicate(
      (widget) => switch (widget.key) {
        ValueKey<String>(:final value) => value.startsWith(
          'timeline-row-caret-',
        ),
        _ => false,
      },
    );
    // Down the S rows' zone, as the carry test goes: every line that stands
    // on the way, whichever row's target draws it — an S row's label, a
    // lane's, a chain header's.
    final zone = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-section-zone-t0-se')),
    );
    final seen = <String>{};
    for (var at = zone.top; at <= zone.bottom + 12; at += 4) {
      await gesture.moveTo(Offset(start.dx, at));
      await tester.pump();
      for (final line in caret.evaluate()) {
        final name = (line.widget.key! as ValueKey<String>).value;
        seen.add(name);
        expect(
          find.ancestor(
            of: find.byElementPredicate((each) => identical(each, line)),
            matching: find.byType(StillRaster),
          ),
          findsNothing,
          reason: '$name hangs across a row\'s boundary',
        );
      }
    }
    expect(seen, isNotEmpty, reason: '⛔premise: the carry draws its lines');
    // The line BEFORE a row is drawn in its own target's stack, over the
    // row above (the line after one, over every row — `RailRowLines`): a
    // region around a target would cut it at the row's edge. No carry here
    // lands before a row, so the targets are asked where they stand.
    final targets = find.descendant(
      of: rail,
      matching: find.byType(LayerRowDragTarget),
    );
    expect(targets, findsWidgets, reason: '⛔premise: the rail\'s targets');
    for (final target in targets.evaluate()) {
      expect(
        find.ancestor(
          of: find.byElementPredicate((each) => identical(each, target)),
          matching: find.byType(StillRaster),
        ),
        findsNothing,
        reason: 'the target of a '
            '${(target.widget as LayerRowDragTarget).subject.runtimeType} '
            'stands inside a row\'s region',
      );
    }

    for (final r in regionsOf(tester)) {
      final box = Offset.zero & r.region.size;
      void visit(RenderObject child) {
        if (child case RenderBox(:final size) when child.hasSize) {
          final at = MatrixUtils.transformRect(
            child.getTransformTo(r.region),
            Offset.zero & size,
          );
          if (!at.isEmpty) {
            expect(
              at.top >= box.top - 0.01 && at.bottom <= box.bottom + 0.01,
              isTrue,
              reason: 'row ${rowOf(r.at)} lays ${child.runtimeType} out at '
                  '$at, across past its box $box',
            );
          }
        }
        child.visitChildren(visit);
      }

      r.region.visitChildren(visit);
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
