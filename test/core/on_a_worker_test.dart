import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/on_a_worker.dart';

/// Set on this isolate only: a worker isolate starts with its own statics.
String? _marked;

/// [onAWorker]: a worker in the app, this isolate in the test corpus — the
/// one switch a `testWidgets` clock needs ([debugWorkersRunHere]).
void main() {
  late bool corpus;
  setUp(() {
    corpus = debugWorkersRunHere;
    _marked = 'this isolate';
  });
  tearDown(() => debugWorkersRunHere = corpus);

  test('🚨the corpus runs every worker\'s job here — a widget test\'s clock '
      'cannot wait for a real isolate', () {
    expect(corpus, isTrue);
  });

  test('run here, the job runs inside the call, on this isolate, and its '
      'answer still comes through a future', () async {
    debugWorkersRunHere = true;
    var ran = false;
    final answer = onAWorker(() {
      ran = true;
      return _marked;
    });
    expect(ran, isTrue);
    expect(await answer, 'this isolate');
  });

  test('otherwise the job runs on a worker isolate', () async {
    debugWorkersRunHere = false;
    expect(await onAWorker(() => _marked), isNull);
  });

  group('a job that says how far it is', reportingFromAWorker);
}

/// [onAWorkerReporting]: a worker's job that tells its caller how far it is
/// (🗣️F-494 — a trimmed movie's piece stood a minute at 0% behind the wait
/// window, its worker saying nothing until its answer).
void reportingFromAWorker() {
  late bool corpus;
  setUp(() => corpus = debugWorkersRunHere);
  tearDown(() => debugWorkersRunHere = corpus);

  /// A job that counts a thousand steps to its end, and answers what the
  /// isolate it ran on holds in [_marked].
  String? counting(void Function(double fraction) report) {
    for (var step = 1; step <= 1000; step += 1) {
      report(step / 1000);
    }
    return _marked;
  }

  void expectTheBarMoved(List<double> heard) {
    expect(heard.last, 1, reason: 'the end is always said');
    expect(heard.first, lessThan(0.01), reason: 'and the start: $heard');
    for (var i = 1; i < heard.length - 1; i += 1) {
      expect(
        heard[i] - heard[i - 1],
        greaterThanOrEqualTo(0.005 - 1e-9),
        reason: 'told only when the bar moves by half a percent: $heard',
      );
    }
    expect(
      heard.length,
      greaterThan(100),
      reason: 'and every time it does, not just at the end',
    );
  }

  test('🎯on a worker, the job\'s reports reach the caller\'s isolate as it '
      'goes, and its answer still comes back', () async {
    debugWorkersRunHere = false;
    _marked = 'this isolate';
    final heard = <double>[];

    final answer = await onAWorkerReporting(heard.add, counting);

    expect(answer, isNull, reason: 'it ran on a worker');
    expectTheBarMoved(heard);
  });

  // 🐞F-494's own regression (10-30): the import window's listener holds the
  // window's state, futures and all, and none of that crosses to a worker.
  test('🎯a listener that holds what no isolate message carries — the import '
      'window\'s, futures and all — is heard all the same: only the job '
      'crosses', () async {
    debugWorkersRunHere = false;
    _marked = 'this isolate';
    final window = Completer<void>();
    final heard = <double>[];
    void listener(double fraction) {
      if (!window.isCompleted) {
        heard.add(fraction);
      }
    }

    final answer = await onAWorkerReporting(listener, counting);

    expect(answer, isNull, reason: 'it ran on a worker');
    expectTheBarMoved(heard);
  });

  test('run here, the reports are heard the same way', () async {
    debugWorkersRunHere = true;
    _marked = 'this isolate';
    final heard = <double>[];

    final answer = await onAWorkerReporting(heard.add, counting);

    expect(answer, 'this isolate');
    expectTheBarMoved(heard);
  });

  test('the end is told once, however often the job says it', () async {
    debugWorkersRunHere = false;
    final heard = <double>[];

    await onAWorkerReporting(heard.add, (report) {
      report(0.5);
      report(1);
      report(1);
    });

    expect(heard, [0.5, 1]);
  });

  test('with nobody listening the job runs and reports into no one',
      () async {
    debugWorkersRunHere = false;

    expect(await onAWorkerReporting(null, counting), isNull);
  });
}
