import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
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
/// 로딩창띄우도록」 · F-566 (유저 2026-11-05): 「추가로 블록 복사/붙여넣기/
/// 링크붙여넣기등도 마찬가지. 단독이면 표시안하고 복수선택 동작이면 띄움.
/// 공용알약같은거.」
///
/// The shared pill's presses — the ones a hand takes many times — each
/// stand behind the app's one wait window under their own name where they
/// land on more than one drawing, and a step that did is undone and redone
/// behind the same (F-566-Q1 「처음 실행을 따른다」); on one drawing each is
/// taken at once, and so are its undo and redo. The colour edit list's rows
/// are pinned beside their verbs (`pixel_verbs_reach_the_ui_test`); the
/// doors no press here reaches are read from source
/// (`every_heavy_door_stands_behind_the_wait_window_test`).
void main() {
  const copy = ValueKey<String>('shared-copy-button');
  const pasteIndependent = ValueKey<String>('shared-paste-independent-button');
  const pasteLinked = ValueKey<String>('shared-paste-linked-button');
  const duplicate = ValueKey<String>('shared-duplicate-button');
  const undo = ValueKey<String>('undo-button');
  const redo = ValueKey<String>('redo-button');

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

  /// Onto [cell] of the first row — its far half, past a drawn run's end
  /// handle (`home_frame_and_clipboard_test`'s linked paste).
  Future<void> standOn(WidgetTester tester, int cell) async {
    final rect = timelineCellGlobalRect(tester, 'default-layer-1', cell);
    await tester.tapAt(Offset(rect.left + rect.width * 3 / 4, rect.center.dy));
    await tester.pumpAndSettle();
  }

  /// The first row's two drawings (cells 0 and 1) under a band.
  Future<void> bandTwoDrawings(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await createSecondAuthoredFrame(tester);
    final row = session.activeLayerId!;
    expect(
      session.layers.firstWhere((layer) => layer.id == row).frames,
      hasLength(2),
      reason: '⛔전제: two drawings',
    );
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: row,
      startIndex: 0,
      endIndexExclusive: 2,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one drawing: the pill\'s copy, independent paste and '
      'duplicate are each taken at once — 「단독이면 표시안하고」 — and the '
      'paste\'s undo and redo', (tester) async {
    final session = await pump(tester);
    final history = session.historyManager;
    final start = history.undoCount;

    expect(await windowBehindTheTap(tester, copy), isNull);

    // The row stood on holds its one drawing.
    expect(await windowBehindTheTap(tester, duplicate), isNull);
    expect(history.undoCount, start + 1, reason: 'the duplicate was taken');

    await standOn(tester, 1);
    final before = history.undoCount;
    expect(await windowBehindTheTap(tester, pasteIndependent), isNull);
    expect(history.undoCount, before + 1, reason: 'the copy was pasted');

    expect(await windowBehindTheTap(tester, undo), isNull);
    expect(history.undoCount, before);
    expect(await windowBehindTheTap(tester, redo), isNull);
    expect(history.undoCount, before + 1);
  });

  testWidgets('two drawings under a band: the copy and the independent '
      'paste stand behind the window under their own name — 「복수선택 '
      '동작이면 띄움」 — and so do the paste\'s undo and redo', (tester) async {
    final session = await pump(tester);
    final history = session.historyManager;
    await bandTwoDrawings(tester, session);

    final copied = await windowBehindTheTap(tester, copy);
    expect(
      (copied?.windowKey, copied?.title),
      (
        const ValueKey<String>('work-progress-dialog'),
        editorActionLabel(EditorActionIds.editCopy),
      ),
    );

    session.frameRangeSelection.value = null;
    await standOn(tester, 3);
    final before = history.undoCount;
    final pasted = await windowBehindTheTap(tester, pasteIndependent);
    expect(
      (pasted?.windowKey, pasted?.title),
      (
        const ValueKey<String>('paste-progress-dialog'),
        editorActionLabel(EditorActionIds.editPasteIndependent),
      ),
    );
    expect(history.undoCount, before + 1, reason: 'the paste was taken');

    final undone = await windowBehindTheTap(tester, undo);
    expect(undone?.title, pasted?.title);
    expect(history.undoCount, before);

    final redone = await windowBehindTheTap(tester, redo);
    expect(redone?.title, pasted?.title);
    expect(history.undoCount, before + 1);

    final duplicated = await windowBehindTheTap(tester, duplicate);
    expect(
      (duplicated?.windowKey, duplicated?.title),
      (
        const ValueKey<String>('duplicate-progress-dialog'),
        editorActionLabel(EditorActionIds.editDuplicate),
      ),
      reason: 'the row stood on holds its drawings',
    );
    expect(history.undoCount, before + 2, reason: 'the duplicate was taken');
  });

  // 링크 붙여넣기 puts up its own window (its question comes between two of
  // them), on each of its branches.
  testWidgets('the pill\'s linked paste: a cel in hand is laid at once; two '
      'cels, and rows holding two drawings, behind the window under its own '
      'name', (tester) async {
    final session = await pump(tester);
    final pasting = (
      const ValueKey<String>('paste-progress-dialog'),
      editorActionLabel(EditorActionIds.editPasteLinked),
    );

    await windowBehindTheTap(tester, copy);
    await standOn(tester, 1);
    expect(await windowBehindTheTap(tester, pasteLinked), isNull);

    await bandTwoDrawings(tester, session);
    await windowBehindTheTap(tester, copy);
    session.frameRangeSelection.value = null;
    await standOn(tester, 3);
    final cels = await windowBehindTheTap(tester, pasteLinked);
    expect((cels?.windowKey, cels?.title), pasting);

    session.rowSelectionVerbs.beginRowSelection(
      LayerRowAddress(session.activeLayerId!),
    );
    await tester.pumpAndSettle();
    await windowBehindTheTap(tester, copy);
    expect(
      session.layerClipboard.hasLayerClipboard,
      isTrue,
      reason: '⛔전제: rows in hand',
    );
    final rows = await windowBehindTheTap(tester, pasteLinked);
    expect((rows?.windowKey, rows?.title), pasting);
  });
}
