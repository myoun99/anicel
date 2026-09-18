import 'dart:ui' show ImageByteFormat;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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

/// 🚨★★★**F-164 ⑤ — 유저 2026-09-18: 「새로 선을 그어도 긋고나서 커밋하면
/// 사라짐」**, the last symptom of the report whose first four this round
/// closed.
///
/// ⛔**IT NEEDS A RIG THAT DRAWS.** The panel-level file pins the session
/// itself, and its own note says why it stops one step short: a stroke
/// committed straight through the coordinator moves the drawn ink by ZERO
/// on a cel that panel has already painted, so an assertion there measures
/// nothing (measured, with a control, 2026-09-18). The symptom is about a
/// stroke the USER draws, so this one drives the real workspace — the pen,
/// the keys and the seeks.
///
/// 🧪**WHAT IT TOOK TO MAKE THIS PIN REAL**, in the order it was measured:
/// ①asking the CEL what it holds catches nothing, because a session never
/// writes to the cel; ②asking the SCREEN catches it, but only inside the
/// canvas, because this app's chrome is dark too; ③and the defect needs
/// BOTH halves switched off to reappear — a silent let-go alone no longer
/// reproduces it, since arriving on the next cel now opens a session that
/// replaces the stale one (F-164 ③). With both off, the assertion that
/// fails is ⑤'s own: the new stroke does not show.
void main() {
  const frameA = FrameId('rt-frame-a');
  const frameB = FrameId('rt-frame-b');
  const layerId = LayerId('rt-layer');
  const captureKey = ValueKey<String>('rt-capture');

  Project twoFrameProject() => Project(
    id: const ProjectId('rt-project'),
    name: 'Round Trip',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('rt-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('rt-cut'),
            name: 'Round Trip Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'Round Trip Layer',
                frames: [
                  Frame(id: frameA, name: 'A', duration: 1, strokes: const []),
                  Frame(id: frameB, name: 'B', duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(frameA, length: 1),
                  1: const TimelineExposure.drawing(frameB, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  BrushFrameKey keyFor(FrameId frameId) => BrushFrameKey(
    projectId: const ProjectId('rt-project'),
    trackId: const TrackId('rt-track'),
    cutId: const CutId('rt-cut'),
    layerId: layerId,
    frameId: frameId,
  );

  /// How much ink a cel HOLDS, sampled on a grid over the whole canvas.
  int inkOn(WidgetTester tester, FrameId frameId, {int step = 8}) {
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final coordinator = workspace.session.pixelEditingCoordinator;
    expect(coordinator, isNotNull, reason: '⛔fixture: the canvas built one');
    final surface = coordinator!.currentSurfaceOf(keyFor(frameId));
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

  /// How much ink is ON SCREEN inside the drawing canvas.
  ///
  /// 🚨★★★**THIS IS THE AXIS, AND [inkOn] IS NOT.** 🧪Measured 2026-09-18:
  /// with the layer letting go of a session silently — the original defect
  /// — every cel assertion in this file stays green, because a session
  /// never writes to the cel. The hole 유저 sees is a VIEW the panel
  /// derives and draws, so 「그림이 사라짐」 is a fact about the screen and
  /// only the screen can report it.
  ///
  /// ⚠️Scoped to [visibleCanvasRect]: this app's chrome is dark, so an ink
  /// count over the whole window is a count of the panels. Inside the
  /// canvas, dark means drawing — the marching ants are red or green.
  Future<int> inkOnScreen(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final rect = visibleCanvasRect(tester);
    final image = boundary.toImageSync();
    final width = image.width;
    late int ink;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      var dark = 0;
      for (var y = rect.top.toInt(); y < rect.bottom; y += 1) {
        for (var x = rect.left.toInt(); x < rect.right; x += 1) {
          final i = (y * width + x) * 4;
          if (i + 2 >= bytes.length) continue;
          if (bytes[i] < 80 && bytes[i + 1] < 80 && bytes[i + 2] < 80) {
            dark += 1;
          }
        }
      }
      ink = dark;
    });
    image.dispose();
    return ink;
  }

  /// ⛔**`pumpAndSettle` CANNOT BE USED ONCE A BOX CAN BE OPEN.** The
  /// marching ants animate for as long as there is a selection, so the tree
  /// never goes quiet and the wait dies on its own timeout — which reads
  /// exactly like a hang in the code under test, and 🧪did: the first run
  /// of the mutant below failed on the timeout instead of on the assertion
  /// that names 유저's symptom. A fixed few frames is enough here, because
  /// nothing in this script waits on a clock — only on state reaching the
  /// next build.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> strokeAt(WidgetTester tester, Offset offset) async {
    final gesture = await tester.startGesture(
      visibleCanvasPoint(tester, offset: offset),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.up();
    await pumpFrames(tester);
  }

  Future<void> seekTo(WidgetTester tester, int index) async {
    tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .selectFrameIndex(index);
    await pumpFrames(tester);
  }

  testWidgets('a new stroke on the cel a transform round-tripped through '
      'survives its own commit', (tester) async {
    await tester.pumpWidget(
      // ⚠️The boundary is the TEST's, not the app's: nothing in the
      // workspace is a repaint boundary at the root, and the pixels are
      // what this file is about.
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(home: HomePage(initialProject: twoFrameProject())),
      ),
    );
    await tester.pumpAndSettle();

    // 유저: 「프레임1,2에 그림을 그려두고」.
    await strokeAt(tester, Offset.zero);
    final drewOnA = inkOn(tester, frameA);
    final showedA = await inkOnScreen(tester);
    await seekTo(tester, 1);
    await strokeAt(tester, const Offset(40, 0));
    final drewOnB = inkOn(tester, frameB);

    // ⛔**THE CONTROL COMES FIRST.** An instrument that cannot move
    // satisfies 「the ink is still there」 by being blind, so this rig says
    // out loud that it can see a stroke arrive before it is allowed to say
    // one survived.
    expect(drewOnA, greaterThan(0), reason: '⛔CONTROL: the rig draws at all');
    expect(drewOnB, greaterThan(0), reason: '⛔CONTROL: and on the next cel');
    expect(
      showedA,
      greaterThan(0),
      reason: '⛔CONTROL: and the SCREEN shows what was drawn',
    );

    // 유저: 「프레임1에서 변형으로 확대한 다음 확정하지 않고」.
    await seekTo(tester, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester);
    // ⚠️A REAL transform, not an identity box: Enter on an identity affine
    // 「closes the box with the session still pending」, which is a
    // different path from the confirm 유저 describes.
    final drag = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await drag.moveBy(const Offset(30, 20));
    await tester.pump();
    await drag.up();
    await pumpFrames(tester);
    expect(
      inkOn(tester, frameA),
      drewOnA,
      reason: 'a session writes NOTHING until it is confirmed (F-116)',
    );

    // 유저: 「프레임2가면」 … 「그 상태에서 엔터버튼으로 확정시키고」.
    await seekTo(tester, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);

    // 유저: 「프레임1가면 프레임1의 그림이 사라짐」 — it must not.
    await seekTo(tester, 0);
    expect(
      inkOn(tester, frameA),
      drewOnA,
      reason: '프레임1은 확정된 적이 없으니 셀은 그대로다',
    );
    final backOnA = await inkOnScreen(tester);
    expect(
      backOnA,
      greaterThan(showedA ~/ 2),
      reason:
          '④유저: 「엔터버튼으로 확정시키고 프레임1가면 프레임1의 그림이 '
          '사라짐」 — a cel still drawn through a session the host never '
          'closed shows its HOLE, and the hole here is the whole picture',
    );

    // 유저: 「새로 선을 그어도 긋고나서 커밋하면 사라짐」 — and drawing means
    // the BRUSH: Ctrl+T left the move tool in hand.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await pumpFrames(tester);
    await strokeAt(tester, const Offset(-70, -50));

    expect(
      inkOn(tester, frameA),
      greaterThan(drewOnA),
      reason: '⛔CONTROL: the new stroke reached the cel at all',
    );
    expect(
      await inkOnScreen(tester),
      greaterThan(backOnA),
      reason:
          '⑤유저: 「새로 선을 그어도 긋고나서 커밋하면 사라짐」 — a cel drawn '
          'through a stale hole swallows whatever is drawn on it next, so '
          'the new stroke has to show ON SCREEN and the old ink has to '
          'still be under it',
    );
  });
}
