import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_frame_key.dart';
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
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨★★★**A VERB IN FLIGHT OWNS THE KEYBOARD TOO.**
///
/// 🗣️유저 2026-09-21 (F-173): 「**선 그리는 도중 언두가 작동함.** 선 말고도
/// **도구를 사용중이면 언두/리두 작동불가**하도록」.
///
/// ⛔It is not a fourth channel beside the polygon, the transform box and
/// the document. Those three answer 「is this key about the thing I am in
/// the middle of?」 and fall through when it is not; this says the key is
/// not a key at all while a contact is down — a different sentence, so it
/// comes first.
void main() {
  const frameId = FrameId('vf-frame');
  const layerId = LayerId('vf-layer');

  Project oneFrameProject() => Project(
    id: const ProjectId('vf-project'),
    name: 'Verb In Flight',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('vf-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('vf-cut'),
            name: 'Verb Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'Verb Layer',
                frames: [
                  Frame(id: frameId, name: 'A', duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(frameId, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  int inkOn(WidgetTester tester, {int step = 8}) {
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final surface = workspace.session.pixelEditingCoordinator!.currentSurfaceOf(
      const BrushFrameKey(
        projectId: ProjectId('vf-project'),
        trackId: TrackId('vf-track'),
        cutId: CutId('vf-cut'),
        layerId: layerId,
        frameId: frameId,
      ),
    );
    final size = surface.canvasSize;
    var ink = 0;
    for (var y = 0; y < size.height; y += step) {
      for (var x = 0; x < size.width; x += step) {
        if ((surfacePixelRgba(surface, x, y) ?? 0) != 0) {
          ink += 1;
        }
      }
    }
    return ink;
  }

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: oneFrameProject())),
    );
    await tester.pumpAndSettle();
  }

  Future<TestGesture> strokeStart(WidgetTester tester) async {
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    return pen;
  }

  testWidgets('🚨Ctrl+Z does nothing while the pen is still down', (
    tester,
  ) async {
    await pumpApp(tester);

    // One finished stroke, so the document HAS something to undo — the
    // pin would pass on an empty history for the wrong reason.
    final first = await strokeStart(tester);
    await first.up();
    await pumpFrames(tester);
    final drawn = inkOn(tester);
    expect(drawn, greaterThan(0), reason: '⛔CONTROL: the rig draws');

    // A second stroke, still in the hand.
    final pen = await strokeStart(tester);
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);

    expect(
      inkOn(tester),
      greaterThanOrEqualTo(drawn),
      reason:
          '🚨유저: 「선 그리는 도중 언두가 작동함 … 도구를 사용중이면 '
          '언두/리두 작동불가하도록」 — the first stroke must still be there',
    );

    await pen.up();
    await pumpFrames(tester);
  });

  testWidgets('⛔and once the pen is up the SAME key undoes', (tester) async {
    // 🚨THE CONTROL: without it, 「undo does nothing mid-stroke」 also
    // passes on a build where undo does nothing at all.
    await pumpApp(tester);
    final pen = await strokeStart(tester);
    await pen.up();
    await pumpFrames(tester);
    expect(inkOn(tester), greaterThan(0), reason: '⛔전제: the rig draws');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(inkOn(tester), 0, reason: '손을 떼면 언두는 언두다');
  });
}
