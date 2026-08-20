import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// D12 × R6q2 (유저 확정 08-18): playback fit is the CAMERA VIEW's.
/// Toggle ON — every cut entry fits the camera's output frame and the
/// stop RESTORES the pre-play viewport. Toggle OFF — playback never
/// touches the viewport at all: the user's framing is the framing.
void main() {
  Project project() => Project(
    id: const ProjectId('fit'),
    name: 'Fit',
    frameRate: const ProjectFrameRate.integer(10),
    createdAt: DateTime.utc(2026, 8, 18),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: '1',
            duration: 4,
            canvasSize: const CanvasSize(width: 400, height: 300),
            layers: const [],
          ),
          Cut(
            id: const CutId('cut-2'),
            name: '2',
            duration: 4,
            canvasSize: const CanvasSize(width: 1600, height: 300),
            layers: const [],
          ),
        ],
      ),
    ],
  );

  Future<(EditorSessionManager, ValueNotifier<bool>)> pumpArea(
    WidgetTester tester, {
    required bool cameraView,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraViewEnabled = ValueNotifier<bool>(cameraView);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraViewEnabled.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraViewEnabled,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();
    return (session, cameraViewEnabled);
  }

  CanvasViewport panelViewport(WidgetTester tester) =>
      tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel)).viewport!;

  /// Drains the prerender scheduler's debounced warming (the established
  /// EditorCanvasArea test epilogue — its Future.delayed timers cannot be
  /// cancelled by dispose).
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('camera view OFF: playback never touches the viewport — a '
      'manual pan survives start, crossings and stop', (tester) async {
    final (session, _) = await pumpArea(tester, cameraView: false);
    final before = panelViewport(tester);
    // ⚠️Whatever the view OPENED at — the identity, not a render 1.0. The
    // claim here is that playback does not touch it, so the number itself
    // is not the point.
    final opened = before.zoom;

    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump();
    expect(
      panelViewport(tester).zoom,
      opened,
      reason: "toggle OFF = 재생 시 fit 안 함 (유저 확정 08-18)",
    );

    // Pan by hand mid-run, then cross into cut 2 exactly at local 0.
    final panned = panelViewport(tester).copyWith(panX: 40);
    tester
        .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .onViewportChanged!(panned);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      panelViewport(tester).panX,
      40,
      reason: 'no fit at the crossing either — the framing is the user\'s',
    );

    session.playback.stop();
    await tester.pump();
    expect(panelViewport(tester).panX, 40, reason: 'and none on stop');
    await drainWarming(tester);
  });

  testWidgets('camera view ON: every cut entry fits the camera\'s output '
      'frame (the crossing arrives through the D12 notifier), and the '
      'stop RESTORES the pre-play viewport', (tester) async {
    final (session, _) = await pumpArea(tester, cameraView: true);
    // A distinctive pre-play framing to restore.
    final prePlay = panelViewport(tester).copyWith(panX: 123, zoom: 2.0);
    tester
        .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .onViewportChanged!(prePlay);
    await tester.pump();

    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump();
    final fitStart = panelViewport(tester);
    expect(fitStart.zoom, isNot(2.0), reason: 'play start fits the frame');

    // Pan mid-cut, then cross into cut 2 EXACTLY at local frame 0: the
    // cursor publishes 0→0 (suppressed) and the empty-layer cuts publish
    // no row — only the D12 notifier can carry the crossing, and the
    // re-fit stomps the mid-cut pan back to the frame fit.
    final panned = fitStart.copyWith(panX: fitStart.panX + 40);
    tester
        .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .onViewportChanged!(panned);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      panelViewport(tester).panX,
      fitStart.panX,
      reason: '컷마다 fit — the crossing refits the same camera frame',
    );

    session.playback.stop();
    await tester.pump();
    final restored = panelViewport(tester);
    expect(restored.zoom, 2.0, reason: '정지 시 복원 (유저 확정 08-18)');
    expect(restored.panX, 123);
    await drainWarming(tester);
  });
}
