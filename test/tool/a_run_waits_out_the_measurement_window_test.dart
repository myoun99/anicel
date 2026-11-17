@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/measure_window.dart';
import '../../tool/test_queue.dart';
import '../helpers/temp_dir.dart';

/// 🪟THE MACHINE'S MEASUREMENT WINDOW (card a-quiet-window-drains-in-minutes,
/// 관제 2026-11-17 on 유저 「할수있는거 최대한하자」): while it is open no run
/// in the line takes suites, whatever its turn — it waits where it stands
/// and says what for — so the machine falls quiet within one batch, and a
/// window past its deadline holds nothing (tool/measure_window.dart).
void main() {
  late Directory line;
  setUp(() => line = Directory.systemTemp.createTempSync('queue_window'));
  tearDown(() => deleteTempQuietly(line));

  const thirty = Duration(minutes: 30);

  /// One run of [files] files in the line, its room said by [room]: what
  /// it heard, and whether the window was closed when it ran.
  Future<({List<String> said, bool ranClosed})> runIn({
    Future<bool> Function()? room,
  }) async {
    final said = <String>[];
    final ranClosed = await inTurn(
      'a run',
      (_) async => openWindow(line) == null,
      files: 4,
      line: line,
      room: room ?? () async => true,
      say: said.add,
      lookAgain: const Duration(milliseconds: 1),
      askAgain: const Duration(milliseconds: 1),
    );
    return (said: said, ranClosed: ranClosed);
  }

  test('a run waits while the window is open, says for whom and till when '
      'once, and runs once it is closed', () async {
    final open = openTheWindow(line, who: '브러시  측정', lasting: thirty);
    Timer(const Duration(milliseconds: 80), () => closeTheWindow(line));

    final (:said, :ranClosed) = await runIn();

    expect(ranClosed, isTrue);
    expect(said.where((s) => s.contains('측정 창')), [
      'test_queue: ${waitingFor(open)}',
    ]);
    final clock =
        '${open.until.hour.toString().padLeft(2, '0')}:'
        '${open.until.minute.toString().padLeft(2, '0')}';
    expect(waitingFor(open), '기다리는 중 — 측정 창(브러시 측정 · $clock까지)');
  });

  test('a window that opens while the machine is measured is seen under '
      'the line\'s lock: the run does not take its suites', () async {
    var asked = 0;
    final (:said, :ranClosed) = await runIn(
      room: () async {
        if (asked++ == 0) {
          openTheWindow(line, who: '관제', lasting: thirty);
          Timer(const Duration(milliseconds: 80), () => closeTheWindow(line));
        }
        return true;
      },
    );

    expect(ranClosed, isTrue);
    expect(said.where((s) => s.contains('측정 창')), hasLength(1));
  });

  test('⏰a window past its deadline holds nothing, its file there or not',
      () async {
    openTheWindow(
      line,
      who: '잊은 창',
      lasting: thirty,
      now: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(File('${line.path}/$kWindowFile').existsSync(), isTrue);

    final (:said, :ranClosed) = await runIn();

    expect(ranClosed, isTrue);
    expect(said.where((s) => s.contains('측정 창')), isEmpty);
  });

  test('the file is a deadline in seconds, a tab and who — as the shell '
      'reads it — and anything else is no window', () {
    final at = DateTime.now().add(thirty);
    final seconds = at.millisecondsSinceEpoch ~/ 1000;
    final file = File('${line.path}/$kWindowFile')
      ..writeAsStringSync('$seconds\t저장 서피스\n');
    expect(openWindow(line), (
      who: '저장 서피스',
      until: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    ));
    file.writeAsStringSync('soon\t누구\n');
    expect(openWindow(line), isNull);
    file.writeAsStringSync('$seconds 누구\n');
    expect(openWindow(line), isNull);
    closeTheWindow(line);
    expect(openWindow(line), isNull);
    closeTheWindow(line);
  });

  test('`--window` opens it only with whole minutes and a name', () {
    final said = <String>[];
    int ask(List<String> args) =>
        windowCommand(line, args, describe: (_) => const [], say: said.add);

    expect(ask(['0', '관제']), 2);
    expect(ask(['ten', '관제']), 2);
    expect(ask(['10']), 2);
    expect(openWindow(line), isNull);
    expect(ask(['10', '브러시', '측정']), 0);
    expect(openWindow(line)?.who, '브러시 측정');
    expect(ask([]), 0);
    expect(said.last, contains('open — 브러시 측정'));
    expect(ask(['close']), 0);
    expect(openWindow(line), isNull);
  });

  group('⚠️two readers, not three — the shell reads the same file and says '
      'the same words', () {
    final shell = File('tool/measure_window.sh').readAsStringSync();

    test('the same file', () {
      final folder = queueFolder({'HOME': '/h'})!.path.split('/').last;
      expect(
        shell,
        contains('MEASURE_WINDOW="\$MACHINE_FOLDER/$folder/$kWindowFile"'),
      );
    });

    test('the same words', () {
      final words = waitingFor((who: 'WHO', until: DateTime(2026, 1, 1, 9, 5)));
      expect(words, '기다리는 중 — 측정 창(WHO · 09:05까지)');
      expect(
        shell.replaceAll('\r\n', '\n'),
        contains(r'echo "기다리는 중 — 측정 창($who · $(date -d "@$until" +%H:%M'),
      );
      expect(shell, contains('+%H:%M)까지)"'));
    });

    test('the cargo turn waits for it, but not the hook\'s --hold', () {
      final cargo = File('tool/cargo_turn.sh').readAsStringSync();
      expect(cargo, contains(r'. "$TOOL_DIR/measure_window.sh"'));
      expect(cargo, contains(r'[ "$1" = --hold ] && HOLD=1'));
      expect(
        cargo,
        contains(r'in_the_window() { [ -z "$HOLD" ] && window_words'),
      );
      expect(
        cargo,
        contains(r'until [ "$(first_in_line "$LINE")" = "$TICKET" ] '
            r'&& ! in_the_window && mkdir "$TURN"'),
      );
    });

    test('a land\'s gates wait for it with the room, in one loop', () {
      final lanes = File('tool/lane.sh').readAsStringSync();
      expect(lanes, contains(r'. "$ROOT/tool/measure_window.sh"'));
      expect(
        lanes.replaceAll('\r\n', '\n'),
        contains('  until ! words="\$(window_words)" \\\n'
            '    && seen="\$(bash "\$ROOT/tool/run.sh" flutter_room'),
      );
    });
  });
}
