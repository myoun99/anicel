import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// 🗣️F-551 (유저 2026-11-04): 「연산 필요한거? 무거운거? 들은 왠만하면 다
/// 로딩창띄우도록. 색변환이나 색삭제나 그런거.」.
///
/// Every door that takes a heavy step takes it through the app's one wait
/// window's entrance — which puts the window up where the step lands on
/// more than one block (🗣️F-566, `reachesManyBlocks`), and so its undo and
/// redo stand behind the same (`StepWindows`). The doors a behaviour pin
/// presses are pinned there (`heavy_steps_stand_behind_the_wait_window_test`
/// — the pill's; `pixel_verbs_reach_the_ui_test` — the colour edit list's);
/// these are the rest, read from source — the ones a pin would need a
/// canvas gesture, a dropped file or a dialog to reach, and every row and
/// press beside the pinned ones: a door that took its step at once again
/// would go back to freezing the screen with nothing on it.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Whether [body] takes its step through the window's entrance.
  bool waits(String body) =>
      body.contains('takeBehindTheWaitWindow(') ||
      body.contains('workAheadBehindTheWaitWindow(') ||
      body.contains(RegExp(r'\.standBehind\b'));

  /// [head] read through its parameter list: a named parameter's `{` would
  /// otherwise be taken for the body's.
  RegExp throughItsParameters(String head) =>
      RegExp('${RegExp.escape(head)}[\\s\\S]*?\\}\\)');

  /// [head] where a body follows it: an interface's bare declaration of the
  /// same name (`void pasteLinkedFrame();`) has none, and the first `{`
  /// after it is another member's.
  RegExp whereItsBodyOpens(String head) =>
      RegExp('${RegExp.escape(head)}(?=[^;{]*\\{)');

  for (final (path, head, :named) in [
    ('lib/src/ui/canvas/canvas_selection_layer.dart',
        'void _confirmBehindTheWaitWindow()', named: false),
    ('lib/src/ui/workspace/workspace_tabs.dart',
        'ValueChanged<DrawingGuide>? _guideRasterizer(', named: false),
    ('lib/src/ui/editor_workspace.dart', 'Future<void> _swapReference(',
        named: false),
    ('lib/src/ui/brush/brush_canvas_panel.dart',
        'void pasteCutPieceAtOrigin()', named: false),
    ('lib/src/ui/range_move_asking_first.dart',
        'Future<void> releaseRangeMoveAskingFirst(', named: false),
    ('lib/src/ui/dialogs/link_window.dart', 'Widget build(', named: false),
    ('lib/src/ui/paste_linked_asking_first.dart',
        'Future<void> pasteLinkedAskingFirst(', named: true),
    ('lib/src/ui/timeline/toolbar_panel_context.dart',
        'void Function() _behindTheWaitWindow(', named: true),
    ('lib/src/ui/timeline/toolbar_panel_context.dart',
        'void pasteLinkedFrame()', named: false),
    ('lib/src/ui/timeline/timeline_bar_menus.dart',
        'static void _behindTheWaitWindow(', named: true),
  ]) {
    test('$head — ${path.split('/').last} — behind the window', () {
      final signature =
          named ? throughItsParameters(head) : whereItsBodyOpens(head);
      expect(waits(sourceBodyOf(read(path), signature)), isTrue);
    });
  }

  test('확정 is the window\'s whenever it lands a session', () {
    final applies = sourceBodyOf(
      read('lib/src/ui/canvas/canvas_selection_layer.dart'),
      'VoidCallback? _applyAction()',
    );
    expect(applies, contains('return _confirmBehindTheWaitWindow;'));
    expect(applies, isNot(contains('return _confirmSession;')));
  });

  test('every shared press but the linked paste goes through the window', () {
    final presses = sourceBodyOf(
      read('lib/src/ui/timeline/toolbar_panel_context.dart'),
      'extension ToolbarSharedPresses on ToolbarPanelContext',
    );
    for (final action in [
      'editCut',
      'editCopy',
      'editPasteIndependent',
      'editUnlink',
      'editDuplicate',
    ]) {
      expect(
        RegExp(
          r'_behindTheWaitWindow\(\s*EditorActionIds\.' '$action' r'\b',
        ).hasMatch(presses),
        isTrue,
        reason: action,
      );
    }
  });

  test('every row of the colour edit list runs through the window — the '
      'overwrite verbs\' and the pixel board\'s', () {
    final source = read('lib/src/ui/timeline/timeline_bar_menus.dart');
    expect(
      RegExp(r'onSelected: \(\) => _behindTheWaitWindow\(').allMatches(source),
      hasLength(2),
    );
    expect(source, isNot(contains('onSelected: () => session.pixelVerbs')));
  });
}
