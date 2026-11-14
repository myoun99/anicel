import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/viewer_page_loading.dart';
import 'package:anicel/src/ui/playback/frame_wait_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️gpu-canonical-store-Q12 (유저 2026-11-10): 「캔버스 자리에 준비 중 표시를
/// 둔다」 — the canvas is ONE place ([FrameWaitPlace]): the frame it stands
/// on and the track stack it parks on mark it while the engine is still to
/// be opened, with the app's mark for a page that is not there yet
/// (🗣️gpu-canonical-store-Q13, 유저 2026-11-11: 「뷰어 · 출력 · 임포트
/// 미리보기의 그 고리를 그대로 쓴다」 — [ViewerPageLoading], F-315), at the
/// middle of what the panels lying on the canvas leave of it to be seen,
/// and no more once it is open.
///
/// What makes a frame wait, view by view, is
/// `a_frame_that_waits_for_its_plugins_holds_its_picture_test.dart`'s.
void main() {
  final theMark = find.byType(ViewerPageLoading);
  setUp(() => FrameWaitMark.debugStands = true);
  tearDown(() => FrameWaitMark.debugStands = false);

  /// The frames a place's word is heard after, and its mark built or taken
  /// down in.
  Future<void> theMarkFollows(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  // ⚠️First in the file: the app's engine is opened by the first that asks.
  testWidgets('the canvas standing on a frame, then parked on a track '
      'stack, marks the middle of what its floor leaves to be seen till the '
      'engine is open', (tester) async {
    expect(
      appEngineFrameToolsOpen,
      isNull,
      reason: '⛔premise: the engine is still to be opened',
    );
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.selectCut(
      session.repository.requireProject().tracks.first.cuts.first.id,
    );
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    // A timeline lying on the floor's bottom, a region docked on its top.
    const covered = EdgeInsets.only(top: 40, bottom: 200);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasFloorInsets(
            insets: covered,
            child: EditorCanvasArea(
              session: session,
              brushToolState: brushTool,
              cameraViewEnabled: cameraView,
              cameraDimOpacity: cameraDim,
            ),
          ),
        ),
      ),
    );
    await theMarkFollows(tester);
    final seen = covered.deflateRect(
      tester.getRect(find.byType(EditorCanvasArea)),
    );

    expect(theMark, findsOneWidget);
    expect(tester.getCenter(theMark), seen.center);

    session.parkGlobalFrame(0);
    await theMarkFollows(tester);
    expect(
      find.byKey(const ValueKey<String>('canvas-track-stack-view')),
      findsOneWidget,
      reason: '⛔premise: parked, the track stack is shown',
    );
    expect(theMark, findsOneWidget);
    expect(tester.getCenter(theMark), seen.center);

    await tester.runAsync(() => appEngineFrameTools);
    await theMarkFollows(tester);
    await tester.pump();

    expect(theMark, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a place stands one mark while any frame shown in it waits, '
      'however many do', (tester) async {
    late FramesWaiting place;
    await tester.pumpWidget(
      MaterialApp(
        home: FrameWaitPlace(
          child: Stack(
            children: [
              const Positioned.fill(child: FrameWaitMark()),
              Builder(
                builder: (context) {
                  place = FrameWaitPlace.of(context)!;
                  return const SizedBox.expand();
                },
              ),
            ],
          ),
        ),
      ),
    );
    final (one, another) = (Object(), Object());
    expect(theMark, findsNothing);

    place.says(one, waits: true);
    place.says(another, waits: true);
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget);

    place.says(one, waits: false);
    await theMarkFollows(tester);
    expect(theMark, findsOneWidget, reason: 'the other waits still');

    place.says(another, waits: false);
    await theMarkFollows(tester);
    expect(theMark, findsNothing);
  });

  // The canvas panel's shell seats the mark wherever it lies — a conte
  // sheet, a viewer in a rail — and only the canvas is a place.
  testWidgets('a mark in no place stands nothing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FrameWaitMark()));

    expect(theMark, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
