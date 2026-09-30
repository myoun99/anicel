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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/repaint_strays.dart';

/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림 … 무거운
/// 컷일수록 심해짐」): A DRAG STEP REPAINTS ITS TICK LAYERS AND THE CANVAS —
/// NOTHING ELSE.
///
/// A drag publishes its preview on every step, the way playback moves
/// its cursor on every tick — and what the preview moves (the dragged row,
/// the cut's end and its margin on the ruler and the body) rebuilt in the
/// build scope of the grid's `LayoutBuilder`, which lays that LayoutBuilder
/// out again, and a layout ends by asking for a paint of everything up to
/// the boundary above it: the panel. Measured on the user's own cut (FU 301,
/// 18 rows, 09-30): every step repainted the layer rail's controls — 373
/// objects — around the one row that moved. [TickLayer] is where a tick is
/// laid out and painted alone, and a drag step is a tick.
///
/// This reads, at each of a run of steps, every boundary waiting to repaint,
/// and names any that waits at EVERY one of them and is neither a tick layer
/// (or inside one) nor a canvas — whose picture following the drag IS the
/// step.
void main() {
  const frames = 96;

  /// Two animation rows of six-frame blocks, and an S row for the lanes.
  Project project() => Project(
    id: const ProjectId('drag-step-layers'),
    name: 'Drag step layers',
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

  /// Every boundary waiting to repaint that is not a tick layer's (or
  /// inside one) and not a canvas's.
  Set<RenderObject> strays(WidgetTester tester) {
    final allowed = tickLayersAndCanvas(tester);
    return {
      for (final view in tester.binding.renderViews)
        ...repaintStrays(view, allowed: allowed),
    };
  }

  /// The views a timeline drag is made in. ⛔The storyboard is not one: it
  /// follows drags of its own (a panel's comma, a cut's trim along the
  /// strip), which are that panel's question.
  final views = <String, List<String>>{
    'timeline': [],
    'timeline with its lanes open': ['legend-lanes-toggle'],
    'x-sheet': ['timeline-orientation-toggle-button'],
    'x-sheet with its lanes open': [
      'legend-lanes-toggle',
      'timeline-orientation-toggle-button',
    ],
    'folded timeline': ['floating-bottom-collapse'],
  };

  /// The drags of a timeline block — each begun on a block of row A (or
  /// the cut's end), stepped by [step] frames at a time, and dropped.
  final drags =
      <
        String,
        ({
          bool Function(EditorSessionManager session) begin,
          void Function(EditorSessionManager session, int step) update,
          void Function(EditorSessionManager session) cancel,
        })
      >{
        'comma drag': (
          begin: (session) => session.edgeDrag.beginExposureEdgeDrag(
            layerId: const LayerId('a'),
            blockStartIndex: 12,
            edge: TimelineBlockEdge.end,
          ),
          update: (session, step) =>
              session.edgeDrag.updateExposureEdgeDrag(step),
          cancel: (session) => session.edgeDrag.cancelExposureEdgeDrag(),
        ),
        // The LAST block, whose way right is clear: a landing that collides
        // clears the preview, and a step with no preview is no step.
        'block move': (
          begin: (session) => session.drawingBlockMove
              .beginDrawingBlockMoveDrag(
                layerId: const LayerId('a'),
                blockStartIndex: 42,
              ),
          update: (session, step) => session.drawingBlockMove
              .updateDrawingBlockMoveDrag(frameDelta: step),
          cancel: (session) =>
              session.drawingBlockMove.cancelDrawingBlockMoveDrag(),
        ),
        'cut end trim': (
          begin: (session) => session.edgeDrag.beginCutEdgeDrag(
            cutId: const CutId('cut-0'),
            edge: TimelineBlockEdge.end,
          ),
          update: (session, step) => session.edgeDrag.updateCutEdgeDrag(-step),
          cancel: (session) => session.edgeDrag.cancelCutEdgeDrag(),
        ),
      };

  for (final MapEntry(key: drag, value: verbs) in drags.entries) {
    for (final MapEntry(key: view, value: taps) in views.entries) {
      testWidgets('a $drag step in the $view repaints its tick layers and '
          'the canvas and nothing around them', (tester) async {
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
        expect(
          verbs.begin(session),
          isTrue,
          reason: 'premise: there is something to grab',
        );
        // The first steps build the preview's surfaces once; what a drag
        // repaints once is not a step's.
        for (var step = 1; step <= 2; step += 1) {
          verbs.update(session, step);
          await tester.pump();
        }

        Set<RenderObject>? atEveryStep;
        for (var step = 3; step <= 6; step += 1) {
          final before = session.dragPreview.value;
          verbs.update(session, step);
          expect(
            session.dragPreview.value,
            isNot(same(before)),
            reason: 'premise: the step published a preview',
          );
          // One step, run to its layout and stopped before the paint, so
          // what waits to repaint can be read.
          await tester.pump(null, EnginePhase.layout);
          final now = strays(tester);
          atEveryStep = atEveryStep?.intersection(now) ?? now;
          await tester.pump();
        }
        verbs.cancel(session);
        await tester.pump();
        expect(
          atEveryStep!.map(nameOf),
          isEmpty,
          reason: atEveryStep.map(nameOf).join('\n\n'),
        );
      });
    }
  }
}
