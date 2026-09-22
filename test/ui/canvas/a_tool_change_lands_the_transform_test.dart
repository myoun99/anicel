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
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨★★★**AN INTERRUPTION HAS EXACTLY TWO ANSWERS.**
///
/// 🗣️유저 2026-09-17: 「**프레임이동이나 레이어이동등은 착지시킬 이유가
/// 없는것들은 착지안하고 편집중 그대로 유지**. 근데 여기서 **다른 도구
/// 선택하는 등만 착지**시키는거고」, and again on 09-22 when it was still
/// broken: 「변형중 프레임 이동 등 **가능한동작이면 가능하게 냅두고,
/// 불가능한 동작이면 마지막 변형대로 커밋**하라고 내가 말하지않았냐? **두개로
/// 딱 나누라고**?」 — 「b나 e 누르면 **캔버스 사라지고 이상해지는데**」.
///
/// ⛔**AND IT IS THE WHOLE FAMILY, NOT THE TWO KEYS.** 유저, the same
/// minute: 「**b랑 e만막고 다른 경로 안막는 멍청한짓은 안하길바란다**」. So
/// the pins below walk the ROUTES — a key, the tool rail, a frame walk —
/// and each one has to come out in one of the two buckets.
void main() {
  const frameA = FrameId('tl-frame-a');
  const frameB = FrameId('tl-frame-b');
  const layerId = LayerId('tl-layer');
  const captureKey = ValueKey<String>('tl-capture');

  Project twoFrameProject() => Project(
    id: const ProjectId('tl-project'),
    name: 'Tool Land',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('tl-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('tl-cut'),
            name: 'Tool Land Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'Tool Land Layer',
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

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  int inkOn(WidgetTester tester, FrameId frameId, {int step = 8}) {
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final coordinator = workspace.session.pixelEditingCoordinator!;
    final surface = coordinator.currentSurfaceOf(
      BrushFrameKey(
        projectId: const ProjectId('tl-project'),
        trackId: const TrackId('tl-track'),
        cutId: const CutId('tl-cut'),
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

  /// How much ink is ON SCREEN inside the drawing canvas — the half the
  /// cel cannot answer, because a session never writes to the cel and the
  /// hole 유저 sees is a VIEW.
  Future<int> inkOnScreen(WidgetTester tester) async {
    final boundary =
        tester.renderObject(find.byKey(captureKey)) as RenderRepaintBoundary;
    final image = boundary.toImageSync();
    final rect = visibleCanvasRect(tester);
    var ink = 0;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final width = image.width;
      for (var y = rect.top.toInt() + 4; y < rect.bottom.toInt() - 4; y += 4) {
        for (var x = rect.left.toInt() + 4; x < rect.right.toInt() - 4; x += 4) {
          final o = (y * width + x) * 4;
          if (o + 3 >= bytes.length) continue;
          // The fixture draws in the brush's own colour on white paper, so
          // 「not paper」 is the reading — and a hole is paper.
          final dark = bytes[o] + bytes[o + 1] + bytes[o + 2] < 600;
          if (dark && bytes[o + 3] > 0) ink += 1;
        }
      }
    });
    image.dispose();
    return ink;
  }

  Future<void> strokeAt(WidgetTester tester, Offset offset) async {
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester, offset: offset),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.up();
    await pumpFrames(tester);
  }

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester);
  }

  /// Opens a box on the stroke and moves it, leaving the session pending.
  ///
  /// ⛔It ASSERTS that the box really changed. A drag that grabbed nothing
  /// leaves an identity transform, and 「an identity landed correctly」 is
  /// not the question — 유저's symptom is about a transform that was
  /// actually made.
  Future<void> openAndTransform(WidgetTester tester) async {
    await pressCtrl(tester, LogicalKeyboardKey.keyT);
    final drag = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await drag.moveBy(const Offset(30, 20));
    await tester.pump();
    await drag.up();
    await pumpFrames(tester);
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    expect(
      commands.transformActive,
      isTrue,
      reason: '⛔전제: the grab opened a box',
    );
    final v = commands.transformValues!;
    expect(
      v.scale != 1 || v.tx != 0 || v.rotationDegrees != 0,
      isTrue,
      reason: '⛔전제: and the drag really transformed it — $v',
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(home: HomePage(initialProject: twoFrameProject())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🚨a tool change LANDS the transform — the picture is still '
      'there, wherever the box left it', (tester) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    final drew = inkOn(tester, frameA);
    final showed = await inkOnScreen(tester);
    expect(drew, greaterThan(0), reason: '⛔CONTROL: the rig draws at all');
    expect(showed, greaterThan(0), reason: '⛔CONTROL: and the screen shows it');

    await openAndTransform(tester);

    // 유저: 「b나 e 누르면 캔버스 사라지고 이상해지는데」.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await pumpFrames(tester);

    expect(
      inkOn(tester, frameA),
      greaterThan(0),
      reason: '유저: 「불가능한 동작이면 마지막 변형대로 커밋」 — it landed',
    );
    expect(
      await inkOnScreen(tester),
      greaterThan(showed ~/ 2),
      reason:
          '🚨유저: 「캔버스 사라지고 이상해지는데」 — the picture has to be ON '
          'SCREEN after the switch, not a hole where it used to be',
    );
  });

  /// 🚨★★★**THE FLOAT GOES WITH THE LAYER THAT PUBLISHED IT.**
  ///
  /// `_publishFloat` runs from BUILD, and a switch to a painting tool does
  /// not rebuild the selection layer — it disposes it. The last float it
  /// published stayed in the composite forever, drawing over the picture
  /// that had just landed. ⛔This is the half a cel reading can never see,
  /// which is why it is asked of the overlay itself.
  testWidgets('🚨the float the layer published is taken back when it goes', (
    tester,
  ) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    await openAndTransform(tester);

    final overlay = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .floatOverlay!;
    expect(
      overlay.value,
      isNotNull,
      reason: '⛔전제: a session really is floating a picture',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await pumpFrames(tester);

    expect(
      overlay.value,
      isNull,
      reason:
          '🚨유저: 「캔버스 사라지고 이상해지는데」 — a float nobody owns keeps '
          'painting over the landing',
    );
  });

  testWidgets('🚨and the eraser is not a different law', (tester) async {
    // ⛔THE SECOND KEY, because 유저 named two and a fix that knows only
    // one is the fix they refused in advance.
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    final showed = await inkOnScreen(tester);
    await openAndTransform(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await pumpFrames(tester);

    expect(inkOn(tester, frameA), greaterThan(0));
    expect(await inkOnScreen(tester), greaterThan(showed ~/ 2));
  });

  testWidgets('⛔a FRAME walk is the other bucket: nothing lands and the '
      'box is still open', (tester) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    await openAndTransform(tester);
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );

    workspace.session.selectFrameIndex(1);
    await pumpFrames(tester);

    expect(
      inkOn(tester, frameB),
      0,
      reason:
          '유저: 「착지시킬 이유가 없는것들은 착지안하고 편집중 그대로 유지」',
    );
  });
}
