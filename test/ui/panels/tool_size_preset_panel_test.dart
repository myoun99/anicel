import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/panels/tool_size_preset_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/text_finders.dart';

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
///
/// 🗣️I-170 (유저 2026-11-13): 「도구 브러시크기 프리셋패널, 슬슬 추가/삭제버튼
/// 추가. 추가버튼 작동시 숫자입력 공용창? 열리고 입력한게 중복된거면 거부.
/// 존재한다는 메시지창과함께. 정상적이면 프리셋에 추가. 삭제는 선택(강조색
/// 되있는)되있는 크기를 삭제하는버튼」 — the rack is handed in, and handed
/// back changed.
void main() {
  /// The panel over [rack] with the tool at [size]: the sizes it was
  /// pressed for, and each rack it handed back.
  Future<({List<double> picked, List<List<double>> kept})> pumpPanel(
    WidgetTester tester, {
    double size = 8,
    List<double> rack = AppInputSettings.defaultToolSizes,
  }) async {
    final picked = <double>[];
    final kept = <List<double>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: ToolSizePresetPanel(
              size: size,
              onSizeSelected: picked.add,
              presets: rack,
              onPresetsChanged: kept.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (picked: picked, kept: kept);
  }

  Finder cell(double value) => find.byKey(
    ValueKey<String>('tool-size-preset-${ToolSizePresetPanel.label(value)}'),
  );
  final add = find.byKey(const ValueKey<String>(ToolSizePresetPanel.addKey));
  final delete = find.byKey(
    const ValueKey<String>(ToolSizePresetPanel.deleteKey),
  );
  final notice = find.byKey(const ValueKey<String>('app-notice-close'));

  /// The ＋ pressed, [keys] pressed on the pad it opens, and its ✓.
  Future<void> addOnThePad(WidgetTester tester, List<String> keys) async {
    await tester.tap(add);
    await tester.pumpAndSettle();
    for (final key in [...keys, 'enter']) {
      await tester.tap(
        find.byKey(
          ValueKey<String>('${ToolSizePresetPanel.addKey}-pad-$key'),
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the rack is the dense list off the card — the sizes a pen '
      'actually lives at', (tester) async {
    final (:picked, kept: _) = await pumpPanel(tester);

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
          find.descendant(of: cell(value), matching: find.anyText()),
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

  group('🗣️I-170: the rack is the user\'s to edit', () {
    testWidgets('the cells are the rack it is handed, in its order', (
      tester,
    ) async {
      await pumpPanel(tester, rack: const [3, 9, 40]);

      expect(cell(3), findsOneWidget);
      expect(cell(9), findsOneWidget);
      expect(cell(40), findsOneWidget);
      expect(cell(8), findsNothing, reason: 'not on this rack');
      expect(
        tester.getTopLeft(cell(3)).dx,
        lessThan(tester.getTopLeft(cell(9)).dx),
      );
    });

    testWidgets('the ＋ and the delete stand whatever the rack holds — the '
        'delete grey while no cell is lit', (tester) async {
      await pumpPanel(tester, size: 8);
      expect(tester.appIconButton(add).onPressed, isNotNull);
      expect(tester.appIconButton(delete).onPressed, isNotNull);
      expect(
        tester.appIconButton(delete).iconColor,
        AppColors.danger,
        reason: 'a delete that can be pressed is the red every delete is',
      );

      // 9 is on no cell: nothing is lit, and there is nothing to take off.
      await pumpPanel(tester, size: 9);
      expect(tester.appIconButton(add).onPressed, isNotNull);
      expect(delete, findsOneWidget, reason: 'it does not go');
      expect(tester.appIconButton(delete).onPressed, isNull);
      expect(
        tester.appIconButton(delete).iconColor,
        AppColors.glyphDisabled,
        reason: 'and one that cannot wears no red',
      );

      await pumpPanel(tester, rack: const []);
      expect(tester.appIconButton(add).onPressed, isNotNull);
      expect(tester.appIconButton(delete).onPressed, isNull);
    });

    testWidgets('🚨the ＋ opens the number pad on the tool\'s size, and the '
        'number it comes back with is put on the rack where its size '
        'stands', (tester) async {
      final (picked: _, :kept) = await pumpPanel(
        tester,
        size: 8,
        rack: const [3, 8, 40],
      );

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>(
                  '${ToolSizePresetPanel.addKey}-pad-number',
                ),
              ),
            )
            .data,
        '8',
        reason: 'the pad opens on the size in hand',
      );
      // A press away from the pad, off the panel.
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(kept, isEmpty, reason: 'a pad left untouched puts nothing on');

      await addOnThePad(tester, ['1', '2', 'point', '5']);
      expect(kept, [
        [3, 8, 12.5, 40],
      ]);
      expect(notice, findsNothing);
    });

    testWidgets('🚨a size the rack already holds is refused, and the notice '
        'says so', (tester) async {
      final (picked: _, :kept) = await pumpPanel(
        tester,
        size: 3,
        rack: const [3, 8, 40],
      );

      await addOnThePad(tester, ['8']);

      expect(kept, isEmpty, reason: 'the rack is as it was');
      expect(notice, findsOneWidget);
      expect(find.text(AppText.strings.toolSizeAlreadyThere), findsOneWidget);

      await tester.tap(notice);
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(
        find.byKey(
          const ValueKey<String>('${ToolSizePresetPanel.addKey}-pad-number'),
        ),
        findsNothing,
        reason: 'the pad went before the notice came',
      );
    });

    testWidgets('a number past the brush\'s range goes on as the size the '
        'size bar holds it at, and that one is refused twice', (tester) async {
      final (picked: _, :kept) = await pumpPanel(
        tester,
        rack: const [3, 2000],
      );

      await addOnThePad(tester, ['9', '9', '9', '9']);

      expect(kept, isEmpty, reason: '9999 is held at 2000, which is there');
      expect(notice, findsOneWidget);
    });

    testWidgets('🚨the delete takes the lit size off the rack, and only it', (
      tester,
    ) async {
      final (picked: _, :kept) = await pumpPanel(
        tester,
        size: 8,
        rack: const [3, 8, 40],
      );

      await tester.tap(delete);
      await tester.pumpAndSettle();

      expect(kept, [
        [3, 40],
      ]);
    });
  });
}
