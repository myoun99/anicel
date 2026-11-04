import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;

import '../helpers/home_page_probes.dart';
import '../helpers/room_for_the_pills.dart';
import '../helpers/wait_window.dart' show windowBehindTheTap;
import 'timeline/timeline_cell_probe.dart' show timelineCellGlobalRect;

/// 🗣️F-551 (유저 2026-11-04): 「연산 필요한거? 무거운거? 들은 왠만하면 다
/// 로딩창띄우도록. 색변환이나 색삭제나 그런거.」 · Q1 「전부 늘 띄운다」.
///
/// The shared pill's presses — the ones a hand takes many times — each
/// stand behind the app's one wait window under their own name, every
/// time, and a step that did is undone and redone behind the same. The
/// colour edit list's rows are pinned beside their verbs
/// (`pixel_verbs_reach_the_ui_test`); the doors no press here reaches are
/// read from source (`every_heavy_door_stands_behind_the_wait_window_test`).
void main() {
  /// The app on a bare project whose first row has one drawing, standing
  /// on it.
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(appWindowWithRoomForItsPills);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  testWidgets('the pill\'s copy, independent paste and duplicate each stand '
      'behind the window under their own name — and the paste\'s undo and '
      'redo behind the paste\'s', (tester) async {
    final session = await pump(tester);
    final history = session.historyManager;

    final copied = await windowBehindTheTap(
      tester,
      const ValueKey<String>('shared-copy-button'),
    );
    expect(
      (copied?.windowKey, copied?.title),
      (
        const ValueKey<String>('work-progress-dialog'),
        editorActionLabel(EditorActionIds.editCopy),
      ),
    );

    // Onto the next cell — its far half, past the drawn run's end handle
    // (`home_frame_and_clipboard_test`'s linked paste).
    final cell = timelineCellGlobalRect(tester, 'default-layer-1', 1);
    await tester.tapAt(Offset(cell.left + cell.width * 3 / 4, cell.center.dy));
    await tester.pumpAndSettle();

    final before = history.undoCount;
    final pasted = await windowBehindTheTap(
      tester,
      const ValueKey<String>('shared-paste-independent-button'),
    );
    expect(
      (pasted?.windowKey, pasted?.title),
      (
        const ValueKey<String>('paste-progress-dialog'),
        editorActionLabel(EditorActionIds.editPasteIndependent),
      ),
    );
    expect(history.undoCount, before + 1, reason: 'the paste was taken');

    final undone = await windowBehindTheTap(
      tester,
      const ValueKey<String>('undo-button'),
    );
    expect(undone?.title, pasted?.title);
    expect(history.undoCount, before);

    final redone = await windowBehindTheTap(
      tester,
      const ValueKey<String>('redo-button'),
    );
    expect(redone?.title, pasted?.title);
    expect(history.undoCount, before + 1);

    final duplicated = await windowBehindTheTap(
      tester,
      const ValueKey<String>('shared-duplicate-button'),
    );
    expect(
      (duplicated?.windowKey, duplicated?.title),
      (
        const ValueKey<String>('duplicate-progress-dialog'),
        editorActionLabel(EditorActionIds.editDuplicate),
      ),
    );
    expect(history.undoCount, before + 2, reason: 'the duplicate was taken');
  });
}
