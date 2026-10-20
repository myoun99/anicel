import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';

/// 🚨EVERY TEST THAT WAITS OUT THE WAIT WINDOW ENDS BY STOPPING PLAYBACK'S
/// WARMER — see `pumpPastTheWaitWindow`.
///
/// The failure it closes is a flake, and that is why it is a scan: the
/// warmer starts on the REAL clock, so a body that forgot the stop passes on
/// a quiet machine and fails on a busy one (「A Timer is still pending even
/// after the widget tree was disposed」 — 2026-10-08: the PDF % test, 2 runs
/// in 8 on one master, 1 in 8 on another lane of it, every one at the
/// warmer's step between two pictures). Twenty-three tests waited out the
/// window that day, and not one of them stopped it.
///
/// 🚨A HELPER A TEST WAITS THROUGH IS HELD TO IT TOO, and stops the warmer
/// itself — once, for every test that waits through it (card
/// warmer-scan-sees-helpers, 2026-10-16). The scan read only `testWidgets`
/// bodies, so a test that waited inside a helper was never asked: 10-10's
/// `place()` was one, and the import window's two `runImport`s left five
/// tests ending with the warmer running.
void main() {
  test('the scan: a test or a helper that waits, each asked once — a '
      'closure handed on is its function\'s', () {
    // A string, so the scan reading this file sees none of it as calls.
    const source = '''
void main() {
  testWidgets('stops', (tester) async {
    await pumpPastTheWaitWindow(tester);
    s.playbackRig.prerenderScheduler.cancel();
  });
  testWidgets('forgets', (tester) async {
    await pumpPastTheWaitWindow(tester);
  }, skip: false);
  testWidgets('never waits', (tester) async {});
  Future<void> placeAndStop(WidgetTester tester) async {
    await pumpPastTheWaitWindow(tester);
    s.playbackRig.prerenderScheduler.cancel();
  }
  Future<void> placeAndForget(WidgetTester tester) async {
    await pumpPastTheWaitWindow(tester);
  }
  testWidgets('waits through a helper', (tester) async {
    await placeAndForget(tester);
  });
  testWidgets('waits in a closure it hands on', (tester) async {
    await tester.runAsync(() => pumpPastTheWaitWindow(tester));
    s.playbackRig.prerenderScheduler.cancel();
  });
}
''';

    expect(waitersIn('x.dart', source), {
      'x.dart:2': true,
      'x.dart:6': false,
      'x.dart:10': true,
      'x.dart:14': false,
      'x.dart:20': true,
    });
  });

  late final waiters = windowWaitersUnder('test');

  test('⛔premise: the scan finds the family', () {
    // 41 on 2026-10-16: the tests and the helpers they wait through.
    expect(waiters, hasLength(greaterThanOrEqualTo(41)));
  });

  test('🚨and every one of them stops the warmer', () {
    expect(
      [
        for (final MapEntry(:key, :value) in waiters.entries)
          if (!value) key,
      ],
      isEmpty,
      reason: 'end it with session.playbackRig.prerenderScheduler.cancel() '
          '— a helper for every test that waits through it — see '
          'pumpPastTheWaitWindow',
    );
  });
}

/// Each function under [dir] — `'test'` spelled out, for the affected-tests
/// selector — that waits out the window, as 「file:line」, with whether it
/// stops the warmer.
///
/// Only a file that names the wait is parsed: a parse of every file under
/// `test` was 2.8 s of this file's run, and the wait is called by name.
Map<String, bool> windowWaitersUnder(String dir) => {
  for (final file in dartFilesUnder(dir))
    if (file.readAsStringSync() case final source
        when source.contains('pumpPastTheWaitWindow'))
      ...waitersIn(file.path.replaceAll(r'\', '/'), source),
};

/// The functions in [source] that call `pumpPastTheWaitWindow`, by the line
/// they start on, with whether their text stops the warmer: a `testWidgets`
/// body (its line is the call's), or a function or method a test waits
/// through. A closure handed to anything else — a `runAsync`, a tear-down —
/// is the function's it was written in.
Map<String, bool> waitersIn(String path, String source) {
  final unit = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final waits = _Waits();
  unit.accept(waits);
  return {
    for (final waiter in waits.found)
      '$path:${unit.lineInfo.getLocation(waiter.offset).lineNumber}': source
          .substring(waiter.offset, waiter.end)
          .contains('prerenderScheduler.cancel()'),
  };
}

class _Waits extends RecursiveAstVisitor<void> {
  final Set<AstNode> found = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'pumpPastTheWaitWindow') {
      final waiter = _waiterOf(node);
      if (waiter != null) {
        found.add(waiter);
      }
    }
    super.visitMethodInvocation(node);
  }

  /// The `testWidgets(…)` call whose body [node] is in, or the function or
  /// method it is in — whichever is nearer.
  static AstNode? _waiterOf(AstNode node) {
    for (var at = node.parent; at != null; at = at.parent) {
      if (at is FunctionDeclaration || at is MethodDeclaration) {
        return at;
      }
      if (at is MethodInvocation && at.methodName.name == 'testWidgets') {
        return at;
      }
    }
    return null;
  }
}
