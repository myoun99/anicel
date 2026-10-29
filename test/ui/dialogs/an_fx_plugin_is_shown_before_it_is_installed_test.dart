import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:typed_data';

import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/dialogs/fx_plugin_install_flow.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/settle_async.dart';

/// I-132: an fx plugin's file opened like any other is shown to the person
/// as what it says of itself — who made it, which version, the version it
/// replaces — and, a WARNING, that a native build of it runs outside the
/// sandbox; only their yes installs it.
void main() {
  final description = jsonEncode({
    'spec': 1,
    'id': 'com.example.invert',
    'name': 'Invert',
    'vendor': 'Example Studio',
    'version': '1.2.0',
    'can': ['cpu'],
    'params': <Object?>[],
  });

  Uint8List fileOf({required bool native}) {
    final archive = Archive()
      ..add(ArchiveFile.bytes('plugin.wasm', utf8.encode(description)));
    final entry = fxPluginNativeEntryFor(Abi.current());
    if (native && entry != null) {
      archive.add(ArchiveFile.bytes(entry, [1, 2, 3]));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  late _LibraryInMemory library;
  late InstalledFxPlugins plugins;

  setUp(() {
    library = _LibraryInMemory();
    plugins = InstalledFxPlugins(
      service: library,
      describe: (wasm) => (text: utf8.decode(wasm), refusal: null),
    );
  });
  tearDown(() => plugins.dispose());

  const window = ValueKey<String>('install-fx-plugin-dialog');

  /// Opens [bytes] through the flow, answers the question with [answer]
  /// and gives back what the flow said.
  Future<String?> open(
    WidgetTester tester,
    Uint8List bytes, {
    required String answer,
    void Function(String message)? asked,
  }) async {
    var finished = false;
    String? said;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                said = await installFxPluginFile(
                  context,
                  plugins,
                  'Invert.anifx',
                  bytes,
                );
                finished = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settleAsync(
      tester,
      () => finished,
      everyFrame: () async {
        await tester.pumpAndSettle();
        if (find.byKey(window).evaluate().isNotEmpty) {
          asked?.call(
            tester
                .widget<AppConfirmDialog>(find.byType(AppConfirmDialog))
                .message,
          );
          await tester.tap(find.byKey(ValueKey<String>(answer)));
          await tester.pumpAndSettle();
        }
      },
    );
    expect(finished, isTrue);
    return said;
  }

  testWidgets('the question says who made which version, and a yes '
      'installs it', (tester) async {
    final strings = AppText.strings;
    final questions = <String>[];
    final said = await open(
      tester,
      fileOf(native: false),
      answer: 'install-fx-plugin-confirm-button',
      asked: questions.add,
    );
    expect(questions, [
      strings.fxPluginInstallBody('Invert', 'Example Studio', '1.2.0'),
    ]);
    expect(said, strings.fxPluginInstalled('Invert'));
    expect([for (final p in plugins.plugins) p.description.id], [
      'com.example.invert',
    ]);
  });

  testWidgets('a native build is warned of, and a plugin installed again '
      'names the version it replaces', (tester) async {
    final strings = AppText.strings;
    await open(
      tester,
      fileOf(native: false),
      answer: 'install-fx-plugin-confirm-button',
    );
    final questions = <String>[];
    await open(
      tester,
      fileOf(native: true),
      answer: 'install-fx-plugin-confirm-button',
      asked: questions.add,
    );
    final native = fxPluginNativeEntryFor(Abi.current()) != null;
    expect(questions.single, contains(strings.fxPluginReplaces('1.2.0')));
    expect(
      questions.single.contains(strings.fxPluginRunsNatively),
      native,
      reason: 'a device with native builds is warned of one',
    );
  });

  testWidgets('a no installs nothing and says nothing', (tester) async {
    final said = await open(
      tester,
      fileOf(native: false),
      answer: 'install-fx-plugin-cancel-button',
    );
    expect(said, isNull);
    expect(plugins.plugins, isEmpty);
    expect(library.kept, isEmpty);
  });

  testWidgets('what is no plugin is said so, with no question', (
    tester,
  ) async {
    final questions = <String>[];
    final said = await open(
      tester,
      Uint8List.fromList([1, 2, 3]),
      answer: 'install-fx-plugin-confirm-button',
      asked: questions.add,
    );
    expect(questions, isEmpty);
    expect(said, AppText.strings.fxPluginUnreadable('Invert.anifx'));
  });
}

/// The library with no disk under it: a widget test's clock finishes no
/// real IO.
class _LibraryInMemory extends FxPluginLibraryService {
  _LibraryInMemory() : super(directoryPath: 'memory');

  final kept = <InstalledFxPlugin>[];
  List<InstalledFxPlugin> index = const [];

  @override
  Future<InstalledFxPlugin> keep(
    FxPluginBundle bundle,
    FxPluginDescription description, {
    Abi? abi,
  }) async {
    final plugin = (
      wasm: 'k${kept.length}-${description.id}.wasm',
      native: bundle.native == null ? null : 'k${kept.length}-n.dll',
      description: description,
    );
    kept.add(plugin);
    return plugin;
  }

  @override
  Future<void> saveIndex(List<InstalledFxPlugin> plugins) async =>
      index = plugins;

  @override
  Future<List<InstalledFxPlugin>> loadIndex() async => index;

  @override
  Future<void> delete(InstalledFxPlugin plugin) async {}
}
