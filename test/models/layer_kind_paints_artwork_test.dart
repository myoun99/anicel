// WHICH ROWS PAINT A SURFACE OF THEIR OWN.
//
// Folder rows composite their members' buffer and never a surface of their
// own; a drawing row does. The mutation campaign (2026-09-03) turned the
// predicate's `&&` into `||` — a folder then "painted artwork" — and nothing
// noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_kind.dart';

void main() {
  test('a drawing row paints artwork', () {
    expect(layerKindPaintsArtwork(LayerKind.animation), isTrue);
  });

  test('a folder row composites its members and paints nothing itself', () {
    expect(layerKindPaintsArtwork(LayerKind.folder), isFalse);
  });

  test('every kind that paints artwork also composites', () {
    for (final kind in LayerKind.values) {
      if (layerKindPaintsArtwork(kind)) {
        expect(layerKindComposites(kind), isTrue, reason: '$kind');
        expect(layerKindGroupsLayers(kind), isFalse, reason: '$kind');
      }
    }
  });
}
