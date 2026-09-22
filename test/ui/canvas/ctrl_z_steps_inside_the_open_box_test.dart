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
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨★★★**⑤CTRL+Z INSIDE AN OPEN BOX IS THE BOX'S, NOT THE DOCUMENT'S.**
///
/// 🗣️유저 2026-09-20: 「**변형도구 사용시 변형에 대한 조작마다 언두로 기록**
/// 된단거야 … **확정하면 변형 하나로서의 언두만 작동**」.
///
/// ⛔**IT NEEDS A RIG THAT DRAWS, and that is the whole reason this file
/// exists.** The channel's own pins call `undoTransformStep()` themselves,
/// so a build where the SHORTCUT never asked it passes every one of them —
/// 🧪measured 2026-09-22, a mutant that wrote `if (false && …)` into
/// `home_page.dart` survived the entire suite. A source contract catches
/// that too, but only the key can say the key works.
///
/// 🧪**WHAT IT TOOK TO MAKE THE RIG RUN**, all three measured the hard way:
/// ①a fresh `HomePage()` has no cel under the playhead, so a transform has
/// no pixels to lift and the box never opens (`canEdit=false`); ②the pen
/// has to aim at [visibleCanvasPoint], not at the widget's centre — the
/// window is mostly chrome; ③⛔`pumpAndSettle` cannot be used once a box
/// can be open, because the marching ants animate forever and the wait dies
/// on its own timeout, which reads exactly like a hang in the code under
/// test.
void main() {
  const frameId = FrameId('cz-frame');
  const layerId = LayerId('cz-layer');

  Project oneFrameProject() => Project(
    id: const ProjectId('cz-project'),
    name: 'Ctrl Z',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('cz-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('cz-cut'),
            name: 'Ctrl Z Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'Ctrl Z Layer',
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

  /// ⛔See ③ above. A fixed few frames is enough because nothing in this
  /// script waits on a clock — only on state reaching the next build.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// How much ink the cel HOLDS, on a coarse grid.
  int inkOn(WidgetTester tester, {int step = 8}) {
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final coordinator = workspace.session.pixelEditingCoordinator;
    expect(coordinator, isNotNull, reason: '⛔fixture: the canvas built one');
    final surface = coordinator!.currentSurfaceOf(
      const BrushFrameKey(
        projectId: ProjectId('cz-project'),
        trackId: TrackId('cz-track'),
        cutId: CutId('cz-cut'),
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

  /// The app-level selection channel.
  ///
  /// ⚠️`.first` is safe HERE and would not be for a per-tool property: the
  /// tool library keeps several layers alive at once, but every one of them
  /// is handed the SAME channel object by the shell.
  CanvasSelectionCommands commandsOf(WidgetTester tester) => tester
      .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
      .selectionCommands!;

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester);
  }

  testWidgets('Ctrl+Z takes the last transform operation back, and the box '
      'stays open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: oneFrameProject())),
    );
    await tester.pumpAndSettle();

    // Ink first: a transform lifts PIXELS.
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.up();
    await pumpFrames(tester);

    // ⚠️Ctrl+T picks the TOOL. The box opens on the GRAB (R17-U 핸들 상시),
    // so the drag below is both the opening and operation number one.
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final commands = commandsOf(tester);
    expect(
      commands.transformActive,
      isFalse,
      reason: '⛔전제: the key alone opens nothing',
    );

    final grab = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await grab.moveBy(const Offset(30, 20));
    await tester.pump();
    await grab.up();
    await pumpFrames(tester);

    expect(commands.transformActive, isTrue, reason: '⛔전제: the grab opened it');
    final moved = commands.transformValues!;
    // ⚠️WHICHEVER grip the press found. The box frames a stroke about 50
    // screen px across, and nine 16px targets do not fit on that — so this
    // asks 「it is no longer as it opened」 rather than naming one channel.
    expect(
      moved.scale != 1 || moved.tx != 0 || moved.rotationDegrees != 0,
      isTrue,
      reason: '⛔전제: the drag really changed the box — $moved',
    );

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);

    final back = commands.transformValues;
    expect(
      back?.scale == 1 && back?.tx == 0 && back?.rotationDegrees == 0,
      isTrue,
      reason: 'the KEY took the step — 유저: 「조작마다 언두 기록」 ($back)',
    );
    expect(
      commands.transformActive,
      isTrue,
      reason:
          '⛔and the box is still open: undo did not land the session and '
          'reach past it into the document',
    );
    expect(
      commands.undoTransformStep(),
      isFalse,
      reason: '⛔한 걸음뿐이었으니 이제 비었다 — 그 다음 Ctrl+Z 는 문서의 것',
    );

    // ⛔CLOSE THE SESSION BEFORE THE TEST ENDS. A box left open outlives
    // the widget tree: the teardown disposes the HistoryManager and the
    // lift's deferred confirm then lands on it — 「A HistoryManager was
    // used after being disposed」, which is a failure of this script and
    // not of the app.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
  });

  testWidgets('⛔with no box open the SAME key still undoes the document', (
    tester,
  ) async {
    // 🚨THE CONTROL, and it has to be the document's own outcome. Without
    // it, 「Ctrl+Z is the box's」 would also pass on a build where the
    // transform channel ATE undo whether or not anything was open — the
    // failure the polygon trace already refused by answering false once its
    // own stack runs out. Asking the channel for false would be asking the
    // accused; this asks the cel.
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: oneFrameProject())),
    );
    await tester.pumpAndSettle();

    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.up();
    await pumpFrames(tester);
    final drawn = inkOn(tester);
    expect(drawn, greaterThan(0), reason: '⛔전제: the rig draws at all');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    expect(inkOn(tester), 0, reason: 'the stroke went back — undo still undoes');
  });
}
