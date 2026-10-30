import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨★★★A CEL IS SHOWN THROUGH ONE SEAM (R9-rest, the text tool).
///
/// 유저 2026-10-06: a text on a cel is 「셀의 그림이랑 정확히 동일」. What a cel
/// shows is therefore two passes over its own bytes — its texts laid over
/// the drawing, then the row's colour keys — and they run in ONE function,
/// `celSurfaceAsShown`, that every route which draws a cel calls: the
/// shared plan, the editing stack's row images, the row being drawn on, the
/// conte's live picture.
///
/// ⛔A behaviour test cannot hold this. Before texts existed the keys' pass
/// (`celSurfaceWithSourceEffects`) WAS the seam, and it still works: a new
/// route that calls it draws every cel right today — every cel without a
/// text, which is every cel a test fixture happens to hold — and shows a
/// cel that carries one with its letters missing, on that route only. So
/// the rule is read off the source: nothing under `lib/` calls the keys'
/// pass but the seam.
///
/// The pass has a second door now: a text a hand carries on a row that
/// keys is shown as the bytes it will land as, keyed over a region of its
/// cel rather than over its tiles (`celSourceEffectsOverStraight`,
/// F-344-Q3). It is the same pass and the same hazard, so it is held to the
/// same seam.
///
/// And a third: a live stroke shows its result in place of the cel's tile
/// at every coordinate it changes, so the result is shown as the tile the
/// cel will show there — one tile (`celTileWithSourceEffects`), or its
/// bytes before they are one (card a-stroke-on-a-keyed-row-shows-its-tiles-
/// unkeyed: a keyed sheet's ground showed bare under the pen).
void main() {
  const seam = 'lib/src/services/cel_surface_as_shown.dart';
  const keysPass = 'lib/src/services/cel_source_effect_pass.dart';

  /// The doors into the keys' pass, each with how it is declared.
  const doors = {
    'celSurfaceWithSourceEffects(':
        'BitmapSurface celSurfaceWithSourceEffects(',
    'celTileWithSourceEffects(': 'BitmapTile celTileWithSourceEffects(',
    'celSourceEffectsOverStraight(': 'void celSourceEffectsOverStraight(',
  };

  /// How many roads in the seam open each door: a cel, one of its tiles,
  /// and bytes that are no tile yet — a landing text's region and a live
  /// stroke's tile.
  const roads = {
    'celSurfaceWithSourceEffects(': 1,
    'celTileWithSourceEffects(': 1,
    'celSourceEffectsOverStraight(': 2,
  };

  /// The lines of [source] that CALL [door] — a mention in a comment is not
  /// a call, and the door's own declaration is not one.
  List<String> callsIn(String source, String door) => [
    for (final line in source.split('\n'))
      if (line.contains(door) &&
          !line.trimLeft().startsWith('//') &&
          !line.trimLeft().startsWith(doors[door]!))
        line.trim(),
  ];

  List<String> straysUnder(String root, {required Set<String> allowed}) => [
    for (final file in dartFilesUnder(root))
      if (!allowed.contains(file.path.replaceAll(r'\', '/')))
        for (final door in doors.keys)
          for (final line in callsIn(file.readAsStringSync(), door))
            '${file.path.replaceAll(r'\', '/')}: $line',
  ];

  test('nothing under lib/ keys a cel\'s tiles but the seam', () {
    expect(
      straysUnder('lib', allowed: {seam}),
      isEmpty,
      reason:
          'these take the colour keys\' pass on its own, so the cel they '
          'draw is shown WITHOUT the texts it carries — call '
          '`celSurfaceAsShown`, which lays them first',
    );
  });

  test('the seam lays the texts and keys what they made — once a road', () {
    final source = File(seam).readAsStringSync();
    final flat = source.replaceAll(RegExp(r'\s+'), '');

    for (final door in doors.keys) {
      expect(callsIn(source, door), hasLength(roads[door]), reason: door);
    }
    const order =
        'the order is the order they exist in: the texts are part of the '
        'picture, the keys filter that picture';
    expect(
      source.contains(
        'celSurfaceWithSourceEffects(celSurfaceWithTextsLaid(surface), '
        'effects)',
      ),
      isTrue,
      reason: order,
    );
    expect(
      flat,
      contains(
        'celTileWithSourceEffects(plates==null?tile:'
        'celTileWithPlatesLaid(tile,plates,tileSize)!,effects,tileSize,)',
      ),
      reason: 'a tile: $order',
    );
    expect(
      flat,
      contains(
        'layPlatesOverStraight(straight,plates,tileSize);}'
        'celSourceEffectsOverStraight(straight,effects);',
      ),
      reason: 'a live tile\'s bytes: $order',
    );
  });

  /// 🗣️I-132-Q32 b: a plugin runs where the keys run, after them — so it
  /// is one more step of the keys' pass, and a route that ran it alone
  /// would show a cel through the plugin without its texts or its keys.
  test('nothing under lib/ runs a plugin over a cel but the keys\' pass', () {
    const door = 'celSurfaceThroughPlugin(';
    const declared = 'BitmapSurface celSurfaceThroughPlugin(';
    final calls = [
      for (final file in dartFilesUnder('lib'))
        for (final line in file.readAsStringSync().split('\n'))
          if (line.contains(door) &&
              !line.trimLeft().startsWith('//') &&
              !line.trimLeft().startsWith(declared))
            '${file.path.replaceAll(r'\', '/')}: ${line.trim()}',
    ];
    expect(calls, hasLength(1));
    expect(calls.single, startsWith('$keysPass: '));
    expect(
      File(
        'lib/src/services/cel_plugin_pass.dart',
      ).readAsStringSync(),
      contains(declared),
    );
  });

  test('fixture: the pass is declared where this test thinks it is', () {
    final source = File(keysPass).readAsStringSync();
    for (final declared in doors.values) {
      expect(source, contains(declared));
    }
  });

  test('🚨the scan sees a stray when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-seam');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/a_route.dart').writeAsStringSync(
      'void draw() {\n'
      '  // celSurfaceWithSourceEffects(surface, effects) is the old seam\n'
      '  final shown = celSurfaceWithSourceEffects(surface, effects);\n'
      '  final keyed = celTileWithSourceEffects(tile, effects, 8);\n'
      '  celSourceEffectsOverStraight(bytes, effects);\n'
      '}\n',
    );
    File('${planted.path}/a_good_route.dart').writeAsStringSync(
      'void draw() {\n'
      '  final shown = celSurfaceAsShown(surface, effects);\n'
      '}\n',
    );

    final found = straysUnder(planted.path, allowed: const {});

    expect(found, hasLength(3), reason: 'a call of each door, and a comment');
    expect(found, everyElement(contains('a_route.dart')));
    expect(found.first, contains('final shown = '));
    expect(found[1], contains('celTileWithSourceEffects(tile'));
    expect(found.last, contains('celSourceEffectsOverStraight(bytes'));
  });
}
