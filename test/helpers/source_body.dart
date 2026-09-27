import 'package:flutter_test/flutter_test.dart';

/// The body of the function whose declaration starts with [signature] in
/// [source]: from its opening brace to the one that closes it.
///
/// The SOURCE PINS read through this — the tests that say what a function
/// does where no machine the suite runs on can run it (an Android activity,
/// Apple's audio session) or where only the order of its calls is the law.
/// Brace-matched, so Dart, Kotlin and C read alike. ⚠️A brace inside a
/// string or a comment counts too: a pinned function holding an unbalanced
/// one would read past its end.
///
/// Call it inside a test: its premise is an expectation.
String sourceBodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: 'premise: $signature is in the file');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i += 1) {
    switch (source[i]) {
      case '{':
        depth += 1;
      case '}':
        depth -= 1;
        if (depth == 0) {
          return source.substring(open, i + 1);
        }
    }
  }
  fail('$signature never closes');
}
