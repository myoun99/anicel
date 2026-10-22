@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';

/// 🚨A FRAGMENT SHADER THAT SAMPLES A TEXTURE HAS NO `return` IN `main()`.
///
/// Windows runs Impeller as GLES through ANGLE, which hands every shader to
/// D3D's compiler as HLSL — and that compiler can crash on a shader that
/// samples a texture and returns early (flutter#190809). The issue was
/// closed on 2026-09-29 with a compiler WARNING for exactly that pair, not a
/// fix, and a warning scrolls past in a build log. This fails instead.
///
/// ⚠️THE SAME QUESTION THE WARNING ASKS (impellerc, flutter#191969):
/// comments stripped, `main`'s body found by its braces, any `return` in it,
/// in a shader that has a sampler. Asked the same way on purpose, so a
/// shader this passes is one the SDK does not warn about either.
void main() {
  test('no shader that samples a texture returns from main()', () {
    final sampling = <String>[];
    final offenders = <String>[];
    for (final file in Directory('shaders').listSync().whereType<File>()) {
      if (!file.path.endsWith('.frag')) {
        continue;
      }
      final source = withoutComments(file.readAsStringSync());
      if (!RegExp(r'\bsampler2D\b').hasMatch(source)) {
        continue;
      }
      final body = bodyOf(source, _main);
      expect(body, isNotNull, reason: '${file.path} has no main() to read');
      sampling.add(file.uri.pathSegments.last);
      if (RegExp(r'\breturn\b').hasMatch(body!)) {
        offenders.add(file.path);
      }
    }
    // A scan that found nothing to read passes on an empty folder too.
    expect(sampling, contains('colour_key.frag'));
    expect(
      offenders,
      isEmpty,
      reason: 'These sample a texture and return from main(), the shape '
          'D3D can crash on under ANGLE (flutter#190809). Let the value '
          'fall through to the end instead — a select, not a return.',
    );
  });

  test('the reading finds a return where the crash shape has one', () {
    const crashShape = '''
uniform sampler2D uSource;
out vec4 fragColor;
void main() {
  vec4 src = texture(uSource, vec2(0.0));
  if (src.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  fragColor = src;
}
''';
    final body = bodyOf(withoutComments(crashShape), _main)!;
    expect(body, contains('return;'));
    // The inner braces did not end main early: the body runs to its end.
    expect(
      body.substring(0, body.length - 1).trimRight(),
      endsWith('fragColor = src;'),
    );
    // A `return` inside a comment is not one.
    expect(
      bodyOf(
        withoutComments('void main() { // return;\n /* return; */ }'),
        _main,
      ),
      isNot(contains('return')),
    );
  });
}

/// Where `main(...)` begins; its body is read the one way ([bodyOf]).
final _main = RegExp(r'\bmain\s*\([^)]*\)');
