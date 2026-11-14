import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';

/// Can a transform preview resample only the pixels that are ON SCREEN?
///
/// A whole-picture transform is 8.66 MP at 125% and a viewport is under
/// one, so the answer decides whether the tool can be fast without giving
/// up any resolution — which is the one thing 유저 08-13 ruled out ("치명적이야
/// 그림툴에서는").
///
/// It can, where a window KEEPS the whole output's destination grid — the
/// whole's map asked for fewer of its pixels, never a map of its own (the
/// engine's `Window`):
///
///     resample(rect(0,0,W,H))[ox..ox+w, oy..oy+h]  ==  window(ox,oy,w,h)
///
/// ↩️A sweep once found 241 of 400 clipped resamples differing from the
/// whole: it clipped by recomputing the output rect, which moves the grid.
/// These pin it where the dab around the bytes is made, for each warp a
/// float takes.
void main() {
  /// Line art: thin strokes on transparent, the content the tool is for
  /// and the one Pick's flat-support probe behaves differently on.
  Uint8List lineArt(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final onStroke = x % 23 < 2 || y % 19 < 2 || x == y || x + y == width;
        if (onStroke) {
          final offset = (y * width + x) * 4;
          rgba[offset] = (x * 7) & 0xFF;
          rgba[offset + 1] = (y * 5) & 0xFF;
          rgba[offset + 2] = 0x20;
          rgba[offset + 3] = 255;
        }
      }
    }
    return rgba;
  }

  test('a windowed dab is the window of the whole dab — bytes AND where it '
      'sits', () {
    // The bytes, and the DAB around them. A window drawn at the whole
    // rect's centre would be off by half the difference in size — visible,
    // and invisible to a test that only compares pixels.
    const width = 200;
    const height = 160;
    final dab = BrushDab(
      center: CanvasPoint(x: width / 2, y: height / 2),
      color: 0xFF000000,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'window',
        width: width,
        height: height,
        rgba: lineArt(width, height),
      ),
    );
    final affine = SelectionAffine(
      pivot: CanvasPoint(x: width / 2, y: height / 2),
      sx: 1.4,
      sy: 1.4,
      rotationDegrees: 21,
    );

    // A visible rect that cuts the result down on every side.
    final full = transformStampDab(dab, affine);
    final whole = full.stamp!;
    final fullLeft = full.center.x - whole.width / 2;
    final fullTop = full.center.y - whole.height / 2;
    final visible = (
      left: fullLeft + 37,
      top: fullTop + 23,
      right: fullLeft + whole.width - 41,
      bottom: fullTop + whole.height - 29,
    );
    final windowed = transformStampDab(dab, affine, visible: visible);
    final windowStamp = windowed.stamp!;

    expect(
      windowStamp.width < whole.width && windowStamp.height < whole.height,
      isTrue,
      reason: 'the window really is smaller, or this test proves nothing',
    );

    // Where it sits: the window's top-left in canvas space must be the
    // whole rect's top-left plus the offset asked for.
    final windowLeft = windowed.center.x - windowStamp.width / 2;
    final windowTop = windowed.center.y - windowStamp.height / 2;
    final offsetX = (windowLeft - fullLeft).round();
    final offsetY = (windowTop - fullTop).round();
    expect(offsetX, 37);
    expect(offsetY, 23);

    // And the bytes are that window of the whole, exactly.
    var mismatched = 0;
    for (var row = 0; row < windowStamp.height; row += 1) {
      final wholeBase = ((offsetY + row) * whole.width + offsetX) * 4;
      final windowBase = row * windowStamp.width * 4;
      for (var byte = 0; byte < windowStamp.width * 4; byte += 1) {
        if (whole.rgba[wholeBase + byte] !=
            windowStamp.rgba[windowBase + byte]) {
          mismatched += 1;
        }
      }
    }
    expect(mismatched, 0);
  });

  test('퍼스 and 메쉬 clip too, and their windows are the whole warp\'s '
      'windows — the mesh moved a per-TRIANGLE origin at first, which is '
      'the one regrouping ABI 26 exists to prevent', () {
    const width = 180;
    const height = 140;
    final dab = BrushDab(
      center: CanvasPoint(x: width / 2, y: height / 2),
      color: 0xFF000000,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'warp',
        width: width,
        height: height,
        rgba: lineArt(width, height),
      ),
    );
    final base = <CanvasPoint>[
      CanvasPoint(x: 0, y: 0),
      CanvasPoint(x: width.toDouble(), y: 0),
      CanvasPoint(x: width.toDouble(), y: height.toDouble()),
      CanvasPoint(x: 0, y: height.toDouble()),
    ];

    void compareWindowed(String label, BrushDab whole, BrushDab windowed) {
      final full = whole.stamp!;
      final part = windowed.stamp!;
      expect(
        part.width < full.width || part.height < full.height,
        isTrue,
        reason: '$label: the window must be smaller or this proves nothing',
      );
      final offsetX =
          ((windowed.center.x - part.width / 2) -
                  (whole.center.x - full.width / 2))
              .round();
      final offsetY =
          ((windowed.center.y - part.height / 2) -
                  (whole.center.y - full.height / 2))
              .round();
      var mismatched = 0;
      for (var row = 0; row < part.height; row += 1) {
        final fullBase = ((offsetY + row) * full.width + offsetX) * 4;
        final partBase = row * part.width * 4;
        for (var byte = 0; byte < part.width * 4; byte += 1) {
          if (full.rgba[fullBase + byte] != part.rgba[partBase + byte]) {
            mismatched += 1;
          }
        }
      }
      expect(mismatched, 0, reason: '$label: the window is not the window');
    }

    // 퍼스: a real quad, not a rectangle.
    final quad = <CanvasPoint>[
      CanvasPoint(x: 14, y: 8),
      CanvasPoint(x: width + 30.0, y: 22),
      CanvasPoint(x: width - 6.0, y: height + 25.0),
      CanvasPoint(x: 2, y: height - 11.0),
    ];
    final quadWhole = transformStampDabQuad(dab, quad);
    final quadFull = quadWhole.stamp!;
    final quadLeft = quadWhole.center.x - quadFull.width / 2;
    final quadTop = quadWhole.center.y - quadFull.height / 2;
    compareWindowed(
      'quad',
      quadWhole,
      transformStampDabQuad(
        dab,
        quad,
        visible: (
          left: quadLeft + 25,
          top: quadTop + 18,
          right: quadLeft + quadFull.width - 30,
          bottom: quadTop + quadFull.height - 20,
        ),
      ),
    );

    // 메쉬: a 3×3 grid with one interior point pulled aside.
    const columns = 3;
    const rows = 3;
    final points = <CanvasPoint>[
      for (var row = 0; row <= rows; row += 1)
        for (var column = 0; column <= columns; column += 1)
          CanvasPoint(
            x: base[0].x + column * width / columns,
            y: base[0].y + row * height / rows,
          ),
    ];
    points[1 * (columns + 1) + 1] = CanvasPoint(
      x: points[1 * (columns + 1) + 1].x - 17,
      y: points[1 * (columns + 1) + 1].y + 23,
    );
    final meshWhole = transformStampDabMesh(
      dab,
      columns: columns,
      rows: rows,
      points: points,
    );
    final meshFull = meshWhole.stamp!;
    final meshLeft = meshWhole.center.x - meshFull.width / 2;
    final meshTop = meshWhole.center.y - meshFull.height / 2;
    // The mesh's buffer is its window, like the other two warps' — nothing
    // is built past what was asked for. ↩️It kept the WHOLE rect and filled
    // only the visible part until 2026-10-06, when a grid carried on past
    // its box (a range's other cels) could reach far past the wall.
    final meshClipped = transformStampDabMesh(
      dab,
      columns: columns,
      rows: rows,
      points: points,
      visible: (
        left: meshLeft + 20,
        top: meshTop + 16,
        right: meshLeft + meshFull.width - 24,
        bottom: meshTop + meshFull.height - 18,
      ),
    );
    final meshPart = meshClipped.stamp!;
    expect(
      (meshPart.width, meshPart.height),
      (meshFull.width - 44, meshFull.height - 34),
      reason: 'mesh: the window is what was asked for, no more',
    );
    expect(
      (
        meshClipped.center.x - meshPart.width / 2,
        meshClipped.center.y - meshPart.height / 2,
      ),
      (meshLeft + 20, meshTop + 16),
      reason: 'mesh: and it stands where that part of the whole stands',
    );
    var meshMismatched = 0;
    for (var row = 0; row < meshPart.height; row += 1) {
      for (var column = 0; column < meshPart.width; column += 1) {
        final whole = ((row + 16) * meshFull.width + (column + 20)) * 4;
        final part = (row * meshPart.width + column) * 4;
        for (var byte = 0; byte < 4; byte += 1) {
          if (meshFull.rgba[whole + byte] != meshPart.rgba[part + byte]) {
            meshMismatched += 1;
          }
        }
      }
    }
    expect(
      meshMismatched,
      0,
      reason:
          'mesh: the visible region of a clipped mesh must be byte-for-byte '
          'the same region of the unclipped one',
    );
  });

  test('asking for a visible rect that covers everything returns the WHOLE '
      'dab, so small selections keep the commit-reuse path', () {
    const width = 64;
    const height = 48;
    final dab = BrushDab(
      center: CanvasPoint(x: width / 2, y: height / 2),
      color: 0xFF000000,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'small',
        width: width,
        height: height,
        rgba: lineArt(width, height),
      ),
    );
    final affine = SelectionAffine(
      pivot: CanvasPoint(x: width / 2, y: height / 2),
      sx: 1.1,
      sy: 1.1,
      rotationDegrees: 9,
    );
    final whole = transformStampDab(dab, affine).stamp!;
    final generous = transformStampDab(
      dab,
      affine,
      visible: (left: -9999, top: -9999, right: 9999, bottom: 9999),
    ).stamp!;
    expect(generous.width, whole.width);
    expect(generous.height, whole.height);
  });
}
