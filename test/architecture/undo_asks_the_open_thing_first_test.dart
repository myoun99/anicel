import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**UNDO ASKS WHAT IS OPEN BEFORE IT ASKS THE DOCUMENT.**
///
/// 🗣️유저 2026-09-20: 「**변형도구 사용시 변형에 대한 조작마다 언두로 기록**
/// 된단거야 … **확정하면 변형 하나로서의 언두만 작동**」. The polygon trace
/// had the same law first (유저 확정, 2026-08).
///
/// ⛔**SO THIS SCANS SOURCE, and the reason is measured.** The channel's own
/// pins call `undoTransformStep()` themselves, so a build where the SHORTCUT
/// never asked it passes every one of them — a mutation that deleted the
/// call from `home_page.dart` survived the whole suite on 2026-09-22. The
/// behaviour version of this pin needs a HomePage with ink on the cel, which
/// this fixture cannot make without a project to load.
///
/// ⚠️What it pins is ORDER, not presence: the document undo is the fallback,
/// so it has to come last or the open thing never gets asked at all.
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
