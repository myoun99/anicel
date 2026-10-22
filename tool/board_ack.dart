// Leaves something the gate named alone, with the reason — or takes that
// back.
//
//   bash tool/run.sh board_ack "$ANICEL_BOARD" <key> <reason…>
//   bash tool/run.sh board_ack "$ANICEL_BOARD" --drop <key>
//
// <key> is the card id or the PR number the complaint named. Every word after
// it is the reason; the line is dated by the clock of the machine that holds
// the board, as `board_say` stamps a record.
//
// 카드 an-away-machine-cannot-ack-the-gate (서피스 저장 세션, 10-08): the
// acks sat in a file on the machine that holds the board, the gate of every
// other machine is judged by that machine's server, and a session elsewhere
// had no way to write the line its own Stop hook told it to write. The
// complaint now names this command, and it is the same command on every
// machine: here it writes the file, anywhere else it asks the server to.
//
// Exit codes: 0 written · 2 refused or could not ask.
import 'dart:convert';
import 'dart:io';

import 'board_check.dart';
import 'board_door.dart';

/// What a run of this tool asks for: [why] null takes [key]'s ack back.
typedef AckAsked = ({String place, String key, String? why});

/// What [args] ask for, or why they ask for nothing this tool does.
({AckAsked? asked, String? refusal}) boardAckArgs(List<String> args) {
  const usage = '사용법: board_ack.dart <보드> <키> <이유…> · '
      'board_ack.dart <보드> --drop <키>';
  if (args.length == 3 && args[1] == '--drop') {
    return (asked: (place: args[0], key: args[2], why: null), refusal: null);
  }
  if (args.length < 3 || args.skip(1).any((a) => a.startsWith('--'))) {
    return (asked: null, refusal: 'board_ack: $usage');
  }
  return (
    asked: (place: args[0], key: args[1], why: args.skip(2).join(' ')),
    refusal: null,
  );
}

/// Writes (or takes back) what [asked] says at [place]: null when it was
/// done, the reason when it was not.
Future<String?> ackAt(BoardPlace place, AckAsked asked) async {
  switch (place) {
    case BoardFile(:final path):
      final records = File(path);
      return asked.why == null
          ? unackOnBoard(records, asked.key)
          : ackOnBoard(records, asked.key, asked.why!, DateTime.now());
    case final BoardServer server:
      final answer = await askBoard(
        server,
        'POST',
        asked.why == null ? '/unack' : '/ack',
        body: jsonEncode({'key': asked.key, 'why': ?asked.why}),
      );
      return switch (answer.status) {
        HttpStatus.ok => null,
        0 => answer.body,
        HttpStatus.unauthorized =>
          '보드 서버가 들여보내지 않았습니다(${server.base}) — '
              '${turnedAwayAdvice(server)}',
        HttpStatus.badRequest => answer.body,
        _ => '보드 서버가 ${answer.status} 로 답했습니다(${server.base}).',
      };
  }
}

Future<void> main(List<String> args) async {
  final (:asked, :refusal) = boardAckArgs(args);
  if (asked == null) {
    stderr.writeln(refusal);
    exit(2);
  }
  final why = await ackAt(boardPlaceOf(asked.place), asked);
  if (why != null) {
    stderr.writeln('board_ack: $why');
    exit(2);
  }
  stdout.writeln(
    asked.why == null
        ? 'board_ack: 「${asked.key}」 의 ack 를 거뒀습니다.'
        : 'board_ack: 「${asked.key}」 를 그대로 둡니다 — ${asked.why}',
  );
}
