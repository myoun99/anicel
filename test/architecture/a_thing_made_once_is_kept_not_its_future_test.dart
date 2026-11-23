import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WHAT IS MADE ONCE AND KEPT IS KEPT AS ITSELF — `MadeOnce`
/// (`lib/src/core/made_once.dart`) — NOT AS THE FUTURE IT WAS MADE BY.
///
/// Card an-engine-setup-hangs-in-a-batch (2026-11-23): a done future
/// answers what listens to it from then on in the zone it was made in, and
/// a widget test's zone is its faked clock, which nobody pumps once that
/// test ends. The app's engine opening was kept so, made in the shell's
/// widget test, and every file bundled after it stood in its `setUpAll` for
/// good. Five such keepings were written by hand, four of them handing the
/// future on; four more were found beside them that day (a plugin index, a
/// font index, the PDF probe, the picture side) — written the same way.
///
/// ⛔A behaviour test cannot hold this: a tenth keeping, written by hand
/// and first asked for in the real zone, passes every pin. What gives one
/// away is what it has to hold — a future, kept in a field it fills once —
/// so that is what is scanned for.
void main() {
  test('nothing under lib/ fills a field of a future once but the one law, '
      'outside the ledger — and every ledger entry still does', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._futuresKeptOnce(libPath(file), file.readAsStringSync()),
      ],
      _notAnotherMadeOnce.keys,
      unledgered:
          'what is made once and kept is a `MadeOnce` — `of` it '
          '(`KeptOnTheAppsEngine.once` on the app\'s engine). A future kept '
          'for something else goes in the ledger, with why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_notAnotherMadeOnce);
  });

  test('the scan sees a planted keeping by its field — filled once, or '
      'kept on the app\'s engine — and not one in a comment, nor a field '
      'set another way', () {
    const planted = '''
  Future<void>? _loading;
  Future<void> load() => _loading ??= _read();
  static Future<int>? _side;
  static Future<int> side() => _side ??= _measure();
  final _tools = KeptOnTheAppsEngine<Future<Tools>>();
  final KeptOnTheAppsEngine<Future<void>> _strips = KeptOnTheAppsEngine();
  // Future<void>? _said; … _said ??= say();
  Future<void>? _onItsWay;
  void ask() => _onItsWay = run();
''';
    expect(_futuresKeptOnce('planted.dart', planted), [
      'planted.dart: _loading',
      'planted.dart: _side',
      'planted.dart: _tools',
      'planted.dart: _strips',
    ]);
  });
}

/// Futures filled once and kept that are not a thing made once — and the
/// law's own.
const _notAnotherMadeOnce = <String, String>{
  'lib/src/core/made_once.dart: _making':
      'the one law — the making, joined while it goes and let go as it ends',
  'lib/src/services/media/video_decode_worker.dart: _starting':
      'no thing kept as its future: the worker is kept as itself (_worker) '
      'and handed at once once it answers; this is its start, joined while '
      'it goes, and forgotten with the worker when the worker stops',
  'lib/src/ui/playback/engine_frame_picture_store.dart: opening':
      'made in no one\'s zone (Zone.root), so no test\'s faked clock holds '
      'it while it opens nor once it is done — a store\'s tools are waited '
      'for by screens of every test\'s zone. ⛔Not the app\'s engine\'s way: '
      'a widget test has the engine it asks for by its next pump '
      '(a-process-first-test-never-sees-the-canvas-stand-Q1)',
};

/// Each future [source] fills once and keeps, by `path: field`, comments
/// apart: a field of a nullable future set with `??=`, and any future kept
/// on the app's engine.
List<String> _futuresKeptOnce(String path, String source) {
  final code = codeOfLines(source);
  return [
    for (final field in _futureField.allMatches(code))
      if (RegExp('\\b${field.group(1)}\\s*\\?\\?=').hasMatch(code))
        '$path: ${field.group(1)}',
    for (final kept in _keptOnTheEngine.allMatches(code))
      '$path: ${kept.group(1) ?? kept.group(2)}',
  ];
}

final _futureField = RegExp(r'Future<[^;=]*>\?\s+(\w+)\s*;');
final _keptOnTheEngine = RegExp(
  r'(\w+)\s*=\s*KeptOnTheAppsEngine<Future<'
  r'|KeptOnTheAppsEngine<Future<[^;=]*>>\s+(\w+)',
);
