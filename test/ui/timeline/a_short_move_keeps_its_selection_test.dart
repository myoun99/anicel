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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart';

import 'timeline_cell_probe.dart';

/// 🚨A SELECTION MOVED ONE FRAME IS STILL SELECTED, AT EVERY ZOOM.
///
/// Measured 2026-10-07 in the app's own tree: at 24px a cell a block moved
/// one frame kept its selection, and at 8px a cell the release that had
/// moved it dropped it. F-238 (유저 2026-09-29: 「1콤마만 바로바로 움직이는게
/// 불가능함」) let a drag take its first step as soon as it changes
/// something — on a cell narrower than the slop a release may travel and
/// still be a tap ([InstantTapRegion.travelSlop]), that is INSIDE it, so the
/// cells read the release as a tap, and a tap clears every selection (T10).
///
/// 「Did it travel」 no longer tells a tap from a drag; 「did the drag change
/// anything」 does (`pointerDragTookAStep`).
void main() {
  /// One row, one block ten frames long from frame 4 — long enough that a
  /// drag from its middle starts on no edge grip.
  Project project() => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 10, 7),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c1'),
            name: '1',
            duration: 48,
            canvasSize: const CanvasSize(width: 64, height: 36),
            layers: [
              Layer(
                id: const LayerId('a'),
                name: 'A',
                frames: [
                  Frame(
                    id: const FrameId('f1'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  4: const TimelineExposure.drawing(FrameId('f1'), length: 10),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// The app at [cell] pixels a frame, the block selected by a drag from the
  /// empty cell before it.
  Future<EditorSessionManager> selected(
    WidgetTester tester, {
    required double cell,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    tester
        .widget<FieldSlider>(
          find.byKey(const ValueKey<String>('timeline-zoom-slider')),
        )
        .onChanged!(cell);
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    final gesture = await tester.startGesture(
      timelineCellCenter(tester, 'a', 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(timelineCellCenter(tester, 'a', 8));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final selection = session.frameRangeSelection.value;
    expect(
      (selection?.startIndex, selection?.endIndexExclusive),
      (1, 14),
      reason: '⛔전제: the sweep took the block whole',
    );
    return session;
  }

  List<int> blockStarts(EditorSessionManager session) => [
    ...session.layers
        .firstWhere((layer) => layer.id.value == 'a')
        .timeline
        .keys,
  ];

  for (final cell in [24.0, 8.0]) {
    testWidgets('🚨at ${cell.toInt()}px a cell, a block moved ONE frame '
        'takes its selection with it', (tester) async {
      final session = await selected(tester, cell: cell);
      // One cell and a pixel: at 8px a cell that is nine, inside the twelve
      // a release may travel and still be a tap.
      final travel = cell + 1;
      if (cell == 8) {
        expect(travel, lessThan(InstantTapRegion.travelSlop), reason: '⛔전제');
      }

      final from = timelineCellCenter(tester, 'a', 9);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(from + Offset(travel, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(blockStarts(session), [5], reason: 'the block moved one frame');
      final selection = session.frameRangeSelection.value;
      expect(
        (selection?.startIndex, selection?.endIndexExclusive),
        (2, 15),
        reason: 'and it is still selected, one frame on',
      );
    });
  }
}
