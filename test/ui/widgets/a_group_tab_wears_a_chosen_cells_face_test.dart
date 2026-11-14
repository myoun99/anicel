import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/group_tab.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q12 (유저 2026-11-08, 2: 「호버 ·
/// 포커스를 테두리 안쪽 채움의 색으로 그리고, 넷도 채우기 둘로」): a group
/// tab is a chosen cell's face (`chosenCellFace`) — its edge two fills, the
/// primary colour around its fill while chosen, the outline's colour around
/// the ground it stands on while not.
void main() {
  final theme = buildAppTheme();
  final colorScheme = theme.colorScheme;

  Future<RenderObject> pumpTab(
    WidgetTester tester, {
    required bool selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: GroupTab.namedWidth,
              child: GroupTab(
                keyValue: 'tab',
                label: 'Pencils',
                selected: selected,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject(find.byKey(const ValueKey<String>('tab')));
  }

  testWidgets('chosen, its edge is the primary colour around its fill', (
    tester,
  ) async {
    expect(
      await pumpTab(tester, selected: true),
      paints
        ..rsuperellipse(color: colorScheme.primary)
        ..rsuperellipse(color: colorScheme.surfaceContainerHigh),
    );
  });

  testWidgets('not chosen, the outline\'s colour around the ground', (
    tester,
  ) async {
    expect(
      await pumpTab(tester, selected: false),
      paints
        ..rsuperellipse(color: colorScheme.outlineVariant)
        ..rsuperellipse(color: AppColors.surface),
    );
  });
}
