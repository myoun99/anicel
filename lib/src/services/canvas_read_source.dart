import '../models/cut.dart';
import '../models/layer_id.dart';

/// WHAT A TOOL THAT READS THE PICTURE READS — one question, asked by the
/// eyedropper (R28 #6: Photoshop's "current layer / all layers", Clip
/// Studio's 参照元) and by the fill (I-36), so one type and one answer
/// ([layersReadBy]).
///
/// 🗣️유저 2026-09-24 (I-36-Q1): 「모드 세개. 참조(보이는거 전부), 참조(참조
/// 설정한 레이어만, 없으면 현재), 현재레이어. 이 과정에서 법 다른거 통일」.
/// ↩️The middle one went with I-92 (유저 2026-10-12: 「채우기도구에서
/// 채색참조 기반으로 채우기 이런식으로 구현되있는데, 그런버튼 삭제하고」):
/// the rail's flag it read is the layer's CLIPPING now
/// ([Layer.clipsToBelow]), so both tools offer the same two.
enum CanvasReadSource {
  /// Every visible layer — what you SEE. Both tools start here.
  display,

  /// The ACTIVE layer alone.
  layer,
}

/// The layers [source] reads — null for every visible layer.
///
/// What a layer then gives is the frame's business: a hidden layer, or one
/// with nothing exposed at the playhead, reads as nothing.
Set<LayerId>? layersReadBy(
  CanvasReadSource source,
  LayerId? activeLayerId,
) => switch (source) {
  CanvasReadSource.display => null,
  CanvasReadSource.layer => {?activeLayerId},
};

/// [layersReadBy] as the names the tool settings show, in the cut's stack
/// order — null for every visible layer, empty when there is no cut.
List<String>? layerNamesReadBy(
  CanvasReadSource source,
  Cut? cut,
  LayerId? activeLayerId,
) {
  if (cut == null) {
    return const [];
  }
  final read = layersReadBy(source, activeLayerId);
  if (read == null) {
    return null;
  }
  return [
    for (final layer in cut.layers)
      if (read.contains(layer.id)) layer.name,
  ];
}
