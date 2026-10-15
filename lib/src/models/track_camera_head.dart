import 'cut.dart';
import 'layer.dart';
import 'layer_id.dart';

/// THE HEAD A TRACK'S CAMERAS WEAR (I-73 ④). 🗣️유저 2026-10-09: 「그럼
/// 카메라행도 글로벌? 콘티행처럼 머리 같도록 할까하는데」 →
/// I-73-camera-row-Q1: 「좋은데 색라벨은 컷마다 있는게 좋을거같은데」 — the
/// storyboard draws the cameras of a track's cuts as one row, whose name and
/// fx switch are one; the colour label stays each cut's own.
///
/// [camera] wearing [head]'s head: its name and its fx switch — and its
/// twirl, the row's since F-360, which the storyboard's one camera row
/// opens on every camera (I-73 ④ⓔ) — and its eye and its opacity, the
/// camera view's switch and its dim since F-363 (「카메라 불투명도는 레이어랑
/// 통일」). ⛔Not its label, and nothing it holds — its keys are its own
/// cut's.
///
/// A camera is BORN wearing it when its cut joins a track
/// (`projectWithCutInserted`); after that the name, the switch, the twirl,
/// the eye and the opacity are written to every camera of the track at once
/// (`cameraHeadTargets`).
Layer cameraWearingHeadOf(Layer head, Layer camera) => camera.copyWith(
  name: head.name,
  transformEnabled: head.transformEnabled,
  lanesExpanded: head.lanesExpanded,
  isVisible: head.isVisible,
  opacity: head.opacity,
);

/// The camera whose head a cut joining [cuts] wears: the first of their
/// cameras. Null while none of them has one.
Layer? cameraHeadOf(Iterable<Cut> cuts) {
  for (final cut in cuts) {
    if (cut.layers.cameraLayer case final camera?) {
      return camera;
    }
  }
  return null;
}

/// The cameras of [cuts] — the rows that wear a track's one camera head,
/// and so twirl as one (the twirl's command writes every one of them,
/// `headMirrorTargets`) and show one graph (`RailView.followHeads`).
List<LayerId> cameraHeadFamilyOf(Iterable<Cut> cuts) => [
  for (final cut in cuts)
    if (cut.layers.cameraLayer case final camera?) camera.id,
];

/// [cut] as it joins [cuts]' track: its camera wearing their head
/// ([cameraWearingHeadOf]). [cut] itself when either has no camera.
Cut cutJoiningWithCameraHead(Cut cut, Iterable<Cut> cuts) {
  final head = cameraHeadOf(cuts);
  final camera = cut.layers.cameraLayer;
  if (head == null || camera == null) {
    return cut;
  }
  final worn = cameraWearingHeadOf(head, camera);
  return cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        if (identical(layer, camera)) worn else layer,
    ],
  );
}
