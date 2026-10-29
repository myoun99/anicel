import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import 'package:anicel/src/services/persistence/app_ui_scale_store.dart';
import 'package:anicel/src/ui/dialogs/first_run_settings_window.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/ui_scale.dart';

/// A scale kept in memory — a widget test's clock finishes no real write.
class _MemoryScaleStore extends AppUiScaleStore {
  _MemoryScaleStore() : super(filePath: 'unused');

  double? saved;

  @override
  Future<double?> load() async => saved;

  @override
  Future<void> save(double scale) async => saved = scale;
}

final _window = find.byKey(const ValueKey<String>('first-run-settings'));
final _start = find.byKey(const ValueKey<String>('first-run-settings-start'));

/// 🗣️유저 2026-10-29 (I-144): 「초기실행시 게임처럼 ui배율 강조색 커서
/// 골라서 정할수있게」 — one window (Q3: 「한 창에서 한번에 보여주고
/// (나중에 바꿀수있다고 알림)」), the languages in it too, on the machine's
/// first launch only (Q4: 「진짜 기계에서 처음 실행됬을때만」).
void main() {
  late Directory temp;
  late _MemoryScaleStore scaleStore;
  late EditorSessionManager session;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('first_run_');
    scaleStore = _MemoryScaleStore();
    session = EditorSessionManager(
      initialProject: createDefaultProject(),
      appSettings: EditorAppSettings(uiScaleStore: scaleStore),
    );
    AppUiScale.value.value = 0.8;
  });

  tearDown(() {
    session.dispose();
    AppUiScale.value.value = AppUiScale.defaultScale;
    temp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFirstRunSettings(context, session),
              child: const Text('launch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
  }

  testWidgets('🎯one window: the languages, the scale, the accent and the '
      'cursor — Preferences\' own rows — and where they change later', (
    tester,
  ) async {
    await open(tester);
    expect(_window, findsOneWidget);
    for (final row in [
      'settings-program-language',
      'settings-notation-language',
      'settings-ui-scale',
      'settings-drawing-cursor',
    ]) {
      expect(
        find.descendant(of: _window, matching: find.byKey(ValueKey(row))),
        findsOneWidget,
        reason: row,
      );
    }
    expect(
      find.descendant(
        of: _window,
        matching: find.text(AppText.strings.prefsAccent),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _window,
        matching: find.text(AppText.strings.firstRunChangeLater),
      ),
      findsOneWidget,
    );
    // The languages above the rest, so the rest is read in the one picked.
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('settings-program-language')))
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('settings-ui-scale'))).dy,
      ),
    );
  });

  testWidgets('🎯the scale it closes on is kept — the device\'s default a '
      'person saw and went on with', (tester) async {
    expect(scaleStore.saved, isNull);
    await open(tester);
    await tester.tap(_start);
    await tester.pumpAndSettle();
    expect(_window, findsNothing);
    expect(scaleStore.saved, 0.8);
  });

  group('🎯the machine\'s first launch is an empty settings room', () {
    test('no room, or a room with nothing in it, is a first launch', () {
      expect(settingsRoomIsEmpty(containerRoot: temp.path), isTrue);
      Directory('${temp.path}/Settings').createSync();
      expect(settingsRoomIsEmpty(containerRoot: temp.path), isTrue);
    });

    test('⛔a room with anything in it is not — an update never is', () {
      Directory('${temp.path}/Settings').createSync();
      File('${temp.path}/Settings/window.json').writeAsStringSync('{}');
      expect(settingsRoomIsEmpty(containerRoot: temp.path), isFalse);
    });
  });
}
