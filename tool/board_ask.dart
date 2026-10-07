// Asks the board's server one question and prints what it answers.
//
//   dart run tool/board_ask.dart <http://host:4321> <path?query>
//
//   …/api/records?id=<card>      that card's lines, its questions with them
//   …/api/records?since=<stamp>  every line stamped at or after it
//   …/api/find?q=<words>         the cards that say so
//   …/api/board                  every card's head
//   …/api/check                  what the gate says (`board_check` asks it)
//
// For a machine that holds no records file (유저 2026-10-07, card
// the-board-is-one-server-for-both-machines). It is `curl` that knows where
// the door's secret is: the file is named by ANICEL_BOARD_TOKEN_FILE, so the
// secret is never typed into a command line — and a command line ends up in
// a transcript.
//
// Exit codes: 0 answered · 1 answered with an error status · 2 could not ask.
import 'dart:io';

import 'board_door.dart';

/// Why this run cannot happen, or null if it can.
String? boardAskRefusal(List<String> args) {
  if (args.length != 2) {
    return 'board_ask: 인자는 두 개입니다 — <http://host:4321> <path?query> '
        '(${args.length}개 받음)';
  }
  if (boardPlaceOf(args.first, environment: const {}) is! BoardServer) {
    return 'board_ask: 첫 인자는 보드 서버의 주소(http://…)입니다 — '
        '받은 것: ${args.first}';
  }
  if (!args[1].startsWith('/')) {
    return 'board_ask: 둘째 인자는 /로 시작하는 경로입니다 — 받은 것: ${args[1]}';
  }
  return null;
}

Future<void> main(List<String> args) async {
  final refusal = boardAskRefusal(args);
  if (refusal != null) {
    stderr.writeln(refusal);
    exit(2);
  }
  final server = boardPlaceOf(args.first) as BoardServer;
  final answer = await askBoard(server, 'GET', args[1]);
  if (answer.status == 0) {
    stderr.writeln('board_ask: ${answer.body}');
    exit(2);
  }
  if (answer.status == HttpStatus.unauthorized) {
    stderr.writeln('board_ask: 보드 서버가 들여보내지 않았습니다 — '
        '${turnedAwayAdvice(server)}');
    exit(2);
  }
  stdout.write(answer.body);
  if (answer.status != HttpStatus.ok) exit(1);
}
