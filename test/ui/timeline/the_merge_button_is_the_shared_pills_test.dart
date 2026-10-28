import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/layer_merging.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/app_shortcuts.dart';
import '../../helpers/home_page_probes.dart';
import '../../helpers/wait_window.dart';

/// 🗣️I-78 (유저 2026-10-06): 「병합버튼 … 공용알약에 두는걸 생각중」 — 병합 is
/// the shared pill's button, lit where the press would merge something,
/// and a row of the shortcut list whose key is that button.
///
/// The collaborator is held BY ITS OWN TYPE so the mutation runner names
/// this file as its witness (it picks witnesses by import).
void main() {
  LayerMerging mergingOf(EditorSessionManager s) => s.layerMerging;

  const button = ValueKey<String>('shared-merge-button');
  // U is free on the registry's keys.
  const key = LogicalKeyboardKey.keyU;

  List<LayerId> animationRowsOf(EditorSessionManager s) => [
    for (final layer in s.layers)
      if (layer.kind == LayerKind.animation) layer.id,
  ];

  /// Whether the press has made the two rows one and its window has gone.
  bool merged(EditorSessionManager s) =>
      animationRowsOf(s).length == 1 &&
      find
          .byKey(const ValueKey<String>('layer-merge-progress'))
          .evaluate()
          .isEmpty;

  /// The app over the bare project, with a second drawing row on it and
  /// [selected] of the two selected.
  Future<EditorSessionManager> app(
    WidgetTester tester, {
    int selected = 2,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await useAnicelKeys(tester);
    appShortcuts(tester).setActivators(EditorActionIds.editMerge, const [
      SingleActivator(key),
    ]);
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    TimelineToolbarPanelContext(s).addLayer();
    final rows = animationRowsOf(s);
    expect(rows, hasLength(2), reason: '⛔premise: two animation rows');
    s.rowSelection.value = [
      for (final row in rows.take(selected)) LayerRowAddress(row),
    ];
    await tester.pumpAndSettle();
    return s;
  }

  test('it is one row of the shortcut list, and ships with no key', () {
    final definition = editorActionDefinitions.singleWhere(
      (it) => it.id == EditorActionIds.editMerge,
    );
    expect(definition.defaultActivators, isEmpty);
  });

  testWidgets('one row selected, the button is dim', (tester) async {
    final s = await app(tester, selected: 1);

    expect(mergingOf(s).mergesSelection, isFalse);
    expect(await isActionButtonEnabled(tester, button), isFalse);
  });

  testWidgets('two rows selected, it lights — and its press makes them '
      'one', (tester) async {
    final s = await app(tester);
    final top = animationRowsOf(s).last;
    expect(await isActionButtonEnabled(tester, button), isTrue);

    await tapToolbarButton(tester, button);
    await settleBehindTheWaitWindow(tester, () => merged(s));

    expect(animationRowsOf(s), [top]);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the key is the button: it makes them one too', (tester) async {
    final s = await app(tester);
    final top = animationRowsOf(s).last;

    await tester.sendKeyEvent(key);
    await settleBehindTheWaitWindow(tester, () => merged(s));

    expect(animationRowsOf(s), [top]);
    s.playbackRig.prerenderScheduler.cancel();
  });
}
