import 'cel_bank_lanes.dart' show laneBlockStarts;
import 'conte_group.dart' show cutAcceptsAnotherStoryboardLayer;
import 'cut.dart';
import 'import/cut_folder_edits.dart';
import 'layer.dart';
import 'layer_kind.dart';

/// The kinds a row's TYPE BUTTON turns it between — the picture rows of
/// the action section (🗣️F-613, 유저 2026-11-19: 「레이어영역의 레이어의
/// 아이콘 누르면 변경가능한 대상 뜨고 변경가능하게. 우선 액션란의
/// 이미지-애니메이션-콘티 이 세가지 타입 변경가능하게」).
const layerKindChoices = [
  LayerKind.image,
  LayerKind.animation,
  LayerKind.storyboard,
];

/// Whether [layer]'s type button turns it between [layerKindChoices]: it is
/// one of them, and not an attach row, which wears its base's kind.
bool turnsBetweenKinds(Layer layer) =>
    layerKindChoices.contains(layer.kind) && !isAttachedLayer(layer);

/// Whether [layer], standing in [cut], can turn into [kind] — by the rules
/// the kinds already keep (「규칙은 다른거 참고해서」): a cut's ONE conte
/// ([cutAcceptsAnotherStoryboardLayer]), and an image holding one cel
/// ([CutFolderEdits.holds] — 「셀이 여럿인 곳은 그 차이를 보여 주되 고를
/// 수 없다」). The kind it is now it can always stay.
bool canTurnInto(Layer layer, LayerKind kind, {required Cut cut}) {
  if (!turnsBetweenKinds(layer) || !layerKindChoices.contains(kind)) {
    return false;
  }
  if (kind == layer.kind) {
    return true;
  }
  return switch (kind) {
    LayerKind.storyboard => cutAcceptsAnotherStoryboardLayer(
      cut,
      exceptLayerId: layer.id,
    ),
    LayerKind.image => CutFolderEdits.holds(
      LayerKind.image,
      laneBlockStarts(layer.timeline).length,
    ),
    _ => true,
  };
}
