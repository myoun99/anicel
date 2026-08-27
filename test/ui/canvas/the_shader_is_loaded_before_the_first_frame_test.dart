import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A GATE THAT OPENS ON AN UNLOADED PROGRAM IS A CRASH.
///
/// The colour key on a folder is a fragment shader, and a `Paint` is built
/// INSIDE a paint — which cannot wait for an asset. So `ColourKeyShader`
/// throws when its program is not there, and the only thing that makes that
/// throw unreachable is loading it before the first frame.
///
/// ⛔THIS IS NOT HYPOTHETICAL. The round that opened `effectKindsFor` to
/// every kind shipped without the load: the moment a folder took a colour
/// key, the composite threw. A structural audit found it, and this is what
/// keeps the next round from doing it again.
///
/// A source check, because nothing else can see it. `main()` runs once, at
/// startup, and a test that pumps a widget has already missed it.
void main() {
  test('main() awaits the colour key program before runApp', () {
    final source = File('lib/main.dart').readAsStringSync();
    final loadAt = source.indexOf('await ColourKeyShader.load()');
    expect(
      loadAt,
      greaterThanOrEqualTo(0),
      reason: 'lib/main.dart must await ColourKeyShader.load() — without it '
          'a folder with a colour key throws on its first paint',
    );
    final runAppAt = source.indexOf('runApp(');
    expect(runAppAt, greaterThanOrEqualTo(0), reason: 'fixture: main runs an app');
    expect(
      loadAt,
      lessThan(runAppAt),
      reason: 'the program has to be in hand BEFORE the first frame, not '
          'racing it',
    );
  });

  test('the shader asset is declared, or the load cannot find it', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('shaders:'));
    expect(pubspec, contains('shaders/colour_key.frag'));
    expect(
      File('shaders/colour_key.frag').existsSync(),
      isTrue,
      reason: 'the declared shader must exist on disk',
    );
  });
}
