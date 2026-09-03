// A LOG LINE THAT NOBODY DECIDED ON IS NOISE THE APP SHIPS.
//
// `print` and `debugPrint` are not error handling and not telemetry — they
// are a developer talking to a console that, on a tablet, nobody reads. The
// audit's baseline (2026-09-01) found six of them and every one had a
// reason; this ledger keeps those reasons next to the counts so a seventh
// cannot slip in as "just a debug line".
//
// The ledger is keyed by file and holds the COUNT of log calls the file may
// contain. Counts rather than line numbers, because a line number moves
// every time the file above it is edited and a ledger that rots is a ledger
// nobody reads. A file that gains a call fails; a file that loses one fails
// too — the entry is paid off and must be deleted here (2026-09-03).
//
// It is an instrument, so here is what it looks like when it lies: it reads
// source text, so a `print(` inside a string literal or a comment counts,
// and a call spelled `foundation.debugPrint(` or aliased through a variable
// does not.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to log, how many calls each, and why.
const _ledger = <String, ({int calls, String why})>{
  'lib/dev/brush_lab_main.dart': (
    calls: 1,
    why:
        'The brush lab is a developer entry point (lib/dev) whose console '
        'IS its output.',
  ),
  'lib/src/core/dev_profile.dart': (
    calls: 1,
    why:
        'labProbe reports timings only in BRUSH_LAB_PROFILE builds; the '
        'print is behind that compile-time flag.',
  ),
  'lib/src/ui/playback/playback_prerender_scheduler.dart': (
    calls: 1,
    why:
        'Same BRUSH_LAB_PROFILE probe, for the warm-up path (the site says '
        'so with its own ignore comment).',
  ),
  'lib/src/ui/playback/audioplayers_clip_player.dart': (
    calls: 3,
    why:
        'Audio failure logs (load / start / volume). The audio lane owns '
        'this file; routing those failures to a user-visible surface is that '
        'lane\'s call, not the audit\'s (2026-09-03).',
  ),
};

/// A `print(` or `debugPrint(` call at the start of a statement or after an
/// operator — not `myPrint(` and not `.print(`.
final _logCall = RegExp(r'(?<![\w.])(?:print|debugPrint)\(');

void main() {
  test('every print/debugPrint in lib/ is on the ledger, and the ledger '
      'has no paid-off entries', () {
    final counts = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      final calls = _logCall.allMatches(entity.readAsStringSync()).length;
      if (calls > 0) {
        counts[path] = calls;
      }
    }

    final unledgered = <String>[
      for (final entry in counts.entries)
        if (_ledger[entry.key]?.calls != entry.value)
          '${entry.key}: ${entry.value} call(s), ledger says '
              '${_ledger[entry.key]?.calls ?? 0}',
    ];
    expect(
      unledgered,
      isEmpty,
      reason:
          'Log calls the ledger does not account for. Remove the call, or '
          'add the file to `_ledger` with the reason it must log:\n  '
          '${unledgered.join('\n  ')}',
    );

    final paidOff = <String>[
      for (final path in _ledger.keys)
        if (!counts.containsKey(path)) path,
    ];
    expect(
      paidOff,
      isEmpty,
      reason:
          'Ledger entries whose file no longer logs (or is gone). Delete '
          'them:\n  ${paidOff.join('\n  ')}',
    );
  });
}
