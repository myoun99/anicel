import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★★**UNDO ASKS WHAT IS OPEN BEFORE IT ASKS THE DOCUMENT.**
///
/// 🗣️유저 2026-09-20: 「**변형도구 사용시 변형에 대한 조작마다 언두로 기록**
/// 된단거야 … **확정하면 변형 하나로서의 언두만 작동**」. The polygon trace
/// had the same law first (유저 확정, 2026-08).
///
/// ⛔**THE BEHAVIOUR IS PINNED ELSEWHERE** — `test/ui/canvas/
/// ctrl_z_steps_inside_the_open_box_test.dart` presses the real key and the
/// real rail button on a real box. ⚠️This file is not that pin's
/// understudy: what it holds is the SHAPE, which is a rule about the NEXT
/// channel — and the next DOOR — to be added. The document undo is the
/// fallback, so it has to stay last and each open thing has to decide on its
/// own answer; and every door has to open [HistoryVerbs], or it skips all of
/// that (H42, 2026-09-24: the rail's ↶ ↷ did).
///
/// 🧪Both halves were measured: a mutation that wrote `if (false && …)` into
/// the undo survived the whole suite on 2026-09-22, and the first version
/// of THIS file — which read only the calls' positions — survived it too,
/// because a `false &&` leaves every position where it was.
void main() {
  const verbs = 'lib/src/ui/brush/history_verbs.dart';

  String bodyOf(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: '$signature is where the order lives');
    return source.substring(start, source.indexOf('\n  }\n', start));
  }

  test('undo asks polygon, then transform, then the document', () {
    final undo = bodyOf(File(verbs).readAsStringSync(), 'VoidCallback? _undo()');
    final polygon = undo.indexOf('selection.hasOpenPolygon');
    final transform = undo.indexOf('selection.canUndoTransformStep');
    final document = undo.indexOf('session.canUndo');

    // ⚠️THE QUESTION IS THE WHOLE CONDITION, not a term inside one. ↩️This
    // pin read positions alone and a mutant that wrote `if (false && …)`
    // kept every position it was reading — it survived (2026-09-22).
    for (final question in const ['hasOpenPolygon', 'canUndoTransformStep']) {
      expect(
        undo,
        matches(RegExp('if \\(selection\\.$question\\) \\{')),
        reason: '$question decides on its own answer, ungated',
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
    final redo = bodyOf(File(verbs).readAsStringSync(), 'VoidCallback? _redo()');
    expect(
      redo,
      matches(RegExp(r'if \(selection\.canRedoPolygonPoint\) \{')),
    );
    expect(
      redo.indexOf('canRedoPolygonPoint'),
      lessThan(redo.indexOf('session.canRedo')),
    );
  });

  test('🚨every door opens the verb — nothing else undoes the document', () {
    // H42 (유저 2026-09-24): the rail's ↶ ↷ called the session's undo and
    // redo themselves, and skipped the polygon, the box and F-173 with it.
    final doors = {
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != verbs &&
            _documentHistory.hasMatch(file.readAsStringSync()))
          libPath(file),
    };
    expect(
      doors,
      isEmpty,
      reason: 'a door that reaches the session\'s undo or redo itself skips '
          'what HistoryVerbs asks first — open that verb instead',
    );
  });

  test('the scan sees a planted door, and not the verb\'s own names', () {
    // ⛔A WALL THAT FINDS NOTHING PROVES NOTHING until it has found
    // something.
    expect(_documentHistory.hasMatch('onPressed: session.undo,'), isTrue);
    expect(_documentHistory.hasMatch('_session.redo();'), isTrue);
    expect(_documentHistory.hasMatch('widget.session.undo()'), isTrue);
    expect(_documentHistory.hasMatch('_history.undo();'), isFalse);
    expect(_documentHistory.hasMatch('history.canUndo'), isFalse);
    expect(_documentHistory.hasMatch('session.canUndo'), isFalse);
  });
}

/// A reach for the session's own undo or redo.
final _documentHistory = RegExp(r'\b_?session\.(undo|redo)\b');
