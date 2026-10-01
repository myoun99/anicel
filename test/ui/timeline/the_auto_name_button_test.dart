import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/home_page_probes.dart';

/// 🗣️I-18 (유저): 「타임라인 공용 알약에 새 버튼 신설 … 버튼은 자동 이름
/// 지정이고, 누르면 숫자 편집하는 창 나와서 숫자만 입력가능」 — the button on
/// both panels' shared pill, its window, and the link notice behind it.
void main() {
  const button = ValueKey<String>('shared-auto-name-button');
  const notice = ValueKey<String>('frame-name-conflict-dialog');

  Future<EditorSessionManager> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  /// Drawings named [names], one a cell from 0, on the active row.
  LayerId drawn(EditorSessionManager s, List<String> names) {
    for (var index = 0; index < names.length; index += 1) {
      s.selectFrameIndex(index);
      s.createDrawingAtCurrentFrame();
      expect(s.frameVerbs.renameSelectedFrame(names[index]), isNull);
    }
    return s.activeLayerId!;
  }

  List<String?> reads(EditorSessionManager s, LayerId row, int count) {
    final layer = s.layers.firstWhere((layer) => layer.id == row);
    return [
      for (var index = 0; index < count; index += 1)
        s.frameVerbs.frameNameForLayer(layer, index),
    ];
  }

  /// Types [start] into the open window and applies it.
  Future<void> numberFrom(WidgetTester tester, int start) async {
    await tester.tap(find.byKey(const ValueKey<String>('auto-name-start')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('auto-name-start-input')),
      '$start',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('auto-name-apply-button')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dim over an empty cell, lit over a block; its window opens at '
      '1, and Apply numbers the row from the number given', (tester) async {
    final s = await pumpHome(tester);
    final row = drawn(s, ['1', '2', '3']);
    s.selectFrameIndex(6);
    await tester.pumpAndSettle();
    expect(await isActionButtonEnabled(tester, button), isFalse);

    s.selectFrameIndex(0);
    await tester.pumpAndSettle();
    expect(await isActionButtonEnabled(tester, button), isTrue);

    await tapToolbarButton(tester, button);
    expect(
      find.byKey(const ValueKey<String>('auto-name-dialog')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('auto-name-start')),
        matching: find.text('1'),
      ),
      findsOneWidget,
      reason: '「기본값은 1인상태」',
    );
    await numberFrom(tester, 5);

    expect(reads(s, row, 3), ['5', '6', '7']);
  });

  testWidgets('a name held outside the press: the notice lists both frames, '
      'Cancel writes nothing, Link joins them as ONE step', (tester) async {
    final s = await pumpHome(tester);
    final row = drawn(s, ['1', '2', '3', '4']);
    s.selectFrameIndex(2);
    await tester.pumpAndSettle();
    final entries = s.historyManager.undoCount;

    await tapToolbarButton(tester, button);
    await numberFrom(tester, 1);
    expect(find.byKey(notice), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('app-notice-details-list')),
        matching: find.byType(Text),
      ),
      findsNWidgets(2),
      reason: 'the drawings 3 and 4 a join would discard',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(reads(s, row, 4), ['1', '2', '3', '4']);
    expect(s.historyManager.undoCount, entries, reason: 'no step at all');

    await tapToolbarButton(tester, button);
    await numberFrom(tester, 1);
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
    );
    await tester.pumpAndSettle();
    expect(reads(s, row, 4), ['1', '2', '1', '2']);
    expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
  });

  testWidgets('the storyboard\'s pill carries it too, and numbers the cuts '
      'from the one under the playhead', (tester) async {
    final s = await pumpHome(tester);
    s.cutVerbs.createCut();
    s.cutVerbs.createCut();
    await showStoryboardPanel(tester);
    s.selectGlobalFrame(0);
    s.selectTrackRow(s.selectedTrackId);
    await tester.pumpAndSettle();
    expect(await isActionButtonEnabled(tester, button), isTrue);

    await tapToolbarButton(tester, button);
    await numberFrom(tester, 5);

    final cuts = s.repository.requireProject().tracks.first.cuts;
    expect([for (final cut in cuts) cut.name], ['5', '6', '7']);
  });
}
