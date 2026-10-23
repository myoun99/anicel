import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

import '../helpers/fill_pieces.dart';
import '../helpers/native_engine_path.dart';

/// 🚨THE FILL READS WHAT IS DRAWN, NOT THE PAPER (board F-416 — 유저
/// 2026-10-20: 「캔버스 용지색이 흰색이고, 레이어에 그린것도 흰색일때 … 캔버스
/// 전체를 칠해버리는거같음. 그림부분만 칠해야하는데」 · 「캔버스밖 채우기 체크하더라도
/// 그 경우 칠해지도록 … 페이스트보드쪽도 칠해지도록」).
///
/// White ink is the colour the fill used to read for a white paper — the
/// default one, which the fill read when it was given none: a fill on it
/// took the whole canvas,
/// and with the fill past the canvas on, the white shape running onto the
/// pasteboard flooded to the wall and was refused as open. Every case runs
/// on the Dart reference and on the native engine, whose compose and flood
/// are their own code.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  const canvasSize = CanvasSize(width: 8, height: 8);

  /// [white] pixels inked opaque white, on 4-pixel tiles anywhere in the
  /// world — off the canvas too.
  BitmapSurface whiteInk(Set<(int, int)> white) {
    final tiles = <TileCoord, Uint8List>{};
    for (final (x, y) in white) {
      final coord = TileCoord.fromPixel(pixelX: x, pixelY: y, tileSize: 4);
      final buffer = tiles.putIfAbsent(coord, () => Uint8List(4 * 4 * 4));
      final index = ((y % 4) * 4 + (x % 4)) * 4;
      buffer.fillRange(index, index + 4, 255);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {
        for (final entry in tiles.entries)
          entry.key: BitmapTile(size: 4, pixels: entry.value),
      },
    );
  }

  Set<(int, int)> block(int left, int top, int right, int bottom) => {
    for (var y = top; y <= bottom; y += 1)
      for (var x = left; x <= right; x += 1) (x, y),
  };

  final cut = Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [
      Layer(
        id: const LayerId('ink'),
        name: 'Ink',
        frames: [
          Frame(
            id: const FrameId('ink-frame'),
            duration: 1,
            strokes: const [],
          ),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('ink-frame'), length: 1),
        },
      ),
    ],
    duration: 24,
    canvasSize: canvasSize,
  );

  List<BrushDab> fill(
    BitmapSurface surface, {
    required CanvasPoint at,
    bool pastTheCanvas = false,
    void Function()? onOpenRegion,
  }) => buildFillDabs(
    cut: cut,
    frameIndex: 0,
    surfaceResolver: (_, _) => surface,
    point: at,
    color: 0xFF3366CC,
    options: FloodFillOptions(
      expandPx: 0,
      antiAlias: false,
      extendBeyondCanvas: pastTheCanvas,
    ),
    onOpenRegion: onOpenRegion,
  );

  for (final engine in ['dart', 'native']) {
    group('($engine)', () {
      setUp(() {
        QaNativeEngine.debugResetForTests();
        if (engine == 'dart') {
          QaNativeEngine.debugForceDartFallback = true;
        } else {
          debugQaEngineLibraryPathOverride = dllPath;
        }
      });
      final skip = engine == 'native' && dllPath == null
          ? nativeEngineMissingSkipReason
          : null;

      test('a fill on white ink takes the ink, not the canvas around it', () {
        final dabs = fill(
          whiteInk(block(2, 2, 5, 5)),
          at: CanvasPoint(x: 3, y: 3),
        );

        expect(piecesBox(dabs), (left: 2, top: 2, width: 4, height: 4));
        expect(
          piecesAlphaAt(dabs, 0, 0),
          0,
          reason: '↩️the canvas around the ink read as the same white',
        );
      }, skip: skip);

      test('a fill beside white ink takes the empty canvas, and leaves the '
          'ink', () {
        final dabs = fill(
          whiteInk(block(2, 2, 5, 5)),
          at: CanvasPoint(x: 0, y: 0),
        );

        expect(piecesAlphaAt(dabs, 0, 0), 255);
        expect(piecesAlphaAt(dabs, 7, 7), 255);
        expect(
          piecesAlphaAt(dabs, 3, 3),
          0,
          reason: 'the white ink is drawn: it walls the fill',
        );
      }, skip: skip);

      test('🚨with the fill past the canvas on, a white shape running onto the '
          'pasteboard fills whole — its pasteboard part too', () {
        var refused = false;
        final dabs = fill(
          whiteInk(block(-3, 2, 3, 5)),
          at: CanvasPoint(x: 1, y: 3),
          pastTheCanvas: true,
          onOpenRegion: () => refused = true,
        );

        expect(
          refused,
          isFalse,
          reason: '↩️the white shape flooded into the paper to the wall',
        );
        expect(piecesBox(dabs), (left: -3, top: 2, width: 7, height: 4));
        expect(piecesAlphaAt(dabs, -3, 2), 255, reason: 'on the pasteboard');
      }, skip: skip);

      test('without it, the same shape fills inside the canvas only', () {
        final dabs = fill(
          whiteInk(block(-3, 2, 3, 5)),
          at: CanvasPoint(x: 1, y: 3),
        );

        expect(piecesBox(dabs), (left: 0, top: 2, width: 4, height: 4));
      }, skip: skip);
    });
  }
}
