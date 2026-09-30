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
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import '../../helpers/frame_census.dart';

/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림」): AN EDIT'S
/// COMMIT REBUILDS NO RAIL ROW'S DRAG.
///
/// Every edit rebuilds the timeline host, and the rail kept each row's body
/// (its memo) but wrapped it in a fresh drag target every time — the host
/// made its drag hooks anew each build, so nothing about the wrapper could
/// be kept: ~170 elements on 24 rows, at every commit. The host binds its
/// hooks once now, and the row's memo keeps the wrapped row.
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

  testWidgets('a comma drag released rebuilds no rail row\'s drag target', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: project()),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    expect(
      find.byType(LayerRowDragTarget),
      findsWidgets,
      reason: 'premise: the rail rows wear their drag targets',
    );

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

    // A first release first: what the FIRST edit changes once is not what
    // every edit costs.
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

    expect(
      release.rebuilt,
      contains(TimelineTabHost),
      reason: 'premise: the commit rebuilt the host the rail hangs from',
    );
    expect(
      release.rebuilt.where((type) => type == LayerRowDragTarget),
      isEmpty,
    );
  });

  // A kept wrapper is only right while it is the one a fresh build would
  // make: the oracle is the grid mounted afresh (the x-sheet and back), whose
  // rail has kept nothing.
  group('a kept row drag is the one a fresh rail makes', () {
    Future<EditorSessionManager> openApp(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(initialProject: project()),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
    }

    Future<void> remountTheGrid(WidgetTester tester) async {
      final flip = find.byKey(
        const ValueKey<String>('timeline-orientation-toggle-button'),
      );
      await tester.tap(flip);
      await tester.pumpAndSettle();
      await tester.tap(flip);
      await tester.pumpAndSettle();
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

    testWidgets('its caret line, after the rows move and the last one goes', (
      tester,
    ) async {
      final session = await openApp(tester);
      // The top row (the last layer) goes down two rows, through its own
      // wrapper — the way a hand moves it.
      final top = targetOf(tester, 'd');
      top.hooks!.onBegin(top.subject);
      top.onCrossed(2, null, 0);
      top.hooks!.onEnd();
      await tester.pumpAndSettle();
      final moved = caretLines(tester);
      await remountTheGrid(tester);
      expect(moved, caretLines(tester), reason: 'after the move');

      // The bottom row goes: the one above it becomes the last row, at the
      // slot it already had.
      session.selectLayer(const LayerId('a'));
      session.layerVerbs.deleteActiveLayer();
      await tester.pumpAndSettle();
      final shortened = caretLines(tester);
      await remountTheGrid(tester);
      expect(shortened, caretLines(tester), reason: 'after the delete');
    });

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
