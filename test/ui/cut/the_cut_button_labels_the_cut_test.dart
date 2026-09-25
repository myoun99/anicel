import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️유저 2026-09-26: 「색라벨 정하는건 블록마다 다른거니까 컷버튼안에
/// 있다던가」 · 「정한거 그대로 사용」 — the cut button carries THE label list
/// the rail chip opens (stages, then each stage's corrections), one level
/// deeper.
void main() {
  testWidgets('the cut button\'s 색 라벨 opens the label list — its stages, '
      'then a stage\'s corrections — and a pick labels the cut', (
    tester,
  ) async {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: CutCommandGroup(session: session)),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('cut-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('cut-mark-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('layer-mark-option-none')),
      findsOneWidget,
      reason: 'the rail chip\'s own list, first row 라벨 없음',
    );

    await tester.tap(find.byKey(const ValueKey<String>('layer-mark-stage-key')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-mark-option-key')),
    );
    await tester.pumpAndSettle();

    expect(
      session.activeCutOrNull!.metadata.mark,
      const LayerMark(process: LayerProcess.key),
    );
    expect(
      find.byKey(const ValueKey<String>('cut-mark-button')),
      findsNothing,
      reason: 'the pick closes every level',
    );
  });
}
