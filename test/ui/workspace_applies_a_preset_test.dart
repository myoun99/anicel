import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_group_id.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart' show BrushMaskSlot;
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart'
    show paperGrainTextureMask;
import 'package:anicel/src/ui/brush/brush_hand_settings_store.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/brush_settings_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/brush_actions.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import '../helpers/project_scratch_folder.dart';

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
    deleteAfterSessionEnds(directory);
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

  Future<void> fromTheMenu(WidgetTester tester, String verb) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-menu-button')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(verb).first);
    await tester.pumpAndSettle();
  }

  /// The library's order, every brush, as the panel is handed it.
  List<BrushPresetId> order(WidgetTester tester) => [
    for (final preset in panel(tester).presets) preset.id,
  ];

  /// The brushes of the tab [id] shows in, in order.
  List<BrushPresetId> tabOf(WidgetTester tester, BrushPresetId id) {
    final shown = panel(tester);
    final group = shown.presets
        .firstWhere((preset) => preset.id == id)
        .groupShownAmong(shown.groups);
    return [
      for (final preset in shown.presets)
        if (preset.groupShownAmong(shown.groups) == group) preset.id,
    ];
  }

  Future<void> pickInView(WidgetTester tester, BrushPresetId id) async {
    await tester.ensureVisible(tileOf(id));
    await pick(tester, id);
  }

  /// Opens the first tab holding at least [count] brushes, picks its first
  /// and returns the tab. ⚠️These cases are about the library, not about
  /// the tab the roster opens on — board F-218 put the two-brush Basic tab
  /// first, and a case reading the third brush of the opening tab broke.
  Future<List<BrushPresetId>> openTabWithAtLeast(
    WidgetTester tester,
    int count,
  ) async {
    final shown = panel(tester);
    for (final group in shown.groups) {
      final ids = [
        for (final preset in shown.presets)
          if (preset.groupShownAmong(shown.groups) == group.id) preset.id,
      ];
      if (ids.length < count) {
        continue;
      }
      final tabKey = find.byKey(
        ValueKey<String>('brush-preset-tab-${group.id.value}'),
      );
      await tester.ensureVisible(tabKey);
      await tester.tap(tabKey);
      await tester.pumpAndSettle();
      await pickInView(tester, ids.first);
      return tabOf(tester, ids.first);
    }
    throw StateError('⛔premise: no tab holds $count brushes');
  }

  // 🗣️F-250 (유저 2026-10-01): 「브러시 위치 바꾸는것도 언두에 기록. 그룹바꾸든
  // 순서바꾸든. 그리고 브러시 삭제하면 현재 선택된 브러시 ui가 없어지는데,
  // 제대로 삭제하면 그 외 브러시 선택시키도록」.
  testWidgets('🚨F-250: a brush moved in the library goes back with one undo '
      '— and a brush deleted since stays deleted', (tester) async {
    await pumpWithPresets(tester);
    final tab = await openTabWithAtLeast(tester, 4);
    final before = order(tester);
    final moved = [...panel(tester).presets];
    moved.insert(0, moved.removeAt(before.indexOf(tab[2])));
    panel(tester).onPresetsReordered!(moved);
    await tester.pumpAndSettle();
    expect(order(tester).first, tab[2], reason: 'premise: it moved');

    // Not on the undo stack: a delete between the move and its undo.
    final doomed = tab[3];
    await pickInView(tester, doomed);
    await fromTheMenu(tester, 'Delete selected brush');
    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();

    expect(order(tester), [
      for (final id in before)
        if (id != doomed) id,
    ]);
  });

  testWidgets('🚨F-250: deleting the brush in hand hands every tool that held '
      'it the brush beside it', (tester) async {
    await pumpWithPresets(tester);
    final tab = await openTabWithAtLeast(tester, 3);
    final doomed = tab[1];
    await pickInView(tester, doomed);
    await takeUp(tester, 'eraser');
    await pickInView(tester, doomed);
    await takeUp(tester, 'brush');

    await fromTheMenu(tester, 'Delete selected brush');

    expect(tileOf(doomed), findsNothing, reason: 'premise: it is gone');
    expect(panel(tester).selectedPresetId, tab[2], reason: 'the next one');
    await takeUp(tester, 'eraser');
    expect(
      panel(tester).selectedPresetId,
      tab[2],
      reason: 'the eraser held it too',
    );
  });

  testWidgets('F-250: the last brush of a tab hands over to the one before',
      (tester) async {
    await pumpWithPresets(tester);
    final tab = tabOf(tester, panel(tester).selectedPresetId!);
    await pickInView(tester, tab.last);

    await fromTheMenu(tester, 'Delete selected brush');

    expect(panel(tester).selectedPresetId, tab[tab.length - 2]);
  });

  /// The tabs of at least [count] brushes that the opening brush does not
  /// show in, in rail order.
  List<List<BrushPresetId>> otherTabsWithAtLeast(
    WidgetTester tester,
    int count,
  ) {
    final shown = panel(tester);
    final opening = shown.presets
        .firstWhere((preset) => preset.id == shown.selectedPresetId)
        .groupShownAmong(shown.groups);
    return [
      for (final group in shown.groups)
        if (group.id != opening)
          [
            for (final preset in shown.presets)
              if (preset.groupShownAmong(shown.groups) == group.id) preset.id,
          ],
    ].where((tab) => tab.length >= count).toList();
  }

  /// A tap on the tab [member] shows in, the way a hand taps it.
  Future<void> tapTabOf(WidgetTester tester, BrushPresetId member) async {
    final shown = panel(tester);
    final group = shown.presets
        .firstWhere((preset) => preset.id == member)
        .groupShownAmong(shown.groups);
    final tab = find.byKey(
      ValueKey<String>('brush-preset-tab-${group?.value ?? 'root'}'),
    );
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  // 🗣️F-250 (유저 2026-10-01): 「브러시 그룹을 바꿀때(선택하던 뭐던), 해당
  // 그룹의 마지막으로 선택했던걸 기억해서 그거 자동선택되도록」.
  testWidgets('🚨F-250: opening a group takes up the brush last picked there '
      '— its first the first time — and the tab in hand stays', (
    tester,
  ) async {
    await pumpWithPresets(tester);
    final [x, y, ...] = otherTabsWithAtLeast(tester, 2);

    await tapTabOf(tester, x.first);
    expect(
      panel(tester).selectedPresetId,
      x.first,
      reason: 'nothing held there yet: the group\'s first',
    );
    await pickInView(tester, x[1]);
    await tapTabOf(tester, y.first);
    expect(panel(tester).selectedPresetId, y.first);

    await tapTabOf(tester, x.first);
    expect(
      panel(tester).selectedPresetId,
      x[1],
      reason: '「해당 그룹의 마지막으로 선택했던걸 기억해서」',
    );
    await tapTabOf(tester, x.first);
    expect(
      panel(tester).selectedPresetId,
      x[1],
      reason: 'the brush in hand is in that tab already — it stays',
    );
  });

  // 🗣️F-250-group-memory-Q1 (유저 2026-10-01): 「도구마다 따로」.
  //
  // ⚠️A paint tool held for the first time takes up the brush in hand
  // (PaintToolStateNotifier), and taking a brush up is remembered in its
  // tab like any pick — so the eraser is taken up in ANOTHER tab here, or
  // it would hold the brush tool's choice in x already and the rule 「inside
  // the tab, the brush stays」 would answer for the memory.
  testWidgets('🚨F-250: each paint tool remembers its own last brush in a '
      'group', (tester) async {
    await pumpWithPresets(tester);
    final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
    await tapTabOf(tester, x.first);
    await pickInView(tester, x[1]);
    await tapTabOf(tester, y.first);

    await takeUp(tester, 'eraser');
    await tapTabOf(tester, x.first);
    expect(
      panel(tester).selectedPresetId,
      x.first,
      reason: 'the eraser never held one there — the brush tool\'s choice '
          'is the brush tool\'s',
    );

    await takeUp(tester, 'brush');
    await tapTabOf(tester, x.first);
    expect(
      panel(tester).selectedPresetId,
      x[1],
      reason: 'and the eraser\'s did not overwrite it',
    );
  });

  // The rail's other half (railEntry: 안에 있으면 그대로): a tab the brush in
  // hand shows in keeps it, whatever was last picked there — the memory
  // answers only a hand coming from outside.
  testWidgets('🚨F-250: the brush in hand moved into another tab stays in '
      'hand when that tab opens', (tester) async {
    await pumpWithPresets(tester);
    final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
    await tapTabOf(tester, y.first);
    await tapTabOf(tester, x.first);
    await pickInView(tester, x[1]);
    final shown = panel(tester);
    final yGroup = shown.presets
        .firstWhere((preset) => preset.id == y.first)
        .groupShownAmong(shown.groups);
    shown.onPresetsReordered!([
      for (final preset in shown.presets)
        if (preset.id == x[1]) preset.copyWith(groupId: yGroup) else preset,
    ]);
    await tester.pumpAndSettle();
    expect(tabOf(tester, x[1]), contains(y.first), reason: 'premise: moved');

    await tapTabOf(tester, y.first);

    expect(
      panel(tester).selectedPresetId,
      x[1],
      reason: 'it shows in that tab now — the hand stays on it, though '
          '${y.first} was the last picked there',
    );
  });

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

  testWidgets('🚨F-181: a library reset forgets what the hand set on its '
      'brushes — and every paint tool lets go of it', (tester) async {
    // 유저 2026-09-27 (F-181-Q1): 「pc로는 초기화해도 남아있던데 폰으로보니
    // 안골라져있음 … 초기화가 제대로 브러시 설정도 기본값으로 초기화
    // 안하는걸지도」 — the G-pen's remembered paper grain came back after a
    // reset. A size is the same memory (the hand bank) and the strip shows it.
    await pumpWithPresets(tester);
    final one = onScreen(tester)[0];
    final two = onScreen(tester)[1];
    await pick(tester, one);
    final own = size(tester);
    await setSizeAt(tester, 0.8);
    expect(size(tester), isNot(own), reason: 'premise: the hand set it');
    // The eraser holds the same brush and the hand sets it too.
    await takeUp(tester, 'eraser');
    await pick(tester, one);
    await setSizeAt(tester, 0.3);
    expect(size(tester), isNot(own), reason: 'premise: and on the eraser');
    await takeUp(tester, 'brush');

    // The library itself has changed too: a brush is deleted.
    await pick(tester, two);
    await fromTheMenu(tester, 'Delete selected brush');
    expect(tileOf(two), findsNothing, reason: 'premise: it is gone');
    await pick(tester, one);

    await fromTheMenu(tester, 'Reset brush library');
    await tester.tap(
      find.byKey(const ValueKey<String>('brush-preset-reset-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(tileOf(two), findsOneWidget, reason: 'the built-ins are back');
    expect(size(tester), own, reason: 'the brush in hand is the reset brush');
    await pick(tester, one);
    expect(size(tester), own, reason: 'and picking it finds nothing kept');
    await takeUp(tester, 'eraser');
    expect(size(tester), own, reason: 'the eraser let go of it too');

    // And nothing waits on disk to bring it back at the next launch. The
    // write is real file IO started on the fake clock: a real-time window
    // for each step and a pump for each continuation, until it lands.
    final bank = File(BrushHandSettingsStore.defaultBrushHandSettingsFilePath());
    bool forgotten() {
      try {
        final json = jsonDecode(bank.readAsStringSync());
        return json is Map<String, dynamic> &&
            (json['brushes'] as Map<String, dynamic>).isEmpty;
      } on Object {
        return false;
      }
    }

    for (var tries = 0; tries < 40 && !forgotten(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(
      forgotten(),
      isTrue,
      reason: 'the bank on disk is emptied too — a save of the old bank '
          'started just before the reset must not land after it. It holds: '
          '${bank.existsSync() ? bank.readAsStringSync() : 'no file'}',
    );
  });

  // 🗣️board `a-brush-picked-wears-the-texture-of-the-one-before` (유저
  // 2026-10-01): 「아날로그가 아닌 일반수채등 질감이 없어야하는게 아직있거든?
  // … 초기화가 설마 텍스처항목은 초기화안하나?」 — F-181 again. Its pin read
  // a size for the paper grain, and the grain rode a door the size never
  // takes: the tool state's copyWith laid the LEFT brush's texture over the
  // brush picked, and H25 filed it as the hand's. These read the texture.
  group('🚨the texture a brush wears is its own', () {
    Future<void> openWatercolours(WidgetTester tester) async {
      final tab = find.byKey(
        const ValueKey<String>('brush-preset-tab-builtin-watercolor-group'),
      );
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    BrushToolState held(WidgetTester tester) => tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!
        .value;

    const analog = BrushPresetId('builtin-analog-watercolor');
    const plain = BrushPresetId('builtin-watercolor');

    testWidgets('a brush picked after a textured one wears none — and none '
        'is filed as the hand\'s to come back', (tester) async {
      await pumpWithPresets(tester);
      await openWatercolours(tester);
      await pickInView(tester, analog);
      expect(held(tester).textureMaskSource, isNotNull, reason: 'premise');

      await pickInView(tester, plain);
      expect(held(tester).textureMaskSource, isNull);
      await pickInView(tester, analog);
      await pickInView(tester, plain);
      expect(held(tester).textureMaskSource, isNull);
    });

    testWidgets('a library reset takes off a texture the hand laid on', (
      tester,
    ) async {
      await pumpWithPresets(tester);
      await openWatercolours(tester);
      await pickInView(tester, plain);
      await openBrushSettings(tester);
      await edit(
        tester,
        (state) => state.withMask(BrushMaskSlot.texture, paperGrainTextureMask),
      );
      expect(held(tester).textureMaskSource, isNotNull, reason: 'premise');

      await fromTheMenu(tester, 'Reset brush library');
      await tester.tap(
        find.byKey(const ValueKey<String>('brush-preset-reset-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(held(tester).presetId, plain, reason: 'premise: still in hand');
      expect(
        held(tester).textureMaskSource,
        isNull,
        reason: '「초기화가 설마 텍스처항목은 초기화안하나?」',
      );
    });
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

  // 🗣️I-56 (유저 2026-10-01): 「브러시 그룹이나 브러시에도 단축키 명명가능하게.
  // 단축키리스트 등록」 — a key presses what the brush's row or the group's
  // tab does (the rows themselves: test/ui/shortcuts/brush_keys_test.dart).
  //
  // 🗣️F-319 (유저 2026-10-08): 「브러시 그룹은 도구가 두곳에 있으니까 두 곳
  // 나눠서 지정하도록. 브러시도구의 브러시그룹/브러시 변경. 지우개도구의
  // 브러시그룹/브러시변경」 — a key is on a brush or a group OF A TOOL, and
  // brings that tool to hand with it.
  group('🚨I-56: a key on a brush or a group', () {
    const k = LogicalKeyboardKey.keyK;
    const brush = CanvasTool.brush;
    const eraser = CanvasTool.eraser;

    EditorShortcutBindings keys(WidgetTester tester) =>
        EditorShortcutScope.peek(tester.element(find.byType(EditorWorkspace)))!;

    BrushGroupId groupOf(WidgetTester tester, BrushPresetId member) {
      final shown = panel(tester);
      return shown.presets
          .firstWhere((preset) => preset.id == member)
          .groupShownAmong(shown.groups)!;
    }

    CanvasTool toolInHand(WidgetTester tester) => tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!
        .value
        .tool;

    /// The action K is on — one at a time, or two rows would answer one key.
    String? keyed;
    setUp(() => keyed = null);

    /// Records K on [actionId], and takes it off whatever it was on.
    void putKeyOn(WidgetTester tester, String actionId) {
      final bindings = keys(tester);
      if (keyed case final before?) {
        bindings.setActivators(before, const []);
      }
      bindings.setActivators(actionId, const [SingleActivator(k)]);
      keyed = actionId;
    }

    /// The key, once the app has taken in what was just recorded for it.
    Future<void> press(WidgetTester tester) async {
      await tester.pump();
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
    }

    /// A group with no brush in it, made the way the panel's menu makes one.
    Future<BrushGroupId> anEmptyGroup(WidgetTester tester) async {
      panel(tester).onGroupCreated!('Nothing yet');
      await tester.pumpAndSettle();
      final shown = panel(tester);
      final made = shown.groups.firstWhere(
        (group) => group.name == 'Nothing yet',
      );
      expect(
        shown.presets.where(
          (preset) => preset.groupShownAmong(shown.groups) == made.id,
        ),
        isEmpty,
        reason: '⛔premise',
      );
      return made.id;
    }

    Future<void> tapTab(WidgetTester tester, BrushGroupId group) async {
      final tab = find.byKey(
        ValueKey<String>('brush-preset-tab-${group.value}'),
      );
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    testWidgets('the library\'s groups and brushes are rows of the shortcut '
        'list once it has landed, in the library\'s order', (tester) async {
      await pumpWithPresets(tester);
      final shown = panel(tester);
      expect(shown.groups, isNotEmpty, reason: '⛔premise');
      expect(
        [
          for (final row in keys(tester).definitions)
            if (row.brushPress != null) row.id,
        ],
        [
          for (final row in brushActionsOf(shown.groups, shown.presets))
            row.id,
        ],
      );
    });

    // 🗣️F-319 (유저 2026-10-08): 「브러시만 지정하더라도 브러시 누르면 그룹
    // 바껴야함」 · 「브러시는 항상 선택된그룹/브러시 를 보여줌」.
    // ↩️This pinned the opposite until then — 「…and the tab shown stays」:
    // the key changed the hand and the library went on showing the tab that
    // had been tapped last.
    testWidgets('🚨a brush\'s key takes it up out of another tab — and the '
        'library shows the tab it is in', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await tapTabOf(tester, x.first);
      expect(tileOf(y[1]), findsNothing, reason: '⛔premise: tab x is shown');
      putKeyOn(tester, brushPresetActionId(brush, y[1]));

      await press(tester);

      expect(panel(tester).selectedPresetId, y[1]);
      expect(tileOf(y[1]), findsOneWidget, reason: 'its tab is shown');
      expect(tileOf(x.first), findsNothing);
    });

    // 🗣️F-319: 「지금 브러시 선택하다 지우개 선택하면 도구라이브러리에서
    // 다른곳에 있는 브러시로 바껴야하는데 바뀌지않음」.
    testWidgets('🚨the eraser coming to hand shows the tab of the brush IT '
        'holds — whatever tab had been tapped', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      // The eraser holds a brush of tab x; the brush tool one of tab y.
      await takeUp(tester, 'eraser');
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      await takeUp(tester, 'brush');
      await tapTabOf(tester, y.first);
      await pickInView(tester, y[1]);
      expect(tileOf(x[1]), findsNothing, reason: '⛔premise: tab y is shown');

      await takeUp(tester, 'eraser');

      expect(panel(tester).selectedPresetId, x[1], reason: '⛔premise');
      expect(tileOf(x[1]), findsOneWidget, reason: 'the eraser\'s tab');
      expect(tileOf(y[1]), findsNothing);

      await takeUp(tester, 'brush');
      expect(tileOf(y[1]), findsOneWidget, reason: 'and back');
    });

    testWidgets('a group\'s key enters its tab: the brush last picked there '
        'comes to hand, and the tab is shown', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      await tapTabOf(tester, y.first);
      expect(tileOf(x[1]), findsNothing, reason: '⛔premise: tab y is shown');
      putKeyOn(tester, brushGroupActionId(brush, groupOf(tester, x.first)));

      await press(tester);

      expect(
        panel(tester).selectedPresetId,
        x[1],
        reason: '「그 그룹에서 마지막으로 고른 브러시」',
      );
      expect(tileOf(x[1]), findsOneWidget, reason: 'the tab itself is shown');
      expect(tileOf(y.first), findsNothing);
    });

    // 🗣️F-319: 「브러시를 단축키로 바꿀때, 단축키누르면 브러시그룹이 바껴야하는데
    // 안바뀜 … 브러시그룹을 단축키 지정했을때 얘기임」 · 「이상한건 됫다가
    // 말았다가 함」.
    //
    // 🔬Measured on the code before (2026-10-08, the two cases below run
    // there): with the eraser never taken up they pass; once it HAS been,
    // the key moves the hand and the tab on screen stays (the first), and
    // the eraser then comes to hand on a tab its brush is not in (the
    // second). The tool library keeps a panel alive for each paint tool, and
    // a group's key reached 「the panel」 through one slot the panel mounted
    // LAST had taken — the eraser's, from the moment it was first taken up.
    testWidgets('🚨a group\'s key turns the tab ON SCREEN, though the '
        'eraser\'s library has been on screen since the app opened', (
      tester,
    ) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await takeUp(tester, 'eraser');
      await takeUp(tester, 'brush');
      await tapTabOf(tester, y.first);
      expect(tileOf(x.first), findsNothing, reason: '⛔premise: tab y shown');
      putKeyOn(tester, brushGroupActionId(brush, groupOf(tester, x.first)));

      await press(tester);

      expect(panel(tester).selectedPresetId, x.first, reason: 'the hand');
      expect(tileOf(x.first), findsOneWidget, reason: 'and the tab shown');
      expect(tileOf(y.first), findsNothing);
    });

    testWidgets('🚨…and it turns no tab of the eraser\'s library: the eraser '
        'comes to hand showing the tab of its own brush', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await takeUp(tester, 'eraser');
      final erasers = panel(tester).selectedPresetId!;
      expect(tileOf(erasers), findsOneWidget, reason: '⛔premise');
      expect(x, isNot(contains(erasers)), reason: '⛔premise');
      await takeUp(tester, 'brush');
      await tapTabOf(tester, y.first);
      putKeyOn(tester, brushGroupActionId(brush, groupOf(tester, x.first)));
      await press(tester);

      await takeUp(tester, 'eraser');

      expect(panel(tester).selectedPresetId, erasers, reason: 'its brush');
      expect(tileOf(erasers), findsOneWidget, reason: 'and its tab');
      expect(tileOf(x.first), findsNothing);
    });

    testWidgets('🚨a tool has its own keys: the eraser\'s brings the ERASER '
        'to hand with its brush, the brush tool\'s the brush tool — and '
        'each leaves the other\'s brush alone', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      expect(toolInHand(tester), brush, reason: '⛔premise');

      // The eraser's key, with the brush tool in hand.
      putKeyOn(tester, brushPresetActionId(eraser, y[1]));
      await press(tester);
      expect(toolInHand(tester), eraser);
      expect(panel(tester).tool, eraser, reason: 'the eraser\'s library');
      expect(panel(tester).selectedPresetId, y[1]);
      expect(tileOf(y[1]), findsOneWidget, reason: 'and its tab is shown');

      // The brush tool's key, with the eraser in hand.
      putKeyOn(tester, brushPresetActionId(brush, y.first));
      await press(tester);
      expect(toolInHand(tester), brush);
      expect(panel(tester).tool, brush);
      expect(panel(tester).selectedPresetId, y.first);

      await takeUp(tester, 'eraser');
      expect(
        panel(tester).selectedPresetId,
        y[1],
        reason: 'the eraser holds what ITS key gave it',
      );
    });

    // F-181's law, for a key: a tool taken up holding a brush EQUAL to the
    // one in hand is not a bare switch back to what it had banked.
    testWidgets('🚨a tool brought to hand by a key holds THAT brush — though '
        'it is the very brush the tool in hand holds', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await takeUp(tester, 'eraser');
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      await takeUp(tester, 'brush');
      await tapTabOf(tester, y.first);
      await pickInView(tester, y[1]);
      putKeyOn(tester, brushPresetActionId(eraser, y[1]));

      await press(tester);

      expect(toolInHand(tester), eraser);
      expect(
        panel(tester).selectedPresetId,
        y[1],
        reason: 'not ${x[1]}, the brush the eraser had put down',
      );
    });

    testWidgets('🚨the eraser\'s group key hands the eraser what the ERASER '
        'last held there — and brings it to hand', (tester) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      // The eraser last held x[1] in tab x, and holds a brush of tab y.
      await takeUp(tester, 'eraser');
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      await tapTabOf(tester, y.first);
      // The brush tool held x's first there, and is in hand.
      await takeUp(tester, 'brush');
      await tapTabOf(tester, x.first);
      await tapTabOf(tester, y.first);
      putKeyOn(tester, brushGroupActionId(eraser, groupOf(tester, x.first)));

      await press(tester);

      expect(toolInHand(tester), eraser);
      expect(
        panel(tester).selectedPresetId,
        x[1],
        reason: '「도구마다 따로」 — not ${x.first}, the brush tool\'s',
      );
      expect(tileOf(x[1]), findsOneWidget, reason: 'the tab is shown');
    });

    // 「안에 있으면 그대로」 asks where the brush of the tool PRESSED FOR is —
    // not the one in hand.
    testWidgets('🚨the eraser\'s group key enters the group though the brush '
        'in hand is already in it', (tester) async {
      await pumpWithPresets(tester);
      final [x, ...] = otherTabsWithAtLeast(tester, 2);
      await takeUp(tester, 'eraser');
      final erasers = panel(tester).selectedPresetId!;
      expect(x, isNot(contains(erasers)), reason: '⛔premise');
      await takeUp(tester, 'brush');
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      putKeyOn(tester, brushGroupActionId(eraser, groupOf(tester, x.first)));

      await press(tester);

      expect(toolInHand(tester), eraser);
      expect(
        panel(tester).selectedPresetId,
        x.first,
        reason: 'the eraser never held one there: the group\'s first — not '
            '$erasers, which it held outside it',
      );
    });

    testWidgets('a group\'s tab wears its key, as every button does — the '
        'key of the tool whose library it is', (tester) async {
      await pumpWithPresets(tester);
      final [x, ...] = otherTabsWithAtLeast(tester, 2);
      final group = groupOf(tester, x.first);
      final name = panel(tester).groups
          .firstWhere((candidate) => candidate.id == group)
          .name;
      final tab = find.byKey(
        ValueKey<String>('brush-preset-tab-${group.value}'),
      );
      String? tipOfTab() => tester
          .widget<AppTooltip>(
            find.ancestor(of: tab, matching: find.byType(AppTooltip)).first,
          )
          .message;
      expect(tipOfTab(), name);

      putKeyOn(tester, brushGroupActionId(brush, group));
      await tester.pump();
      expect(tipOfTab(), '$name (K)');
      // 🗣️F-319: 「이름이 있는곳은 흐린글자로 표시임」.
      expect(
        find.descendant(of: tab, matching: find.text('K')),
        findsOneWidget,
        reason: 'and after its name, where the name shows',
      );

      await takeUp(tester, 'eraser');
      expect(tipOfTab(), name, reason: 'the eraser\'s tab is another row');
      expect(find.descendant(of: tab, matching: find.text('K')), findsNothing);
    });

    testWidgets('with a tool in hand that paints nothing, a key brings ITS '
        'tool to hand: the brush tool holding what it last held in the '
        'group, its own tab\'s key too — and the eraser\'s key the eraser', (
      tester,
    ) async {
      await pumpWithPresets(tester);
      final [x, y, ...] = otherTabsWithAtLeast(tester, 2);
      await tapTabOf(tester, x.first);
      await pickInView(tester, x[1]);
      await tapTabOf(tester, y.first);
      final groupX = groupOf(tester, x.first);
      final groupY = groupOf(tester, y.first);
      putKeyOn(tester, brushGroupActionId(brush, groupX));

      await takeUp(tester, 'select');
      expect(toolInHand(tester), CanvasTool.select, reason: '⛔premise');
      await press(tester);

      expect(toolInHand(tester), brush);
      expect(panel(tester).selectedPresetId, x[1]);

      // The hand outside again, and the key of the tab its brush shows in:
      // the tool comes to hand holding exactly what it holds.
      await tapTabOf(tester, y.first);
      putKeyOn(tester, brushGroupActionId(brush, groupY));
      await takeUp(tester, 'select');
      await press(tester);
      expect(toolInHand(tester), brush);
      expect(panel(tester).selectedPresetId, y.first);

      putKeyOn(tester, brushGroupActionId(eraser, groupX));
      await takeUp(tester, 'select');
      await press(tester);
      expect(toolInHand(tester), eraser);
      expect(
        panel(tester).selectedPresetId,
        x.first,
        reason: 'the eraser never held one there: the group\'s first',
      );
    });

    // 「브러시는 항상 선택된그룹/브러시 를 보여줌」 has one exception, and it
    // ends with the hand: a group with no brush to take up can only be
    // LOOKED INTO.
    testWidgets('🚨a group with no brush is looked into — by a tap or by its '
        'key — until the hand is another: another tool, the held group\'s '
        'key, the held brush\'s key', (tester) async {
      await pumpWithPresets(tester);
      final [x, ...] = otherTabsWithAtLeast(tester, 2);
      // The eraser holds a brush of its own from the start. ⚠️Taken up for
      // the first time later, it would take the brush in hand — and the
      // delete at the end would then hand BOTH tools the brush beside it,
      // passing the eraser through the hand on the way: a tool changed,
      // where the case is a brush changed.
      await takeUp(tester, 'eraser');
      await takeUp(tester, 'brush');
      await tapTabOf(tester, x.first);
      final nothing = await anEmptyGroup(tester);
      expect(tileOf(x.first), findsOneWidget, reason: '⛔premise: x shown');

      // A tap looks into it; the hand holds what it held.
      await tapTab(tester, nothing);
      expect(onScreen(tester), isEmpty, reason: 'the empty tab');
      expect(panel(tester).selectedPresetId, x.first);

      // Another tool comes to hand, and the brush tool back: no look left.
      await takeUp(tester, 'eraser');
      expect(onScreen(tester), isNotEmpty, reason: 'the eraser\'s own tab');
      await takeUp(tester, 'brush');
      expect(tileOf(x.first), findsOneWidget, reason: 'the held brush\'s');

      // Its key looks into it too.
      putKeyOn(tester, brushGroupActionId(brush, nothing));
      await press(tester);
      expect(onScreen(tester), isEmpty);
      expect(panel(tester).selectedPresetId, x.first);

      // The key of the group the hand is in: the hand stays, the tab shows.
      putKeyOn(tester, brushGroupActionId(brush, groupOf(tester, x.first)));
      await press(tester);
      expect(tileOf(x.first), findsOneWidget);
      expect(panel(tester).selectedPresetId, x.first);

      // And the key of the very brush in hand.
      await tapTab(tester, nothing);
      expect(onScreen(tester), isEmpty, reason: '⛔premise');
      putKeyOn(tester, brushPresetActionId(brush, x.first));
      await press(tester);
      expect(tileOf(x.first), findsOneWidget);

      // And a hand changed by no press at all: the brush in hand deleted,
      // the hand takes up the one beside it (F-250) — and the library shows
      // that.
      await tapTab(tester, nothing);
      expect(onScreen(tester), isEmpty, reason: '⛔premise');
      panel(tester).onPresetDeleted!(x.first);
      await tester.pumpAndSettle();
      expect(panel(tester).selectedPresetId, x[1], reason: '⛔premise');
      expect(tileOf(x[1]), findsOneWidget);
    });

    testWidgets('the ERASER\'s key on a group with no brush brings the '
        'eraser to hand, holding what it holds, and looks into the group', (
      tester,
    ) async {
      await pumpWithPresets(tester);
      await takeUp(tester, 'eraser');
      final erasers = panel(tester).selectedPresetId!;
      await takeUp(tester, 'brush');
      final nothing = await anEmptyGroup(tester);
      putKeyOn(tester, brushGroupActionId(eraser, nothing));

      await press(tester);

      expect(toolInHand(tester), eraser);
      expect(panel(tester).selectedPresetId, erasers);
      expect(onScreen(tester), isEmpty, reason: 'the empty tab is shown');

      await takeUp(tester, 'brush');
      expect(onScreen(tester), isNotEmpty, reason: 'and it ends with the hand');
    });
  });
}
