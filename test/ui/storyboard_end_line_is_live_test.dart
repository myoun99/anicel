import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

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

  // 🗣️F-445 (유저 2026-10-23): 「콘티패널에서만 그런거같은데, 엔드라인 손으로
  // 드래그할때 가끔 프레임영역 가로 스크롤 작동함. 엔드라인은 조작
  // 위젯이니까 작동안하게 제대로 다른위젯처럼 강한클레임으로 법 통일」. The
  // sheet's one drag moves both axes (F-351), so a finger that starts a hair
  // off the line's own axis is the sheet's before a one-axis drag can count.
  testWidgets('🚨a finger on the end line is the line\'s, though it starts '
      'off the line\'s axis — the frame area does not scroll', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final scrollers = [
      for (final state in tester.stateList<ScrollableState>(
        find.descendant(
          of: find.byType(StoryboardPanel),
          matching: find.byType(Scrollable),
        ),
      ))
        state.position,
    ];
    final frames = [
      for (final position in scrollers)
        if (position.axis == Axis.horizontal && position.maxScrollExtent > 0)
          position,
    ];
    expect(frames, isNotEmpty, reason: '⛔전제: the frame area can scroll');
    // To its end, where the line is — and from where a finger moving right
    // would scroll it back.
    for (final frame in frames) {
      frame.jumpTo(frame.maxScrollExtent);
    }
    await tester.pumpAndSettle();
    final before = [for (final position in scrollers) position.pixels];

    final handle = find.byKey(
      const ValueKey<String>('storyboard-cut-end-handle'),
    );
    final line = find.byKey(
      const ValueKey<String>('storyboard-cut-end-line'),
    );
    final lineBefore = tester.getTopLeft(line).dx;
    expect(
      lineBefore,
      lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
      reason: '⛔전제: the line is on screen',
    );
    final finger = await tester.startGesture(
      tester.getCenter(handle),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 16));
    // Past the touch slop as a whole, short of it along the line's axis.
    await finger.moveBy(const Offset(8, -20));
    await tester.pump(const Duration(milliseconds: 16));
    await finger.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));

    expect(session.dragPreview.value, isNotNull, reason: 'the line\'s drag');
    expect(tester.getTopLeft(line).dx, greaterThan(lineBefore));
    expect(
      [for (final position in scrollers) position.pixels],
      before,
      reason: 'neither of the sheet\'s axes moved',
    );

    await finger.up();
    await tester.pumpAndSettle();
  });
}
