import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/tool_setting_rows.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/app_icon_button_probe.dart';

/// 🗣️I-176 (유저 2026-11-16): 「앞으로 리셋버튼은 값이 바뀌어서 리셋이
/// 작동가능하면? 유효하면 강조색되도록」 — a reset wears its family's accent
/// exactly while it can be pressed ([resetWearsAccent]), and every family
/// that draws a reset asks that one law. Each family is pinned three ways:
/// a live reset lit, an out reset not, and a live button that is no reset
/// not — so a family that lit on "live" alone, or on "reset" alone, fails.
///
/// The flyout row's half stands with the flyout's own tests
/// (`panel_flyout_test`), where its harness opens a list.
void main() {
  Widget harness(Widget child) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  test('the law: lit while it can be pressed, and only a reset', () {
    expect(resetWearsAccent(resets: true, live: true), isTrue);
    expect(resetWearsAccent(resets: true, live: false), isFalse);
    expect(resetWearsAccent(resets: false, live: true), isFalse);
    expect(resetWearsAccent(resets: false, live: false), isFalse);
  });

  testWidgets('an icon button', (tester) async {
    await tester.pumpWidget(
      harness(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              keyValue: 'lit',
              tooltip: '',
              icon: const Icon(Icons.restart_alt),
              onPressed: () {},
              resets: true,
            ),
            const AppIconButton(
              keyValue: 'out',
              tooltip: '',
              icon: Icon(Icons.restart_alt),
              onPressed: null,
              resets: true,
            ),
            AppIconButton(
              keyValue: 'plain',
              tooltip: '',
              icon: const Icon(Icons.restart_alt),
              onPressed: () {},
            ),
            AppIconButton(
              keyValue: 'word',
              tooltip: '',
              icon: const Text('1:1'),
              onPressed: () {},
              resets: true,
            ),
          ],
        ),
      ),
    );
    Color? inkOf(String key) =>
        tester.glyphInkOf(find.byKey(ValueKey<String>(key)));

    expect(inkOf('lit'), AppColors.accent);
    expect(inkOf('out'), isNot(AppColors.accent));
    expect(inkOf('plain'), isNot(AppColors.accent));
    // A word in the glyph's slot wears the same ink (the 1:1).
    final word = find.text('1:1');
    expect(
      tester.widget<Text>(word).style?.color ??
          DefaultTextStyle.of(tester.element(word)).style.color,
      AppColors.accent,
    );
  });

  testWidgets('a rail glyph — the timeline group reset', (tester) async {
    await tester.pumpWidget(
      harness(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (name, press, resets) in [
              ('lit', () {}, true),
              ('out', null, true),
              ('plain', () {}, false),
            ])
              KeyedSubtree(
                key: ValueKey<String>(name),
                child: RailGlyphButton(
                  name: name,
                  tooltip: '',
                  glyph: const RailIconGlyph(Icons.settings_backup_restore),
                  size: AppIconButtonSize.micro,
                  onPressed: press,
                  resets: resets,
                ),
              ),
          ],
        ),
      ),
    );
    Color? inkOf(String key) =>
        tester.glyphInkOf(find.byKey(ValueKey<String>(key)));

    expect(inkOf('lit'), AppColors.accent);
    expect(inkOf('out'), isNot(AppColors.accent));
    expect(inkOf('plain'), isNot(AppColors.accent));
  });

  testWidgets('a tool setting button — its ground', (tester) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolSettingAction(
                keyValue: 'lit',
                label: 'Reset',
                onPressed: () {},
                resets: true,
              ),
              const ToolSettingAction(
                keyValue: 'out',
                label: 'Reset',
                onPressed: null,
                resets: true,
              ),
              ToolSettingAction(
                keyValue: 'plain',
                label: 'Reset',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    Color? groundOf(String key) =>
        (tester.widget<DecoratedBox>(find.byKey(ValueKey<String>(key)))
                    .decoration
                as SuperellipseFace)
            .color;

    expect(groundOf('lit'), AppColors.accent);
    expect(groundOf('out'), isNot(AppColors.accent));
    expect(groundOf('plain'), isNot(AppColors.accent));
  });

  testWidgets('an export chip — 초기화 and the cut grid 전부', (tester) async {
    await tester.pumpWidget(
      harness(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExportResetChip(enabled: true, onPressed: () {}, label: 'lit'),
            ExportResetChip(enabled: false, onPressed: () {}, label: 'out'),
          ],
        ),
      ),
    );
    Color? wordOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;

    expect(wordOf('lit'), AppColors.accent);
    expect(wordOf('out'), isNot(AppColors.accent));
  });
}
