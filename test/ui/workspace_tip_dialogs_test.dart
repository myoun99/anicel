import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile, XTypeGroup;
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSelectorPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// THE WORKSPACE'S TIP AND BRUSH-FILE DIALOGS — MEASURED.
///
/// The tip picker and the preset panel hand the workspace a callback and
/// have their own tests. The workspace's half — asking for a name and
/// renaming, importing and putting the result in a notice — was not
/// measured before the two importers and the two name prompts were folded
/// into one each (round 8). These drive the real callbacks the panels are
/// handed and read the workspace's answer back off the tree.
void main() {
  late Directory directory;
  late BrushTipLibraryService tips;
  late BrushPresetFileService presets;
  late FileSelectorPlatform realFileDialogs;

  /// The real workspace on a temp directory, with the tool settings group
  /// opened so [ToolSettingsPanel] is on screen. Real file IO only inside
  /// runAsync — the testWidgets clock is fake, and an awaited read never
  /// completes on it.
  Future<void> pumpWorkspace(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(presetFileService: presets, tipLibraryService: tips),
      ),
    );
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
    final settingsGroup = EditorWorkspace.railGroupId(right: false, slot: 2);
    await tester.tap(find.byKey(ValueKey<String>('rail-group-$settingsGroup')));
    await tester.pumpAndSettle();
    expect(find.byType(ToolSettingsPanel), findsOneWidget, reason: 'premise');
  }

  ToolSettingsPanel toolSettings(WidgetTester tester) =>
      tester.widget<ToolSettingsPanel>(find.byType(ToolSettingsPanel));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-tip-dialogs');
    presets = BrushPresetFileService(
      filePath: '${directory.path}/brush_presets.json',
    );
    tips = BrushTipLibraryService(directoryPath: '${directory.path}/tips');
    realFileDialogs = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _NoFileDialog();
  });

  tearDown(() async {
    FileSelectorPlatform.instance = realFileDialogs;
    await directory.delete(recursive: true);
  });

  testWidgets('renaming a tip asks for the name in a window and renames '
      'the library entry with the TRIMMED answer', (tester) async {
    await tester.runAsync(() async {
      final entry = await tips.writeImage(
        BrushTipMask(
          id: 'user-tip',
          size: 8,
          alpha: Uint8List.fromList(List<int>.filled(64, 200)),
        ),
        name: 'Old name',
      );
      await tips.saveIndex([entry]);
    });
    await pumpWorkspace(tester);
    final tip = toolSettings(tester).tips.firstWhere((t) => !t.builtIn);
    expect(tip.name, 'Old name', reason: 'premise: the user tip loaded');

    toolSettings(tester).onRenameTip!(tip);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('rename-tip-dialog')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-tip-name-field')),
      '  New name  ',
    );
    await tester.tap(find.text(AppText.strings.commonRename).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('rename-tip-dialog')),
      findsNothing,
    );
    expect(
      toolSettings(tester).tips.firstWhere((t) => t.id == tip.id).name,
      'New name',
    );
  });

  testWidgets('an EMPTY answer leaves the name alone, silently', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final entry = await tips.writeImage(
        BrushTipMask(
          id: 'user-tip',
          size: 8,
          alpha: Uint8List.fromList(List<int>.filled(64, 200)),
        ),
        name: 'Old name',
      );
      await tips.saveIndex([entry]);
    });
    await pumpWorkspace(tester);
    final tip = toolSettings(tester).tips.firstWhere((t) => !t.builtIn);

    toolSettings(tester).onRenameTip!(tip);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-tip-name-field')),
      '   ',
    );
    await tester.tap(find.text(AppText.strings.commonRename).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('rename-tip-dialog')),
      findsNothing,
    );
    expect(
      toolSettings(tester).tips.firstWhere((t) => t.id == tip.id).name,
      'Old name',
    );
  });

  testWidgets('a tip import that fails puts the message in a notice', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    // The file dialog under the library cannot open (swapped in setUp), so
    // the library reports — the workspace's job is to show that.
    toolSettings(tester).onTipImportRequested!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-notice-close')),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.commonNotice), findsOneWidget);
  });

  testWidgets('a brush-file import that fails puts the message in a '
      'notice', (tester) async {
    await pumpWorkspace(tester);
    tester
        .widget<BrushPresetPanel>(find.byType(BrushPresetPanel).first)
        .onPresetImportRequested!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-notice-close')),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.commonNotice), findsOneWidget);
  });
}

/// The layer UNDER the importers: a file dialog that cannot open, which is
/// what both libraries turn into the message the workspace must show.
class _NoFileDialog extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => throw StateError('no file dialog under test');
}
