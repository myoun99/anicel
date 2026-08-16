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
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/native_engine_path.dart';

/// The hot cel budget scales to the MACHINE (유저 확정 2026-08-16): a
/// quarter of physical RAM clamped to [384MB, 1536MB], with the OS
/// memory-pressure signal halving it (floored, never raised) and
/// kicking a cooling pass. Unknown RAM keeps the old desktop default,
/// byte-for-byte — a machine without the engine behaves exactly as
/// every machine did before this existed.
void main() {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;

  group('deviceScaledHotCelBudget', () {
    test('unknown RAM (null / zero / negative) keeps the desktop 1536MB', () {
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: null), 1536 * mb);
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: 0), 1536 * mb);
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: -1), 1536 * mb);
    });

    test('a quarter of RAM, clamped to [384MB, 1536MB]', () {
      // A 3GB tablet: the quarter itself.
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: 3 * gb), 768 * mb);
      // A 12GB iPad: the ceiling — today's desktop number, unchanged.
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: 12 * gb), 1536 * mb);
      // 6GB sits exactly AT the ceiling.
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: 6 * gb), 1536 * mb);
      // A 1GB device: the floor holds (a 256MB quarter would thrash).
      expect(deviceScaledHotCelBudget(physicalMemoryBytes: 1 * gb), 384 * mb);
    });
  });

  group('respondToMemoryPressure', () {
    test('halves the budget; floors at 256MB; never raises', () {
      final store = BrushFrameStore();
      expect(store.hotCelByteBudget, 1536 * mb, reason: 'fixture: default');

      store.respondToMemoryPressure();
      expect(store.hotCelByteBudget, 768 * mb);

      // 500MB halves to 250MB, which is under the floor: floor wins.
      store.hotCelByteBudget = 500 * mb;
      store.respondToMemoryPressure();
      expect(store.hotCelByteBudget, 256 * mb);

      // At the floor the signal is a no-op on the number.
      store.respondToMemoryPressure();
      expect(store.hotCelByteBudget, 256 * mb);

      // A budget already BELOW the floor must not be raised by the very
      // signal that says memory is scarce.
      store.hotCelByteBudget = 300;
      store.respondToMemoryPressure();
      expect(store.hotCelByteBudget, 300);
    });

    test('kicks a cooling pass — a plain budget write alone never cools',
        () async {
      final store = BrushFrameStore();
      final k1 = BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: const CutId('c'),
        layerId: const LayerId('l'),
        frameId: const FrameId('f1'),
      );
      final k2 = BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: const CutId('c'),
        layerId: const LayerId('l'),
        frameId: const FrameId('f2'),
      );
      BitmapSurface ink(int seed) {
        final pixels = Uint8List(8 * 8 * 4);
        for (var i = 0; i < pixels.length; i += 1) {
          pixels[i] = (i * seed * 31 + seed) & 0xFF;
        }
        return BitmapSurface(
          canvasSize: const CanvasSize(width: 16, height: 16),
          tileSize: 8,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(
              coord: TileCoord(x: 0, y: 0),
              size: 8,
              pixels: pixels,
            ),
          },
        );
      }

      // Stored UNDER the default budget: both hot, nothing scheduled.
      store.storeBakedSurface(k1, ink(3));
      store.storeBakedSurface(k2, ink(5));

      // A direct field write is exactly what pressure does internally —
      // and it must NOT cool by itself, or the kick assertion below
      // would be vacuous.
      store.hotCelByteBudget = 300;
      await store.drainCooling();
      expect(
        store.isCelCold(k1),
        isFalse,
        reason: 'presence anchor: the budget write alone scheduled nothing',
      );

      store.respondToMemoryPressure();
      await store.drainCooling();
      expect(
        store.isCelCold(k1),
        isTrue,
        reason: 'the pressure response is what kicked the cooling pass',
      );
      expect(
        store.isCelCold(k2),
        isFalse,
        reason: 'the most recently used cel never cools',
      );
      expect(
        store.hotCelByteBudget,
        300,
        reason: 'the floor never raises a deliberately tight budget',
      );
    });
  });

  test('the session seeds the store from the device and forwards pressure '
      'to it', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);

    // No engine in a host test run → unknown RAM → the desktop default.
    // (On CI the engine may load; then the seed is machine-scaled but
    // still within the clamp.)
    expect(session.brushFrameStore.hotCelByteBudget, inInclusiveRange(384 * mb, 1536 * mb));

    session.brushFrameStore.hotCelByteBudget = 1024 * mb;
    session.respondToMemoryPressure();
    expect(
      session.brushFrameStore.hotCelByteBudget,
      512 * mb,
      reason: 'the session forwards the OS signal to the store',
    );
  });

  test('the engine answers physical RAM with a sane number (needs the '
      'standalone binary)', () {
    final path = nativeEngineLibraryPathOrNull();
    if (path == null) {
      if (nativeEngineRequired) {
        fail(nativeEngineMissingSkipReason);
      }
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    debugQaEngineLibraryPathOverride = path;
    QaNativeEngine.debugResetForTests();
    addTearDown(() {
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugResetForTests();
    });

    final engine = QaNativeEngine.instance;
    expect(
      engine,
      isNotNull,
      reason: 'a null engine here means the standalone binary does not '
          'speak ABI v$kQaEngineAbiVersion — rebuild it',
    );
    final bytes = engine!.physicalMemoryBytes;
    expect(bytes, isNotNull, reason: 'a real machine knows its RAM');
    expect(
      bytes,
      inInclusiveRange(1 * gb, 100 * 1024 * gb),
      reason: 'sanity bounds: more than 1GB, less than 100TB',
    );
  });
}
