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
void main() {
  const seam = 'lib/src/services/cel_surface_as_shown.dart';
  const keysPass = 'lib/src/services/cel_source_effect_pass.dart';
  const call = 'celSurfaceWithSourceEffects(';

  /// The lines of [source] that CALL the keys' pass — a mention in a
  /// comment is not a call, and the pass's own declaration is not one.
  List<String> callsIn(String source) => [
    for (final line in source.split('\n'))
      if (line.contains(call) &&
          !line.trimLeft().startsWith('//') &&
          !line.trimLeft().startsWith('BitmapSurface $call'))
        line.trim(),
  ];

  List<String> straysUnder(String root, {required Set<String> allowed}) => [
    for (final file in dartFilesUnder(root))
      if (!allowed.contains(file.path.replaceAll(r'\', '/')))
        for (final line in callsIn(file.readAsStringSync()))
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

  test('the seam lays the texts and keys what they made — once each', () {
    final source = File(seam).readAsStringSync();

    expect(callsIn(source), hasLength(1));
    expect(
      source.contains(
        'celSurfaceWithSourceEffects(celSurfaceWithTextsLaid(surface), '
        'effects)',
      ),
      isTrue,
      reason:
          'the order is the order they exist in: the texts are part of the '
          'picture, the keys filter that picture',
    );
  });

  test('fixture: the pass is declared where this test thinks it is', () {
    expect(
      File(keysPass).readAsStringSync(),
      contains('BitmapSurface $call'),
    );
  });

  test('🚨the scan sees a stray when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-seam');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/a_route.dart').writeAsStringSync(
      'void draw() {\n'
      '  // celSurfaceWithSourceEffects(surface, effects) is the old seam\n'
      '  final shown = celSurfaceWithSourceEffects(surface, effects);\n'
      '}\n',
    );
    File('${planted.path}/a_good_route.dart').writeAsStringSync(
      'void draw() {\n'
      '  final shown = celSurfaceAsShown(surface, effects);\n'
      '}\n',
    );

    final found = straysUnder(planted.path, allowed: const {});

    expect(found, hasLength(1), reason: 'one call, and a comment beside it');
    expect(found.single, contains('a_route.dart'));
    expect(found.single, contains('final shown = '));
  });
}
