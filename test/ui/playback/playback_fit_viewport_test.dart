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

/// D12: playback defaults to FIT, per cut — entering a cut reframes the
/// viewport onto that cut's own canvas (cuts can differ in size), through
/// the panel's playback-follow law (CanvasAutoFrameRequest, the timesheet
/// page-turn's mechanism). Between crossings the viewport stays
/// user-owned: the token only changes on cut ENTRY, so a manual pan
/// mid-cut survives until the next boundary (D13's half of the deal).
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

  Future<EditorSessionManager> pumpArea(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();
    return session;
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

  testWidgets('D12: entering a cut fits ITS canvas; the frames inside it '
      'leave the viewport user-owned; the next cut refits', (tester) async {
    final session = await pumpArea(tester);
    final before = panelViewport(tester);
    expect(before.zoom, 1.0, reason: 'the editing viewport starts identity');

    // All-cuts playback from cut 1 (400x300 into ~900x700 → zoom > 1).
    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    // The reframe is post-frame (the panel's autoFrame law) — one more
    // frame lands it.
    await tester.pump();
    final fitCut1 = panelViewport(tester);
    expect(
      fitCut1.zoom,
      greaterThan(1.0),
      reason: 'cut 1 (400x300) fits UP into the panel',
    );

    // Mid-cut ticks must not stomp the viewport: pan by hand, advance
    // frames WITHIN cut 1, and the pan survives (the token is the cut).
    // 10fps · 4 frames per cut: 100ms steps stay inside cut 1.
    await tester.pump(const Duration(milliseconds: 100));
    final panned = fitCut1.copyWith(panX: fitCut1.panX + 40);
    tester
        .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .onViewportChanged!(panned);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      panelViewport(tester).panX,
      panned.panX,
      reason: 'no per-frame refit — the user owns the viewport mid-cut',
    );

    // Cross into cut 2 (1600 wide): the fit fires again, at a smaller
    // zoom than cut 1's (a 4x wider canvas into the same panel).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final fitCut2 = panelViewport(tester);
    expect(
      fitCut2.zoom,
      lessThan(fitCut1.zoom),
      reason: 'the 1600-wide cut fits at a smaller zoom — the crossing '
          'refit, per cut, exactly once',
    );
    expect(
      fitCut2.panX,
      isNot(panned.panX),
      reason: 'the crossing reframes — the mid-cut pan ended at the '
          'boundary',
    );

    session.playback.stop();
    await drainWarming(tester);
  });

  testWidgets('D12: camera view ON fits the camera\'s OUTPUT frame at the '
      'origin — the project-wide frame, not the cut\'s canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(true);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();

    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump();
    final fitCamera = panelViewport(tester);
    final frame = session.cameraFrameSize;
    // The camera frame is project-wide: both cuts fit the SAME rect, so
    // the zoom matches a fit of that frame, not of cut 1's 400x300.
    final panelSize = tester.getSize(find.byType(BrushCanvasPanel));
    final expected = CanvasViewport.fitToView(
      canvasWidth: frame.width.toDouble(),
      canvasHeight: frame.height.toDouble(),
      viewportWidth: panelSize.width,
      viewportHeight: panelSize.height,
    );
    expect(fitCamera.zoom, moreOrLessEquals(expected.zoom, epsilon: 0.2));

    session.playback.stop();
    await drainWarming(tester);
  });
}
