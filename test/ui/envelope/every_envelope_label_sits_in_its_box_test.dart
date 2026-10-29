import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_painter.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;

import '../../helpers/app_faces.dart';

/// 🗣️F-498 (유저 2026-10-29): 「디지털 컷봉투, 헤더의 공정이름이 칸에서
/// 삐져나와있음. 안삐져나오도록」 — every printed label of every bundled
/// form lies inside its own box, measured the way the painter sets it
/// ([envelopeLine] in [envelopeWordsStyle], at [envelopeLineSlot]) in the
/// faces the app prints in.
///
/// ↩️The digital form's check heads were 10 tall: a 9.5 label hung from a
/// 3 inset ran 13 down, past the stamp row's top rule.
void main() {
  testWidgets('every bundled form prints each label inside its box', (
    tester,
  ) async {
    await loadTheAppFaces();
    const face = TextStyle(
      fontFamily: AppTypography.bundledFamily,
      fontFamilyFallback: AppTypography.bundledFallback,
    );

    final spills = <String>[];
    for (final form in CutEnvelopePresets.all) {
      final layout = CutEnvelopeLayout.fit(
        form: form,
        paperWidth: 660,
        paperHeight: 660 / form.aspectRatio,
      );
      for (final placed in layout.placedBoxes) {
        final label = placed.box.label;
        if (label == null || label.isEmpty) {
          continue;
        }
        final line = envelopeLine(
          label,
          envelopeWordsStyle(
            face,
            layout,
            size: placed.box.labelSize,
            color: envelopeValueInk,
          ),
          layout,
          placed,
        );
        final slot = envelopeLineSlot(
          layout,
          placed,
          line.height,
          align: placed.box.labelAlign,
          top: true,
        );
        final bottom = placed.y + placed.height;
        if (slot.bottom > bottom) {
          spills.add(
            '${form.id} ${placed.box.id} 「$label」: the line ends at '
            '${slot.bottom.toStringAsFixed(1)}, the box at '
            '${bottom.toStringAsFixed(1)}',
          );
        }
        line.dispose();
      }
    }

    expect(spills, isEmpty);
  });
}
