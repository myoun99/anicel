import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 **다른 레이어의 버튼
/// 누르면 작동안함.** 불투명도 슬라이더는 **한번 움직이고 드래그가 풀림.**
/// 액티브 레이어만 작용같은 규칙 두지말고 **자유롭게 가능하도록.** 레이어에
/// 있는 **모든 버튼이나 편집이** 그럼」
///
/// ★The scope is 「모든 버튼」, so this is a law rather than one button —
/// a rail row's controls act on the row they are drawn on, whichever row
/// the drawing target happens to be.
void main() {
  Future<EditorSessionManager> pumpRail(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.addLayerOfKind(LayerKind.animation);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('a NON-active layer\'s visibility button works on the first '
      'press', (tester) async {
    final session = await pumpRail(tester);

    // The row that is NOT the drawing target.
    final other = session.layers
        .map((layer) => layer.id)
        .firstWhere((id) => id != session.activeLayerId);
    final before = session.layers.firstWhere((l) => l.id == other).isVisible;

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-layer-visibility-$other')),
    );
    await tester.pumpAndSettle();

    expect(
      session.layers.firstWhere((l) => l.id == other).isVisible,
      !before,
      reason:
          'the press landed on that row\'s button and did nothing — 「액티브 '
          '레이어만 작용같은 규칙 두지말고」',
    );
  });

  testWidgets('and it did not need to steal the drawing target to do it', (
    tester,
  ) async {
    final session = await pumpRail(tester);
    final active = session.activeLayerId;
    final other = session.layers
        .map((layer) => layer.id)
        .firstWhere((id) => id != active);

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-layer-visibility-$other')),
    );
    await tester.pumpAndSettle();

    // ⚠️Pinned deliberately. If the button only works BECAUSE the press
    // first made that row active, the row rebuilds under the gesture — and
    // that is the other half of the report: 「슬라이더는 한번 움직이고
    // 드래그가 풀림」.
    expect(
      session.activeLayerId,
      active,
      reason: 'pressing a row control moved the drawing target',
    );
  });
}
