import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/panels/tool_size_preset_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// **I-2 — the tool's sizes, as buttons.**
///
/// 유저 2026-08-24: 「클튜처럼 툴 사이즈 패널 만들고싶음. **프리셋으로서 툴
/// 사이즈.**」 · 유저 결정 2026-08-25: 「**새 패널로 만든다 — 이번은 예외**」.
///
/// ⛔THIS FILE WAS REWRITTEN, NOT PATCHED. Every test in it used to assert
/// that the rack IS `brushSizeSnaps`, on the reasoning that two lists of one
/// thing drift. 유저 2026-08-29 threw the premise out — 「**목록은 하나여야
/// 한다는게 대체 무슨소리지? 이해안가는데** … 전혀 신경안써도되는데. 그
/// 사이즈를 변경하는 **연결된 패널일뿐임**」 — so the assertions were not
/// wrong about the code, they were wrong about the product. A snap is where
/// a drag catches (sparse to be usable); a preset is what you point at
/// (dense to be useful).
///
/// ↩️F-391 (유저 2026-10-17): 「브러시 크기 스냅은 … 툴 사이즈 패널을
/// 바탕으로」 — the drag catches on THIS rack now and the settings' ladder
/// is gone, so 「sparse to be usable」 above was a guess. The test that
/// pinned the two lists apart went with the ladder; the drag's own pin is
/// `a_snapped_size_drag_lands_on_the_rack_test`.
void main() {
  Future<List<double>> pumpPanel(WidgetTester tester, {double size = 8}) async {
    final picked = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: ToolSizePresetPanel(size: size, onSizeSelected: picked.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  Finder cell(double value) => find.byKey(
    ValueKey<String>('tool-size-preset-${ToolSizePresetPanel.label(value)}'),
  );

  testWidgets('the rack is the dense list off the card — the sizes a pen '
      'actually lives at', (tester) async {
    final picked = await pumpPanel(tester);

    // 0.7 is on the reference the user gave (「무조건 스샷 참고」). ↩️This
    // said it could never be a snap; since F-391 the drag catches on it.
    expect(cell(0.7), findsOneWidget, reason: 'from the card\'s screenshot');
    expect(cell(1700), findsOneWidget, reason: 'and so is the coarse end');

    await tester.tap(cell(0.7));
    await tester.pumpAndSettle();
    expect(
      picked,
      [0.7],
      reason:
          'the press writes the value verbatim — 「마치 입력을 '
          '대신해주는것뿐」, so it must not re-snap to 1',
    );
  });

  testWidgets('the size is DRAWN, and the dot grows with it', (tester) async {
    await pumpPanel(tester);

    double dotOf(double value) => tester
        .getSize(
          find
              .descendant(of: cell(value), matching: find.byType(Container))
              .first,
        )
        .width;

    // 🚨What makes it a rack rather than a list of numbers: you pick by how
    // big the blob looks. A cell that printed only digits would be the size
    // field with extra steps.
    expect(dotOf(4), greaterThan(dotOf(1)));
    expect(dotOf(20), greaterThan(dotOf(4)));

    // ⛔AND IT CAPS. Past the cell there is nothing a 38px square can show,
    // so the big sizes draw the same circle and the number tells them
    // apart — the reference does this too.
    expect(
      dotOf(2000),
      dotOf(1000),
      reason: 'both are far past the cell, so both fill it',
    );
    expect(
      dotOf(2000),
      lessThan(38),
      reason: 'a 2000px dot must not try to draw 2000px',
    );
  });

  testWidgets('the size the tool is on reads as selected — COLOUR ONLY, '
      'and nothing is filled in behind it', (tester) async {
    await pumpPanel(tester, size: 8);

    Color inkOf(double value) => tester
        .widget<Text>(
          find.descendant(of: cell(value), matching: find.byType(Text)),
        )
        .style!
        .color!;

    expect(
      inkOf(8),
      AppColors.accent,
      reason: 'the app rule is an accent FOREGROUND',
    );
    expect(inkOf(4), isNot(AppColors.accent));

    // 🚨THE BUG THIS FILE MISSED FOR A ROUND. The cell used to paint
    // `primaryContainer` BEHIND the selected chip — a filled chip, which
    // 「선택 표시는 색상만」 forbids outright — and the source scan that
    // guards the rule looks for `backgroundColor:`, so a
    // `Material(color: selected ? …)` walked straight past it. The old test
    // here asserted only that the two colours DIFFERED, which a filled chip
    // satisfies perfectly.
    for (final value in [8.0, 4.0]) {
      expect(
        tester
            .widget<Material>(
              find.descendant(of: cell(value), matching: find.byType(Material)),
            )
            .color,
        Colors.transparent,
        reason: 'no plate behind the selected cell, and none behind the rest',
      );
    }
  });
}
