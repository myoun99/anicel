import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart' show codeOfLines;

/// 🚨WHAT IS DONE AS THE HAND RESTS IS OFF TILL THE LAUNCH SAYS SO.
///
/// A rest is taken by a timer, and a test's ledger and engine arm none —
/// a widget test's clock would not end one (`EngineTileLedger
/// .copiesAtRest`, `.foldsAtRest`, `GpuEngine.restsAfter`). So each is the
/// launch's to turn on, and every pin of a rest turns its own on: with
/// one of these lines gone the app keeps a decision of the user's no
/// more, and no test of behaviour says so. No test runs a launch, so it
/// is read from the source.
///
/// - 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
///   유지한다」 — the copies.
/// - 🗣️F-610-Q5 (유저 2026-11-19): 「압축은 일단 중복줄이면서 하는데 결국은
///   3번대로 하자」 — the folds.
/// - 🗣️a-transform-drag-over-folder-rows-draws-a-frame-in-a-third-of-a-
///   second-Q1 = b (유저 2026-11-20): 「손을 떼면 바로 놓는다」 — the buffers
///   the engine's composes run in, let go by the rest the ledger's
///   landings are taken to rest by: one number.
void main() {
  test('main turns on what is done as the hand rests before it runs the '
      'app', () {
    final source = codeOfLines(File('lib/main.dart').readAsStringSync());
    final run = source.indexOf('runApp(');
    expect(run, greaterThan(0), reason: '⛔premise: the app is run');

    for (final said in const [
      'EngineTileLedger.copiesAtRest = true;',
      'EngineTileLedger.foldsAtRest = true;',
      'GpuEngine.restsAfter = EngineTileLedger.rest;',
    ]) {
      final at = source.indexOf(said);
      expect(at, greaterThan(0), reason: said);
      expect(at, lessThan(run), reason: '$said — before the app is run');
    }
  });
}
