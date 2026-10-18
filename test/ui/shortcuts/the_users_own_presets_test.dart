import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/project_scratch_folder.dart';

/// 🗣️I-107-Q1 (유저 2026-10-18, 「기타」): 「프리셋 리스트 추가/삭제
/// 가능하게해서 사용자 입맛대로 추가해서 설정가능하고, 가져올땐 새
/// 프리셋으로서 등록」. ⚠️The details are asked on the board (I-107-Q3) and
/// built as its recommendation (a): the three the app ships stay, a new one
/// is the layout in use copied, and its name is given when it is made.
void main() {
  late EditorShortcutBindings bindings;

  setUp(() => bindings = EditorShortcutBindings());
  tearDown(() => bindings.dispose());

  /// [actionId]'s live keys as the window writes them on a PC.
  List<String> keysOf(String actionId, [EditorShortcutBindings? held]) => [
    for (final key in (held ?? bindings).activatorsFor(actionId))
      singleActivatorLabel(key, TargetPlatform.windows),
  ];

  const f9 = SingleActivator(LogicalKeyboardKey.f9);
  const f2 = SingleActivator(LogicalKeyboardKey.f2);

  test('⛔fixture premise: what the TVPaint preset holds', () {
    bindings.setPreset(ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
    expect(keysOf(EditorActionIds.cutNew), isNot(['F9']));
  });

  test('＋ copies the layout in use — its keys and what was recorded over '
      'them — into a preset of the user\'s that comes into use', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.cutNew, const [f9]);

    final mine = bindings.addPreset('Mine');

    expect(bindings.preset, mine);
    expect(bindings.userPresets, [mine]);
    expect((mine.name, mine.base), ('Mine', ShortcutPreset.tvpaint));
    expect(keysOf(EditorActionIds.cutNew), ['F9']);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
    expect(
      bindings.isOverridden(EditorActionIds.cutNew),
      isFalse,
      reason: 'F9 is a key it was made with',
    );
  });

  test('what is recorded under a preset of the user\'s stays with it — the '
      'preset it was copied from is left as it was', () {
    bindings
      ..setPreset(ShortcutPreset.tvpaint)
      ..setActivators(EditorActionIds.cutNew, const [f9]);
    final mine = bindings.addPreset('Mine');

    bindings.setActivators(EditorActionIds.undo, const [f2]);
    bindings.setPreset(ShortcutPreset.tvpaint);

    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
    expect(keysOf(EditorActionIds.cutNew), ['F9']);
    bindings.setPreset(mine);
    expect(keysOf(EditorActionIds.undo), ['F2']);
  });

  test('＋ over a preset of the user\'s copies all it holds', () {
    final first = bindings.addPreset('First');
    bindings.setActivators(EditorActionIds.undo, const [f2]);

    final second = bindings.addPreset('Second');

    expect(second.base, first.base);
    expect(keysOf(EditorActionIds.undo), ['F2']);
    expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
  });

  test('the window\'s reset takes a preset of the user\'s back to the keys '
      'it was made with', () {
    bindings.setActivators(EditorActionIds.cutNew, const [f9]);
    bindings.addPreset('Mine');
    bindings.setActivators(EditorActionIds.cutNew, const [f2]);

    bindings.resetAll();

    expect(keysOf(EditorActionIds.cutNew), ['F9']);
  });

  test('a deleted preset takes what was recorded under it along; deleted '
      'in use, the preset it stood on comes into use', () {
    bindings.setPreset(ShortcutPreset.tvpaint);
    final kept = bindings.addPreset('Kept');
    final gone = bindings.addPreset('Gone');
    bindings.setActivators(EditorActionIds.undo, const [f2]);

    bindings.deletePreset(gone);

    expect(bindings.userPresets, [kept]);
    expect(bindings.preset, ShortcutPreset.tvpaint);
    expect(keysOf(EditorActionIds.undo), ['Ctrl+Z', 'U']);
  });

  test('a preset deleted while another is in use leaves that one in '
      'use', () {
    final gone = bindings.addPreset('Gone');
    final kept = bindings.addPreset('Kept');

    bindings.deletePreset(gone);

    expect(bindings.preset, kept);
    expect(bindings.userPresets, [kept]);
  });

  test('a new preset never takes the id of one still on the list', () {
    final first = bindings.addPreset('A');
    final second = bindings.addPreset('B');
    bindings.deletePreset(first);

    final third = bindings.addPreset('C');

    expect(third.id, isNot(second.id));
  });

  group('on disk', () {
    late String path;

    setUp(() async {
      final directory = await Directory.systemTemp.createTemp('users-presets');
      deleteAfterSessionEnds(directory);
      path = '${directory.path}/overrides.json';
    });

    Future<EditorShortcutBindings> restored() async {
      final held = EditorShortcutBindings(
        store: ShortcutSettingsStore(filePath: path),
      );
      addTearDown(held.dispose);
      await held.restore();
      return held;
    }

    test('the user\'s presets come back: their names, the keys they were '
        'made with, what was recorded under them, and the one in '
        'use', () async {
      final saving = EditorShortcutBindings(
        store: ShortcutSettingsStore(filePath: path),
      );
      addTearDown(saving.dispose);
      saving
        ..setPreset(ShortcutPreset.tvpaint)
        ..setActivators(EditorActionIds.cutNew, const [f9])
        ..addPreset('Made')
        ..setActivators(EditorActionIds.undo, const [f2])
        ..addPreset('In use');
      await saving.pendingPersist;

      final again = await restored();

      expect([for (final preset in again.userPresets) preset.name], [
        'Made',
        'In use',
      ]);
      expect(again.preset, again.userPresets.last);
      again.setPreset(again.userPresets.first);
      expect(keysOf(EditorActionIds.cutNew, again), ['F9']);
      expect(keysOf(EditorActionIds.undo, again), ['F2']);
      expect(again.isOverridden(EditorActionIds.cutNew), isFalse);
      expect(again.isOverridden(EditorActionIds.undo), isTrue);
      again.resetAll();
      expect(keysOf(EditorActionIds.undo, again), ['Ctrl+Z', 'U']);
    });

    test('a preset of the user\'s that names one no build ships stands on '
        'Anicel\'s, and keeps its own keys', () async {
      File(path).writeAsStringSync(
        jsonEncode({
          'version': ShortcutSettingsStore.version,
          'preset': 'user-1',
          'overrides': <String, Object?>{},
          'presets': [
            {
              'id': 'user-1',
              'name': 'From later',
              'base': 'aProgramNotYetShipped',
              'keys': {
                EditorActionIds.cutNew: [singleActivatorToJson(f9)],
              },
            },
          ],
        }),
      );

      final again = await restored();

      expect(again.preset, again.userPresets.single);
      expect(again.userPresets.single.base, ShortcutPreset.anicel);
      expect(keysOf(EditorActionIds.cutNew, again), ['F9']);
    });
  });

  group('the shortcut window\'s list', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShortcutSettingsDialog(bindings: bindings)),
        ),
      );
      await tester.pump();
    }

    Finder byKey(String key) => find.byKey(ValueKey<String>(key));

    List<PanelFlyoutEntry> entries(WidgetTester tester) => tester
        .widget<PanelFlyoutButton>(byKey('shortcut-preset'))
        .entriesBuilder();

    Future<void> openList(WidgetTester tester) async {
      await tester.tap(byKey('shortcut-preset'));
      await tester.pumpAndSettle();
    }

    testWidgets('the three the app ships, then a rule and the user\'s own '
        '— a delete on each of those alone', (tester) async {
      final mine = bindings.addPreset('Mine');
      await pump(tester);

      final shown = entries(tester);
      final rows = shown.whereType<PanelFlyoutItem>().toList();
      expect([for (final row in rows) row.keyValue], [
        for (final preset in ShortcutPreset.values)
          'shortcut-preset-${preset.name}',
        'shortcut-preset-${mine.id}',
      ]);
      expect([for (final row in rows) row.action != null], [
        false,
        false,
        false,
        true,
      ]);
      expect(
        shown.indexWhere((entry) => entry is PanelFlyoutDivider),
        shown.indexOf(rows.last) - 1,
      );
      expect(rows.last.selected, isTrue);
      expect(
        tester.widget<PanelFlyoutButton>(byKey('shortcut-preset')).label,
        'Mine',
      );
    });

    testWidgets('no rule stands under the three while the user has none of '
        'their own', (tester) async {
      await pump(tester);

      expect(entries(tester).whereType<PanelFlyoutDivider>(), isEmpty);
    });

    testWidgets('the ＋ asks the name, and the layout in use copied under '
        'it comes into use', (tester) async {
      bindings
        ..setPreset(ShortcutPreset.tvpaint)
        ..setActivators(EditorActionIds.cutNew, const [f9]);
      await pump(tester);
      await openList(tester);

      await tester.tap(byKey('shortcut-preset-add'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('shortcut-preset-new-text-field'), 'Mine');
      await tester.tap(byKey('shortcut-preset-new-ok-button'));
      await tester.pumpAndSettle();

      final mine = bindings.preset as UserShortcutPreset;
      expect((mine.name, mine.base), ('Mine', ShortcutPreset.tvpaint));
      expect(keysOf(EditorActionIds.cutNew), ['F9']);
    });

    testWidgets('a preset of the user\'s goes only once the user says '
        'so', (tester) async {
      final mine = bindings.addPreset('Mine');
      await pump(tester);
      await openList(tester);

      await tester.tap(byKey('shortcut-preset-${mine.id}-delete'));
      await tester.pumpAndSettle();
      expect(bindings.userPresets, [mine], reason: 'asked, not yet answered');
      await tester.tap(byKey('shortcut-preset-delete-cancel-button'));
      await tester.pumpAndSettle();
      expect(bindings.userPresets, [mine]);

      await openList(tester);
      await tester.tap(byKey('shortcut-preset-${mine.id}-delete'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('shortcut-preset-delete-confirm-button'));
      await tester.pumpAndSettle();

      expect(bindings.userPresets, isEmpty);
      expect(bindings.preset, ShortcutPreset.clipStudio);
    });
  });
}
