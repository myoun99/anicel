import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';

/// 🚨WHERE A BRACKET CLOSES, READ THE ONE WAY — `tool/source_brackets.dart`
/// (2026-10-18, source-scans-count-brackets-by-hand): what every source
/// scan and source tool asks of a body, a call's arguments or one argument.
/// The ways a reading of it went wrong are each pinned here, on text whose
/// answer is known.
void main() {
  test('a bracket in a string or a comment is not one', () {
    expect(matchingClose("f(')', x) + 1", 1), 8);
    expect(matchingClose('f(a, // )\n b)', 1), 12);
    expect(matchingClose('f(a /* ) */, b)', 1), 14);
    expect(matchingClose("f('{', b)", 1), 8, reason: 'a C character');
  });

  test('a raw string escapes nothing, a tripled one runs over lines, and '
      'one in one quote ends with its line', () {
    expect(matchingClose(r"f(r'\', b)", 1), 9);
    expect(matchingClose("f('''\n)\n''', b)", 1), 14);
    expect(
      matchingClose("f('unclosed\n, b)", 1),
      15,
      reason: 'the misreading stops at the line, not at the end of the file',
    );
  });

  test('the code inside an interpolation is read as code, strings in it '
      'and all', () {
    // 「'${on ? '(' : ''}'」 holds no bracket: the `(` is a string's.
    expect(matchingClose("f('\${on ? '(' : ''}', b)", 1), 23);
    expect(matchingClose('f("\${foo("x")}", b)', 1), 18, reason: 'Kotlin');
  });

  test('a bracket the text never closes answers null', () {
    expect(matchingClose('f(a, b', 1), isNull);
    expect(callArguments('f(a, b', 1), isNull);
  });

  test("a call's arguments are cut at its own commas, and a trailing comma "
      'makes none', () {
    expect(callArguments('f(a: 1, b: g(x, y), c: [1, 2],)', 1), [
      'a: 1',
      ' b: g(x, y)',
      ' c: [1, 2]',
    ]);
    expect(callArguments('f()', 1), isEmpty);
    expect(callArguments('f(a, // why\n)', 1), ['a']);
  });

  test("a named argument is the call's own — not one nested in another, "
      'and not one whose name only ends in it', () {
    const call = "Item(child: Item(enabled: false), debugName: 'a', "
        "name: 'b')";
    expect(namedArgument(call, 4, 'enabled'), isNull);
    expect(namedArgument(call, 4, 'name'), "'b'");
    expect(
      namedArgument('Item(\n  // why\n  enabled:   false,\n)', 4, 'enabled'),
      'false',
      reason: 'on one line, the comment before it out',
    );
  });

  test('the first named argument WITHIN a call is its own, or one written '
      'inside it — in the order written', () {
    const pill = "Pill(head: Cell(keyValue: 'a'), keyValue: 'b')";
    expect(namedArgumentWithin(pill, 4, 'keyValue'), "'a'");
    const row = "Pill(children: [Row(keyValue: 'c')])";
    expect(namedArgumentWithin(row, 4, 'keyValue'), "'c'");
    const said = "Pill(label: 'keyValue: x')";
    expect(
      namedArgumentWithin(said, 4, 'keyValue'),
      isNull,
      reason: 'a string is not an argument',
    );
  });

  test('a body is read from the first brace after its signature — past a '
      'named parameter list, and past one in a comment', () {
    const named = 'void f({int a = 1}) { if (x) { y(); } }';
    expect(bodyOf(named, 'void f({int a = 1})'), '{ if (x) { y(); } }');
    expect(bodyOf('void f() // {\n{ a; }', 'void f()'), '{ a; }');
    expect(
      bodyOf(
        'class Foo extends Bar {\n  int x;\n}\nclass FooBar {}',
        RegExp(r'\bclass\s+Foo\b'),
      ),
      '{\n  int x;\n}',
    );
    expect(bodyOf('void g() {}', 'void f()'), isNull);
  });

  test('comments come out and strings stay whole', () {
    expect(
      withoutComments("a // b\nc /* d */ e 'f // g'"),
      "a \nc  e 'f // g'",
    );
  });
}
