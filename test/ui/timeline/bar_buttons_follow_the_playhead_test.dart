import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/panel_collapsed_scope.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';

/// 🚨#10 (유저 정정 2026-08-21): 「접어서 간편오버레이 상태가 됐을때,
/// **타임라인이나 스토리보드에있는 버튼**이 제대로 **인덱스에 맞춰서
/// 활성화/비활성화가 안된다.** 그거를 제대로 **버튼 싹 다** 맞춰서
/// 해달라는것」
///
/// 🎯**Measured, the fold was innocent** — and that mattered, because the
/// obvious reading (「접었을 때만 그렇다」) would have sent the fix into the
/// collapse machinery. Folded and open answered identically on every path
/// this file drives. What was actually broken was the **ruler drag**, in
/// both states alike: a committed seek fires on the RELEASE, so for the
/// whole gesture the bar showed the frame the drag began on and snapped
/// when the finger came up. While the panel is folded the command bar is
/// all that is left of it (「접으면 버튼행만 남는다」), which is why the
/// report arrived attached to the fold.
///
/// ⚠️Buttons are ENUMERATED from the tree, never listed here. 「버튼 싹 다」
/// is the ask, and a hand-written list is a list of the buttons that
/// existed the day it was written — the previous contract file's ten
/// missed fifteen, including every one this round fixed.
EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

bool _isCollapsed(WidgetTester tester) => tester
    .widgetList<PanelCollapsedScope>(find.byType(PanelCollapsedScope))
    .any((scope) => scope.collapsed);

/// Every keyed, enable-able widget under the command bar.
Map<String, bool> _bar(WidgetTester tester) {
  final out = <String, bool>{};
  for (final bar in find.byType(TimelineCommandBar).evaluate()) {
    void visit(Element element) {
      final widget = element.widget;
      final key = widget.key;
      if (key is ValueKey<String>) {
        final enabled = switch (widget) {
          TextButton(:final onPressed) => onPressed != null,
          IconButton(:final onPressed) => onPressed != null,
          InkWell(:final onTap) => onTap != null,
          _ => null,
        };
        if (enabled != null) {
          out[key.value] = enabled;
        }
      }
      element.visitChildren(visit);
    }

    bar.visitChildren(visit);
  }
  return out;
}

Future<void> _pump(WidgetTester tester, {required bool storyboard}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  if (storyboard) {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
  }
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -420),
  );
  await tester.pumpAndSettle();
}

Future<void> _collapse(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('floating-bottom-collapse')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a ruler DRAG moves the timeline bar, and it already reads what '
      'the release will say', (tester) async {
    await _pump(tester, storyboard: false);
    final session = _sessionOf(tester);
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final onTheBlock = _bar(tester);
    expect(onTheBlock, isNotEmpty);

    // A SCRUB — the live ruler drag's own caller, and deliberately not a
    // committed seek: the commit is the signal the bar already had.
    session.scrubFrameIndex(6);
    await tester.pumpAndSettle();
    final duringDrag = _bar(tester);
    expect(
      duringDrag,
      isNot(onTheBlock),
      reason:
          'measured before the fix: NINE of twenty-five buttons sat at '
          'the drag\'s starting frame for the whole gesture',
    );

    session.selectFrameIndex(6);
    await tester.pumpAndSettle();
    expect(
      _bar(tester),
      duringDrag,
      reason:
          'and the release changes nothing — a bar that snaps on release '
          'was showing the wrong answer until then',
    );
  });

  testWidgets('the storyboard bar follows its own drag the same way', (
    tester,
  ) async {
    await _pump(tester, storyboard: true);
    final session = _sessionOf(tester);
    session.selectGlobalFrame(0);
    await tester.pumpAndSettle();
    final atStart = _bar(tester);

    session.scrubGlobalFrame(400);
    await tester.pumpAndSettle();
    final duringDrag = _bar(tester);
    expect(duringDrag, isNot(atStart));

    session.selectGlobalFrame(400);
    await tester.pumpAndSettle();
    final afterRelease = _bar(tester);
    // ⚠️ONE button legitimately waits for the release: the shift pair is
    // anchored on the ACTIVE CUT, and a scrub is a preview that has not
    // taken a cut yet. Its answer is about what a press would do RIGHT
    // NOW, so it must not move until the seek commits — measured, not
    // assumed (`canPushCuts` reads `_cutShiftScope`, which asks for the
    // active cut and never for the parked frame).
    final movedOnRelease = [
      for (final key in afterRelease.keys)
        if (afterRelease[key] != duringDrag[key]) key,
    ];
    expect(movedOnRelease, ['push-blocks-button']);
  });

  /// The fold, measured against itself: same panel, same drag, folded and
  /// open. ⚠️One app per test — the second `_pump` in a single test cannot
  /// find the region's splitter, because the first one folded it away.
  Future<void> foldReadsLikeOpen(
    WidgetTester tester, {
    required bool storyboard,
  }) async {
    await _pump(tester, storyboard: storyboard);
    final session = _sessionOf(tester);
    void toStart() =>
        storyboard ? session.selectGlobalFrame(0) : session.selectFrameIndex(0);
    void drag() =>
        storyboard ? session.scrubGlobalFrame(400) : session.scrubFrameIndex(6);

    toStart();
    if (!storyboard) {
      session.createDrawingAtCurrentFrame();
    }
    await tester.pumpAndSettle();
    final openStart = _bar(tester);
    drag();
    await tester.pumpAndSettle();
    final openDragged = _bar(tester);
    expect(openDragged, isNot(openStart), reason: 'the drag moves something');

    await _collapse(tester);
    expect(_isCollapsed(tester), isTrue, reason: 'really folded');
    toStart();
    await tester.pumpAndSettle();
    expect(
      _bar(tester),
      openStart,
      reason:
          'folded at the start frame must read like open at it — button '
          'by button, so a single frozen one names itself',
    );

    drag();
    await tester.pumpAndSettle();
    expect(
      _bar(tester),
      openDragged,
      reason:
          'and folded MID-DRAG must read like open mid-drag. This is the '
          'pair that says the fold is innocent: if the two ever diverge, '
          'the collapse machinery has started eating a signal',
    );
  }

  testWidgets(
    'the folded TIMELINE bar reads exactly like the open one',
    (tester) => foldReadsLikeOpen(tester, storyboard: false),
  );

  testWidgets(
    'the folded STORYBOARD bar reads exactly like the open one',
    (tester) => foldReadsLikeOpen(tester, storyboard: true),
  );
}
