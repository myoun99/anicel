import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// 유저 2026-10-07: 「작업을 노트북이 해줫으면 한단거지」, and on how its
/// branches reach this machine: 「브랜치는 깃 랩 미러로하고」 (cards
/// work-runs-on-the-surface-too, a-lane-arrives-from-another-machine). A
/// clone that names itself (`git config anicel.machine …`) is an AWAY
/// machine: it cuts lanes, sends them, and lands nothing; the machine that
/// holds the trunk receives them and lands them through every gate.
///
/// ⚠️These pin WHERE the script asks and refuses — the suite spawns no
/// process (tests_do_not_race_the_code_test). What it DOES was run by hand
/// that day in scratch repositories (a bare mirror, a trunk clone, an away
/// clone; stand-in `flutter` and `dart`): an away lane is cut under the
/// machine's name · `land` refuses there · a backup copy is not an offer ·
/// `send` refuses a lane that is not on top of the trunk and offers one that
/// is · the trunk's machine lists, receives and lands it, and offer and copy
/// leave the mirror · the away `sync` lets go of the landed lane, keeps one
/// that grew since it was sent, and refuses a master that holds a commit of
/// its own · neither machine pushes the other's lanes. Two faults were found
/// that way and are pinned below by name.
void main() {
  final lane = LaneScript(File('tool/lane.sh').readAsStringSync());
  int at(List<String> code, String text) =>
      code.indexWhere((line) => line.contains(text));

  group('nothing lands on an away machine', () {
    test('🚨`land` refuses there before it touches anything', () {
      final land = lane.codeOf('cmd_land');
      final refuses = at(land, 'away && die');
      expect(refuses, isNot(-1));
      expect(
        [
          for (final line in land.take(refuses))
            if (line.contains('git ') || line.contains('flutter ')) line,
        ],
        isEmpty,
        reason: 'no git and no gate comes before the refusal',
      );
      expect(refuses, lessThan(at(land, r'rebase "$TRUNK"')));
    });

    test('🚨it never pushes master: the push of the trunk returns first', () {
      final push = lane.codeOf('mirror_trunk');
      final returns = at(push, 'away && return 0');
      expect(returns, isNot(-1));
      expect(returns, lessThan(at(push, 'push')));
      expect(returns, lessThan(at(push, 'mirroring')), reason: 'nor says so');
    });
  });

  group('the trunk\'s machine never takes master from the mirror', () {
    test('🚨master is fetched in ONE function, and that one refuses on the '
        'trunk\'s machine before anything else', () {
      expect(lane.functions, contains('cmd_sync'), reason: 'LIVENESS');
      final fetchers = [
        for (final function in lane.functions)
          if (lane
              .codeOf(function)
              .any((l) => l.contains('fetch') && l.contains(r'"$TRUNK"')))
            function,
      ];
      expect(fetchers, ['cmd_sync']);

      final sync = lane.codeOf('cmd_sync');
      final refuses = at(sync, 'away || die');
      expect(refuses, isNot(-1));
      expect(
        [
          for (final line in sync.take(refuses))
            if (line.contains('git ')) line,
        ],
        isEmpty,
      );
    });

    test('🚨`receive` takes the ONE lane that was offered — into a lane of '
        'that name, and nothing else comes with it', () {
      final receive = lane.codeOf('cmd_receive');
      final fetches = [
        for (final line in receive)
          if (line.contains('fetch') || line.contains('refs/heads/')) line,
      ].join(' ');
      expect(
        fetches,
        contains(r'"refs/heads/sent/$name:refs/heads/work/$name"'),
      );
      expect(receive.join('\n'), isNot(contains(r'"$TRUNK"')));
      expect(at(receive, 'away && die'), isNot(-1));
      expect(at(receive, 'away && die'), lessThan(at(receive, 'fetch')));
    });
  });

  group('sync', () {
    test('🚨a master that is AHEAD of the trunk is refused before the merge '
        '— the merge itself calls that 「already up to date」 (found running '
        'it, 2026-10-07)', () {
      final sync = lane.codeOf('cmd_sync');
      final asked = at(sync, r'merge-base --is-ancestor "$TRUNK" FETCH_HEAD');
      final merged = at(sync, 'merge --ff-only FETCH_HEAD');
      expect(asked, isNot(-1));
      expect(merged, isNot(-1));
      expect(asked, lessThan(merged));
      expect(at(sync, 'fetch'), lessThan(asked));
    });

    test('it lets go of what landed, after the trunk is taken', () {
      final sync = lane.codeOf('cmd_sync');
      expect(
        at(sync, 'landed_lanes_leave'),
        greaterThan(at(sync, 'merge --ff-only FETCH_HEAD')),
      );
    });
  });

  group('a lane that landed leaves the machine that sent it', () {
    late final leave = lane.codeOf('landed_lanes_leave');

    test('🚨only on the mirror\'s own word: a mirror that cannot be asked '
        'drops nothing', () {
      final asked = at(leave, 'ls-remote');
      expect(asked, isNot(-1));
      expect(at(leave, '|| return 0'), inInclusiveRange(asked, asked + 2));
      expect(at(leave, 'cmd_drop'), greaterThan(at(leave, '|| return 0')));
      expect(
        leave.join('\n'),
        contains(r'"refs/heads/sent/$MACHINE/*"'),
        reason: 'it asks after the OFFERS, and only this machine\'s',
      );
    });

    test('🚨a lane that grew since it was sent is KEPT: it is dropped only '
        'when its tip is still what was sent', () {
      final same = at(leave, r'rev-parse "$ref")" = "$sent"');
      final drop = at(leave, 'cmd_drop');
      final other = at(leave, 'else');
      expect(same, isNot(-1));
      expect(drop, inExclusiveRange(same, other));
      expect(
        at(leave, 'config --unset'),
        greaterThan(other),
        reason: 'the kept lane stops being asked about, and says why',
      );
    });

    test('a lane that was never sent is not asked about at all', () {
      final sent = at(leave, r'config --get "branch.$ref.sent"');
      expect(sent, isNot(-1));
      expect(leave[sent], contains('|| continue'));
      expect(sent, lessThan(at(leave, 'cmd_drop')));
    });
  });

  group('send', () {
    late final send = lane.codeOf('cmd_send');

    test('🚨what is offered is what was measured: clean, then the trunk as '
        'the mirror has it, then the lane on top of it — and only then the '
        'push', () {
      final clean = at(send, r'lane_is_clean "$p" || die');
      final synced = at(send, 'cmd_sync');
      final onTop = at(send, r'merge-base --is-ancestor "$TRUNK" HEAD || die');
      final pushed = at(send, 'push --quiet');
      expect([clean, synced, onTop, pushed], everyElement(isNot(-1)));
      expect(clean, lessThan(synced));
      expect(synced, lessThan(onTop));
      expect(onTop, lessThan(pushed));
      expect(
        send.join('\n'),
        isNot(contains('rebase "')),
        reason: 'it does not rebase for the author: a rebase needs its gates '
            'again, and those are the author\'s to run',
      );
    });

    test('🚨it writes the OFFER — sent/…, never the copy — and notes what '
        'was offered', () {
      final all = send.join('\n');
      expect(
        all,
        contains(r'"+refs/heads/work/$name:refs/heads/sent/$name"'),
      );
      expect(all, isNot(contains(r':refs/heads/work/$name"')));
      expect(
        at(send, r'config "branch.work/$name.sent"'),
        greaterThan(at(send, 'push --quiet')),
      );
      expect(at(send, 'away || die'), lessThan(at(send, 'push --quiet')));
    });
  });

  group('a copy is not an offer', () {
    test('🚨`incoming` reads the offers and never the copies (a backup of a '
        'half-done lane looked like one waiting to land — found running it, '
        '2026-10-07)', () {
      final incoming = lane.codeOf('cmd_incoming').join('\n');
      expect(incoming, contains("'refs/heads/sent/*/*'"));
      expect(incoming, isNot(contains('refs/heads/work/*')));
    });

    test('🚨each machine backs up its own lanes and nobody else\'s', () {
      final backup = lane.codeOf('cmd_backup');
      final all = backup.join('\n');
      final awayPush = at(
        backup,
        r'"+refs/heads/work/$MACHINE/*:refs/heads/work/$MACHINE/*"',
      );
      final awayDone = backup.indexWhere(
        (line) => line.trim() == 'return 0',
        awayPush,
      );
      final homeList = at(backup, "'refs/heads/work/*')");
      expect([awayPush, awayDone, homeList], everyElement(isNot(-1)));
      expect(awayDone, lessThan(homeList), reason: 'away never reaches it');
      expect(
        all,
        isNot(contains("'+refs/heads/work/*:refs/heads/work/*'")),
        reason: 'a `*` in a push refspec crosses the slash and would push '
            'the lanes this machine only received',
      );
      expect(all, isNot(contains('refs/heads/sent/')), reason: 'nor offers');
    });

    test('🚨a landed lane leaves the mirror — its offer and its copy — '
        'after the merge, and without asking for a login', () {
      final land = lane.codeOf('cmd_land');
      final merged = at(land, 'merge --ff-only');
      final names = at(land, r'for gone in "sent/$name" "work/$name"; do');
      final deleted = at(land, r'--delete "$gone"');
      expect([merged, names, deleted], everyElement(isNot(-1)));
      expect(names, greaterThan(merged));
      expect(deleted, greaterThan(names));
      final push = land.sublist(names, deleted + 1).join('\n');
      expect(push, contains('GIT_TERMINAL_PROMPT=0'));
      expect(push, contains('GCM_INTERACTIVE=Never'));
    });
  });

  group('one lane, wherever it was cut', () {
    test('🚨`open` and `receive` furnish a worktree through one function — '
        'neither has an engine copy or a pub get of its own', () {
      for (final function in ['cmd_open', 'cmd_receive']) {
        final code = lane.codeOf(function).join('\n');
        expect(code, contains(r'furnish "$p"'), reason: function);
        expect(code, isNot(contains('pub get')), reason: function);
        expect(code, isNot(contains('ensure_engine')), reason: function);
      }
      final furnish = lane.codeOf('furnish').join('\n');
      expect(furnish, contains('flutter pub get'));
      expect(furnish, contains(r'ensure_engine "$p"'));
    });

    test('a lane\'s directory never nests: the slash of another machine\'s '
        'lane becomes a dash', () {
      expect(
        lane.text,
        contains(r'lane_path() { echo "$LANES/lane-${1//\//-}"; }'),
      );
    });

    test('🚨a name names one lane of one machine: no climbing out, no '
        'second slash, and an away machine\'s lanes are its own', () {
      final named = lane.codeOf('lane_named').join('\n');
      expect(named, contains('*..*'));
      expect(named, contains('*/*/*'));
      expect(named, contains(r'*) name="$MACHINE/$name" ;;'));
      expect(named, contains(r'"$MACHINE"/*) ;;'));
    });
  });

  test('🚨every command the script answers to is in the usage it prints', () {
    final commands = [
      for (final m in RegExp(
        r'^  ([a-z]+)\) shift; cmd_',
        multiLine: true,
      ).allMatches(lane.text))
        m.group(1)!,
    ];
    expect(commands, containsAll(['open', 'land', 'send', 'receive']));
    final printed = RegExp(r"sed -n '2,(\d+)p'").firstMatch(lane.text);
    expect(printed, isNotNull, reason: 'LIVENESS — the fallback prints lines');
    final usage = lane.text
        .split('\n')
        .sublist(1, int.parse(printed!.group(1)!))
        .join('\n');
    for (final command in commands) {
      expect(
        usage,
        contains(
          RegExp('^#   bash tool/lane\\.sh $command\\b', multiLine: true),
        ),
        reason: command,
      );
    }
  });
}
