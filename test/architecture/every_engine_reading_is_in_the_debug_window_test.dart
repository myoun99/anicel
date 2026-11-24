import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★WHAT THE ENGINE SAYS OF ITSELF, THE DEBUG WINDOW SHOWS.
///
/// 🗣️유저 2026-11-24 (card one-debug-window-shows-everything, by 관제):
/// 「하나하나 추가할 빠에 뭐든 화면에 보이게 싹 다 넣은 디버그 창」 — and
/// 관제's law for it: an instrument the code has is shown, and one left out
/// says why. A reading nobody shows reads exactly like a reading that says
/// nothing is wrong: the engine's fills and readouts lay in the census's
/// rest, and its picture pages were read by nothing once the frame
/// statistics' MEMORY line went (both found by this list).
///
/// The engine's readings are its one engine's getters and the package's
/// statics. Each is named by the window's sources, or [_notShown] says why
/// — `via:<symbol>` where the window reads it through something of the
/// app's, which is checked, not taken on trust.
void main() {
  test('every reading of the engine is named by the debug window, or says '
      'why not', () {
    final engine = _source(_enginePath);
    final window = [for (final path in _windowPaths) _source(path)].join();
    final missing = <String>[];

    for (final reading in _readingsOf(engine)) {
      final excuse = _notShown[reading.name];
      if (excuse != null) {
        if (excuse.startsWith('via:')) {
          final symbol = excuse.substring(4).split(' ').first;
          if (!window.contains(symbol)) {
            missing.add('${reading.name} (claims via:$symbol — the window '
                'has no such reader)');
          }
        }
        continue;
      }
      if (!window.contains(reading.asRead)) {
        missing.add(reading.name);
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'the engine says these and the debug window names none of them — '
          'show it, or put it in _notShown with the reason:\n'
          '${missing.join('\n')}',
    );
  });

  test('the ledger has no stale entries', () {
    final live = {
      for (final reading in _readingsOf(_source(_enginePath))) reading.name,
    };
    expect(
      _notShown.keys.where((name) => !live.contains(name)),
      isEmpty,
      reason: 'the ledger names readings that no longer exist',
    );
  });

  test('the scan finds the readings it is for', () {
    // ⛔A scan that finds nothing passes: these are known to exist.
    final names = {
      for (final reading in _readingsOf(_source(_enginePath))) reading.name,
    };
    expect(
      names,
      containsAll(<String>[
        'GpuEngine.waitsPastTheirLimit',
        'GpuEngine.pictureBytes',
        'GpuFloods.liveBytes',
        'SharedTexture.untold',
      ]),
    );
    expect(names.where((name) => name.contains('.debug')), isEmpty);
  });
}

const _enginePath = 'packages/gpu_engine/lib/gpu_engine.dart';

/// The window's sources: itself, the census it shows, and the lines it
/// takes whole from the frame statistics, the engine's stages and the
/// screen's probe.
const _windowPaths = <String>[
  'lib/src/ui/debug/debug_window.dart',
  'lib/src/ui/diagnostics/memory_census.dart',
  'lib/src/ui/debug/frame_stats.dart',
  'lib/src/ui/debug/engine_stages.dart',
  'lib/src/ui/debug/screen_check.dart',
];

/// Readings the window does not name, and why.
const _notShown = <String, String>{
  'GpuEngine.isClosed': 'the app closing its own engine, not a reading',
  'GpuEngine.picturesWeighedAgain':
      'a signal to weigh the pictures again, which the census then reads',
  'GpuEngine.screenSaid':
      'via:ScreenTexture.path — the newest screen opened keeps it',
  'SharedTexture.untold':
      'via:ScreenTexture.surfaceWaits — the waits keep the words',
};

typedef _Reading = ({String name, String asRead});

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

final _classDeclaration = RegExp(
  '^(?:abstract |final |base |sealed |interface )*'
  r'(?:class|enum|mixin|extension type|extension) (\w+)',
  multiLine: true,
);

final _getter = RegExp(
  r'^  (static )?[\w<>?, ()]+? get ([a-z]\w*)',
  multiLine: true,
);

/// The engine's readings in [source]: every public static getter of the
/// package's classes, and every public getter of [GpuEngine] — the test
/// seams (`debug…`) apart.
Iterable<_Reading> _readingsOf(String source) sync* {
  final classes = _classDeclaration.allMatches(source).toList();
  for (final match in _getter.allMatches(source)) {
    final name = match.group(2)!;
    if (name.startsWith('debug')) {
      continue;
    }
    final owner = classes
        .lastWhere((declaration) => declaration.start < match.start)
        .group(1)!;
    if (owner.startsWith('_')) {
      continue;
    }
    final isStatic = match.group(1) != null;
    if (isStatic) {
      yield (name: '$owner.$name', asRead: '$owner.$name');
    } else if (owner == 'GpuEngine') {
      yield (name: '$owner.$name', asRead: '.$name');
    }
  }
}
