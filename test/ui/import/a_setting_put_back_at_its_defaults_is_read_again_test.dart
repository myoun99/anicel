import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/handed_files.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/services/persistence/settings_room_file.dart'
    show settingsRoomPath;
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/wait_window.dart';

/// 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 — a settings file that
/// holds a setting at its defaults puts the defaults back, and what reads
/// it again reads them: through the whole app, from the file handed in to
/// the workspace that stands as it stood at first.
///
/// The import window's own tests hand it a stand-in for what puts the
/// settings in place; this is the workspace's own, which no test reached
/// when the defaults began to travel (10-30): the arrangement put back at
/// the factory one, and the export window's settings read again.
void main() {
  Finder region() =>
      find.byKey(const ValueKey<String>('floating-bottom-region'));

  testWidgets('a file holding the layout and the export window at their '
      'defaults puts both back — the region stands open again, the export '
      'window opens on its defaults', (tester) async {
    // The room's own file, so what the import takes out of the room is what
    // the workspace reads again.
    final store = WorkspaceLayoutStore(
      filePath: settingsRoomPath('workspace_layout.json'),
    );
    final folder = Directory.systemTemp.createTempSync('qa_put_back_');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path.replaceAll(r'\', '/')}/Mine.anisettings';
    File(path).writeAsStringSync(
      encodeSettingsFile(
        const {},
        atDefaults: {'workspace_layout.json', 'export_settings.json'},
      ),
    );
    AppExport.settings.value = AppExportSettings(presetsDrawerOpen: false);
    addTearDown(() => AppExport.settings.value = AppExportSettings());
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(layoutStore: store),
      ),
    );
    await tester.pumpAndSettle();
    final open = tester.getRect(region()).height;

    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    // The save is debounced 800 ms behind the last change.
    await tester.pump(const Duration(milliseconds: 900));
    final saved = await settleAsync(
      tester,
      () async =>
          (await tester.runAsync(store.load))?['bottomCollapsed'] == true,
    );
    expect(saved, isTrue, reason: 'CONTROL: the fold reached the room');
    expect(tester.getRect(region()).height, lessThan(open), reason: 'CONTROL');

    // As the platform hands the running app a file — a double-click on it.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      HandedFiles.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(HandedFiles.openMethod, [path]),
      ),
      (_) {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ImportDialog), findsOneWidget, reason: 'CONTROL');
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);

    await settleAsync(
      tester,
      () =>
          (tester.getRect(region()).height - open).abs() < 0.5 &&
          AppExport.settings.value == AppExportSettings(),
    );
    expect(
      tester.getRect(region()).height,
      closeTo(open, 0.5),
      reason: 'no arrangement in the room is the factory one, read again',
    );
    expect(
      AppExport.settings.value,
      AppExportSettings(),
      reason: 'the export window opens on its defaults, not on this run\'s',
    );
  });
}
