import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// F-18 — **the storyboard RULER's end line follows the drag with the strip's.**
///
/// 유저 2026-08-28: 「프레임영역은 라이브로 따라가는데 룰러에 있는 엔드라인은
/// 라이브로 안보임. 이걸 통일이라고 한거냐?」.
///
/// The strip's end line and grip were made to follow a movie-end drag
/// (`storyboard_end_line_is_live_test.dart`), each through a reader of its
/// own, and the ruler read no preview at all — so mid-drag the ruler kept the
/// committed end while the strip moved.
///
/// ⚠️Measured as PIXELS MOVED under a live drag, by the same distance the strip
/// line moves: a ruler line that exists, or a preview channel that carries a
/// value, is what the old build would also have passed.
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

  testWidgets('dragging the end line moves the ruler\'s end line with it '
      'before the release', (tester) async {
    final session = await pumpStoryboard(tester);

    final line = find.byKey(const ValueKey<String>('storyboard-cut-end-line'));
    final handle = find.byKey(
      const ValueKey<String>('storyboard-cut-end-handle'),
    );
    final rulerLine = find.descendant(
      of: find.byKey(const ValueKey<String>('storyboard-frame-ruler')),
      matching: find.byKey(
        const ValueKey<String>('timeline-cut-end-boundary-ruler'),
      ),
    );
    expect(line, findsOneWidget, reason: 'fixture premise');
    expect(handle, findsOneWidget, reason: 'fixture premise');
    expect(rulerLine, findsOneWidget, reason: 'fixture premise');

    final lineBefore = tester.getTopLeft(line).dx;
    final rulerBefore = tester.getTopLeft(rulerLine).dx;

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      session.dragPreview.value,
      isNotNull,
      reason: 'fixture premise: the drag is live',
    );
    final lineMoved = tester.getTopLeft(line).dx - lineBefore;
    expect(lineMoved, greaterThan(0), reason: 'fixture premise: the strip moved');
    expect(
      tester.getTopLeft(rulerLine).dx - rulerBefore,
      closeTo(lineMoved, 1),
      reason: 'the ruler follows the finger by as much as the strip does',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
