import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_shift_buttons.dart';

/// T17 — a button must answer about NOW, and to do that it has to subscribe
/// to everything its predicate reads.
///
/// 유저 2026-08-13: 「뒤 블록이 붙어있는 상태에서는 당기기버튼 비활성화잖아.
/// 그건 좋은데 그 상태에서 밀고나면 여백생기는데, 그 상태에서 당기기버튼
/// 활성화 안 됨」 — and the tell was that stepping one frame away and back
/// woke it up, because a committed seek was the only signal the pair had.
///
/// ⚠️This drives the REAL buttons rather than the session verbs. A test that
/// called `pushBlocks` and then read `canPullBlocks` passes on the broken
/// build: the predicate was never wrong, the widget was. Killing the session
/// subscription in `TimelineShiftButtons` must fail something, and this is
/// the something.
void main() {
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  // The key sits ON the IconButton (see AppIconButton), so this reads the
  // widget itself rather than a descendant.
  bool enabled(WidgetTester tester, String keyValue) =>
      tester.widget<IconButton>(find.byKey(ValueKey<String>(keyValue)))
          .onPressed !=
      null;

  testWidgets('the pair wakes on an ARRANGEMENT change — no seek, no parent '
      'rebuild', (tester) async {
    // 🚨MOUNTED ALONE, deliberately. In the whole app a push also vacates the
    // anchor cell, which flips `canDeleteCellAtCurrentFrame` and friends, drops
    // the toolbar's cached widget and rebuilds this pair for an unrelated
    // reason — so an app-level test passes on a build with no subscription at
    // all. It did exactly that when this was first written, and the mutation
    // run is what caught it.
    //
    // ⚠️Do not "promote" this to the full HomePage to make it look more
    // realistic. Nothing in this tree rebuilds on its own, which is the only
    // way the widget's own subscription is the thing under test.
    final session = EditorSessionManager(initialProject: createDefaultProject());
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TimelineShiftButtons(session: session))),
    );
    await tester.pumpAndSettle();

    // Packed against frame 0: there is no lead-in to close.
    expect(session.canPullBlocks(), isFalse);
    expect(enabled(tester, 'pull-blocks-button'), isFalse);
    expect(enabled(tester, 'push-blocks-button'), isTrue);

    // An EDIT, not a seek — and nothing above this widget is listening.
    session.pushBlocks(1);
    await tester.pump();

    expect(
      session.canPullBlocks(),
      isTrue,
      reason: 'the arrangement really did change',
    );
    expect(
      enabled(tester, 'pull-blocks-button'),
      isTrue,
      reason: 'and the button that reads it says so, on its own subscription',
    );

    // Both ways: closing the slack greys it again.
    session.pullBlocks(1);
    await tester.pump();
    expect(session.canPullBlocks(), isFalse);
    expect(enabled(tester, 'pull-blocks-button'), isFalse);

    // Unmount before disposing: the widget holds two listeners on this
    // session, and the session owns timers the test binding checks for.
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('and the real buttons on the bar drive that verb', (
    tester,
  ) async {
    final session = await pump(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    expect(enabled(tester, 'push-blocks-button'), isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('push-blocks-button')));
    await tester.pumpAndSettle();

    expect(session.canPullBlocks(), isTrue);
    expect(enabled(tester, 'pull-blocks-button'), isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('pull-blocks-button')));
    await tester.pumpAndSettle();
    expect(session.canPullBlocks(), isFalse);
  });

  /// T16 — the delete glyph's two ends are NAMED, so no third colour exists
  /// for a baked bar to freeze on.
  ///
  /// 유저: 「블록에 있다가 빈칸하면 빨강→하양→회색. 중간에 이상하게 하얀색이
  /// 존재하는 버그」 · 「접고 나서 빈칸 가면 공통삭제가 하얀색됨」.
  testWidgets('the shared delete crosses from red to dim with no third '
      'colour in between', (tester) async {
    final session = await pump(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    Color? glyph() => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('shared-delete-button')),
            matching: find.byType(Icon),
          ),
        )
        .color;

    expect(glyph(), AppColors.danger);

    // Step onto empty paper. Every frame of the crossing must be one of the
    // two named colours — the white the user saw was the BUTTON's live ink
    // showing through a null.
    session.selectFrameIndex(session.activeCutPlaybackFrameCount - 1);
    for (var frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(
        glyph(),
        anyOf(AppColors.danger, AppColors.glyphDisabled),
        reason: 'no third colour may appear while the gate flips',
      );
    }
    await tester.pumpAndSettle();
    expect(glyph(), isNot(AppColors.text));
  });
}
