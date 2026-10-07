import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/session_hooks/install.dart';

/// 유저 2026-10-07: 「작업을 노트북이 해줫으면 한단거지」 — a second machine
/// runs sessions, and on where the hooks live: 「훅 보관위치 알아서
/// 권장대로해줘」 (= the repository; card work-runs-on-the-surface-too).
/// Until then the hooks sat in one machine's memory folder with that
/// machine's paths written into them, and the settings that named them were
/// written by hand. Now one command writes a machine's settings from three
/// facts — its board folder, its memory folder, and (where the board is
/// not) the address of the machine that holds it — and the scripts are
/// handed everything else.
///
/// ⚠️The scripts themselves are bash and the suite spawns no process
/// (tests_do_not_race_the_code_test): what they DO was run by hand from
/// their new place that day — `autorun_test.sh` 35/35 and
/// `guard_git_add_test.sh` 22/22, the conflicted-copy guard on names in
/// three languages. What is pinned here is what a machine is GIVEN, and
/// that the scripts can be given it.
void main() {
  const MachineSetup holder = (
    repo: 'C:/code/anicel',
    board: 'C:/local/board',
    memory: 'E:/Sync/memory',
    home: null,
    oldMemory: null,
  );
  const MachineSetup moved = (
    repo: 'C:/code/anicel',
    board: 'C:/local/board',
    memory: 'E:/Sync/memory',
    home: null,
    oldMemory: 'C:/local/old memory',
  );
  const MachineSetup away = (
    repo: 'D:/work/anicel',
    board: 'D:/local/board',
    memory: 'D:/Sync/memory',
    home: 'http://MYOUN_HOME.local:4321',
    oldMemory: null,
  );

  /// Every `command` of a hooks block, under the event that runs it.
  Map<String, List<String>> commandsOf(Map<String, dynamic> hooks) => {
    for (final event in hooks.entries)
      event.key: [
        for (final group in event.value as List)
          for (final hook in (group as Map)['hooks'] as List)
            '${(hook as Map)['command']}',
      ],
  };
  List<String> every(MachineSetup setup) => [
    for (final commands in commandsOf(hooksFor(setup)).values) ...commands,
  ];
  String theOne(MachineSetup setup, String script) =>
      every(setup).singleWhere((command) => command.contains('/$script"'));

  final scripts = {
    for (final entity in Directory('tool/session_hooks').listSync())
      if (entity.path.endsWith('.sh'))
        entity.uri.pathSegments.last: File(
          entity.path,
        ).readAsStringSync(),
  };

  group('the hooks a machine is given', () {
    test('🚨every script the settings name IS in tool/session_hooks, and '
        'every hook there is named — a script nobody installs guards '
        'nothing', () {
      final named = {
        for (final command in every(moved))
          RegExp(
            r'/tool/session_hooks/([a-z_]+\.sh)"',
          ).firstMatch(command)?.group(1),
      };
      expect(named, isNot(contains(null)), reason: 'each names a script');
      expect(named, hasLength(greaterThan(5)), reason: '⛔premise');
      expect(named.difference(scripts.keys.toSet()), isEmpty);
      expect(
        scripts.keys.toSet().difference(named),
        {
          'autorun_test.sh',
          'board_gate_test.sh',
          'guard_git_add_test.sh',
          'hook_says_test.sh',
          // Read in by every hook that speaks, never run by itself
          // (a_hook_speaks_through_one_mouth_test).
          'hook_says.sh',
        },
        reason: 'what is there and not installed is a test run by hand, or '
            'the one file the hooks read in',
      );
    });

    test('🚨every path a command holds is quoted: a folder with a space in '
        'its name is still one argument', () {
      for (final command in every(moved)) {
        expect(
          command,
          matches(RegExp(r'^bash( "[^"]+")+$')),
          reason: command,
        );
      }
      expect(
        theOne(moved, 'knowledge_fold.sh'),
        endsWith('"C:/local/old memory" "E:/Sync/memory"'),
      );
    });

    test('they run from the repository this machine installed from', () {
      for (final command in every(away)) {
        expect(command, startsWith('bash "D:/work/anicel/tool/session_hooks/'));
      }
    });
  });

  group('the scripts can be handed to any machine', () {
    test('🚨none of them names a path of one machine — the one drive letter '
        'left is where the GitHub installer puts gh, and PATH is asked when '
        'it is not there', () {
      expect(scripts, isNotEmpty, reason: '⛔premise: the scan found them');
      for (final script in scripts.entries) {
        for (final line in const LineSplitter().convert(script.value)) {
          // What a comment tells of a path that once was written here is
          // history, not a path this script reads.
          if (line.trimLeft().startsWith('#')) continue;
          expect(line, isNot(contains('/Users/')), reason: script.key);
          if (!line.contains(RegExp('[A-Z]:/'))) continue;
          expect(
            line,
            'GH="C:/Program Files/GitHub CLI/gh.exe"',
            reason: script.key,
          );
        }
      }
      for (final name in const ['board_up.sh', 'board_gate.sh']) {
        expect(
          scripts[name],
          contains(r'[ -x "$GH" ] || GH="$(cygpath -m "$(command -v gh'),
          reason: name,
        );
      }
    });

    test('🚨none of them finds its folder by sitting in it: the board folder '
        'is an argument, and a script with none does nothing', () {
      for (final name in const [
        'board_up.sh',
        'board_gate.sh',
        'autorun_arm.sh',
        'autorun_gate.sh',
      ]) {
        final text = scripts[name]!;
        final handed = text.indexOf('MEM="\${1:-}"\n[ -d "\$MEM" ] || exit 0');
        expect(handed, isNot(-1), reason: name);
        expect(
          text,
          isNot(contains(RegExp(r'^MEM="\$\(cd ', multiLine: true))),
          reason: name,
        );
      }
      expect(scripts['guard_memory_size.sh'], contains('INDEX="\${1:-}"'));
      expect(
        scripts['guard_memory_conflicts.sh'],
        contains('DIR="\${1:-}"\n[ -d "\$DIR" ] || exit 0'),
      );
    });

    test('🚨the board\'s gate asks whatever it is handed as the board — a '
        'file here, a server there — and starts the script beside it', () {
      final gate = scripts['board_gate.sh']!;
      expect(gate, contains(r'PLACE="${2:-$MEM/board.jsonl}"'));
      expect(gate, contains(r'raw=$("$MEM/board_check.exe" "$PLACE" 2>'));
      expect(gate, contains(r'("$HERE/board_up.sh" "$MEM" >/dev/null 2>&1 &)'));
      expect(
        gate,
        contains(r'ANICEL_BOARD_TOKEN_FILE:-$MEM/.board-token}'),
        reason: 'a server is asked with the secret beside the flags',
      );
    });

    test('🚨a machine that does not hold the board builds and starts no '
        'server — only the gate\'s exe', () {
      final up = const LineSplitter().convert(scripts['board_up.sh']!);
      int at(String text) => up.indexWhere((line) => line.contains(text));
      final server = at(r'if [ -z "$AWAY" ] && [ -f "$SRC" ]');
      final gate = at(r'if [ -f "$CHECK_SRC" ]');
      final leaves = at(r'[ -z "$AWAY" ] || exit 0');
      final secret = at(r'TOKEN="$MEM/.board-token"');
      final starts = up.indexWhere((line) => line.trim() == 'launch');
      expect([server, gate, leaves, secret, starts], everyElement(isNot(-1)));
      expect(up[gate], isNot(contains('AWAY')), reason: 'the gate is built');
      expect(leaves, greaterThan(gate), reason: 'after the gate\'s exe');
      expect(leaves, lessThan(secret), reason: 'before a secret is made');
      expect(leaves, lessThan(starts), reason: 'and before any launch');
      expect(
        at(r'AWAY="$(git -C "$REPO" config --get anicel.machine'),
        isNot(-1),
        reason: 'the one question tool/lane.sh asks too',
      );
    });

    test('🚨the server starts its own rebuild through the repository\'s '
        'script, handed the folder its records are in', () {
      final server = File('tool/board_server.dart').readAsStringSync();
      expect(
        server,
        contains(r"File('$_gitRoot/tool/session_hooks/board_up.sh')"),
      );
      expect(server, contains('[up.path, File(_recordsPath).parent.path],'));
    });
  });

  group('on the machine that holds the board', () {
    test('🚨the gate reads the records FILE — it runs at the end of every '
        'turn and must answer while the server is being rebuilt', () {
      expect(
        theOne(holder, 'board_gate.sh'),
        endsWith('"C:/local/board" "C:/local/board/board.jsonl"'),
      );
    });

    test('🚨a session\'s commands are given the SERVER as the board there '
        'too, so one process writes the records whichever machine spoke',
        () {
      expect(environmentFor(holder), {
        'ANICEL_BOARD': 'http://localhost:4321',
        'ANICEL_BOARD_TOKEN_FILE': 'C:/local/board/.board-token',
      });
    });

    test('the two folders are kept the same only where the memory was moved '
        'out of one', () {
      expect(every(holder).join('\n'), isNot(contains('knowledge_fold')));
      expect(
        theOne(moved, 'knowledge_fold.sh'),
        endsWith('"C:/local/old memory" "E:/Sync/memory"'),
      );
      final watched = {
        for (final group in hooksFor(moved)['PostToolUse'] as List)
          for (final hook in (group as Map)['hooks'] as List)
            '${(hook as Map)['if']}',
      };
      expect(watched, {
        'Edit(E:/Sync/memory/MEMORY.md)',
        'Write(E:/Sync/memory/MEMORY.md)',
        'Edit(C:/local/old memory/MEMORY.md)',
        'Write(C:/local/old memory/MEMORY.md)',
      });
    });

    test('🚨the size guard is handed the very index its `if` watches', () {
      for (final group in hooksFor(moved)['PostToolUse'] as List) {
        for (final hook in (group as Map)['hooks'] as List) {
          final watched = RegExp(
            r'\((.+)\)$',
          ).firstMatch('${(hook as Map)['if']}')!.group(1);
          expect(
            '${hook['command']}',
            endsWith('guard_memory_size.sh" "$watched"'),
          );
        }
      }
    });
  });

  group('on a machine that does not hold the board', () {
    test('🚨the gate and the session\'s commands both ask the machine that '
        'does', () {
      expect(
        theOne(away, 'board_gate.sh'),
        endsWith('"D:/local/board" "http://MYOUN_HOME.local:4321"'),
      );
      expect(environmentFor(away), {
        'ANICEL_BOARD': 'http://MYOUN_HOME.local:4321',
        'ANICEL_BOARD_TOKEN_FILE': 'D:/local/board/.board-token',
      });
    });
  });

  group('the settings file', () {
    const written = {
      'permissions': {
        'allow': ['Bash(git rm *)'],
      },
      'somethingAPersonAdded': true,
      'env': {'THEIRS': 'kept', 'ANICEL_BOARD': 'an old address'},
      'hooks': {
        'Stop': [
          {
            'hooks': [
              {'type': 'command', 'command': 'bash "C:/old/board_gate.sh"'},
            ],
          },
        ],
      },
    };

    test('🚨the hooks are written WHOLE — one from before is gone — and '
        'everything else a person had is kept', () {
      final settings = settingsWith(written, away);
      expect(jsonEncode(settings['hooks']), isNot(contains('C:/old/')));
      expect(settings['hooks'], hooksFor(away));
      expect(settings['permissions'], written['permissions']);
      expect(settings['somethingAPersonAdded'], isTrue);
      expect(settings['autoMemoryDirectory'], 'D:/Sync/memory');
      expect(settings['env'], {
        'THEIRS': 'kept',
        'ANICEL_BOARD': 'http://MYOUN_HOME.local:4321',
        'ANICEL_BOARD_TOKEN_FILE': 'D:/local/board/.board-token',
      });
    });

    test('running it twice writes the same file', () {
      final once = settingsWith(written, moved);
      expect(jsonEncode(settingsWith(once, moved)), jsonEncode(once));
    });
  });

  group('what is asked for', () {
    ({MachineSetup? setup, String? refusal}) ask(
      List<String> args, {
      bool away = false,
    }) => setupAsked(args, repo: r'C:\code\anicel', away: away);

    test('paths are taken the way a shell reads them', () {
      final asked = ask([
        '--board',
        r'C:\local\board\',
        '--memory',
        'E:/Sync/memory/',
        '--old-memory',
        r'C:\local\old memory',
      ]);
      expect(asked.refusal, isNull);
      expect(asked.setup, moved);
    });

    test('🚨the board folder is never the memory folder, nor inside it — '
        'one is this machine\'s, the other every machine\'s', () {
      for (final board in ['E:/Sync/memory', 'E:/Sync/memory/board']) {
        final asked = ask(['--board', board, '--memory', 'E:/Sync/memory']);
        expect(asked.setup, isNull, reason: board);
        expect(asked.refusal, contains('메모리 폴더'), reason: board);
      }
    });

    test('🚨a clone that named itself needs the address of the machine that '
        'holds the board, and the one that holds it takes none', () {
      const folders = ['--board', 'D:/local/board', '--memory', 'D:/Sync/m'];
      expect(ask(folders, away: true).refusal, contains('--home'));
      expect(
        ask([...folders, '--home', 'http://x:4321'], away: true).setup?.home,
        'http://x:4321',
      );
      expect(
        ask([...folders, '--home', 'http://x:4321']).refusal,
        contains('보드를 가진 기계'),
      );
      expect(
        ask([...folders, '--home', 'MYOUN_HOME'], away: true).refusal,
        contains('http://'),
      );
    });

    test('both folders are asked for by name', () {
      expect(ask(['--board', 'C:/local/board']).refusal, isNotNull);
      expect(ask(['--memory', 'E:/Sync/memory']).refusal, isNotNull);
      expect(ask(const []).refusal, isNotNull);
    });
  });

  // 2026-10-07, the Surface: the first commit of the first lane was refused
  // — 「Author identity unknown」. A machine nobody has committed from has
  // no author, and setting one by hand was a step no list named.
  group('a clone with no commit author is given the trunk\'s', () {
    Map<String, String> given({String name = '', String email = ''}) =>
        authorGiven(
          name: name,
          email: email,
          trunkName: 'Trunk Person\n',
          trunkEmail: ' trunk@users.noreply.example ',
        );

    test('both, where it has neither — as the trunk writes them', () {
      expect(given(), {
        'user.name': 'Trunk Person',
        'user.email': 'trunk@users.noreply.example',
      });
    });

    test('⛔what a person set is theirs: only the missing one is given, and '
        'a clone that has both is given nothing', () {
      expect(given(name: 'Someone'), {
        'user.email': 'trunk@users.noreply.example',
      });
      expect(given(email: 'someone@example.com'), {
        'user.name': 'Trunk Person',
      });
      expect(given(name: 'Someone', email: 'someone@example.com'), isEmpty);
    });

    test('⛔a trunk that names no author gives nothing — an empty name is '
        'not a name', () {
      expect(
        authorGiven(name: '', email: '', trunkName: '', trunkEmail: ' '),
        isEmpty,
      );
    });
  });

  // 2026-10-07, the Surface: the second clone showed `.claude/` as work to
  // commit. The first machine had hidden it with files only it has — its
  // global ignore and its clone's info/exclude — and a commit on a machine
  // that borrows the trunk is refused by its next `lane.sh sync`.
  group('what the tools make on a machine, the repository ignores', () {
    final ignored = {
      for (final line in File('.gitignore').readAsLinesSync()) line.trim(),
    };

    test('the settings file the installer writes', () {
      final path = settingsPathOf(holder);
      expect(path, startsWith('${holder.repo}/'));
      expect(ignored, contains(path.substring(holder.repo.length + 1)));
    });

    test('the folder the lane script keeps its worktrees in', () {
      const head = r'LANES="$ROOT/';
      final line = File('tool/lane.sh')
          .readAsLinesSync()
          .map((line) => line.trim())
          .singleWhere((line) => line.startsWith(head));
      final folder = line.substring(head.length, line.length - 1);
      expect(folder, isNotEmpty);
      expect(ignored, contains('$folder/'));
    });
  });
}
