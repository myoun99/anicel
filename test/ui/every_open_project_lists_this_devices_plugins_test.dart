import 'dart:convert';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/settle_async.dart';

/// I-132: the plugins this device has installed are the device's, not a
/// project's — ONE list for every tab the app has open, read once as the
/// app starts, and kept while any tab is; a session born without it keeps
/// its own and lets it go with itself.
void main() {
  testWidgets('every open project lists the one the app read, and closing '
      'one of them leaves it to the others', (tester) async {
    await tester.runAsync(() async {
      final device = InstalledFxPlugins(
        describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
      );
      final archive = Archive()
        ..add(
          ArchiveFile.bytes(
            'plugin.wasm',
            utf8.encode(
              jsonEncode({
                'spec': 1,
                'id': 'com.example.glow',
                'name': 'Glow',
                'vendor': 'Example',
                'version': '1',
                'can': ['cpu'],
                'params': [],
              }),
            ),
          ),
        );
      await device.install(
        ZipEncoder().encodeBytes(archive),
        confirm: (_, {required native, required replacing}) async => true,
      );
      device.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    final first = projects.active;
    expect(
      await settleAsync(tester, () => first.fxPlugins.plugins.isNotEmpty),
      isTrue,
      reason: 'the app read what the device has',
    );

    final second = projects.open(createDefaultProject());
    await tester.pumpAndSettle();

    expect(second.fxPlugins, same(first.fxPlugins));
    expect(second.fxPlugins.plugins.single.description.id, 'com.example.glow');

    projects.close(first, fresh: createDefaultProject);
    expect(await settleAsync(tester, () => first.disposed), isTrue);
    expect(ChangeNotifier.debugAssertNotDisposed(second.fxPlugins), isTrue);
    expect(second.fxPlugins.plugins, hasLength(1));
  });

  test('a session handed none keeps its own, and lets it go with itself', () {
    final own = EditorSessionManager(initialProject: createDefaultProject());
    final ownList = own.fxPlugins;
    own.dispose();
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(ownList),
      throwsFlutterError,
    );

    final shared = InstalledFxPlugins();
    addTearDown(shared.dispose);
    EditorSessionManager(
      initialProject: createDefaultProject(),
      fxPlugins: shared,
    ).dispose();
    expect(ChangeNotifier.debugAssertNotDisposed(shared), isTrue);
  });
}
