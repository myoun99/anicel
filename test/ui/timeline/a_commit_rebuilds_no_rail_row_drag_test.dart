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
}
