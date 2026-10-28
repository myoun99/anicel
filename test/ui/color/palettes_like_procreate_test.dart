// I-131: THE PALETTES AS PROCREATE KEEPS THEM, BUILT AS THE 시안 DREW THEM.
//
// I-131-Q1 답 「Procreate(프로크리에이트)의 팔레트」 · Q2 「시안대로 만든다」 ·
// Q3 「최근 + 기본 팔레트(프로크리에이트처럼)」. Every place answers the same
// three ways wherever it stands — a press picks, a press on an empty one
// fills, a drag moves or trades — and these pins drive them as a hand does,
// with a mouse unless the device is the question.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import 'package:anicel/src/ui/color/color_palettes.dart';
import 'package:anicel/src/ui/color/color_panels.dart';
import 'package:anicel/src/ui/color/color_wheel_panel.dart' show ColorWheel;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/disabled_ink.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/overflow_scrollers.dart';

const int _red = 0xFFE53935;
const int _blue = 0xFF1E88E5;
const int _green = 0xFF43A047;

/// Two palettes — 「Skin」 the default, red · blue · empty · red, and 「Sky」
/// holding a blue.
ColorPaletteState _two() => ColorPaletteState(
  palettes: [
    NamedPalette(
      id: 'p1',
      name: 'Skin',
      slots: NamedPalette.placed(const [_red, _blue, null, _red]),
    ),
    NamedPalette(
      id: 'p2',
      name: 'Sky',
      slots: NamedPalette.placed(const [_blue]),
    ),
  ],
  defaultId: 'p1',
);

/// What the panel was handed back, as the host keeps it.
class _Desk {
  _Desk(this.palettes, this.color);

  ColorPaletteState palettes;
  int color;
  final List<int> picks = [];

  List<int?> slotsOf(String id) =>
      palettes.palettes.firstWhere((palette) => palette.id == id).slots;
}

/// The panel in a group of [size], on its floor as the dock hosts it
/// (`EditorPanelTabs._onItsFloor`).
Future<_Desk> _open(
  WidgetTester tester, {
  ColorPickerKind kind = ColorPickerKind.palette,
  ColorPaletteState? palettes,
  int color = _green,
  Size size = const Size(300, 600),
}) async {
  final desk = _Desk(palettes ?? _two(), color);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: StatefulBuilder(
              builder: (context, setState) => OverflowScrollers(
                minWidth: ColorPickerPanel.minContentWidthIn(context),
                minHeight: ColorPickerPanel.contentExtentIn(context, kind) ?? 0,
                child: ColorPickerPanel(
                  kind: kind,
                  color: desk.color,
                  palette: desk.palettes,
                  onColorChanged: (color) => setState(() {
                    desk.color = color;
                    desk.picks.add(color);
                  }),
                  onPaletteChanged: (palettes) =>
                      setState(() => desk.palettes = palettes),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return desk;
}

Finder _place(String paletteId, int index) =>
    find.byKey(ValueKey<String>('palette-$paletteId-slot-$index'));

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.tap(target, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

/// Two quick presses on [target] — a double click.
Future<void> _doubleClick(WidgetTester tester, Finder target) async {
  await tester.tap(target, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(target, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

/// Palette [id]'s name, typed from its ⋯ — a press on the name folds it.
Future<void> _rename(WidgetTester tester, String id) async {
  await _press(tester, _key('palette-$id-more'));
  await _press(tester, _key('palette-rename'));
}

/// How many places palette [id] shows.
int _shownPlaces(String id) => find
    .byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'palette-$id-slot-',
          ),
    )
    .evaluate()
    .length;

/// Presses [from], trembles inside it, and lets go on [to] — by way of
/// [via] when given.
Future<void> _carry(
  WidgetTester tester,
  Finder from,
  Finder to, {
  Finder? via,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final start = tester.getCenter(from);
  final stops = [if (via != null) tester.getCenter(via), tester.getCenter(to)];
  final gesture = await tester.startGesture(start, kind: kind);
  await gesture.moveBy(const Offset(1, 1));
  await tester.pump();
  for (final stop in stops) {
    await gesture.moveTo(Offset.lerp(start, stop, 0.5)!);
    await tester.pump();
    await gesture.moveTo(stop);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('a place', () {
    testWidgets('a press on a colour picks it, and the palette stays as it '
        'was', (tester) async {
      final desk = await _open(tester);
      final before = desk.palettes;

      await _press(tester, _place('p1', 1));

      expect(desk.picks, [_blue]);
      expect(identical(desk.palettes, before), isTrue);
    });

    testWidgets('a press on an empty one puts the current colour in — one '
        'the palette holds already too', (tester) async {
      final desk = await _open(tester, color: _red);

      await _press(tester, _place('p1', 2));

      expect(desk.slotsOf('p1').take(4), [_red, _blue, _red, _red]);
      expect(desk.picks, isEmpty, reason: 'filling picks nothing');
    });

    for (final kind in const [
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
    ]) {
      testWidgets('${kind.name}: carried onto an empty place it moves, onto '
          'a colour it trades — and picks nothing', (tester) async {
        final desk = await _open(tester);

        await _carry(tester, _place('p1', 0), _place('p1', 2), kind: kind);
        expect(desk.slotsOf('p1').take(4), [null, _blue, _red, _red]);

        await _carry(tester, _place('p1', 1), _place('p1', 2), kind: kind);
        expect(desk.slotsOf('p1').take(4), [null, _red, _blue, _red]);
        expect(desk.picks, isEmpty);
      });
    }

    testWidgets('🚨a colour carried out and brought back to its own place '
        'neither moves nor picks — a press that became a carry is not a '
        'press', (tester) async {
      final desk = await _open(tester);
      final before = desk.palettes;

      await _carry(
        tester,
        _place('p1', 0),
        _place('p1', 0),
        via: _place('p1', 5),
      );

      expect(identical(desk.palettes, before), isTrue);
      expect(desk.picks, isEmpty);
    });

    testWidgets('the place a colour is carried out of shows it dimmed — its '
        'own colours, with no layer over them', (tester) async {
      await _open(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(_place('p1', 0)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(1, 1));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(_place('p1', 5)));
      await tester.pump();

      final left = find.descendant(
        of: _place('p1', 0),
        matching: find.byType(DecoratedBox),
      );
      expect(
        [
          for (final box in tester.widgetList<DecoratedBox>(left))
            ?(box.decoration as BoxDecoration).color,
        ],
        [dimmedIfDisabled(const Color(_red), enabled: false)],
      );
      expect(
        find.descendant(of: _place('p1', 0), matching: find.byType(Opacity)),
        findsNothing,
        reason: 'a layer is a repaint boundary inside the panel\'s bake',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a place takes no colour carried from another palette', (
      tester,
    ) async {
      final desk = await _open(tester);
      final before = desk.palettes;

      await _carry(tester, _place('p2', 0), _place('p1', 2));

      expect(identical(desk.palettes, before), isTrue);
    });

    testWidgets('🚨a tremor on a place is still a press, and the list under '
        'it does not scroll — 「컨트롤 위에서 시작한 제스처는 그 컨트롤의 '
        '것이다」', (tester) async {
      final desk = await _open(tester, size: const Size(260, 220));
      final list = tester.state<ScrollableState>(
        find.descendant(
          of: _key('palette-panel'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(list.position.maxScrollExtent, greaterThan(0), reason: '⛔전제');

      final gesture = await tester.startGesture(
        tester.getCenter(_place('p1', 1)),
        kind: PointerDeviceKind.mouse,
      );
      for (final step in const [Offset(0, -2), Offset(1, -3), Offset(-2, 1)]) {
        await gesture.moveBy(step);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(desk.picks, [_blue]);
      expect(list.position.pixels, 0);
    });
  });

  group('the recent colours', () {
    testWidgets('hold their ten places empty — the row does not come into '
        'being with the first stroke', (tester) async {
      await _open(tester);
      final empty = [
        for (var i = 0; i < ColorPaletteState.maxRecent; i += 1)
          tester.getRect(_key('palette-recent-$i')),
      ];

      await _open(tester, palettes: _two().withRecentColor(_red));
      final one = [
        for (var i = 0; i < ColorPaletteState.maxRecent; i += 1)
          tester.getRect(_key('palette-recent-$i')),
      ];

      expect(one, empty);
      expect(empty.first.width, greaterThan(0));
    });

    testWidgets('a press on one picks it; an empty one is no control', (
      tester,
    ) async {
      final desk = await _open(tester, palettes: _two().withRecentColor(_red));

      await _press(tester, _key('palette-recent-1'));
      expect(desk.picks, isEmpty);

      await _press(tester, _key('palette-recent-0'));
      expect(desk.picks, [_red]);
    });
  });

  group('a palette', () {
    testWidgets('the − empties every place holding the current colour, and '
        'is dead where the palette holds none', (tester) async {
      final desk = await _open(tester, color: _red);

      AppIconButtonFace remove(String id) =>
          tester.widget<AppIconButtonFace>(_key('palette-$id-remove'));
      expect(remove('p2').onPressed, isNull);

      await _press(tester, _key('palette-p1-remove'));

      expect(desk.slotsOf('p1').take(4), [null, _blue, null, null]);
      expect(desk.slotsOf('p1'), hasLength(NamedPalette.slotCount));
      expect(remove('p1').onPressed, isNull, reason: 'none is left');
    });

    testWidgets('its ⋯ types its name where it stands: Enter keeps it, '
        'Escape lets it go, a press away keeps it', (tester) async {
      final desk = await _open(tester);
      String nameOf(String id) => desk.palettes.palettes
          .firstWhere((palette) => palette.id == id)
          .name;

      await _rename(tester, 'p2');
      final field = tester.widget<TextField>(_key('palette-p2-name-input'));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
        reason: 'the name is selected whole, so typing replaces it',
      );
      expect(
        field.decoration?.border,
        isNot(InputBorder.none),
        reason: "the 시안 drew the name typed into the app's field box",
      );
      await tester.enterText(_key('palette-p2-name-input'), ' Sea ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(nameOf('p2'), 'Sea');
      expect(_key('palette-p2-name-input'), findsNothing);

      await _rename(tester, 'p2');
      await tester.enterText(_key('palette-p2-name-input'), 'Gone');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(nameOf('p2'), 'Sea');
      expect(_key('palette-p2-name-input'), findsNothing);

      await _rename(tester, 'p2');
      await tester.enterText(_key('palette-p2-name-input'), 'Ocean');
      // Below the last palette: the list's own empty room, no control.
      await tester.tapAt(const Offset(130, 450));
      await tester.pumpAndSettle();
      expect(nameOf('p2'), 'Ocean');
    });

    testWidgets('a press on its name folds it — the name stays, its places '
        'go — and a second opens it (I-131, 10-28)', (tester) async {
      final desk = await _open(tester);
      bool folded(String id) =>
          desk.palettes.palettes.firstWhere((p) => p.id == id).folded;

      await _press(tester, _key('palette-p1-name'));
      expect(folded('p1'), isTrue);
      expect(_shownPlaces('p1'), 0);
      expect(_key('palette-p1-name'), findsOneWidget);
      expect(_key('palette-p1-name-input'), findsNothing, reason: 'no rename');
      expect(_shownPlaces('p2'), NamedPalette.slotCount, reason: 'p2 alone');

      await _press(tester, _key('palette-p1-name'));
      expect(folded('p1'), isFalse);
      expect(_shownPlaces('p1'), NamedPalette.slotCount);
    });

    testWidgets('a drag that leaves its name moves the palette — the brush '
        'groups\' own move (I-131, 10-28)', (tester) async {
      final desk = await _open(tester);
      List<String> order() => [
        for (final palette in desk.palettes.palettes) palette.id,
      ];

      // Up past the top of p1's entry, in steps the list can follow.
      final start = tester.getCenter(_key('palette-p2-name'));
      final rise = start.dy - tester.getTopLeft(_key('palette-p1')).dy + 8;
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 1; step <= 10; step += 1) {
        await gesture.moveTo(start - Offset(0, rise * step / 10));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(), ['p2', 'p1']);
      expect(
        desk.palettes.palettes.first.folded,
        isFalse,
        reason: 'a drag is not a press',
      );
    });

    testWidgets('locked, it shows its colours alone, packed, and a press '
        'only picks — no fill, no carry, no −, no colour window', (
      tester,
    ) async {
      final desk = await _open(
        tester,
        color: _red,
        palettes: _two().withLocked('p1', locked: true),
      );
      final lock = tester.widget<AppIconButtonFace>(_key('palette-p1-lock'));
      expect(lock.isSelected, isTrue);
      expect(_shownPlaces('p1'), 3);
      expect(_place('p1', 2), findsNothing, reason: 'the empty place goes');
      expect(
        tester.getRect(_place('p1', 3)).left -
            tester.getRect(_place('p1', 1)).right,
        moreOrLessEquals(4),
        reason: 'the colour after the empty place packs up to the one before',
      );
      expect(
        tester.widget<AppIconButtonFace>(_key('palette-p1-remove')).onPressed,
        isNull,
      );

      await _press(tester, _place('p1', 1));
      expect(desk.color, _blue);
      await _carry(tester, _place('p1', 0), _place('p1', 1));
      expect(desk.slotsOf('p1').take(4), [_red, _blue, null, _red]);
      await _doubleClick(tester, _place('p1', 3));
      expect(_key('palette-place-delete'), findsNothing);

      await _press(tester, _key('palette-p1-lock'));
      expect(desk.palettes.palettes.first.locked, isFalse);
      expect(_shownPlaces('p1'), NamedPalette.slotCount);
      expect(desk.slotsOf('p1').take(4), [_red, _blue, null, _red]);
    });

    testWidgets('a double click on a colour opens its window: the wheel '
        'recolours that place, the delete empties it alone (I-131, 10-28)', (
      tester,
    ) async {
      final desk = await _open(tester);

      await _doubleClick(tester, _place('p1', 0));
      expect(_key('palette-place-delete'), findsOneWidget);
      tester
          .widget<ColorWheel>(find.byType(ColorWheel))
          .onChanged(HSVColor.fromColor(const Color(_green)));
      await tester.pump();
      expect(desk.slotsOf('p1').first, _green);

      await _press(tester, _key('palette-place-delete'));
      expect(_key('palette-place-delete'), findsNothing, reason: 'it closed');
      expect(desk.slotsOf('p1').take(4), [null, _blue, null, _red]);
    });

    testWidgets("the default palette says so by its name's colour alone", (
      tester,
    ) async {
      await _open(tester);
      Color? inkOf(String id) => tester
          .widget<Text>(
            find.descendant(
              of: _key('palette-$id-name'),
              matching: find.byType(Text),
            ),
          )
          .style
          ?.color;
      final accent = Theme.of(
        tester.element(_key('palette-panel')),
      ).colorScheme.primary;

      expect(inkOf('p1'), accent);
      expect(inkOf('p2'), isNot(accent));
    });
  });

  group('the ⋯', () {
    Future<void> choose(WidgetTester tester, String id, String row) async {
      await _press(tester, _key('palette-$id-more'));
      await _press(tester, _key(row));
    }

    testWidgets('makes a palette the default — the default itself has '
        'nothing to make', (tester) async {
      final desk = await _open(tester);

      await choose(tester, 'p1', 'palette-make-default');
      expect(desk.palettes.defaultId, 'p1');
      expect(
        _key('palette-make-default'),
        findsOneWidget,
        reason: 'a dead row takes no press, and the list stays open',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_key('palette-make-default'), findsNothing, reason: '⛔전제');

      await choose(tester, 'p2', 'palette-make-default');
      expect(desk.palettes.defaultId, 'p2');
    });

    testWidgets('duplicates a palette right after itself', (tester) async {
      final desk = await _open(tester);

      await choose(tester, 'p1', 'palette-duplicate');

      expect(desk.palettes.palettes.map((palette) => palette.name), [
        'Skin',
        AppText.strings.paletteCopyName('Skin'),
        'Sky',
      ]);
      expect(desk.palettes.palettes[1].slots, _two().palettes.first.slots);
    });

    testWidgets('deletes through a confirm window, and the top palette left '
        'becomes the default', (tester) async {
      final desk = await _open(tester);

      await choose(tester, 'p1', 'palette-delete');
      expect(_key('palette-delete-dialog'), findsOneWidget);
      await _press(tester, _key('palette-delete-cancel-button'));
      expect(desk.palettes.palettes, hasLength(2));

      await choose(tester, 'p1', 'palette-delete');
      await _press(tester, _key('palette-delete-confirm-button'));
      expect(desk.palettes.palettes.map((palette) => palette.id), ['p2']);
      expect(desk.palettes.defaultId, 'p2');
    });

    testWidgets('never deletes the last palette', (tester) async {
      final desk = await _open(tester, palettes: _two().deleted('p2'));

      await choose(tester, 'p1', 'palette-delete');

      expect(_key('palette-delete-dialog'), findsNothing);
      expect(desk.palettes.palettes, hasLength(1));
    });
  });

  testWidgets('the ＋ makes an empty 「팔레트 N」 on top, one past the highest '
      'N, and the default — as Procreate does', (tester) async {
    final strings = AppText.strings;
    final desk = await _open(
      tester,
      palettes: _two().renamed('p2', strings.paletteNumbered(4)),
    );

    await _press(tester, _key('palette-new'));

    final made = desk.palettes.palettes.first;
    expect(made.name, strings.paletteNumbered(5));
    expect(made.slots, everyElement(isNull));
    expect(desk.palettes.defaultId, made.id);
    expect(_place(made.id, 0), findsOneWidget);
  });

  testWidgets('the view lays every palette at once: cards carry their '
      "colour's hex, compact places none", (tester) async {
    final desk = await _open(tester);
    expect(find.text('#E53935'), findsNothing);

    await _press(tester, _key('palette-view-cards'));

    expect(desk.palettes.view, PaletteView.cards);
    expect(find.text('#E53935'), findsNWidgets(2), reason: 'Skin holds two');
    expect(tester.getSize(_place('p1', 0)), const Size(56, 56));
    // Three cards share a row's width, 8 apart.
    final card = (tester.getSize(_key('palette-p1')).width - 2 * 8) / 3;
    expect(
      tester.getCenter(_place('p1', 2)).dx -
          tester.getCenter(_place('p1', 0)).dx,
      closeTo(2 * (card + 8), 0.01),
    );

    await _press(tester, _key('palette-view-compact'));
    expect(find.text('#E53935'), findsNothing);
  });

  group('under the wheel and the RGB bars', () {
    for (final kind in const [ColorPickerKind.wheel, ColorPickerKind.rgb]) {
      testWidgets('${kind.name}: the default palette answers as it does in '
          'the panel — always compact', (tester) async {
        final desk = await _open(
          tester,
          kind: kind,
          palettes: _two().withView(PaletteView.cards),
        );
        expect(_place('p2', 0), findsNothing, reason: 'the default alone');
        expect(find.text('#E53935'), findsNothing, reason: 'compact');

        await _press(tester, _place('p1', 2));
        expect(desk.slotsOf('p1')[2], _green);

        await _press(tester, _place('p1', 1));
        expect(desk.picks, [_blue]);

        await _carry(tester, _place('p1', 0), _place('p1', 5));
        expect(desk.slotsOf('p1')[5], _red);
        expect(desk.slotsOf('p1')[0], isNull);
      });

      testWidgets('${kind.name}: a locked default stands packed here too — '
          'the same places, not a second set', (tester) async {
        final desk = await _open(
          tester,
          kind: kind,
          palettes: _two().withLocked('p1', locked: true),
        );
        expect(_shownPlaces('p1'), 3);
        expect(_place('p1', 2), findsNothing);

        await _carry(tester, _place('p1', 0), _place('p1', 1));
        expect(desk.slotsOf('p1').take(4), [_red, _blue, null, _red]);
      });
    }

    testWidgets('its places share the width up to 24 a side — a cap the '
        "tab's floor counts on", (tester) async {
      await _open(
        tester,
        kind: ColorPickerKind.wheel,
        size: const Size(280, 600),
      );
      // Ten places and nine gaps of 4 across the room inside its padding.
      final room = tester.getSize(_key('palette-under-picker')).width - 20;
      expect(room, lessThan(10 * 24 + 9 * 4), reason: '⛔전제: they share it');
      expect(
        tester.getSize(_place('p1', 0)).width,
        closeTo((room - 9 * 4) / 10, 0.01),
      );
      expect(
        tester.getTopLeft(_place('p1', 1)).dx -
            tester.getTopRight(_place('p1', 0)).dx,
        closeTo(4, 0.01),
      );

      await _open(
        tester,
        kind: ColorPickerKind.wheel,
        size: const Size(500, 700),
      );
      expect(tester.getSize(_place('p1', 0)), const Size(24, 24));
      expect(
        tester.getSize(_key('palette-under-picker')).height,
        PaletteUnderPicker.maxExtent,
        reason: 'the floor counts what the places stand, their gaps and all',
      );
    });
  });

  test('「팔레트 N」 reads back as N in every language, and no other name '
      'does', () {
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      expect(strings.paletteNumberOf(strings.paletteNumbered(12)), 12);
      expect(strings.paletteNumberOf('Skin'), isNull, reason: '$language');
      expect(
        strings.paletteNumberOf('${strings.paletteNumbered(3)} copy'),
        isNull,
        reason: '$language',
      );
    }
  });
}
