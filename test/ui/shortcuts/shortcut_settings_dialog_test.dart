// THE SHORTCUTS EDITOR: THE SEARCH NARROWS THE LIST, RECORD CAPTURES THE
// NEXT KEY AS THE ACTION'S ONLY BINDING, AND RESET ALL PUTS THE DEFAULTS
// BACK.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, on bindings with no store behind them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show actionLabelOf;
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';
import 'package:anicel/src/ui/shortcuts/touch_shortcuts.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerFoldTwirl;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/named_finders.dart';

void main() {
  Future<EditorShortcutBindings> pump(WidgetTester tester) async {
    final bindings = EditorShortcutBindings();
    addTearDown(bindings.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShortcutSettingsDialog(bindings: bindings)),
      ),
    );
    await tester.pump();
    return bindings;
  }

  Finder recordButtons() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('shortcut-record-'),
  );
  /// The keys of the rows the list holds, in order — built or not: the list
  /// is lazy, so they are read off the children it was handed.
  List<String> listed(WidgetTester tester) => [
    for (final child
        in (tester
                    .widget<ListView>(
                      find.byKey(const ValueKey<String>('shortcut-action-list')),
                    )
                    .childrenDelegate
                as SliverChildListDelegate)
            .children)
      if (child.key case ValueKey<String>(:final value)) value,
  ];

  /// The shelf headings the list holds, in order — a place's and every
  /// shelf's under it that stands open.
  List<String> headings(WidgetTester tester) => [
    for (final key in listed(tester))
      if (key.startsWith('shortcut-shelf-')) key,
  ];

  String headingKeyOf(ShortcutShelf shelf) => 'shortcut-shelf-${shelf.name}';

  /// The places' headings the list holds, in order.
  List<String> places(WidgetTester tester) => [
    for (final place in ShortcutShelf.places)
      if (headings(tester).contains(headingKeyOf(place))) headingKeyOf(place),
  ];
  final search = find.byKey(const ValueKey<String>('shortcut-search-field'));
  Finder twirlOf(ShortcutShelf shelf) =>
      find.named('shortcut-bundle-shelf-${shelf.name}');
  ShortcutShelf shelfOf(EditorShortcutBindings bindings, String id) =>
      bindings.definitions.singleWhere((row) => row.id == id).shelf;

  /// Opens every shelf [id] stands under, its place first — every shelf
  /// starts shut (menu-rows-and-panels-are-shortcut-rows), as the brush
  /// bundles do.
  Future<void> openShelvesOf(
    WidgetTester tester,
    EditorShortcutBindings bindings,
    String id,
  ) async {
    for (final shelf in shelfOf(bindings, id).path) {
      await tester.tap(twirlOf(shelf));
      await tester.pump();
    }
  }

  testWidgets('the search narrows the list to matching actions', (
    tester,
  ) async {
    final bindings = await pump(tester);
    final all = places(tester);
    expect(all.length, greaterThan(1));
    await tester.enterText(search, 'zzzz-no-such-action');
    await tester.pump();
    expect(headings(tester), isEmpty);
    expect(recordButtons(), findsNothing);

    final first = bindings.definitions.first;
    await tester.enterText(search, first.label);
    await tester.pump();
    expect(
      find.byKey(ValueKey<String>('shortcut-record-${first.id}')),
      findsOneWidget,
    );
    expect(
      places(tester).length,
      lessThan(all.length),
      reason: 'only the places it finds something in',
    );

    await tester.enterText(search, '');
    await tester.pump();
    expect(places(tester), all);
  });

  // 🗣️유저 2026-10-08 (menu-rows-and-panels-are-shortcut-rows): 「단축키
  // 많으니까 항목은 기본적으로 접을수있게. 브러시항목에서 쓴 거나 법
  // 통일하면서」 — the brush bundles' law (I-56-Q1: 기본 접힘 · 검색하면 맞는
  // 묶음이 펼쳐진다), for every shelf. 🗣️The shelves themselves:
  // shortcut-presets-anicel-and-clip-studio-Q1 (유저 2026-10-09) 「버튼이
  // 있는 자리로」 — a place, the bars and pills in it, then the keys.
  group('a shelf folds as a brush bundle does', () {
    bool isOpen(WidgetTester tester, ShortcutShelf shelf) => tester
        .widget<LayerFoldTwirl>(
          find.byWidgetPredicate(
            (widget) =>
                widget is LayerFoldTwirl &&
                widget.name == 'shortcut-bundle-shelf-${shelf.name}',
          ),
        )
        .expanded;

    testWidgets('a shelf has ONE heading, and its rows stand together under '
        'it — though the registry holds them in two places', (tester) async {
      final bindings = await pump(tester);
      final shelves = [for (final row in bindings.definitions) row.shelf];
      // ⛔premise: a shelf of no shelves whose rows the registry holds apart.
      final apart = shelves.toSet().firstWhere(
        (shelf) =>
            shelf.shelves.isEmpty &&
            shelves.lastIndexOf(shelf) - shelves.indexOf(shelf) >=
                shelves.where((each) => each == shelf).length,
      );
      final members = [
        for (final row in bindings.definitions)
          if (row.shelf == apart) 'shortcut-row-${row.id}',
      ];

      for (final shelf in apart.path) {
        await tester.tap(twirlOf(shelf));
        await tester.pump();
      }

      final keys = listed(tester);
      expect(
        keys.where((key) => key == headingKeyOf(apart)),
        hasLength(1),
      );
      final heading = keys.indexOf(headingKeyOf(apart));
      expect(
        keys.sublist(heading + 1, heading + 1 + members.length),
        members,
        reason: '${apart.name}\'s rows, all of them, right under its heading',
      );
    });

    testWidgets('every shelf stands shut when the window opens: the places\' '
        'headings and nothing under them', (tester) async {
      await pump(tester);
      expect(headings(tester), [
        for (final place in ShortcutShelf.places) headingKeyOf(place),
      ]);
      expect(recordButtons(), findsNothing);
      for (final place in ShortcutShelf.places) {
        expect(isOpen(tester, place), isFalse, reason: place.name);
      }
    });

    testWidgets('a place\'s twirl opens its shelves, each shut; a shelf\'s, '
        'its rows — and no other shelf\'s', (tester) async {
      final bindings = await pump(tester);
      final first = bindings.definitions.first;
      final place = first.shelf.path.first;
      final other = bindings.definitions.firstWhere(
        (row) => row.shelf != first.shelf,
      );

      await tester.tap(twirlOf(place));
      await tester.pump();
      expect(isOpen(tester, place), isTrue);
      expect(headings(tester), containsAll([
        for (final shelf in place.shelves) headingKeyOf(shelf),
      ]));
      expect(recordButtons(), findsNothing, reason: 'its shelves stand shut');

      for (final shelf in first.shelf.path.skip(1)) {
        await tester.tap(twirlOf(shelf));
        await tester.pump();
      }
      expect(
        find.byKey(ValueKey<String>('shortcut-record-${first.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('shortcut-record-${other.id}')),
        findsNothing,
        reason: '${other.shelf.name} stays shut',
      );

      await tester.tap(twirlOf(place));
      await tester.pump();
      expect(isOpen(tester, place), isFalse);
      expect(recordButtons(), findsNothing);
      expect(
        headings(tester),
        isNot(contains(headingKeyOf(first.shelf))),
        reason: 'a shut place shows none of its shelves',
      );
    });

    testWidgets('a search opens every shelf above what it finds; they stay '
        'open after, and the twirl folds them like any other', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final first = bindings.definitions.first;
      await tester.enterText(search, first.label);
      await tester.pump();
      for (final shelf in first.shelf.path) {
        expect(isOpen(tester, shelf), isTrue, reason: shelf.name);
      }

      await tester.enterText(search, '');
      await tester.pump();
      expect(isOpen(tester, first.shelf), isTrue);
      expect(
        find.byKey(ValueKey<String>('shortcut-record-${first.id}')),
        findsOneWidget,
      );

      await tester.tap(twirlOf(first.shelf));
      await tester.pump();
      expect(isOpen(tester, first.shelf), isFalse);
    });

    testWidgets('a search for a shelf\'s name finds every row it holds, on '
        'the shelves under it too', (tester) async {
      final bindings = await pump(tester);
      await tester.enterText(search, ShortcutShelf.pills.label);
      await tester.pump();
      const shelf = ShortcutShelf.cutPill;
      for (final row in bindings.definitions.where((r) => r.shelf == shelf)) {
        expect(
          listed(tester),
          contains('shortcut-row-${row.id}'),
          reason: row.id,
        );
      }
    });
  });

  // 🗣️유저 2026-10-09 (shortcut-presets-anicel-and-clip-studio): 「항목 접게
  // 만든거 좋은데 펼치는거랑 스크롤바랑 겹치는건지 안열림. 그냥 그 줄 누르면
  // 열리도록. 그러고 접기펼치기버튼은 항목 글자 왼쪽에 두도록. 다만 물론
  // 누르는건 그 항목 전체니까 접기펼치기 위젯은 그냥 보이기만할뿐인것임」.
  group('a fold is its whole row, its twirl left of its words', () {
    Finder headingOf(ShortcutShelf shelf) =>
        find.byKey(ValueKey<String>(headingKeyOf(shelf)));
    Finder wordsOf(Finder row) =>
        find.descendant(of: row, matching: find.byType(Text));

    testWidgets('pressing a heading\'s WORDS opens it, and pressing its far '
        'end shuts it — the end the list\'s scrollbar runs by', (
      tester,
    ) async {
      await pump(tester);
      final place = ShortcutShelf.places.first;
      final under = headingOf(place.shelves.first);

      await tester.tap(wordsOf(headingOf(place)));
      await tester.pump();
      expect(under, findsOneWidget);

      final row = tester.getRect(headingOf(place));
      await tester.tapAt(Offset(row.right - 40, row.center.dy));
      await tester.pump();
      expect(under, findsNothing);
    });

    testWidgets('the twirl stands left of the words, and only shows', (
      tester,
    ) async {
      await pump(tester);
      final place = ShortcutShelf.places.first;
      expect(
        tester.getRect(twirlOf(place)).right,
        lessThanOrEqualTo(tester.getRect(wordsOf(headingOf(place))).left),
      );
      expect(
        tester
            .widget<LayerFoldTwirl>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is LayerFoldTwirl &&
                    widget.name == 'shortcut-bundle-shelf-${place.name}',
              ),
            )
            .onToggle,
        isNull,
      );
    });

    testWidgets('a shelf\'s words start where its place\'s words do, and a '
        'row\'s where its shelf\'s do', (tester) async {
      final bindings = await pump(tester);
      final first = bindings.definitions.first;
      await openShelvesOf(tester, bindings, first.id);
      final place = first.shelf.path.first;
      expect(
        tester.getRect(twirlOf(first.shelf)).left,
        tester.getRect(wordsOf(headingOf(place))).left,
      );
      expect(
        tester.getRect(find.text(actionLabelOf(first))).left,
        tester.getRect(wordsOf(headingOf(first.shelf))).left,
      );
    });
  });

  testWidgets('recording waits past a modifier pressed alone, then takes the '
      'chord it modifies', (tester) async {
    // The same question the playback gate asks (`isModifierKey`): a key
    // that modifies another is not one to bind by itself.
    final bindings = await pump(tester);
    final id = bindings.definitions.first.id;
    await openShelvesOf(tester, bindings, id);

    await tester.tap(find.byKey(ValueKey<String>('shortcut-record-$id')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('shortcut-recording-hint')),
      findsOneWidget,
      reason: 'Ctrl alone is not a key to bind — still recording',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final recorded = bindings.activatorsFor(id).single;
    expect(recorded.trigger, LogicalKeyboardKey.f9);
    expect(recorded.control, isTrue);
  });

  testWidgets('record captures the next key, and reset all restores', (
    tester,
  ) async {
    final bindings = await pump(tester);
    final id = bindings.definitions.first.id;
    final defaults = bindings.activatorsFor(id);
    await openShelvesOf(tester, bindings, id);

    await tester.tap(find.byKey(ValueKey<String>('shortcut-record-$id')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    // SingleActivator has no `==`: compare the trigger and the modifiers.
    final recorded = bindings.activatorsFor(id).single;
    expect(recorded.trigger, LogicalKeyboardKey.f9);
    expect(recorded.control || recorded.shift || recorded.alt, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('shortcut-reset-all-button')),
    );
    await tester.pump();
    expect(
      bindings.activatorsFor(id).map((a) => a.trigger),
      defaults.map((a) => a.trigger),
    );
  });

  // F-230: the touch column picks from the shared list, 「없음」 first.
  testWidgets('a touch gesture is picked from the list, and 「none」 unbinds '
      'it', (tester) async {
    final bindings = await pump(tester);
    final id = bindings.definitions.first.id;
    final trigger = find.byKey(ValueKey<String>('shortcut-touch-$id'));
    await openShelvesOf(tester, bindings, id);

    Future<void> pick(String row) async {
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('shortcut-touch-$id-$row')));
      await tester.pumpAndSettle();
    }

    final other = TouchGesture.values.firstWhere(
      (gesture) => gesture != bindings.touchGestureFor(id),
    );
    await pick(other.name);
    expect(bindings.touchGestureFor(id), other);
    await pick('none');
    expect(bindings.touchGestureFor(id), isNull);
  });

  // 🗣️F-318 (유저 2026-10-08): 「동일한 단축키 있을때 빨간 경고메시지가 영어로
  // 뜨고, 단축키 할당 해제 버튼같은게 없음」.
  group('🚨F-318', () {
    // A key no action ships with — a clash made here is these two rows'.
    const spare = SingleActivator(LogicalKeyboardKey.f20);
    final banner = find.byKey(
      const ValueKey<String>('shortcut-conflict-banner'),
    );
    final list = find.byKey(const ValueKey<String>('shortcut-action-list'));

    /// Whether the warning is SHOWN — its line is laid out either way.
    bool warns(WidgetTester tester) => tester
        .widget<Visibility>(
          find.ancestor(of: banner, matching: find.byType(Visibility)),
        )
        .visible;

    void speak(AppLanguage language) {
      final before = AppText.settings.value;
      addTearDown(() => AppText.settings.value = before);
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
    }

    /// The first row with a key and no touch gesture — the plainest row
    /// there is, and at the top of the list.
    String aKeyedRow(EditorShortcutBindings bindings) => bindings.definitions
        .firstWhere(
          (row) =>
              bindings.activatorsFor(row.id).isNotEmpty &&
              bindings.touchGestureFor(row.id) == null,
        )
        .id;

    /// Two rows put on one key.
    (String, String) clash(EditorShortcutBindings bindings) {
      final [first, second, ...] = bindings.definitions;
      bindings
        ..setActivators(first.id, const [spare])
        ..setActivators(second.id, const [spare]);
      expect(bindings.conflictedActionIds, {first.id, second.id});
      return (first.id, second.id);
    }

    AppIconButton button(WidgetTester tester, String what, String id) =>
        tester.widget<AppIconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AppIconButton &&
                widget.keyValue == 'shortcut-$what-$id',
          ),
        );

    Future<void> tap(WidgetTester tester, String what, String id) async {
      await tester.tap(find.byKey(ValueKey<String>('shortcut-$what-$id')));
      await tester.pump();
    }

    for (final language in AppLanguage.values) {
      testWidgets('the warning for a shared key speaks the program language '
          '(${language.name}) — and its line is there before any key '
          'clashes, so the list does not move when it shows', (tester) async {
        speak(language);
        final bindings = await pump(tester);
        expect(warns(tester), isFalse, reason: 'nothing to warn of yet');
        expect(banner, findsOneWidget, reason: 'and its place is kept');
        final listBefore = tester.getRect(list);
        final lineBefore = tester.getRect(banner);
        expect(lineBefore.height, greaterThan(0));

        clash(bindings);
        await tester.pump();

        expect(warns(tester), isTrue);

        final words = AppStrings.of(language).shortcutConflictBanner;
        expect(tester.widget<Text>(banner).data, words);
        if (language != AppLanguage.en) {
          expect(
            words,
            isNot(AppStrings.of(AppLanguage.en).shortcutConflictBanner),
            reason: '⛔premise: the table has this language\'s sentence',
          );
        }
        expect(tester.getRect(banner), lineBefore);
        expect(tester.getRect(list), listBefore);
      });
    }

    testWidgets('a row\'s key is taken off by its own button — its default '
        'too — and the reset beside it brings the default back', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final id = aKeyedRow(bindings);
      final defaults = [
        for (final activator in bindings.activatorsFor(id)) activator.trigger,
      ];
      await openShelvesOf(tester, bindings, id);
      final row = find.byKey(ValueKey<String>('shortcut-row-$id'));
      expect(
        find.descendant(of: row, matching: find.byType(Chip)),
        findsWidgets,
        reason: '⛔premise: the row shows its key',
      );
      expect(button(tester, 'reset', id).onPressed, isNull, reason: '⛔premise');

      await tap(tester, 'unassign', id);

      expect(bindings.activatorsFor(id), isEmpty);
      expect(
        bindings.isOverridden(id),
        isTrue,
        reason: '「no key」 is an answer the bindings keep',
      );
      expect(
        find.descendant(of: row, matching: find.byType(Chip)),
        findsNothing,
      );
      expect(
        button(tester, 'unassign', id).onPressed,
        isNull,
        reason: 'nothing left to take off',
      );

      await tap(tester, 'reset', id);
      expect(
        [for (final activator in bindings.activatorsFor(id)) activator.trigger],
        defaults,
      );
      expect(button(tester, 'unassign', id).onPressed, isNotNull);
    });

    testWidgets('taking the key off ends a recording under way for that row', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final id = aKeyedRow(bindings);
      final hint = find.byKey(
        const ValueKey<String>('shortcut-recording-hint'),
      );
      await openShelvesOf(tester, bindings, id);
      await tap(tester, 'record', id);
      expect(hint, findsOneWidget, reason: '⛔premise');

      await tap(tester, 'unassign', id);

      expect(hint, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pump();
      expect(bindings.activatorsFor(id), isEmpty, reason: 'nothing recorded');
    });

    testWidgets('a clash ends when one of its rows gives the key up', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final (kept, given) = clash(bindings);
      await tester.pump();
      expect(warns(tester), isTrue, reason: '⛔premise');

      await openShelvesOf(tester, bindings, given);
      await tap(tester, 'unassign', given);

      expect(warns(tester), isFalse);
      expect(bindings.conflictedActionIds, isEmpty);
      expect(bindings.activatorsFor(kept).single.trigger, spare.trigger);
    });

    testWidgets('the button says what it does in the program language', (
      tester,
    ) async {
      speak(AppLanguage.ko);
      final bindings = await pump(tester);
      await openShelvesOf(tester, bindings, aKeyedRow(bindings));
      expect(
        button(tester, 'unassign', aKeyedRow(bindings)).tooltip,
        AppStrings.of(AppLanguage.ko).shortcutUnassign,
      );
    });
  });
}
