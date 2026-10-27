import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/color_palette_file_service.dart';
import '../helpers/project_scratch_folder.dart';

/// I-131 (Procreate's palettes): named palettes of thirty places, one of
/// them the default, and the recent colours — the model the palette panel
/// and the places under the pickers both change.
void main() {
  const red = 0xFFE53935;
  const blue = 0xFF1E88E5;
  const white = 0xFFFFFFFF;

  ColorPaletteState two() => ColorPaletteState(
    palettes: [
      NamedPalette(
        id: 'p1',
        name: 'Skin',
        slots: NamedPalette.placed(const [red, blue, null, red]),
      ),
      NamedPalette(
        id: 'p4',
        name: 'Sky',
        slots: NamedPalette.placed(const [blue]),
      ),
    ],
    defaultId: 'p1',
  );

  List<int?> slotsOf(ColorPaletteState state, String id) =>
      state.palettes.firstWhere((palette) => palette.id == id).slots;

  test('recent colors dedupe to the front and cap at the limit', () {
    var state = ColorPaletteState.starter('Palette 1');
    for (var i = 0; i < 14; i += 1) {
      state = state.withRecentColor(0xFF000000 + i);
    }
    expect(state.recent, hasLength(ColorPaletteState.maxRecent));
    expect(state.recent.first, 0xFF000000 + 13);

    // Re-using an old color promotes it without duplicating.
    state = state.withRecentColor(0xFF000000 + 10);
    expect(state.recent.first, 0xFF000000 + 10);
    expect(state.recent.where((c) => c == 0xFF000000 + 10), hasLength(1));

    // The current front is a no-op (wheel drags won't churn the row).
    final same = state.withRecentColor(state.recent.first);
    expect(identical(same, state), isTrue);
  });

  test('a machine with no palette starts on one, the default, holding the '
      'quick swatches the single row started with', () {
    final starter = ColorPaletteState.starter('Palette 1');
    expect(starter.palettes, hasLength(1));
    expect(starter.defaultPalette.name, 'Palette 1');
    expect(starter.defaultPalette.slots, hasLength(NamedPalette.slotCount));
    expect(
      starter.defaultPalette.slots.take(4),
      ColorPaletteState.starterColors,
    );
    expect(starter.defaultPalette.slots.skip(4), everyElement(isNull));
    expect(starter.recent, isEmpty);
  });

  test('an empty place takes the current colour — one the palette already '
      'holds goes in all the same', () {
    final filled = two().filled('p1', 2, red);
    expect(slotsOf(filled, 'p1').take(4), [red, blue, red, red]);
    expect(slotsOf(filled, 'p4'), slotsOf(two(), 'p4'), reason: 'p4 alone');
  });

  test('two places trade — a move, where the other was empty', () {
    final traded = two().traded('p1', 0, 1);
    expect(slotsOf(traded, 'p1').take(4), [blue, red, null, red]);

    final moved = two().traded('p1', 3, 2);
    expect(slotsOf(moved, 'p1').take(4), [red, blue, red, null]);
  });

  test('taking a colour out empties every place holding it, and the places '
      'stay where they are', () {
    final emptied = two().emptied('p1', red);
    expect(slotsOf(emptied, 'p1').take(4), [null, blue, null, null]);
    expect(slotsOf(emptied, 'p1'), hasLength(NamedPalette.slotCount));
    expect(two().palettes.first.holds(red), isTrue);
    expect(emptied.palettes.first.holds(red), isFalse);
  });

  test('a rename trims the name, and a blank one keeps the name it had', () {
    expect(two().renamed('p4', '  Sea ').palettes[1].name, 'Sea');
    expect(two().renamed('p4', '   ').palettes[1].name, 'Sky');
  });

  test('a new palette is empty, on top, and the default — as Procreate '
      'makes one', () {
    final made = two().withNewPalette('Palette 2');
    expect(made.palettes.map((palette) => palette.name), [
      'Palette 2',
      'Skin',
      'Sky',
    ]);
    expect(made.palettes.first.slots, everyElement(isNull));
    expect(made.palettes.first.slots, hasLength(NamedPalette.slotCount));
    expect(made.defaultId, made.palettes.first.id);
    expect(
      made.palettes.first.id,
      'p5',
      reason: 'one past the highest number among the ids',
    );
  });

  test('a copy stands right after its palette, under a new id and the name '
      'it is given', () {
    final copied = two().duplicated('p1', 'Skin copy');
    expect(copied.palettes.map((palette) => palette.name), [
      'Skin',
      'Skin copy',
      'Sky',
    ]);
    expect(copied.palettes[1].slots, two().palettes.first.slots);
    expect(copied.palettes[1].id, isNot(anyOf('p1', 'p4')));
    expect(copied.defaultId, 'p1', reason: 'the default stays');
  });

  test('deleting the default makes the top palette left the default; the '
      'last palette is never deleted', () {
    final withoutDefault = two().deleted('p1');
    expect(withoutDefault.palettes.map((palette) => palette.id), ['p4']);
    expect(withoutDefault.defaultId, 'p4');

    final withoutOther = two().deleted('p4');
    expect(withoutOther.defaultId, 'p1');

    final last = withoutDefault.deleted('p4');
    expect(identical(last, withoutDefault), isTrue);
  });

  test('the default and the view are set as asked', () {
    expect(two().withDefault('p4').defaultPalette.name, 'Sky');
    expect(two().withView(PaletteView.cards).view, PaletteView.cards);
  });

  test('a document is read as far as it holds — places laid on thirty, a '
      'default it does not name falls to the first', () {
    final read = ColorPaletteState.fromJson({
      'palettes': [
        {
          'id': 'p2',
          'name': 'Read',
          'slots': [red, 'blue', null, ...List.filled(40, white)],
        },
        {'id': 3, 'name': 'no id'},
      ],
      'default': 'gone',
      'view': 'shelves',
      'recent': [blue, 'red', ...List.filled(20, white)],
    })!;
    expect(read.palettes.map((palette) => palette.id), ['p2']);
    expect(read.defaultId, 'p2');
    expect(read.view, PaletteView.compact);
    expect(read.palettes.first.slots, hasLength(NamedPalette.slotCount));
    expect(read.palettes.first.slots.take(4), [red, null, null, white]);
    expect(read.recent, hasLength(ColorPaletteState.maxRecent));
    expect(read.recent.first, blue);
  });

  test('palettes persist through the file service; a corrupt file, and the '
      'single row the file held before I-131, yield the starter', () async {
    final directory = await Directory.systemTemp.createTemp('palette-test');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}/palette.json';

    final service = ColorPaletteFileService(filePath: path);
    final saved = two()
        .withDefault('p4')
        .withView(PaletteView.cards)
        .withRecentColor(white);
    await service.save(saved);
    final restored = await ColorPaletteFileService(
      filePath: path,
    ).loadOrDefaults();
    expect(restored.toJson(), saved.toJson());
    expect(restored.view, PaletteView.cards, reason: 'one side writes it');

    File(path).writeAsStringSync('not json');
    final fallback = await ColorPaletteFileService(
      filePath: path,
    ).loadOrDefaults(starterName: 'パレット 1');
    expect(fallback.palettes.single.name, 'パレット 1');

    File(path).writeAsStringSync(
      '{"version":1,"pinned":[4278190080],"recent":[4294967295]}',
    );
    final before = await ColorPaletteFileService(
      filePath: path,
    ).loadOrDefaults();
    expect(before.toJson(), ColorPaletteState.starter('Palette 1').toJson());
  });
}
