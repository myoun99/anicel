import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_display_cache.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/photoshop/psd_image.dart';

/// Two more files nothing named (2026-09-05): the display cache that is
/// never the source of truth, and the PSD bridge that makes a .psd behave
/// like a .png everywhere.
void main() {
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapSurface surface() => BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 8,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile.blank(
        coord: TileCoord(x: 0, y: 0),
        size: 8,
      ),
    },
  );

  group('the display cache', () {
    test('a fresh cache is valid, and knows which revision it was built '
        'from', () {
      final cache = BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: surface(),
        sourceRevision: 7,
      );

      expect(cache.isValid, isTrue);
      expect(cache.sourceRevision, 7);
    });

    test('🚨DIRTY is not valid — the cache is rebuildable and never the '
        'source of truth, so a stale one must say so rather than be shown', () {
      final cache = BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: surface(),
        sourceRevision: 7,
        dirty: true,
      );

      expect(cache.isValid, isFalse);
    });

    test('copyWith keeps what it is not given', () {
      final first = surface();
      final cache = BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: first,
        sourceRevision: 7,
      );

      final next = cache.copyWith(sourceRevision: 8);

      expect(next.frameKey, key);
      expect(identical(next.previewSurface, first), isTrue);
      expect(next.sourceRevision, 8);
      expect(next.isValid, isTrue);
    });

    test('copyWith can turn a cache dirty and clean again', () {
      final cache = BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: surface(),
        sourceRevision: 7,
      );

      expect(cache.copyWith(dirty: true).isValid, isFalse);
      expect(
        cache.copyWith(dirty: true).copyWith(dirty: false).isValid,
        isTrue,
      );
    });

    test('the dirty tiles default to none rather than null — a caller '
        'walking them must not have to ask first', () {
      final cache = BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: surface(),
        sourceRevision: 0,
      );

      expect(cache.dirtyTiles.isEmpty, isTrue);
    });

    test('the dirty tiles carry through copyWith', () {
      final cache = BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: surface(),
        sourceRevision: 0,
        dirtyTiles: DirtyTileSet([TileCoord(x: 2, y: 3)]),
      );

      expect(cache.copyWith(sourceRevision: 1).dirtyTiles.length, 1);
    });
  });

  group('the PSD bridge', () {
    test('⛔bytes that are not a PSD are refused before any decode', () {
      expect(
        () => decodePsdCompositeImage(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      '🚨a PSD saved WITHOUT a composite says so — Photoshop only writes '
      'one when "Maximize Compatibility" is on, and naming that is worth '
      'more than "could not open" because the user can go and re-save',
      () async {
        // A minimal valid header: 8BPS v1, 3 channels, 1x1, 8-bit, RGB,
        // then empty colour-mode / resource / layer sections and an EMPTY
        // image-data section, which is what a composite-less file looks
        // like here.
        final header = <int>[
          0x38, 0x42, 0x50, 0x53, // 8BPS
          0x00, 0x01, // version 1
          0, 0, 0, 0, 0, 0, // reserved
          0x00, 0x03, // channels
          0, 0, 0, 1, // height
          0, 0, 0, 1, // width
          0x00, 0x08, // depth
          0x00, 0x03, // RGB
          0, 0, 0, 0, // colour mode data length
          0, 0, 0, 0, // image resources length
          0, 0, 0, 0, // layer and mask length
        ];

        await expectLater(
          decodePsdCompositeImage(Uint8List.fromList(header)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('composite'),
            ),
          ),
        );
      },
    );
  });
}
