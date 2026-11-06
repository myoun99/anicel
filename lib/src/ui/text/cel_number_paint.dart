import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart' show MatrixUtils;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../models/canvas_size.dart';
import '../../models/cel_number_letters.dart';
import '../../models/text_cel_style.dart';
import '../canvas/display_resample.dart' show wholeLevelPixelsOutward;
import '../canvas/image_pieces.dart';
import 'canvas_letter_plate.dart';
import 'text_cel_render.dart';

/// A CEL NUMBER's letters (I-65) — the one implementation every walk that
/// composites a row calls ([CompositeCelNumber]), so the canvas, the camera
/// and the files cannot disagree on where the letters stand or how they
/// look.
///
/// Set as the text tool sets letters ([layoutTextCel] — the app's own faces,
/// at the tool's size and in [CelNumberLetters.color]), the middle of their
/// box on [CelNumberLetters.center] of the row's paper and scaled about it.
///
/// 🚨★★★CANVAS PIXELS, LAID AS THE ROW'S PICTURE IS (card
/// cel-number-letters-drawn-as-vectors, 유저 2026-11-07 「지금까지가 셀번호가
/// 벡터엿던게 버그야. 통일하지 않았던거니까」): the letters are a plate on the
/// row's paper ([keptLetterPlate]), which the walk draws as it draws the
/// row's picture. ↩️They were drawn as vectors under the row's placement:
/// a file showed them at its own resolution, and a row turned or scaled
/// showed them smooth over its pixels.
///
/// Null for letters that paint nothing. 🚨Draw it at once ([keptLetterPlate]).
ImagePiece? celNumberPlate(CelNumberLetters letters) {
  final window = celNumberExtent(letters);
  if (window.isEmpty) {
    return null;
  }
  final layout = _layoutOf(letters);
  final plate = keptLetterPlate((layout, letters), window, (into) {
    into.save();
    into.transform(_standOf(letters, layout).storage);
    layout.paint(into);
    into.restore();
  });
  return (image: plate, worldRect: window);
}

/// The rect of the row's paper [letters] may paint, on whole pixels — the
/// plate they are drawn from, and what a buffer that holds them must cover.
ui.Rect celNumberExtent(CelNumberLetters letters) => wholeLevelPixelsOutward(
  _onThePaper(letters, (layout) => layout.paintBounds),
  0,
);

/// The box of [letters]' ink on the row's paper, where they stand — what
/// the canvas's box frames them by (F-477), as a row's box frames its ink.
ui.Rect celNumberBox(CelNumberLetters letters) =>
    _onThePaper(letters, (layout) => layout.inkBounds);

/// [rectOf] [letters]' layout, on the row's paper where they stand.
ui.Rect _onThePaper(
  CelNumberLetters letters,
  ui.Rect Function(TextCelLayout layout) rectOf,
) {
  final layout = _layoutOf(letters);
  return MatrixUtils.transformRect(_standOf(letters, layout), rectOf(layout));
}

/// The layout [letters] are drawn and measured by ([_layoutOf]).
@visibleForTesting
TextCelLayout celNumberLayoutOf(CelNumberLetters letters) =>
    _layoutOf(letters);

/// [letters] laid out with their anchor at the origin — once for each text
/// and colour ([textCelLaidOut]): where they stand and how large is
/// [_standOf]'s, not the layout's, so the buffer's bounds
/// ([celNumberExtent]) and the letters themselves ask the one layout
/// wherever a stroke's step is.
TextCelLayout _layoutOf(CelNumberLetters letters) => textCelLaidOut(
  content: TextCelContent(
    text: letters.text,
    style: TextCelStyle(color: letters.color),
    position: ui.Offset.zero,
  ),
  // ⚠️Read only where a content stands nowhere, and this one stands at the
  // origin.
  canvas: const CanvasSize(width: 0, height: 0),
);

/// Where [layout] stands on the row's paper: its box's middle moved onto
/// [CelNumberLetters.center], scaled about it.
Matrix4 _standOf(CelNumberLetters letters, TextCelLayout layout) {
  final middle = layout.inkBounds.center;
  return Matrix4.translationValues(letters.center.x, letters.center.y, 0)
    ..scaleByDouble(letters.scale.x, letters.scale.y, 1, 1)
    ..translateByDouble(-middle.dx, -middle.dy, 0, 1);
}
