import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_scrub.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart'
    show commitStoryboardScrub;

/// 🚨F-90 (유저 2026-09-12): 「스토리보드패널, 룰러 드래그 하는동안 se의
/// 네임태그가 캔버스에 존재했던게 다음 컷이나 갭부분까지 남아있음. 안남아있도록
/// 비디오트랙이나 se트랙이나 법 하나로 통일」.
///
/// A scrub past the cut parks the canvas on the track stack, which draws the
/// parked frame's picture AND its name tags. The editing canvas's own tags
/// have to leave with its picture.
void main() {
  const stackKey = ValueKey<String>('canvas-track-stack-view');

  /// Held by its own type, so the mutation campaign names this file a
  /// witness of the scrub (see canvas_parked_track_stack_test.dart).
  FrameScrub scrub(EditorSessionManager s) => s.frameScrub;

  /// Two default-track cuts with a 4-frame gap before the second, and a line
  /// on the first cut's SE row from its first frame to its end.
  (EditorSessionManager, int) gappedSessionWithALine() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.first;
    s.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    s.selectCut(track.cuts[0].id);
    final seRow = s.layers.firstWhere((layer) => layer.kind == LayerKind.se);
    s.selectLayer(seRow.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: '쿵');
    return (s, track.cuts[0].duration);
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
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
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
  }

  /// Drains the prerender scheduler's debounced warming (the established
  /// EditorCanvasArea test epilogue).
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// Whether the EDITING canvas paints name tags — its own overlay, not the
  /// track stack's, which draws the parked frame's through its own painter.
  bool editingCanvasShowsTags(WidgetTester tester) => find
      .byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_SeNameTagOverlayPainter',
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('a scrub past the cut takes the line off the editing canvas with '
      'the picture — over the next cut and over a gap — and back on the cut '
      'the line comes back', (tester) async {
    final (s, cutEnd) = gappedSessionWithALine();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    expect(
      editingCanvasShowsTags(tester),
      isTrue,
      reason: 'the line is on the cut under the playhead',
    );

    // Grab the playhead on its own cut, then drag into the next cut's frames.
    scrub(s).scrubGlobalFrame(0);
    await tester.pump();
    scrub(s).scrubGlobalFrame(cutEnd + 5);
    await tester.pump();
    expect(find.byKey(stackKey), findsOneWidget, reason: 'the picture parked');
    expect(
      editingCanvasShowsTags(tester),
      isFalse,
      reason: '「다음 컷이나 갭부분까지 남아있음」 — the line the drag left goes '
          'with the picture it was on',
    );

    scrub(s).scrubGlobalFrame(cutEnd + 1);
    await tester.pump();
    expect(find.byKey(stackKey), findsOneWidget, reason: 'parked in the gap');
    expect(editingCanvasShowsTags(tester), isFalse, reason: 'and in a gap');

    scrub(s).scrubGlobalFrame(2);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(stackKey), findsNothing, reason: 'back on the cut');
    expect(
      editingCanvasShowsTags(tester),
      isTrue,
      reason: 'back on its own cut, the line is back',
    );

    commitStoryboardScrub(s);
    await drainWarming(tester);
  });
}
