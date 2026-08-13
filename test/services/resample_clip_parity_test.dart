import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/resample/selection_resample.dart';

import '../helpers/native_engine_path.dart';

/// Can a transform preview resample only the pixels that are ON SCREEN?
///
/// `canvas_selection.dart` carries a warning that it cannot: "a sweep
/// found 241 of 400 transforms where a clipped resample differs from the
/// same region of an unclipped one". A whole-picture transform is 8.66 MP
/// at 125% and a viewport is under one, so the answer decides whether the
/// tool can be fast without giving up any resolution — which is the one
/// thing 유저 08-13 ruled out ("치명적이야 그림툴에서는").
///
/// The hypothesis this checks is that the earlier sweep clipped by
/// recomputing the OUTPUT RECT, which moves `outLeft`/`outTop` — and the
/// destination pixel grid is anchored to those, so every sample lands
/// somewhere else and of course the bytes differ. Clipping while KEEPING
/// the original grid asks a different question:
///
///     resample(rect(0,0,W,H))[ox..ox+w, oy..oy+h]
///       ==  resample(rect(ox,oy,w,h))            ?
///
/// where the second call is handed `outLeft + ox` / `outTop + oy`, so both
/// calls place destination pixel (ox+i, oy+j) at the same source position.
///
/// Prints the tally, and FAILS if any window differs — a clip that is
/// exact 399 times out of 400 is not exact.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

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

  /// Every clipped buffer the sweep produced, so the two kernels can be
  /// held against each OTHER and not only against themselves.
  final clippedByKernel = <bool, List<Uint8List>>{};

  void runSweep({required bool forceDart}) {
    final produced = <Uint8List>[];
    clippedByKernel[forceDart] = produced;
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = forceDart;

    const srcWidth = 240;
    const srcHeight = 180;
    final src = lineArt(srcWidth, srcHeight);
    const srcLeft = 0.0;
    const srcTop = 0.0;

    var compared = 0;
    var differing = 0;
    final differences = <String>[];

    for (final mode in ResampleMode.values) {
      for (final scale in const <double>[0.6, 0.85, 1.0, 1.3, 2.1]) {
        for (final degrees in const <double>[0, 7, 33, 90, 150, 217, 300]) {
          final affine = SelectionAffine(
            pivot: CanvasPoint(x: srcWidth / 2, y: srcHeight / 2),
            sx: scale,
            sy: scale,
            rotationDegrees: degrees,
            tx: 3.25,
            ty: -1.75,
          );
          final corners = [
            for (final corner in <CanvasPoint>[
              CanvasPoint(x: srcLeft, y: srcTop),
              CanvasPoint(x: srcLeft + srcWidth, y: srcTop),
              CanvasPoint(x: srcLeft + srcWidth, y: srcTop + srcHeight),
              CanvasPoint(x: srcLeft, y: srcTop + srcHeight),
            ])
              affine.apply(corner),
          ];
          final out = selectionWarpOutputRect(corners);

          // The whole output, the way a commit computes it.
          final full = Uint8List(out.width * out.height * 4);
          resampleSelectionInto(
            src: src,
            srcWidth: srcWidth,
            srcHeight: srcHeight,
            dst: full,
            dstWidth: out.width,
            dstHeight: out.height,
            transform: selectionAffineResampleTransform(
              affine: affine,
              srcLeft: srcLeft,
              srcTop: srcTop,
              outLeft: out.left,
              outTop: out.top,
            ),
            mode: mode,
          );

          // A window of it, computed on its own — the same destination
          // pixels, addressed by shifting the ORIGIN rather than by
          // recomputing the rect.
          final ox = out.width ~/ 3;
          final oy = out.height ~/ 4;
          final w = math.max(1, out.width ~/ 3);
          final h = math.max(1, out.height ~/ 3);
          final clipped = Uint8List(w * h * 4);
          resampleSelectionInto(
            src: src,
            srcWidth: srcWidth,
            srcHeight: srcHeight,
            dst: clipped,
            dstWidth: w,
            dstHeight: h,
            // The FULL rect's matrix, with the window's position handed
            // over separately. Folding `ox` into `outLeft` instead is the
            // arithmetically-equal-but-not-bitwise-equal version, and it
            // is what made eight of these differ before ABI 26.
            transform: selectionAffineResampleTransform(
              affine: affine,
              srcLeft: srcLeft,
              srcTop: srcTop,
              outLeft: out.left,
              outTop: out.top,
            ),
            mode: mode,
            clipX: ox,
            clipY: oy,
          );

          produced.add(clipped);
          compared += 1;
          var mismatched = 0;
          for (var row = 0; row < h; row += 1) {
            final fullBase = ((oy + row) * out.width + ox) * 4;
            final clipBase = row * w * 4;
            for (var byte = 0; byte < w * 4; byte += 1) {
              if (full[fullBase + byte] != clipped[clipBase + byte]) {
                mismatched += 1;
              }
            }
          }
          if (mismatched != 0) {
            differing += 1;
            if (differences.length < 6) {
              differences.add(
                '${mode.name} ×$scale @$degrees°: $mismatched of '
                '${w * h * 4} bytes',
              );
            }
          }
        }
      }
    }

    debugPrint(
      '[clip parity ${forceDart ? "dart" : "native"}] $compared transforms '
      'compared, $differing differ'
      '${differences.isEmpty ? "" : "  →  ${differences.join("; ")}"}',
    );
    expect(compared, greaterThan(0), reason: 'the sweep ran');
    expect(
      differing,
      0,
      reason:
          'a window computed on its own must equal that window of the '
          'whole, byte for byte — a preview that clips to the viewport is '
          'only honest if it is the same picture the commit lands. '
          '${differences.join("; ")}',
    );
  }

  test('a windowed dab is the window of the whole dab — bytes AND where it '
      'sits', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

    // The bytes are the parity sweep's business; this is about the DAB
    // around them. A window drawn at the whole rect's centre would be off
    // by half the difference in size — visible, and invisible to a test
    // that only compares pixels.
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
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

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
    // The mesh keeps the WHOLE buffer and fills only the visible part, so
    // its "window" is the same size — compare the visible region instead.
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
    var meshMismatched = 0;
    for (var row = 16; row < meshFull.height - 18; row += 1) {
      for (var column = 20; column < meshFull.width - 24; column += 1) {
        final offset = (row * meshFull.width + column) * 4;
        for (var byte = 0; byte < 4; byte += 1) {
          if (meshFull.rgba[offset + byte] != meshPart.rgba[offset + byte]) {
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
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

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

  test('a clipped resample that keeps the destination GRID: native vs the '
      'Dart reference', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    // Both, because WHICH ONE differs is the whole diagnosis. The maths
    // says a window is a window: the transform is parameterised by
    // outLeft/outTop, so the same absolute destination pixel samples the
    // same source position either way. If the Dart reference agrees with
    // itself and only the native kernel does not, the cause is in the
    // kernel's row banding rather than in the idea.
    runSweep(forceDart: false);
    runSweep(forceDart: true);

    // And against each other. The two agreeing with THEMSELVES leaves the
    // case where both are wrong the same way — which is exactly what
    // happened when the supersampler was missed, since the C mirrors the
    // Dart line for line.
    final native = clippedByKernel[false]!;
    final dart = clippedByKernel[true]!;
    expect(native, hasLength(dart.length));
    var crossMismatched = 0;
    for (var i = 0; i < native.length; i += 1) {
      expect(native[i].length, dart[i].length);
      for (var byte = 0; byte < native[i].length; byte += 1) {
        if (native[i][byte] != dart[i][byte]) {
          crossMismatched += 1;
        }
      }
    }
    expect(
      crossMismatched,
      0,
      reason: 'the native kernel and the Dart reference must clip alike',
    );
  });
}
