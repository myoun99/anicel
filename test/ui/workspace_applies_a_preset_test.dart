import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_hand_settings_store.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// APPLYING A PRESET FROM THE WORKSPACE — MEASURED.
///
/// The preset panel has its own tests, with a callback in place of the
/// workspace. The workspace's half — taking the preset into the brush tool
/// and marking it active in the library — was not measured: when the
/// presets were carved out of the workspace State (2026-09-02) the
/// adversarial check made `_applyPreset` a no-op and every preset test
/// stayed green. So this taps a preset in the real panel and reads the
/// active preset the panel is then handed back.
///
/// 🚨H25-again and H36 (유저 2026-09-11) live here for the same reason: the
/// state-level rules held while the WIRING filed one brush's size under
/// another, so these drive the user's own sequences through the real panel,
/// the real size bar and the real tool buttons.
void main() {
  // Every test starts with nothing remembered: the bank is one sandbox file
  // per test process, and what one test's hand set would otherwise come back
  // on the next test's brushes.
  setUp(() {
    final bank = File(
      BrushHandSettingsStore.defaultBrushHandSettingsFilePath(),
    );
    if (bank.existsSync()) {
      bank.deleteSync();
    }
  });

  /// The app with the built-in presets loaded, on temp files.
  ///
  /// [beforeTheLibraryLands] runs after the first frame and before the
  /// library has loaded — the window in which the hand holds no preset yet.
  Future<void> pumpWithPresets(
    WidgetTester tester, {
    Future<void> Function()? beforeTheLibraryLands,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Under FLUTTER_TEST the workspace's preset library loads from nothing
    // and is empty; a service on a missing file yields the built-in
    // presets. Real file IO only inside runAsync — the testWidgets clock is
    // fake, and an awaited read never completes on it.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('presets'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    final service = BrushPresetFileService(
      filePath: '${directory.path}/brush_presets.json',
    );
    // The tip library loads first (presets reference tips by id); on its
    // own temp directory so nothing on this machine is read or written.
    final tips = BrushTipLibraryService(
      directoryPath: '${directory.path}/tips',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(presetFileService: service, tipLibraryService: tips),
      ),
    );
    await beforeTheLibraryLands?.call();
    // The loads are real file IO started on the fake clock: each step
    // completes in real time (a runAsync window) and its continuation runs
    // on the fake one (a pump). Alternate until the panel has presets.
    for (var tries = 0; tries < 40; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      // Loaded = the presets are listed AND a brush is in hand: the opening
      // brush is taken up only once the hand-settings bank has landed too
      // (H25-again), and that is one more file read after the libraries'.
      final panels = find.byType(BrushPresetPanel).evaluate();
      final shown = panels.isEmpty
          ? null
          : tester.widget<BrushPresetPanel>(
              find.byType(BrushPresetPanel).first,
            );
      if (shown != null &&
          shown.presets.isNotEmpty &&
          shown.selectedPresetId != null) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  BrushPresetPanel panel(WidgetTester tester) =>
      tester.widget<BrushPresetPanel>(find.byType(BrushPresetPanel).first);

  Finder tileOf(BrushPresetId id) =>
      find.byKey(ValueKey<String>('brush-preset-entry-${id.value}'));

  /// The presets the panel is showing right now — the library's contents
  /// are the product's, not this test's.
  List<BrushPresetId> onScreen(WidgetTester tester) => [
    for (final preset in panel(tester).presets)
      if (tileOf(preset.id).evaluate().isNotEmpty) preset.id,
  ];

  Future<void> pick(WidgetTester tester, BrushPresetId id) async {
    await tester.tap(tileOf(id));
    await tester.pumpAndSettle();
  }

  final sizeBar = find.byKey(const ValueKey<String>('top-strip-size-bar'));

  double size(WidgetTester tester) => tester.widget<FieldSlider>(sizeBar).value;

  /// A tap on the strip's size bar, [along] of the way across — the bar sets
  /// the value at the pointer and keeps it.
  Future<void> setSizeAt(WidgetTester tester, double along) async {
    final bar = tester.getRect(sizeBar);
    await tester.tapAt(Offset(bar.left + bar.width * along, bar.center.dy));
    await tester.pumpAndSettle();
  }

  Future<void> takeUp(WidgetTester tester, String tool) async {
    await tester.tap(find.byKey(ValueKey<String>('tool-$tool-button')));
    await tester.pumpAndSettle();
  }

  /// Opens the brush settings — their own rail slot, which ships closed.
  Future<void> openBrushSettings(WidgetTester tester) async {
    final group = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$group')));
    await tester.pumpAndSettle();
  }

  BrushSettingsPanel settings(WidgetTester tester) =>
      tester.widget<BrushSettingsPanel>(find.byType(BrushSettingsPanel));

  /// An edit made the way the settings panel's own controls make one —
  /// through the callback the workspace hands the panel.
  Future<void> edit(
    WidgetTester tester,
    BrushToolState Function(BrushToolState state) change,
  ) async {
    final panel = settings(tester);
    panel.onChanged(change(panel.state));
    await tester.pumpAndSettle();
  }

  String curveOf(BrushToolState state) =>
      jsonEncode(state.shape.sizePressureCurve?.toJson());

  testWidgets('tapping a preset makes it the active one', (tester) async {
    await pumpWithPresets(tester);
    final active = panel(tester).selectedPresetId;
    final target = onScreen(tester).firstWhere(
      (id) => id != active,
      orElse: () => throw StateError(
        '⛔premise: no other preset is on screen — active $active',
      ),
    );

    await pick(tester, target);

    expect(
      panel(tester).selectedPresetId,
      target,
      reason: 'the workspace applied the preset and marked it active',
    );
  });

  testWidgets('🚨H25-again: each brush comes back at the size set ON IT — '
      '유저\'s own sequence', (tester) async {
    await pumpWithPresets(tester);
    final shown = onScreen(tester);
    expect(shown.length, greaterThanOrEqualTo(2), reason: 'premise');
    final one = shown[0];
    final two = shown[1];

    await pick(tester, one);
    await setSizeAt(tester, 0.2);
    final sizeOne = size(tester);
    await pick(tester, two);
    await setSizeAt(tester, 0.8);
    final sizeTwo = size(tester);
    expect(sizeTwo, isNot(sizeOne), reason: 'premise: two different sizes');

    await pick(tester, one);
    expect(size(tester), sizeOne, reason: '「1 고르면 6되는데」');
    await pick(tester, two);
    expect(
      size(tester),
      sizeTwo,
      reason: '「다시 2 고르면 100이아니라 6이되」 — the switch to 1 filed '
          '1\'s size under 2, because the listener heard the new brush '
          'while the old one was still named',
    );
    await pick(tester, one);
    expect(size(tester), sizeOne);
  });

  testWidgets('🚨what the ERASER sets on a brush does not come back when '
      'that brush is picked to draw with (R11-④)', (tester) async {
    await pumpWithPresets(tester);
    final shown = onScreen(tester);
    final one = shown[0];
    final two = shown[1];
    await pick(tester, one);
    await setSizeAt(tester, 0.2);
    final drawing = size(tester);
    // The brush moves on, so nothing it does on the way back can re-file
    // `one` — only the eraser touches it from here.
    await pick(tester, two);

    // The eraser picks `one` for itself and is set bigger.
    await takeUp(tester, 'eraser');
    await pick(tester, one);
    await setSizeAt(tester, 0.8);
    expect(size(tester), isNot(drawing), reason: 'premise');

    await takeUp(tester, 'brush');
    await pick(tester, one);

    expect(
      size(tester),
      drawing,
      reason: 'one key for both tools filed the eraser\'s size under the '
          'brush — each paint tool keeps its own settings',
    );
  });

  testWidgets('🚨H36: the eraser shows the brush it holds from the first '
      'time it is taken up, and each tool keeps its own', (tester) async {
    await pumpWithPresets(tester);
    final held = panel(tester).selectedPresetId;
    expect(held, isNotNull, reason: 'premise (F-63): the brush opens on one');

    await takeUp(tester, 'eraser');
    expect(
      panel(tester).selectedPresetId,
      held,
      reason: '「지우개는 첫 선택된 지우개가 활성화표시? 그게 안되있는데? '
          '브러시만 되있는데 이상하잖아」',
    );

    final other = onScreen(tester).firstWhere((id) => id != held);
    await pick(tester, other);
    expect(panel(tester).selectedPresetId, other);

    await takeUp(tester, 'brush');
    expect(panel(tester).selectedPresetId, held);
    await takeUp(tester, 'eraser');
    expect(panel(tester).selectedPresetId, other);
  });

  testWidgets('🚨H36: a paint tool banked before the library landed opens '
      'on a brush the moment it is taken up again', (tester) async {
    await pumpWithPresets(
      tester,
      beforeTheLibraryLands: () => takeUp(tester, 'eraser'),
    );
    expect(
      panel(tester).selectedPresetId,
      isNotNull,
      reason: 'the eraser was in hand when the library landed',
    );

    await takeUp(tester, 'brush');

    expect(
      panel(tester).selectedPresetId,
      isNotNull,
      reason: 'the brush was banked holding nothing — taking it up again is '
          'its opening moment, not only the app\'s first frame',
    );
  });

  testWidgets('saving the brush in hand as a preset makes the new one the '
      'brush in hand', (tester) async {
    await pumpWithPresets(tester);
    final before = {for (final preset in panel(tester).presets) preset.id};

    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-save-button')),
    );
    await tester.pumpAndSettle();

    final saved = panel(
      tester,
    ).presets.singleWhere((preset) => !before.contains(preset.id));
    expect(
      panel(tester).selectedPresetId,
      saved.id,
      reason: 'the library said a save "makes it active" and the highlight '
          'never followed — the panel read one fact and the save wrote '
          'another',
    );
  });

  testWidgets('🚨H25-again: the pressure curve, the flow and the edge come '
      'back with THEIR brush — 「필압이나 이런거」', (tester) async {
    await pumpWithPresets(tester);
    await openBrushSettings(tester);
    final shown = onScreen(tester);
    final one = shown[0];
    final two = shown[1];
    final curve = BrushPressureCurve.linearFrom(0.6);
    await pick(tester, two);
    final twoAsFiled = settings(tester).state;
    await pick(tester, one);
    expect(settings(tester).state.flow, isNot(0.3), reason: 'premise');
    expect(
      settings(tester).state.antiAlias,
      isNot(BrushAntiAlias.none),
      reason: 'premise',
    );

    await edit(
      tester,
      (state) => state.copyWith(
        sizePressureCurve: curve,
        flow: 0.3,
        antiAlias: BrushAntiAlias.none,
      ),
    );
    await pick(tester, two);

    final other = settings(tester).state;
    expect(
      other.flow,
      twoAsFiled.flow,
      reason: 'one brush\'s edit is not the next brush\'s',
    );
    expect(other.antiAlias, twoAsFiled.antiAlias);
    expect(curveOf(other), curveOf(twoAsFiled));

    await pick(tester, one);
    final back = settings(tester).state;
    expect(back.flow, 0.3, reason: '「사이즈말고도 … 싹 다」');
    expect(back.antiAlias, BrushAntiAlias.none);
    expect(curveOf(back), jsonEncode(curve.toJson()));
  });

  testWidgets('🚨what the hand set survives closing the app — and the brush '
      'the app opens on wears it from the first frame it is held', (
    tester,
  ) async {
    await pumpWithPresets(tester);
    await openBrushSettings(tester);
    final opening = panel(tester).selectedPresetId;
    expect(opening, isNotNull, reason: 'premise: a brush is in hand');
    await edit(
      tester,
      (state) => state.copyWith(flow: 0.3, antiAlias: BrushAntiAlias.none),
    );

    // Closing the workspace writes the bank. That is real file IO started on
    // the fake clock, so it lands the way the loads do — a real-time window
    // for each step and a pump for each continuation — until it is on disk.
    await tester.pumpWidget(const SizedBox());
    final bank = File(BrushHandSettingsStore.defaultBrushHandSettingsFilePath());
    bool written() {
      try {
        return bank.existsSync() && bank.readAsStringSync().contains('"flow"');
      } on FileSystemException {
        return false;
      }
    }

    for (var tries = 0; tries < 40 && !written(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(
      written(),
      isTrue,
      reason: 'premise: closing the workspace wrote what the hand set',
    );
    await pumpWithPresets(tester);
    await openBrushSettings(tester);

    expect(panel(tester).selectedPresetId, opening);
    expect(
      settings(tester).state.flow,
      0.3,
      reason: 'the bank lands before the opening brush is taken up, so that '
          'brush wears what the hand left on it',
    );
    expect(settings(tester).state.antiAlias, BrushAntiAlias.none);
  });

  testWidgets('🚨F-123: the workspace hands the door what the tools hold, and '
      'puts a saved choice back through the library', (tester) async {
    await pumpWithPresets(tester);
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final bridge = workspace.session.projectDoor.toolChoice!;
    final tools = workspace.brushTool!;
    final held = tools.value.presetId;
    final other = onScreen(tester).firstWhere(
      (id) => id != held,
      orElse: () => throw StateError('⛔premise: one preset only — $held'),
    );
    expect(
      bridge.read()['tool'],
      tools.value.tool.name,
      reason: 'the door reads the hand as it is',
    );

    bridge.resume({
      'tool': 'eraser',
      'presets': {'eraser': other.value},
    });
    await tester.pumpAndSettle();
    expect(tools.value.tool, CanvasTool.eraser);
    expect(tools.value.presetId, other);
  });

  testWidgets('🚨F-123: a choice handed back BEFORE the library has landed '
      'waits for it — a brush is named by a preset only a loaded library can '
      'find', (tester) async {
    const saved = BrushPresetId('builtin-g-pen');
    late EditorWorkspace workspace;
    await pumpWithPresets(
      tester,
      beforeTheLibraryLands: () async {
        workspace = tester.widget<EditorWorkspace>(
          find.byType(EditorWorkspace),
        );
        workspace.session.projectDoor.toolChoice!.resume({
          'presets': {'brush': saved.value},
        });
      },
    );
    expect(
      panel(tester).presets.first.id,
      isNot(saved),
      reason: 'premise: the opening brush is another one',
    );
    expect(
      workspace.brushTool!.value.presetId,
      saved,
      reason: 'resumed once the library could name it, not dropped because '
          'it was still empty',
    );
  });
}
