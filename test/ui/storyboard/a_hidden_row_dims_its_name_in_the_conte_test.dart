import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

import '../../helpers/conte_track_fixture.dart';

/// 🗣️I-62 (유저 2026-10-03): 「레이어 비지블off시 색라벨 비활성화색?으로 하는데,
/// 추가로 레이어 이름도 비활성화색? 반투명? 어둡게」 — on the conte, whose S
/// rows and transition row wear the rail's own eye and label.
///
/// The timeline's and the x-sheet's half is
/// `timeline/a_hidden_folder_dims_what_it_hides_test`.
void main() {
  testWidgets('a row turned off by its eye wears its name at the rail\'s '
      'off, and on again its own ink — the S row and the transition row, '
      'each by its own eye', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final transition = session.activeTrack.transitionLayer;

    double inkOf(String labelKey, String name) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey<String>(labelKey)),
            matching: find.text(name),
          ),
        )
        .style!
        .color!
        .a;
    double sName() =>
        inkOf('storyboard-se-label-${conteTrackId.value}-1', 'S1');
    double transitionName() => inkOf(
      'storyboard-transition-label-${conteTrackId.value}',
      transition.name,
    );
    Future<void> pressEye(String layerId) async {
      await tester.tap(
        find.byKey(ValueKey<String>('storyboard-layer-visibility-$layerId')),
      );
      await tester.pumpAndSettle();
    }

    expect(sName(), 1, reason: '⛔전제: lit at rest');
    expect(transitionName(), 1, reason: '⛔전제: lit at rest');

    await pressEye(conteSeId.value);
    expect(
      session.activeTrack.seLayers.single.isVisible,
      isFalse,
      reason: '⛔전제: the eye turned the row off',
    );
    expect(sName(), closeTo(AppColors.offAlpha, 0.001));
    expect(transitionName(), 1, reason: 'each by its own eye');

    await pressEye(conteSeId.value);
    expect(sName(), 1, reason: 'on again, its own ink');

    await pressEye(transition.id.value);
    expect(session.activeTrack.transitionLayer.isVisible, isFalse);
    expect(transitionName(), closeTo(AppColors.offAlpha, 0.001));
    expect(sName(), 1);
  });
}
