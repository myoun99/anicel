import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**UNDO ASKS WHAT IS OPEN BEFORE IT ASKS THE DOCUMENT.**
///
/// 🗣️유저 2026-09-20: 「**변형도구 사용시 변형에 대한 조작마다 언두로 기록**
/// 된단거야 … **확정하면 변형 하나로서의 언두만 작동**」. The polygon trace
/// had the same law first (유저 확정, 2026-08).
///
/// ⛔**THE BEHAVIOUR IS PINNED ELSEWHERE** — `test/ui/canvas/
/// ctrl_z_steps_inside_the_open_box_test.dart` presses the real key on a
/// real box. ⚠️This file is not that pin's understudy: what it holds is the
/// SHAPE, which is a rule about the NEXT channel to be added. The document
/// undo is the fallback, so it has to stay last and each open thing has to
/// decide on its own answer — a build that asked the document first, or
/// wrapped one of these calls in a guard, would leave that channel dead.
///
/// 🧪Both halves were measured: a mutation that wrote `if (false && …)` into
/// `home_page.dart` survived the whole suite on 2026-09-22, and the first
/// version of THIS file — which read only the calls' positions — survived it
/// too, because a `false &&` leaves every position where it was.
void main() {
  test('the undo key asks polygon, then transform, then the document', () {
    final source = File('lib/src/ui/home_page.dart').readAsStringSync();
    final polygon = source.indexOf('undoPolygonPoint()');
    final transform = source.indexOf('undoTransformStep()');
    final document = source.indexOf('_session.undo()');

    // ⚠️THE CALL IS THE WHOLE CONDITION, not a term inside one. ↩️This pin
    // read positions alone and a mutant that wrote `if (false && …)` kept
    // every position it was reading — it survived (2026-09-22).
    for (final verb in const ['undoPolygonPoint', 'undoTransformStep']) {
      expect(
        source,
        matches(
          RegExp('if \\(_canvasSelectionCommands\\.$verb\\(\\)\\) \\{'),
        ),
        reason: '$verb decides on its own answer, ungated',
      );
    }
    expect(polygon, isNonNegative, reason: 'the polygon trace is asked');
    expect(transform, isNonNegative, reason: 'the open box is asked');
    expect(document, isNonNegative, reason: 'the document is the fallback');
    expect(
      transform,
      greaterThan(polygon),
      reason: 'the polygon is the newer thing on screen and keeps its place',
    );
    expect(
      document,
      greaterThan(transform),
      reason:
          '⛔the document is LAST. Asked first it would land the session and '
          'undo somebody else\'s edit while the user was still transforming',
    );
  });

  test('redo is the same shape, and says so by asking the trace first', () {
    final source = File('lib/src/ui/home_page.dart').readAsStringSync();
    expect(
      source.indexOf('redoPolygonPoint()'),
      lessThan(source.indexOf('_session.redo()')),
    );
  });
}
