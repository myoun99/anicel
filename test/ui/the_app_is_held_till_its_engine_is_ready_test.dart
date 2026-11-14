import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/app_kernels_ahead.dart';
import 'package:anicel/src/services/input/pencil_interaction_service.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_view_hold.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/viewer_page_loading.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/playback/frame_wait_mark.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
/// 띄운다 — 그때까지 고리」 · 「애초에 타임라인같은거도 포함해서 고리띄우고
/// 모든 조작 막음」 — while the app gets its engine ready
/// ([appEngineGetsReady]) the editor takes no input: a press that needed a
/// kernel still to be compiled stopped the whole app for as long as its
/// compile took.
///
/// 🗣️유저 2026-11-11 (채팅, 관제 13:49 전달): 「준비안된화면, 캔버스든
/// 타임라인이든 구분안두고 그냥 여는중? 뭐 그런 로딩 안내창있잖아. 그거
/// 공용창 띄워서 입력 막게하는게 베스트라고생각해」 — the app's one wait
/// window is what stands meanwhile, and what takes that input.
void main() {
  final window = find.byType(AppProgressDialog);
  final ring = find.byType(ViewerPageLoading);
  final add = find.byKey(const ValueKey<String>('new-frame-button'));

  Future<void> stand(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(debugLetTheAppGo);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
  }

  /// The app mounted as a launch mounts it: its tree built BEFORE its first
  /// frame is begun (`runApp` attaches the root, then draws). ⛔Not
  /// `pumpWidget`, which builds a new tree inside the frame it pumps — over
  /// the root every test starts with — where what is asked before that
  /// frame is drawn cannot be told from what is asked after it.
  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(debugLetTheAppGo);
    final launched = ValueNotifier(false);
    addTearDown(launched.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: launched,
          builder: (context, launched, _) => launched
              ? HomePage(initialProject: createDefaultProject())
              : const SizedBox(),
        ),
      ),
    );
    launched.value = true;
    tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
    await tester.pump();
  }

  /// The frames a held app is given: it never settles, its window's
  /// spinner turning.
  Future<void> frames(WidgetTester tester) async {
    for (var frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  EditorSessionManager sessionOf(WidgetTester tester) => tester
      .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
      .projects
      .sessions
      .first;

  CanvasTool toolOf(WidgetTester tester) => tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .brushTool!
      .value
      .tool;

  Future<void> pressUndo(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('held from before its first frame, the app stands behind its '
      'ONE wait window in that frame — no ring of the editor\'s or of a '
      'place\'s under it — and behind none the frame it is let go', (
    tester,
  ) async {
    // A place's own mark as the app stands it (`flutter_test_config.dart`
    // has why the corpus does not): were it to stand meanwhile, it would
    // be seen.
    FrameWaitMark.debugStands = true;
    addTearDown(() => FrameWaitMark.debugStands = false);
    // As a launch says it, before the app is run (`main`).
    holdTheAppForItsEngine();
    await launch(tester);

    expect(window, findsOneWidget, reason: 'in the first frame');
    final up = tester.widget<AppProgressDialog>(window);
    expect(up.windowKey, const ValueKey<String>('launch-progress-dialog'));
    expect(up.title, AppText.strings.launchStageApp);
    expect(up.runningLabel, AppText.strings.launchProgressRunning);
    expect(up.onCancel, isNull, reason: 'no way out of it');

    await frames(tester);
    expect(window, findsOneWidget);
    expect(ring, findsNothing);

    debugLetTheAppGo();
    await tester.pump();

    expect(window, findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('held, the editor takes no press, no bound key, no held key '
      'and no pencil tap — and each once the app is let go', (tester) async {
    await stand(tester);
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    // An edit for the undo to take back.
    await tester.tap(add);
    await tester.pumpAndSettle();
    final edits = session.historyManager.undoCount;
    expect(edits, greaterThan(0), reason: '⛔premise: an edit to take back');
    expect(toolOf(tester), isNot(CanvasTool.eraser), reason: '⛔premise');
    final tap = PencilInteractionService.instance.onPencilTap!;

    holdTheAppForItsEngine();
    await frames(tester);

    await tester.tap(add, warnIfMissed: false);
    await frames(tester);
    expect(session.historyManager.undoCount, edits, reason: 'no press');
    await pressUndo(tester);
    expect(session.historyManager.undoCount, edits, reason: 'no bound key');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasViewHold.held.value, isNull, reason: 'no held key');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    tap(PencilTapAction.switchEraser);
    await frames(tester);
    expect(toolOf(tester), isNot(CanvasTool.eraser), reason: 'no pencil tap');

    debugLetTheAppGo();
    await tester.pumpAndSettle();

    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(session.historyManager.undoCount, edits + 1);
    await pressUndo(tester);
    expect(session.historyManager.undoCount, edits);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(CanvasViewHold.held.value, ViewHold.pan);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    tap(PencilTapAction.switchEraser);
    await tester.pumpAndSettle();
    expect(toolOf(tester), CanvasTool.eraser);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
