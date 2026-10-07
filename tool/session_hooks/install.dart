// Sets up THIS MACHINE'S clone for its sessions: the hooks, the memory
// folder and the board's address, written into `.claude/settings.local.json`
// — the one settings file that is this machine's alone (git ignores it).
//
//   dart run tool/session_hooks/install.dart --board <folder> --memory <folder>
//       [--home <http://host:4321>] [--old-memory <folder>] [--dry]
//
//   --board       this machine's BOARD FOLDER: a local folder for the flags
//                 and the two exes — and, on the machine that holds the
//                 board, the records. Never a synced folder.
//   --memory      the memory folder, as this machine names it: the one
//                 folder every machine sees (a sync client keeps it).
//   --home        (a machine that does NOT hold the board) the address of
//                 the machine that does.
//   --old-memory  (only where the memory was moved out of a folder) that
//                 folder, kept the same as the new one until every session
//                 that started before the move has been started again.
//   --dry         print the settings instead of writing them.
//
// 유저 2026-10-07: 「작업을 노트북이 해줫으면 한단거지」 — a second machine
// runs sessions, so everything a session is given has to be givable twice.
// Until that day the hooks sat in one machine's memory folder with that
// machine's paths written into them, and the settings file that named them
// was written by hand (「훅 보관위치 알아서 권장대로해줘」 = the repository;
// card work-runs-on-the-surface-too).
//
// WHICH MACHINE THIS IS is asked of git, the same question `tool/lane.sh`
// asks: a clone that named itself (`git config anicel.machine <name>`) does
// not hold the board. It is given the board's address and its sessions
// write through that server; the machine that holds the board is given its
// own.
//
// ⛔THE HOOKS BLOCK IS WRITTEN WHOLE, never patched: a hook that is not in
// [hooksFor] is not installed. Everything else in the file — the
// permissions, whatever a person added — is kept as it was.
import 'dart:convert';
import 'dart:io';

/// What one machine's settings are made from. Every path with forward
/// slashes: they go into commands a POSIX shell reads.
typedef MachineSetup = ({
  String repo,
  String board,
  String memory,

  /// The server of the machine that holds the board — null ON that machine.
  String? home,

  /// The folder the memory moved out of — null where there was none.
  String? oldMemory,
});

/// The address every tool is handed as 「the board」 on this machine.
///
/// ⚠️On the machine that holds it too: a session's record goes through the
/// server there as well, so one process writes the records file whichever
/// machine spoke (유저 2026-10-07, card
/// the-board-is-one-server-for-both-machines).
String boardAddressOf(MachineSetup setup) =>
    setup.home ?? 'http://localhost:4321';

/// The variables a session's commands read the board by.
Map<String, String> environmentFor(MachineSetup setup) => {
  'ANICEL_BOARD': boardAddressOf(setup),
  'ANICEL_BOARD_TOKEN_FILE': '${setup.board}/.board-token',
};

/// The hooks of a session on this machine — all of them.
Map<String, dynamic> hooksFor(MachineSetup setup) {
  String run(String script, [List<String> handed = const []]) => [
    'bash',
    '"${setup.repo}/tool/session_hooks/$script"',
    for (final value in handed) '"$value"',
  ].join(' ');
  final index = '${setup.memory}/MEMORY.md';
  final oldIndex = setup.oldMemory == null
      ? null
      : '${setup.oldMemory}/MEMORY.md';
  // ⚠️The gate reads the records FILE on the machine that holds it — it
  // runs at the end of every turn, and must answer while the server is
  // being rebuilt — and asks the server anywhere else.
  final gateReads = setup.home ?? '${setup.board}/board.jsonl';
  return {
    'PreToolUse': [
      {
        'matcher': 'Bash',
        'hooks': [
          {
            'type': 'command',
            'command': run('guard_git_add.sh'),
            'if': 'Bash(git *)',
            'timeout': 10,
          },
        ],
      },
    ],
    'PostToolUse': [
      {
        'matcher': 'Edit|Write',
        'hooks': [
          for (final watched in [index, ?oldIndex])
            for (final tool in const ['Edit', 'Write'])
              {
                'type': 'command',
                'command': run('guard_memory_size.sh', [watched]),
                'if': '$tool($watched)',
                'timeout': 10,
              },
        ],
      },
    ],
    'UserPromptSubmit': [
      {
        'hooks': [
          {
            'type': 'command',
            'command': run('autorun_arm.sh', [setup.board]),
            'timeout': 10,
          },
        ],
      },
    ],
    'SessionStart': [
      {
        'hooks': [
          {
            'type': 'command',
            'command': run('board_up.sh', [setup.board]),
            'timeout': 60,
            'async': true,
            'statusMessage': '보드 서버 확인',
          },
        ],
      },
    ],
    'Stop': [
      {
        'hooks': [
          {
            'type': 'command',
            'command': run('board_gate.sh', [setup.board, gateReads]),
            'timeout': 40,
            'statusMessage': '보드 최신인지 확인',
          },
          {
            'type': 'command',
            'command': run('autorun_gate.sh', [setup.board]),
            'timeout': 15,
            'statusMessage': '자율진행 확인',
          },
          {
            'type': 'command',
            'command': run('guard_memory_conflicts.sh', [setup.memory]),
            'timeout': 10,
            'statusMessage': '메모리 충돌 사본 확인',
          },
          if (setup.oldMemory case final old?)
            {
              'type': 'command',
              'command': run('knowledge_fold.sh', [old, setup.memory]),
              'timeout': 20,
              'statusMessage': '메모리 두 자리 맞추기',
            },
        ],
      },
    ],
  };
}

/// [existing] as this machine's settings: the hooks written whole, the
/// memory folder and the board's variables set, and everything else kept.
Map<String, dynamic> settingsWith(
  Map<String, dynamic> existing,
  MachineSetup setup,
) => {
  ...existing,
  'hooks': hooksFor(setup),
  'autoMemoryDirectory': setup.memory,
  'env': {
    ...?(existing['env'] as Map?)?.cast<String, dynamic>(),
    ...environmentFor(setup),
  },
};

/// What was asked for on the command line, or why it cannot be done.
({MachineSetup? setup, String? refusal}) setupAsked(
  List<String> args, {
  required String repo,
  required bool away,
}) {
  String? flag(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? slashed(args[i + 1]) : null;
  }

  ({MachineSetup? setup, String? refusal}) refuse(String why) =>
      (setup: null, refusal: 'install: $why');

  final board = flag('--board');
  final memory = flag('--memory');
  final home = flag('--home');
  if (board == null || memory == null) {
    return refuse('--board <폴더> 와 --memory <폴더> 가 있어야 합니다.');
  }
  if (board == memory || board.startsWith('$memory/')) {
    return refuse('보드 폴더는 메모리 폴더와 달라야 합니다 — 보드 폴더는 이 '
        '기계의 것이고(표식 · exe · 비밀값), 메모리 폴더는 다른 기계와 같이 '
        '보는 폴더입니다.');
  }
  if (away && home == null) {
    return refuse('이 클론은 이름이 붙은 기계입니다(anicel.machine) — 보드를 '
        '가진 기계의 주소가 있어야 합니다: --home http://<그 기계>:4321');
  }
  if (!away && home != null) {
    return refuse('이 클론이 보드를 가진 기계입니다(anicel.machine 이 없음) — '
        '--home 은 다른 기계에서만 씁니다.');
  }
  if (home != null && !home.startsWith('http://')) {
    return refuse('--home 은 http://<기계>:4321 꼴의 주소입니다 — 받은 것: '
        '$home');
  }
  return (
    setup: (
      repo: slashed(repo),
      board: board,
      memory: memory,
      home: home,
      oldMemory: flag('--old-memory'),
    ),
    refusal: null,
  );
}

/// [path] the way a POSIX shell and a settings file both read it.
String slashed(String path) {
  final forward = path.replaceAll('\\', '/');
  return forward.length > 1 && forward.endsWith('/')
      ? forward.substring(0, forward.length - 1)
      : forward;
}

void main(List<String> args) {
  final repo = File.fromUri(Platform.script).parent.parent.parent.path;
  final machine = Process.runSync('git', [
    '-C',
    repo,
    'config',
    '--get',
    'anicel.machine',
  ]);
  final name = '${machine.stdout}'.trim();
  final asked = setupAsked(args, repo: repo, away: name.isNotEmpty);
  final setup = asked.setup;
  if (setup == null) {
    stderr.writeln(asked.refusal);
    exit(2);
  }
  if (!File('${setup.memory}/MEMORY.md').existsSync()) {
    stderr.writeln('install: ${setup.memory} 에 MEMORY.md 가 없습니다 — 메모리 '
        '폴더가 아니거나, 동기화가 아직 다 받지 못했습니다.');
    exit(2);
  }

  final file = File('${setup.repo}/.claude/settings.local.json');
  final before = file.existsSync() ? file.readAsStringSync() : '{}';
  final settings = settingsWith(
    jsonDecode(before) as Map<String, dynamic>,
    setup,
  );
  final after = '${const JsonEncoder.withIndent('  ').convert(settings)}\n';
  if (args.contains('--dry')) {
    stdout.write(after);
    return;
  }

  Directory(setup.board).createSync(recursive: true);
  file.parent.createSync(recursive: true);
  // The file as it was, once: what a person wrote by hand is not thrown away
  // by the first run of a tool.
  final kept = File('${setup.board}/.settings.local.json.before-install');
  if (file.existsSync() && !kept.existsSync()) kept.writeAsStringSync(before);
  file.writeAsStringSync(after);
  Process.runSync('git', [
    '-C',
    setup.repo,
    'config',
    'core.hooksPath',
    '.githooks',
  ]);

  stdout.writeln('install: ${file.path}');
  stdout.writeln('  이 기계      ${name.isEmpty ? '보드를 가진 기계' : name}');
  stdout.writeln('  보드 폴더    ${setup.board}');
  stdout.writeln('  메모리 폴더  ${setup.memory}');
  stdout.writeln('  보드 주소    ${boardAddressOf(setup)}');
  if (setup.home != null &&
      !File('${setup.board}/.board-token').existsSync()) {
    stdout.writeln('⚠️비밀값 파일이 아직 없습니다 — 보드를 가진 기계의 보드 '
        '폴더에 있는 `.board-token` 을 이 자리에 복사하세요: '
        '${setup.board}/.board-token');
  }
  stdout.writeln('새로 여는 세션부터 적용됩니다.');
}
