import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindIcon;

/// ⑤⑥ 유저 2026-08-12 — the Add Layer entrance.
void main() {
  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-menu')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the ＋ makes an ANIMATION layer, whatever is selected', (
    tester,
  ) async {
    // ⑥ 유저: 「레이어 +버튼, 선택된 레이어 기준이아니라 애니메이션레이어 생성.」
    final session = await pump(tester);
    session.addLayerOfKind(LayerKind.se);
    await tester.pumpAndSettle();
    expect(session.activeLayer!.kind, LayerKind.se);

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-button')),
    );
    await tester.pumpAndSettle();

    expect(
      session.activeLayer!.kind,
      LayerKind.animation,
      reason: 'a button that made a different kind depending on where you '
          'stood could not be pressed without first looking',
    );
  });

  testWidgets('「같은 종류로」 is GONE from the menu', (tester) async {
    // 유저: 「레이어 +에 있는 현재 선택한 레이어로 생성 삭제. 필요없음. 묻지마.」
    await pump(tester);
    await openAddMenu(tester);
    expect(
      find.byKey(const ValueKey<String>('add-layer-kind-same')),
      findsNothing,
    );
  });

  testWidgets('EVERY kind entry wears its own icon, from the ONE table', (
    tester,
  ) async {
    // 유저: 「레이어 생성, 아이콘이 있고없고 그러는데, 다 아이콘 앞에 붙임」.
    // Three carried a hand-picked glyph and the rest carried none, which is
    // how the menu came to disagree with the rail it creates rows for.
    await pump(tester);
    await openAddMenu(tester);

    for (final (key, kind) in const [
      ('animation', LayerKind.animation),
      ('storyboard', LayerKind.storyboard),
      ('image', LayerKind.image),
      ('text', LayerKind.text),
      ('se', LayerKind.se),
      ('instruction', LayerKind.instruction),
      ('adjustment', LayerKind.adjustment),
      ('folder', LayerKind.folder),
    ]) {
      final entry = find.byKey(ValueKey<String>('add-layer-kind-$key'));
      expect(entry, findsOneWidget, reason: '$key must be offered');
      expect(
        find.descendant(of: entry, matching: find.byIcon(layerKindIcon(kind))),
        findsOneWidget,
        reason: '$key must wear the same glyph its ROW wears',
      );
    }
  });
}
