import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';

/// **R27 #16 — the direction row is a row you can draw on.**
///
/// 유저 확정 2026-08-25: 「일단 유효야. **카메라랑 트랜지션은 지금처럼
/// 못그리는데 디렉션레이어는 그림 그릴수있는 행으로**」.
///
/// 🚨The change that made it possible is a SPLIT, not a flag: "carries
/// instructions" had been answering two questions at once — *does this row
/// draw span overlays* and *does this row have a timeline of its own* — and
/// they had never disagreed because nothing was ever both. A direction row
/// is both now.
void main() {
  test('a direction row draws, and carries its instructions too', () {
    expect(layerKindIsDrawingCel(LayerKind.instruction), isTrue);
    expect(layerKindAcceptsBrushInput(LayerKind.instruction), isTrue);
    expect(
      layerKindCarriesInstructions(LayerKind.instruction),
      isTrue,
      reason: 'the spans are what the row is FOR — they did not go away',
    );
    expect(
      layerKindBandIsInstructionsOnly(LayerKind.instruction),
      isFalse,
      reason: 'its band is its own timeline now, with the spans over it',
    );
  });

  test('⛔and the camera and transition rows are untouched', () {
    for (final kind in [LayerKind.camera, LayerKind.transition]) {
      expect(layerKindIsDrawingCel(kind), isFalse, reason: '$kind');
      expect(layerKindAcceptsBrushInput(kind), isFalse, reason: '$kind');
    }
    expect(
      layerKindBandIsInstructionsOnly(LayerKind.transition),
      isTrue,
      reason: 'the transition row is instructions-only and stays so — its '
          'placement in a cut is a projection, not a drawing',
    );
  });

  test('the band predicate answers for every kind, once', () {
    for (final kind in LayerKind.values) {
      expect(
        layerKindBandIsInstructionsOnly(kind),
        layerKindCarriesInstructions(kind) && !layerKindIsDrawingCel(kind),
        reason: '$kind — one derivation, so the two halves cannot drift',
      );
      if (layerKindBandIsInstructionsOnly(kind)) {
        expect(
          layerKindAcceptsBrushInput(kind),
          isFalse,
          reason: '$kind has no timeline to draw into',
        );
      }
    }
  });
}
