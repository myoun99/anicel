import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
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
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🗣️F-562 (유저 2026-11-04): 「변형도구 사용시, 꼭짓점 끄는 그런 캔버스쪽
/// 조작할때, 손가락커서가 될때가있고 아닐때가있음. 선택도구로 선택하고
/// 변형누르면 높은확률로 손가락커서되는듯? 로직 입구가 제대로 통일안되있는거
/// 같은데 손가락으로 안바뀌도록 제대로통일」.
///
/// What is measured is what the SYSTEM is told last — the one cursor it
/// shows, whichever device asked — not what one device was told.
void main() {
  const layerId = LayerId('pc-layer');
  const cutId = CutId('pc-cut');

  /// The rail's 확정 (↵): dead until the box holds a change, as every door
  /// of the one verb is ([CanvasSelectionCommands.canApplyTransform]).
  final confirm = find.byWidgetPredicate(
    (widget) => widget is RailButton && widget.keyValue == 'rail-confirm-button',
  );
  bool confirmIsLive(WidgetTester tester) =>
      tester.widget<RailButton>(confirm).onPressed != null;

  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Project project() => Project(
    id: const ProjectId('pc-project'),
    name: 'Pointer cursor',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('pc-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: cutId,
            name: cutId.value,
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: layerId.value,
                frames: [
                  Frame(
                    id: const FrameId('pc-frame'),
                    name: 'pc-frame',
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('pc-frame'), length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  CanvasSelectionCommands commandsOf(WidgetTester tester) =>
      workspaceOf(tester).canvasSelectionCommands!;

  /// ⛔Not `pumpAndSettle`: the marching ants of an open box never settle.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Every cursor the system is asked for, in order.
  List<String> systemAsked(WidgetTester tester) {
    final asked = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      (call) async {
        if (call.method == 'activateSystemCursor') {
          final arguments = call.arguments as Map<Object?, Object?>;
          asked.add(arguments['kind']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.mouseCursor,
        null,
      ),
    );
    return asked;
  }

  /// Ink on the cel, drawn by the pen.
  Future<void> ink(WidgetTester tester) async {
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester, offset: Offset.zero),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(120, 60));
    await tester.pump();
    await pen.moveBy(const Offset(120, 60));
    await tester.pump();
    await pen.up();
    await pen.removePointer();
    await pumpFrames(tester);
  }

  Future<void> useTool(WidgetTester tester, CanvasTool tool) async {
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(tool: tool);
    await pumpFrames(tester);
  }

  /// The whole canvas selected, the ink inside it.
  Future<void> selectAll(WidgetTester tester) async {
    await useTool(tester, CanvasTool.select);
    commandsOf(tester).setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: 0,
          top: 0,
          right: defaultCutCanvasSize.width.toDouble(),
          bottom: defaultCutCanvasSize.height.toDouble(),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// Every way into the box ([CanvasTool.move]) over the ink: the box is
  /// up when it returns.
  final entrances = <String, Future<void> Function(WidgetTester tester)>{
    'the transform tool, nothing selected': (tester) =>
        useTool(tester, CanvasTool.move),
    'a selection, then the transform tool': (tester) async {
      await selectAll(tester);
      await useTool(tester, CanvasTool.move);
    },
    'Ctrl+T over a selection': (tester) async {
      await selectAll(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpFrames(tester);
    },
  };

  for (final MapEntry(key: way, value: enter) in entrances.entries) {
    testWidgets('$way: a mouse resting on 확정 does not take the cursor from '
        'the pen dragging the box — 확정 going live under it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: project())),
      );
      await tester.pumpAndSettle();
      await ink(tester);
      await enter(tester);
      final asked = systemAsked(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(confirm));
      addTearDown(mouse.removePointer);
      await pumpFrames(tester);
      expect(
        confirmIsLive(tester),
        isFalse,
        reason: '⛔전제: 확정 has nothing to do yet, so it is dead under the mouse',
      );

      final on = visibleCanvasPoint(tester, offset: const Offset(60, 30));
      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.addPointer(location: on);
      await pumpFrames(tester);
      await pen.down(on);
      await pumpFrames(tester);
      for (var step = 0; step < 3; step += 1) {
        await pen.moveBy(const Offset(20, 0));
        await pumpFrames(tester);
      }
      await pen.up();
      await pumpFrames(tester);
      expect(
        confirmIsLive(tester),
        isTrue,
        reason: '⛔CONTROL: the drag gave the box a change, and 확정 went live '
            'under the mouse',
      );
      expect(asked.last, 'basic', reason: 'the pen hovers the box it moved');

      // The next drag on the box, where the report saw the hand.
      await pen.down(on + const Offset(60, 0));
      await pumpFrames(tester);
      for (var step = 0; step < 2; step += 1) {
        await pen.moveBy(const Offset(10, 0));
        await pumpFrames(tester);
        expect(
          asked.last,
          'basic',
          reason: 'the pen drags, so the pen\'s arrow',
        );
      }
      await pen.up();
      await pumpFrames(tester);
      await pen.removePointer();
      await pumpFrames(tester);
    });
  }

  testWidgets('the pen coming back takes the cursor back from the mouse that '
      'moved last', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await ink(tester);
    await useTool(tester, CanvasTool.move);
    commandsOf(tester).editTransformValues((now) => now.copyWith(tx: 10));
    await pumpFrames(tester);
    expect(confirmIsLive(tester), isTrue, reason: '⛔전제');
    final asked = systemAsked(tester);

    final on = visibleCanvasPoint(tester, offset: const Offset(60, 30));
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: on);
    addTearDown(pen.removePointer);
    await pumpFrames(tester);
    expect(asked.last, 'basic', reason: '⛔CONTROL: the pen over the box');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(confirm));
    addTearDown(mouse.removePointer);
    await pumpFrames(tester);
    expect(asked.last, 'click', reason: '⛔CONTROL: the mouse on 확정, live');

    await pen.moveBy(const Offset(4, 0));
    await pumpFrames(tester);
    expect(asked.last, 'basic', reason: 'the pen moved last');
  });
}
