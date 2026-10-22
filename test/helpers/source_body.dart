import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';

/// The body of the declaration that starts with [signature] in [source]:
/// from its opening brace to the one that closes it.
///
/// The SOURCE PINS read through this — the tests that say what a function
/// does where no machine the suite runs on can run it (an Android activity,
/// Apple's audio session) or where only the order of its calls is the law.
/// Brace-matched by the one reading ([bodyOf]), so Dart, Kotlin, Swift and
/// C read alike, and a brace inside a string or a comment is not one.
/// [signature] is a plain string, or a [RegExp] where the name must stand
/// alone (`class Foo\b` is not `class FooBar`).
///
/// Call it inside a test: its premise is an expectation.
String sourceBodyOf(String source, Pattern signature) {
  final shown = signature is RegExp ? signature.pattern : signature;
  expect(
    signature.allMatches(source),
    isNotEmpty,
    reason: 'premise: $shown is in the file',
  );
  return bodyOf(source, signature) ?? fail('$shown never closes');
}
