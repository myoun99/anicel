import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/wait_window.dart';

/// 🗣️F-551-Q1 (유저 2026-11-04: 「전부 늘 띄운다」 — 무거운 조작은 누를 때마다
/// 창 뒤로, 그 되돌리기 · 다시하기도 매번): a step taken behind a wait window
/// is undone and redone behind that same window, whatever command it is; one
/// taken behind none is undone and redone at once.
void main() {
  late HistoryManager history;
  final window = _Window();

  setUp(() => history = HistoryManager());

  WaitWindow? undoBehind() => history.stepBehind(undo: true)?.window;
  WaitWindow? redoBehind() => history.stepBehind(undo: false)?.window;

  test('🎯taken behind a window: undone behind it, redone behind it, and '
      'undone behind it again', () {
    behindWaitWindow(window, () => history.execute(_Step()));
    expect(undoBehind(), same(window));
    history.undo();
    expect(redoBehind(), same(window));
    expect(undoBehind(), isNull, reason: 'nothing left to undo');
    history.redo();
    expect(undoBehind(), same(window));
  });

  test('taken behind none: stands behind none either way', () {
    history.execute(_Step());
    expect(history.stepBehind(undo: true), isNull);
    history.undo();
    expect(history.stepBehind(undo: false), isNull);
  });

  test('only what the window was up over — the step before it and the one '
      'after stand behind none', () {
    history.execute(_Step());
    behindWaitWindow(window, () => history.execute(_Step()));
    history.execute(_Step());
    expect(undoBehind(), isNull);
    history.undo();
    expect(undoBehind(), same(window));
    history.undo();
    expect(undoBehind(), isNull);
  });

  test('a run of writes made one step behind the window stands behind it', () {
    behindWaitWindow(
      window,
      () => history.runAsOneStep('two', () {
        history.execute(_Step());
        history.execute(_Step());
      }),
    );
    expect(history.undoCount, 1, reason: 'premise: one step');
    expect(undoBehind(), same(window));
  });

  test('across an await: what the window\'s task lands after waiting', () async {
    await behindWaitWindow(window, () async {
      await Future<void>.delayed(Duration.zero);
      history.execute(_Step());
    });
    expect(undoBehind(), same(window));
  });

  test('a gesture\'s writes folded into one keep the window they stood '
      'behind', () {
    final mark = history.gestures.mark;
    behindWaitWindow(window, () => history.execute(_Step()));
    history.execute(_Step());
    history.gestures.foldSince(mark, 'swipe');
    expect(history.undoCount, 1, reason: 'premise: folded');
    expect(undoBehind(), same(window));
  });

  test('what the step works out ahead comes with its window', () async {
    final log = <String>[];
    behindWaitWindow(window, () => history.execute(_Ahead(log)));
    history.undo();
    final behind = history.stepBehind(undo: false)!;
    expect(behind.window, same(window));
    await behind.ahead!((_) {});
    expect(log, ['ahead']);
    expect(
      history.stepBehind(undo: true),
      isNull,
      reason: 'nothing to undo yet: the step was undone',
    );
  });

  test('work ahead with no window stands behind none — no door took it '
      'behind one', () {
    history.execute(_Ahead([]));
    history.undo();
    expect(history.stepBehind(undo: false), isNull);
  });
}

class _Window implements WaitWindow {}

class _Step implements Command {
  @override
  String get description => 'step';

  @override
  void execute() {}

  @override
  void undo() {}
}

class _Ahead extends _Step implements WorksAheadCommand {
  _Ahead(this.log);

  final List<String> log;

  @override
  WorkAhead? workAhead({required bool undo}) =>
      undo ? null : (report) async => log.add('ahead');
}
