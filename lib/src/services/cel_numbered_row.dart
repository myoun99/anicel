import '../models/canvas_size.dart';
import '../models/cel_number_letters.dart';
import '../models/composite_tree.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';

/// How a row composites, apart from its pixels and where it lies: its
/// strength, its blend and its effect chain.
typedef RowPaint = ({
  double opacity,
  LayerBlendMode blendMode,
  List<ResolvedLayerEffect> effects,
});

/// A row's node in its tree, as its chain [paint] makes it — 🚨THE ONE
/// LOWERING OF A CEL NUMBER (I-65), for every tree that holds rows.
///
/// A chain with no cel number is the row's leaf, painted with [paint]
/// ([rowOf]). A chain that holds one is a GROUP: the row's picture under
/// the links before the number, the number's letters over it
/// ([CompositeCelNumber]), and the links after it on the two as one
/// picture — then the row's strength and blend on that, once. So a blur
/// after the number blurs the letters too, and one before it does not
/// (유저 08-07: 「체인 위치 고정 반대 — 블러 걸고 싶은 상황을 막는 제한」);
/// a second number is a group around the first.
///
/// The letters say [text] ([celNumberText]) and stand where the number's
/// keys put them on [paper] ([effectStandPose]) — unkeyed, where a row
/// stands at rest.
///
/// ⚠️The links after a number apply to their group, in the space a
/// folder's do: on a row that its transform turns or scales, a blur after
/// the number spreads as a folder's blur, not as the row's own.
CompositeNode<P> celNumberedRow<P>({
  required RowPaint paint,
  required P Function(RowPaint paint) rowOf,
  required String text,
  required CanvasSize paper,
}) {
  final effects = paint.effects;
  final numbers = [
    for (var index = 0; index < effects.length; index += 1)
      if (effects[index].kind.drawsItsOwnPicture) index,
  ];
  if (numbers.isEmpty) {
    return CompositeLeaf<P>(rowOf(paint));
  }
  final row = CompositeLeaf<P>(
    rowOf((
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: List.unmodifiable(effects.sublist(0, numbers.first)),
    )),
  );
  CompositeNode<P> node = row;
  for (var each = 0; each < numbers.length; each += 1) {
    final last = each == numbers.length - 1;
    final at = numbers[each];
    node = CompositeGroup<P>(
      children: List.unmodifiable([
        node,
        CompositeCelNumber<P>(
          on: row,
          letters: celNumberLettersOf(effects[at], text: text, paper: paper),
        ),
      ]),
      opacity: last ? paint.opacity : 1,
      blendMode: last ? paint.blendMode : LayerBlendMode.normal,
      effects: List.unmodifiable(
        effects.sublist(at + 1, last ? effects.length : numbers[each + 1]),
      ),
    );
  }
  return node;
}

/// What [number] — a resolved cel number — writes, saying [text]: the
/// letters a row's tree lays, and the ones the canvas's box frames
/// (F-477).
CelNumberLetters celNumberLettersOf(
  ResolvedLayerEffect number, {
  required String text,
  required CanvasSize paper,
}) {
  final stand = effectStandPose(number.stand!, paper);
  return CelNumberLetters(
    text: text,
    color: number.ink!,
    center: stand.center,
    scale: stand.scale,
  );
}
