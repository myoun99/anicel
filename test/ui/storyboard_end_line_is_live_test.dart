import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

/// F-18 — **the storyboard's end line follows the drag.**
///
/// 유저 2026-08-24: 「스토리보드패널의 엔드라인 드래그시 라이브로 안보임. 어떤
/// 다른 규칙을 만든거지? 타임라인패널이랑 통일」.
///
/// The storyboard's body builds from the COMMITTED project once, on purpose —
/// the drag preview is read further down, where a measurement says it matters.
/// The end line was built up there with it, so it stood still until release
/// while its timeline sibling followed the pointer.
///
/// ⚠️Measured as PIXELS MOVED under a live drag. Asserting that the widget
/// exists, or that the session's preview channel carries a value, is what the
/// old build would also have passed — the preview was there all along; the
/// line simply did not read it.
void main() {
  Future<EditorSessionManager> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  testWidgets('dragging the end line moves it before the release', (
    tester,
  ) async {
    final session = await pumpStoryboard(tester);

    final line = find.byKey(
      const ValueKey<String>('storyboard-cut-end-line'),
    );
    final handle = find.byKey(
      const ValueKey<String>('storyboard-cut-end-handle'),
    );
    expect(line, findsOneWidget, reason: 'fixture premise');
    expect(handle, findsOneWidget, reason: 'fixture premise');

    final before = tester.getTopLeft(line).dx;
    final grip = tester.getCenter(handle);

    final gesture = await tester.startGesture(grip);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 16));

    // MID-DRAG: nothing has been committed yet, and the line has moved.
    expect(
      session.dragPreview.value,
      isNotNull,
      reason: 'fixture premise: the drag is live',
    );
    expect(
      tester.getTopLeft(line).dx,
      greaterThan(before),
      reason: 'the line follows the finger — 「타임라인패널이랑 통일」',
    );
    expect(
      tester.getCenter(handle).dx,
      greaterThan(grip.dx),
      reason: 'and so does the grip, or the finger leaves it behind on the '
          'first frame of every drag',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
