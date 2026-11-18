import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WORK PUT OFF TILL THE CODE ON ITS WAY IS THROUGH, AND DONE ONCE, IS
/// WRITTEN IN ONE PLACE — `OnceAMicrotask`
/// (`lib/src/core/once_a_microtask.dart`).
///
/// Card told-once-a-microtask-is-written-nine-times (2026-11-13): written
/// out by hand nine times, one of them saying in its comment that it
/// answered as another did, for the same reason.
///
/// ⛔A behaviour test cannot hold this: a tenth copy written well tells
/// once perfectly. What gives one away is what it has to keep — a mark that
/// it is asked for already — set or read just before the microtask is
/// scheduled. That is what is scanned for.
void main() {
  test('nothing under lib/ marks its own microtask as asked for but the one '
      'law, outside the ledger — and every ledger entry is still there', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._microtasksMarkedByHand(libPath(file), file.readAsStringSync()),
      ],
      _notAnotherOnce.keys,
      unledgered:
          'work done once after the code on its way is a `OnceAMicrotask` — '
          'ask it. A mark of this shape that is something else goes in the '
          'ledger, with why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_notAnotherOnce);
  });

  test('the scan sees each shape the nine were written in, and not one in a '
      'comment or behind a condition that is no mark', () {
    const planted = '''
  void _announce() {
    if (_announcing) {
      return;
    }
    _announcing = true;
    scheduleMicrotask(() {
      _announcing = false;
      notifyListeners();
    });
  }
  void _enqueue() {
    if (!_drainScheduled) {
      _drainScheduled = true;
      // Off the paint phase.
      scheduleMicrotask(_drain);
    }
  }
  void drawnOn(int cut) {
    final scheduled = _drawnOn.isNotEmpty;
    _drawnOn.add(cut);
    if (scheduled) {
      return;
    }
    scheduleMicrotask(_tell);
  }
  void _follow() {
    if (!walkFollowsHistory) {
      return;
    }
    scheduleMicrotask(_walk);
  }
  // _said = true; scheduleMicrotask(_say);
''';
    expect(_microtasksMarkedByHand('planted.dart', planted), [
      'planted.dart: _announcing',
      'planted.dart: _drainScheduled',
      'planted.dart: scheduled',
    ]);
  });
}

/// Marks of the shape that are not work put off by hand — and the law's own.
const _notAnotherOnce = <String, String>{
  'lib/src/core/once_a_microtask.dart: _asked':
      'the one law — what every other asks',
  'lib/src/native/engine_refusals.dart: _opensAnother':
      'no work done once a microtask: the mark stays up while the app lets '
      'go of the gone engine and opens another, however long that takes, '
      'and is let go of when it is done',
  'lib/src/ui/input/control_press_claim.dart: _anOwnedLiftIsBeingDispatched':
      'no work put off: the mark IS the answer — that the lift being '
      'dispatched is a control\'s own — read by silentPress for the rest of '
      'that one dispatch, and only let go of in the microtask after it',
};

/// Each mark [source] keeps of a microtask asked for by hand, by
/// `path: name`, once a name, comments apart.
List<String> _microtasksMarkedByHand(String path, String source) {
  final code = codeOfLines(source);
  return [
    for (final name in {
      for (final shape in _shapes)
        for (final match in shape.allMatches(code)) match.group(1)!,
    })
      '$path: $name',
  ];
}

/// A mark raised right before the microtask is scheduled — and one read
/// right before it, where a condition that is a mark returns.
final _shapes = [
  RegExp(r'(_\w+) = true;\s*scheduleMicrotask\('),
  RegExp(
    r'if \((\w+)\) \{\s*return;\s*\}\s*(?:\w+ = true;\s*)?'
    r'scheduleMicrotask\(',
  ),
];
