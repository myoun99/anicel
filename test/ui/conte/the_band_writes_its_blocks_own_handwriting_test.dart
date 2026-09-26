import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/device_viewport.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/conte/conte_ink_windows.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// 🚨THE BAND OF A CELL IS ITS BLOCK'S OWN HANDWRITING.
///
/// 유저 2026-09-25 (conte-drawing-target): what a stroke leaves outside the
/// picture is the block's handwriting, and blocks of the same name are not
/// linked. Two blocks exposing ONE cel are the case that used to share: the
/// band was keyed by the cel. The first stroke on a block's band puts the
/// block's id on it, in the stroke's own undo step.
void main() {
  const cutId = CutId('1');

  /// One cel exposed twice: two blocks of the same drawing, two cells.
  Project project() => Project(
    id: const ProjectId('conte-project'),
    name: 'Conte',
    createdAt: DateTime.utc(2026, 9, 26),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: cutId,
            name: '1',
            duration: 6,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('sb'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: [
                  Frame(
                    id: const FrameId('f'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('f'), length: 3),
                  3: TimelineExposure.drawing(FrameId('f'), length: 3),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  late EditorSessionManager session;
  late ConteInkController ink;

  ContePageLayout page() => layoutConteSheet(
    buildConteSheetSource(session.repository.requireProject()),
    metrics: ConteSheetMetrics(cameraAspect: session.camera.cameraFrameAspect),
  ).first;

  /// The panel, its brush on; returns where the page's origin is on the
  /// screen.
  Future<Offset> pumpPanel(WidgetTester tester) async {
    session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    ink = ConteInkController();
    addTearDown(ink.dispose);
    final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brush.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The panel goes first (tear-downs run last-added first).
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, ink]),
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewport: seedFromRender(tester, CanvasViewport()),
              inkController: ink,
              brushToolState: brush,
              brushAllowed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getTopLeft(
      find.byKey(const ValueKey<String>('conte-form-paint')),
    );
  }

  /// A spot of [cell]'s band in its TIME column — the band's, and no
  /// picture's or words'.
  Offset timeColumnOf(ContePlacedCell cell) {
    final metrics = page().metrics;
    return Offset(
      metrics.timeLeft + 8,
      cell.rowBandRect(metrics).center.dy,
    );
  }

  ExposureMemo? memoAt(int start) => storyboardLayerForCut(
    session.cutById(cutId)!,
  )!.timeline[start]!.memo;

  /// Whether the band of the block opening at [start] shows handwriting —
  /// under its own id, or the name the pen would write it under.
  bool bandInked(int start) => ink.hasInkFor(
    ConteInkPlane.row,
    conteInkRowKey(
      cutId,
      switch (memoAt(start)?.inkId) {
        final inkId? when inkId.isNotEmpty => inkId,
        _ => session.storyboardCursor.conteInkIdFor(cutId, start),
      },
    ),
  );

  testWidgets('a stroke on one block\'s band is that block\'s alone — its '
      'twin of the same cel shows none; the stroke puts the block\'s id on '
      'it, and ONE undo takes both', (tester) async {
    final origin = await pumpPanel(tester);
    final first = page().cells.firstWhere(
      (cell) => cell.source.startFrame == 0,
    );
    final at = origin + timeColumnOf(first);

    final gesture = await tester.startGesture(at, pointer: 7);
    await tester.pump();
    await gesture.moveTo(at + const Offset(12, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final inkId = memoAt(0)?.inkId ?? '';
    expect(inkId, isNotEmpty, reason: 'the block took its id');
    expect(bandInked(0), isTrue);
    expect(memoAt(3), isNull, reason: 'the twin was not written on');
    expect(bandInked(3), isFalse, reason: 'one cel, two handwritings');
    expect(
      conteInkMarks(page(), page().metrics).map((mark) => mark.key),
      contains(conteInkRowKey(cutId, inkId)),
      reason: 'the page prints what was written',
    );

    session.historyManager.undo();
    await tester.pumpAndSettle();
    expect(memoAt(0)?.inkId ?? '', isEmpty);
    expect(
      ink.hasInkFor(ConteInkPlane.row, conteInkRowKey(cutId, inkId)),
      isFalse,
    );

    session.historyManager.redo();
    await tester.pumpAndSettle();
    expect(memoAt(0)?.inkId, inkId);
    expect(bandInked(0), isTrue);
  });

  testWidgets('a block already written on takes a second stroke under the '
      'same id — no step of its own', (tester) async {
    final origin = await pumpPanel(tester);
    final first = page().cells.firstWhere(
      (cell) => cell.source.startFrame == 0,
    );
    Future<void> strokeAt(Offset at) async {
      final gesture = await tester.startGesture(at, pointer: 7);
      await tester.pump();
      await gesture.moveTo(at + const Offset(12, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await strokeAt(origin + timeColumnOf(first));
    final inkId = memoAt(0)!.inkId;
    final steps = session.historyManager.undoCount;
    await strokeAt(origin + timeColumnOf(first) + const Offset(0, 6));

    expect(memoAt(0)!.inkId, inkId);
    expect(
      session.historyManager.undoCount,
      steps + 1,
      reason: 'the stroke, and nothing written beside it',
    );
  });
}
