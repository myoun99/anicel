@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/code_map.dart';

/// 🚨★★★THE INSTRUMENT THE AUDIT STANDS ON.
///
/// `tool/code_map.dart` produces the numbers every later step ranks by — what
/// is big, what holds the most state, what forks the most, what would be
/// noticed if it moved. If it counts wrong, every ranking built on it is
/// wrong in the same direction and nothing downstream can tell.
///
/// ⛔SO THE FIRST CASE CHECKS THE PREMISE. A map of an empty walk passes every
/// "nothing is miscounted" assertion trivially, and that failure mode has cost
/// this repo real rounds. If the fixture is not read, the first test fails and
/// says so.
///
/// ⚠️IT LIVES HERE AND NOT IN `test/tool/`. `.githooks/pre-push` treats
/// `^(tool/board_[a-z_]+\.dart|test/tool/)` as board-only and pushes it
/// straight to master without a PR — correct for the board, wrong for audit
/// machinery, which wants CI on four platforms like any other change.
void main() {
  late Directory dir;

  /// Writes [name] with [source] into the fixture directory.
  void write(String name, String source) {
    File('${dir.path}/$name').writeAsStringSync(source);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('code_map_fixture');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// A file exercising every declaration shape the map claims to count.
  const alpha = '''
import 'dart:math';
import 'beta.dart';
import 'package:flutter/material.dart';

int topLevel(int x) {
  int helper(int y) => y + 1;
  if (x > 0 && x < 10) return helper(x);
  return x ?? 0;
}

class Thing {
  Thing(this.a);
  int a = 0;
  int _b = 1;
  int get sum => a + _b;
  set sum(int v) {
    a = v;
  }

  void doIt() {
    for (var i = 0; i < 3; i++) {
      if (i == 1) continue;
    }
  }
}
''';

  const beta = '''
class Other {
  void nothing() {}
}
''';

  CodeMap mapOf(Map<String, String> files) {
    files.forEach(write);
    return CodeMap.walk(dir.path);
  }

  group('the premise', () {
    test('the fixture is actually read — an empty walk proves nothing', () {
      final map = mapOf({'alpha.dart': alpha, 'beta.dart': beta});
      expect(map.files, hasLength(2), reason: 'the walk found no files, so '
          'every other expectation in this file would pass vacuously');
      expect(map.unreadable, isEmpty);
      expect(map.functions, isNotEmpty);
      expect(map.types, isNotEmpty);
    });
  });

  group('declarations', () {
    test('every member shape is counted, and a local function is not', () {
      final map = mapOf({'alpha.dart': alpha, 'beta.dart': beta});
      final inAlpha = map.functions.where((f) => f.file.endsWith('alpha.dart'));

      expect(
        inAlpha.map((f) => '${f.kind}:${f.qualified}').toSet(),
        {
          'function:topLevel',
          'constructor:Thing.(default)',
          'getter:Thing.sum',
          'setter:Thing.sum',
          'method:Thing.doIt',
        },
        reason: '⛔`helper` is a LOCAL function. Counting it as its own entry '
            'would double-count its body — once as itself and once inside '
            'topLevel, which is where its complexity already lands.',
      );
    });

    test('a method knows its owner and a top-level function has none', () {
      final map = mapOf({'alpha.dart': alpha});
      final byName = {for (final f in map.functions) f.name: f};
      expect(byName['topLevel']!.owner, isNull);
      expect(byName['doIt']!.owner, 'Thing');
    });

    test('state and behaviour are counted separately', () {
      final map = mapOf({'alpha.dart': alpha});
      final thing = map.types.singleWhere((t) => t.name == 'Thing');
      expect(thing.kind, 'class');
      // a, _b
      expect(thing.fields, 2);
      // ctor, get sum, set sum, doIt
      expect(thing.methods, 4);
      // everything but `_b`
      expect(thing.publicMembers, 5);
    });

    test('a multi-modifier class is still one class', () {
      // 🧪This is the exact shape a `^(abstract |sealed |final )?class ` grep
      // missed on `lib/`: 31 `abstract final class` + 4 `abstract interface
      // class` = the 35 the parser found and the grep did not.
      final map = mapOf({
        'mods.dart': '''
abstract final class A {}
abstract interface class B {}
sealed class C {}
mixin M {}
enum E { one, two }
extension X on int { int get twice => this * 2; }
typedef T = int Function(int);
''',
      });
      expect(
        map.types.map((t) => '${t.kind}:${t.name}').toSet(),
        {
          'class:A',
          'class:B',
          'class:C',
          'mixin:M',
          'enum:E',
          'extension:X',
          'typedef:T',
        },
      );
    });

    test('an enum case is counted, and it is not counted as state', () {
      // ⚠️Folding constants into `fields` would rank a 40-case enum above a
      // session object on the god-object table, which is the table's whole
      // purpose. They are still worth SEEING, so they get their own number
      // rather than being dropped.
      //
      // 🧪This assertion had to be rewritten to earn its place: it first read
      // only `fields == 0`, and no edit could make that fail —
      // `EnumConstantDeclaration` is not a `ClassMember`, so the compiler
      // already refused the mistake. A test that cannot fail is a comment
      // wearing a test's clothes.
      final map = mapOf({
        'e.dart': 'enum Big { a, b, c, d, e, f, g, h }',
      });
      expect(map.types.single.fields, 0);
      expect(map.types.single.constants, 8);
    });
  });

  group('complexity', () {
    int complexityOf(String source, String name) {
      final map = mapOf({'c.dart': source});
      return map.functions.singleWhere((f) => f.name == name).complexity;
    }

    test('straight-line code scores 1', () {
      expect(complexityOf('int f() { return 1; }', 'f'), 1);
    });

    test('every fork counts, including && || ??', () {
      // 1 + if + && + ?? = 4
      expect(
        mapOf({'alpha.dart': alpha})
            .functions
            .singleWhere((f) => f.name == 'topLevel')
            .complexity,
        4,
      );
    });

    test('a boolean operator chain is not free', () {
      // ⛔A version counting only STATEMENTS scores this 1. The repo is full
      // of guard-heavy predicates whose whole complexity is in the condition.
      expect(complexityOf('bool f(int a) => a > 0 && a < 5 || a == 9;', 'f'), 3);
    });

    test('loops, switches and catches each fork', () {
      expect(
        complexityOf('''
int f(int a) {
  for (var i = 0; i < 2; i++) {}
  while (a > 0) { a--; }
  do { a++; } while (a < 0);
  try { a++; } catch (_) {}
  switch (a) {
    case 1: break;
    case 2: break;
  }
  return a;
}
''', 'f'),
        // 1 + for + while + do + catch + 2 cases
        7,
      );
    });
  });

  group('the import graph', () {
    test('a relative import is an edge and fan-in counts it', () {
      final map = mapOf({'alpha.dart': alpha, 'beta.dart': beta});
      final a = map.files.values.singleWhere((f) => f.path.endsWith('alpha.dart'));
      final b = map.files.values.singleWhere((f) => f.path.endsWith('beta.dart'));

      expect(a.imports, hasLength(1));
      expect(a.imports.single, endsWith('beta.dart'));
      expect(b.fanIn, 1, reason: 'beta is imported by alpha');
      expect(a.fanIn, 0);
    });

    test('dart: and other packages are not edges', () {
      // ⚠️`alpha.dart` imports `dart:math` and `package:flutter/material.dart`
      // as well. An edge to Flutter would out-rank every real file on the
      // fan-in table without answering anything the audit asks.
      final map = mapOf({'alpha.dart': alpha, 'beta.dart': beta});
      final a = map.files.values.singleWhere((f) => f.path.endsWith('alpha.dart'));
      expect(a.imports.where((i) => i.contains('math')), isEmpty);
      expect(a.imports.where((i) => i.contains('material')), isEmpty);
    });
  });

  group('lines', () {
    test('a file counts the lines `wc -l` would count', () {
      // 🧪The bug this pins: `LineInfo.lineCount` counts the empty position
      // after a trailing newline, so it read one high on EVERY file. Across
      // `lib/` the totals differed by 809 — exactly the file count.
      final map = mapOf({'three.dart': 'var a = 1;\nvar b = 2;\nvar c = 3;\n'});
      expect(map.files.values.single.lines, 3);
    });

    test('a file with no trailing newline is not counted short', () {
      final map = mapOf({'two.dart': 'var a = 1;\nvar b = 2;'});
      expect(map.files.values.single.lines, 2);
    });
  });

  group('a hole in the map is loud', () {
    test('a file that does not parse lands in `unreadable`', () {
      // 🚨★★★THE WORST FAILURE THIS TOOL CAN HAVE is reading 806 of 809 files
      // and reporting the totals as if they were all of them. Every count
      // would be quietly low and the screen would say nothing.
      final map = mapOf({
        'good.dart': beta,
        'broken.dart': 'class Oops { void f( { } }} )]',
      });
      expect(
        map.unreadable.keys.map((p) => p.split('/').last),
        contains('broken.dart'),
        reason: 'a syntax error must not be swallowed as an empty tree',
      );
      expect(
        map.files.keys.map((p) => p.split('/').last),
        isNot(contains('broken.dart')),
        reason: 'a partially-parsed tree must not contribute counts',
      );
      // ⚠️And the rest of the walk still reports — refusing everything would
      // be a different kind of useless.
      expect(map.files, hasLength(1));
      expect(map.types.map((t) => t.name), ['Other']);
    });
  });
}
