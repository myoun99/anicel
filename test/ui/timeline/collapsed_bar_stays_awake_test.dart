import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/panel_collapsed_scope.dart';

/// 🚨T16ⓒ — 유저 mandate: 「t16잔여 맞음. **비활성화인채 얼어있음. 이런거 좀
/// 없게하자.**」
///
/// The 「이런거」 is this round's number-one recurring shape, stated once:
/// **the value moved and the drawing side says nothing changed** (㉞·⑩·⑰·ε
/// three times·T16·T17). So the mandate is not "fix this button" — it is
/// "make the class stop happening", and a class is only closed by a contract
/// that walks ALL of it.
///
/// That is what this file is. Every keyed button on the timeline's command
/// bar gets folded away and then handed an edit its enablement depends on,
/// and each one has to answer. Four separate caches sit between the session
/// and those buttons —
///
/// 1. `EditorPanelTabs._contentCache[tab.id]`, whose own comment says 「the
///    cached widget instance never changes」
/// 2. `_SeekGatedTimelineToolbar._cachedActions`, dropped only by a committed
///    seek, a host rebuild, or a language switch
/// 3. `_StaticCommandGroup._cached`, dropped only when `rebuildKey` differs,
///    which is checked in `didUpdateWidget` and so needs a parent rebuild
/// 4. `StaticRaster`, the pixel bake
///
/// — and the EDIT below is deliberately not a seek, because a seek is the one
/// signal (2) already listens for. A button that only wakes when the playhead
/// moves passes a seek test and fails a person.
///
/// ⚠️This measures STATE, which is what a widget test can see. The user
/// watches COLOUR. `past_cut_end_paints_test` learned the same lesson from
/// the other end: a green state test does not clear the pixels, and if a
/// report survives this file the remaining suspect is the bake at (4).
EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

/// Whether the panel is folded, asked of the app's own authority.
///
/// ⚠️Not "is the grid offstage" — that was this probe's first guess and it
/// answered false in the folded state, which reads exactly like the collapse
/// never happened. `PanelCollapsedScope` is the seam the panel itself reads.
bool _isCollapsed(WidgetTester tester) => tester
    .widgetList<PanelCollapsedScope>(find.byType(PanelCollapsedScope))
    .any((scope) => scope.collapsed);

/// ⚠️These are plain [TextButton]s and [IconButton]s carrying the key
/// themselves, not one shared type — looking for the wrong one produced a
/// "Bad state: No element" that reads exactly like a failing app.
bool? _enabledOf(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey<String>(key));
  if (finder.evaluate().isEmpty) {
    return null;
  }
  final widget = finder.evaluate().first.widget;
  return switch (widget) {
    TextButton(:final onPressed) => onPressed != null,
    IconButton(:final onPressed) => onPressed != null,
    InkWell(:final onTap) => onTap != null,
    _ => null,
  };
}

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -420),
  );
  await tester.pumpAndSettle();
}

Future<void> _collapse(WidgetTester tester) async {
  // The app's own affordance. ⚠️Dragging the splitter down does NOT collapse
  // — the region shrinks to its floor and stays expanded.
  await tester.tap(
    find.byKey(const ValueKey<String>('floating-bottom-collapse')),
  );
  await tester.pumpAndSettle();
}

/// Every keyed button on the bar. Enumerated rather than sampled, because
/// the mandate is about the CLASS: a new button that forgets to subscribe
/// should fail here on the day it is added.
const _barButtons = <String>[
  'new-frame-button',
  'blank-exposure-button',
  'toggle-mark-button',
  'shared-copy-button',
  'shared-paste-linked-button',
  'shared-paste-independent-button',
  'shared-edit-button',
  'shared-delete-button',
  'set-comma-1-button',
  'set-comma-n-button',
];

void main() {
  testWidgets('the folded bar answers an edit, and so does the open one', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();

    // ── Expanded: the control. Whatever the fold does, it has to be
    // measured against what NOT folding does with the same edit.
    final openBefore = {
      for (final key in _barButtons) key: _enabledOf(tester, key),
    };
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final openAfter = {
      for (final key in _barButtons) key: _enabledOf(tester, key),
    };
    expect(
      openAfter,
      isNot(openBefore),
      reason: 'the control is only a control if the edit moves SOMETHING',
    );

    // ── Folded: the same edit, undone and redone.
    await _collapse(tester);
    expect(_isCollapsed(tester), isTrue, reason: 'really folded');

    session.deleteCellAtCurrentFrame();
    await tester.pumpAndSettle();
    final foldedEmpty = {
      for (final key in _barButtons) key: _enabledOf(tester, key),
    };
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final foldedDrawn = {
      for (final key in _barButtons) key: _enabledOf(tester, key),
    };

    expect(
      foldedEmpty,
      openBefore,
      reason: 'folded and empty must read like open and empty — button by '
          'button, so a single frozen one names itself',
    );
    expect(
      foldedDrawn,
      openAfter,
      reason: 'and folded WITH a drawing must read like open with one. A '
          'button that answers only while the panel is unfolded is the '
          'freeze this contract exists to catch',
    );
  });

  testWidgets('a committed SEEK is not what wakes them', (tester) async {
    // The toolbar's cache listens for committed seeks, so a test that moves
    // the playhead proves nothing about an edit — and an edit is what the
    // user was doing. This pins that the two paths agree, so the seek
    // subscription can never quietly become the only one that works.
    await _pump(tester);
    final session = _sessionOf(tester);
    await _collapse(tester);

    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    final afterEdit = {
      for (final key in _barButtons) key: _enabledOf(tester, key),
    };

    // Nudge the playhead away and back: the seek path re-derives everything.
    session.selectFrameIndex(1);
    await tester.pumpAndSettle();
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    final afterSeek = {
      for (final key in _barButtons) key: _enabledOf(tester, key),
    };

    expect(
      afterEdit,
      afterSeek,
      reason: 'if these differ, the bar was showing the last SEEK\'s answer '
          'and the edit had gone unnoticed until the playhead moved',
    );
  });
}
