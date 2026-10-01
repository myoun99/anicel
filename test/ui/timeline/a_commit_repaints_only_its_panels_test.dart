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
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/repaint_strays.dart';

/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림 … 무거운
/// 컷일수록 심해짐」): AN EDIT'S COMMIT REPAINTS THE PANELS IT CHANGES — NOT
/// THE PAGE AROUND THEM.
///
/// Every panel host hears the session and builds itself again on every
/// edit. The sheets did it on a layer of their own; the frame panels and
/// the canvas area did it bare, in the dock's and the workspace's layout
/// scopes — so a comma drag's release laid those out again, and a layout
/// ends by asking for a paint of everything up to the boundary above it:
/// the page's root (443 objects on the default layout, the whole strip,
/// the rails and the dock chrome) around the panels that changed.
///
/// This releases a comma drag and reads, at the release's frame, every
/// boundary waiting to repaint that is neither a tick layer's (every panel
/// host rides one) nor the canvas's. A first release goes before it:
/// what the FIRST edit of a session changes once (the undo door lighting)
/// is not what every edit costs.
void main() {
  const frames = 96;

  Project project() => Project(
    id: const ProjectId('commit-layers'),
    name: 'Commit layers',
    createdAt: DateTime.utc(2026, 9, 30),
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
              for (final row in const ['a', 'b'])
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
        seLayers: [
          Layer(
            id: const LayerId('s1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: const [],
          ),
        ],
      ),
    ],
  );

  String nameOf(RenderObject node) => nameOfBoundary(node, depth: 40);

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  final views = <String, List<String>>{
    'timeline': [],
    'timeline with its lanes open': ['legend-lanes-toggle'],
    'x-sheet': ['timeline-orientation-toggle-button'],
    'storyboard': ['timeline-mode-storyboard-button'],
  };
  for (final MapEntry(key: view, value: taps) in views.entries) {
    testWidgets('a comma drag released with the $view showing repaints its '
        'panels\' layers and the canvas and nothing around them', (
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
      for (final key in taps) {
        await tap(tester, key);
      }
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;

      Future<void> dragTheComma(int by) async {
        expect(
          session.edgeDrag.beginExposureEdgeDrag(
            layerId: const LayerId('a'),
            blockStartIndex: 12,
            edge: TimelineBlockEdge.end,
          ),
          isTrue,
          reason: 'premise: the block is there to grab',
        );
        session.edgeDrag.updateExposureEdgeDrag(by);
        await tester.pump();
      }

      await dragTheComma(2);
      session.edgeDrag.endExposureEdgeDrag();
      await tester.pumpAndSettle();

      await dragTheComma(-2);
      final before = session.historyManager.canUndo;
      session.edgeDrag.endExposureEdgeDrag();
      expect(before, isTrue, reason: 'premise: the first release committed');
      // The release's frame, run to its layout and stopped before the
      // paint, so what waits to repaint can be read.
      await tester.pump(null, EnginePhase.layout);
      final allowed = tickLayersAndCanvas(tester);
      final strays = {
        for (final root in tester.binding.renderViews)
          ...repaintStrays(root, allowed: allowed),
      };
      await tester.pumpAndSettle();
      expect(
        session.requireActiveCut.layers
            .firstWhere((layer) => layer.id == const LayerId('a'))
            .timeline[12]
            ?.length,
        6,
        reason: 'premise: the second release committed its comma back',
      );
      expect(
        strays.map(nameOf),
        isEmpty,
        reason: strays.map(nameOf).join('\n\n'),
      );
    });
  }
}
