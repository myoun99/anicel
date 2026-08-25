import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-15 — **a frame drag that reaches past the edge scrolls, like the ruler.**
///
/// 유저 2026-08-24: 「프레임 엣지나 +버튼으로 드래그하면서 잡아끌때, 룰러랑
/// 동일로직으로 보이는영역 넘어가면 스크롤하는거? 따라가는거 적용」.
///
/// `edgeAutoPanApply` is the shared apply (D42) the ruler scrub, the layer-row
/// drag and the range gesture already went through; the comma grips and the
/// run `[+]` did not, so a drag that left the viewport simply stopped.
///
/// ⚠️A SOURCE scan, deliberately. The behaviour needs a scrolled viewport, a
/// pointer past its edge and a scroll position to read back — and the thing
/// that was missing was never the maths (`edge_auto_pan_test` covers that) but
/// the WIRING, in a file no auto-pan test opened. That is the same shape as
/// `every_row_joins_a_selection_test`'s wiring group, and for the same reason.
void main() {
  String source(String path) => File(path).readAsStringSync();

  /// Every drag that moves along the FRAME axis while the user holds the
  /// pointer. Each must reach the shared apply AND fold the result back into
  /// its own travel — the helper's own warning: "content moving under a
  /// stationary pointer is the same thing as the pointer moving over
  /// stationary content".
  const dragFiles = <String, String>{
    'lib/src/ui/timeline/timeline_row_edit_chrome.dart':
        'the comma grips and the run [+] — F-15',
    'lib/src/ui/timeline/layer_row_drag.dart': 'the rail row drag (D42)',
    'lib/src/ui/timeline/timeline_frame_range_gesture.dart':
        'the range select/move gesture (D42)',
  };

  for (final entry in dragFiles.entries) {
    test('${entry.key} reaches the shared edge pan — ${entry.value}', () {
      expect(
        source(entry.key),
        contains('edgeAutoPanApply'),
        reason: 'a drag that stops at the viewport edge is the report',
      );
    });
  }

  test('the edit chrome folds the pan into BOTH of its drags', () {
    final text = source('lib/src/ui/timeline/timeline_row_edit_chrome.dart');
    // The grip drag adds it to the scalar travel; the [+] adds it to the
    // offset. Two call sites, because they are two drags.
    expect(
      RegExp(r'_autoPanEdge\(details\.globalPosition\)')
          .allMatches(text)
          .length,
      2,
      reason: 'the comma grip and the run [+] each pull the pointer, so each '
          'has to fold the scroll back into its own accumulated travel — a '
          'drag that scrolls but does not count the scroll freezes the '
          'moment the view starts moving',
    );
  });
}
