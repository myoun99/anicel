import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨2026-09-11: the census added each cel store's COLD bytes to the
/// drawings and sheet-ink rows. But a cooled cel is written to the run's
/// 이사대기 room and only a file ref stays in memory — disk counted as
/// RAM, so 「ours」 swelled and the engine's share shrank by as much.
void main() {
  // The census reads the image cache, and that needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvasSize = CanvasSize(width: 16, height: 16);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  AnicelCelBlob parkedBlob(BrushFrameKey k) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 31 + 7) & 0xFF;
    }
    final surface = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
    return AnicelCelBlob.encode(AnicelCelEntry.fromSurface(k, surface));
  }

  test('🚨cels parked on disk are not RAM — the drawings and sheet-ink '
      'rows count what is resident', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final caches = session.renderCaches;
    caches.brushFrameStore.restoreBaked({key('a'): parkedBlob(key('a'))});
    caches.conteInkPageStore.restoreBaked({key('b'): parkedBlob(key('b'))});
    // Fixture: both stores really hold parked bytes.
    expect(caches.brushFrameStore.coldBakedBytes, greaterThan(0));
    expect(caches.conteInkPageStore.coldBakedBytes, greaterThan(0));

    final rows = {
      for (final item in collectMemoryCensus(session).items)
        item.id: item.bytes,
    };
    expect(
      rows['drawings'],
      caches.brushFrameStore.hotBakedBytes +
          caches.brushFrameStore.reclaimableViewBytes,
      reason: 'a parked cel is a file on disk, not memory',
    );
    expect(
      rows['sheetInk'],
      caches.conteInkRowStore.hotBakedBytes +
          caches.conteInkPageStore.hotBakedBytes +
          caches.envelopeInkStore.hotBakedBytes +
          caches.timesheetInkStripStore.hotBakedBytes +
          caches.timesheetInkPageStore.hotBakedBytes,
      reason: 'the same for the sheet-ink stores',
    );
  });
}
