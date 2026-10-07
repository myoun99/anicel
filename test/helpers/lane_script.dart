import 'package:flutter_test/flutter_test.dart';

/// `tool/lane.sh`, cut into its functions — for the tests that pin WHERE
/// the script does a thing. The suite spawns no process
/// (tests_do_not_race_the_code_test), so what the script DOES is run by
/// hand in scratch repositories, and what holds each step in its place is
/// the order of its lines.
///
/// 🪦Two tests each carried their own cut until a third needed one
/// (2026-10-07) — the rule of three.
///
/// ⚠️The caller reads the file, `File('tool/lane.sh')` spelled out in the
/// test: the affected-tests selector finds a source scan by the path the
/// TEST names.
class LaneScript {
  LaneScript(String text) : text = text.replaceAll('\r\n', '\n');

  final String text;

  /// Every function written over several lines, in the order the script
  /// has them.
  late final List<String> functions = [
    for (final m in RegExp(r'\n([a-z_]+)\(\) \{\n').allMatches(text))
      m.group(1)!,
  ];

  /// The whole of [function], comments and all.
  String body(String function) {
    final start = text.indexOf('\n$function() {\n');
    expect(start, isNot(-1), reason: 'LIVENESS — $function is in the script');
    return text.substring(start, text.indexOf('\n}\n', start));
  }

  /// [function] line by line with every comment line blanked, so a word
  /// that only a comment says is not found in the code.
  List<String> codeOf(String function) => [
    for (final line in body(function).split('\n'))
      if (line.trimLeft().startsWith('#')) '' else line,
  ];
}
