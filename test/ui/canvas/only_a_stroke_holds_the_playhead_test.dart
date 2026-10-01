import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🗣️F-196 (유저 2026-09-27): 「타임라인이 잠금상태? 룰러쪽 드래그
/// 안먹는데 위아래 이동은 먹힘. 애초에 잠그는 기능을 싹 다 빼고 필요한거만
/// 보고해」.
///
/// The one lock that stayed, and the ones that went. Switched off in turn
/// and measured (2026-09-27): a SEEK under the pen was already safe — the
/// canvas pins a live stroke to its cel — but a ruler SCRUB and a CUT
/// SWITCH under the pen threw the stroke away. So a live stroke keeps the
/// playhead and the cut where they are until the pen lifts (R15-⑤), and a
/// selection drag — marquee or move — holds nothing: a session walks to the
/// next cel and a float writes nothing until it lands.
void main() {
  const frameA = FrameId('nl-frame-a');
  const frameB = FrameId('nl-frame-b');
  const frameC = FrameId('nl-frame-c');
  const layerId = LayerId('nl-layer');
  const otherLayerId = LayerId('nl-other-layer');
  const cutId = CutId('nl-cut');
  const otherCutId = CutId('nl-other-cut');

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

  Project project() => Project(
    id: const ProjectId('nl-project'),
    name: 'No lock',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('nl-track'),
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
        projectId: const ProjectId('nl-project'),
        trackId: const TrackId('nl-track'),
        cutId: cut,
        layerId: cut == cutId ? layerId : otherLayerId,
        frameId: frameId,
      );

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  EditorSessionManager sessionOf(WidgetTester tester) =>
      workspaceOf(tester).session;

  int inkOf(WidgetTester tester, FrameId frameId, {CutId cut = cutId}) {
    final coordinator = sessionOf(tester).pixelEditing.coordinator!;
    final surface = coordinator.currentSurfaceOf(keyFor(frameId, cut: cut));
    final size = surface.canvasSize;
    var ink = 0;
    for (var y = 0; y < size.height; y += 4) {
      for (var x = 0; x < size.width; x += 4) {
        if ((surfacePixelRgba(surface, x, y) ?? 0) != 0) {
          ink += 1;
        }
      }
    }
    return ink;
  }

  /// ⛔Not `pumpAndSettle`: the marching ants of an open box never settle.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> useTool(WidgetTester tester, CanvasTool tool) async {
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(tool: tool);
    await pumpFrames(tester);
  }

  /// A pen drag across the canvas; [midway] runs with the pen down.
  Future<void> drag(
    WidgetTester tester, {
    required void Function(EditorSessionManager session) midway,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final gesture = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: kind,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    midway(sessionOf(tester));
    await pumpFrames(tester, 2);
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.up();
    await pumpFrames(tester);
  }

  testWidgets('a scrub under the pen waits, and the stroke lands where it '
      'began', (tester) async {
    await pumpApp(tester);
    await drag(
      tester,
      midway: (session) {
        session.frameScrub.scrubFrameIndex(1);
        session.frameScrub.commitFrameScrub();
      },
    );
    expect(tester.takeException(), isNull);
    expect(sessionOf(tester).currentFrameIndex, 0, reason: 'the scrub waited');
    expect(inkOf(tester, frameA), greaterThan(0), reason: 'A took the line');
    expect(inkOf(tester, frameB), 0);
  });

  testWidgets('a cut switch under the pen waits too', (tester) async {
    await pumpApp(tester);
    await drag(tester, midway: (session) => session.selectCut(otherCutId));
    expect(tester.takeException(), isNull);
    expect(sessionOf(tester).activeCutOrNull?.id, cutId);
    expect(inkOf(tester, frameA), greaterThan(0), reason: 'the line survived');
    expect(inkOf(tester, frameC, cut: otherCutId), 0);
  });

  testWidgets('a marquee holds nothing — the seek runs mid-drag', (
    tester,
  ) async {
    await pumpApp(tester);
    await useTool(tester, CanvasTool.select);
    await drag(
      tester,
      kind: PointerDeviceKind.mouse,
      midway: (session) => session.selectFrameIndex(1),
    );
    expect(tester.takeException(), isNull);
    expect(sessionOf(tester).currentFrameIndex, 1);
  });

  testWidgets('a move holds nothing — the seek runs, and nothing lands '
      'anywhere', (tester) async {
    await pumpApp(tester);
    await drag(tester, midway: (_) {});
    final drawn = inkOf(tester, frameA);
    expect(drawn, greaterThan(0), reason: 'CONTROL: the rig draws');
    await useTool(tester, CanvasTool.move);
    await drag(
      tester,
      kind: PointerDeviceKind.mouse,
      midway: (session) => session.selectFrameIndex(1),
    );
    expect(tester.takeException(), isNull);
    expect(sessionOf(tester).currentFrameIndex, 1);
    expect(inkOf(tester, frameA), drawn, reason: 'A is as it was');
    expect(inkOf(tester, frameB), 0, reason: 'nothing floated onto B');
  });
}
