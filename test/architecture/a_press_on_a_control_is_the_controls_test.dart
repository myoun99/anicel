import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A PRESS THAT LANDS ON A CONTROL BELONGS TO THAT CONTROL.**
///
/// 🗣️유저 has said it five times — 2026-08-14 for sliders (「슬라이더위에서
/// 조작하기 시작하면 슬라이더조작하는거고 **그 외가 스크롤인거야**」), 08-28
/// for buttons, 08-29 (「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이
/// 발생하는게 심각한 버그야**」), 08-30 striking down the threshold, and
/// 09-22 on the transform box's own buttons:
///
/// > 「왜 **확정/취소버튼을 클릭하면서 드래그하면 회전이 작동**하지? 버튼에
/// > 오는 동작은 **버튼이 무조건 가져가야하는거아냐**? … **마지막 경고니까
/// > 다신 이딴식으로 하지마. 버튼에 오는 동작은 무조건 버튼꺼야**」
///
/// ⛔**THE LAW EXISTED AND THE SURFACE SIMPLY DID NOT ASK.** That is the
/// shape this file exists to make impossible: `control_press_claim` has
/// been the keeper since August, the buttons wore it, and the canvas
/// started a rotation anyway because nothing checked. A behaviour pin
/// covers the buttons that were reported; this covers the SURFACES, so the
/// next control to float over one of them is already safe.
void main() {
  /// Every surface that starts a VERB of its own from the raw pointer
  /// stream, and how it stands down for a control.
  ///
  /// ⚠️A LEDGER, not an allowlist: each entry names a file that must ask,
  /// and a new drag surface earns a line here by asking too. Controls are
  /// not in it — they CLAIM rather than ask, which is the other half of
  /// the same law and lives in `control_press_claim`.
  const mustAsk = <String, String>{
    'lib/src/ui/canvas/canvas_selection_layer.dart':
        'the marquee, the transform box and its handles — and the '
        '확정/취소 buttons float inside its own Listener',
    'lib/src/ui/brush/canvas_panel/canvas_panel_tap.dart':
        'the tool tap and the stamp drag: the other half of the canvas',
    'lib/src/ui/canvas/canvas_viewport_gesture_layer.dart':
        'pan / zoom / rotate of the view itself',
    'lib/src/ui/input/eager_pan_gesture_recognizer.dart':
        'the rails\' column drag, which every row recogniser goes through',
    'lib/src/ui/timeline/rail_column_swipe.dart':
        'the swipe column, which mounts the STRONG claim over the weak one',
    'lib/src/ui/widgets/instant_tap_region.dart':
        'dismiss-on-outside-press: a press on a control is not "outside"',
  };

  test('every drag surface asks whether a control took the press', () {
    final silent = <String>[];
    for (final entry in mustAsk.entries) {
      final source = File(entry.key).readAsStringSync();
      if (!source.contains('controlOwnsTap')) {
        silent.add('${entry.key} — ${entry.value}');
      }
    }
    expect(
      silent,
      isEmpty,
      reason:
          '⛔These start a drag without asking whose press it is:\n'
          '${silent.join('\n')}\n'
          'Add `if (controlOwnsTap(event.pointer)) return;` at the top of '
          'the pointer-down. 유저: 「버튼에 오는 동작은 무조건 버튼꺼야」.',
    );
  });

  test('⛔and the ledger still points at files that exist', () {
    final gone = mustAsk.keys.where((p) => !File(p).existsSync()).toList();
    expect(
      gone,
      isEmpty,
      reason:
          '⛔A ledger entry for a file nobody has is a rule nobody keeps — '
          'if a surface moved, move its line; if it went, delete it.',
    );
  });
}
