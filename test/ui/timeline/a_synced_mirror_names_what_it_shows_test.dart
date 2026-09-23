import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import 'timeline_cell_probe.dart';

/// 🚨F-147 (유저 2026-09-16): 「기준레이어 엣지 움직일때 어태치 동기 레이어의
/// 해당 프레임블록의 프레임이름이 엣지 움직일때만 1로보이는 상황 발생. 정확한
/// 상황은 타임라인이 1--3--1--3--1--4--5--8 으로 되있는 프로젝트에서, 4의
/// 앞엣지나 뒷엣지를 움직일때 같은 어태치의 4 프레임이 움직일때만 가끔 1로보임
/// … 해당 관련로직 싹 점검」.
///
/// A synced mirror row is painted from the drag's PREVIEW of its base; its
/// names were read off the COMMITTED base at the same index, so a block
/// whose start had moved printed whatever the committed base held there.
/// ⛔Not one index: every block start the mirror paints mid-drag is read off
/// the painter the user looks at and must print what its base prints there
/// — on both grids, on both edges.
void main() {
  /// A base reading 1, 4, 5 — two commas each — under a synced attach row.
  (EditorSessionManager, LayerId, LayerId) fixture() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final base = s.activeLayer!.id;
    for (final (at, name) in [(0, '1'), (2, '4'), (4, '5')]) {
      s.selectFrameIndex(at);
      s.createDrawingAtCurrentFrame();
      expect(s.frameVerbs.renameSelectedFrame(name), isNull);
      s.edgeDrag.beginExposureEdgeDrag(
        layerId: base,
        blockStartIndex: at,
        edge: TimelineBlockEdge.end,
      );
      s.edgeDrag.updateExposureEdgeDrag(1);
      s.edgeDrag.endExposureEdgeDrag();
    }
    s.selectLayer(base);
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final mirror = s.activeLayer!.id;
    expect(
      [
        for (final entry in s.requireActiveCut.layers
            .firstWhere((layer) => layer.id == base)
            .timeline
            .entries)
          (entry.key, entry.value.length),
      ],
      [(0, 2), (2, 2), (4, 2)],
      reason: 'fixture: 1 4 5, two commas each',
    );
    return (s, base, mirror);
  }

  Widget host(
    EditorSessionManager session,
    TimelineOrientation orientation,
  ) => MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => TimelineTabHost(
          session: session,
          orientation: orientation,
          onOrientationChanged: (_) {},
          pixelsPerFrame: 24,
          onPixelsPerFrameChanged: (_) {},
          showSeconds: false,
          onShowSecondsChanged: (_) {},
        ),
      ),
    ),
  );

  for (final (orientation, prefix) in [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    for (final (edge, delta, what) in [
      (TimelineBlockEdge.start, -1, "4's lead edge into the 1 before it"),
      (TimelineBlockEdge.end, -1, "4's tail, pulling the 5 into 4's place"),
    ]) {
      testWidgets('$prefix: mid-drag of $what, the mirror prints what its '
          'base prints at every block start', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final (session, base, mirror) = fixture();
        addTearDown(session.dispose);
        await tester.pumpWidget(host(session, orientation));
        await tester.pumpAndSettle();

        expect(
          session.edgeDrag.beginExposureEdgeDrag(
            layerId: base,
            blockStartIndex: 2,
            edge: edge,
          ),
          isTrue,
        );
        session.edgeDrag.updateExposureEdgeDrag(delta);
        await tester.pump();

        final starts = <int>[
          for (var index = 0; index < 6; index += 1)
            if (timelineCellModel(tester, base.value, index, prefix: prefix)
                    .exposureState ==
                TimelineCellExposureState.drawingStart)
              index,
        ];
        expect(starts, hasLength(3), reason: 'LIVENESS: the base previews');
        expect(
          starts,
          isNot([0, 2, 4]),
          reason: 'LIVENESS: the drag moved a block start',
        );
        for (final index in starts) {
          expect(
            timelineCellModel(tester, mirror.value, index, prefix: prefix)
                .glyph,
            timelineCellModel(tester, base.value, index, prefix: prefix).glyph,
            reason: 'block start $index: 「어태치의 4 프레임이 … 1로보임」',
          );
        }
        session.edgeDrag.cancelExposureEdgeDrag();
      });
    }
  }
}
