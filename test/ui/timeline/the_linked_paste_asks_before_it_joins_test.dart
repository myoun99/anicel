import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/home_page_probes.dart';

/// 🗣️I-71 (유저 2026-10-05): 「다른레이어에 붙여넣을때 … 링크붙여넣기
/// 가능하게. 동작은 말한대로 이름 유지되는붙여넣기. 해당행동시 기존에 이름
/// 존재한다면 링크시킬지 묻는것도 띄우고」 — the PRESS, on the pill.
///
/// The law of what lands is pinned a layer down
/// (`session/a_linked_paste_keeps_its_names_across_rows_test`); this says the
/// button asks before it joins, once, in the paste's own words — and that
/// Cancel writes nothing.
void main() {
  const window = ValueKey<String>('frame-name-conflict-dialog');
  const paste = ValueKey<String>('shared-paste-linked-button');

  Layer rowOf(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  /// The app with two cel rows: [from] holding X at 0 — copied — and [to],
  /// stood on at frame 4, holding [held] at 0: named X too when
  /// [toHoldsTheName], unnamed otherwise.
  Future<({EditorSessionManager s, LayerId to, FrameId held})> copiedAcross(
    WidgetTester tester, {
    required bool toHoldsTheName,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final s = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final from = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    expect(s.frameVerbs.renameSelectedFrame('X'), isNull, reason: '⛔전제');
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final to = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    if (toHoldsTheName) {
      expect(s.frameVerbs.renameSelectedFrame('X'), isNull, reason: '⛔전제');
    }
    final held = rowOf(s, to).timeline[0]!.frameId!;
    s.selectLayer(from);
    s.selectFrameIndex(0);
    s.copyFrameAtCurrentFrame();
    s.selectLayer(to);
    s.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(rowOf(s, to).timeline[4], isNull, reason: '⛔전제: an empty cell');
    return (s: s, to: to, held: held);
  }

  testWidgets('a name the row holds: the window asks once, in the paste\'s '
      'words — Cancel writes nothing, Link shows the row\'s own drawing', (
    tester,
  ) async {
    final (:s, :to, :held) = await copiedAcross(tester, toHoldsTheName: true);
    final steps = s.historyManager.undoCount;

    await tapToolbarButton(tester, paste);
    expect(find.byKey(window), findsOneWidget);
    expect(
      find.text(AppText.strings.linkedPasteConflictBody),
      findsOneWidget,
      reason: 'the listed frames are the row\'s own — the rename\'s sentence '
          'would say THEIR drawings are discarded',
    );
    expect(rowOf(s, to).timeline[4], isNull, reason: 'asked first');

    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(window), findsNothing);
    expect(rowOf(s, to).timeline[4], isNull, reason: 'Cancel writes nothing');
    expect(s.historyManager.undoCount, steps);

    await tapToolbarButton(tester, paste);
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(window), findsNothing);
    expect(rowOf(s, to).timeline[4]?.frameId, held);
    expect(rowOf(s, to).frames, hasLength(1), reason: 'nothing born');
    expect(s.historyManager.undoCount, steps + 1);
  });

  testWidgets('a name the row does not hold: it lands at once, with no '
      'window', (tester) async {
    final (:s, :to, :held) = await copiedAcross(tester, toHoldsTheName: false);

    await tapToolbarButton(tester, paste);

    expect(find.byKey(window), findsNothing);
    final pasted = rowOf(s, to).timeline[4]?.frameId;
    expect(pasted, isNotNull);
    expect(pasted, isNot(held));
    expect(rowOf(s, to).frameById(pasted!)?.name, 'X');
  });
}
