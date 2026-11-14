import 'dart:ui' as ui;

import '../canvas/raster_picture.dart';

/// What [paint] draws in canvas space, rastered over [window] — whole
/// canvas pixels — one texel a canvas pixel: the PLATE of a set of letters.
///
/// 🚨★★★ONE RASTER FOR EVERY LETTER A PICTURE HOLDS (card
/// cel-number-letters-drawn-as-vectors, 유저 2026-11-07 「지금까지가 셀번호가
/// 벡터엿던게 버그야. 통일하지 않았던거니까」 · engine-canvas-letters-Q1
/// 「캔버스 화소로 보인다(그림 · 셀 글자와 같은 법)」): a text on a cel bakes its
/// plate from here ([bakeCelTextPlate]), and a cel number and an SE name
/// tag are rastered as plates by the engine's letters
/// (`EngineLetters`), each posed as a row's picture is. ↩️The cel numbers
/// and the tags were drawn as vectors at whatever resolution the draw
/// landed on — a file's, the screen's — so a file or a zoomed view showed
/// the picture's pixels and letters on it that had none. ↩️Their plates
/// were drawn from here and kept (`keptLetterPlate`) while a walk drew in
/// Flutter, until the last — the tags — moved onto the engine
/// (the-flutter-fx-chain-is-a-second-chain).
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

/// How many bytes of plates the engine's letters keep — bytes, not plates:
/// a raster costs the same whatever its size (🔬1.6–2.0 ms on Windows,
/// 2026-09-25), so a bound by count that a frame's numbered rows outgrew
/// would raster them all again at every frame laid. A cel number's plate
/// is some tens of kilobytes; this holds the letters of every row of a
/// long cut's every drawing.
const int letterPlateBytesKept = 32 << 20;
