import 'dart:typed_data';

import 'package:anicel/src/services/fx_plugins/fx_plugin_bundle.dart';
import 'package:anicel/src/services/fx_plugins/fx_plugin_library_service.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/dialogs/fx_plugin_install_flow.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fx_plugin_file.dart';
import '../../helpers/settle_async.dart';

/// I-132: an fx plugin's file opened like any other is shown to the person
/// as what it says of itself — who made it, which version, the version it
/// replaces; only their yes installs it.
void main() {
  Uint8List fileOf({String version = '1.2.0'}) => fxPluginFileOf(
    fxPluginDescriptionOf(
      'com.example.invert',
      name: 'Invert',
      vendor: 'Example Studio',
      version: version,
    ),
    source: '// invert $version\n',
  );

  late _LibraryInMemory library;
  late InstalledFxPlugins plugins;

  setUp(() {
    library = _LibraryInMemory();
    plugins = InstalledFxPlugins(
      service: library,
      // The device is not asked here: opening WGSL on the GPU is
      // a_gpu_plugin_opens_and_runs_on_the_engine_test's.
      check: (_) async => (opened: null, refusal: null),
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
      fileOf(),
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

  testWidgets('a plugin installed again names the version it replaces', (
    tester,
  ) async {
    final strings = AppText.strings;
    await open(
      tester,
      fileOf(),
      answer: 'install-fx-plugin-confirm-button',
    );
    final questions = <String>[];
    await open(
      tester,
      fileOf(version: '1.3.0'),
      answer: 'install-fx-plugin-confirm-button',
      asked: questions.add,
    );
    expect(questions.single, contains(strings.fxPluginReplaces('1.2.0')));
  });

  testWidgets('a no installs nothing and says nothing', (tester) async {
    final said = await open(
      tester,
      fileOf(),
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
  Future<InstalledFxPlugin> keep(FxPluginBundle bundle) async {
    final plugin = (
      source: 'k${kept.length}-${bundle.description.id}.wgsl',
      description: bundle.description,
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
