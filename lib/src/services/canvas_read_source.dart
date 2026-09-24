import '../models/cut.dart';
import '../models/layer_id.dart';

/// WHAT A TOOL THAT READS THE PICTURE READS — one question, asked by the
/// eyedropper (R28 #6: Photoshop's "current layer / all layers", Clip
/// Studio's 参照元) and by the fill (I-36), so one type and one answer
/// ([layersReadBy]).
///
/// 🗣️유저 2026-09-24 (I-36-Q1): 「모드 세개. 참조(보이는거 전부), 참조(참조
/// 설정한 레이어만, 없으면 현재), 현재레이어. 이 과정에서 법 다른거 통일」.
/// The eyedropper keeps the two it offered; the fill offers all three.
enum CanvasReadSource {
  /// Every visible layer — what you SEE. Both tools start here.
  display,

  /// The layers carrying the fill-reference flag (the rail's bucket); the
  /// ACTIVE layer when no layer of the cut carries it.
  references,

  /// The ACTIVE layer alone.
  layer,
}

/// The layers [source] reads in [cut] — null for every visible layer.
///
/// What a layer then gives is the frame's business: a hidden layer, or one
/// with nothing exposed at the playhead, reads as nothing.
///
/// ⚠️「없으면 현재」 asks about the FLAG, not about what a frame exposes. A
/// flagged line-art layer with no drawing at this frame is still the
/// reference — the fill reads nothing from it there, rather than quietly
/// switching to the current layer from one frame to the next.
///
/// ⛔Before I-36 the fill answered 「flagged, else EVERY visible layer」 on
/// its own (R20-C2). That fallback is gone: the user's modes put 「every
/// visible layer」 on its own button and send an empty flag to the current
/// layer.
Set<LayerId>? layersReadBy(
  CanvasReadSource source,
  Cut cut,
  LayerId? activeLayerId,
) {
  final active = {?activeLayerId};
  return switch (source) {
    CanvasReadSource.display => null,
    CanvasReadSource.layer => active,
    CanvasReadSource.references => _flagged(cut) ?? active,
  };
}

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
  final read = layersReadBy(source, cut, activeLayerId);
  if (read == null) {
    return null;
  }
  return [
    for (final layer in cut.layers)
      if (read.contains(layer.id)) layer.name,
  ];
}

Set<LayerId>? _flagged(Cut cut) {
  final flagged = {
    for (final layer in cut.layers)
      if (layer.isFillReference) layer.id,
  };
  return flagged.isEmpty ? null : flagged;
}
