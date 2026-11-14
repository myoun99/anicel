// THE SHORTCUTS EDITOR: THE SEARCH NARROWS THE LIST, RECORD CAPTURES THE
// NEXT KEY AS THE ACTION'S ONLY BINDING, AND THE PRESET'S RESET PUTS ITS KEYS
// BACK.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, on bindings with no store behind them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/brush/tool_library_panel.dart'
    show subToolTilesOf;
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show actionLabelOf, labelWithKeys;
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart'
    show activatorKey, singleActivatorLabel;
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';
import 'package:anicel/src/ui/shortcuts/touch_shortcuts.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerFoldTwirl;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/text_finders.dart';

void main() {
  Future<EditorShortcutBindings> pump(
    WidgetTester tester, {
    EditorShortcutBindings? bindings,
  }) async {
    final held = bindings ?? EditorShortcutBindings();
    addTearDown(held.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShortcutSettingsDialog(bindings: held)),
      ),
    );
    await tester.pump();
    return held;
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

  // 🗣️F-580 (유저 2026-11-10): 「키보드 단축키 창 좀 더 커도될듯. 너무작음」
  // — the import and export windows' share of the screen (F-337), and never
  // smaller than the 520 × 520 it stood at.
  group('the window', () {
    /// The window as it is laid out — the box inside the Material `Dialog`
    /// its key is on, as the import window's pin reads it.
    Future<Size> windowOn(WidgetTester tester, Size screen) async {
      await pump(tester);
      await tester.binding.setSurfaceSize(screen);
      await tester.pump();
      return tester.getSize(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('shortcut-settings-dialog'),
              ),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
    }

    testWidgets('takes the import window\'s share of the screen', (
      tester,
    ) async {
      final size = await windowOn(tester, const Size(1600, 1000));
      expect(size.width, closeTo(1306.4, 0.1));
      expect(size.height, closeTo(816.5, 0.1));
    });

    testWidgets('never smaller than the 520 it stood at', (tester) async {
      final size = await windowOn(tester, const Size(700, 600));
      expect(size.height, 520);
    });
  });

  // 🗣️I-168 (유저 2026-11-10): 「동작검색 말고 단축키검색도 생성. 키보드
  // 단축키 지정하는거 재사용해서 버튼누르고 단축키입력하면 그 키의 단축키
  // 보이게. 리셋버튼으로 리셋」.
  group('🗣️I-168: the search by key', () {
    final seekButton = find.byKey(
      const ValueKey<String>('shortcut-search-by-key'),
    );
    final clearButton = find.byKey(
      const ValueKey<String>('shortcut-search-by-key-clear'),
    );
    const f9 = LogicalKeyboardKey.f9;
    const save = EditorActionIds.fileSave;
    const undo = EditorActionIds.undo;

    /// Presses the ⌨ beside the search, then [key] — Ctrl held where
    /// [control] says.
    Future<void> seek(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool control = false,
    }) async {
      await tester.tap(seekButton);
      await tester.pump();
      if (control) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.sendKeyEvent(key);
      if (control) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pump();
    }

    List<String> rowsListed(WidgetTester tester) => [
      for (final key in listed(tester))
        if (key.startsWith('shortcut-row-')) key,
    ];

    testWidgets('the ⌨ beside the search takes the next key, and the list '
        'keeps the actions that hold it — their shelves open', (
      tester,
    ) async {
      final bindings = await pump(tester);
      expect(
        [
          for (final row in bindings.definitions)
            if (bindings.holds(row.id, const SingleActivator(f9))) row.id,
        ],
        isEmpty,
        reason: '⛔premise: no one holds F9 out of the box',
      );
      bindings
        ..setActivators(save, const [SingleActivator(f9)])
        ..setActivators(undo, const [SingleActivator(f9)]);
      await tester.pump();
      expect(rowsListed(tester), isEmpty, reason: '⛔premise: all shut');

      await seek(tester, f9);
      expect(rowsListed(tester), ['shortcut-row-$undo', 'shortcut-row-$save']);
      expect(bindings.activatorsFor(save), hasLength(1), reason: 'nothing '
          'was recorded on a row');
    });

    testWidgets('a key is its modifiers too: Ctrl+F9 is not F9', (
      tester,
    ) async {
      final bindings = await pump(tester);
      bindings
        ..setActivators(save, const [SingleActivator(f9)])
        ..setActivators(undo, const [SingleActivator(f9, control: true)]);
      await tester.pump();

      await seek(tester, f9);
      expect(rowsListed(tester), ['shortcut-row-$save']);
      await seek(tester, f9, control: true);
      expect(rowsListed(tester), ['shortcut-row-$undo']);
    });

    testWidgets('the ↺ lets the key go — and stands dead while none is '
        'sought', (tester) async {
      final bindings = await pump(tester);
      bindings.setActivators(save, const [SingleActivator(f9)]);
      await tester.pump();
      final all = places(tester);
      expect(tester.appIconButton(clearButton).onPressed, isNull);

      await seek(tester, f9);
      expect(places(tester), hasLength(1), reason: '⛔premise: it narrowed');
      expect(tester.appIconButton(clearButton).onPressed, isNotNull);
      await tester.tap(clearButton);
      await tester.pump();
      expect(places(tester), all);
      expect(tester.appIconButton(clearButton).onPressed, isNull);
    });

    testWidgets('Esc while it waits takes nothing — the key sought stays', (
      tester,
    ) async {
      final bindings = await pump(tester);
      bindings.setActivators(save, const [SingleActivator(f9)]);
      await tester.pump();
      await seek(tester, f9);

      await tester.tap(seekButton);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(rowsListed(tester), ['shortcut-row-$save']);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('shortcut-search-by-key-sought'),
          ),
          matching: find.text(singleActivatorLabel(const SingleActivator(f9))),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with words too, what answers both', (tester) async {
      final bindings = await pump(tester);
      bindings
        ..setActivators(save, const [SingleActivator(f9)])
        ..setActivators(undo, const [SingleActivator(f9)]);
      await tester.pump();
      await tester.enterText(
        search,
        actionLabelOf(
          bindings.definitions.singleWhere((row) => row.id == save),
        ),
      );
      await seek(tester, f9);
      expect(rowsListed(tester), ['shortcut-row-$save']);
    });

    // 🗣️F-241: an arrow is kept as the timeline reads it, and the X-sheet
    // turns a pressed one — the key sought is what it presses there.
    testWidgets('on the X-sheet an arrow finds what it presses there', (
      tester,
    ) async {
      final sheet = FlipHudController()..framesRunVertically = true;
      addTearDown(sheet.dispose);
      await pump(
        tester,
        bindings: EditorShortcutBindings()
          ..setPreset(ShortcutPreset.anicel)
          ..sheet = sheet,
      );

      await seek(tester, LogicalKeyboardKey.arrowDown);
      final rows = rowsListed(tester);
      expect(rows, contains('shortcut-row-${EditorActionIds.drawingNext}'));
      expect(
        rows,
        isNot(contains('shortcut-row-${EditorActionIds.layerDown}')),
      );
    });

    testWidgets('⛔the search line keeps its place: the field is as wide '
        'while it waits and with a key sought', (tester) async {
      final bindings = await pump(tester);
      bindings.setActivators(save, const [SingleActivator(f9)]);
      await tester.pump();
      final width = tester.getSize(search).width;

      await tester.tap(seekButton);
      await tester.pump();
      expect(tester.getSize(search).width, width, reason: 'waiting');
      await tester.sendKeyEvent(f9);
      await tester.pump();
      expect(tester.getSize(search).width, width, reason: 'F9 sought');
    });
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

    // 🗣️F-580 (유저 2026-11-10): 「캔버스-도구에 도구 있고, 그 밑에 해당 도구의
    // 세부도구 … 도구-세부도구-도구-세부도구 순으로 있는게 알기쉬움」 — a tool's
    // row, then a step in what is that tool's: its tiles in the tool
    // library's order, then its own shelf. ↩️「세부 도구」 was one shelf of
    // every tool's tiles, its rows before the tool library's shelves (F-560).
    group('under 도구, a tool\'s own stand a step in under its row', () {
      Future<(EditorShortcutBindings, List<String>)> openTools(
        WidgetTester tester,
      ) async {
        final bindings = await pump(tester);
        // Tall enough that every row of 도구 is laid out at once.
        await tester.binding.setSurfaceSize(const Size(900, 3600));
        for (final shelf in ShortcutShelf.tools.path) {
          await tester.tap(twirlOf(shelf));
          await tester.pump();
        }
        return (bindings, listed(tester));
      }

      String rowKeyOf(String id) => 'shortcut-row-$id';

      testWidgets('a tool\'s tiles right under its row, in the tool '
          'library\'s order', (tester) async {
        final (bindings, keys) = await openTools(tester);
        for (final (id, group) in [
          (EditorActionIds.toolSelect, CanvasTool.select),
          (EditorActionIds.toolCut, CanvasTool.cut),
          (EditorActionIds.toolFill, CanvasTool.fill),
          (EditorActionIds.toolTransform, CanvasTool.move),
        ]) {
          final tiles = [
            for (final tile in subToolTilesOf(group))
              rowKeyOf(
                bindings.definitions
                    .singleWhere((row) => row.toolPress == tile.press)
                    .id,
              ),
          ];
          expect(tiles, isNotEmpty, reason: '⛔premise: $id has tiles');
          final at = keys.indexOf(rowKeyOf(id));
          expect(at, isNot(-1), reason: id);
          expect(keys.sublist(at + 1, at + 1 + tiles.length), tiles);
        }
      });

      testWidgets('a tool\'s own shelf right under its row', (tester) async {
        final (_, keys) = await openTools(tester);
        for (final (id, shelf) in [
          (EditorActionIds.toolText, ShortcutShelf.texts),
          (EditorActionIds.toolGuide, ShortcutShelf.guides),
        ]) {
          expect(
            keys[keys.indexOf(rowKeyOf(id)) + 1],
            headingKeyOf(shelf),
            reason: id,
          );
        }
      });

      testWidgets('every row of 도구 stands once — a tile no tool lists is '
          'not lost', (tester) async {
        final (bindings, _) = await openTools(tester);
        for (final shelf in ShortcutShelf.tools.shelves) {
          if (twirlOf(shelf).evaluate().isEmpty) {
            continue; // a shelf with no rows has no heading
          }
          await tester.tap(twirlOf(shelf));
          await tester.pump();
        }
        final opened = listed(tester);
        for (final row in bindings.definitions) {
          if (row.shelf.path.contains(ShortcutShelf.tools)) {
            expect(
              opened.where((key) => key == rowKeyOf(row.id)),
              hasLength(1),
              reason: row.id,
            );
          }
        }
      });

      testWidgets('a tile\'s words start where its tool\'s shelf\'s do — one '
          'step in from its tool\'s', (tester) async {
        final (bindings, _) = await openTools(tester);
        Rect wordsOfRow(String id) => tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey<String>(rowKeyOf(id))),
            matching: find.text(
              actionLabelOf(
                bindings.definitions.singleWhere((row) => row.id == id),
              ),
            ),
          ),
        );
        Rect wordsOfHeading(ShortcutShelf shelf) => tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey<String>(headingKeyOf(shelf))),
            matching: find.anyText(),
          ),
        );
        expect(
          wordsOfRow(EditorActionIds.toolCut).left,
          wordsOfHeading(ShortcutShelf.tools).left,
        );
        expect(
          wordsOfRow(EditorActionIds.toolCutStamp).left,
          wordsOfHeading(ShortcutShelf.texts).left,
        );
        expect(
          wordsOfRow(EditorActionIds.toolCutStamp).left,
          greaterThan(wordsOfRow(EditorActionIds.toolCut).left),
        );
      });
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
        find.descendant(of: row, matching: find.anyText());

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

  testWidgets('record captures the next key, and the reset restores', (
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
      find.byKey(const ValueKey<String>('shortcut-preset-reset-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('shortcut-preset-reset-confirm-button'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      bindings.activatorsFor(id).map((a) => a.trigger),
      defaults.map((a) => a.trigger),
    );
  });

  // 🗣️F-522 (유저 2026-11-01): 「키보드 단축키 모두초기화버튼, 현재 프리셋
  // 초기화로 바꾸고, 누르면 초기화하겟냐고 메시지창 띄우기. 그리고 할당 충돌하면
  // 해당 들어있는 항목 다 빨간강조색으로. 어디 들어있는건지 안보임. 패널 안
  // 빨간강조색만들고 미디어 빨간강조색만들고 이런식」.
  group('🚨F-522', () {
    const spare = SingleActivator(LogicalKeyboardKey.f20);
    final resetButton = find.byKey(
      const ValueKey<String>('shortcut-preset-reset-button'),
    );

    List<LogicalKeyboardKey> keysOf(EditorShortcutBindings bindings, String id) =>
        [for (final each in bindings.activatorsFor(id)) each.trigger];

    Future<void> press(WidgetTester tester, Finder button) async {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    for (final language in AppLanguage.values) {
      testWidgets('the button names the preset in use, not 「all」, and its '
          'window names the preset (${language.name})', (tester) async {
        final before = AppText.settings.value;
        addTearDown(() => AppText.settings.value = before);
        AppText.settings.value = AppLanguageSettings(programLanguage: language);
        final bindings = await pump(tester);
        final strings = AppStrings.of(language);
        expect(
          find.descendant(
            of: resetButton,
            matching: find.text(strings.shortcutResetPreset),
          ),
          findsOneWidget,
        );

        await press(tester, resetButton);

        final preset = bindings.preset as ShortcutPreset;
        expect(
          find.text(
            strings.shortcutResetPresetBody(
              strings.shortcutPresetName(preset.name, preset.label),
            ),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('the reset asks first: cancelled nothing moves, and only the '
        'yes puts the keys back', (tester) async {
      final bindings = await pump(tester);
      final id = bindings.definitions.first.id;
      final defaults = keysOf(bindings, id);
      bindings.setActivators(id, const [spare]);
      await tester.pump();

      await press(tester, resetButton);
      expect(
        find.byKey(const ValueKey<String>('shortcut-preset-reset-dialog')),
        findsOneWidget,
      );
      expect(keysOf(bindings, id), [spare.trigger], reason: 'not yet answered');

      await press(
        tester,
        find.byKey(
          const ValueKey<String>('shortcut-preset-reset-cancel-button'),
        ),
      );
      expect(keysOf(bindings, id), [spare.trigger]);

      await press(tester, resetButton);
      await press(
        tester,
        find.byKey(
          const ValueKey<String>('shortcut-preset-reset-confirm-button'),
        ),
      );
      expect(keysOf(bindings, id), defaults);
    });

    /// The ink [key]'s words are written in.
    Color? inkOf(WidgetTester tester, String key) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.anyText(),
          ),
        )
        .style
        ?.color;

    Color red(WidgetTester tester) =>
        Theme.of(tester.element(search)).colorScheme.error;

    /// A row two shelves deep and a row of another place — the clash under
    /// test, and every fold over the first.
    (String, String) twoPlaces(EditorShortcutBindings bindings) {
      final deep = bindings.definitions.firstWhere(
        (row) => row.shelf.path.length > 1,
      );
      final other = bindings.definitions.firstWhere(
        (row) => row.shelf.path.first != deep.shelf.path.first,
      );
      return (deep.id, other.id);
    }

    Future<void> everyFoldOverTheRowIsRed(
      WidgetTester tester,
      EditorShortcutBindings bindings,
      String id,
    ) async {
      final color = red(tester);
      for (final shelf in shelfOf(bindings, id).path) {
        await tester.ensureVisible(twirlOf(shelf));
        await tester.pump();
        expect(inkOf(tester, headingKeyOf(shelf)), color, reason: shelf.name);
        await tester.tap(twirlOf(shelf));
        await tester.pump();
      }
    }

    testWidgets('a clash of keys stands red on every fold over it, step by '
        'step down to its row, while the other places keep their ink', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final (deep, other) = twoPlaces(bindings);
      final place = shelfOf(bindings, deep).path.first;
      final calm = ShortcutShelf.places.firstWhere(
        (each) =>
            each != place && each != shelfOf(bindings, other).path.first,
      );
      final accent = Theme.of(tester.element(search)).colorScheme.primary;
      expect(inkOf(tester, headingKeyOf(place)), accent, reason: '⛔premise');

      bindings
        ..setActivators(deep, const [spare])
        ..setActivators(other, const [spare]);
      await tester.pump();

      expect(inkOf(tester, headingKeyOf(calm)), accent);
      expect(
        inkOf(tester, headingKeyOf(shelfOf(bindings, other).path.first)),
        red(tester),
        reason: 'both sides of the clash',
      );
      await everyFoldOverTheRowIsRed(tester, bindings, deep);
      final row = find.byKey(ValueKey<String>('shortcut-row-$deep'));
      await tester.ensureVisible(row);
      await tester.pump();
      Color? rowInk() => tester
          .widget<Text>(
            find.descendant(
              of: row,
              matching: find.text(actionLabelOf(bindings.definitionFor(deep)!)),
            ),
          )
          .style
          ?.color;
      expect(rowInk(), red(tester));

      bindings.setActivators(other, const []);
      await tester.pump();
      expect(rowInk(), isNot(red(tester)), reason: 'it ended');
    });

    testWidgets('a clash of touch gestures stands red the same way', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final (deep, other) = twoPlaces(bindings);
      for (final id in [deep, other]) {
        bindings.setTouchGesture(id, TouchGesture.values.last);
      }
      await tester.pump();
      expect(bindings.touchConflictedActionIds, containsAll([deep, other]));
      expect(bindings.conflictedActionIds, isEmpty, reason: '⛔premise');

      await everyFoldOverTheRowIsRed(tester, bindings, deep);
    });

    testWidgets('the red says what is under a fold, whatever the search '
        'shows of it', (tester) async {
      final bindings = await pump(tester);
      final (deep, other) = twoPlaces(bindings);
      bindings
        ..setActivators(deep, const [spare])
        ..setActivators(other, const [spare]);
      final place = shelfOf(bindings, deep).path.first;
      final calm = bindings.definitions.firstWhere(
        (row) => row.shelf.path.first == place && row.id != deep,
      );
      await tester.enterText(search, actionLabelOf(calm));
      await tester.pump();
      expect(
        actionLabelOf(bindings.definitionFor(deep)!),
        isNot(actionLabelOf(calm)),
        reason: '⛔premise: the search leaves the clash out',
      );

      expect(inkOf(tester, headingKeyOf(place)), red(tester));
    });
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

    // 🗣️I-158 (유저 2026-11-04): 「키 충돌하면 같은키를 쓰는 동작 있습니다
    // 옆에 대상 텍스트로 보여주게. 예를들어 올가미 채우기(Y) : 펜(Y) 이런식.
    // 여러개 충돌하면 해당 영역 버튼눌러서 리스트팝오버로 여러개 보여주게.
    // 그리고 추가로 펜(Y)이런식으로 이 텍스트를 버튼으로 만들어서, 이걸로
    // 할당하는 기능. 호버하면 설명 말한대로 툴팁으로 보여주고 그거
    // 버튼누르면 올가미채우기의 키가 사라지는식으로」.
    group('🗣️I-158: who clashes stands beside the warning', () {
      const another = SingleActivator(LogicalKeyboardKey.f19);
      final clashList = find.byKey(
        const ValueKey<String>('shortcut-clash-list'),
      );
      Finder keep(String id, SingleActivator key) => find.byKey(
        ValueKey<String>('shortcut-clash-keep-$id-${activatorKey(key)}'),
      );
      String nameOf(EditorShortcutBindings bindings, String id) =>
          actionLabelOf(bindings.definitionFor(id)!);
      List<String> keysOf(EditorShortcutBindings bindings, String id) => [
        for (final activator in bindings.activatorsFor(id))
          activatorKey(activator),
      ];

      testWidgets('a pair: each name with the key, on the warning\'s line '
          'after it — a button, and nothing there before', (tester) async {
        final bindings = await pump(tester);
        final [first, second, ...] = bindings.definitions;
        expect(keep(first.id, spare), findsNothing);

        clash(bindings);
        await tester.pump();

        final line = tester.getRect(banner);
        for (final row in [first, second]) {
          final name = keep(row.id, spare);
          expect(
            tester
                .widget<Text>(
                  find.descendant(of: name, matching: find.anyText()),
                )
                .data,
            labelWithKeys(
              nameOf(bindings, row.id),
              singleActivatorLabel(spare),
            ),
          );
          expect(tester.getRect(name).left, greaterThan(line.right));
          expect(
            tester.getRect(name).center.dy,
            closeTo(line.center.dy, line.height / 2),
          );
        }
        expect(
          tester.getRect(keep(second.id, spare)).left,
          greaterThan(tester.getRect(keep(first.id, spare)).right),
          reason: 'the pair reads along the line, in the registry\'s order',
        );
        expect(clashList, findsNothing);
      });

      testWidgets('a name pressed keeps the key on it alone, and the clash '
          'ends', (tester) async {
        final bindings = await pump(tester);
        final (first, second) = clash(bindings);
        await tester.pump();

        await tester.tap(keep(second, spare));
        await tester.pump();

        expect(keysOf(bindings, second), [activatorKey(spare)]);
        expect(keysOf(bindings, first), isEmpty);
        expect(warns(tester), isFalse);
      });

      testWidgets('hovered, a name says what its press does, in the program '
          'language', (tester) async {
        speak(AppLanguage.ko);
        final bindings = await pump(tester);
        final (first, second) = clash(bindings);
        await tester.pump();

        final strings = AppStrings.of(AppLanguage.ko);
        expect(
          tester
              .widget<AppTooltip>(
                find.ancestor(
                  of: keep(second, spare),
                  matching: find.byType(AppTooltip),
                ),
              )
              .message,
          strings.shortcutClashKeep(
            singleActivatorLabel(spare),
            nameOf(bindings, second),
            nameOf(bindings, first),
          ),
        );
        expect(
          strings.shortcutClashKeep('k', 'n', 'o'),
          isNot(AppStrings.of(AppLanguage.en).shortcutClashKeep('k', 'n', 'o')),
          reason: '⛔premise: the table has this language\'s sentence',
        );
      });

      testWidgets('more than one pair: a button named by their keys opens '
          'the list, a line a pair — and the list under the warning does '
          'not move', (tester) async {
        final bindings = await pump(tester);
        final listBefore = tester.getRect(list);
        final [a, b, c, d, ...] = [
          for (final row in bindings.definitions) row.id,
        ];
        bindings
          ..setActivators(a, const [spare])
          ..setActivators(b, const [spare])
          ..setActivators(c, const [another])
          ..setActivators(d, const [another]);
        await tester.pump();

        expect(keep(a, spare), findsNothing, reason: 'no pair stands alone');
        expect(
          tester.widget<PanelFlyoutButton>(clashList).label,
          '${singleActivatorLabel(spare)}, ${singleActivatorLabel(another)}',
        );
        expect(tester.getRect(list), listBefore);

        await tester.tap(clashList);
        await tester.pumpAndSettle();
        for (final (id, key) in [
          (a, spare),
          (b, spare),
          (c, another),
          (d, another),
        ]) {
          expect(keep(id, key), findsOneWidget, reason: id);
        }

        await tester.tap(keep(c, another));
        await tester.pump();
        expect(keysOf(bindings, c), [activatorKey(another)]);
        expect(keysOf(bindings, d), isEmpty);
        expect(
          keep(d, another),
          findsOneWidget,
          reason: 'the line stays up, and shows where the key went',
        );
        Color? inkOf(String id) => tester
            .widget<TextButton>(keep(id, another))
            .style
            ?.foregroundColor
            ?.resolve({});
        final colors = Theme.of(tester.element(keep(d, another))).colorScheme;
        expect(inkOf(c), colors.primary);
        expect(inkOf(d), colors.onSurfaceVariant);
      });

      testWidgets('one key on three actions is more than a pair', (
        tester,
      ) async {
        final bindings = await pump(tester);
        final [a, b, c, ...] = [
          for (final row in bindings.definitions) row.id,
        ];
        for (final id in [a, b, c]) {
          bindings.setActivators(id, const [spare]);
        }
        await tester.pump();

        expect(keep(a, spare), findsNothing);
        expect(
          tester.widget<PanelFlyoutButton>(clashList).label,
          singleActivatorLabel(spare),
        );
      });
    });
  });
}
