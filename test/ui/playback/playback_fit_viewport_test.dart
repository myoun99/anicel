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
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// D12 × R6q2 (유저 확정 08-18): playback fit is the CAMERA VIEW's.
/// Toggle ON — playback frames the camera's output frame for as long as it
/// runs, and the user's framing is there again the moment it stops. Toggle
/// OFF — playback never touches the viewport at all: the user's framing is
/// the framing.
///
/// 🎯**결정 7 (유저 08-22): the fit STANDS IN FRONT of the user's framing;
/// it does not overwrite and restore it.** 「한프레임 늦추면 뭔가 시간적인
/// 느낌이 이상해지지않을까」 — so the fit had to stop being a write. It now
/// resolves at the READ (`BrushCanvasPanel.unframedFit`), which is what the
/// first-frame pin below measures, and the stored framing is never written
/// at all, which is what the silence pin measures.
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

  Future<({EditorSessionManager session, double ratio})> pumpArea(
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

    // 🚨The view is STORED in device pixels and PAINTED in logical ones, and
    // this file writes the first and reads the second — so the factor between
    // them is MEASURED here rather than assumed to be `tester.view
    // .devicePixelRatio` (the panel's ratio also carries the UI scale). Write
    // a known device zoom, read what the panel paints, put the view back to
    // unframed. Without this every number below is silently off by 3× and the
    // pins read as implementation failures.
    final controller = tester
        .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .viewportController!;
    controller.value = CanvasViewport(zoom: 8);
    await tester.pump();
    final ratio =
        8 /
        tester
            .widget<CanvasViewportGestureLayer>(
              find.byType(CanvasViewportGestureLayer),
            )
            .viewport
            .zoom;
    controller.value = null;
    await tester.pump();
    return (session: session, ratio: ratio);
  }

  /// What the panel actually PAINTS AND HIT-TESTS WITH.
  ///
  /// 🚨⛔NOT `publishedViewport`, which this file used to read. That getter
  /// answers off the widget's own fields — the STORED framing — and the
  /// playback fit is deliberately not stored any more. Reading it here would
  /// have quietly measured the user's framing all through playback and
  /// passed every pin below for the wrong reason. The gesture layer takes
  /// the panel's resolved view because it has to turn pointer positions into
  /// canvas ones, so it cannot be given anything but the painted value.
  CanvasViewport paintedViewport(WidgetTester tester) => tester
      .widget<CanvasViewportGestureLayer>(
        find.byType(CanvasViewportGestureLayer),
      )
      .viewport;

  /// The view object the DOCUMENT keeps — the one that gets saved, and the
  /// one the user's framing lives in. During playback the panel is handed a
  /// different object, so this is where "was the user's framing touched?"
  /// is asked.
  ValueNotifier<CanvasViewport?> storedView(WidgetTester tester) => tester
      .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
      .viewportController!;

  /// Frames the view the way a hand does — into the object in force, which
  /// is where the panel's own gestures land too. [viewport] is given in the
  /// LOGICAL units [paintedViewport] reads back, and converted on the way in
  /// (the panel's own setter does exactly this).
  CanvasViewport asStored(CanvasViewport logical, double ratio) =>
      logical.copyWith(
        zoom: logical.zoom * ratio,
        panX: logical.panX * ratio,
        panY: logical.panY * ratio,
      );

  void frameByHand(
    WidgetTester tester,
    CanvasViewport viewport, {
    required double ratio,
  }) {
    storedView(tester).value = asStored(viewport, ratio);
  }

  /// Drains the prerender scheduler's debounced warming (the established
  /// EditorCanvasArea test epilogue — its Future.delayed timers cannot be
  /// cancelled by dispose).
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('camera view OFF: playback never touches the viewport — a '
      'manual pan survives start, crossings and stop', (tester) async {
    final rig = await pumpArea(tester, cameraView: false);
    final session = rig.session;
    final ratio = rig.ratio;
    final before = paintedViewport(tester);
    // ⚠️Whatever the view OPENED at — the identity, not a render 1.0. The
    // claim here is that playback does not touch it, so the number itself
    // is not the point.
    final opened = before.zoom;

    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump();
    expect(
      paintedViewport(tester).zoom,
      opened,
      reason: "toggle OFF = 재생 시 fit 안 함 (유저 확정 08-18)",
    );

    // Pan by hand mid-run, then cross into cut 2 exactly at local 0.
    final panned = paintedViewport(tester).copyWith(panX: 40);
    frameByHand(tester, panned, ratio: ratio);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      paintedViewport(tester).panX,
      40,
      reason: 'no fit at the crossing either — the framing is the user\'s',
    );

    session.playback.stop();
    await tester.pump();
    expect(paintedViewport(tester).panX, 40, reason: 'and none on stop');
    await drainWarming(tester);
  });

  testWidgets('camera view ON: THE VERY FIRST FRAME OF PLAYBACK IS ALREADY '
      'FITTED — no post-frame write, so no frame of lag (결정 7)',
      (tester) async {
    final rig = await pumpArea(tester, cameraView: true);
    final session = rig.session;
    final ratio = rig.ratio;
    final prePlay = paintedViewport(tester).copyWith(panX: 123, zoom: 2.0);
    frameByHand(tester, prePlay, ratio: ratio);
    await tester.pump();
    expect(paintedViewport(tester).zoom, 2.0, reason: 'presence first');

    session.playback.play(scope: PlaybackScope.allCuts);
    // ⚠️ONE pump. This is the whole point of the pin: the old shape read
    // the request in `didUpdateWidget`, deferred the reframe to a
    // post-frame callback and reframed with a `setState`, so the first
    // painted frame of playback still carried the user's zoom and the fit
    // landed on the second. A second pump here would pass either way.
    await tester.pump();
    expect(
      paintedViewport(tester).zoom,
      isNot(2.0),
      reason: '재생을 알게 된 그 프레임이 이미 fit이어야 한다 (결정 7)',
    );
    // ⚠️Stop first: `pumpAndSettle` inside the drain cannot settle while the
    // playback ticker keeps scheduling frames.
    session.playback.stop();
    await tester.pump();
    await drainWarming(tester);
  });

  testWidgets('camera view ON: playback frames the camera output and the '
      'user\'s framing comes back on stop — WITHOUT EVER BEING WRITTEN',
      (tester) async {
    final rig = await pumpArea(tester, cameraView: true);
    final session = rig.session;
    final ratio = rig.ratio;
    final prePlay = paintedViewport(tester).copyWith(panX: 123, zoom: 2.0);
    frameByHand(tester, prePlay, ratio: ratio);
    await tester.pump();

    // ★The document's own view object, captured BEFORE playback swaps a
    // different one in front of it. Every write to it from here on is a
    // failure: the fit must not pass through the thing that gets saved.
    final document = storedView(tester);
    var documentWrites = 0;
    void count() => documentWrites += 1;
    document.addListener(count);
    addTearDown(() => document.removeListener(count));

    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump();
    final fitStart = paintedViewport(tester);
    expect(fitStart.zoom, isNot(2.0), reason: 'play start fits the frame');
    expect(
      document.value,
      asStored(prePlay, ratio),
      reason: 'the fit is somewhere else entirely — a save taken here still '
          'persists the framing the user chose',
    );

    // Cross into cut 2 EXACTLY at local frame 0: the cursor publishes 0→0
    // (suppressed) and the empty-layer cuts publish no row — only the D12
    // notifier can carry the crossing.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      paintedViewport(tester).panX,
      fitStart.panX,
      reason: '컷마다 fit — the crossing refits the same camera frame',
    );

    session.playback.stop();
    await tester.pump();
    final restored = paintedViewport(tester);
    expect(restored.zoom, 2.0, reason: '정지 시 유저의 프레이밍 (유저 확정 08-18)');
    expect(restored.panX, 123);
    expect(
      documentWrites,
      0,
      reason: '★결정 7: nothing was saved aside and nothing was put back, '
          'because nothing was ever overwritten. The old restore ran only '
          'if `mounted` and the camera toggle still agreed — conditions '
          'under which the framing could quietly fail to come back.',
    );
    await drainWarming(tester);
  });

  testWidgets('camera view ON: a pan DURING playback moves the view (D13) '
      'and still leaves the user\'s framing untouched', (tester) async {
    final rig = await pumpArea(tester, cameraView: true);
    final session = rig.session;
    final ratio = rig.ratio;
    final prePlay = paintedViewport(tester).copyWith(panX: 123, zoom: 2.0);
    frameByHand(tester, prePlay, ratio: ratio);
    await tester.pump();
    final document = storedView(tester);

    session.playback.play(scope: PlaybackScope.allCuts);
    await tester.pump();
    await tester.pump();
    final fitStart = paintedViewport(tester);

    // D13 (유저 확정 08-17): 「재생 중 팬·줌 가능」. The pan lands in the
    // object playback was handed, which is a DIFFERENT object from the
    // document's — so it takes over from the fit exactly the way a first
    // framing takes over from the identity on a fresh canvas.
    frameByHand(tester, fitStart.copyWith(panX: fitStart.panX + 40), ratio: ratio);
    await tester.pump();
    expect(
      paintedViewport(tester).panX,
      fitStart.panX + 40,
      reason: 'the pan has to actually move the view — a fit that could not '
          'be panned off would have made D13 a dead letter',
    );
    expect(document.value, asStored(prePlay, ratio), reason: 'and none of it reached the doc');

    session.playback.stop();
    await tester.pump();
    expect(paintedViewport(tester).zoom, 2.0);
    expect(paintedViewport(tester).panX, 123);
    await drainWarming(tester);
  });
}
