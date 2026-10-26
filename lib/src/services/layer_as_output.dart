import '../models/export_spec.dart' show ExportLayerFx;
import '../models/layer.dart';
import '../models/layer_effect.dart';
import '../models/layer_kind.dart';
import '../models/transform_track.dart';

/// [layer] as an output written with [fx] keeps it — the ONE answer every
/// tab of the export reads: the rows of a video and of a still, and the
/// chains a delivery cel is laid through (I-65).
///
/// * [ExportLayerFx.on] — every fx: the transform and each link of the
///   chain.
/// * [ExportLayerFx.basic] — the basic links ([EffectKind.isBasic]) and the
///   reference fx; the transform and every other link off.
/// * [ExportLayerFx.off] — none, the reference fx too: a file's picture
///   stands where its pixels are laid ([MediaReference.laid]).
///
/// 🗣️I-65-Q5 (유저 2026-10-25): 「출력은 머리를 안 본다」 — 「셀도 똑같이 머리
/// 비지블 꺼도 출력리스트에 뜸으로 통일. 셀출력은 그게기본」: the switches the
/// timeline holds (the transform's, each link's) hide an fx on the screen,
/// and what an output keeps is the window's choice alone. ↩️An output was
/// the screen's, down to each row's switches.
/// 🗣️I-65-Q6 (유저 2026-10-25): 「참조 fx 도 끈다(정말 날 것)」 — 「동작이
/// 바껴서 기본fx로 분류되고 그거마저 끌수있게 하는걸 노리는것임」. ↩️I-68-Q1
/// kept it whatever the output's switch said.
///
/// 🗣️I-65-Q11 (유저 2026-10-25): 「켬 · 기본만 켬이면 화면 스위치대로, 끔이면
/// 빠짐 — 카메라 행도 같이」, on Q10's memo 「출력할때 fx on 되있으면, 보는
/// 화면에서 on 되있는거를 fx로서 넣어서 출력함. 보는화면에서 off 되있으면
/// 안넣음」: the camera row's switch bypasses the cut's camera work on the
/// screen, and an output keeps the work as the screen shows it under 켬 and
/// 기본만 켬, and none of it under 끔 — the V row's chain too (the renderer's
/// `_trackFxLaid`). ↩️I-65-Q8 (「출력은 이 머리도 안 본다」) kept both whatever
/// the switches and the window said; before it, both switches reached the
/// output.
///
/// The window's choice expressed as DATA: the plan renders exactly the rows
/// it is given, so no route can forget it.
Layer layerAsOutput(Layer layer, ExportLayerFx fx) {
  if (layer.kind == LayerKind.camera) {
    return layer.copyWith(
      transformEnabled: layer.transformEnabled && fx != ExportLayerFx.off,
    );
  }
  final reference = layer.mediaReference;
  return layer.copyWith(
    transformEnabled: fx == ExportLayerFx.on,
    effects: chainAsOutput(layer.effects, fx),
    mediaReference: fx == ExportLayerFx.off && reference != null
        ? reference.copyWith(pose: reference.laid, fx: TransformTrack.empty())
        : reference,
  );
}

/// [chain] as an output written with [fx] keeps it ([layerAsOutput]): each
/// link on or off by the window's choice, whatever its own switch says.
List<LayerEffect> chainAsOutput(List<LayerEffect> chain, ExportLayerFx fx) => [
  for (final effect in chain)
    effect.copyWith(
      enabled: switch (fx) {
        ExportLayerFx.on => true,
        ExportLayerFx.basic => effect.kind.isBasic,
        ExportLayerFx.off => false,
      },
    ),
];
