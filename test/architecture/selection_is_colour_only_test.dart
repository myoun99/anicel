import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★유저 규칙: **선택 표시는 색상만.**
///
/// A selected row, chip, tab or key says so by COLOUR. Anything else the
/// selection changes — a border that thickens, a label that bolds, a shape
/// that swells — moves the layout under the user's hand and makes two
/// controls that are the same size stop being the same size.
///
/// ⛔THIS IS A CENSUS, NOT A WALL (the pattern `layer_image_draw_contract`
/// and `app_shapes_coverage` set). The sites standing when the gate landed
/// stay; the number may only go DOWN. A NEW one has to argue itself into
/// the number in the same commit — which is the whole point, because every
/// one of these arrived as "just a hairline" and nobody was asked.
///
/// ⚠️It reads COLOUR-ONLY as the rule, so a selection-conditional `color`
/// is never counted. What it counts is a selection flag deciding a
/// non-colour property on the same line.
void main() {
  test('selection changes colour, and the non-colour sites do not grow', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'\b(width|height|fontWeight|elevation|borderRadius|shape|thickness'
      r'|letterSpacing|padding|size|blurRadius|spreadRadius|strokeWidth)'
      r':[^,]*\b(selected|isSelected|isActive)\b *\?',
    );

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (pattern.hasMatch(line)) {
          offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }
    }

    expect(
      offenders.length,
      lessThanOrEqualTo(_knownNonColourSelection),
      reason:
          'A selection now changes something that is not a colour. The rule '
          'is colour only: a border that thickens or a label that bolds '
          'moves the layout under the hand and makes two controls that were '
          'the same size stop being it. If this site is genuinely an '
          'exception, say why and raise _knownNonColourSelection in the '
          'same commit.\n${offenders.join('\n')}',
    );
    expect(
      offenders.length,
      greaterThanOrEqualTo(_knownNonColourSelection),
      reason:
          'One went away — lower _knownNonColourSelection to '
          '${offenders.length} so the census keeps its grip.',
    );
  });
}

/// The sites standing when this gate landed (2026-09-04), all of them a
/// border that thickens or a label that bolds on selection:
///
///  * `brush_preset_panel` ×2 and `brush_tip_picker` — a preset/tip tile's
///    outline goes 1 → 1.5.
///  * `text_cel_dialog` — a font tile's outline goes 1 → 2.
///  * `timeline_lane_rows` — a lane KEY's outline, and the comment two
///    lines above it already says "color only (the selection rule)".
///  * `app_window` — a window TAB's label goes w400 → w500.
///
/// ⛔NOT FIXED HERE ON PURPOSE. Which of these the user wants flattened is
/// a look decision, and the audit's job was to make them countable so the
/// question can be asked once instead of drifting.
const int _knownNonColourSelection = 6;
