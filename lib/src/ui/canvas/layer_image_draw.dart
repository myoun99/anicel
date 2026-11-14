/// How a POSED PICTURE the app draws itself reaches a canvas — the one
/// place that decides it (P2a): a sheet's photo.
///
/// ↩️It was every route's LAYER image — four routes (playback's cache, the
/// camera render, the editing stack and export) each hand-rolled the same
/// steps and disagreed on the sampling, so zooming in made the layer you
/// were drawing on the only jagged one on screen (T21) — with its chain run
/// in Flutter (`steppedForChain`), in pieces past the side this engine
/// holds, from its ink alone where that drew the same bytes (유저 2026-09-23
/// 「1/4해상도같은 결과바뀌는건 절대로 허용안하고 … 보이는 결과 특히」), and at
/// `none` where it landed texel for texel (유저 2026-09-24 「통일해서」, D14),
/// until every row stood on the engine and the Flutter chain went
/// (the-flutter-fx-chain-is-a-second-chain): the engine lays a row's tiles
/// texel for texel and runs its chain itself.
///
/// The same `applyLayerPlacement` also carries the cut pose, but that
/// applies to an already-composed frame in output space and must not
/// quietly inherit a picture's sampling.
library;

import 'dart:ui' as ui;

import '../../models/layer_blend_mode.dart';
import '../../services/composite_effect_paint.dart' show alphaOnly;
import '../../services/layer_pose_paint.dart';

/// [image], standing for [worldRect] of the canvas, posed by [placement],
/// faded to [opacity] and laid in [blendMode].
///
/// A4 — [filterQuality] is REQUIRED, deliberately. A default here is how
/// the sampling drift this file exists to end comes back: a new route
/// "just draws" and inherits a quality nobody chose. Requiring the
/// argument blocks the CLASS, not the instance — every route answers the
/// sampling question at its call site, in writing, and the source
/// contract test (`layer_image_draw_contract_test.dart`) freezes the
/// raw-draw census so new image draws have to come through here.
void drawPosedLayerImage(
  ui.Canvas canvas, {
  required ui.Image image,
  required ui.Rect worldRect,
  required LayerPlacement? placement,
  required double opacity,
  required LayerBlendMode blendMode,
  required ui.FilterQuality filterQuality,
}) {
  final paint = ui.Paint()
    ..color = alphaOnly(opacity)
    // R26 #30: the layer blend applies at composite time, so every route
    // shows the picture playback composes.
    ..blendMode = blendMode.paintBlendMode
    ..filterQuality = filterQuality;
  void draw() => canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    worldRect,
    paint,
  );
  // A null placement draws with no save/restore at all: an identity
  // picture should not pay for a matrix.
  if (placement == null) {
    draw();
    return;
  }
  canvas.save();
  try {
    applyLayerPlacement(canvas, placement);
    draw();
  } finally {
    canvas.restore();
  }
}
