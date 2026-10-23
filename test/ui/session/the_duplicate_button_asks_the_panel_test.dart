import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/app_shortcuts.dart';
import '../../helpers/home_page_probes.dart';

/// 🗣️F-455 — 복제 IS THE SHARED PILL'S, AND EACH PANEL PRESSES ITS OWN NOUN.
///
/// 유저 2026-10-23: 「공용알약에 복제 버튼 만들고 레이어랑 컷버튼의
/// 레이어복제/컷복제 삭제. 그리고 복제버튼, 물론 각 규칙 따르고」 — the layer
/// pill's duplicate and the cut pill's became one button: on the timeline it
/// duplicates the rows (the selected ones, else the one you stand on), on the
/// storyboard the cut you stand on (R5q1: cuts are the storyboard's noun).
///
/// The collaborators are held BY THEIR OWN TYPES so the mutation runner names
/// this file as their witness (it picks witnesses by import).
void main() {
  LayerVerbs layerVerbsOf(EditorSessionManager s) => s.layerVerbs;
  CutVerbs cutVerbsOf(EditorSessionManager s) => s.cutVerbs;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  int cutCount(EditorSessionManager s) =>
      s.repository.requireProject().tracks.first.cuts.length;

  List<LayerId> rowsOf(EditorSessionManager s) => [
    for (final layer in s.layers) layer.id,
  ];

  test('the timeline\'s press copies the row you stand on — no cut', () {
    final s = session();
    final panel = TimelineToolbarPanelContext(s);
    final rows = rowsOf(s);
    final cuts = cutCount(s);
    expect(
      layerVerbsOf(s).duplicatableSelectedLayerIds(),
      isEmpty,
      reason: '⛔premise: no row is selected',
    );
    expect(panel.canDuplicate, isTrue);

    panel.duplicatePress!();

    expect(rowsOf(s), hasLength(rows.length + 1));
    expect(cutCount(s), cuts, reason: 'the timeline never reaches for a cut');
    expect(s.activeLayerId, isNot(isIn(rows)), reason: 'standing on the copy');
  });

  test('…and dims on a row that takes no copy beside it — the camera', () {
    final s = session();
    final camera = s.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    s.selectLayer(camera.id);
    final panel = TimelineToolbarPanelContext(s);

    expect(panel.canDuplicate, isFalse);
    expect(panel.duplicatePress, isNull);
  });

  test('the storyboard\'s press copies the cut you stand on — no row', () {
    final s = session();
    final panel = StoryboardToolbarPanelContext(s);
    final rows = rowsOf(s);
    final cuts = cutCount(s);
    final standing = s.activeCutId;
    expect(panel.canDuplicate, isTrue);

    panel.duplicatePress!();

    expect(cutCount(s), cuts + 1);
    expect(s.activeCutId, isNot(standing), reason: 'standing on the copy');
    s.selectCut(standing!);
    expect(rowsOf(s), rows, reason: 'the cut it copied kept its rows');
    expect(
      cutVerbsOf(s).cutIsLinked(standing),
      isFalse,
      reason: 'a copy of its own, not a 겸용컷',
    );
  });

  // 🗣️F-455-Q1 (유저 2026-10-23): 「선택한 컷 전부」 — 「레이어랑 똑같이
  // 선택한 묶음 뒤에 차례로」.
  test('…and with a band of cuts it copies them ALL, as one block right '
      'after the band, in their order — one undo — standing on the last '
      'copy', () {
    final s = session();
    s.cutVerbs
      ..createCut()
      ..createCut();
    List<CutId> order() => [for (final cut in s.activeTrack.cuts) cut.id];
    final before = order();
    expect(before, hasLength(3), reason: '⛔premise');
    int startOf(CutId id) {
      var frame = 0;
      for (final cut in s.activeTrack.cuts) {
        frame += cut.leadingGapFrames;
        if (cut.id == id) {
          return frame;
        }
        frame += cut.duration;
      }
      throw StateError('no cut $id');
    }

    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: startOf(before[0]),
      headGlobalFrame: startOf(before[1]),
    );
    expect(
      s.storyboardRows.storyboardSelectedCutIds,
      before.sublist(0, 2),
      reason: '⛔premise: a band over the first two',
    );
    final names = {for (final cut in s.activeTrack.cuts) cut.id: cut.name};

    StoryboardToolbarPanelContext(s).duplicatePress!();

    final after = order();
    expect(after, hasLength(5));
    expect(after.sublist(0, 2), before.sublist(0, 2));
    expect(after.last, before.last, reason: 'the cut past the band waits');
    expect(
      [for (final id in after.sublist(2, 4)) s.cutById(id)!.name],
      ['${names[before[0]]} Copy', '${names[before[1]]} Copy'],
      reason: 'right after the band, in its order',
    );
    expect(s.activeCutId, after[3], reason: 'on the last copy');

    s.undo();
    expect(order(), before, reason: 'one gesture, one undo');
  });

  group('the button and its key', () {
    const button = ValueKey<String>('shared-duplicate-button');
    const key = LogicalKeyboardKey.keyU;

    Future<EditorSessionManager> app(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: createDefaultProject())),
      );
      await tester.pumpAndSettle();
      // U is free on the registry's keys.
      await useAnicelKeys(tester);
      appShortcuts(tester).setActivators(EditorActionIds.editDuplicate, const [
        SingleActivator(key),
      ]);
      await tester.pumpAndSettle();
      return tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
    }

    test('it is one row of the shortcut list, and ships with no key', () {
      final definition = editorActionDefinitions.singleWhere(
        (it) => it.id == EditorActionIds.editDuplicate,
      );
      expect(definition.defaultActivators, isEmpty);
    });

    testWidgets('the button is on the shared pill and copies the row', (
      tester,
    ) async {
      final s = await app(tester);
      final rows = rowsOf(s).length;
      expect(await isActionButtonEnabled(tester, button), isTrue);

      await tapToolbarButton(tester, button);

      expect(rowsOf(s), hasLength(rows + 1));
    });

    testWidgets('the key is the button of the panel being worked in: the row '
        'on the timeline, the cut on the storyboard', (tester) async {
      final s = await app(tester);
      Future<void> workIn(WorkingPanel panel) async {
        await tester.tap(
          find.byKey(
            ValueKey<String>(switch (panel) {
              WorkingPanel.timeline => 'timeline-mode-timeline-button',
              WorkingPanel.storyboard => 'timeline-mode-storyboard-button',
            }),
          ),
        );
        await tester.pumpAndSettle();
        expect(s.workingPanel, panel, reason: '⛔premise');
      }

      Future<void> pressTheKey() async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      await workIn(WorkingPanel.timeline);
      var rows = rowsOf(s).length;
      var cuts = cutCount(s);
      await pressTheKey();
      expect(rowsOf(s), hasLength(rows + 1));
      expect(cutCount(s), cuts);

      await workIn(WorkingPanel.storyboard);
      rows = rowsOf(s).length;
      cuts = cutCount(s);
      final standing = s.activeCutId!;
      await pressTheKey();
      expect(cutCount(s), cuts + 1);
      s.selectCut(standing);
      await tester.pumpAndSettle();
      expect(rowsOf(s), hasLength(rows), reason: 'and no row was copied');
    });
  });
}
