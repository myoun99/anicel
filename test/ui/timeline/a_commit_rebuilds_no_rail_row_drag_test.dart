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
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_view_cluster.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import '../../helpers/frame_census.dart';
import '../../helpers/home_page_probes.dart' show showStoryboardPanel;

/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림」): AN EDIT'S
/// COMMIT REBUILDS NO RAIL ROW'S DRAG.
///
/// Every edit rebuilds the timeline host, and the rail kept each row's body
/// (its memo) but wrapped it in a fresh drag target every time — the host
/// made its drag hooks anew each build, so nothing about the wrapper could
/// be kept: ~170 elements on 24 rows, at every commit. The host binds its
/// hooks once now, and the row's memo keeps the wrapped row.
///
/// The x-sheet kept nothing at all: every header of the sheet — the rail
/// row turned on its side — was built again at every commit (8,276 elements
/// on 24 layers). It keeps them by the rail's memo now.
void main() {
  Project project() => Project(
    id: const ProjectId('rail-drags'),
    name: 'Rail drags',
    createdAt: DateTime.utc(2026, 9, 30),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-0'),
            name: 'cut-0',
            duration: 96,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (final row in const ['a', 'b', 'c', 'd'])
                Layer(
                  id: LayerId(row),
                  name: row.toUpperCase(),
                  frames: [
                    for (var i = 0; i < 8; i += 1)
                      Frame(
                        id: FrameId('$row-$i'),
                        duration: 1,
                        strokes: const [],
                        name: '${i + 1}',
                      ),
                  ],
                  timeline: {
                    for (var i = 0; i < 8; i += 1)
                      i * 6: TimelineExposure.drawing(
                        FrameId('$row-$i'),
                        length: 6,
                      ),
                  },
                ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> flip(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
  }

  Future<EditorSessionManager> openApp(
    WidgetTester tester, {
    bool sheet = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project()),
      ),
    );
    await tester.pumpAndSettle();
    if (sheet) {
      await flip(tester);
    }
    expect(
      find.byType(XSheetTimelineGrid),
      sheet ? findsOneWidget : findsNothing,
      reason: 'premise: the grid is the one the test names',
    );
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  /// What the frame of a comma drag's release rebuilds — after a first
  /// release, since what the FIRST edit changes once is not what every edit
  /// costs.
  Future<List<Type>> rebuiltByARelease(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    void dragTheComma(int by) {
      expect(
        session.edgeDrag.beginExposureEdgeDrag(
          layerId: const LayerId('b'),
          blockStartIndex: 12,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
        reason: 'premise: the block is there to grab',
      );
      session.edgeDrag.updateExposureEdgeDrag(by);
    }

    dragTheComma(2);
    await tester.pump();
    session.edgeDrag.endExposureEdgeDrag();
    await tester.pumpAndSettle();

    dragTheComma(-2);
    await tester.pump();
    final release = await frameCensus(
      tester,
      session.edgeDrag.endExposureEdgeDrag,
    );
    await tester.pumpAndSettle();
    return release.rebuilt;
  }

  // The x-sheet's header strip is the rail turned on its side, and keeps
  // its headers by the rail's own memo.
  for (final sheet in [false, true]) {
    final rows = sheet ? 'x-sheet header' : 'rail row';
    testWidgets('a comma drag released rebuilds no $rows nor its drag '
        'target', (tester) async {
      final session = await openApp(tester, sheet: sheet);
      expect(
        find.byType(LayerRowDragTarget),
        findsWidgets,
        reason: 'premise: the ${rows}s wear their drag targets',
      );
      final rebuilt = await rebuiltByARelease(tester, session);

      expect(
        rebuilt,
        contains(TimelineTabHost),
        reason: 'premise: the commit rebuilt the host the ${rows}s hang from',
      );
      expect(
        rebuilt.where(
          (type) =>
              type == TimelineLayerControlsRow || type == LayerRowDragTarget,
        ),
        isEmpty,
      );
    });
  }

  // F-244 ⑧: the view cluster is kept by what it shows — a commit moves
  // none of it (10-01: 47 elements, rebuilt at every one).
  for (final sheet in [false, true]) {
    testWidgets('a comma drag released rebuilds none of the view cluster '
        '(${sheet ? 'x-sheet' : 'timeline'})', (tester) async {
      final session = await openApp(tester, sheet: sheet);
      final rebuilt = await rebuiltByARelease(tester, session);
      expect(
        rebuilt,
        contains(TimelineTabHost),
        reason: 'premise: the commit rebuilt the host the cluster hangs from',
      );
      expect(rebuilt, isNot(contains(TimelineViewCluster)));
    });
  }

  testWidgets('a comma drag released rebuilds none of the view cluster '
      '(storyboard)', (tester) async {
    final session = await openApp(tester);
    await showStoryboardPanel(tester);
    final rebuilt = await rebuiltByARelease(tester, session);
    expect(
      rebuilt,
      contains(StoryboardTabHost),
      reason: 'premise: the commit rebuilt the host the cluster hangs from',
    );
    expect(rebuilt, isNot(contains(TimelineViewCluster)));
  });

  // A kept wrapper is only right while it is the one a fresh build would
  // make: the oracle is the grid mounted afresh (the other grid and back),
  // whose rows have kept nothing.
  group('a kept row drag is the one a fresh grid makes', () {
    Future<void> remountTheGrid(WidgetTester tester) async {
      await flip(tester);
      await flip(tester);
    }

    LayerRowDragTarget targetOf(WidgetTester tester, String layer) =>
        tester.widget<LayerRowDragTarget>(
          find.byWidgetPredicate(
            (widget) =>
                widget is LayerRowDragTarget &&
                widget.subject == LayerRowSubject(LayerId(layer)),
          ),
        );

    Map<LayerRowDragSubject, (int, bool)> caretLines(WidgetTester tester) => {
      for (final target in tester.widgetList<LayerRowDragTarget>(
        find.byType(LayerRowDragTarget),
      ))
        target.subject: (target.slotBefore, target.isLastRow),
    };

    for (final sheet in [false, true]) {
      testWidgets('its caret line, after the rows move and the last one goes'
          '${sheet ? ' (x-sheet)' : ''}', (tester) async {
        final session = await openApp(tester, sheet: sheet);
        List<LayerId> order() => [for (final layer in session.layers) layer.id];
        final before = order();
        // The top layer goes two rows toward the bottom one, through its own
        // wrapper — the way a hand moves it. The rail lists the stack
        // reversed and the sheet raw, so the steps run the other way there.
        final top = targetOf(tester, 'd');
        top.hooks!.onBegin(top.subject);
        top.onCrossed(sheet ? -2 : 2, null, 0);
        top.hooks!.onEnd();
        await tester.pumpAndSettle();
        expect(order(), isNot(before), reason: 'premise: the move moved it');
        final moved = caretLines(tester);
        await remountTheGrid(tester);
        expect(moved, caretLines(tester), reason: 'after the move');

        // The bottom layer goes: every row's place among the rest moves or
        // one becomes the last, and a kept wrapper must follow.
        session.selectLayer(const LayerId('a'));
        session.layerVerbs.deleteActiveLayer();
        await tester.pumpAndSettle();
        final shortened = caretLines(tester);
        await remountTheGrid(tester);
        expect(shortened, caretLines(tester), reason: 'after the delete');
      });
    }

    testWidgets('its crossing, after the row below it opens its lanes', (
      tester,
    ) async {
      final session = await openApp(tester);
      final kept = targetOf(tester, 'd');
      session.railView.expandedLaneLayerIds.value = {const LayerId('c')};
      await tester.pumpAndSettle();
      expect(
        identical(targetOf(tester, 'd'), kept),
        isTrue,
        reason: 'premise: the top row\'s wrapper was kept — its slot and its '
            'place as a row did not move',
      );

      int? slotCrossingTwoRows() {
        final target = targetOf(tester, 'd');
        target.hooks!.onBegin(target.subject);
        target.onCrossed(2, null, 0);
        final slot = session.layerRowDragVerbs.inFlight.value?.caretSlot;
        target.hooks!.onCancel();
        return slot;
      }

      final throughTheKept = slotCrossingTwoRows();
      await tester.pumpAndSettle();
      await remountTheGrid(tester);
      expect(throughTheKept, isNotNull, reason: 'premise: the drag ran');
      expect(throughTheKept, slotCrossingTwoRows());
    });
  });
}
