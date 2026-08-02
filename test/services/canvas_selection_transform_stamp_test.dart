import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';

/// R19 pixel selection: Ctrl+T resamples the LIFTED STAMP through the
/// affine. Pins the exactness tiers: identity = same object, pure
/// translation = same bytes at a shifted center (the byte-preservation
/// contract — the user's retouch workflow), axis-aligned 90° rotation =
/// exact pixel permutation, scaling = alpha-weighted bilinear.
void main() {
  /// A 2×2 stamp with four distinct opaque colors:
  ///   R G
  ///   B W
  BrushDab stampDab() {
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, /**/ 0, 255, 0, 255, //
      0, 0, 255, 255, /**/ 255, 255, 255, 255, //
    ]);
    return BrushDab(
      center: CanvasPoint(x: 10, y: 10),
      color: 0xFFFFFFFF,
      size: 2,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'stamp', width: 2, height: 2, rgba: rgba),
    );
  }

  List<int> pixelOf(BrushStampImage stamp, int x, int y) {
    final offset = (y * stamp.width + x) * 4;
    return stamp.rgba.sublist(offset, offset + 4);
  }

  test('identity returns the dab untouched', () {
    final dab = stampDab();
    final out = transformStampDab(
      dab,
      SelectionAffine(pivot: CanvasPoint(x: 10, y: 10)),
    );
    expect(identical(out, dab), isTrue);
  });

  test('pure translation shifts the center and keeps the stamp BYTES '
      '(the retouch byte-preservation contract)', () {
    final dab = stampDab();
    final out = transformStampDab(
      dab,
      SelectionAffine(pivot: CanvasPoint(x: 10, y: 10), tx: 7, ty: -3),
    );
    expect(out.center, CanvasPoint(x: 17, y: 7));
    expect(
      identical(out.stamp!.rgba, dab.stamp!.rgba),
      isTrue,
      reason: 'no resample on a pure move — the same byte buffer travels',
    );
  });

  test('a 90° rotation about the stamp center is an exact pixel '
      'permutation (pixel centers land on pixel centers)', () {
    final dab = stampDab();
    final out = transformStampDab(
      dab,
      SelectionAffine(pivot: CanvasPoint(x: 10, y: 10), rotationDegrees: 90),
    );
    final stamp = out.stamp!;
    expect(stamp.width, 2);
    expect(stamp.height, 2);
    // 90° clockwise-in-screen-space (y down): R G / B W  →  B R / W G.
    expect(pixelOf(stamp, 0, 0), [0, 0, 255, 255]);
    expect(pixelOf(stamp, 1, 0), [255, 0, 0, 255]);
    expect(pixelOf(stamp, 0, 1), [255, 255, 255, 255]);
    expect(pixelOf(stamp, 1, 1), [0, 255, 0, 255]);
    expect(out.center, CanvasPoint(x: 10, y: 10));
  });

  test('a 2× scale doubles the footprint: interior pixels are fully '
      'opaque source color, edges feather, nothing changes hue', () {
    final rgba = Uint8List.fromList([
      for (var i = 0; i < 4; i += 1) ...[255, 0, 0, 255],
    ]);
    final dab = BrushDab(
      center: CanvasPoint(x: 10, y: 10),
      color: 0xFFFFFFFF,
      size: 2,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'red', width: 2, height: 2, rgba: rgba),
    );
    final out = transformStampDab(
      dab,
      SelectionAffine(pivot: CanvasPoint(x: 10, y: 10), sx: 2, sy: 2),
    );
    final stamp = out.stamp!;
    expect(stamp.width, 4);
    expect(stamp.height, 4);
    expect(out.center, CanvasPoint(x: 10, y: 10));
    for (var y = 0; y < 4; y += 1) {
      for (var x = 0; x < 4; x += 1) {
        final pixel = pixelOf(stamp, x, y);
        if (pixel[3] == 0) {
          continue;
        }
        expect(pixel.sublist(0, 3), [255, 0, 0], reason: 'pure red ($x,$y)');
        final interior = x >= 1 && x <= 2 && y >= 1 && y <= 2;
        if (interior) {
          expect(pixel[3], 255, reason: 'interior full alpha ($x,$y)');
        }
      }
    }
  });

  test('scaling a mid-tone edge NEVER leaves the source range — the tent '
      'is convex, so the pale halo beside a dark line cannot exist', () {
    // A 4×1 opaque stamp: two gray-100 texels then two gray-200 texels.
    //
    // This test used to assert the OPPOSITE. It pinned the Catmull-Rom's
    // negative lobes ("the negative lobes must ring across the edge"),
    // which is precisely the defect that made free transform unusable on
    // line art: a cubic beside a dark edge emits a pixel brighter than
    // anything it read. Measured against TVPaint 12 at 80% reduction, its
    // Medium leaves 6,990 such halo pixels and its VeryHigh 16,366. A
    // convex kernel leaves zero by construction, and that is now the
    // contract.
    final rgba = Uint8List.fromList([
      for (var i = 0; i < 2; i += 1) ...[100, 100, 100, 255],
      for (var i = 0; i < 2; i += 1) ...[200, 200, 200, 255],
    ]);
    final dab = BrushDab(
      center: CanvasPoint(x: 10, y: 10),
      color: 0xFFFFFFFF,
      size: 4,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'edge-tone', width: 4, height: 1, rgba: rgba),
    );
    final out = transformStampDab(
      dab,
      SelectionAffine(pivot: CanvasPoint(x: 10, y: 10), sx: 2, sy: 1),
    );
    final stamp = out.stamp!;
    var visible = 0;
    var between = 0;
    for (var x = 0; x < stamp.width; x += 1) {
      final pixel = pixelOf(stamp, x, 0);
      if (pixel[3] == 0) {
        continue;
      }
      visible += 1;
      expect(
        pixel[0],
        inInclusiveRange(100, 200),
        reason: 'x=$x left the footprint\'s own min..max',
      );
      if (pixel[0] > 100 && pixel[0] < 200) {
        between += 1;
      }
    }
    // Without these two the assertion above passes vacuously on an
    // all-transparent or all-flat result — which is exactly what a broken
    // fold would produce.
    expect(visible, greaterThan(0), reason: 'the warp landed nothing');
    expect(
      between,
      greaterThan(0),
      reason: 'AA ON must interpolate across the edge, not step',
    );
  });

  group('perspective quad (R20-D2)', () {
    test('solveHomography reproduces all four correspondences exactly', () {
      final from = [
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 4, y: 0),
        CanvasPoint(x: 4, y: 4),
        CanvasPoint(x: 0, y: 4),
      ];
      final to = [
        CanvasPoint(x: 1, y: 0.5),
        CanvasPoint(x: 3, y: 0),
        CanvasPoint(x: 5, y: 4),
        CanvasPoint(x: -1, y: 5),
      ];
      final h = solveHomography(from, to)!;
      for (var i = 0; i < 4; i += 1) {
        final w = h[6] * from[i].x + h[7] * from[i].y + h[8];
        expect(
          (h[0] * from[i].x + h[1] * from[i].y + h[2]) / w,
          closeTo(to[i].x, 1e-9),
        );
        expect(
          (h[3] * from[i].x + h[4] * from[i].y + h[5]) / w,
          closeTo(to[i].y, 1e-9),
        );
      }
      expect(
        solveHomography(from, [
          CanvasPoint(x: 0, y: 0),
          CanvasPoint(x: 1, y: 1),
          CanvasPoint(x: 2, y: 2),
          CanvasPoint(x: 3, y: 3),
        ]),
        isNull,
        reason: 'a collinear target quad is degenerate — refuse',
      );
    });

    test('corners at the source rect leave the dab untouched', () {
      final dab = stampDab(); // 2×2 centered at (10,10) → rect (9,9)-(11,11).
      final out = transformStampDabQuad(dab, [
        CanvasPoint(x: 9, y: 9),
        CanvasPoint(x: 11, y: 9),
        CanvasPoint(x: 11, y: 11),
        CanvasPoint(x: 9, y: 11),
      ]);
      expect(identical(out, dab), isTrue);
    });

    test('a pinched top edge renders a trapezoid: the top of the output '
        'is narrower than the bottom (the perspective signature)', () {
      final rgba = Uint8List.fromList([
        for (var i = 0; i < 36; i += 1) ...[255, 0, 0, 255],
      ]);
      final dab = BrushDab(
        center: CanvasPoint(x: 10, y: 10),
        color: 0xFFFFFFFF,
        size: 6,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(id: 'quad', width: 6, height: 6, rgba: rgba),
      );
      // Source rect (7,7)-(13,13); pinch the TOP corners inward by 2px.
      final out = transformStampDabQuad(dab, [
        CanvasPoint(x: 9, y: 7),
        CanvasPoint(x: 11, y: 7),
        CanvasPoint(x: 13, y: 13),
        CanvasPoint(x: 7, y: 13),
      ]);
      final stamp = out.stamp!;
      int opaqueWidthOfRow(int y) {
        var count = 0;
        for (var x = 0; x < stamp.width; x += 1) {
          if (stamp.rgba[(y * stamp.width + x) * 4 + 3] > 128) {
            count += 1;
          }
        }
        return count;
      }

      expect(
        opaqueWidthOfRow(0),
        lessThan(opaqueWidthOfRow(stamp.height - 1)),
        reason: 'perspective, not affine: parallel edges converge',
      );
      // The warp stays pure red everywhere it lands.
      for (var i = 0; i < stamp.rgba.length; i += 4) {
        if (stamp.rgba[i + 3] > 0) {
          expect(stamp.rgba[i], 255);
          expect(stamp.rgba[i + 2], 0);
        }
      }
    });
  });

  group('mesh warp (R20-D3)', () {
    BrushDab redDab(int size) {
      final rgba = Uint8List.fromList([
        for (var i = 0; i < size * size; i += 1) ...[255, 0, 0, 255],
      ]);
      return BrushDab(
        center: CanvasPoint(x: 10, y: 10),
        color: 0xFFFFFFFF,
        size: size.toDouble(),
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(
          id: 'mesh',
          width: size,
          height: size,
          rgba: rgba,
        ),
      );
    }

    List<CanvasPoint> baseGrid(BrushDab dab, int columns, int rows) {
      final stamp = dab.stamp!;
      final left = dab.center.x - stamp.width / 2;
      final top = dab.center.y - stamp.height / 2;
      return [
        for (var row = 0; row <= rows; row += 1)
          for (var column = 0; column <= columns; column += 1)
            CanvasPoint(
              x: left + column * stamp.width / columns,
              y: top + row * stamp.height / rows,
            ),
      ];
    }

    test('an untouched grid is identity', () {
      final dab = redDab(8);
      final out = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: baseGrid(dab, 2, 2),
      );
      expect(identical(out, dab), isTrue);
    });

    test('pulling ONE interior control point bulges the warp locally: '
        'coverage grows on the pulled side only, hue stays pure', () {
      final dab = redDab(8); // rect (6,6)-(14,14), 2×2 grid center = (10,10).
      final points = baseGrid(dab, 2, 2);
      // Pull the CENTER control point 3px right.
      points[4] = CanvasPoint(x: 13, y: 10);
      final out = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: points,
      );
      expect(identical(out, dab), isFalse);
      final stamp = out.stamp!;
      // Every visible pixel stays pure red (alpha-weighted bicubic).
      var visible = 0;
      for (var i = 0; i < stamp.rgba.length; i += 4) {
        if (stamp.rgba[i + 3] > 0) {
          visible += 1;
          expect(stamp.rgba[i], 255);
          expect(stamp.rgba[i + 2], 0);
        }
      }
      // The outer boundary is unchanged (corners stayed), so the footprint
      // stays the 8×8 rect — the warp is interior-only.
      expect(visible, greaterThan(0));
      expect((stamp.width, stamp.height), (8, 8));
    });

    test('warping the whole right edge outward widens the footprint', () {
      final dab = redDab(8);
      final points = baseGrid(dab, 2, 2);
      for (final index in [2, 5, 8]) {
        points[index] = CanvasPoint(x: points[index].x + 4, y: points[index].y);
      }
      final out = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: points,
      );
      expect(out.stamp!.width, 12, reason: 'right edge moved +4');
      // Rightmost column carries visible pixels (the warp reached it).
      var rightHit = false;
      final stamp = out.stamp!;
      for (var y = 0; y < stamp.height; y += 1) {
        if (stamp.rgba[(y * stamp.width + stamp.width - 1) * 4 + 3] > 100) {
          rightHit = true;
        }
      }
      expect(rightHit, isTrue);
    });
  });

  group('Pick — the AA-OFF mode (P3a)', () {
    /// A two-value cel in miniature: white ground, black ink, one 1px
    /// diagonal and one 1px vertical. Deliberately 24×24 and not 2×2 —
    /// every assertion in this file skips fully transparent pixels, so a
    /// fixture small enough for its border ring to swallow the content
    /// passes while reading nothing.
    BrushDab lineArtDab({int size = 24}) {
      final rgba = Uint8List(size * size * 4);
      final words = Uint32List.view(rgba.buffer);
      const white = 0xffffffff;
      const ink = 0xff101010;
      for (var i = 0; i < words.length; i += 1) {
        words[i] = white;
      }
      for (var i = 2; i < size - 2; i += 1) {
        words[i * size + i] = ink;
        words[i * size + size ~/ 2] = ink;
      }
      return BrushDab(
        center: CanvasPoint(x: size / 2, y: size / 2),
        color: 0xFFFFFFFF,
        size: size.toDouble(),
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(
          id: 'line-art',
          width: size,
          height: size,
          rgba: rgba,
        ),
      );
    }

    Set<int> wordsOf(BrushStampImage stamp) =>
        Uint32List.view(stamp.rgba.buffer).toSet();

    test('introduces no colour that was not already in the source — '
        'the whole point of the mode', () {
      final dab = lineArtDab();
      final source = wordsOf(dab.stamp!);
      final out = transformStampDab(
        dab,
        SelectionAffine(
          pivot: CanvasPoint(x: 12, y: 12),
          rotationDegrees: 23,
          sx: 1.4,
          sy: 0.9,
        ),
        mode: ResampleMode.pick,
      );
      final produced = wordsOf(out.stamp!);
      expect(
        produced.difference(source).difference({0x00000000}),
        isEmpty,
        reason:
            'every word must be one the source already held, or the '
            'transparent outside token',
      );
      // And the alpha stays two-valued: no soft edge sneaks in.
      for (var i = 3; i < out.stamp!.rgba.length; i += 4) {
        expect(out.stamp!.rgba[i], anyOf(0, 255));
      }
    });

    test('the same rotation under AA ON DOES make in-between colours — '
        'so the switch is not decorative', () {
      final dab = lineArtDab();
      final source = wordsOf(dab.stamp!);
      final out = transformStampDab(
        dab,
        SelectionAffine(pivot: CanvasPoint(x: 12, y: 12), rotationDegrees: 23),
        mode: ResampleMode.blend,
      );
      expect(
        wordsOf(out.stamp!).difference(source).difference({0x00000000}),
        isNotEmpty,
      );
    });

    test('a quarter turn keeps every ink pixel — the case the kernel\'s '
        'own 1.5 radius floor would have halved', () {
      final dab = lineArtDab();
      const ink = 0xff101010;
      final before = Uint32List.view(
        dab.stamp!.rgba.buffer,
      ).where((word) => word == ink).length;
      for (final degrees in <double>[90, 180, 270]) {
        final out = transformStampDab(
          dab,
          SelectionAffine(
            pivot: CanvasPoint(x: 12, y: 12),
            rotationDegrees: degrees,
          ),
          mode: ResampleMode.pick,
        );
        final after = Uint32List.view(
          out.stamp!.rgba.buffer,
        ).where((word) => word == ink).length;
        expect(after, before, reason: '$degrees° lost ink');
        expect(out.stamp!.width, 24);
        expect(out.stamp!.height, 24);
      }
    });

    test('integer magnification is exact block replication', () {
      final dab = lineArtDab(size: 8);
      final out = transformStampDab(
        dab,
        SelectionAffine(pivot: CanvasPoint(x: 4, y: 4), sx: 2, sy: 2),
        mode: ResampleMode.pick,
      );
      final stamp = out.stamp!;
      expect((stamp.width, stamp.height), (16, 16));
      final sourceWords = Uint32List.view(dab.stamp!.rgba.buffer);
      final outWords = Uint32List.view(stamp.rgba.buffer);
      for (var y = 0; y < 16; y += 1) {
        for (var x = 0; x < 16; x += 1) {
          expect(
            outWords[y * 16 + x],
            sourceWords[(y ~/ 2) * 8 + (x ~/ 2)],
            reason: 'at ($x,$y)',
          );
        }
      }
    });

    test('an opaque block stays opaque to its own edge — the outside '
        'token must not win a border vote', () {
      final rgba = Uint8List(16 * 16 * 4);
      final words = Uint32List.view(rgba.buffer);
      for (var i = 0; i < words.length; i += 1) {
        words[i] = 0xff2040c0;
      }
      final dab = BrushDab(
        center: CanvasPoint(x: 8, y: 8),
        color: 0xFFFFFFFF,
        size: 16,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(id: 'block', width: 16, height: 16, rgba: rgba),
      );
      final out = transformStampDab(
        dab,
        SelectionAffine(pivot: CanvasPoint(x: 8, y: 8), rotationDegrees: 90),
        mode: ResampleMode.pick,
      );
      final outWords = Uint32List.view(out.stamp!.rgba.buffer);
      expect(
        outWords.where((word) => word == 0).length,
        0,
        reason: 'a quarter turn of a solid block punched holes in it',
      );
    });

    test('the quad and the mesh honour the mode too — an AA-off switch '
        'that only works in one of three warp modes is worse than none', () {
      final dab = lineArtDab();
      final source = wordsOf(dab.stamp!);
      final quad = transformStampDabQuad(dab, [
        CanvasPoint(x: 2, y: 1),
        CanvasPoint(x: 21, y: 0),
        CanvasPoint(x: 24, y: 25),
        CanvasPoint(x: -1, y: 23),
      ], mode: ResampleMode.pick);
      expect(
        wordsOf(quad.stamp!).difference(source).difference({0x00000000}),
        isEmpty,
      );

      final points = <CanvasPoint>[
        for (var row = 0; row <= 2; row += 1)
          for (var column = 0; column <= 2; column += 1)
            CanvasPoint(x: column * 12.0, y: row * 12.0),
      ];
      points[4] = CanvasPoint(x: 15, y: 13); // pull the centre
      final mesh = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: points,
        mode: ResampleMode.pick,
      );
      expect(
        wordsOf(mesh.stamp!).difference(source).difference({0x00000000}),
        isEmpty,
      );
    });

    test('a whole-quad and a whole-mesh drag are pure translations — '
        'they must not resample at all', () {
      final dab = lineArtDab();
      final quad = transformStampDabQuad(dab, [
        CanvasPoint(x: 3.5, y: -1.5),
        CanvasPoint(x: 27.5, y: -1.5),
        CanvasPoint(x: 27.5, y: 22.5),
        CanvasPoint(x: 3.5, y: 22.5),
      ], mode: ResampleMode.pick);
      expect(identical(quad.stamp!.rgba, dab.stamp!.rgba), isTrue);
      expect(quad.center, CanvasPoint(x: 15.5, y: 10.5));

      final points = <CanvasPoint>[
        for (var row = 0; row <= 2; row += 1)
          for (var column = 0; column <= 2; column += 1)
            CanvasPoint(x: column * 12.0 + 3.5, y: row * 12.0 - 1.5),
      ];
      final mesh = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: points,
        mode: ResampleMode.pick,
      );
      expect(identical(mesh.stamp!.rgba, dab.stamp!.rgba), isTrue);
      expect(mesh.center, CanvasPoint(x: 15.5, y: 10.5));
    });

    test('a mesh fold-over still resolves first-hit-wins', () {
      // Drag one control point across its neighbour so two triangles
      // claim the same destination pixels. The EARLIER triangle owns
      // them — that is what makes the warp deterministic, and it is the
      // property a whole-output kernel call would have destroyed.
      final dab = lineArtDab(size: 12);
      final points = <CanvasPoint>[
        for (var row = 0; row <= 2; row += 1)
          for (var column = 0; column <= 2; column += 1)
            CanvasPoint(x: column * 6.0, y: row * 6.0),
      ];
      points[4] = CanvasPoint(x: -4, y: 6); // the centre, pulled past the left
      final folded = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: points,
        mode: ResampleMode.pick,
      );
      // Deterministic across runs and identical on a rerun: the ONLY
      // thing that decides an overlap is visit order.
      final again = transformStampDabMesh(
        dab,
        columns: 2,
        rows: 2,
        points: points,
        mode: ResampleMode.pick,
      );
      expect(folded.stamp!.rgba, again.stamp!.rgba);
      expect(
        wordsOf(
          folded.stamp!,
        ).difference(wordsOf(dab.stamp!)).difference({0x00000000}),
        isEmpty,
      );
    });
  });

  test('transparent texels never bleed color into opaque neighbours '
      '(alpha-weighted sampling)', () {
    // A 2×1 stamp: opaque WHITE next to fully transparent BLACK.
    final rgba = Uint8List.fromList([
      255, 255, 255, 255, /**/ 0, 0, 0, 0, //
    ]);
    final dab = BrushDab(
      center: CanvasPoint(x: 10, y: 10),
      color: 0xFFFFFFFF,
      size: 2,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(id: 'edge', width: 2, height: 1, rgba: rgba),
    );
    final out = transformStampDab(
      dab,
      SelectionAffine(pivot: CanvasPoint(x: 10, y: 10), sx: 2, sy: 2),
    );
    final stamp = out.stamp!;
    for (var y = 0; y < stamp.height; y += 1) {
      for (var x = 0; x < stamp.width; x += 1) {
        final pixel = pixelOf(stamp, x, y);
        if (pixel[3] == 0) {
          continue;
        }
        expect(
          pixel.sublist(0, 3),
          [255, 255, 255],
          reason:
              'every visible pixel stays pure white — the transparent '
              'black texel contributes no color at ($x,$y)',
        );
      }
    }
  });
}
