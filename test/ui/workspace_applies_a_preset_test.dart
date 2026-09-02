import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// APPLYING A PRESET FROM THE WORKSPACE — MEASURED.
///
/// The preset panel has its own tests, with a callback in place of the
/// workspace. The workspace's half — taking the preset into the brush tool
/// and marking it active in the library — was not measured: when the
/// presets were carved out of the workspace State (2026-09-02) the
/// adversarial check made `_applyPreset` a no-op and every preset test
/// stayed green. So this taps a preset in the real panel and reads the
/// active preset the panel is then handed back.
void main() {
  testWidgets('tapping a preset makes it the active one', (tester) async {
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
    // The loads are real file IO started on the fake clock: each step
    // completes in real time (a runAsync window) and its continuation runs
    // on the fake one (a pump). Alternate until the panel has presets.
    for (var tries = 0; tries < 40; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final loaded =
          find.byType(BrushPresetPanel).evaluate().isNotEmpty &&
          tester
              .widget<BrushPresetPanel>(find.byType(BrushPresetPanel).first)
              .presets
              .isNotEmpty;
      if (loaded) {
        break;
      }
    }
    await tester.pumpAndSettle();

    BrushPresetPanel panel() =>
        tester.widget<BrushPresetPanel>(find.byType(BrushPresetPanel).first);
    BrushPresetId? active() => panel().selectedPresetId;

    // Any preset the panel is showing that is not the active one — the
    // library's contents are the product's, not this test's.
    Finder tileOf(BrushPresetId id) =>
        find.byKey(ValueKey<String>('brush-preset-entry-${id.value}'));
    final target = panel().presets.firstWhere(
      (preset) =>
          preset.id != active() && tileOf(preset.id).evaluate().isNotEmpty,
      orElse: () => throw StateError(
        '⛔premise: no other preset is on screen — active ${active()}, '
        'presets ${panel().presets.map((p) => p.id.value).toList()}',
      ),
    );
    expect(active(), isNot(target.id), reason: 'premise — not active yet');

    await tester.tap(tileOf(target.id));
    await tester.pumpAndSettle();

    expect(
      active(),
      target.id,
      reason: 'the workspace applied the preset and marked it active',
    );
  });
}
