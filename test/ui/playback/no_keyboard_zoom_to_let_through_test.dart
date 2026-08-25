import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';

/// R6q3 — **the keyboard has no zoom to let through.**
///
/// 유저 2026-08-25, 답 2번: 「키보드 줌도 통과시킨다. 재생 중 줌은 입력 수단과
/// 무관하게 한 법으로」.
///
/// The question assumed a split that does not exist. `PlaybackActuationGate`'s
/// doc claimed 「bound zoom keys included」 in its stop law, and that sentence
/// is the whole of the evidence for one: nothing in [editorActionDefinitions]
/// zooms the viewport, and nothing in the canvas reads a key for it. Zoom is
/// the wheel, the pinch, the bar buttons and the panbars — all POINTER, all of
/// them already through the D13 hole.
///
/// ⇒ There is nothing to fix and something to PIN: the day a zoom key is
/// bound, this test goes red and whoever binds it reads the answer above and
/// puts the pass-through in the gate rather than inside the zoom action.
void main() {
  test('no registry action zooms the viewport', () {
    final zoomish = [
      for (final definition in editorActionDefinitions)
        if (definition.id.contains('zoom') ||
            definition.label.toLowerCase().contains('zoom'))
          definition.id,
    ];

    expect(
      zoomish,
      isEmpty,
      reason: 'R6q3 answered "keyboard zoom passes during playback". If this '
          'is red, that answer now has a subject: let it through in '
          'PlaybackActuationGate._onKey and in the funnel\'s '
          '_consumedByPlayback — the two places the POINTER hole already '
          'lives — and never as a playback check inside the zoom action',
    );
  });

  test('and the gate no longer claims otherwise', () {
    final gate = File(
      'lib/src/ui/playback/playback_actuation_gate.dart',
    ).readAsStringSync();

    expect(
      gate,
      isNot(contains('bound zoom keys included')),
      reason: 'that clause is what made the split look real — this repo does '
          'not delete a decision comment, it corrects a wrong one',
    );
    expect(
      gate,
      contains('R6q3'),
      reason: 'and the correction says which question it answers',
    );
  });
}
