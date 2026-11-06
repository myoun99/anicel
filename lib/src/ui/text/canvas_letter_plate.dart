import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/lru.dart';
import '../canvas/raster_picture.dart';

/// What [paint] draws in canvas space, rastered over [window] — whole
/// canvas pixels — one texel a canvas pixel: the PLATE of a set of letters.
///
/// 🚨★★★ONE RASTER FOR EVERY LETTER A PICTURE HOLDS (card
/// cel-number-letters-drawn-as-vectors, 유저 2026-11-07 「지금까지가 셀번호가
/// 벡터엿던게 버그야. 통일하지 않았던거니까」 · engine-canvas-letters-Q1
/// 「캔버스 화소로 보인다(그림 · 셀 글자와 같은 법)」): a text on a cel bakes its
/// plate from here ([bakeCelTextPlate]), and a cel number and an SE name
/// tag draw theirs from here ([keptLetterPlate]), each posed as a row's
/// picture is. ↩️The cel numbers and the tags were drawn as vectors at
/// whatever resolution the draw landed on — a file's, the screen's — so a
/// file or a zoomed view showed the picture's pixels and letters on it
/// that had none.
///
/// A DEFERRED raster ([rasterPicture]): it is rastered by the pass that
/// draws it.
ui.Image letterPlateOver(
  ui.Rect window,
  void Function(ui.Canvas canvas) paint,
) {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder)..translate(-window.left, -window.top));
  return rasterPicture(recorder, window.width.round(), window.height.round());
}

/// [key]'s plate — [paint] over [window] ([letterPlateOver]) — made the
/// first time it is asked for and kept: what says the same letters at the
/// same place draws the plate already made.
///
/// 🔬Drawn afresh, a tag would be rastered again at every paint that shows
/// it — each frame of a run, a pan, a zoom — and a cel number at every
/// step of a drag that composes its row.
///
/// 🚨THE PLATE IS THE KEEPER'S: draw it at once and never dispose it — the
/// next plate asked for may let go of it.
ui.Image keptLetterPlate(
  Object key,
  ui.Rect window,
  void Function(ui.Canvas canvas) paint,
) => _plates.resolve(key, () => letterPlateOver(window, paint));

/// How many bytes of plates [keptLetterPlate] keeps — bytes, not plates: a
/// raster costs the same whatever its size (🔬1.6–2.0 ms on Windows,
/// 2026-09-25), so a bound by count that a frame's numbered rows outgrew
/// would raster them all again at every frame laid. A cel number's plate
/// is some tens of kilobytes; this holds the letters of every row of a
/// long cut's every drawing.
@visibleForTesting
const int letterPlateBytesKept = 32 << 20;

/// What the plates kept weigh — the memory census's `textImages`, beside the
/// words the screen bakes.
int get letterPlateBytes => _plates.held;

final Lru<Object, ui.Image> _plates = Lru(
  limit: () => letterPlateBytesKept,
  costOf: (plate) => plate.width * plate.height * 4,
  letGo: (_, plate) => plate.dispose(),
);
