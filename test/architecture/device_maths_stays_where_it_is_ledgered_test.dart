import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨A SINE, A COSINE, AN EXPONENTIAL — ANY CALL THE DEVICE'S MATHS LIBRARY
/// ROUNDS — IS `alike_maths.dart`'S WHERE WHAT IT WORKS OUT IS KEPT OR
/// HANDED THE ENGINE.
///
/// 🗣️gpu-same-formula (유저 2026-11-05) · native-to-rust-Q14 (2026-11-07):
/// the same on every device. `dart:math`'s sin, cos, tan, exp, log, pow
/// and arcs are the device's libm's, which IEEE does not hold to its last
/// bit: Linux's handed the engine other bits than Windows's (board
/// `linux-libm-hands-the-engine-other-last-bits`, 2026-11-17).
///
/// ⛔SO THIS SCANS THE SOURCE: every test runs on one device, where the
/// device's call and the alike one agree to within an ulp. Each file that
/// still calls the device's is ledgered with how often and why — what it
/// works out from a hand, draws on the screen only, or is NOT YET ALIKE and
/// on that card's list. A new call anywhere else fails.
void main() {
  test('no file calls the device\'s maths but those the ledger names, as '
      'often as it says — and each it names still does', () {
    final found = <String, List<int>>{};
    for (final file in dartFilesUnder('lib')) {
      final calls = _deviceMathsCalls(file.readAsStringSync());
      if (calls.isNotEmpty) {
        found[libPath(file)] = calls;
      }
    }
    expectCountsMatchLedger(
      {for (final MapEntry(:key, :value) in found.entries) key: value.length},
      {
        for (final MapEntry(:key, value: (count, _))
            in _callsTheDevices.entries)
          key: count,
      },
      grew:
          'call `alikeSin`, `alikeCos` or `alikeExp` (lib/src/core/'
          'alike_maths.dart) — the device\'s rounds its last bit its own '
          'way. Where the device\'s IS meant (a hand, the screen), the file '
          'goes in the ledger, with why',
      paidOff: 'these call it so no more — take them off the list',
      hits: found,
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy({
      for (final MapEntry(:key, value: (_, why)) in _callsTheDevices.entries)
        key: why,
    });
  });

  test('the scan counts a call where it is one — not a comment that names '
      'it, the square root IEEE rounds, or a constant', () {
    const planted = '''
/// Was math.sin(turn).
final x = math.cos(turn) * math.pi; // math.exp(x)
final y = math.sqrt(x) + math.ln2;
final z = math.pow(x, 2) + math.atan2(y, x);
''';
    expect(_deviceMathsCalls(planted), [2, 4, 4]);
  });
}

/// From where a hand went: the device's own, which no two devices repeat.
const _aHand =
    'works a value out from where a hand went — a pointer, a pen\'s tilt, '
    'a wheel — which no two devices repeat; what is kept is the value';

/// Drawn on the screen only.
const _theScreen =
    'draws on the screen only — a control, an overlay, a cursor, a '
    'preview; nothing it works out is saved or laid by an export';

/// Debt: on the card's list.
const _notYetAlike =
    'NOT YET ALIKE — shapes what a stroke, a tip, a guide, a selection, a '
    'mark or an import lays and keeps, so a last bit may part two devices: '
    'on board linux-libm-hands-the-engine-other-last-bits\'s list';

/// Who calls the device's maths, how often, and why.
const _callsTheDevices = <String, (int, String)>{
  'lib/src/models/brush_tip_mask.dart': (2, _notYetAlike),
  'lib/src/models/camera_work_marks.dart': (5, _notYetAlike),
  'lib/src/models/cut_content_translation.dart': (1, _notYetAlike),
  'lib/src/models/drawing_guide.dart': (3, _notYetAlike),
  'lib/src/services/brush_dab_dirty_region.dart': (2, _notYetAlike),
  'lib/src/services/brush_dab_share.dart': (1, _notYetAlike),
  'lib/src/services/brush_stroke_dynamics.dart': (5, _notYetAlike),
  'lib/src/services/brush_tip_mask_defaults.dart': (14, _notYetAlike),
  'lib/src/services/brush_tip_stamp_cache.dart': (2, _notYetAlike),
  'lib/src/services/canvas_selection_shape.dart': (3, _notYetAlike),
  'lib/src/services/cel_text_frame.dart': (1, _notYetAlike),
  'lib/src/services/directional_blur_passes.dart': (
    8,
    'whole numbers to whole powers — Dart\'s int pow, exact on every '
        'device (the taps of a line blur\'s passes)',
  ),
  'lib/src/services/guide_geometry.dart': (9, _notYetAlike),
  'lib/src/services/import/clip_lettering.dart': (3, _notYetAlike),
  'lib/src/services/import/clip_placement.dart': (4, _notYetAlike),
  'lib/src/services/input/pen_lean.dart': (4, _aHand),
  'lib/src/services/playback/present_slot.dart': (
    1,
    'weighs the frame times THIS device measured, the newest most — its '
        'own, which no other device repeats or reads',
  ),
  'lib/src/services/round_tip_profile.dart': (1, _notYetAlike),
  'lib/src/services/shape_ratio_lock.dart': (1, _aHand),
  'lib/src/services/stroke_corners.dart': (1, _notYetAlike),
  'lib/src/services/stroke_post_correction.dart': (2, _notYetAlike),
  'lib/src/services/stroke_stabilizer.dart': (4, _notYetAlike),
  'lib/src/services/transform_box_law.dart': (1, _aHand),
  'lib/src/services/viewport_transform_matrix.dart': (
    1,
    'reads the view\'s turn back off its matrix — how the canvas is seen, '
        'not what it holds or an export lays',
  ),
  'lib/src/ui/brush/brush_cursor_geometry.dart': (1, _theScreen),
  'lib/src/ui/brush/brush_stroke_preview_cache.dart': (3, _theScreen),
  'lib/src/ui/canvas/canvas_viewport_gesture_layer.dart': (2, _aHand),
  'lib/src/ui/canvas/guide_overlay.dart': (9, _theScreen),
  'lib/src/ui/color/color_wheel_panel.dart': (5, _aHand),
  'lib/src/ui/editor_canvas_area.dart': (1, _aHand),
  'lib/src/ui/panels/panel_flash.dart': (1, _theScreen),
  'lib/src/ui/session/editor_voice_recording.dart': (
    2,
    'a cue beep played out of the speaker — never mixed, recorded or '
        'saved',
  ),
  'lib/src/ui/timeline/se_crossing_mark_painter.dart': (1, _theScreen),
  'lib/src/ui/widgets/angle_dial.dart': (2, _theScreen),
  'lib/src/ui/widgets/field_slider.dart': (4, _aHand),
  'lib/src/ui/widgets/tip_direction_popup.dart': (2, _theScreen),
};

/// The lines of [source] that call one of `dart:math`'s rounded-by-device
/// functions, once a call: not one a comment names.
List<int> _deviceMathsCalls(String source) {
  final call = RegExp(
    r'\bmath\.(sin|cos|tan|exp|log|pow|atan2|atan|acos|asin)\(',
  );
  final code = codeOfLines(source.replaceAll('\r\n', '\n'));
  return [
    for (final (index, line) in code.split('\n').indexed)
      for (final _ in call.allMatches(line)) index + 1,
  ];
}
