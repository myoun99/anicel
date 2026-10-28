
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/dialogs/preferences_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

import '../helpers/boolean_dot_probe.dart';

/// 🚨★★★A RING BESIDE A LABEL IS ONE ROW — 유저 answered board
/// `one-boolean-row-shape-Q1` on 2026-09-24: 「**설정 줄 하나로**」.
///
/// Three shapes stood there: the settings rows (the whole row presses, the
/// ring on the right), the brush settings panel's switches (ring on the
/// right, but only the ring pressed) and the export and import windows'
/// switches (ring on the LEFT, only the ring pressed). The answer was the
/// first shape everywhere — 「라벨을 눌러도 켜지고 꺼진다」.
///
/// 🚨★★★AND THEN ONLY THE RING PRESSES — 유저 2026-10-23, board
/// `F-439-Q1`: 「**링만 컨트롤, 라벨은 글자**」. A row that was all control
/// left a pen nowhere to start a scroll in a window of them (Preferences ▸
/// Input, F-439).
///
/// 🧪**What those answers ARE, measured, at one row of each shape.** ⛔Not
/// which widget class sits there — the source scan in
/// `one_boolean_control_test` holds that; this holds what a hand meets:
/// ① a press on the RING turns the toggle, and a press on the LABEL does
///   not,
/// ② the ring sits to the RIGHT of the label,
/// ③ a drag that starts on the label scrolls the window, and one that
///   starts on the ring does not.
/// And where its neighbours stand in the same tree (the brush panel),
/// ④ the label reads at their size — the tool settings' one name size
/// (tool-settings-panel-tidy, 유저 2026-10-10: 「켜고 끄는 줄도 같은
/// 높이와 같은 글자」).
void main() {
  /// ② — the ring's box starts where the label's box has ended.
  void expectRingRightOf(WidgetTester tester, Finder tile, Finder label) {
    final ring = tester.getRect(
      find.descendant(of: tile, matching: find.byType(BooleanDot)),
    );
    expect(
      ring.left,
      greaterThanOrEqualTo(tester.getRect(label).right),
      reason: 'the ring sits on the right of its label',
    );
  }

  testWidgets('the brush settings panel\'s switch: the ring presses it and '
      'the label does not, the ring is on the right, the label reads as the '
      'names beside it', (tester) async {
    var state = BrushToolState.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                StatefulBuilder(
                  builder: (context, setState) => BrushSettingsPanel(
                    state: state,
                    onChanged: (next) => setState(() => state = next),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final tile = find.byKey(
      const ValueKey<String>('brush-tool-mixing-toggle'),
    );
    final label = find.descendant(
      of: tile,
      matching: find.text(AppText.strings.brMixing),
    );
    expect(state.mixesGroundColor, isFalse);

    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(state.mixesGroundColor, isFalse, reason: 'the label is words');

    await tester.pressRingIn(tile);
    await tester.pumpAndSettle();
    expect(state.mixesGroundColor, isTrue);
    expectRingRightOf(tester, tile, label);
    // A bar's name, in the column beside it.
    expect(
      tester.getSize(label).height,
      tester.getSize(find.text(AppText.strings.brFlow)).height,
    );
  });

  testWidgets('the export window\'s switch: the ring presses it and the label '
      'does not, the ring is on the right', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1120, 660));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            session: session,
            formatAvailability: ExportFormatAvailability.permissive(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-tab-sequence')));
    await tester.pump();
    final tile = find.byKey(const ValueKey<String>('export-audio-toggle'));
    if (tile.evaluate().isEmpty) {
      // A folded accordion titles itself 「Audio — …」.
      final header = find.textContaining(AppText.strings.exAudio).first;
      await tester.ensureVisible(header);
      await tester.tap(header);
      await tester.pump();
    }
    final dialog = tester.state<ExportDialogState>(find.byType(ExportDialog));
    final before = dialog.debugSpecs.sequence.includeAudio;
    final label = find.descendant(
      of: tile,
      matching: find.text(AppText.strings.exMuxSeMix),
    );

    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pump();
    expect(
      dialog.debugSpecs.sequence.includeAudio,
      before,
      reason: 'the label is words',
    );

    await tester.pressRingIn(tile);
    await tester.pump();
    expect(dialog.debugSpecs.sequence.includeAudio, !before);
    expectRingRightOf(tester, tile, label);
  });

  testWidgets('the ring is drawn as a list tile draws its glyph, and the row '
      'stands as tall as one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              SettingsSwitchRow(
                tileKey: const ValueKey<String>('row'),
                label: 'Row',
                value: false,
                onChanged: (_) {},
              ),
              const ListTile(
                key: ValueKey<String>('tile'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Row'),
                trailing: BooleanDot(value: false),
              ),
            ],
          ),
        ),
      ),
    );
    Size ringIn(String key) => tester.getSize(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(BooleanDot),
      ),
    );
    expect(ringIn('row'), ringIn('tile'));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('row'))).height,
      tester.getSize(find.byKey(const ValueKey<String>('tile'))).height,
    );
  });

  // 🗣️F-439 (유저 2026-10-22): 「환경설정의 손가락 추가 모디파이어등 …
  // 항목에서만 펜으로 스크롤이 시작안됨」 — measured: every switch row, with
  // a tooltip or without.
  group('③ a drag from the label scrolls the window — Preferences ▸ Input', () {
    tearDown(
      () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
    );

    for (final kind in const [
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      PointerDeviceKind.mouse,
    ]) {
      testWidgets(kind.name, (tester) async {
        final session = EditorSessionManager(
          initialProject: createDefaultProject(),
        );
        addTearDown(session.dispose);
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPreferencesDialog(
                    context,
                    session: session,
                    openSessions: [session],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // A row with a tooltip and a row without one.
        for (final key in const [
          'settings-extra-finger',
          'settings-ignore-touch',
        ]) {
          final tile = find.byKey(ValueKey<String>(key));
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          // The list the row stands in — not the window's first scrollable.
          final position = Scrollable.of(
            tester.element(tile),
            axis: Axis.vertical,
          ).position;
          expect(
            position.maxScrollExtent,
            greaterThan(100),
            reason: '⛔전제: $key stands in a list that scrolls',
          );
          final before = tester.booleanDotIn(tile).value;
          final label = find
              .descendant(of: tile, matching: find.byType(Text))
              .first;

          var at = position.pixels;
          await tester.dragFrom(
            tester.getCenter(label),
            Offset(0, at > 40 ? 40 : -40),
            kind: kind,
          );
          await tester.pumpAndSettle();
          expect(
            position.pixels,
            isNot(at),
            reason: '$key: the label scrolls',
          );
          expect(tester.booleanDotIn(tile).value, before, reason: key);

          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          at = position.pixels;
          await tester.dragFrom(
            tester.getCenter(
              find.descendant(of: tile, matching: find.byType(BooleanDot)),
            ),
            Offset(0, at > 40 ? 40 : -40),
            kind: kind,
          );
          await tester.pumpAndSettle();
          expect(position.pixels, at, reason: '$key: the ring is a control');
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  });
}
