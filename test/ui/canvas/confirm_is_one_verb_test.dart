import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
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
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨★★★**확정 — ONE verb, three doors** (confirm-button, 유저 2026-09-24):
/// 「입구 확실하게 안전하게 해서 **일반상태=마지막 스트로크 재입력,
/// 변형도구=변형중이지 않으면 마지막 변형 재실행, 변형중이면 확정**」, and
/// how the stroke comes back: 「**그린걸 픽셀 보관해서 덮는게** 가장 쉽고
/// 깔끔하고 가벼운 근본적인 방법」 — at the same place, on the cel you stand
/// on, one step and one undo.
///
/// ⛔It needs a rig that DRAWS: the stroke has to come through the canvas's
/// own funnel for it to be the last drawing action at all, so the pen, the
/// keys and the rail button are the real ones.
void main() {
  const frameA = FrameId('cv-frame-a');
  const frameB = FrameId('cv-frame-b');
  const frameC = FrameId('cv-frame-c');
  const layerId = LayerId('cv-layer');
  const otherLayerId = LayerId('cv-other-layer');
  const cutId = CutId('cv-cut');
  const otherCutId = CutId('cv-other-cut');

  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Cut cut(CutId id, LayerId layer, List<FrameId> frames) => Cut(
    id: id,
    name: id.value,
    duration: defaultCutDuration,
    canvasSize: defaultCutCanvasSize,
    layers: [
      Layer(
        id: layer,
        name: layer.value,
        frames: [
          for (final frame in frames)
            Frame(id: frame, name: frame.value, duration: 1, strokes: const []),
        ],
        timeline: {
          for (var i = 0; i < frames.length; i += 1)
            i: TimelineExposure.drawing(frames[i], length: 1),
        },
      ),
    ],
  );

  // Two cels side by side and an EMPTY cell after them; a second cut to
  // walk to.
  Project project() => Project(
    id: const ProjectId('cv-project'),
    name: 'Confirm',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('cv-track'),
        name: 'Video Track',
        cuts: [
          cut(cutId, layerId, const [frameA, frameB]),
          cut(otherCutId, otherLayerId, const [frameC]),
        ],
      ),
    ],
  );

  BrushFrameKey keyFor(FrameId frameId, {CutId cut = cutId}) =>
      BrushFrameKey(
        projectId: const ProjectId('cv-project'),
        trackId: const TrackId('cv-track'),
        cutId: cut,
        layerId: cut == cutId ? layerId : otherLayerId,
        frameId: frameId,
      );

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  EditorSessionManager sessionOf(WidgetTester tester) =>
      workspaceOf(tester).session;

  /// A cel's pixels on a grid over the whole canvas — 「the same place」
  /// is two of these being equal.
  List<int> pixelsOf(
    WidgetTester tester,
    FrameId frameId, {
    CutId cut = cutId,
    int step = 4,
  }) {
    final coordinator = sessionOf(tester).pixelEditingCoordinator!;
    final surface = coordinator.currentSurfaceOf(keyFor(frameId, cut: cut));
    final size = surface.canvasSize;
    return [
      for (var y = 0; y < size.height; y += step)
        for (var x = 0; x < size.width; x += step)
          surfacePixelRgba(surface, x, y) ?? 0,
    ];
  }

  int inkIn(List<int> pixels) => pixels.where((pixel) => pixel != 0).length;

  /// ⛔Not `pumpAndSettle`: the marching ants of an open box never settle.
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
    sessionOf(tester).selectFrameIndex(index);
    await pumpFrames(tester);
  }

  Future<void> useTool(WidgetTester tester, CanvasTool tool) async {
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(tool: tool);
    await pumpFrames(tester);
  }

  Future<void> pressEnter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);
  }

  final railConfirm = find.byWidgetPredicate(
    (widget) => widget is RailButton && widget.keyValue == 'rail-confirm-button',
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Enter lays the last stroke down again on the cel you stand '
      'on — the same pixels at the same place, and ONE undo takes it back', (
    tester,
  ) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    final drawn = pixelsOf(tester, frameA);
    expect(inkIn(drawn), greaterThan(0), reason: '⛔CONTROL: the rig draws');
    expect(inkIn(pixelsOf(tester, frameB)), 0, reason: '⛔전제: B는 비어 있다');

    await seekTo(tester, 1);
    final entriesBefore = sessionOf(tester).historyManager.undoCount;
    await pressEnter(tester);

    expect(pixelsOf(tester, frameB), drawn, reason: '그린 픽셀 그대로, 같은 자리');
    expect(sessionOf(tester).historyManager.undoCount, entriesBefore + 1);
    expect(pixelsOf(tester, frameA), drawn, reason: '⛔A는 그대로');

    sessionOf(tester).undo();
    await pumpFrames(tester);
    expect(inkIn(pixelsOf(tester, frameB)), 0, reason: '되돌리기 한 번에 사라진다');
  });

  testWidgets('an ERASE comes back as an erase — the blend travels with '
      'the pixels', (tester) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    await seekTo(tester, 1);
    await strokeAt(tester, Offset.zero);
    expect(
      pixelsOf(tester, frameB),
      pixelsOf(tester, frameA),
      reason: '⛔전제: 두 셀에 같은 선',
    );

    await seekTo(tester, 0);
    // The eraser's own key: it arms the eraser WITH its settings, the erase
    // blend among them (a bare tool swap would keep the brush's).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await pumpFrames(tester);
    await strokeAt(tester, Offset.zero);
    final erased = pixelsOf(tester, frameA);
    // ⚠️A count of inked pixels cannot see this: an erase that thins a pixel
    // leaves it inked. The pixels themselves can.
    expect(
      erased,
      isNot(pixelsOf(tester, frameB)),
      reason: '⛔CONTROL: the eraser changed A',
    );

    await seekTo(tester, 1);
    await pressEnter(tester);
    // ⚠️Within one level a channel, not byte for byte: the live erase on A
    // landed through the pen-up's own path and the one laid down here
    // through the commit's, and the two round an erased edge one level
    // apart (measured: one sample, 10 against 11). An erase that did not
    // come back as an erase would differ by the whole line.
    final laid = pixelsOf(tester, frameB);
    var worst = 0;
    for (var i = 0; i < laid.length; i += 1) {
      for (var shift = 0; shift < 32; shift += 8) {
        final gap =
            (((laid[i] >> shift) & 0xFF) - ((erased[i] >> shift) & 0xFF)).abs();
        worst = gap > worst ? gap : worst;
      }
    }
    expect(worst, lessThanOrEqualTo(1), reason: '지우개면 지우는 모양으로 덮는다');
  });

  testWidgets('on an EMPTY cell it takes the stroke\'s door: with the auto '
      'frame on the cel is made and the stroke lands in it as ONE undo', (
    tester,
  ) async {
    AppInput.settings.value = const AppInputSettings(
      autoCreateFrameOnDraw: true,
    );
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    final drawn = pixelsOf(tester, frameA);

    await seekTo(tester, 2);
    final session = sessionOf(tester);
    expect(
      session.activeLayer!.timeline.containsKey(2),
      isFalse,
      reason: '⛔전제: 빈 칸',
    );
    final entriesBefore = session.historyManager.undoCount;
    await pressEnter(tester);

    final made = session.activeLayer!.timeline[2];
    expect(made, isNotNull, reason: '칸이 만들어졌다');
    expect(pixelsOf(tester, made!.frameId!), drawn, reason: '그리고 덮였다');
    expect(
      session.historyManager.undoCount,
      entriesBefore + 1,
      reason: '⛔블록과 선이 한 걸음 — 펜으로 빈 칸에 그은 것과 같다',
    );

    session.undo();
    await pumpFrames(tester);
    expect(
      session.activeLayer!.timeline.containsKey(2),
      isFalse,
      reason: '되돌리기 한 번에 칸까지',
    );
  });

  testWidgets('…and with the auto frame OFF an empty cell takes nothing', (
    tester,
  ) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);

    await seekTo(tester, 2);
    final session = sessionOf(tester);
    final entriesBefore = session.historyManager.undoCount;
    await pressEnter(tester);

    expect(session.activeLayer!.timeline.containsKey(2), isFalse);
    expect(session.historyManager.undoCount, entriesBefore);
  });

  testWidgets('the rail\'s ↵ is the same verb — grey until there is a '
      'stroke, and the stroke survives a walk to another CUT', (tester) async {
    await pumpApp(tester);
    expect(railConfirm, findsOneWidget);
    expect(
      tester.widget<RailButton>(railConfirm).onPressed,
      isNull,
      reason: '할 게 없으면 회색',
    );

    await strokeAt(tester, Offset.zero);
    final drawn = pixelsOf(tester, frameA);
    expect(tester.widget<RailButton>(railConfirm).onPressed, isNotNull);

    // 유저 08-27: 「프로그램을 닫을 때까지」 — the cut is left behind, the
    // stroke is not.
    sessionOf(tester).selectCut(otherCutId);
    await pumpFrames(tester);
    await tester.tap(railConfirm);
    await pumpFrames(tester);
    expect(pixelsOf(tester, frameC, cut: otherCutId), drawn);
  });

  testWidgets('the TRANSFORM tool never lays the stroke down: with nothing '
      'to replay its Enter does nothing, and its ↵ is grey', (tester) async {
    await pumpApp(tester);
    await strokeAt(tester, Offset.zero);
    await seekTo(tester, 1);
    await useTool(tester, CanvasTool.move);
    expect(
      tester.widget<RailButton>(railConfirm).onPressed,
      isNull,
      reason: '변형도구에서 확정은 적용이다 — 재현할 변형도, 확정할 것도 없다',
    );

    final entriesBefore = sessionOf(tester).historyManager.undoCount;
    await pressEnter(tester);
    expect(inkIn(pixelsOf(tester, frameB)), 0, reason: '⛔재입력이 아니다');
    expect(sessionOf(tester).historyManager.undoCount, entriesBefore);
  });
}
