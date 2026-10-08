import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
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
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import '../storyboard_conte_row_probe.dart';

/// 🧪I-73 (2026-10-08, measured before the row was built): a cut an O.L
/// arrives into keeps its conte AFTER the のりしろ it owes (F-227) — its
/// conte layer's first panel is keyed that many frames in. The panels'
/// gesture counted from the cut's start and handed that on as the layer's
/// frame, so a sweep over the cut's first panel selected the のりしろ before
/// it, and one over its second panel the first.
///
/// The conte row reads a frame of the track as the frame of the layer it
/// stands on ([conteRowOwnFrameAt]) — for its blocks, its gesture and its
/// band alike.
void main() {
  const trackId = 'ol-track';

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('cel-$id'), name: 'A', frames: const []),
      Layer(
        id: LayerId('sb-$id'),
        name: 'Conte',
        kind: LayerKind.storyboard,
        frames: [
          for (final panel in ['p1', 'p2'])
            Frame(id: FrameId('$panel-$id'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('p1-$id'), length: 12),
          12: TimelineExposure.drawing(FrameId('p2-$id'), length: 12),
        },
      ),
    ],
  );

  /// Cuts a [0, 24) and b [24, 48), two panels of twelve each, joined by an
  /// O.L over [18, 30): six frames of it are b's のりしろ.
  Future<EditorSessionManager> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: Project(
            id: const ProjectId('ol-project'),
            name: 'O.L',
            createdAt: DateTime.utc(2026, 10, 8),
            tracks: [
              Track(
                id: const TrackId(trackId),
                name: 'Video',
                cuts: [cut('a'), cut('b')],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    await tester.pumpAndSettle();
    return session;
  }

  StoryboardPanel panel(WidgetTester tester) =>
      tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));

  Offset contePoint(WidgetTester tester, int globalFrame) {
    final rect = conteRowRect(tester, trackId);
    return Offset(
      rect.left + (globalFrame + 0.5) * panel(tester).pixelsPerFrame,
      rect.center.dy,
    );
  }

  Future<void> sweep(WidgetTester tester, int from, int to) async {
    final gesture = await tester.startGesture(
      contePoint(tester, from),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(contePoint(tester, to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Layer conteOf(EditorSessionManager session, String cutId) => session
      .repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == CutId(cutId))
      .layers
      .firstWhere((layer) => layer.kind == LayerKind.storyboard);

  testWidgets('⛔전제: the arriving cut\'s conte begins six frames into its '
      'row', (tester) async {
    final session = await open(tester);

    expect(storyboardConteStart(conteOf(session, 'a').timeline), 0);
    expect(storyboardConteStart(conteOf(session, 'b').timeline), 6);
  });

  testWidgets('the row draws the arriving cut\'s panels from the cut\'s '
      'own start', (tester) async {
    await open(tester);

    expect(conteRowBlocks(tester, trackId), {0: 12, 12: 12, 24: 12, 36: 12});
  });

  testWidgets('🚨a sweep over the arriving cut\'s first panel selects THAT '
      'panel — in the row\'s own frames, past the のりしろ', (tester) async {
    await open(tester);

    await sweep(tester, 26, 28);

    final selection = panel(tester).stripSelect!.selection.value!;
    expect(selection.layerId, const LayerId('sb-b'));
    expect(
      (selection.startIndex, selection.endIndexExclusive),
      (6, 18),
      reason: '↩️[0, 6): the のりしろ before the panel under the pointer',
    );
  });

  testWidgets('🚨…and one over its second panel, the second', (tester) async {
    await open(tester);

    await sweep(tester, 38, 39);

    final selection = panel(tester).stripSelect!.selection.value!;
    expect((selection.startIndex, selection.endIndexExclusive), (18, 30));
  });

  testWidgets('the band stands over the panel that was swept', (tester) async {
    await open(tester);
    final row = conteRowRect(tester, trackId);
    final ppf = panel(tester).pixelsPerFrame;
    Rect band() => tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-strip-range-selection')),
    );

    // The first panel, [6, 18) of the row: BOTH its ends lie inside the
    // cut, so neither is the cut's edge standing in for it.
    await sweep(tester, 26, 28);
    expect(band().left, moreOrLessEquals(row.left + 24 * ppf));
    expect(
      band().width,
      moreOrLessEquals(12 * ppf),
      reason: 'it ends where the second panel begins, not a のりしろ later',
    );

    await sweep(tester, 38, 39);
    expect(band().left, moreOrLessEquals(row.left + 36 * ppf));
    expect(band().width, moreOrLessEquals(12 * ppf));
  });

  testWidgets('a press inside the selection is inside it: a drag from the '
      'selected panel slides the panels', (tester) async {
    final session = await open(tester);
    await sweep(tester, 26, 28);

    // From the first panel past the middle of the second.
    await sweep(tester, 27, 44);

    final row = conteOf(session, 'b');
    expect(
      [
        for (final entry in row.timeline.entries)
          if (!entry.value.ghost) (entry.key, entry.value.frameId!.value),
      ],
      [(6, 'p2-b'), (18, 'p1-b')],
      reason: 'the two panels traded places, as on any cut',
    );
  });
}
