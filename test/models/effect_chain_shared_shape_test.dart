import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';

/// The 겸용 mirror's merge: an effect chain's SHAPE is shared structure,
/// its NUMBERS are lane content. Copying a chain verbatim into a sibling
/// would wipe that cut's parameter values and keyframes, which is exactly
/// what this function exists to prevent.
void main() {
  final radiusId = effectParametersOf(EffectKind.blur).first.id;
  final brightnessId = effectParametersOf(
    EffectKind.brightnessContrast,
  ).first.id;

  LayerEffect blur(String id, {bool enabled = true, double radius = 0}) =>
      LayerEffect(
        id: EffectId(id),
        kind: EffectKind.blur,
        enabled: enabled,
        parameters: {radiusId: EffectParameter(value: radius)},
      );

  LayerEffect brightness(String id, {double amount = 0}) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.brightnessContrast,
    parameters: {brightnessId: EffectParameter(value: amount)},
  );

  double radiusOf(LayerEffect effect) => effect.parameterOf(radiusId).value;

  test('an effect the sibling already has KEEPS its own numbers', () {
    final merged = effectChainWithSharedShape(
      [blur('e1', radius: 12)],
      onto: [blur('e1', radius: 3)],
    );

    expect(merged, hasLength(1));
    expect(
      radiusOf(merged.single),
      3,
      reason: "the sibling's value survives the mirror",
    );
  });

  test('a NEW effect arrives whole (defaults and all)', () {
    final merged = effectChainWithSharedShape(
      [blur('e1', radius: 3), brightness('e2', amount: 40)],
      onto: [blur('e1', radius: 3)],
    );

    expect(merged.map((effect) => effect.id.value), ['e1', 'e2']);
    expect(merged.last.kind, EffectKind.brightnessContrast);
  });

  test('a REMOVED effect drops out of the sibling too', () {
    final merged = effectChainWithSharedShape(
      [blur('e1', radius: 3)],
      onto: [blur('e1', radius: 3), brightness('e2', amount: 40)],
    );

    expect(merged.map((effect) => effect.id.value), ['e1']);
  });

  test('ORDER follows the shape, not the sibling', () {
    final merged = effectChainWithSharedShape(
      [brightness('e2'), blur('e1', radius: 9)],
      onto: [blur('e1', radius: 3), brightness('e2')],
    );

    expect(merged.map((effect) => effect.id.value), ['e2', 'e1']);
    expect(
      radiusOf(merged.last),
      3,
      reason: 'reordering still keeps the sibling numbers',
    );
  });

  test('ENABLED follows the shape — a switch is structure', () {
    final merged = effectChainWithSharedShape(
      [blur('e1', enabled: false, radius: 12)],
      onto: [blur('e1', radius: 3)],
    );

    expect(merged.single.enabled, isFalse);
    expect(
      radiusOf(merged.single),
      3,
      reason: 'the switch mirrors without dragging the value along',
    );
  });

  test('an empty sibling chain takes the shape verbatim', () {
    final shape = [blur('e1', radius: 12)];

    expect(effectChainWithSharedShape(shape, onto: const []), shape);
  });

  test('a reused id with a DIFFERENT kind takes the incoming effect', () {
    final merged = effectChainWithSharedShape(
      [brightness('e1', amount: 40)],
      onto: [blur('e1', radius: 3)],
    );

    expect(merged.single.kind, EffectKind.brightnessContrast);
  });
}
