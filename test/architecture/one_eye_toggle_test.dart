import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★★THE EYE IS ONE WIDGET.
///
/// 유저 (F-58): 「비지블off시 **비지블버튼 자체를 비활성화색(어둡게)** 하란
/// 거였음. 그러니 작업하고, 추가적으로 **비지블버튼은 다른곳에서도 쓰니까
/// 공용화/통일화**시켜서 결과적으로 **다른곳도 비활성화시 비활성화색 되도록**」.
///
/// ⛔SO THIS SCANS SOURCE. 「다른곳도」 is the whole request, and a behaviour
/// test cannot deliver it: two copies that agree today both pass, and the
/// copy this round deleted had already drifted — it dimmed its OFF state in
/// a colour of its own while the five rails dimmed in none.
///
/// ⚠️The ledger below is the point of the test. Every entry names a file
/// that may say `Icons.visibility` and WHY; a new one has to earn a line.
void main() {
  /// 🚨THE LEDGER. Measured 2026-09-01: four files named the glyph and
  /// exactly one of them was a second eye.
  const allowed = <String, String>{
    'lib/src/ui/timeline/layer_label_controls.dart':
        'THE eye — LayerVisibilityToggleButton, and the only toggle',
    'lib/src/ui/timeline/instruction_icon_palette.dart':
        'fade-in / fade-out INSTRUCTION glyphs: a picture of an effect, '
        'nothing toggles',
    'lib/src/ui/timeline/timeline_layer_controls_header.dart':
        '모두 보이기/숨기기 flyout entries and the legend column glyph — menu '
        'items and a heading, not a control with an on state',
  };

  test('only the ledger names the eye glyph', () {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.readAsStringSync().contains('Icons.visibility')) {
        hits.add(libPath(file));
      }
    }
    hits.sort();
    expect(
      hits,
      allowed.keys.toList()..sort(),
      reason:
          'a file that draws the eye itself is a second eye. Use '
          '`LayerVisibilityToggleButton`, or add a line here saying why '
          'this one is not a toggle',
    );
  });

  test('the ledger is not empty of reasons', () {
    // ★A ledger whose entries say nothing is a list of exceptions, which is
    // the thing this file exists to prevent.
    for (final entry in allowed.entries) {
      expect(
        entry.value.length,
        greaterThan(20),
        reason: '${entry.key} needs a reason, not a slot',
      );
    }
  });
}
