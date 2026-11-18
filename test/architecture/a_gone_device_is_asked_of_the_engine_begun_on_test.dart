import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WHETHER A DEVICE WENT IS ASKED OF THE ENGINE THE WORK BEGAN ON
/// (`GpuEngine.isGone`, of the engine kept from before the wait) — not of
/// the engine the app has when the asking comes (`appGpuEngineIsGone`).
///
/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — the app lets a gone engine go
/// the turn after it first hears of it, so work that waited longer than
/// that finds the app on no engine or on the next, and the app's says no:
/// ↩️a tip's picture asked so was said as an error and left empty for the
/// run (`BrushTipThumbnails`, 2026-11-13), and a vector layer drawn as its
/// device goes opens blank with no word (board
/// `a-vector-layer-read-as-its-device-goes-opens-blank`, measured the same
/// day).
///
/// ⛔SO THIS SCANS THE SOURCE: the two questions have one answer in every
/// test that never lets an engine go, which is nearly every test. Who asks
/// the app's is listed, with why the app's is the one it means.
void main() {
  test('no file asks whether the app\'s engine is gone but those the ledger '
      'names, as often as it says — and each it names still asks', () {
    final found = <String, List<int>>{};
    for (final file in dartFilesUnder('lib')) {
      final reads = _readsOfTheApps(file.readAsStringSync());
      if (reads.isNotEmpty) {
        found[libPath(file)] = reads;
      }
    }
    expectCountsMatchLedger(
      {for (final MapEntry(:key, :value) in found.entries) key: value.length},
      {
        for (final MapEntry(:key, value: (count, _)) in _asksTheApps.entries)
          key: count,
      },
      grew:
          'work that began on an engine keeps it and asks it — '
          '`engine.isGone` — after its wait: `appGpuEngineIsGone` speaks of '
          'whichever engine the app has by then. Where the app\'s IS the '
          'one meant, the file goes in the ledger, with why',
      paidOff: 'these ask it so no more — take them off the list',
      hits: found,
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy({
      for (final MapEntry(:key, value: (_, why)) in _asksTheApps.entries)
        key: why,
    });
  });

  test('the scan counts a read where it is one — not the getter\'s own '
      'line, an import that shows it, or a comment that names it', () {
    const planted = '''
import '../native/app_gpu_engine.dart'
    show appGpuEngineIsGone, appGpuEngineOpen;

/// Asks [appGpuEngineIsGone].
bool get appGpuEngineIsGone => _its.engine?.isGone ?? false;
void heard() {
  if (!appGpuEngineIsGone) return; // appGpuEngineIsGone
  final gone = appGpuEngineOpen.value == null || appGpuEngineIsGone;
}
''';
    expect(_readsOfTheApps(planted), [7, 8]);
  });
}

/// Who asks of the app's engine, how often, and why the app's is meant.
const _asksTheApps = <String, (int, String)>{
  'lib/src/native/app_gpu_engine.dart': (
    1,
    '`letTheGoneAppGpuEngineGo` lets the app\'s engine go where that is '
        'gone: the app\'s is what it lets go of',
  ),
  'lib/src/native/engine_refusals.dart': (
    2,
    'the door hears a refusal with no engine to it, and what it opens '
        'another for — and whether the one it opened stands — is the '
        'engine the app has at that moment',
  ),
};

/// The lines of [source] that read `appGpuEngineIsGone`: not where it is
/// declared, shown by an import, or named in a comment.
List<int> _readsOfTheApps(String source) {
  final code = codeOfLines(
    source
        .replaceAll('\r\n', '\n')
        .replaceAllMapped(
          RegExp('^import [^;]*;', multiLine: true),
          (directive) => '\n' * '\n'.allMatches(directive[0]!).length,
        ),
  );
  final read = RegExp(r'(?<!get )\bappGpuEngineIsGone\b');
  return [
    for (final (index, line) in code.split('\n').indexed)
      if (read.hasMatch(line)) index + 1,
  ];
}
