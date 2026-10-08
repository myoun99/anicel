// Says which 담당 this session answers to.
//
//   dart run tool/board_me.dart <담당>     this session answers to <담당>
//   dart run tool/board_me.dart            which 담당 this session is
//
// 유저 2026-10-07 (the-board-is-one-server-for-both-machines-Q2: 「글은
// 카드의 흐름에 적고, 「전달」 보기는 그것을 모아 보여 주기만 한다」): one
// session leaves a line for another by naming its 담당 (`"to"`), and each
// session is shown, at the start and the end of a turn, the lines left for
// its own. That needs one fact nothing else holds — which 담당 a session is.
// A session says it once, here; the name is kept beside this machine's
// flags (`sessionNameFile`), and the tools and the hooks read it from there:
// `board_say` signs a letter with it, and the letters hook asks the board
// for what waits for it.
//
// ⚠️A name with a space in it needs no quotes: every word after the command
// is the name (「캔버스 베이스 패널」).
import 'dart:io';

import 'board_door.dart';
import 'board_model.dart';

/// Why [name] cannot be a session's 담당, or null if it can.
String? sessionNameRefusal(String name) {
  if (name.isEmpty) return '담당 이름이 비었습니다.';
  if (name.contains('\n') || name.contains('\r')) {
    return '담당 이름은 한 줄입니다.';
  }
  if (name == kEveryone) {
    return '「$kEveryone」 는 담당이 아닙니다 — 모든 담당 앞으로 보낼 때 '
        '`to` 에 쓰는 말입니다.';
  }
  return null;
}

void main(List<String> args) {
  final path = sessionNameFile(Platform.environment);
  if (path == null) {
    stderr.writeln('board_me: 이 세션이 어느 기계의 어느 세션인지 알 수 '
        '없습니다 — $kBoardFolderVariable 와 $kSessionIdVariable 가 있어야 '
        '합니다. 앞의 것은 설치 명령이 넣습니다'
        '(dart run tool/session_hooks/install.dart …), 뒤의 것은 Claude Code '
        '의 세션 안에서만 있습니다.');
    exit(2);
  }
  if (args.isEmpty) {
    final name = sessionNameOf(Platform.environment);
    if (name == null) {
      stdout.writeln('board_me: 이 세션은 담당 이름을 등록하지 않았습니다 — '
          'dart run tool/board_me.dart <담당>');
      exit(1);
    }
    stdout.writeln(name);
    return;
  }
  final name = args.join(' ').trim();
  final refusal = sessionNameRefusal(name);
  if (refusal != null) {
    stderr.writeln('board_me: $refusal');
    exit(2);
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('$name\n');
  stdout.writeln('board_me: 이 세션은 「$name」 입니다 — 이 담당 앞으로 남은 '
      '전달이 턴의 처음과 끝에 보입니다.');
  stdout.writeln('  다른 세션 앞으로 남길 때는 기록 줄에 `to` 를 적습니다: '
      '{"id":"<카드>","to":"<담당>","note":"…"} — 모든 담당 앞은 '
      '"to":"$kEveryone", 카드와 무관한 알림은 카드 「$kNoticesCard」 에.');
}
