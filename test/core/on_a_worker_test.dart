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
}
