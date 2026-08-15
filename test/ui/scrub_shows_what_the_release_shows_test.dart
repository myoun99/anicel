import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★ #26 — THE DRAG SHOWS WHAT THE RELEASE SHOWS.
///
/// This file used to be ⑯ (`scrub_preview_runway_test`), and it was about a
/// clamp: the scrub PREVIEW pinned an over-end cursor to the cut's last
/// frame, so dragging past the end kept showing a picture and letting go —
/// where the editing canvas reads the cursor literally — took it away. The
/// user asked for no difference at all between past the end and inside it.
///
/// #26 answered the general form of that: 「그냥 액티브레이어급으로 그냥 원본
/// 보여주게하고싶어 … 그냥 항상 full」. There is no preview any more, so there
/// is no second reader of the cursor that could disagree with the first. The
/// runway rule stops being a rule and becomes a consequence — which is why
/// these tests assert the CONSEQUENCE's parent: what the drag shows and what
/// the release shows are the same thing.
///
/// ⛔The anchors matter. "Equal" is trivially true if both sides are empty,
/// so each test also pins that the state it compared is the state it meant
/// to compare: real artwork where there is artwork, blank paper where there
/// is none.
void main() {
  /// The warm a scrub kicks off is real work on a real scheduler — let it
  /// finish rather than leaving a timer for the harness to trip over.
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// What the editing canvas is actually showing: the cel under the playhead
  /// (the active surface) and how many other layers stack with it.
  ({Object? surface, int nodes}) shown(WidgetTester tester) {
    final view = tester.widget<CanvasLayerStackView>(
      find.byType(CanvasLayerStackView).first,
    );
    return (
      surface: view.activeSurfacePainter?.surface,
      nodes: view.nodes.length,
    );
  }

  Future<void> pumpCanvas(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
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
  }

  testWidgets('a drag past the cut end shows the blank paper the release '
      'shows — not the last frame it could still find', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final runwayFrame = session.activeCutOrNull!.duration + 3;

    // ⛔The artwork goes on the frame the drag ENGAGES on, and that is not
    // fussiness: the first move flips `frameScrubActive`, which rebuilds the
    // canvas area on its own. Anchor anywhere else and a canvas frozen at
    // the engage frame shows blank paper too — the test passes while the
    // feature is gone. Measured: this exact test did.
    session.selectFrameIndex(3);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(0);
    await pumpCanvas(tester, session);

    // The drag engages on the artwork and runs out onto the runway.
    session.scrubFrameIndex(3);
    await tester.pump();
    final engaged = shown(tester);
    expect(
      engaged.surface,
      isNotNull,
      reason: 'the anchor: the gesture engaged on a frame that holds a cel',
    );

    session.scrubFrameIndex(runwayFrame);
    await tester.pump();
    expect(session.frameScrubActive.value, isTrue, reason: 'mid-gesture');
    final duringDrag = shown(tester);
    expect(
      duringDrag.surface,
      isNull,
      reason: 'past the end there is no frame — the paper is the answer',
    );
    expect(
      duringDrag,
      isNot(engaged),
      reason: 'the canvas actually moved off the artwork it started on',
    );

    session.commitFrameScrub();
    await tester.pump();
    expect(
      shown(tester),
      duringDrag,
      reason: 'letting go changes nothing — that is the whole law',
    );

    await drainWarming(tester);
  });

  testWidgets('a drawing OUT on the runway paints while dragging — the paper '
      'is for frames that hold nothing, not for frames past a number', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final runwayFrame = session.activeCutOrNull!.duration + 3;

    // ＋ works out here — the runway takes cels like any other frame — so a
    // canvas that decided by index alone would hide real artwork.
    session.selectFrameIndex(runwayFrame);
    session.createDrawingAtCurrentFrame();
    await pumpCanvas(tester, session);

    session.selectFrameIndex(0);
    await tester.pump();
    final atZero = shown(tester);

    session.scrubFrameIndex(1);
    await tester.pump();
    session.scrubFrameIndex(runwayFrame);
    await tester.pump();
    expect(session.frameScrubActive.value, isTrue, reason: 'mid-gesture');
    final duringDrag = shown(tester);
    expect(
      duringDrag.surface,
      isNotNull,
      reason: 'the drag shows what the release will show — a drawing',
    );
    expect(duringDrag, isNot(atZero), reason: 'and not where it came from');

    session.commitFrameScrub();
    await tester.pump();
    expect(shown(tester), duringDrag, reason: 'letting go changes nothing');

    await drainWarming(tester);
  });
}
