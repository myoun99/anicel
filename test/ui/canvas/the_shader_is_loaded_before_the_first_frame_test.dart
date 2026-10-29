import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';

/// 🚨★★★A GATE THAT OPENS ON AN UNLOADED PROGRAM IS A CRASH.
///
/// The colour key on a folder is a fragment shader, and a `Paint` is built
/// INSIDE a paint — which cannot wait for an asset. So `ColourKeyShader`
/// throws when its program is not there, and the only thing that makes that
/// throw unreachable is loading it before the first frame. A layer whose
/// blend the GPU lacks is composed by `LayerBlendShader` (brush-fidelity-Q4),
/// and a chain's directional, radial and camera lens blurs by theirs, under
/// the same law.
///
/// ⛔THIS IS NOT HYPOTHETICAL. The round that opened `effectKindsFor` to
/// every kind shipped without the load: the moment a folder took a colour
/// key, the composite threw. A structural audit found it, and this is what
/// keeps the next round from doing it again.
///
/// A source check, because nothing else can see it. `main()` runs once, at
/// startup, and a test that pumps a widget has already missed it.
///
/// ⛔EVERY PROGRAM, FOUND, NOT LISTED: every one is a
/// `LoadedFragmentProgram`, and the class that keeps it is what `main()`
/// loads. ↩️A list of two, the colour key's and the blend's, which the
/// directional blur's program never joined.
void main() {
  final loaders = <String, List<String>>{};
  final unowned = <String>[];
  for (final file in dartFilesUnder('lib')) {
    final source = file.readAsStringSync();
    final assets = [
      for (final match in RegExp(
        r"LoadedFragmentProgram\(\s*'([^']+)'",
      ).allMatches(source))
        match.group(1)!,
    ];
    if (assets.isEmpty) {
      continue;
    }
    final owners = RegExp(r'^class (\w+)', multiLine: true)
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toList();
    if (owners.length != 1) {
      unowned.add(libPath(file));
      continue;
    }
    loaders[owners.single] = assets;
  }

  test('a file keeps its programs in one class, the one main() loads', () {
    expect(unowned, isEmpty);
  });

  test('the scan finds every program the composite draws with', () {
    expect(
      loaders.values.expand((assets) => assets),
      containsAll([
        'shaders/colour_key.frag',
        'shaders/layer_blend.frag',
        'shaders/directional_blur.frag',
        'shaders/row_sum.frag',
        'shaders/iris_table.frag',
        'shaders/iris_gather.frag',
      ]),
    );
  });

  for (final MapEntry(key: loader, value: assets) in loaders.entries) {
    test('main() awaits $loader before runApp', () {
      final source = File('lib/main.dart').readAsStringSync();
      final loadAt = source.indexOf('await $loader.load()');
      expect(
        loadAt,
        greaterThanOrEqualTo(0),
        reason: 'lib/main.dart must await $loader.load() — without it the '
            'first paint that needs the program throws',
      );
      final runAppAt = source.indexOf('runApp(');
      expect(
        runAppAt,
        greaterThanOrEqualTo(0),
        reason: 'fixture: main runs an app',
      );
      expect(
        loadAt,
        lessThan(runAppAt),
        reason: 'the program has to be in hand BEFORE the first frame, not '
            'racing it',
      );
    });

    for (final asset in assets) {
      test('$asset is declared, or the load cannot find it', () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('shaders:'));
        expect(pubspec, contains(asset));
        expect(
          File(asset).existsSync(),
          isTrue,
          reason: 'the declared shader must exist on disk',
        );
      });
    }
  }
}
