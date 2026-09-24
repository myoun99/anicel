import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

import '../helpers/boolean_dot_probe.dart';
import '../helpers/solid_png_fixture.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★A RING BESIDE A LABEL IS ONE ROW — 유저 answered board
/// `one-boolean-row-shape-Q1` on 2026-09-24: 「**설정 줄 하나로**」.
///
/// Three shapes stood there: the settings rows (the whole row presses, the
/// ring on the right), the brush settings panel's switches (ring on the
/// right, but only the ring pressed) and the export and import windows'
/// switches (ring on the LEFT, only the ring pressed). The answer is the
/// first shape everywhere — 「라벨을 눌러도 켜지고 꺼진다」.
///
/// 🧪**What that answer IS, measured, at one row of each shape that
/// changed.** ⛔Not which widget class sits there — the source scan in
/// `one_boolean_control_test` holds that; this holds what a hand meets:
/// ① a press on the LABEL turns the toggle,
/// ② the ring sits to the RIGHT of the label.
/// And where a reference row can stand in the same tree (the brush panel),
/// ③ the label reads at the settings row's size.
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

  testWidgets('the brush settings panel\'s switch: the label presses it, the '
      'ring is on the right, the label reads at the settings size', (
    tester,
  ) async {
    const reference = 'A settings row as the rest of the app has it';
    var state = BrushToolState.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SettingsSwitchRow(
                  label: reference,
                  value: false,
                  onChanged: (_) {},
                ),
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
    const tile = ValueKey<String>('brush-tool-mixing-toggle');
    final label = find.descendant(
      of: find.byKey(tile),
      matching: find.text(AppText.strings.brMixing),
    );
    expect(state.mixesGroundColor, isFalse);

    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pumpAndSettle();

    expect(
      state.mixesGroundColor,
      isTrue,
      reason: 'only the ring pressed here before',
    );
    expectRingRightOf(tester, find.byKey(tile), label);
    expect(
      tester.getSize(label).height,
      tester.getSize(find.text(reference)).height,
    );
  });

  testWidgets('the export window\'s switch: the label presses it, the ring is '
      'on the right', (tester) async {
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
    const tile = ValueKey<String>('export-apply-fx-toggle');
    if (find.byKey(tile).evaluate().isEmpty) {
      // A folded accordion titles itself 「Options — FX on」.
      final header = find.textContaining(AppText.strings.exOptions).first;
      await tester.ensureVisible(header);
      await tester.tap(header);
      await tester.pump();
    }
    final dialog = tester.state<ExportDialogState>(find.byType(ExportDialog));
    final before = dialog.debugSpecs.sequence.applyLayerFx;
    final label = find.descendant(
      of: find.byKey(tile),
      matching: find.text(AppText.strings.exApplyLayerFxHelp),
    );

    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pump();

    expect(
      dialog.debugSpecs.sequence.applyLayerFx,
      !before,
      reason: 'the ring stood on the LEFT here, and only it pressed',
    );
    expectRingRightOf(tester, find.byKey(tile), label);
  });

  group('the import window', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anicel-labelled-ring');
    });

    tearDown(() => deleteTempQuietly(tempDir));

    testWidgets('its folder switch: the label presses it, the ring is on the '
        'right', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      // A delivery folder — the settings column is the FOLDER column.
      final folder = (await tester.runAsync(() async {
        const root = 'upn_02_063_lo';
        final sep = Platform.pathSeparator;
        await writeSolidPng(tempDir, '$root${sep}A1.png', rgba: 0xAAAAAAAA);
        return '${tempDir.path}$sep$root';
      }))!;
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: session, initialPaths: [folder]),
          ),
        ),
      );
      for (var i = 0; i < 8; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      const tile = ValueKey<String>('import-subfolders-toggle');
      final before = tester.booleanDotIn(find.byKey(tile)).value;
      final label = find.descendant(
        of: find.byKey(tile),
        matching: find.text(AppText.strings.imArchivedProcesses),
      );

      await tester.ensureVisible(label);
      await tester.tap(label);
      for (var i = 0; i < 4; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }

      expect(
        tester.booleanDotIn(find.byKey(tile)).value,
        !before,
        reason: 'the ring stood on the LEFT here, and only it pressed',
      );
      expectRingRightOf(tester, find.byKey(tile), label);
    });
  });
}
