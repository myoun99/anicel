import 'package:flutter_test/flutter_test.dart';

import '../../helpers/library_source.dart';

/// 🚨★★★**A MOVE SESSION HAS ONE OWNER, AND ONE DOOR OUT.**
///
/// 🗣️유저 2026-09-18 (F-164): 「절대로 낡지않을 구조로 튼튼하게해줘. 지금
/// 1차로 만든게 이렇게 된거보면 알잖아」.
///
/// The session lives in TWO objects and always will: the LAYER holds the
/// float and what the user has done to it, the HOST holds the hole the
/// origin cel is drawn through (`CanvasPanelLift`). Nothing can merge
/// those — one is a widget's interaction state, the other is what a
/// painter reads. What CAN be made impossible is the layer letting go
/// without the host hearing, and that is what this file holds.
///
/// 🔬**The measurement that made it a law.** Before F-164 the layer kept
/// FOUR fields and spelled the ending in FOUR places, and they did not
/// agree: one of them cleared three of the four and told the host nothing
/// at all. The cel it came from then kept drawing its hole for the rest of
/// the run — 「돌아가면 그림사라져있는데 … 새로 선을 그어도 긋고나서 커밋하면
/// 사라짐」.
///
/// ⛔A behaviour test cannot hold this. The failure is a session nobody
/// ends, which looks like nothing until a frame is revisited, so what the
/// pins can prove is that the app still works — not that the next edit
/// cannot break it the same way. This reads the source.
void main() {
  final layer = librarySource('lib/src/ui/canvas/canvas_selection_layer.dart');

  test('⛔a session is CLEARED in exactly one place', () {
    expect(
      '_session = null'.allMatches(layer).length,
      1,
      reason:
          '🚨every extra one is a way to forget a session quietly, which is '
          'what F-164 was. The one that stands is inside `_endSession`, and '
          'that is the method that tells the host',
    );
  });

  test('⛔a session is MADE in exactly one place', () {
    expect(
      '_session = _MoveSession('.allMatches(layer).length,
      1,
      reason: 'a session is made whole or not at all',
    );
  });

  test('⛔only `_endSession` speaks to the host about a session ending', () {
    // The host learns of an ending through exactly these three callbacks.
    // Every call to one of them must sit inside `_endSession`, which is the
    // only method that also drops the field.
    final ender = _methodBody(layer, '_MoveSession? _endSession(');
    expect(ender, isNotNull, reason: '⛔fixture premise: the one door exists');
    for (final call in const [
      'widget.onLiftConfirmed',
      'widget.onLiftReverted',
    ]) {
      expect(
        call.allMatches(layer).length,
        call.allMatches(ender!).length,
        reason:
            '⛔$call is called outside `_endSession`. Whatever that caller '
            'is doing, the field and the host would then be two facts again',
      );
    }
  });

  test('⛔the field itself carries the law, for whoever reads it next', () {
    expect(
      layer,
      contains('THE SESSION IS ONE VALUE'),
      reason:
          '🚨유저: the reason a decision was made lives beside the '
          'declaration, never only in a commit message',
    );
  });
}

/// The body of the method whose signature starts with [signature], by brace
/// depth — good enough for one method in one file, and it fails loudly by
/// answering null rather than a wrong span.
String? _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) {
    return null;
  }
  final open = source.indexOf('{', start);
  if (open < 0) {
    return null;
  }
  var depth = 0;
  for (var i = open; i < source.length; i += 1) {
    if (source[i] == '{') {
      depth += 1;
    } else if (source[i] == '}') {
      depth -= 1;
      if (depth == 0) {
        return source.substring(open, i + 1);
      }
    }
  }
  return null;
}
