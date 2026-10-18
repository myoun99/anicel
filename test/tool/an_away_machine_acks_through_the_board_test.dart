import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_ack.dart';
import '../../tool/board_check.dart';
import '../../tool/board_door.dart';
import '../../tool/board_server.dart';
import '../helpers/temp_dir.dart';

/// 카드 an-away-machine-cannot-ack-the-gate (서피스 저장 세션, 10-08): the
/// gate a session runs on a machine that does not hold the board is judged by
/// that machine's server, and the server reads the acks beside the records.
/// The complaint's exit — 「그 id 를 .gate-ack 에 한 줄로」 — was a file the
/// asking machine did not have, so its Stop hook held the turn until somebody
/// at the board's machine wrote the line for it.
///
/// What this file pins: the acks are written by one function beside the
/// records, the server runs that same function for whoever asks from
/// elsewhere, and the complaint names the one command that reaches it from
/// any machine.
///
/// ⚠️ONE SERVER FOR THE WHOLE FILE, bound on loopback and treating every
/// request as another machine's (the_board_has_a_door_test says why).
void main() {
  const secret = '0123456789abcdef0123456789abcdef';
  final now = DateTime.parse('2026-10-09T04:00:00.000');
  late Directory dir;
  late File records;
  late HttpServer server;
  late Uri base;

  File acks() => gateAckFile(records);
  AckAsked asking(String key, [String? why]) =>
      (place: '$base', key: key, why: why);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('qa_board_ack');
    records = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(
        '${jsonEncode({
          'kind': 'item',
          'id': 'T-1',
          'title': 'the first card',
          'at': '할 일',
          'ts': '2026-10-08T00:00:00.000000',
        })}\n'
        // A word nobody reads: something the gate names until it is acked.
        '${jsonEncode({
          'kind': 'item',
          'id': 'T-9',
          'bogus': 'x',
          'ts': '2026-10-08T00:00:01.000000',
        })}\n',
      );
    boardIs(
      records: records.path,
      gh: '${dir.path}/no-gh-here',
      gitRoot: dir.path,
      door: const LanDoor(secret),
      isThisMachine: (_) => false,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(answerAll(server));
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });
  setUp(() {
    if (acks().existsSync()) acks().deleteSync();
  });
  tearDownAll(() async {
    await server.close(force: true);
    deleteTempQuietly(dir);
  });

  group('the acks are written in one place, by one function', () {
    test('an ack is the key, the reason and the day, beside the records — '
        'and the gate stops naming it', () {
      expect(
        boardCheckComplaints(records),
        contains('T-9'),
        reason: '⛔premise: the gate names it before the ack',
      );
      expect(ackOnBoard(records, 'T-9', '  알고 있다 ', now), isNull);
      expect(acks().readAsStringSync(), 'T-9 알고 있다 2026-10-09\n');
      expect(boardCheckComplaints(records), isNot(contains('T-9')));
    });

    test('it goes after what is there — a last line with no line break is '
        'not glued onto', () {
      acks().writeAsStringSync('# 머리\n1243');
      expect(ackOnBoard(records, 'T-9', '이유', now), isNull);
      expect(acks().readAsStringSync(), '# 머리\n1243\nT-9 이유 2026-10-09\n');
    });

    test('🚨refused — no key, a key of two words, a comment, no reason, a '
        'reason of two lines, a key acked already — and not a byte written',
        () {
      acks().writeAsStringSync('# 머리\nT-1 앞의 이유 2026-10-01\n');
      final before = acks().readAsBytesSync();
      for (final (key, why) in const [
        ('', '이유'),
        ('T 9', '이유'),
        ('#1480', '이유'),
        ('T-9', ''),
        ('T-9', '   '),
        ('T-9', '둘\n줄'),
        ('T-1', '다른 이유'),
      ]) {
        expect(
          ackOnBoard(records, key, why, now),
          isNotNull,
          reason: '「$key」 「$why」',
        );
      }
      expect(acks().readAsBytesSync(), before);
      expect(
        ackOnBoard(records, 'T-1', '다른 이유', now),
        contains('T-1 앞의 이유'),
        reason: 'the refusal shows the line that is there',
      );
    });

    test('taking an ack back takes that key\'s lines and nothing else — not '
        'a comment that mentions it, not a key it begins', () {
      acks().writeAsStringSync(
        '# T-9 는 주석\nT-9 하나\n1243\nT-9 둘 2026-10-01\nT-90 다른 키\n',
      );
      expect(unackOnBoard(records, 'T-9'), isNull);
      expect(acks().readAsStringSync(), '# T-9 는 주석\n1243\nT-90 다른 키\n');
      expect(unackOnBoard(records, 'T-9'), contains('T-9'));
      acks().deleteSync();
      expect(unackOnBoard(records, 'T-9'), isNotNull);
      expect(acks().existsSync(), isFalse, reason: 'and nothing is made');
    });
  });

  group('🚨from a machine that does not hold the board', () {
    test('the tool writes the ack through the server, and the gate that '
        'machine runs stops naming it — and takes it back the same way',
        () async {
      final away = BoardServer(base, secret: secret);
      expect(
        (await boardCheckOf(away)).complaints,
        contains('T-9'),
        reason: '⛔premise: the gate it runs names it',
      );
      expect(await ackAt(away, asking('T-9', '알고 있다')), isNull);
      expect(acks().readAsLinesSync().single, startsWith('T-9 알고 있다 '));
      expect((await boardCheckOf(away)).complaints, isNot(contains('T-9')));

      expect(await ackAt(away, asking('T-9')), isNull);
      expect(acks().readAsStringSync(), isEmpty);
      expect((await boardCheckOf(away)).complaints, contains('T-9'));
    });

    test('a refusal comes back as the board said it, and nothing is written',
        () async {
      final away = BoardServer(base, secret: secret);
      expect(await ackAt(away, asking('T-9', ' ')), contains('이유'));
      expect(acks().existsSync(), isFalse);
      expect(await ackAt(away, asking('T-9')), isNotNull);
    });

    test('without the secret it is turned away by name of the variable that '
        'would have carried it — and nothing is written', () async {
      expect(
        await ackAt(BoardServer(base), asking('T-9', '알고 있다')),
        contains(kDoorSecretFileVariable),
      );
      expect(acks().existsSync(), isFalse);
    });

    test('on the board\'s own machine the same tool writes the file', () async {
      expect(
        await ackAt(BoardFile(records.path), asking('T-9', '여기서')),
        isNull,
      );
      expect(acks().readAsLinesSync().single, startsWith('T-9 여기서 '));
      expect(await ackAt(BoardFile(records.path), asking('T-9')), isNull);
      expect(acks().readAsStringSync(), isEmpty);
    });
  });

  group('the complaint names its exit, and the exit is this tool', () {
    test('a question waiting a day, and an ack a card has outlived, name the '
        'command — which is a file here', () {
      final old = DateTime.parse('2026-10-01T00:00:00');
      final board = File('${dir.path}/aged/board.jsonl')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${jsonEncode({
            'kind': 'item',
            'id': 'A',
            'title': 't',
            'at': '질문',
            'note': 'n',
            'ts': old.toIso8601String(),
          })}\n'
          '${jsonEncode({
            'kind': 'item',
            'id': 'B',
            'title': 't',
            'at': '실기 확인',
            'pr': 1234,
            'note': '고쳤다',
            'ts': old.toIso8601String(),
          })}\n',
        );
      gateAckFile(board).writeAsStringSync('1234 카드 없이 지나감\n');
      final said = boardCheckComplaints(
        board,
        since: old.toIso8601String(),
        linesSince: old.toIso8601String(),
        now: old.add(const Duration(days: 2)),
      );
      expect(said, contains('하루 넘게 답을 기다리는 질문: A'));
      expect(said, contains('$kAckCommand <id> <이유>'));
      expect(said, contains('$kAckCommand --drop <번호>'));
      expect(said, isNot(contains('.gate-ack')), reason: 'not the file');
      final words = kAckCommand.split(' ');
      expect(words.take(2), ['bash', 'tool/run.sh'], reason: kAckCommand);
      final tool = 'tool/${words[2]}.dart';
      expect(File(tool).existsSync(), isTrue, reason: tool);
    });

    test('the command reads as an ack or as taking one back, and nothing '
        'else', () {
      final said = boardAckArgs(['B', 'T-9', '알고', '있다']);
      expect(said.asked, (place: 'B', key: 'T-9', why: '알고 있다'));
      expect(
        boardAckArgs(['B', '--drop', 'T-9']).asked,
        (place: 'B', key: 'T-9', why: null),
      );
      for (final args in const [
        <String>[],
        ['B'],
        ['B', 'T-9'],
        ['B', '--drop'],
        ['B', '--drop', 'T-9', 'more'],
        ['B', 'T-9', '--drop'],
        ['B', '--why', 'T-9'],
      ]) {
        final refused = boardAckArgs(args);
        expect(refused.asked, isNull, reason: '$args');
        expect(refused.refusal, contains('사용법'), reason: '$args');
      }
    });
  });
}
