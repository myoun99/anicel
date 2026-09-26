import '../../models/cut.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_section_defaults.dart' show firstUnusedLayerName;
import '../../models/timeline_exposure.dart';

LayerId defaultLayerIdForSequence(int sequence) {
  if (sequence < 1) {
    throw ArgumentError.value(
      sequence,
      'sequence',
      'Default layer id sequence must be positive.',
    );
  }
  return LayerId('default-layer-$sequence');
}

String celLayerNameForIndex(int index) {
  if (index < 0) {
    throw ArgumentError.value(
      index,
      'index',
      'Cel layer name index must be non-negative.',
    );
  }

  var value = index;
  var name = '';
  do {
    final letter = String.fromCharCode('A'.codeUnitAt(0) + (value % 26));
    name = letter + name;
    value = (value ~/ 26) - 1;
  } while (value >= 0);

  return name;
}

String nextCelLayerNameForCut(Cut cut) => firstUnusedLayerName(
  cut.layers,
  celLayerNameForIndex,
  // Cels count from A, which is index ZERO — the other rows start at 1.
  firstIndex: 0,
);

/// The name a new IMAGE row takes in [cut]: BG while the cut has none, then
/// BOOK — and BOOK again for every one after, the SAME name stacked.
///
/// 🗣️유저 2026-09-25: 「같은이름쌓기로 가자. 지금처럼 중복허용으로. BG가없으면
/// BG만들고, BG있으면 BOOK으로 쌓도록 … 앞으로 레이어이름BOOK고정에
/// 프레임이름으로 북 구분하게 할거야」. ⛔So no number and no skipping: the
/// books tell themselves apart by their FRAME names (BOOK1, BOOK2), and a
/// cel's A/B/C ([nextCelLayerNameForCut]) is not a picture's name.
String nextImageLayerNameForCut(Cut cut) =>
    cut.layers.any((layer) => layer.name == 'BG') ? 'BOOK' : 'BG';

Layer createDefaultAnimationLayer({
  required LayerId layerId,
  required Cut cut,
}) {
  // A new cel layer is all empty cells ("X" everywhere): emptiness needs no
  // timeline entry in the unified model.
  return Layer(
    id: layerId,
    name: nextCelLayerNameForCut(cut),
    frames: const [],
    timeline: const {},
  );
}

/// A COVERING layer ([LayerKind.coversWithoutGaps]) is born covering its
/// cut — one cell, edge to edge (user's rule 2026-07-27 for storyboard;
/// the image layer speaks the same grammar).
///
/// These rows have no empty cells at all: there is no "X" in their world,
/// so a drawing holds to the end of the cut the way a division does.
/// Starting full is what makes that true from the first instant instead
/// of after the first edit — the cut cannot then shrink past it
/// ([minimumCutDurationFor]), and the coverage rule never meets a hole.
Layer createCoveringLayer({
  required LayerId layerId,
  required FrameId frameId,
  required Cut cut,
  LayerKind kind = LayerKind.storyboard,
}) {
  assert(kind.coversWithoutGaps);
  final cel = coveringCelFor(frameId: frameId, cutDuration: cut.duration);
  return Layer(
    id: layerId,
    // A picture row takes a picture's name, a conte row a cel's. ⛔Not
    // [LayerKind.unnamedCelIsTheLayer]: what a row is CALLED and what its
    // unnamed cel IS are two questions, whatever answers them alike today.
    name: kind == LayerKind.image
        ? nextImageLayerNameForCut(cut)
        : nextCelLayerNameForCut(cut),
    kind: kind,
    frames: [cel.frame],
    timeline: cel.timeline,
  );
}

/// The one cel a COVERING row is born with over a cut of [cutDuration]
/// frames, and its exposure edge to edge — what [createCoveringLayer] makes
/// a row of, and what a 겸용 cut's conte row is born with (F-99).
({Frame frame, Map<int, TimelineExposure> timeline}) coveringCelFor({
  required FrameId frameId,
  required int cutDuration,
}) {
  final duration = cutDuration < 1 ? 1 : cutDuration;
  return (
    frame: Frame(id: frameId, duration: duration, strokes: const []),
    timeline: {0: TimelineExposure.drawing(frameId, length: duration)},
  );
}

/// A row of a drawing [kind] made from nothing: a covering kind born over
/// its cut in the one cel [coveringFrameId] names, an animation row with its
/// default cels — and either wearing its kind's label (F-76,
/// [LayerMark.bornOfKind]).
///
/// ONE birth for the layer panel's Add Layer and for the conte row a
/// picture's first stroke makes on a cut that has none.
Layer bornRowOfKind(
  LayerKind kind, {
  required LayerId layerId,
  required FrameId Function() coveringFrameId,
  required Cut cut,
}) =>
    (kind.coversWithoutGaps
            ? createCoveringLayer(
                layerId: layerId,
                frameId: coveringFrameId(),
                cut: cut,
                kind: kind,
              )
            : createDefaultAnimationLayer(layerId: layerId, cut: cut))
        .copyWith(mark: LayerMark.bornOfKind(kind));

/// The storyboard-kind shorthand for [createCoveringLayer] (its original
/// name — the storyboard row was the first covering kind).
Layer createStoryboardLayer({
  required LayerId layerId,
  required FrameId frameId,
  required Cut cut,
}) => createCoveringLayer(layerId: layerId, frameId: frameId, cut: cut);
