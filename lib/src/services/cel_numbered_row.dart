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

/// A row's nodes in its tree, bottom to top, as its chain [paint] makes
/// them — 🚨THE ONE LOWERING OF A CEL NUMBER (I-65), for every tree that
/// holds rows.
///
/// A chain with no cel number is the row's leaf, painted with [paint]
/// ([rowOf]). A chain that holds one is the row's picture under the links
/// before the number and the number's letters over it
/// ([CompositeCelNumber]), the links after it on the two as one picture —
/// then the row's strength and blend on that, once. So a blur after the
/// number blurs the letters too, and one before it does not (유저 08-07:
/// 「체인 위치 고정 반대 — 블러 걸고 싶은 상황을 막는 제한」); a second
/// number is written over the first.
///
/// 🚨ONE PICTURE ONLY WHERE THE TWO DO NOT DISTRIBUTE — the folder's law
/// (`folderNeedsCompositeBuffer`): a GROUP for links after the number, a
/// strength below 1 or a blend other than normal, and for a row that clips
/// or is clipped to ([asOnePicture] — cut or cutting as one picture,
/// I-92); otherwise the letters lie over the row in their place, which is
/// the same picture. ↩️Always a group until 10-27: a stroke's every step
/// rasterised each numbered row's group again — 🔬beside 8 numbered rows,
/// a step reached the screen at p50 18.6ms against 6.8 with the numbers
/// off, and 5.8 with the groups in place (card
/// paint-walk-redoes-the-same-work-each-step, Windows, profile).
///
/// The letters say [text] ([celNumberText]) and stand where the number's
/// keys put them on [paper] ([effectStandPose]) — unkeyed, where a row
/// stands at rest.
///
/// ⚠️The links after a number apply to their group, in the space a
/// folder's do: on a row that its transform turns or scales, a blur after
/// the number spreads as a folder's blur, not as the row's own.
List<CompositeNode<P>> celNumberedRow<P>({
  required RowPaint paint,
  required P Function(RowPaint paint) rowOf,
  required String text,
  required CanvasSize paper,
  required bool asOnePicture,
}) {
  final effects = paint.effects;
  final numbers = [
    for (var index = 0; index < effects.length; index += 1)
      if (effects[index].kind.drawsItsOwnPicture) index,
  ];
  if (numbers.isEmpty) {
    return [CompositeLeaf<P>(rowOf(paint))];
  }
  final row = CompositeLeaf<P>(
    rowOf((
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: List.unmodifiable(effects.sublist(0, numbers.first)),
    )),
  );
  var nodes = <CompositeNode<P>>[row];
  for (var each = 0; each < numbers.length; each += 1) {
    final last = each == numbers.length - 1;
    final at = numbers[each];
    final opacity = last ? paint.opacity : 1.0;
    final blendMode = last ? paint.blendMode : LayerBlendMode.normal;
    final after = List<ResolvedLayerEffect>.unmodifiable(
      effects.sublist(at + 1, last ? effects.length : numbers[each + 1]),
    );
    nodes = [
      ...nodes,
      CompositeCelNumber<P>(
        on: row,
        letters: celNumberLettersOf(effects[at], text: text, paper: paper),
      ),
    ];
    if (after.isNotEmpty ||
        opacity < 1 ||
        blendMode != LayerBlendMode.normal ||
        (last && asOnePicture)) {
      nodes = [
        CompositeGroup<P>(
          children: List.unmodifiable(nodes),
          opacity: opacity,
          blendMode: blendMode,
          effects: after,
        ),
      ];
    }
  }
  return List.unmodifiable(nodes);
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
