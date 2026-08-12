import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/cut_piece_tip.dart';

/// A piece whose left half is opaque and whose right half is transparent,
/// with the OPAQUE half painted white — the case Photoshop's brightness
/// rule gets exactly backwards on a transparent-background cel.
CutPiece _brightOnTransparent({int width = 8, int height = 8}) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final index = (y * width + x) * 4;
      if (x < width ~/ 2) {
        rgba[index] = 255;
        rgba[index + 1] = 255;
        rgba[index + 2] = 255;
        rgba[index + 3] = 255;
      }
    }
  }
  return CutPiece(
    image: BrushStampImage(
      id: 'p',
      width: width,
      height: height,
      rgba: rgba,
    ),
    originLeft: 0,
    originTop: 0,
  );
}

void main() {
  test('a bright drawing on transparency survives registration', () {
    // Photoshop's white-is-transparent rule would erase this piece; on a
    // transparent-background cel the silhouette is what was drawn.
    final mask = cutPieceToTipMask(_brightOnTransparent(), id: 't');
    var covered = 0;
    for (final value in mask.alpha) {
      if (value > 0) {
        covered += 1;
      }
    }
    expect(covered, greaterThan(0));
    // Half the piece was opaque, so about half the mask carries coverage.
    expect(covered, 8 * 8 ~/ 2);
  });

  test('coverage is the alpha channel, verbatim', () {
    final mask = cutPieceToTipMask(_brightOnTransparent(), id: 't');
    expect(mask.size, 8);
    // Row 0: four opaque, four empty.
    expect(mask.alpha.sublist(0, 4), everyElement(255));
    expect(mask.alpha.sublist(4, 8), everyElement(0));
  });

  test('the mask is square, with the content centred', () {
    final mask = cutPieceToTipMask(
      _brightOnTransparent(width: 8, height: 4),
      id: 't',
    );
    expect(mask.size, 8);
    expect(mask.alpha.length, 8 * 8);
    // Padded rows top and bottom are empty; the middle carries the piece.
    expect(mask.alpha.sublist(0, 8), everyElement(0));
    expect(mask.alpha.sublist(2 * 8, 2 * 8 + 4), everyElement(255));
  });

  test('an oversized piece is reduced to the library limit', () {
    final side = maxBrushTipMaskSide * 2;
    final mask = cutPieceToTipMask(
      _brightOnTransparent(width: side, height: side),
      id: 't',
    );
    expect(mask.size, maxBrushTipMaskSide);
    // The reduction averages rather than point-samples, so the opaque half
    // is still there rather than sampled away.
    expect(mask.alpha.take(maxBrushTipMaskSide ~/ 2), everyElement(255));
  });

  test('the pose is honoured — registering takes what you are looking at', () {
    // Unlike paste-at-origin, which is always the untouched original.
    final flipped = cutPieceToTipMask(
      _brightOnTransparent().copyWith(flipHorizontal: true),
      id: 't',
    );
    // The opaque half moved to the right.
    expect(flipped.alpha.sublist(0, 4), everyElement(0));
    expect(flipped.alpha.sublist(4, 8), everyElement(255));
  });

  test('a fully transparent piece yields an empty mask, not a crash', () {
    final blank = CutPiece(
      image: BrushStampImage(
        id: 'p',
        width: 4,
        height: 4,
        rgba: Uint8List(4 * 4 * 4),
      ),
      originLeft: 0,
      originTop: 0,
    );
    final mask = cutPieceToTipMask(blank, id: 't');
    expect(mask.size, 4);
    expect(mask.alpha, everyElement(0));
  });
}
