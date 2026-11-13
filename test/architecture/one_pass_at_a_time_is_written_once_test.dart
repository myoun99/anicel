import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WORK DONE IN PASSES, ONE AT A TIME, IS WRITTEN IN ONE PLACE —
/// `OnePassAtATime` (`lib/src/core/one_pass_at_a_time.dart`).
///
/// Card one-in-flight-the-rest-in-the-next (2026-11-13): written out by
/// hand six times, and the undo stack's spill still ran again after a pass
/// that threw — the spin the cels' cooling had been cured of (a666cc4c1).
///
/// ⛔A behaviour test cannot hold this: a seventh copy written well runs its
/// passes perfectly. What gives one away is what it has to keep — a flag
/// that says a pass is on its way — and where it keeps it: raised before a
/// loop, or let go of as a future lands. Those two are what is scanned for.
void main() {
  test('nothing under lib/ keeps its own pass on its way but the one law, '
      'outside the ledger — and every ledger entry is still there', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._passesKeptByHand(libPath(file), file.readAsStringSync()),
      ],
      _notAnotherOnePass.keys,
      unledgered:
          'work done in passes, one at a time, is a `OnePassAtATime` — ask '
          'it. A flag of this shape that is something else goes in the '
          'ledger, with why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_notAnotherOnePass);
  });

  test('the six that were written by hand hold the one law', () {
    for (final path in _holders) {
      expect(
        File(path).readAsStringSync(),
        contains('OnePassAtATime('),
        reason: path,
      );
    }
  });

  test('the scan sees each shape the six were written in, and not one in a '
      'comment', () {
    const planted = '''
  Future<void> _drain() async {
    _writing = true;
    while (_waiting != null) {
      await _write();
    }
    _writing = false;
  }
  Future<void> _flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        await _post();
      }
    } finally {
      _flushing = false;
    }
  }
  void _scheduleCooling() {
    _activeCooling = _coolLoop().whenComplete(() {
      _activeCooling = null;
      _scheduleCooling();
    });
  }
  void _writeThrough() {
    _writingThrough = true;
    unawaited(
      _store.patchThrough().then(
        (went) {
          _writingThrough = false;
          _writeWhatIsOwed();
        },
        onError: (Object error, StackTrace stack) {
          _writingThrough = false;
        },
      ),
    );
  }
  // _said = true; while (_more) {}
''';
    expect(_passesKeptByHand('planted.dart', planted), [
      'planted.dart: _writing',
      'planted.dart: _flushing',
      'planted.dart: _activeCooling',
      'planted.dart: _writingThrough',
    ]);
  });
}

/// The six that wrote it out by hand, which hold the law now.
const _holders = [
  'lib/src/ui/playback/frame_picture_view.dart',
  'lib/src/services/persistence/versioned_settings_file.dart',
  'lib/src/services/usage_stats/usage_stats.dart',
  'lib/src/services/brush_tip_thumbnails.dart',
  'lib/src/services/brush_frame_store.dart',
  'lib/src/services/history_manager.dart',
];

/// Flags of the shape that are not a pass kept on its way by hand.
const _notAnotherOnePass = <String, String>{};

/// Each flag [source] keeps for a pass of its own on its way, by
/// `path: field`, once a field, comments apart.
List<String> _passesKeptByHand(String path, String source) {
  final code = codeOfLines(source);
  return [
    for (final field in {
      for (final shape in _shapes)
        for (final match in shape.allMatches(code)) match.group(1)!,
    })
      '$path: $field',
  ];
}

/// A flag raised before a loop that runs while work is due — and one let go
/// of as the future of a pass lands, where the next is begun from.
final _shapes = [
  RegExp(r'(_\w+) = true;[^}]{0,300}?\bwhile \('),
  RegExp(
    r'(?:\.(?:then|whenComplete)\(\s*|onError: )\([^)]*\) \{\s*'
    r'(_\w+) = (?:false|null);',
  ),
];
